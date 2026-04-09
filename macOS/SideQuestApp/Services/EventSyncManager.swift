import Foundation
import os.log

class EventSyncManager {
    private let apiClient: APIClient
    private let eventQueue: EventQueue
    private var syncTimer: Timer?
    private let syncIntervalSeconds = 30.0
    private let logger = Logger(subsystem: "ai.sidequest.app", category: "event-sync")

    init(apiClient: APIClient, eventQueue: EventQueue) {
        self.apiClient = apiClient
        self.eventQueue = eventQueue
    }

    // MARK: - Public Interface

    func startPeriodicSync() {
        // Start Timer to call syncEvents every 30 seconds
        // Using Timer (not DispatchSourceTimer) because Timer resumes after Mac wake
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncIntervalSeconds, repeats: true) { [weak self] _ in
            self?.syncEvents()
        }
        ErrorHandler.logInfo("EventSyncManager periodic sync started (every \(syncIntervalSeconds)s)")
    }

    func stopPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        ErrorHandler.logInfo("EventSyncManager periodic sync stopped")
    }

    func syncOnTermination() {
        // Final sync attempt before app terminates
        // Fire-and-forget with 5-second timeout
        Task {
            await self.syncEventsWithTimeout(seconds: 5.0)
            ErrorHandler.logInfo("Termination sync attempt completed")
        }
    }

    // MARK: - Private Implementation

    private func syncEvents() {
        // Fire-and-forget task to avoid blocking main thread
        Task {
            await syncEventsWithTimeout(seconds: 30.0)
        }
    }

    private func syncEventsWithTimeout(seconds: TimeInterval) async {
        // Get pending events from queue
        let events = await eventQueue.getPendingEvents()

        // Early return if no events
        if events.isEmpty {
            return
        }

        // Build POST payload: array of {user_id, quest_id, tracking_id, event_type, metadata}
        let payload = events.map { event -> [String: Any] in
            var eventDict: [String: Any] = [
                "uid": event.userId,
                "qid": event.questId,
                "tid": event.trackingId,
                "event_type": event.eventType,
            ]

            // Include metadata if present
            if let metadata = event.metadata {
                eventDict["metadata"] = self.convertMetadataToJSON(metadata)
            }

            return eventDict
        }

        // POST to /events endpoint
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)

            // Create URL request
            let baseURL = await apiClient.getBaseURL()
            let eventsURL = baseURL.appendingPathComponent("events")
            var request = URLRequest(url: eventsURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = seconds

            // Add bearer token
            let bearerToken = await apiClient.getBearerToken()
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

            request.httpBody = jsonData

            // Make request
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                ErrorHandler.logNetworkError(NSError(domain: "InvalidResponse", code: -1), endpoint: "/events")
                return
            }

            // Check response status
            if (200...299).contains(httpResponse.statusCode) {
                // Success: clear the synced events
                let syncTime = Date()
                await eventQueue.clearEvents(after: syncTime)
                ErrorHandler.logInfo("Events synced successfully (\(events.count) events)")
            } else {
                // Non-2xx response: log error, leave queue intact for retry
                ErrorHandler.logNetworkError(
                    NSError(domain: "HTTPError", code: httpResponse.statusCode),
                    endpoint: "/events"
                )
            }

        } catch URLError.timedOut {
            ErrorHandler.logNetworkError(URLError(.timedOut), endpoint: "/events")
            // Queue persists; will retry on next cycle
        } catch {
            ErrorHandler.logNetworkError(error, endpoint: "/events")
            // Queue persists; will retry on next cycle
        }
    }

    private func convertMetadataToJSON(_ metadata: [String: AnyCodable]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in metadata {
            result[key] = self.anyCodableToJSON(value)
        }
        return result
    }

    private func anyCodableToJSON(_ value: AnyCodable) -> Any {
        switch value {
        case .string(let string):
            return string
        case .int(let int):
            return int
        case .double(let double):
            return double
        case .bool(let bool):
            return bool
        case .null:
            return NSNull()
        case .array(let array):
            return array.map { self.anyCodableToJSON($0) }
        case .object(let object):
            var result: [String: Any] = [:]
            for (key, val) in object {
                result[key] = self.anyCodableToJSON(val)
            }
            return result
        }
    }
}


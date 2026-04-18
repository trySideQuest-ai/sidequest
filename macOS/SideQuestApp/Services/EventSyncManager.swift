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

    deinit {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - Public Interface

    func startPeriodicSync() {
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
        // Final sync attempt — fire-and-forget with 5-second timeout
        Task {
            await self.syncEventsWithTimeout(seconds: 5.0)
        }
    }

    // MARK: - Private Implementation

    private func syncEvents() {
        Task {
            await syncEventsWithTimeout(seconds: 30.0)
        }
    }

    private func syncEventsWithTimeout(seconds: TimeInterval) async {
        let events = await eventQueue.getPendingEvents()

        if events.isEmpty {
            return
        }

        // Send events one at a time (server expects individual events, not arrays)
        var successCount = 0
        for event in events {
            let payload: [String: Any] = {
                var dict: [String: Any] = [
                    "uid": event.userId,
                    "qid": event.questId,
                    "tid": event.trackingId,
                    "event_type": event.eventType,
                ]
                if let metadata = event.metadata {
                    dict["metadata"] = convertMetadataToJSON(metadata)
                }
                return dict
            }()

            do {
                let jsonData = try JSONSerialization.data(withJSONObject: payload)

                let baseURL = await apiClient.getBaseURL()
                let eventsURL = baseURL.appendingPathComponent("events")
                var request = URLRequest(url: eventsURL)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = seconds

                let bearerToken = await apiClient.getBearerToken()
                request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

                request.httpBody = jsonData

                let (_, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode) {
                    successCount += 1
                }
            } catch {
                // Network error — stop trying, will retry next cycle
                break
            }
        }

        if successCount > 0 {
            let syncTime = Date()
            await eventQueue.clearEvents(after: syncTime)
            ErrorHandler.logInfo("Events synced successfully (\(successCount)/\(events.count) events)")
        }
    }

    private func convertMetadataToJSON(_ metadata: [String: AnyCodable]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in metadata {
            result[key] = anyCodableToJSON(value)
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
            return array.map { anyCodableToJSON($0) }
        case .object(let object):
            var result: [String: Any] = [:]
            for (key, val) in object {
                result[key] = anyCodableToJSON(val)
            }
            return result
        }
    }
}

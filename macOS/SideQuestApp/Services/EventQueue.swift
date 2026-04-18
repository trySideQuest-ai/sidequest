import Foundation
import os.log

// MARK: - AnyCodable Helper for metadata JSONB-like storage
enum AnyCodable: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([AnyCodable])
    case object([String: AnyCodable])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: AnyCodable].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodable")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let string):
            try container.encode(string)
        case .int(let int):
            try container.encode(int)
        case .double(let double):
            try container.encode(double)
        case .bool(let bool):
            try container.encode(bool)
        case .null:
            try container.encodeNil()
        case .array(let array):
            try container.encode(array)
        case .object(let object):
            try container.encode(object)
        }
    }
}

// MARK: - QuestEvent struct for individual events
struct QuestEvent: Codable, Identifiable {
    var id: String { eventId }

    let eventId: String
    let userId: String
    let questId: String
    let trackingId: String
    let eventType: String // "quest_shown", "quest_clicked", "quest_dismissed"
    let timestamp: Date
    let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case userId = "user_id"
        case questId = "quest_id"
        case trackingId = "tracking_id"
        case eventType = "event_type"
        case timestamp
        case metadata
    }
}

// MARK: - QueueState struct for persistence
struct QueueState: Codable {
    var events: [QuestEvent] = []
    var lastSyncTime: Date?
    var pendingCount: Int = 0

    enum CodingKeys: String, CodingKey {
        case events
        case lastSyncTime = "last_sync_time"
        case pendingCount = "pending_count"
    }
}

// MARK: - EventQueue actor for thread-safe event persistence
actor EventQueue {
    private let queueFilePath: URL
    private let maxQueueSize = 1000

    init(queueFileName: String = "events-queue.json") {
        // Path: ~/Library/Application Support/SideQuest/events-queue.json
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let sideQuestDir = appSupportDir.appendingPathComponent("SideQuest")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: sideQuestDir, withIntermediateDirectories: true)

        self.queueFilePath = sideQuestDir.appendingPathComponent(queueFileName)
    }

    // Add event to queue with automatic disk persistence
    func addEvent(
        userId: String,
        questId: String,
        trackingId: String,
        eventType: String,
        metadata: [String: AnyCodable]? = nil
    ) {
        var state = readQueue()

        // Create new event
        let event = QuestEvent(
            eventId: UUID().uuidString,
            userId: userId,
            questId: questId,
            trackingId: trackingId,
            eventType: eventType,
            timestamp: Date(),
            metadata: metadata
        )

        // Add to queue
        state.events.append(event)
        state.pendingCount = state.events.count

        // Prune if exceeds max size (remove oldest events first)
        if state.events.count > maxQueueSize {
            let excessCount = state.events.count - maxQueueSize
            state.events.removeFirst(excessCount)
            state.pendingCount = state.events.count

            ErrorHandler.logInfo("Event queue cap exceeded. Removed \(excessCount) oldest events.")
        }

        writeQueue(state)
    }

    // Get all pending events from queue
    func getPendingEvents() -> [QuestEvent] {
        let state = readQueue()
        return state.events
    }

    // Clear events after successful sync
    func clearEvents(after syncTime: Date? = nil) {
        var state = readQueue()

        if let syncTime = syncTime {
            // Clear events synced before this time
            state.events.removeAll { $0.timestamp <= syncTime }
        } else {
            // Clear all events
            state.events.removeAll()
        }

        state.lastSyncTime = Date()
        state.pendingCount = state.events.count

        writeQueue(state)
    }

    // Get current queue size
    func getQueueSize() -> Int {
        let state = readQueue()
        return state.pendingCount
    }

    // MARK: - Private I/O methods (copy pattern from StateManager.swift)

    private func readQueue() -> QueueState {
        guard FileManager.default.fileExists(atPath: queueFilePath.path) else {
            return QueueState()
        }

        do {
            let data = try Data(contentsOf: queueFilePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(QueueState.self, from: data)
            return state
        } catch {
            ErrorHandler.logStateError(error, operation: "read event queue")
            return QueueState()  // Reset to empty queue on corruption
        }
    }

    private func writeQueue(_ state: QueueState) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: queueFilePath, options: .atomic)
        } catch {
            ErrorHandler.logStateError(error, operation: "write event queue")
            // Continue even if write fails — queue lost, but app continues
        }
    }
}

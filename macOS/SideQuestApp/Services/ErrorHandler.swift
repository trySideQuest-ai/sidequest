import Foundation
import os.log

enum ErrorLevel {
    case info
    case warning
    case error
    case critical
}

struct ErrorHandler {
    private static let logger = Logger(subsystem: "ai.sidequest.app", category: "errors")

    static func log(_ message: String, level: ErrorLevel = .error, error: Error? = nil) {
        let logType: OSLogType
        switch level {
        case .info:
            logType = .info
        case .warning:
            logType = .debug
        case .error:
            logType = .error
        case .critical:
            logType = .fault
        }

        if let error = error {
            logger.log(level: logType, "\(message) — \(error.localizedDescription)")
        } else {
            logger.log(level: logType, "\(message)")
        }

        // IMPORTANT: Do NOT show dialog, alert, or any UI
        // Errors are logged to Console.app only, never visible to user
    }

    // Convenience methods for common error types

    static func logNetworkError(_ error: Error, endpoint: String) {
        log("Network error fetching \(endpoint)", level: .error, error: error)
    }

    static func logDecodingError(_ error: Error, type: String) {
        log("Failed to decode \(type)", level: .error, error: error)
    }

    static func logFileIOError(_ error: Error, operation: String) {
        log("File I/O error during \(operation)", level: .error, error: error)
    }

    static func logWindowError(_ error: Error, operation: String) {
        log("Window error during \(operation)", level: .error, error: error)
    }

    static func logStateError(_ error: Error, operation: String) {
        log("State persistence error during \(operation)", level: .warning, error: error)
    }

    // Diagnostic logging (not errors, just info)

    static func logInfo(_ message: String) {
        log(message, level: .info)
    }

    static func logQuestDisplay(_ questId: String) {
        log("Quest displayed: \(questId)", level: .info)
    }

    static func logQuestClick(_ questId: String) {
        log("Quest clicked: \(questId)", level: .info)
    }
}

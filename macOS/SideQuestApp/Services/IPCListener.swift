import Foundation
import Network
import os.log

class IPCListener {
    private var listener: NWListener?
    private let socketPath: String = "/tmp/sidequest.sock"
    var onTriggerReceived: ((String, String) -> Void)?

    // MARK: - Public Interface

    func startListening() throws {
        // Remove stale socket file if it exists
        ErrorHandler.logInfo("Removing stale socket at \(socketPath)")
        do {
            try FileManager.default.removeItem(atPath: socketPath)
        } catch {
            // Socket may not exist; that's fine
            ErrorHandler.logInfo("Stale socket already cleaned up")
        }

        // Create NWListener with Unix domain socket parameters
        let parameters = NWParameters.unix
        let listener = try NWListener(using: parameters)

        // Set state update handler for debugging
        listener.stateUpdateHandler = { [weak self] state in
            self?.logListenerState(state)
        }

        // Set handler for new incoming connections
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        // Start listening on Unix domain socket
        try listener.start(on: .unix(path: socketPath))

        self.listener = listener
        ErrorHandler.logInfo("IPC listener started at \(self.socketPath)")
    }

    func stopListening() {
        ErrorHandler.logInfo("Stopping IPC listener")
        listener?.cancel()
        listener = nil

        // Clean up socket file
        try? FileManager.default.removeItem(atPath: socketPath)
        ErrorHandler.logInfo("IPC socket cleaned up at \(socketPath)")
    }

    // MARK: - Private Implementation

    private func handleConnection(_ connection: NWConnection) {
        ErrorHandler.logInfo("IPC connection established")

        // Set state update handler for this connection
        connection.stateUpdateHandler = { [weak self] state in
            self?.logConnectionState(state, connection: connection)
        }

        // Set up to receive data when connection is ready
        connection.start(queue: .global())

        // Receive data
        receiveData(from: connection)
    }

    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, context, isComplete, error in
            // Handle error
            if let error = error {
                ErrorHandler.logNetworkError(error, endpoint: "/tmp/sidequest.sock")
                connection.cancel()
                return
            }

            // Process received data
            if let data = data, !data.isEmpty {
                ErrorHandler.logInfo("IPC data received: \(data.count) bytes")
                self?.processReceivedData(data)
            }

            // Close connection
            connection.cancel()
        }
    }

    private func processReceivedData(_ data: Data) {
        do {
            // Try to decode JSON: { "questId": "...", "trackingId": "..." }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: String] {
                let questId = json["questId"] ?? ""
                let trackingId = json["trackingId"] ?? ""

                // Validate both fields are non-empty
                if !questId.isEmpty && !trackingId.isEmpty {
                    ErrorHandler.logInfo("IPC trigger received: questId=\(questId), trackingId=\(trackingId)")
                    onTriggerReceived?(questId, trackingId)
                    ErrorHandler.logInfo("IPC callback invoked; quest trigger queued")
                } else {
                    ErrorHandler.logInfo("IPC trigger missing required fields")
                }
            } else {
                ErrorHandler.logInfo("IPC message is not valid JSON")
            }
        } catch {
            ErrorHandler.logInfo("IPC JSON parse failed: \(error.localizedDescription)")
        }
    }

    private func logListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            ErrorHandler.logInfo("IPC listener ready")
        case .failed(let error):
            ErrorHandler.logNetworkError(error, endpoint: socketPath)
        case .cancelled:
            ErrorHandler.logInfo("IPC listener cancelled")
        case .waiting(let error):
            ErrorHandler.logInfo("IPC listener waiting: \(error.localizedDescription)")
        @unknown default:
            ErrorHandler.logInfo("IPC listener state: unknown")
        }
    }

    private func logConnectionState(_ state: NWConnection.State, connection: NWConnection) {
        switch state {
        case .ready:
            ErrorHandler.logInfo("IPC connection state: ready")
        case .failed(let error):
            ErrorHandler.logNetworkError(error, endpoint: socketPath)
        case .cancelled:
            ErrorHandler.logInfo("IPC connection state: cancelled")
        case .waiting(let error):
            ErrorHandler.logInfo("IPC connection state: waiting - \(error.localizedDescription)")
        case .preparing:
            ErrorHandler.logInfo("IPC connection state: preparing")
        @unknown default:
            ErrorHandler.logInfo("IPC connection state: unknown")
        }
    }
}

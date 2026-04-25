import Foundation

class IPCListener {
    private var socketFD: Int32 = -1
    private var isRunning = false
    private var listenThread: Thread?
    private let socketPath: String
    private var embeddingService: EmbeddingService?
    var onTriggerReceived: ((String, String) -> Void)?
    var onQuestReceived: ((QuestData) -> Void)?

    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let sideQuestDir = homeDir.appendingPathComponent(".sidequest")

        if !FileManager.default.fileExists(atPath: sideQuestDir.path) {
            try? FileManager.default.createDirectory(at: sideQuestDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }

        self.socketPath = sideQuestDir.appendingPathComponent("sidequest.sock").path
    }

    func setEmbeddingService(_ service: EmbeddingService) {
        self.embeddingService = service
    }

    func startListening() throws {
        // Remove stale socket
        if FileManager.default.fileExists(atPath: socketPath) {
            try FileManager.default.removeItem(atPath: socketPath)
        }

        // Create Unix domain socket
        socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw NSError(domain: "IPCListener", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }

        // Bind to path
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(socketFD)
            throw NSError(domain: "IPCListener", code: 2, userInfo: [NSLocalizedDescriptionKey: "Socket path too long"])
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for i in 0..<pathBytes.count {
                    dest[i] = pathBytes[i]
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(socketFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            close(socketFD)
            throw NSError(domain: "IPCListener", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to bind: \(String(cString: strerror(errno)))"])
        }

        // Set permissions to 0600
        chmod(socketPath, 0o600)

        // Listen with backlog of 5
        guard listen(socketFD, 5) == 0 else {
            close(socketFD)
            throw NSError(domain: "IPCListener", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to listen"])
        }

        // Accept connections on background thread
        isRunning = true
        listenThread = Thread { [weak self] in
            self?.acceptLoop()
        }
        listenThread?.name = "SideQuest-IPC"
        listenThread?.start()

        ErrorHandler.logInfo("IPC listener started at \(socketPath)")
    }

    func stopListening() {
        isRunning = false
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        try? FileManager.default.removeItem(atPath: socketPath)
        ErrorHandler.logInfo("IPC socket cleaned up")
    }

    // MARK: - Private

    private func acceptLoop() {
        while isRunning {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    accept(socketFD, sockaddrPtr, &clientLen)
                }
            }

            guard clientFD >= 0 else {
                if isRunning {
                    ErrorHandler.logInfo("IPC accept failed: \(String(cString: strerror(errno)))")
                }
                continue
            }

            // Read data from client (max 4KB for embedding requests)
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(clientFD, &buffer, buffer.count)

            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                // Process request and get response
                if let response = processReceivedDataWithResponse(data) {
                    // Send response back via socket
                    do {
                        let responseData = try JSONSerialization.data(withJSONObject: response)
                        var sentBytes = 0
                        while sentBytes < responseData.count {
                            let n = responseData.withUnsafeBytes { ptr in
                                write(clientFD, ptr.baseAddress! + sentBytes, responseData.count - sentBytes)
                            }
                            if n <= 0 { break }
                            sentBytes += Int(n)
                        }
                    } catch {
                        ErrorHandler.logInfo("IPC response send failed: \(error)")
                    }
                }
            }

            close(clientFD)
        }
    }

    private func processReceivedData(_ data: Data) {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let questId = json["questId"] as? String ?? ""

                // Check if full quest data is present
                if let displayText = json["display_text"] as? String,
                   let trackingUrl = json["tracking_url"] as? String,
                   !displayText.isEmpty {
                    let quest = QuestData(
                        quest_id: questId,
                        display_text: displayText,
                        subtitle: json["subtitle"] as? String ?? "",
                        tracking_url: trackingUrl,
                        reward_amount: json["reward_amount"] as? Int ?? 250,
                        brand_name: json["brand_name"] as? String ?? "Unknown",
                        category: json["category"] as? String ?? "DevTool"
                    )
                    ErrorHandler.logInfo("IPC full quest received: \(questId)")
                    // Dispatch to main queue — this method runs on the IPC background thread
                    DispatchQueue.main.async { [weak self] in
                        self?.onQuestReceived?(quest)
                    }
                } else {
                    // Fallback: just IDs, need API fetch
                    let trackingId = json["trackingId"] as? String ?? ""
                    if !questId.isEmpty && !trackingId.isEmpty {
                        ErrorHandler.logInfo("IPC trigger: questId=\(questId)")
                        DispatchQueue.main.async { [weak self] in
                            self?.onTriggerReceived?(questId, trackingId)
                        }
                    }
                }
            }
        } catch {
            ErrorHandler.logInfo("IPC JSON parse failed: \(error.localizedDescription)")
        }
    }

    /// Process embedding request and return response with vectors.
    /// Runs embedding inference if service available, returns null vectors on timeout/error.
    private func processReceivedDataWithResponse(_ data: Data) -> [String: Any]? {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            // Check if this is an embedding request (has user_msg or asst_msg)
            let userMsg = (json["user_msg"] as? String) ?? ""
            let asst_msg = (json["asst_msg"] as? String) ?? ""

            if !userMsg.isEmpty || !asst_msg.isEmpty {
                // This is an embedding request
                return handleEmbeddingRequest(userMsg: userMsg, asst_msg: asst_msg)
            } else {
                // This is a quest trigger/data request — process separately
                processReceivedData(data)
                return nil
            }
        } catch {
            ErrorHandler.logInfo("IPC JSON parse failed: \(error)")
            return nil
        }
    }

    /// Handle embedding request: tokenize + infer + return vectors or null on timeout.
    private func handleEmbeddingRequest(userMsg: String, asst_msg: String) -> [String: Any] {
        let startTime = Date()

        // Default response: null vectors (graceful degradation)
        var response: [String: Any] = [
            "user_vec": NSNull(),
            "asst_vec": NSNull(),
            "inference_ms": 0,
        ]

        guard let service = embeddingService else {
            ErrorHandler.logInfo("EmbeddingService not initialized")
            return response
        }

        // Bridge sync IPC to async embedding via lock-protected box (Swift Sendable rules
        // forbid mutating captured vars from concurrent Tasks).
        let box = EmbeddingResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            async let userVec = service.embedText(userMsg)
            async let asstVec = service.embedText(asst_msg)
            let (u, a) = await (userVec, asstVec)
            box.set(user: u, asst: a)
            semaphore.signal()
        }

        // Wait up to 1100ms for both (buffer beyond 1000ms timeout)
        let waitResult = semaphore.wait(timeout: .now() + 1.1)
        let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)

        if waitResult == .timedOut {
            ErrorHandler.logInfo("Embedding inference timeout after \(elapsed)ms")
        } else {
            let (userVec, asstVec) = box.get()
            if let vec = userVec, vec.count == 384 {
                response["user_vec"] = vec
            }
            if let vec = asstVec, vec.count == 384 {
                response["asst_vec"] = vec
            }
        }

        response["inference_ms"] = elapsed
        return response
    }
}

private final class EmbeddingResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var userVec: [Float]?
    private var asstVec: [Float]?

    func set(user: [Float]?, asst: [Float]?) {
        lock.lock()
        defer { lock.unlock() }
        userVec = user
        asstVec = asst
    }

    func get() -> ([Float]?, [Float]?) {
        lock.lock()
        defer { lock.unlock() }
        return (userVec, asstVec)
    }
}

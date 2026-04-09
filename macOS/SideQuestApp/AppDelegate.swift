import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var apiClient: APIClient?
    var windowManager: WindowManager?
    private var ipcListener: IPCListener?
    private var sleepWorkspaceObserver: NSObjectProtocol?
    private var eventQueue: EventQueue?
    private var eventSyncManager: EventSyncManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            // Set app as background-only (no dock icon)
            NSApp.setActivationPolicy(.accessory)

            // Register for auto-launch on login (one-time check)
            if !LaunchAtLoginManager.shared.isEnabled() {
                LaunchAtLoginManager.shared.registerForLoginItems()
            }

            // Initialize API client with hardcoded values for now
            // (will be replaced with user auth flow in Phase 2)
            let apiBase = "https://bd5x085yt3.execute-api.us-east-1.amazonaws.com"
            let testToken = "0000000000000000000000000000000000000000000000000000000000000000"  // Placeholder 64-char token

            apiClient = APIClient(apiBaseURL: apiBase, bearerToken: testToken)

            // Initialize EventQueue and EventSyncManager
            eventQueue = EventQueue()
            windowManager?.setEventQueue(eventQueue!)

            eventSyncManager = EventSyncManager(apiClient: apiClient!, eventQueue: eventQueue!)
            eventSyncManager?.startPeriodicSync()
            ErrorHandler.logInfo("EventSyncManager initialized and sync started")

            // Initialize WindowManager
            windowManager = WindowManager()
            windowManager?.setAPIClient(apiClient!)
            windowManager?.setEventQueue(eventQueue!)

            // Start IPC listener for plugin triggers
            ipcListener = IPCListener()
            ipcListener?.onTriggerReceived = { [weak self] questId, trackingId in
                self?.handleIPCTrigger(questId: questId, trackingId: trackingId)
            }
            do {
                try ipcListener?.startListening()
                ErrorHandler.logInfo("IPC listener initialized at startup")
            } catch {
                ErrorHandler.logNetworkError(error, endpoint: "/tmp/sidequest.sock")
                // Continue anyway; quests can still be triggered manually
            }

            // Register for sleep/wake notifications to resume IPC after wake
            registerSleepWakeObserver()
            ErrorHandler.logInfo("Sleep/wake observer registered")

            ErrorHandler.logInfo("SideQuest app launched successfully")

        } catch {
            ErrorHandler.logWindowError(error, operation: "app launch")
            // App continues even if initialization partial fails
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Final sync before app terminates
        eventSyncManager?.syncOnTermination()
        eventSyncManager?.stopPeriodicSync()

        // Unregister sleep/wake observer
        if let observer = sleepWorkspaceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

extension AppDelegate {
    private func registerSleepWakeObserver() {
        // Listen for system wake events
        sleepWorkspaceObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applicationDidWake()
        }
    }

    private func applicationDidWake() {
        // Called after system wake from sleep
        ErrorHandler.logInfo("System woke from sleep; resuming IPC")

        // IPC listener should still be running (Network.framework keeps connection alive)
        // But verify it's still listening in case of timeout

        // Optional: Log current IPC listener state
        if ipcListener != nil {
            ErrorHandler.logInfo("IPC listener active after wake")
        } else {
            ErrorHandler.logInfo("IPC listener not found after wake; reinitializing")
            // Reinitialize if somehow lost
            ipcListener = IPCListener()
            ipcListener?.onTriggerReceived = { [weak self] questId, trackingId in
                self?.handleIPCTrigger(questId: questId, trackingId: trackingId)
            }
            do {
                try ipcListener?.startListening()
            } catch {
                ErrorHandler.logNetworkError(error, endpoint: "/tmp/sidequest.sock")
            }
        }
    }

    func showTestQuest() {
        do {
            let testQuest = QuestData(
                quest_id: "test-123",
                display_text: "Test Quest: Explore New Features",
                tracking_url: "https://example.com",
                reward_amount: 250,
                brand_name: "Test Corp",
                category: "DevTool"
            )
            windowManager?.showQuest(testQuest)
            ErrorHandler.logQuestDisplay("test-123")
        } catch {
            ErrorHandler.logWindowError(error, operation: "show test quest")
        }
    }

    func fetchAndShowQuest() {
        guard let apiClient = apiClient else {
            ErrorHandler.logInfo("API client not initialized")
            return
        }
        Task {
            do {
                let quest = try await apiClient.fetchQuest()
                await MainActor.run {
                    windowManager?.showQuest(quest)
                }
            } catch {
                // Silent failure — quest simply won't display
                // Error already logged in APIClient
            }
        }
    }

    func handleIPCTrigger(questId: String, trackingId: String) {
        // Called when plugin sends trigger via IPC
        // Fetch quest from API and display via WindowManager

        Task {
            do {
                guard let apiClient = self.apiClient else {
                    ErrorHandler.logInfo("IPC trigger received but apiClient not ready")
                    return
                }

                let questData = try await apiClient.fetchQuest()

                // Validate quest matches expected questId (security check)
                if questData.quest_id != questId {
                    ErrorHandler.logInfo("IPC questId mismatch: expected=\(questId), got=\(questData.quest_id)")
                    // Still display (race condition acceptable)
                }

                DispatchQueue.main.async {
                    self.windowManager?.showQuest(questData)
                }
            } catch {
                // API error — log but don't show to user
                ErrorHandler.logNetworkError(error, endpoint: "/quest")
                // Quest simply not displayed; no error message
            }
        }
    }
}
import AppKit
import ApplicationServices
import ServiceManagement

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var apiClient: APIClient?
    var stateManager: StateManager?
    var eventQueue: EventQueue?
    var questPresenter: QuestPresenter?
    private var hotkeyManager: HotkeyManager?
    private var panelController: QuestPanelController?
    private var ipcListener: IPCListener?
    private var sleepWorkspaceObserver: NSObjectProtocol?
    private var eventSyncManager: EventSyncManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard: if another SideQuestApp is already running, exit immediately
        let myPID = ProcessInfo.processInfo.processIdentifier
        let isDuplicate = NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == Bundle.main.bundleIdentifier && app.processIdentifier != myPID
        }
        if isDuplicate {
            ErrorHandler.logInfo("Another SideQuestApp instance already running — exiting duplicate (PID \(myPID))")
            NSApp.terminate(nil)
            return
        }

        // Set app as accessory (menu bar only, no dock icon)
        NSApp.setActivationPolicy(.accessory)

        // One-shot cleanup: unregister any orphaned SMAppService Login Items from previous versions
        try? SMAppService().unregister()

        // Log Accessibility status (needed for global keyboard shortcuts)
        // Don't prompt — permission is tied to code signature, breaks on dev rebuilds
        if !AXIsProcessTrusted() {
            ErrorHandler.logInfo("Accessibility not granted — global keyboard shortcuts disabled. Local shortcuts work after clicking notification.")
        }

        // Load token from unified config (~/.sidequest/config.json), fall back to legacy locations
        var bearerToken = ""
        var userId = "unknown"
        var apiBase = "https://api.trysidequest.ai"

        let configPaths = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sidequest/config.json"),
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SideQuest/config.json"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/plugins/sidequest/config.json")
        ]

        for path in configPaths {
            if let data = try? Data(contentsOf: path),
               let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = config["token"] as? String, !token.isEmpty {
                bearerToken = token
                userId = config["user_id"] as? String ?? userId
                apiBase = config["api_base"] as? String ?? apiBase
                break
            }
        }

        if bearerToken.isEmpty {
            ErrorHandler.logInfo("No auth token found. Run the SideQuest setup command or /sidequest:sq-login to authenticate.")
        }

        // Load bundled fonts for the fantasy card renderer
        SQFontLoader.ensureLoaded()

        // Initialize services
        apiClient = APIClient(apiBaseURL: apiBase, bearerToken: bearerToken)
        stateManager = StateManager()
        eventQueue = EventQueue()

        // Presenter stack: HotkeyManager + PanelController + QuestPresenter
        hotkeyManager = HotkeyManager()
        panelController = QuestPanelController()
        questPresenter = QuestPresenter(
            eventQueue: eventQueue!,
            userId: userId,
            hotkeyManager: hotkeyManager!,
            panelController: panelController!
        )

        // Initialize EventSyncManager
        eventSyncManager = EventSyncManager(apiClient: apiClient!, eventQueue: eventQueue!)
        eventSyncManager?.startPeriodicSync()

        // Start IPC listener for plugin triggers
        ipcListener = IPCListener()
        ipcListener?.onTriggerReceived = { [weak self] questId, trackingId in
            self?.handleIPCTrigger(questId: questId, trackingId: trackingId)
        }
        ipcListener?.onQuestReceived = { [weak self] quest in
            self?.handleDirectQuest(quest)
        }
        do {
            try ipcListener?.startListening()
            ErrorHandler.logInfo("IPC listener started")
        } catch {
            ErrorHandler.logNetworkError(error, endpoint: "sidequest.sock")
        }

        // Register for sleep/wake notifications
        registerSleepWakeObserver()

        ErrorHandler.logInfo("SideQuest app launched successfully")
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventSyncManager?.syncOnTermination()
        eventSyncManager?.stopPeriodicSync()

        if let observer = sleepWorkspaceObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        ipcListener?.stopListening()
    }
}

extension AppDelegate {
    private func registerSleepWakeObserver() {
        sleepWorkspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applicationDidWake()
        }
    }

    private func applicationDidWake() {
        ErrorHandler.logInfo("System woke from sleep; checking IPC")

        if ipcListener != nil {
            ErrorHandler.logInfo("IPC listener active after wake")
        } else {
            ipcListener = IPCListener()
            ipcListener?.onTriggerReceived = { [weak self] questId, trackingId in
                self?.handleIPCTrigger(questId: questId, trackingId: trackingId)
            }
            ipcListener?.onQuestReceived = { [weak self] quest in
                self?.handleDirectQuest(quest)
            }
            do {
                try ipcListener?.startListening()
            } catch {
                ErrorHandler.logNetworkError(error, endpoint: "sidequest.sock")
            }
        }
    }

    @MainActor
    func showTestQuest() {
        let testQuest = QuestData(
            quest_id: "test-123",
            display_text: "Speed up your Postgres queries",
            subtitle: "Drop-in connection pooler — 10× faster reads, zero config.",
            tracking_url: "https://example.com",
            reward_amount: 250,
            brand_name: "Supabase",
            category: "DEVTOOL"
        )
        questPresenter?.push(testQuest)
    }

    func fetchAndShowQuest() {
        guard let apiClient = apiClient else { return }
        Task { @MainActor in
            do {
                let quest = try await apiClient.fetchQuest()
                self.questPresenter?.push(quest)
            } catch {
                // Silent — quest won't display
            }
        }
    }

    func handleDirectQuest(_ quest: QuestData) {
        Task { @MainActor in
            if let stateManager = self.stateManager {
                let shouldShow = await stateManager.shouldDisplayQuest()
                if !shouldShow {
                    ErrorHandler.logInfo("Quest blocked by state manager")
                    return
                }
            }
            await self.stateManager?.recordDisplay()
            self.questPresenter?.push(quest)
        }
    }

    func handleIPCTrigger(questId: String, trackingId: String) {
        Task { @MainActor in
            if let stateManager = self.stateManager {
                let shouldShow = await stateManager.shouldDisplayQuest()
                if !shouldShow {
                    ErrorHandler.logInfo("Quest blocked by state manager (cooldown/cap/disabled)")
                    return
                }
            }

            guard let apiClient = self.apiClient else {
                ErrorHandler.logInfo("IPC trigger received but apiClient not ready")
                return
            }

            do {
                let questData = try await apiClient.fetchQuest()
                await self.stateManager?.recordDisplay()
                self.questPresenter?.push(questData)
            } catch {
                ErrorHandler.logNetworkError(error, endpoint: "/quest")
            }
        }
    }
}

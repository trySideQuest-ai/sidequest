import AppKit
import Carbon
import SwiftUI

// NSPanel — .nonactivatingPanel lets clicks work without activating the app
class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// NSHostingView subclass: accepts first-mouse clicks + NSTrackingArea for hover
class HoverTrackingHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChanged: ((Bool) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSCursor.pointingHand.push()
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.pop()
        onHoverChanged?(false)
    }
}

// Shared hover state — bridges NSView hover detection to SwiftUI progress bar
class QuestHoverState: ObservableObject {
    @Published var isHovered = false
}


@MainActor
class WindowManager: NSObject {
    private var notificationWindow: NSWindow?
    private var dismissTimer: Timer?
    private var apiClient: APIClient?
    private var eventQueue: EventQueue?
    private var displayStartTime: Date?
    private var currentQuest: QuestData?
    private var userId: String = "unknown"
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var hotKeyHandlerRef: EventHandlerRef?
    // Static ref so the Carbon C callback can reach the active instance
    nonisolated(unsafe) private static weak var activeInstance: WindowManager?
    private var currentQuestForHotkey: QuestData?
    private var dismissRemainingTime: TimeInterval = 0
    private var timerStartDate: Date?
    private var hoverState = QuestHoverState()

    private static let debugLog = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".sidequest/debug.log")

    private static func debug(_ msg: String) {
        let line = "\(Date()): \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: debugLog.path) {
                if let handle = try? FileHandle(forWritingTo: debugLog) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? FileManager.default.createDirectory(at: debugLog.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: debugLog)
            }
        }
    }

    override init() {
        super.init()
    }

    deinit {
        dismissTimer?.invalidate()
        dismissTimer = nil
        // Inline cleanup — deinit can't call @MainActor methods
        for ref in hotKeyRefs {
            if let ref = ref { UnregisterEventHotKey(ref) }
        }
        if let handler = hotKeyHandlerRef { RemoveEventHandler(handler) }
        WindowManager.activeInstance = nil
    }

    func setAPIClient(_ client: APIClient) {
        self.apiClient = client
    }

    func setEventQueue(_ queue: EventQueue) {
        self.eventQueue = queue
    }

    func setUserId(_ id: String) {
        self.userId = id
    }

    // MARK: - Public Interface

    func showQuest(_ questData: QuestData) {
        // Drop if a notification is already showing — no queuing
        if notificationWindow != nil {
            return
        }

        displayQuest(questData)
    }

    // MARK: - Private Implementation

    private func getActiveScreen() -> NSScreen? {
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func displayQuest(_ questData: QuestData) {
        guard let activeScreen = getActiveScreen() else { return }
        let screenFrame = activeScreen.visibleFrame

        let cardWidth: CGFloat = QuestCardView.cardWidth
        let dismissSeconds = 8.0

        // Reset hover state BEFORE creating the view so both share the same instance
        hoverState = QuestHoverState()

        let contentView = NotificationWindowView(
            questData: questData,
            onOpen: { [weak self] in self?.handleOpen(questData) },
            onDismiss: { [weak self] in self?.handleDismiss() },
            hoverState: hoverState,
            dismissDuration: dismissSeconds
        )

        // Create hosting view with hover tracking via NSTrackingArea
        let hostingView = HoverTrackingHostingView(rootView: contentView)
        hostingView.onHoverChanged = { [weak self] hovering in
            self?.hoverState.isHovered = hovering
            self?.handleHover(hovering)
        }
        let fittingSize = hostingView.fittingSize
        let cardHeight = fittingSize.height

        // Position: flush right, well below macOS notification area
        let x = screenFrame.maxX - cardWidth
        let y = screenFrame.maxY - cardHeight - 150
        let frame = NSRect(x: x, y: y, width: cardWidth, height: cardHeight)

        // NSPanel with .nonactivatingPanel — clicks work without app activation
        let window = FloatingPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.isMovableByWindowBackground = false
        window.acceptsMouseMovedEvents = true

        hostingView.frame = NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight)
        window.contentView = hostingView

        // Lock window to computed size — prevents NSHostingView from resizing
        window.setFrame(frame, display: false)
        window.contentMinSize = NSSize(width: cardWidth, height: cardHeight)
        window.contentMaxSize = NSSize(width: cardWidth, height: cardHeight)

        self.notificationWindow = window
        self.displayStartTime = Date()
        self.currentQuest = questData

        installHotKeys(questData: questData)

        // Capture the currently focused app BEFORE showing our window
        let previousApp = NSWorkspace.shared.frontmostApplication

        animateIn(window, to: frame)

        // Auto-dismiss after 8 seconds
        dismissRemainingTime = dismissSeconds
        timerStartDate = Date()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: dismissSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleDismiss()
            }
        }

        window.orderFrontRegardless()

        // Immediately return focus to whatever app the user was in
        if let previousApp = previousApp {
            previousApp.activate()
        }
        ErrorHandler.logQuestDisplay(questData.quest_id)

        // Log quest_shown event
        let trackingId = deriveTrackingId(from: questData)
        let capturedUserId = userId
        Task {
            await self.eventQueue?.addEvent(
                userId: capturedUserId,
                questId: questData.quest_id,
                trackingId: trackingId,
                eventType: "quest_shown",
                metadata: [
                    "display_duration_ms": .int(8000),
                    "position": .string("top-right")
                ]
            )
        }
    }

    // MARK: - Global Keyboard Shortcuts (Carbon RegisterEventHotKey — no Accessibility needed)

    // Static handler for Carbon callback (C function pointer, cannot capture context)
    nonisolated static func handleHotKey(id: UInt32) {
        Task { @MainActor in
            guard let manager = WindowManager.activeInstance,
                  let quest = manager.currentQuestForHotkey,
                  manager.notificationWindow != nil else { return }

            WindowManager.debug("Carbon hotkey fired: id=\(id)")

            switch id {
            case 1: manager.handleOpen(quest)
            case 2: manager.handleDismiss()
            default: break
            }
        }
    }

    private func installHotKeys(questData: QuestData) {
        removeHotKeys()

        WindowManager.activeInstance = self
        currentQuestForHotkey = questData

        // Install Carbon event handler (one handler for all hotkeys)
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard err == noErr else { return err }
                WindowManager.handleHotKey(id: hotKeyID.id)
                return noErr
            },
            1,
            &eventType,
            nil,
            &hotKeyHandlerRef
        )

        // Register ⌘⌃O (open=1), ⌘⌃D (dismiss=2)
        let modifiers = UInt32(cmdKey | controlKey)
        let keys: [(keyCode: UInt32, id: UInt32)] = [
            (31, 1),  // 'o'
            (2, 2),   // 'd'
        ]
        let signature = OSType(0x5351_5354) // "SQST"

        for key in keys {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: signature, id: key.id)
            RegisterEventHotKey(key.keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
            hotKeyRefs.append(ref)
        }

        WindowManager.debug("Carbon hotkeys registered: \(hotKeyRefs.count) keys")
    }

    private func removeHotKeys() {
        for ref in hotKeyRefs {
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()

        if let handler = hotKeyHandlerRef {
            RemoveEventHandler(handler)
            hotKeyHandlerRef = nil
        }

        currentQuestForHotkey = nil
        WindowManager.activeInstance = nil
    }

    // MARK: - Tracking ID

    private func deriveTrackingId(from questData: QuestData) -> String {
        if let lastSlash = questData.tracking_url.lastIndex(of: "/") {
            let id = String(questData.tracking_url[questData.tracking_url.index(after: lastSlash)...])
            if !id.isEmpty { return id }
        }
        return questData.quest_id
    }

    // MARK: - Animation

    private func animateIn(_ window: NSWindow, to targetFrame: NSRect) {
        var startFrame = targetFrame
        startFrame.origin.x = getActiveScreen()?.visibleFrame.maxX ?? targetFrame.maxX
        window.setFrame(startFrame, display: false)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(targetFrame, display: true)
        })
    }

    // MARK: - Hover Pause/Resume

    private func handleHover(_ hovering: Bool) {
        if hovering {
            // Pause: record remaining time and invalidate timer
            if let start = timerStartDate {
                let elapsed = Date().timeIntervalSince(start)
                dismissRemainingTime = max(0, dismissRemainingTime - elapsed)
            }
            dismissTimer?.invalidate()
            dismissTimer = nil
            timerStartDate = nil
        } else {
            // Resume: always give at least 2 seconds after unhover so the card
            // doesn't vanish from rapid cursor enter/exit at the edges
            let resumeTime = max(dismissRemainingTime, 2.0)
            dismissRemainingTime = resumeTime
            timerStartDate = Date()
            dismissTimer = Timer.scheduledTimer(withTimeInterval: resumeTime, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.handleDismiss()
                }
            }
        }
    }

    // MARK: - Actions

    private func handleOpen(_ questData: QuestData) {
        let trackingId = deriveTrackingId(from: questData)
        let capturedUserId = userId
        Task {
            let timeToClick = self.displayStartTime.map { Date().timeIntervalSince($0) * 1000 } ?? 0
            await self.eventQueue?.addEvent(
                userId: capturedUserId,
                questId: questData.quest_id,
                trackingId: trackingId,
                eventType: "quest_clicked",
                metadata: [
                    "time_to_click_ms": .double(timeToClick),
                    "source": .string("keyboard")
                ]
            )
        }

        if let url = URL(string: questData.tracking_url),
           let scheme = url.scheme?.lowercased(),
           scheme == "https" {
            NSWorkspace.shared.open(url)
        }

        handleDismiss()
    }


    private func handleDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        removeHotKeys()

        guard let window = notificationWindow else { return }

        self.notificationWindow = nil

        let capturedDisplayStart = self.displayStartTime
        let quest = currentQuest
        let trackingId = quest.map { deriveTrackingId(from: $0) } ?? "unknown"
        let questId = quest?.quest_id ?? "unknown"
        let capturedUserId = userId

        self.displayStartTime = nil
        self.currentQuest = nil

        Task {
            let displayDuration = capturedDisplayStart.map { Date().timeIntervalSince($0) * 1000 } ?? 0
            await self.eventQueue?.addEvent(
                userId: capturedUserId,
                questId: questId,
                trackingId: trackingId,
                eventType: "quest_dismissed",
                metadata: [
                    "display_duration_ms": .double(displayDuration)
                ]
            )
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)

            let screenMaxX = getActiveScreen()?.visibleFrame.maxX ?? window.frame.maxX
            window.animator().setFrame(
                NSRect(x: screenMaxX,
                       y: window.frame.origin.y,
                       width: window.frame.width,
                       height: window.frame.height),
                display: true
            )
        }, completionHandler: {
            window.orderOut(nil)

            DispatchQueue.main.async {
                _ = window
            }
        })
    }
}

import AppKit
import SwiftUI

class WindowManager: NSObject {
    private var notificationWindow: NSWindow?
    private var dismissTimer: Timer?
    private var apiClient: APIClient?
    private var eventQueue: EventQueue?
    private var questQueue: [QuestData] = []
    private var displayStartTime: Date?

    override init() {
        super.init()
    }

    func setAPIClient(_ client: APIClient) {
        self.apiClient = client
    }

    func setEventQueue(_ queue: EventQueue) {
        self.eventQueue = queue
    }

    // MARK: - Public Interface

    func showQuest(_ questData: QuestData) {
        // If a notification is already showing, queue it
        if notificationWindow != nil {
            if questQueue.count < 3 {
                questQueue.append(questData)
            }
            // else drop the quest (queue limit exceeded)
            return
        }

        displayQuest(questData)
    }

    // MARK: - Private Implementation

    private func getActiveScreen() -> NSScreen {
        // Detect which monitor the developer is actively using

        // Method 1: Use main screen (most reliable for development)
        if let main = NSScreen.main {
            if let description = main.localizedName {
                ErrorHandler.logInfo("Quest will display on: \(description)")
            }
            return main
        }

        // Method 2: Fallback to primary screen (if main is nil)
        if let primary = NSScreen.screens.first {
            return primary
        }

        // Method 3: Last resort (should not happen)
        return NSScreen()
    }

    private func displayQuest(_ questData: QuestData) {
        do {
            // Position: top-right, just below system notification area
            // Detect which monitor the developer is actively using
            let activeScreen = getActiveScreen()
            let screenFrame = activeScreen.visibleFrame

            let x = screenFrame.maxX - 420  // 400pt wide + 20pt margin (on active screen)
            let y = screenFrame.maxY - 100   // Just below system notifications (on active screen)

            let frame = NSRect(x: x, y: y, width: 400, height: 250)

            // Create borderless, floating window
            let window = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            window.level = .floating          // Always on top
            window.isOpaque = false           // Transparent background
            window.backgroundColor = .clear
            window.collectionBehavior = [.transient, .ignoresCycle]  // Don't affect focus
            window.isMovableByWindowBackground = false

            // Create SwiftUI content
            let contentView = NotificationWindowView(
                questData: questData,
                onOpen: { [weak self] in self?.handleOpen(questData) },
                onDismiss: { [weak self] in self?.handleDismiss() }
            )

            // Wrap SwiftUI in NSHostingView for NSWindow
            window.contentView = NSHostingView(rootView: contentView)

            // Store reference
            self.notificationWindow = window
            self.displayStartTime = Date()

            // Animate in from the right
            animateIn(window)

            // Set auto-dismiss timer (8 seconds)
            dismissTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
                self?.handleDismiss()
            }

            // Make window visible
            window.makeKeyAndOrderFront(nil)
            ErrorHandler.logQuestDisplay(questData.quest_id)

            // Log quest_shown event (fire-and-forget)
            Task {
                await self.eventQueue?.addEvent(
                    userId: "unknown",  // TODO: Get real userId from auth in Plan 04
                    questId: questData.quest_id,
                    trackingId: self.deriveTrackingId(from: questData),
                    eventType: "quest_shown",
                    metadata: [
                        "display_duration_ms": .int(8000),
                        "position": .string("top-right")
                    ]
                )
            }

        } catch {
            ErrorHandler.logWindowError(error, operation: "display quest")
            // Continue without showing error — user never knows
        }
    }

    private func deriveTrackingId(from questData: QuestData) -> String {
        // TODO: Extract tracking_id from questData or tracking_url in Plan 04
        // For now, use questId as placeholder
        return questData.quest_id
    }

    private func animateIn(_ window: NSWindow) {
        // Start from off-screen right
        var frame = window.frame
        frame.origin.x = NSScreen.main?.visibleFrame.maxX ?? 1000
        window.setFrame(frame, display: false)

        // Animate to final position
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3  // 0.3 second slide-in
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            window.animator().setFrame(
                NSRect(x: window.frame.origin.x - (window.frame.width + 20),
                       y: window.frame.origin.y,
                       width: window.frame.width,
                       height: window.frame.height),
                display: true
            )
        })
    }

    private func handleOpen(_ questData: QuestData) {
        // Log quest_clicked event (fire-and-forget)
        Task {
            let timeToClick = self.displayStartTime.map { Date().timeIntervalSince($0) * 1000 } ?? 0
            await self.eventQueue?.addEvent(
                userId: "unknown",  // TODO: Get real userId from auth in Plan 04
                questId: questData.quest_id,
                trackingId: self.deriveTrackingId(from: questData),
                eventType: "quest_clicked",
                metadata: [
                    "time_to_click_ms": .double(timeToClick)
                ]
            )
        }

        // Open landing page in default browser
        if let url = URL(string: questData.tracking_url) {
            NSWorkspace.shared.open(url)
        }

        // Dismiss the notification
        handleDismiss()
    }

    private func handleDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        guard let window = notificationWindow else { return }

        // Capture quest data for event logging (will use placeholder questId)
        let questId = "unknown"  // TODO: Store current questId in displayQuest
        let trackingId = questId

        // Log quest_dismissed event (fire-and-forget)
        Task {
            let displayDuration = self.displayStartTime.map { Date().timeIntervalSince($0) * 1000 } ?? 0
            await self.eventQueue?.addEvent(
                userId: "unknown",  // TODO: Get real userId from auth in Plan 04
                questId: questId,
                trackingId: trackingId,
                eventType: "quest_dismissed",
                metadata: [
                    "display_duration_ms": .double(displayDuration)
                ]
            )
        }

        // Animate fade out
        NSAnimationContext.runAnimationGroup({ [weak self] context in
            context.duration = 0.2  // 0.2 second fade-out
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.completionHandler = {
                window.close()
                self?.notificationWindow = nil
                self?.displayStartTime = nil

                // If there are queued quests, show the next one
                if let nextQuest = self?.questQueue.first {
                    self?.questQueue.removeFirst()
                    self?.displayQuest(nextQuest)
                }
            }

            window.animator().alphaValue = 0.0
        })
    }
}

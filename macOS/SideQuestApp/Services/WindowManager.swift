import AppKit
import SwiftUI

class WindowManager: NSObject {
    private var notificationWindow: NSWindow?
    private var dismissTimer: Timer?
    private var apiClient: APIClient?
    private var questQueue: [QuestData] = []

    override init() {
        super.init()
    }

    func setAPIClient(_ client: APIClient) {
        self.apiClient = client
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

    private func displayQuest(_ questData: QuestData) {
        // Position: top-right, just below system notification area
        let mainScreen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = mainScreen.visibleFrame

        let x = screenFrame.maxX - 420  // 400pt wide + 20pt margin
        let y = screenFrame.maxY - 100   // Just below system notifications (starts from top)

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

        // Animate in from the right
        animateIn(window)

        // Set auto-dismiss timer (8 seconds)
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            self?.handleDismiss()
        }

        // Make window visible
        window.makeKeyAndOrderFront(nil)
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

        // Animate fade out
        NSAnimationContext.runAnimationGroup({ [weak self] context in
            context.duration = 0.2  // 0.2 second fade-out
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.completionHandler = {
                window.close()
                self?.notificationWindow = nil

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

import AppKit
import SwiftUI

// Shared hover-state bridge — NSView hover detection to SwiftUI observable.
final class QuestHoverState: ObservableObject {
    @Published var isHovered: Bool = false
}

// NSPanel subclass — non-activating, respects fullscreen, never steals focus.
// Host for QuestStackView. Positioned at top-right of active screen.

final class QuestPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [
            .transient,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
    }
}

// NSHostingView subclass — accepts first-mouse + hover tracking area.
class QuestHostingView<Content: SwiftUI.View>: NSHostingView<Content> {
    var onHoverChanged: ((Bool) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
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

// Active screen detection: screen containing the mouse cursor, not just main.
enum QuestScreenResolver {
    static func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let containing = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            return containing
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    static func topRightOrigin(for size: NSSize) -> NSPoint {
        let screen = activeScreen()
        let frame = screen.visibleFrame
        let x = frame.maxX - size.width - SQMetric.rightInset
        let y = frame.maxY - size.height - SQMetric.topInset
        return NSPoint(x: x, y: y)
    }
}

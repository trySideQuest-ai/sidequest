import Foundation
import SwiftUI
import AppKit

// QuestPresenter — owns the visible quest stack, timer, hover state,
// and event emission. @MainActor since it drives SwiftUI.
//
// Flow: IPC / manual trigger → push(QuestData) → stack append → view renders.
// Top card's timer ticks via internal Timer; stack behind is frozen.
// Dismiss (user click, close button, hotkey, timer) → remove from stack,
// emit quest_dismissed, unregister hotkeys if stack empty.

@MainActor
final class QuestPresenter: ObservableObject {

    // MARK: - Published state

    @Published private(set) var stack: [Quest] = []

    // Hover state per quest id — isolation lets each card track its own hover
    private var hoverStates: [UUID: QuestHoverState] = [:]

    // Dependencies
    private let eventQueue: EventQueue
    private let userId: String
    private let hotkeyManager: HotkeyManager
    private let panelController: QuestPanelController

    // Display tracking per quest
    private var displayStart: [UUID: Date] = [:]

    // Top card timer management
    private var dismissTimer: Timer?
    private var dismissRemaining: TimeInterval = 0
    private var timerStartDate: Date?

    // MARK: - Init

    init(
        eventQueue: EventQueue,
        userId: String,
        hotkeyManager: HotkeyManager,
        panelController: QuestPanelController
    ) {
        self.eventQueue = eventQueue
        self.userId = userId
        self.hotkeyManager = hotkeyManager
        self.panelController = panelController

        hotkeyManager.onOpen = { [weak self] in self?.openTop() }
        hotkeyManager.onDismiss = { [weak self] in self?.dismissTop() }
    }

    // MARK: - Visible stack (top-N for rendering)

    var visibleStack: [Quest] {
        Array(stack.prefix(SQMetric.stackMaxVisible))
    }

    func hoverState(for id: UUID) -> QuestHoverState {
        if let s = hoverStates[id] { return s }
        let s = QuestHoverState()
        hoverStates[id] = s
        return s
    }

    // MARK: - Push

    func push(_ data: QuestData) {
        let quest = Quest(from: data)
        // Insert newest at front (top of stack)
        stack.insert(quest, at: 0)
        displayStart[quest.id] = Date()

        // Fire quest_shown
        emit("quest_shown",
             questId: quest.sourceQuestId,
             trackingId: quest.sourceTrackingId,
             metadata: [
                "display_duration_ms": .int(Int(quest.duration * 1000)),
                "position": .string("top-right")
             ])
        ErrorHandler.logQuestDisplay(quest.sourceQuestId)

        // Show panel + register hotkeys if first card
        if stack.count == 1 {
            hotkeyManager.register()
        }
        panelController.show(presenter: self)
        restartTopTimer()
    }

    // MARK: - Open / Dismiss (by ID)

    func open(_ id: UUID) {
        guard let quest = stack.first(where: { $0.id == id }) else { return }
        let start = displayStart[quest.id]
        let dtMs = start.map { Date().timeIntervalSince($0) * 1000 } ?? 0
        emit("quest_clicked",
             questId: quest.sourceQuestId,
             trackingId: quest.sourceTrackingId,
             metadata: [
                "time_to_click_ms": .double(dtMs),
                "source": .string("click")
             ])
        openURL(quest.openURL)
        remove(id)
    }

    func dismiss(_ id: UUID) {
        guard let quest = stack.first(where: { $0.id == id }) else { return }
        let start = displayStart[quest.id]
        let dtMs = start.map { Date().timeIntervalSince($0) * 1000 } ?? 0
        emit("quest_dismissed",
             questId: quest.sourceQuestId,
             trackingId: quest.sourceTrackingId,
             metadata: [
                "display_duration_ms": .double(dtMs)
             ])
        remove(id)
    }

    // MARK: - Hotkey shortcuts → act on top

    private func openTop() {
        guard let top = stack.first else { return }
        open(top.id)
    }

    private func dismissTop() {
        guard let top = stack.first else { return }
        dismiss(top.id)
    }

    // MARK: - Timer (top-card only)

    private func restartTopTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        guard let top = stack.first else {
            panelController.hide()
            hotkeyManager.unregister()
            return
        }
        dismissRemaining = top.duration
        timerStartDate = Date()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: top.duration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismissTop() }
        }
    }

    func handleHover(_ hovering: Bool, for id: UUID) {
        // Only top card affects timer
        guard let top = stack.first, top.id == id else { return }

        // Propagate to the card's observable so the progress bar pauses too
        hoverStates[id]?.isHovered = hovering

        if hovering {
            if let start = timerStartDate {
                let elapsed = Date().timeIntervalSince(start)
                dismissRemaining = max(0, dismissRemaining - elapsed)
            }
            dismissTimer?.invalidate()
            dismissTimer = nil
            timerStartDate = nil
        } else {
            let resumeIn = max(dismissRemaining, 2.0)
            dismissRemaining = resumeIn
            timerStartDate = Date()
            dismissTimer = Timer.scheduledTimer(withTimeInterval: resumeIn, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.dismissTop() }
            }
        }
    }

    // MARK: - Remove from stack

    private func remove(_ id: UUID) {
        stack.removeAll { $0.id == id }
        displayStart[id] = nil
        hoverStates[id] = nil

        if stack.isEmpty {
            dismissTimer?.invalidate()
            dismissTimer = nil
            hotkeyManager.unregister()
            panelController.hide()
        } else {
            restartTopTimer()
            panelController.refresh(presenter: self)
        }
    }

    // MARK: - Helpers

    private func emit(_ type: String,
                      questId: String,
                      trackingId: String,
                      metadata: [String: AnyCodable]) {
        let uid = userId
        Task {
            await self.eventQueue.addEvent(
                userId: uid,
                questId: questId,
                trackingId: trackingId,
                eventType: type,
                metadata: metadata
            )
        }
    }

    private func openURL(_ url: URL?) {
        guard let url = url, let scheme = url.scheme?.lowercased(), scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - QuestPanelController (lightweight host for QuestPanel)

@MainActor
final class QuestPanelController {
    private var panel: QuestPanel?
    private var host: QuestHostingView<QuestStackRootView>?

    func show(presenter: QuestPresenter) {
        if panel == nil {
            let initialFrame = NSRect(
                origin: QuestScreenResolver.topRightOrigin(for: NSSize(width: SQMetric.cardWidth, height: 200)),
                size: NSSize(width: SQMetric.cardWidth, height: 200)
            )
            let p = QuestPanel(contentRect: initialFrame)
            let view = QuestStackRootView(presenter: presenter)
            let hv = QuestHostingView(rootView: view)
            hv.onHoverChanged = { [weak presenter] hovering in
                // Route to presenter's top card
                guard let p = presenter, let top = p.stack.first else { return }
                presenter?.handleHover(hovering, for: top.id)
            }
            p.contentView = hv
            self.panel = p
            self.host = hv
        } else {
            // Update presenter ref (new session)
            self.host?.rootView = QuestStackRootView(presenter: presenter)
        }
        refresh(presenter: presenter)
        panel?.orderFrontRegardless()
    }

    func refresh(presenter: QuestPresenter) {
        guard let p = panel, let hv = host else { return }
        // Force layout pass — hosting view recomputes intrinsic size from SwiftUI
        hv.layoutSubtreeIfNeeded()
        let fitting = hv.fittingSize
        let size = NSSize(width: SQMetric.cardWidth, height: max(fitting.height, 120))
        let origin = QuestScreenResolver.topRightOrigin(for: size)
        p.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

// Root view wraps QuestStackView so the hosting view can observe the presenter.
struct QuestStackRootView: View {
    @ObservedObject var presenter: QuestPresenter
    var body: some View {
        QuestStackView(presenter: presenter)
    }
}

import SwiftUI

struct NotificationWindowView: View {
    let questData: QuestData
    let onOpen: () -> Void
    let onDismiss: () -> Void
    @ObservedObject var hoverState: QuestHoverState
    let dismissDuration: Double

    var body: some View {
        QuestCardView(
            questData: questData,
            onOpen: onOpen,
            onDismiss: onDismiss,
            hoverState: hoverState,
            dismissDuration: dismissDuration
        )
    }
}

#if DEBUG
struct NotificationWindowView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationWindowView(
            questData: QuestData(
                quest_id: "test-123",
                display_text: "Explore new features",
                tracking_url: "https://example.com",
                reward_amount: 150,
                brand_name: "GitHub",
                category: "DevTool"
            ),
            onOpen: { print("Opened") },
            onDismiss: { print("Dismissed") },
            hoverState: QuestHoverState(),
            dismissDuration: 12.0
        )
    }
}
#endif

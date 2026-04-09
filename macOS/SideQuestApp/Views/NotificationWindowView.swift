import SwiftUI

struct NotificationWindowView: View {
    let questData: QuestData
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        QuestCardView(
            questData: questData,
            onOpen: onOpen,
            onDismiss: onDismiss
        )
        .frame(width: 400, height: 250)
    }
}

#Preview {
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
        onDismiss: { print("Dismissed") }
    )
}

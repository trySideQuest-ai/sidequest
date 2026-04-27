import Foundation

// View-layer wrapper of QuestData.
// QuestData is the IPC/API contract (snake_case) — do not change it.
// Quest is the ObservableObject-friendly model the card + presenter work with.

struct Quest: Identifiable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String
    let brand: String
    let category: String
    let duration: TimeInterval
    let openURL: URL?

    // Source IDs retained for event tracking
    let sourceQuestId: String
    let sourceTrackingId: String

    init(from data: QuestData, duration: TimeInterval = SQMetric.defaultDuration) {
        self.id = UUID()
        self.title = data.display_text
        self.subtitle = data.subtitle
        self.brand = data.brand_name
        self.category = data.category
        self.duration = duration
        self.openURL = URL(string: data.tracking_url)
        self.sourceQuestId = data.quest_id
        self.sourceTrackingId = Quest.trackingId(from: data)
    }

    static func trackingId(from data: QuestData) -> String {
        if let slash = data.tracking_url.lastIndex(of: "/") {
            let id = String(data.tracking_url[data.tracking_url.index(after: slash)...])
            if !id.isEmpty { return id }
        }
        return data.quest_id
    }

    static func == (lhs: Quest, rhs: Quest) -> Bool { lhs.id == rhs.id }
}

// Sentinel quest IDs for client-side special quests.
//
// welcomeQuestId is a real DB row with active=false (see plugin/hooks/stop-hook),
// so backend events with that FK insert cleanly.
//
// githubStarQuestId is local-only — it has no DB row, so QuestPresenter must
// skip emitting events for it (otherwise the events sync would FK-fail).
enum SpecialQuests {
    static let welcomeQuestId = "00000000-0000-0000-0000-000000000001"
    static let githubStarQuestId = "00000000-0000-0000-0000-000000000002"
    static let githubRepoURL = "https://github.com/trysidequest-ai/sidequest"

    static func githubStarPrompt() -> QuestData {
        QuestData(
            quest_id: githubStarQuestId,
            display_text: "Star SideQuest on GitHub?",
            subtitle: "Stars are how builders like us level up. It will make our day.",
            tracking_url: githubRepoURL,
            reward_amount: 0,
            brand_name: "SideQuest",
            category: "Community"
        )
    }
}

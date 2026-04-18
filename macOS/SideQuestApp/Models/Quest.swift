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

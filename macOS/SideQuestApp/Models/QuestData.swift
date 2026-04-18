import Foundation

struct QuestData: Codable {
    let quest_id: String
    let display_text: String
    let subtitle: String
    let tracking_url: String
    let reward_amount: Int
    let brand_name: String
    let category: String

    enum CodingKeys: String, CodingKey {
        case quest_id
        case display_text
        case subtitle
        case tracking_url
        case reward_amount
        case brand_name
        case category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quest_id = try container.decode(String.self, forKey: .quest_id)
        display_text = try container.decode(String.self, forKey: .display_text)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        tracking_url = try container.decode(String.self, forKey: .tracking_url)
        reward_amount = try container.decode(Int.self, forKey: .reward_amount)
        brand_name = try container.decode(String.self, forKey: .brand_name)
        category = try container.decode(String.self, forKey: .category)
    }

    init(quest_id: String, display_text: String, subtitle: String = "", tracking_url: String, reward_amount: Int, brand_name: String, category: String) {
        self.quest_id = quest_id
        self.display_text = display_text
        self.subtitle = subtitle
        self.tracking_url = tracking_url
        self.reward_amount = reward_amount
        self.brand_name = brand_name
        self.category = category
    }
}

extension QuestData {
    var logDescription: String {
        return "Quest(\(quest_id), '\(display_text)', reward=\(reward_amount)g, from=\(brand_name))"
    }
}
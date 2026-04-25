import Foundation

struct QuestData: Codable {
    let quest_id: String
    let display_text: String
    let subtitle: String
    let tracking_url: String
    let reward_amount: Int
    let brand_name: String
    let category: String

    // Embedding fields (Phase 12 IPC extension)
    let userMsg: String?
    let asst_msg: String?
    let userVec: [Float]?
    let asst_vec: [Float]?
    let inferenceMs: Int?
    let unkRateUser: Double?
    let unkRateAsst: Double?

    enum CodingKeys: String, CodingKey {
        case quest_id
        case display_text
        case subtitle
        case tracking_url
        case reward_amount
        case brand_name
        case category
        case userMsg = "user_msg"
        case asst_msg = "asst_msg"
        case userVec = "user_vec"
        case asst_vec = "asst_vec"
        case inferenceMs = "inference_ms"
        case unkRateUser = "unk_rate_user"
        case unkRateAsst = "unk_rate_asst"
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

        // Decode optional embedding fields
        userMsg = try container.decodeIfPresent(String.self, forKey: .userMsg)
        asst_msg = try container.decodeIfPresent(String.self, forKey: .asst_msg)
        userVec = try container.decodeIfPresent([Float].self, forKey: .userVec)
        asst_vec = try container.decodeIfPresent([Float].self, forKey: .asst_vec)
        inferenceMs = try container.decodeIfPresent(Int.self, forKey: .inferenceMs)
        unkRateUser = try container.decodeIfPresent(Double.self, forKey: .unkRateUser)
        unkRateAsst = try container.decodeIfPresent(Double.self, forKey: .unkRateAsst)
    }

    init(quest_id: String, display_text: String, subtitle: String = "", tracking_url: String, reward_amount: Int, brand_name: String, category: String, userMsg: String? = nil, asst_msg: String? = nil, userVec: [Float]? = nil, asst_vec: [Float]? = nil, inferenceMs: Int? = nil, unkRateUser: Double? = nil, unkRateAsst: Double? = nil) {
        self.quest_id = quest_id
        self.display_text = display_text
        self.subtitle = subtitle
        self.tracking_url = tracking_url
        self.reward_amount = reward_amount
        self.brand_name = brand_name
        self.category = category
        self.userMsg = userMsg
        self.asst_msg = asst_msg
        self.userVec = userVec
        self.asst_vec = asst_vec
        self.inferenceMs = inferenceMs
        self.unkRateUser = unkRateUser
        self.unkRateAsst = unkRateAsst
    }
}

extension QuestData {
    var logDescription: String {
        return "Quest(\(quest_id), '\(display_text)', reward=\(reward_amount)g, from=\(brand_name))"
    }
}
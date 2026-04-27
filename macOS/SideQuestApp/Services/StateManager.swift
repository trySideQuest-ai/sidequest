import Foundation
import os.log

// Daily cap, cooldown, and display counting are server-side concerns
// (see server/src/quest.js: countShownLast24h + users.daily_cap +
// enforceRateLimit). The server's /quest endpoint already returns
// `daily_cap_reached` when the user is over their quota and applies
// cooldown_minutes via the rate-limit gate, so the plugin's PHASE 7
// fetch never returns a quest the app should refuse.
//
// StateManager only owns the local kill switch (user_enabled) — the
// menu-bar toggle that pauses quests entirely. Removing the duplicate
// local cap fixes the drift bug where the app blocked displays while
// the server still thought there was room.
actor StateManager {
    private let stateFilePath: URL

    struct DisplayState: Codable {
        var user_enabled: Bool = true
        // Set to true the first time the user opens a quest that isn't the
        // welcome quest. Arms the GitHub-star prompt for the next push.
        var clicked_non_welcome_quest: Bool = false
        // Set to true once the GitHub-star prompt has been shown.
        // One-shot — never reset.
        var shown_github_star_prompt: Bool = false

        enum CodingKeys: String, CodingKey {
            case user_enabled
            case clicked_non_welcome_quest
            case shown_github_star_prompt
        }

        init() {}

        // Tolerant decode: missing keys fall back to defaults, so older
        // state.json files (pre-GitHub-star-prompt) don't fail decoding
        // and clobber user_enabled in the catch path.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.user_enabled = (try? c.decode(Bool.self, forKey: .user_enabled)) ?? true
            self.clicked_non_welcome_quest = (try? c.decode(Bool.self, forKey: .clicked_non_welcome_quest)) ?? false
            self.shown_github_star_prompt = (try? c.decode(Bool.self, forKey: .shown_github_star_prompt)) ?? false
        }
    }

    init(stateFileName: String = "state.json") {
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let sideQuestDir = appSupportDir.appendingPathComponent("SideQuest")
        try? FileManager.default.createDirectory(at: sideQuestDir, withIntermediateDirectories: true)
        self.stateFilePath = sideQuestDir.appendingPathComponent(stateFileName)
    }

    func shouldDisplayQuest() -> Bool {
        return readState().user_enabled
    }

    func setUserEnabled(_ enabled: Bool) {
        var state = readState()
        state.user_enabled = enabled
        writeState(state)
    }

    func hasClickedNonWelcomeQuest() -> Bool {
        readState().clicked_non_welcome_quest
    }

    func hasShownGithubStarPrompt() -> Bool {
        readState().shown_github_star_prompt
    }

    func markClickedNonWelcomeQuest() {
        var state = readState()
        guard !state.clicked_non_welcome_quest else { return }
        state.clicked_non_welcome_quest = true
        writeState(state)
    }

    func markGithubStarPromptShown() {
        var state = readState()
        guard !state.shown_github_star_prompt else { return }
        state.shown_github_star_prompt = true
        writeState(state)
    }

    private func readState() -> DisplayState {
        guard FileManager.default.fileExists(atPath: stateFilePath.path) else {
            return DisplayState()
        }

        do {
            let data = try Data(contentsOf: stateFilePath)
            // Decode only the fields we still care about. Old state.json files
            // with daily_cap / displays_today / cooldown_minutes / last_display_time
            // / last_reset are tolerated — JSONDecoder ignores unknown keys.
            return try JSONDecoder().decode(DisplayState.self, from: data)
        } catch {
            ErrorHandler.logStateError(error, operation: "read state")
            return DisplayState()
        }
    }

    private func writeState(_ state: DisplayState) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: stateFilePath, options: .atomic)
        } catch {
            ErrorHandler.logStateError(error, operation: "write state")
        }
    }
}

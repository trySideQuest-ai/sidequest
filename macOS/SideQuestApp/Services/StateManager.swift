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

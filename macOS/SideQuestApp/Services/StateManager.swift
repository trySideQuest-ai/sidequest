import Foundation
import os.log

actor StateManager {
    private let stateFilePath: URL

    struct DisplayState: Codable {
        var daily_cap: Int = 5
        var displays_today: Int = 0
        var last_display_time: Date?
        var cooldown_minutes: Int = 15
        var user_enabled: Bool = true
        var last_reset: Date?
    }

    init(stateFileName: String = "state.json") {
        // Path: ~/Library/Application Support/SideQuest/state.json
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let sideQuestDir = appSupportDir.appendingPathComponent("SideQuest")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: sideQuestDir, withIntermediateDirectories: true)

        self.stateFilePath = sideQuestDir.appendingPathComponent(stateFileName)
    }

    func shouldDisplayQuest() -> Bool {
        let state = readState()
        let now = Date()

        // Check if feature enabled
        guard state.user_enabled else { return false }

        // Check daily cap (reset if new day)
        let resetState = checkAndResetIfNewDay(state, now: now)

        if resetState.displays_today >= resetState.daily_cap {
            return false
        }

        // Check cooldown
        if let lastDisplay = resetState.last_display_time {
            let timeSinceLastDisplay = now.timeIntervalSince(lastDisplay)
            let cooldownSeconds = Double(resetState.cooldown_minutes) * 60
            if timeSinceLastDisplay < cooldownSeconds {
                return false
            }
        }

        return true
    }

    func recordDisplay() {
        var state = readState()
        let now = Date()

        // Check if new day and reset if needed
        state = checkAndResetIfNewDay(state, now: now)

        state.displays_today += 1
        state.last_display_time = now
        if state.last_reset == nil {
            state.last_reset = now
        }

        writeState(state)
    }

    func setUserEnabled(_ enabled: Bool) {
        var state = readState()
        state.user_enabled = enabled
        writeState(state)
    }

    private func checkAndResetIfNewDay(_ state: DisplayState, now: Date) -> DisplayState {
        var result = state

        if let lastReset = state.last_reset,
           !Calendar.current.isDateInToday(lastReset) {
            // New day, reset counter
            result.displays_today = 0
            result.last_reset = now
        } else if state.last_reset == nil {
            // First time, initialize reset date
            result.last_reset = now
        }

        return result
    }

    private func readState() -> DisplayState {
        guard FileManager.default.fileExists(atPath: stateFilePath.path) else {
            ErrorHandler.logInfo("State file does not exist, using defaults")
            return DisplayState()
        }

        do {
            let data = try Data(contentsOf: stateFilePath)
            let decoder = JSONDecoder()
            let state = try decoder.decode(DisplayState.self, from: data)
            return state
        } catch {
            ErrorHandler.logStateError(error, operation: "read state")
            return DisplayState()  // Reset to defaults on corruption
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
            // Continue even if write fails — state lost, but app continues
        }
    }
}

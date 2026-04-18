import SwiftUI

struct MenuContentView: View {
    var appDelegate: AppDelegate

    @State private var isEnabled = true
    @State private var isPaused = false
    @State private var pauseEndTime: Date?

    var body: some View {
        VStack {
            if isPaused, let endTime = pauseEndTime {
                Text("SideQuest — Paused until \(formatTime(endTime))")
            } else {
                Text("SideQuest — Running")
            }

            Divider()

            Toggle("Quests Enabled", isOn: $isEnabled)
                .onChange(of: isEnabled) { newValue in
                    Task {
                        await appDelegate.stateManager?.setUserEnabled(newValue)
                    }
                }

            Menu("Pause Quests") {
                Button("1 hour") { pauseFor(hours: 1) }
                Button("4 hours") { pauseFor(hours: 4) }
                Button("8 hours") { pauseFor(hours: 8) }
                Button("Until tomorrow") { pauseUntilTomorrow() }
            }

            if isPaused {
                Button("Resume Quests") {
                    Task {
                        await appDelegate.stateManager?.setUserEnabled(true)
                        await MainActor.run {
                            isPaused = false
                            pauseEndTime = nil
                            isEnabled = true
                        }
                    }
                }
            }

            Button("Show Test Quest") {
                appDelegate.showTestQuest()
            }

            Divider()

            Button("Quit SideQuest") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Helper Methods

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func pauseFor(hours: Int) {
        pauseFor(minutes: hours * 60)
    }

    private func pauseUntilTomorrow() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let tomorrowStart = Calendar.current.startOfDay(for: tomorrow)
        let minutesUntilTomorrow = Int(tomorrowStart.timeIntervalSince(Date()) / 60)
        pauseFor(minutes: minutesUntilTomorrow)
    }

    private func pauseFor(minutes: Int) {
        Task {
            await appDelegate.stateManager?.setUserEnabled(false)
            await MainActor.run {
                isPaused = true
                pauseEndTime = Date().addingTimeInterval(TimeInterval(minutes * 60))
                isEnabled = false
            }

            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)

            await appDelegate.stateManager?.setUserEnabled(true)
            await MainActor.run {
                isPaused = false
                pauseEndTime = nil
                isEnabled = true
            }

            ErrorHandler.logInfo("Quests resumed after \(minutes) minute pause")
        }

        ErrorHandler.logInfo("Quests paused for \(minutes) minutes")
    }
}

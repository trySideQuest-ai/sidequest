import SwiftUI

struct MenuContentView: View {
    @Environment(\.openURL) var openURL

    @State private var isEnabled = true
    @State private var historyEvents: [QuestEvent] = []
    @State private var showHistory = false
    @State private var isPaused = false
    @State private var pauseEndTime: Date?

    var eventQueue: EventQueue? = nil
    var stateManager: StateManager? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text("SideQuest")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Text("Running")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            Divider()

            // Toggle section
            HStack {
                Toggle("Quests Enabled", isOn: $isEnabled)
                    .font(.system(size: 12))
                    .onChange(of: isEnabled) { newValue in
                        Task {
                            await stateManager?.setUserEnabled(newValue)
                        }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Recent history section (if events exist)
            if !historyEvents.isEmpty {
                VStack(spacing: 4) {
                    Text("Recent")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    List(historyEvents.prefix(5), id: \.eventId) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.eventType)
                                .font(.system(size: 11, weight: .medium))
                            Text(formatTimestamp(event.timestamp))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 150)
                    .listStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
            }

            // Pause options section
            HStack {
                Menu {
                    Button("1 hour") { pauseFor(hours: 1) }
                    Button("4 hours") { pauseFor(hours: 4) }
                    Button("Until tomorrow") { pauseUntilTomorrow() }
                } label: {
                    HStack {
                        Image(systemName: "pause.circle")
                            .frame(width: 16)
                        Text("Pause")
                    }
                    .font(.system(size: 13))
                }
                .menuStyle(.borderlessButton)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Settings button
            HStack {
                Button(action: {
                    // Settings action (future: open preferences window)
                    NSLog("Settings clicked")
                }) {
                    HStack {
                        Image(systemName: "gear")
                            .frame(width: 16)
                        Text("Settings")
                    }
                    .font(.system(size: 13))
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Quit button
            HStack {
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack {
                        Image(systemName: "power")
                            .frame(width: 16)
                        Text("Quit SideQuest")
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 240)
        .padding(0)
        .onAppear {
            refreshHistory()
        }
    }

    // MARK: - Helper Methods

    private func refreshHistory() {
        Task {
            let allEvents = await eventQueue?.getPendingEvents() ?? []
            await MainActor.run {
                historyEvents = allEvents
            }
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func pauseFor(hours: Int) {
        let minutes = hours * 60
        pauseFor(minutes: minutes)
    }

    private func pauseUntilTomorrow() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let tomorrowStart = Calendar.current.startOfDay(for: tomorrow)
        let minutesUntilTomorrow = Int(tomorrowStart.timeIntervalSince(Date()) / 60)
        pauseFor(minutes: minutesUntilTomorrow)
    }

    private func pauseFor(minutes: Int) {
        Task {
            // Temporarily disable quests
            await stateManager?.setUserEnabled(false)
            isPaused = true
            pauseEndTime = Date().addingTimeInterval(TimeInterval(minutes * 60))

            // Re-enable after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(minutes * 60)) {
                Task {
                    await stateManager?.setUserEnabled(true)
                    isPaused = false
                    pauseEndTime = nil
                }
            }

            ErrorHandler.logInfo("Quests paused for \(minutes) minutes")
        }
    }
}

#Preview {
    MenuContentView()
}

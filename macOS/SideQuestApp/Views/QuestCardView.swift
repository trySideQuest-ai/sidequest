import SwiftUI

struct QuestCardView: View {
    let questData: QuestData
    let onOpen: () -> Void
    let onDismiss: () -> Void
    @ObservedObject var hoverState: QuestHoverState
    let dismissDuration: Double

    static let cardWidth: CGFloat = 320

    // Timer-driven progress — avoids SwiftUI animation timing mismatch on pause/resume
    @State private var isProgressRunning = false
    @State private var progressStartDate: Date?
    @State private var progressStartValue: CGFloat = 1.0
    @State private var pausedProgress: CGFloat = 1.0

    private func currentProgress(at date: Date) -> CGFloat {
        guard isProgressRunning, let start = progressStartDate else {
            return pausedProgress
        }
        let elapsed = date.timeIntervalSince(start)
        let result = progressStartValue - (elapsed / dismissDuration)
        return max(0, min(1, result))
    }

    var body: some View {
        // Content VStack — drives intrinsic height
        VStack(alignment: .leading, spacing: 6) {
            // Quest title (hook)
            Text(questData.display_text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)

            // Subtitle (what the product actually is)
            if !questData.subtitle.isEmpty {
                Text(questData.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.7))
                    .lineLimit(3)
            }

            Spacer().frame(height: 2)

            // Category badge + sponsor + reward on one line
            HStack(spacing: 6) {
                Text(questData.category.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.15, green: 0.04, blue: 0.28))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(red: 0.9, green: 0.8, blue: 0.4))
                    )

                Text("from \(questData.brand_name)")
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.55))

                Spacer(minLength: 0)

                Image(systemName: "star.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 1.0, green: 0.843, blue: 0.0))

                Text("+\(questData.reward_amount)g")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 1.0, green: 0.843, blue: 0.0))
            }

            // Keyboard shortcut hints
            HStack(spacing: 12) {
                shortcutHint("⌘⌃O", label: "Open")
                shortcutHint("⌘⌃D", label: "Skip")
            }
            .padding(.top, 2)
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .padding(.leading, 16)
        .padding(.trailing, 40) // room for close button
        // Fixed width, dynamic height
        .frame(width: QuestCardView.cardWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        // Entire card is tappable — contentShape ensures padding area is included
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.15, green: 0.04, blue: 0.28))
        )
        // Progress bar overlay at bottom — driven by TimelineView for glitch-free pause/resume
        .overlay(alignment: .bottom) {
            TimelineView(.animation) { context in
                GeometryReader { geo in
                    HStack {
                        Spacer()
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.85, green: 0.65, blue: 0.0),
                                        Color(red: 1.0, green: 0.843, blue: 0.0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * currentProgress(at: context.date), height: 3)
                    }
                }
            }
            .frame(height: 3)
            .allowsHitTesting(false)
            .clipShape(
                RoundedRectangle(cornerRadius: 12)
            )
        }
        // Close button overlay top-right
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: hoverState.isHovered) { [hoverState] _ in
            let hovering = hoverState.isHovered
            if hovering {
                // Pause: snapshot current progress from real time
                pausedProgress = currentProgress(at: Date())
                isProgressRunning = false
                progressStartDate = nil
            } else {
                // Resume: continue from paused value
                progressStartValue = pausedProgress
                progressStartDate = Date()
                isProgressRunning = true
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                progressStartValue = 1.0
                progressStartDate = Date()
                isProgressRunning = true
            }
        }
    }

    private func shortcutHint(_ keys: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(keys)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.4))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Color.white.opacity(0.35))
        }
    }
}

#if DEBUG
struct QuestCardView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            QuestCardView(
                questData: QuestData(
                    quest_id: "test-1",
                    display_text: "Speed Up Your Queries",
                    tracking_url: "https://example.com",
                    reward_amount: 250,
                    brand_name: "Supabase",
                    category: "DevTool"
                ),
                onOpen: {},
                onDismiss: {},
                hoverState: QuestHoverState(),
                dismissDuration: 8.0
            )
            QuestCardView(
                questData: QuestData(
                    quest_id: "test-2",
                    display_text: "Speed Up Your PostgreSQL Queries",
                    subtitle: "Adorable pinnipeds in fashionable headwear — new hats every week",
                    tracking_url: "https://example.com",
                    reward_amount: 250,
                    brand_name: "Supabase",
                    category: "DevTool"
                ),
                onOpen: {},
                onDismiss: {},
                hoverState: QuestHoverState(),
                dismissDuration: 8.0
            )
        }
        .padding()
        .background(Color.gray)
    }
}
#endif

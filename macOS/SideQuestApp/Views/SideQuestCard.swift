import SwiftUI

// MARK: - SideQuestCard (Fantasy Parchment Quest Card)
//
// Pixel-perfect render of v1.9 handoff: parchment body with gold double-ring
// border, pixel L-bracket ornaments, retro "◆ SIDE QUEST" label, title,
// subtitle, brand + category chip, dashed separator, keycap shortcut hints,
// and a gold timer bar along the bottom.

struct SideQuestCard: View {
    let questData: QuestData
    let onOpen: () -> Void
    let onDismiss: () -> Void
    @ObservedObject var hoverState: QuestHoverState
    let dismissDuration: Double

    static let cardWidth: CGFloat = SQMetric.cardWidth

    // Timer state (same strategy as v1.0: TimelineView + snapshot on pause)
    @State private var isProgressRunning = false
    @State private var progressStartDate: Date?
    @State private var progressStartValue: CGFloat = 1.0
    @State private var pausedProgress: CGFloat = 1.0

    // Keycap flash state (set externally on hotkey fire — placeholder scaffolding)
    @State private var openKeycapFlash: Bool = false
    @State private var dismissKeycapFlash: Bool = false

    private func currentProgress(at date: Date) -> CGFloat {
        guard isProgressRunning, let start = progressStartDate else {
            return pausedProgress
        }
        let elapsed = date.timeIntervalSince(start)
        let result = progressStartValue - (elapsed / dismissDuration)
        return max(0, min(1, result))
    }

    var body: some View {
        ZStack {
            cardBase
            content
            cornerOrnaments
            closeButton
            timerBar
        }
        .frame(width: SQMetric.cardWidth)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .sqCardShadow()
        .onChange(of: hoverState.isHovered) { [hoverState] _ in
            let hovering = hoverState.isHovered
            if hovering {
                pausedProgress = currentProgress(at: Date())
                isProgressRunning = false
                progressStartDate = nil
            } else {
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

    // MARK: - Base (parchment w/ gold double-ring border + noise texture)

    private var cardBase: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SQMetric.outerCorner, style: .continuous)
                .fill(SQColor.parchment)

            RoundedRectangle(cornerRadius: SQMetric.outerCorner, style: .continuous)
                .stroke(SQColor.gold, lineWidth: SQMetric.ringOuter)

            RoundedRectangle(cornerRadius: SQMetric.innerCorner, style: .continuous)
                .stroke(SQColor.goldDeep.opacity(0.8), lineWidth: SQMetric.ringInner)
                .padding(SQMetric.ringGap)

            NoiseOverlay()
                .clipShape(RoundedRectangle(cornerRadius: SQMetric.outerCorner, style: .continuous))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Content Stack

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Retro label
            HStack(spacing: 6) {
                Text("◆")
                    .font(SQFont.pixel(7))
                    .foregroundColor(SQColor.gold)
                Text("SIDE QUEST")
                    .font(SQFont.pixel(7))
                    .foregroundColor(SQColor.ink)
                    .tracking(2)
                Spacer()
            }
            .padding(.bottom, 2)

            // Title
            Text(questData.display_text)
                .font(SQFont.inter(15, weight: .semibold))
                .foregroundColor(SQColor.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Subtitle
            if !questData.subtitle.isEmpty {
                Text(questData.subtitle)
                    .font(SQFont.inter(11, weight: .regular))
                    .foregroundColor(SQColor.inkSoft)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer().frame(height: 6)

            // Brand + category chip
            HStack(spacing: 8) {
                if !questData.brand_name.isEmpty {
                    Text("from \(questData.brand_name)")
                        .font(SQFont.inter(10, weight: .medium))
                        .foregroundColor(SQColor.inkMute)
                }
                Spacer(minLength: 0)
                if !questData.category.isEmpty {
                    Text(questData.category.uppercased())
                        .font(SQFont.pixel(7))
                        .foregroundColor(SQColor.categoryTxt)
                        .tracking(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(SQColor.categoryChip)
                        )
                }
            }

            // Dashed separator
            DashedSeparator()
                .frame(height: 1)
                .padding(.top, 4)

            // Shortcut hints
            HStack(spacing: 14) {
                shortcutCluster(keys: ["⌘", "⌃", "O"], label: "Open", flash: $openKeycapFlash)
                shortcutCluster(keys: ["⌘", "⌃", "D"], label: "Skip", flash: $dismissKeycapFlash)
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
        .padding(.top, SQMetric.cardPadding)
        .padding(.bottom, 20)
        .padding(.leading, SQMetric.contentLead)
        .padding(.trailing, 38) // room for close button
    }

    // MARK: - Pixel L-Bracket Ornaments (4 corners)

    private var cornerOrnaments: some View {
        GeometryReader { geo in
            ZStack {
                PixelLBracket(corner: .topLeading)
                    .frame(width: SQMetric.pixelCorner, height: SQMetric.pixelCorner)
                    .position(x: SQMetric.pixelCorner / 2 + 5,
                              y: SQMetric.pixelCorner / 2 + 5)

                PixelLBracket(corner: .topTrailing)
                    .frame(width: SQMetric.pixelCorner, height: SQMetric.pixelCorner)
                    .position(x: geo.size.width - SQMetric.pixelCorner / 2 - 5,
                              y: SQMetric.pixelCorner / 2 + 5)

                PixelLBracket(corner: .bottomLeading)
                    .frame(width: SQMetric.pixelCorner, height: SQMetric.pixelCorner)
                    .position(x: SQMetric.pixelCorner / 2 + 5,
                              y: geo.size.height - SQMetric.pixelCorner / 2 - 5)

                PixelLBracket(corner: .bottomTrailing)
                    .frame(width: SQMetric.pixelCorner, height: SQMetric.pixelCorner)
                    .position(x: geo.size.width - SQMetric.pixelCorner / 2 - 5,
                              y: geo.size.height - SQMetric.pixelCorner / 2 - 5)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Close button (top-right)

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(SQColor.keycapBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(SQColor.inkPale, lineWidth: 0.8)
                            )
                            .frame(width: 18, height: 18)
                        Text("×")
                            .font(SQFont.inter(13, weight: .medium))
                            .foregroundColor(SQColor.inkSoft)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 14)
                .padding(.trailing, 14)
            }
            Spacer()
        }
    }

    // MARK: - Gold Timer Bar

    private var timerBar: some View {
        VStack(spacing: 0) {
            Spacer()
            TimelineView(.animation) { context in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track
                        Rectangle()
                            .fill(SQColor.goldDeep.opacity(0.22))
                            .frame(height: SQMetric.timerBarHeight)

                        // Fill — solid gold (gradient disabled on macOS 26 Metal)
                        Rectangle()
                            .fill(SQColor.gold)
                            .frame(
                                width: geo.size.width * currentProgress(at: context.date),
                                height: SQMetric.timerBarHeight
                            )
                    }
                }
            }
            .frame(height: SQMetric.timerBarHeight)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: SQMetric.outerCorner, style: .continuous))
    }

    // MARK: - Shortcut Cluster

    private func shortcutCluster(keys: [String], label: String, flash: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(keys.indices, id: \.self) { idx in
                    Keycap(text: keys[idx], flashing: flash.wrappedValue)
                }
            }
            Text(label)
                .font(SQFont.inter(10, weight: .medium))
                .foregroundColor(SQColor.inkMute)
        }
    }
}

// MARK: - Noise Overlay (deterministic dot grid via SwiftUI primitives)

private struct NoiseOverlay: View {
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                let spacing: CGFloat = 7
                let dot: CGFloat = 1.5
                let cols = Int(geo.size.width / spacing) + 1
                let rows = Int(geo.size.height / spacing) + 1
                ForEach(0..<rows, id: \.self) { r in
                    ForEach(0..<cols, id: \.self) { c in
                        Circle()
                            .fill(SQColor.noiseDot)
                            .frame(width: dot, height: dot)
                            .offset(
                                x: CGFloat(c) * spacing + CGFloat((r * 31 + c * 17) % 3) - 1,
                                y: CGFloat(r) * spacing
                            )
                    }
                }
            }
        }
    }
}

// MARK: - Pixel L-Bracket Ornament (ZStack of Rectangles)

private struct PixelLBracket: View {
    enum Corner { case topLeading, topTrailing, bottomLeading, bottomTrailing }
    let corner: Corner

    var body: some View {
        // 4x4 grid of pixel blocks (SwiftUI primitives — no Canvas).
        let u = SQMetric.pixelUnit
        let blocks: [(CGFloat, CGFloat)]
        switch corner {
        case .topLeading:
            blocks = [(0,0), (1,0), (2,0), (3,0), (0,1), (0,2), (0,3)]
        case .topTrailing:
            blocks = [(0,0), (1,0), (2,0), (3,0), (3,1), (3,2), (3,3)]
        case .bottomLeading:
            blocks = [(0,0), (0,1), (0,2), (0,3), (1,3), (2,3), (3,3)]
        case .bottomTrailing:
            blocks = [(3,0), (3,1), (3,2), (3,3), (0,3), (1,3), (2,3)]
        }
        return ZStack(alignment: .topLeading) {
            ForEach(0..<blocks.count, id: \.self) { i in
                let (bx, by) = blocks[i]
                Rectangle()
                    .fill(SQColor.gold)
                    .frame(width: u, height: u)
                    .offset(x: bx * u, y: by * u)
            }
        }
        .frame(width: u * 4, height: u * 4, alignment: .topLeading)
    }
}

// MARK: - Dashed Separator (rectangle grid — avoids Canvas)

private struct DashedSeparator: View {
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(0..<Int(geo.size.width / 6), id: \.self) { _ in
                    Rectangle()
                        .fill(SQColor.separator)
                        .frame(width: 3, height: 1)
                }
            }
        }
        .frame(height: 1)
    }
}

// MARK: - Keycap

private struct Keycap: View {
    let text: String
    let flashing: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SQMetric.keycapRadius, style: .continuous)
                .fill(flashing ? SQColor.keycapFlash : SQColor.keycapBg)
                .overlay(
                    RoundedRectangle(cornerRadius: SQMetric.keycapRadius, style: .continuous)
                        .stroke(SQColor.inkPale.opacity(0.7), lineWidth: 0.7)
                )
            Text(text)
                .font(SQFont.inter(9, weight: .medium))
                .foregroundColor(SQColor.ink)
        }
        .frame(width: SQMetric.keycapWidth, height: SQMetric.keycapHeight)
    }
}

// MARK: - Preview

#if DEBUG
struct SideQuestCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            SideQuestCard(
                questData: QuestData(
                    quest_id: "prev-1",
                    display_text: "Speed Up Your PostgreSQL Queries",
                    subtitle: "Index optimization tips tailored to your schema",
                    tracking_url: "https://example.com",
                    reward_amount: 250,
                    brand_name: "Supabase",
                    category: "DevTool"
                ),
                onOpen: {},
                onDismiss: {},
                hoverState: QuestHoverState(),
                dismissDuration: 7.0
            )
            SideQuestCard(
                questData: QuestData(
                    quest_id: "prev-2",
                    display_text: "Instant Feature Flags for Your API",
                    tracking_url: "https://example.com",
                    reward_amount: 150,
                    brand_name: "LaunchDarkly",
                    category: "Tooling"
                ),
                onOpen: {},
                onDismiss: {},
                hoverState: QuestHoverState(),
                dismissDuration: 7.0
            )
        }
        .padding(24)
        .background(Color(red: 0.12, green: 0.10, blue: 0.18))
    }
}
#endif

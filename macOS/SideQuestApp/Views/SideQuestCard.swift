import SwiftUI

// MARK: - SideQuestCard (Fantasy Parchment — design-handoff parity)
//
// Mirrors design_handoff_sidequest_notification/Swift/SideQuestCard.swift:
// parchment body, gold outer ring + purple inner ring (inset 3pt), 4 pixel-art
// L-bracket corners, "◆ SIDE QUEST" gold label w/ fade gradient rule, title,
// subtitle, BrandTag + CategoryTag (left-aligned), solid purple Divider,
// 3-keycap shortcut rows, circular translucent close, trailing-anchored
// gradient timer bar. Preserves app integration API (QuestData, hoverState,
// dismissDuration) + keycap flash scaffolding.

struct SideQuestCard: View {
    let questData: QuestData
    let onOpen: () -> Void
    let onDismiss: () -> Void
    @ObservedObject var hoverState: QuestHoverState
    let dismissDuration: Double

    static let cardWidth: CGFloat = SQMetric.cardWidth

    // Timer state (TimelineView + snapshot-on-pause)
    @State private var isProgressRunning = false
    @State private var progressStartDate: Date?
    @State private var progressStartValue: CGFloat = 1.0
    @State private var pausedProgress: CGFloat = 1.0

    // Keycap flash scaffolding (set externally on hotkey fire)
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
        ZStack(alignment: .topLeading) {
            paperBackground
            ringFrame
            pixelCorners
            content
                .padding(.top,    SQMetric.cardPadTop)
                .padding(.trailing, SQMetric.cardPadRight)
                .padding(.bottom, SQMetric.cardPadBottom)
                .padding(.leading,  SQMetric.cardPadLeft)
            closeButton
            timerBar
        }
        .frame(width: SQMetric.cardWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .sqCardShadow()
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
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

    // MARK: — Paper background (parchment + dot texture)

    private var paperBackground: some View {
        RoundedRectangle(cornerRadius: SQMetric.cardRadius, style: .continuous)
            .fill(SQColor.fantasyPaper)
            .overlay(ParchmentDots().opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: SQMetric.cardRadius, style: .continuous))
    }

    // MARK: — Ring frame (outer gold 1pt + inner purple 1pt inset 3pt)

    private var ringFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SQMetric.cardRadius, style: .continuous)
                .strokeBorder(SQColor.gold400, lineWidth: 1)

            RoundedRectangle(cornerRadius: SQMetric.cardRadius - 3, style: .continuous)
                .strokeBorder(SQColor.purple700.opacity(0.55), lineWidth: 1)
                .padding(SQMetric.ringInsetPurple)
        }
        .allowsHitTesting(false)
    }

    // MARK: — Pixel-art corner brackets (4 corners)

    private var pixelCorners: some View {
        ZStack {
            PixelBracket()
                .offset(x: SQMetric.pixelCornerPad, y: SQMetric.pixelCornerPad)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            PixelBracket()
                .scaleEffect(x: -1, y: 1)
                .offset(x: -SQMetric.pixelCornerPad, y: SQMetric.pixelCornerPad)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            PixelBracket()
                .scaleEffect(x: 1, y: -1)
                .offset(x: SQMetric.pixelCornerPad, y: -SQMetric.pixelCornerPad)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            PixelBracket()
                .scaleEffect(x: -1, y: -1)
                .offset(x: -SQMetric.pixelCornerPad, y: -SQMetric.pixelCornerPad)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .allowsHitTesting(false)
    }

    // MARK: — Content stack

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1: ◆ SIDE QUEST + gold→clear gradient divider
            HStack(spacing: 8) {
                Text("◆ SIDE QUEST")
                    .font(SQFont.pixel(7))
                    .tracking(0.5)
                    .foregroundColor(SQColor.gold600)

                LinearGradient(
                    colors: [SQColor.gold400, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
            }
            .padding(.leading, SQMetric.contentGutter)
            .padding(.bottom, 4)

            // Row 2: Title
            Text(questData.display_text)
                .font(SQFont.inter(14, weight: .semibold))
                .tracking(-0.1)
                .lineSpacing(14 * 0.25)
                .foregroundColor(SQColor.purple800)
                .padding(.leading, SQMetric.contentGutter)
                .fixedSize(horizontal: false, vertical: true)

            // Row 3: Subtitle
            if !questData.subtitle.isEmpty {
                Text(questData.subtitle)
                    .font(SQFont.inter(12, weight: .regular))
                    .lineSpacing(12 * 0.4)
                    .foregroundColor(SQColor.ink2)
                    .padding(.leading, SQMetric.contentGutter)
                    .padding(.top, 3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Row 4: Meta tags — brand + category, left-aligned
            HStack(spacing: 6) {
                if !questData.brand_name.isEmpty {
                    BrandTag(text: questData.brand_name)
                }
                if !questData.category.isEmpty {
                    CategoryTag(text: questData.category.uppercased())
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, SQMetric.contentGutter)
            .padding(.top, 8)

            // Solid purple divider
            Divider()
                .overlay(SQColor.purple700.opacity(0.2))
                .padding(.top, 7)

            // Shortcut row
            HStack(spacing: 8) {
                ShortcutGroup(keys: ["⌘", "⌃", "O"], label: "Open", flashing: openKeycapFlash)
                ShortcutGroup(keys: ["⌘", "⌃", "D"], label: "Skip", flashing: dismissKeycapFlash)
                Spacer(minLength: 0)
            }
            .padding(.top, 6)
            .padding(.leading, SQMetric.contentGutter)
        }
    }

    // MARK: — Close button (circular, black 0.06 bg)

    private var closeButton: some View {
        Button(action: onDismiss) {
            Text("×")
                .font(SQFont.inter(13, weight: .regular))
                .foregroundColor(SQColor.ink3)
                .frame(width: SQMetric.closeSize, height: SQMetric.closeSize)
                .background(Circle().fill(Color.black.opacity(0.06)))
                .offset(y: -1)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 8)
        .padding(.trailing, 8)
    }

    // MARK: — Timer bar (trailing-anchored partial-width gradient)

    private var timerBar: some View {
        TimelineView(.animation) { context in
            let p = currentProgress(at: context.date)
            GeometryReader { _ in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [SQColor.gold500, SQColor.gold300],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: SQMetric.timerHeight)
                    .scaleEffect(x: p, y: 1, anchor: .trailing)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 7,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0,
                            style: .continuous
                        )
                    )
            }
            .frame(height: SQMetric.timerHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.leading, SQMetric.timerEdgeInset)
        .padding(.trailing, SQMetric.timerRightInset)
        .padding(.bottom, SQMetric.timerEdgeInset)
        .allowsHitTesting(false)
    }
}

// MARK: - Pixel bracket (L-shape; 3pt pixels; 10×10pt total)

private struct PixelBracket: View {
    var body: some View {
        Canvas { ctx, _ in
            let p: CGFloat = 3
            let gold = SQColor.gold500
            // Top row: 3 pixels
            for i in 0..<3 {
                ctx.fill(
                    Path(CGRect(x: CGFloat(i) * p, y: 0, width: p, height: p)),
                    with: .color(gold)
                )
            }
            // Left column: 2 additional pixels below top-left
            for i in 1..<3 {
                ctx.fill(
                    Path(CGRect(x: 0, y: CGFloat(i) * p, width: p, height: p)),
                    with: .color(gold)
                )
            }
        }
        .frame(width: SQMetric.pixelCornerSize, height: SQMetric.pixelCornerSize)
        .drawingGroup()
    }
}

// MARK: - Brand tag (purple pill w/ square bullet)

private struct BrandTag: View {
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(SQColor.purple800)
                .frame(width: 4, height: 4)
                .offset(y: -1)
            Text(text)
                .font(SQFont.inter(10.5, weight: .semibold))
                .tracking(0.2)
                .foregroundColor(SQColor.purple800)
        }
        .padding(.horizontal, 7)
        .frame(height: SQMetric.tagHeight)
        .background(SQColor.purple700.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(SQColor.purple700.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

// MARK: - Category tag (gold gradient pill w/ pixel text)

private struct CategoryTag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(SQFont.pixel(6.5))
            .tracking(0.5)
            .foregroundColor(SQColor.purple800)
            .padding(.horizontal, 6)
            .frame(height: SQMetric.tagHeight)
            .background(
                LinearGradient(
                    colors: [SQColor.gold300, SQColor.gold400],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(SQColor.gold500, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

// MARK: - Shortcut group (3 keycaps + verb)

private struct ShortcutGroup: View {
    let keys: [String]
    let label: String
    let flashing: Bool
    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(keys, id: \.self) { k in
                    KeyCap(glyph: k, flashing: flashing)
                }
            }
            Text(label)
                .font(SQFont.inter(11, weight: .regular))
                .foregroundColor(SQColor.ink3)
        }
    }
}

// MARK: - Keycap (18×18 square, Inter 10pt medium)

private struct KeyCap: View {
    let glyph: String
    let flashing: Bool
    var body: some View {
        Text(glyph)
            .font(SQFont.inter(10, weight: .medium))
            .foregroundColor(SQColor.ink2)
            .frame(width: SQMetric.keyCapSize, height: SQMetric.keyCapSize)
            .background(flashing ? SQColor.keycapFlash : Color.white.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.black.opacity(0.14), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Parchment dot overlay (subtle texture)

private struct ParchmentDots: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 6
            let dot: CGFloat = 1.2
            let color = SQColor.purple700.opacity(0.04)
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: dot, height: dot)),
                        with: .color(color)
                    )
                    x += step
                }
                y += step
            }
        }
        .allowsHitTesting(false)
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
                    display_text: "Speed up your Postgres queries",
                    subtitle: "Drop-in connection pooler — 10× faster reads, zero config.",
                    tracking_url: "https://example.com",
                    reward_amount: 250,
                    brand_name: "Supabase",
                    category: "DEVTOOL"
                ),
                onOpen: {},
                onDismiss: {},
                hoverState: QuestHoverState(),
                dismissDuration: 7.0
            )
            SideQuestCard(
                questData: QuestData(
                    quest_id: "prev-2",
                    display_text: "Instant feature flags for your API",
                    subtitle: "Ship safely with targeted rollouts, zero config.",
                    tracking_url: "https://example.com",
                    reward_amount: 150,
                    brand_name: "LaunchDarkly",
                    category: "TOOLING"
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

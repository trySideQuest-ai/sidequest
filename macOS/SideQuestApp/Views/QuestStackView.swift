import SwiftUI

// Stack layout for up to 3 visible cards with depth effects.
// Newest-in-front convention — most recent quest is index 0 (topmost).
// Cards behind scale + offset + opacity per depth.

struct QuestStackView: View {
    @ObservedObject var presenter: QuestPresenter

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(Array(presenter.visibleStack.enumerated()), id: \.element.id) { index, quest in
                SideQuestCard(
                    questData: QuestData(
                        quest_id: quest.sourceQuestId,
                        display_text: quest.title,
                        subtitle: quest.subtitle,
                        tracking_url: quest.openURL?.absoluteString ?? "",
                        reward_amount: 0,
                        brand_name: quest.brand,
                        category: quest.category
                    ),
                    onOpen: { presenter.open(quest.id) },
                    onDismiss: { presenter.dismiss(quest.id) },
                    hoverState: presenter.hoverState(for: quest.id),
                    dismissDuration: quest.duration
                )
                .scaleEffect(scale(for: index))
                .offset(y: yOffset(for: index))
                .opacity(opacity(for: index))
                .zIndex(Double(presenter.visibleStack.count - index))
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
                .allowsHitTesting(index == 0)
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: presenter.visibleStack.map { $0.id })
        .frame(width: SQMetric.cardWidth, alignment: .top)
    }

    private func scale(for depth: Int) -> CGFloat {
        1.0 - (CGFloat(depth) * 0.035)
    }

    private func yOffset(for depth: Int) -> CGFloat {
        CGFloat(depth) * 8
    }

    private func opacity(for depth: Int) -> Double {
        1.0 - (Double(depth) * 0.08)
    }
}

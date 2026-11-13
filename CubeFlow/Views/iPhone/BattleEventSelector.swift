#if os(iOS)
import SwiftUI

enum BattleEventSelectorPolicy {
    static var events: [PuzzleEvent] {
        PuzzleEvent.regularCases.flatMap { event in
            event == .fourByFour ? PuzzleEvent.fourByFourCases : event == .fourByFourFast ? [] : [event]
        } + PuzzleEvent.blindfoldedCases
    }
    static func rotation(player: LocalBattlePlayer, mode: LocalBattleMode) -> Double {
        mode == .headToHead && player == .second ? 180 : 0
    }
}

/// Lives inside its owner's rotated panel, including the actual scroll/buttons.
/// The full panel backdrop consumes touches without blocking the other player.
struct BattleEventSelector: View {
    let selection: PuzzleEvent
    let size: CGSize
    let choose: (PuzzleEvent) -> Void
    let dismiss: () -> Void
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        ZStack {
            Button(action: dismiss) { Color.black.opacity(0.12).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("common.done"))
                .accessibilityIdentifier("battle-event-backdrop")
            VStack(spacing: 0) {
                HStack {
                    Text("timer.battle.choose_event")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($headingFocused)
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("common.done"))
                    .accessibilityIdentifier("battle-event-dismiss")
                }
                .padding(.leading, 16)
                Divider()
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(BattleEventSelectorPolicy.events, id: \.self) { event in
                                Button { choose(event) } label: {
                                    HStack(spacing: 12) {
                                        if let glyph = CompetitionEventIconFont.glyph(for: event.cubingEventID) {
                                            CompetitionEventGlyph(glyph: glyph, eventName: "", size: 20, color: .primary)
                                                .frame(width: 26).accessibilityHidden(true)
                                        }
                                        Text(LocalizedStringKey(event == .fourByFour ? "event.4x4_standard" : event.localizationKey))
                                            .multilineTextAlignment(.leading)
                                            .foregroundStyle(.primary)
                                        Spacer(minLength: 8)
                                        if event == selection {
                                            Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.blue)
                                        }
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 11)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(event == selection ? .isSelected : [])
                                .accessibilityIdentifier("battle-event-\(event.rawValue)")
                                .id(event)
                            }
                        }
                    }
                    .onAppear { reader.scrollTo(selection, anchor: .center) }
                    .onChange(of: selection) { reader.scrollTo($0, anchor: .center) }
                }
            }
            .frame(width: max(0, min(360, size.width - 24)), height: max(0, min(420, size.height - 24)))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, dismiss)
        .onAppear { headingFocused = true }
    }
}
#endif

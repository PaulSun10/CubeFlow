import SwiftUI

nonisolated struct CompetitionTopCuberProfileSelection: Identifiable, Hashable {
    let id: String
    let name: String

    init?(preview: CompetitionTopCuberPreview) {
        let value = preview.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: "^[0-9]{4}[A-Z]{4}[0-9]{2}$", options: .regularExpression) != nil else { return nil }
        id = value
        name = preview.name
    }
}

/// Replace the existing chip tap, without adding a Button inside the glass card's Button.
struct CompetitionTopCuberProfileChip: View {
    let preview: CompetitionTopCuberPreview
    let language: String
    let iconsReady: Bool
    let open: (CompetitionTopCuberProfileSelection) -> Void

    var body: some View {
        let chip = CompetitionTopCuberChip(preview: preview, language: language, iconsReady: iconsReady)
        if let selection = CompetitionTopCuberProfileSelection(preview: preview) {
            chip.contentShape(Rectangle())
                .onTapGesture { open(selection) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("competition-top-cuber-profile-" + selection.id)
        } else {
            chip
        }
    }
}

private struct CompetitionTopCuberProfileDestination: ViewModifier {
    @Binding var selection: CompetitionTopCuberProfileSelection?
    func body(content: Content) -> some View {
        content.background {
            // This is the same native full-page NavigationLink used by WCA
            // competitors and Explore, including on iOS 15 (never a sheet).
            NavigationLink(isActive: Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })) {
                if let selection {
                    WCAProfileView(wcaID: selection.id, displayName: selection.name)
                        .accessibilityIdentifier("competition-top-cuber-wca-profile-" + selection.id)
                }
            } label: { EmptyView() }.hidden()
        }
    }
}

extension View {
    func competitionTopCuberProfileDestination(selection: Binding<CompetitionTopCuberProfileSelection?>) -> some View {
        modifier(CompetitionTopCuberProfileDestination(selection: selection))
    }
}

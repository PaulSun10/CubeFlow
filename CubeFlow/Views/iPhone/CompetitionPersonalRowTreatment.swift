import SwiftUI

/// Drawing-only emphasis; existing row metrics, ranking colors and record badges remain intact.
struct CompetitionPersonalRowTreatment: ViewModifier {
    let isOwn: Bool
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .background(isOwn ? Color(uiColor: .systemBlue).opacity(scheme == .dark ? 0.10 : 0.055) : .clear)
            .overlay(alignment: .leading) {
                if isOwn {
                    Capsule().fill(Color(uiColor: .systemBlue).opacity(scheme == .dark ? 0.90 : 0.80))
                        .frame(width: 3).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
    }
}

struct CompetitionPersonalNameBadge: View {
    let language: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(PublishedCompetitionStrings.text("me", language))
            .font(.caption2.weight(.semibold)).foregroundStyle(.primary)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color(uiColor: .systemBlue).opacity(scheme == .dark ? 0.24 : 0.12), in: RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4).stroke(Color(uiColor: .systemBlue).opacity(scheme == .dark ? 0.45 : 0.28), lineWidth: 0.5)
            }
            .allowsHitTesting(false).accessibilityIdentifier("competition-personal-me")
    }
}

#if DEBUG
private struct CompetitionLivePreviewIdentityKey: EnvironmentKey { static let defaultValue: String? = nil }
private struct CompetitionLivePreviewTransportKey: EnvironmentKey { static let defaultValue: (any CubingChinaLiveTransport)? = nil }
private struct CompetitionLivePreviewDestinationKey: EnvironmentKey { static let defaultValue: String? = nil }
private struct CompetitionLivePreviewSheetKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    var competitionLivePreviewIdentity: String? {
        get { self[CompetitionLivePreviewIdentityKey.self] }
        set { self[CompetitionLivePreviewIdentityKey.self] = newValue }
    }
    var competitionLivePreviewTransport: (any CubingChinaLiveTransport)? {
        get { self[CompetitionLivePreviewTransportKey.self] }
        set { self[CompetitionLivePreviewTransportKey.self] = newValue }
    }
    var competitionLivePreviewDestination: String? {
        get { self[CompetitionLivePreviewDestinationKey.self] }
        set { self[CompetitionLivePreviewDestinationKey.self] = newValue }
    }
    var competitionLivePreviewSheet: String? {
        get { self[CompetitionLivePreviewSheetKey.self] }
        set { self[CompetitionLivePreviewSheetKey.self] = newValue }
    }
}
#endif

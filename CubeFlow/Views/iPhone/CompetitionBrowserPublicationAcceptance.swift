#if DEBUG
import SwiftUI
import Combine

private struct CompetitionBrowserPublicationEnabledKey: EnvironmentKey {
    static let defaultValue = false
}
private struct CompetitionBrowserPublicationScopeKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}
extension EnvironmentValues {
    var competitionBrowserPublicationEnabled: Bool {
        get { self[CompetitionBrowserPublicationEnabledKey.self] }
        set { self[CompetitionBrowserPublicationEnabledKey.self] = newValue }
    }
    var competitionBrowserPublicationScope: UUID? {
        get { self[CompetitionBrowserPublicationScopeKey.self] }
        set { self[CompetitionBrowserPublicationScopeKey.self] = newValue }
    }
}

@MainActor enum CompetitionBrowserPublicationAcceptance {
    static var cache: ((CompetitionQuery) async -> CompetitionCacheSnapshot?)?
    static var page: ((CompetitionQuery, Int) async throws -> CompetitionPageResult)?
    static var displayed: (([String]) -> Void)?
    static var published: ((CompetitionBrowserPublicationSnapshot) -> Void)?
    static var now: (() -> Date)?
    static let refreshRequests = PassthroughSubject<Void, Never>()
    static var checksRequestEpoch = true
    static var scope: UUID?
    static var ignoredForeignDisplays = 0
    static weak var filter: CompetitionFilterPresentation?
    static func reportDisplayed(_ ids: [String], scope owner: UUID?) {
        guard owner == scope else { ignoredForeignDisplays &+= 1; return }
        displayed?(ids)
    }
}

struct CompetitionBrowserPublicationSnapshot: Equatable {
    let revision: Int
    let signature: String
    let ids: [String]
    let sourceIDs: [String]
    let preparedIDs: [String]
    let isActive: Bool
    let phase: String
}

struct CompetitionBrowserPublicationKey: PreferenceKey {
    static var defaultValue: CompetitionBrowserPublicationSnapshot? = nil
    static func reduce(value: inout CompetitionBrowserPublicationSnapshot?,
                       nextValue: () -> CompetitionBrowserPublicationSnapshot?) {
        value = nextValue() ?? value
    }
}
#endif

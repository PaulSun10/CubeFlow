import SwiftUI
import Combine
import QuartzCore

@MainActor final class CompetitionListInteraction: ObservableObject {
    @Published private(set) var isActive = false
    func setActive(_ value: Bool) { if isActive != value { isActive = value } }
}
private struct CompetitionListInteractionKey: EnvironmentKey {
    static let defaultValue: CompetitionListInteraction? = nil
}
extension EnvironmentValues {
    var competitionListInteraction: CompetitionListInteraction? {
        get { self[CompetitionListInteractionKey.self] }
        set { self[CompetitionListInteractionKey.self] = newValue }
    }
}

enum CompetitionTopCuberLoadState: Equatable {
    case idle, loading, empty, failed
    case loaded([CompetitionTopCuberPreview])
}

@MainActor
final class CompetitionTopCubersLoader: ObservableObject {
    @Published private(set) var state: CompetitionTopCuberLoadState
    private var loading = false
    private var pendingState: CompetitionTopCuberLoadState?
    #if DEBUG
    private var diagnosticIdentity = ""
    #endif
    init(initial: CompetitionTopCuberLoadState = .idle) { state = initial }

    func load(cache: () async -> [CompetitionTopCuberPreview]?,
              fetch: () async -> [CompetitionTopCuberPreview]?, identity: String,
              interaction: CompetitionListInteraction? = nil, revalidateCached: Bool = false) async {
        guard !loading, pendingState == nil else { return }
        #if DEBUG
        diagnosticIdentity = identity
        #endif
        if !revalidateCached {
            if case .loaded = state { return }
            if state == .empty { return }
        }
        loading = true
        defer { loading = false }
        let start = CACurrentMediaTime()
        if let cached = await cache() {
            guard !Task.isCancelled else { return }
            publish(cached.isEmpty ? .empty : .loaded(cached), interaction: interaction)
            CompetitionLoadingTrace.record("top-cubers-cache", since: start, detail: identity)
            if !revalidateCached { return }
        }
        guard !Task.isCancelled else { return }
        let hasSavedState: Bool
        switch pendingState ?? state {
        case .loaded, .empty: hasSavedState = true
        default: hasSavedState = false
        }
        if !hasSavedState { state = .loading }
        let result = await fetch()
        guard !Task.isCancelled else { return }
        if let result { publish(result.isEmpty ? .empty : .loaded(result), interaction: interaction) }
        else if !hasSavedState { publish(.failed, interaction: interaction) }
        CompetitionLoadingTrace.record("top-cubers-fetch", since: start, detail: identity)
    }
    private func publish(_ value: CompetitionTopCuberLoadState, interaction: CompetitionListInteraction?) {
        guard value != (pendingState ?? state) else { return }
        #if DEBUG
        CompetitionScrollOwnerDiagnostics.loading(diagnosticIdentity, state: value,
            phase: interaction?.isActive == true ? "queued" : "published")
        #endif
        if interaction?.isActive == true { pendingState = value }
        else { pendingState = nil; state = value }
    }
    func publishPending() {
        guard let pendingState else { return }
        #if DEBUG
        CompetitionScrollOwnerDiagnostics.loading(diagnosticIdentity, state: pendingState, phase: "published-after-idle")
        #endif
        self.pendingState = nil
        state = pendingState
    }
}

struct CompetitionLoadedTopCubers<Content: View, Placeholder: View>: View {
    let competition: CompetitionSummary
    let language: String
    let topSpacing: CGFloat
    let onState: (CompetitionTopCuberLoadState) -> Void
    @ViewBuilder let content: ([CompetitionTopCuberPreview]) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    @StateObject private var loader: CompetitionTopCubersLoader
    @Environment(\.competitionListInteraction) private var interaction
    private let cache: ((String) async -> [CompetitionTopCuberPreview]?)?
    private let fetch: ((CompetitionSummary, String) async -> [CompetitionTopCuberPreview]?)?

    init(competition: CompetitionSummary, language: String, initial: CompetitionTopCuberLoadState,
         topSpacing: CGFloat = 0,
         onState: @escaping (CompetitionTopCuberLoadState) -> Void,
         cache: ((String) async -> [CompetitionTopCuberPreview]?)? = nil,
         fetch: ((CompetitionSummary, String) async -> [CompetitionTopCuberPreview]?)? = nil,
         @ViewBuilder content: @escaping ([CompetitionTopCuberPreview]) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.competition = competition; self.language = language; self.topSpacing = topSpacing; self.onState = onState
        self.content = content; self.placeholder = placeholder
        self.cache = cache; self.fetch = fetch
        _loader = StateObject(wrappedValue: CompetitionTopCubersLoader(initial: initial))
    }

    var body: some View {
        if loader.state != .empty {
            // An empty Group has no mounted child to own task/onReceive from the idle state.
            VStack(alignment: .leading, spacing: 8) {
                switch loader.state {
                case .loaded(let values): content(values)
                case .loading: placeholder()
                default: EmptyView()
                }
            }
            // An idle observer must mount its task without adding a section gap.
            // Only real content (including a loading placeholder) owns separation.
            .padding(.top, hasVisibleContent ? topSpacing : 0)
            .onReceive(loader.$state) {
                #if DEBUG
                CompetitionScrollOwnerDiagnostics.loading(competition.id, state: $0, phase: "visible")
                #endif
                onState($0)
            }
                .onReceive(interaction?.$isActive.eraseToAnyPublisher() ?? Just(false).eraseToAnyPublisher()) { active in
                    if !active { loader.publishPending() }
                }
                .task(id: "\(competition.id)|\(language)") {
                    await loader.load(cache: {
                        if let cache { return await cache(competition.id) }
                        return await CompetitionService.cachedCompetitionTopCuberPreviews(for: competition.id, eventIDs: competition.eventIDs)
                    }, fetch: {
                        if let fetch { return await fetch(competition, language) }
                        return await CompetitionService.fetchCompetitionTopCuberPreviews(for: competition, languageCode: language)
                    }, identity: competition.id, interaction: interaction, revalidateCached: cache == nil && fetch == nil)
                }
        }
    }
    private var hasVisibleContent: Bool {
        switch loader.state {
        case .loading, .loaded: return true
        default: return false
        }
    }
}

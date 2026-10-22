#if os(iOS)
import SwiftUI

struct ExploreCompetitionSearchContext {
    let usesSystemBottomAccessory: Bool
    let isVisible: Binding<Bool>
    let requestID: Binding<Int>
}

private struct ExploreCompetitionSearchContextKey: EnvironmentKey {
    static let defaultValue: ExploreCompetitionSearchContext? = nil
}

extension EnvironmentValues {
    var exploreCompetitionSearchContext: ExploreCompetitionSearchContext? {
        get { self[ExploreCompetitionSearchContextKey.self] }
        set { self[ExploreCompetitionSearchContextKey.self] = newValue }
    }
}

struct ExploreView: View {
    let isActive: Bool
    let competitionRequestID: Int
    let usesSystemBottomAccessory: Bool
    @Binding var isCompetitionBottomAccessoryVisible: Bool
    @Binding var searchRequestID: Int
    @AppStorage("appLanguage") private var language = "en"
    @StateObject private var store = ExploreStore()
    @StateObject private var wcaAuth = WCAAuthManager.shared
    @State private var resolvedWCAID: String?
    @State private var showsRequestedCompetitions = false
    @State private var showsSearch = false
    @State private var showsRecentRecords = false
    @State private var homeDestination: ExploreBrowseDestination?
    @State private var handledCompetitionRequestID = 0

    private var signedInWCAID: String? {
        wcaAuth.isSignedIn ? wcaAuth.profile?.wcaId : nil
    }

    var body: some View {
        CompatibleNavigationContainer {
            List {
                status.modifier(ExploreHomeRow())
                ForEach(store.modules) { module in
                    ExploreModuleView(module: module, store: store, language: language)
                        .modifier(ExploreHomeRow())
                }
                if !store.modules.contains(where: { $0.id == "records.recent" }) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button { showsRecentRecords = true } label: {
                            HStack(spacing: 4) {
                                ExploreHeading(title: appLocalizedString("explore.public.recent_records",
                                    languageCode: language, tableName: "ExplorePublicData"))
                                ExploreChevron(isSectionHeading: true)
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("explore-see-all-records.recent")
                        if store.recordsState == .loading { ProgressView() }
                        else {
                            Text(store.recordsState == .failed
                                ? appLocalizedString("explore.unavailable", languageCode: language)
                                : store.recentRecords.isEmpty
                                    ? appLocalizedString("explore.public.empty", languageCode: language, tableName: "ExplorePublicData")
                                    : appLocalizedString("explore.see_all", languageCode: language))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.modifier(ExploreHomeRow())
                }
                if let history = ExploreHistory.bundled {
                    discovery(history).modifier(ExploreHomeRow())
                    statistics(history).modifier(ExploreHomeRow())
                }
                ExploreBrowseSection(language: language) { homeDestination = $0 }
                    .modifier(ExploreHomeRow())
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
            .modifier(ExploreHomeListStyle())
            .background {
                NavigationLink(isActive: Binding(
                    get: { homeDestination != nil }, set: { if !$0 { homeDestination = nil } }
                )) {
                    if let homeDestination { ExploreBrowseView(destination: homeDestination) }
                } label: { EmptyView() }.hidden()
            }
            .navigationTitle("tab.explore")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel(Text("explore.search"))
                }
            }
            .refreshable {
                async let competitions: Void = store.load(language: language, force: true)
                async let records: Void = store.loadRecentRecords(language: language, force: true)
                _ = await (competitions, records)
            }
            .task(id: "\(isActive)|\(language)|\(signedInWCAID ?? "")") {
                guard isActive else { return }
                if let wcaID = signedInWCAID, resolvedWCAID != wcaID {
                    store.setWCARegionCode(nil)
                    do {
                        let identity = try await WCAResultsService.fetchPersonIdentity(wcaId: wcaID)
                        guard !Task.isCancelled, signedInWCAID == wcaID else { return }
                        store.setWCARegionCode(identity.countryISO2)
                        resolvedWCAID = wcaID
                    } catch is CancellationError {
                        return
                    } catch {
                        // Public identity is optional; Browse and search still work without it.
                    }
                } else if signedInWCAID == nil {
                    resolvedWCAID = nil
                    store.setWCARegionCode(nil)
                }
                guard !Task.isCancelled else { return }
                async let competitions: Void = store.load(language: language)
                async let records: Void = store.loadRecentRecords(language: language)
                _ = await (competitions, records)
            }
            .onChange(of: competitionRequestID) { _ in handleCompetitionRequest() }
            .onAppear { handleCompetitionRequest() }
            .compatibleNavigationDestination(isPresented: $showsRequestedCompetitions) {
                ExploreBrowseView(destination: .competitions)
            }
            .compatibleNavigationDestination(isPresented: $showsSearch) {
                ExploreSearchView(store: store, language: language)
            }
            .compatibleNavigationDestination(isPresented: $showsRecentRecords) {
                ExploreRecentRecordsView(store: store, language: language)
            }
        }
        .environment(\.exploreCompetitionSearchContext, ExploreCompetitionSearchContext(
            usesSystemBottomAccessory: usesSystemBottomAccessory,
            isVisible: $isCompetitionBottomAccessoryVisible,
            requestID: $searchRequestID
        ))
    }

    private func discovery(_ history: ExploreHistory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { homeDestination = .highlights } label: {
                HStack(spacing: 4) {
                    ExploreHeading(title: exploreHomeString("discover", language: language))
                    ExploreChevron(isSectionHeading: true)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { homeDestination = .highlights } label: {
                ExploreSurface {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(exploreHomeString("northernmost", language: language))
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        if let place = history.northernmost.first {
                            if let latitude = place.latitude, let longitude = place.longitude {
                                ExplorePlaceMap(latitude: latitude, longitude: longitude)
                                    .frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 12))
                                    .allowsHitTesting(false).accessibilityHidden(true)
                            }
                            Text(place.name).font(.headline)
                            Text(place.city).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text(exploreHomeString("interesting", language: language))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.foregroundStyle(.primary)
            }.buttonStyle(.plain)
        }
    }

    private func statistics(_ history: ExploreHistory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { homeDestination = .stats } label: {
                HStack(spacing: 4) {
                    ExploreHeading(title: appLocalizedString("explore.stats", languageCode: language))
                    ExploreChevron(isSectionHeading: true)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { homeDestination = .stats } label: {
                ExploreSurface {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(history.completedCount.formatted()).font(.title3.weight(.semibold)).monospacedDigit()
                            Text(exploreHomeString("competitions_held", language: language)).font(.subheadline)
                            Text(String(format: exploreHomeString("history_as_of", language: language), history.exportDate))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                    }
                }.foregroundStyle(.primary)
            }.buttonStyle(.plain)
        }
    }

    private func handleCompetitionRequest() {
        guard competitionRequestID > handledCompetitionRequestID else { return }
        handledCompetitionRequestID = competitionRequestID
        showsRequestedCompetitions = true
    }

    @ViewBuilder private var status: some View {
        if store.modules.isEmpty && (store.state == .loading || store.state == .failed) {
            ExploreSurface {
                VStack(alignment: .leading, spacing: 8) {
                    if store.state == .loading {
                        Text("explore.loading").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("explore.unavailable")
                            .font(.headline)
                        Text("explore.unavailable_body")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if store.canRetry { retry }
                }
            }
        } else if store.showsSavedDataNotice {
            ExploreSurface {
                VStack(alignment: .leading, spacing: 0) {
                    if let date = store.fetchedAt {
                        (Text("explore.saved_updated", tableName: "ExploreHome") + Text(" ") + Text(date, style: .date))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if store.canRetry { retry }
                }
            }
        }
    }

    private var retry: some View {
        Button("explore.retry") {
            Task { await store.load(language: language, force: true) }
        }
        .font(.subheadline)
        .frame(minHeight: 44)
    }
}

struct ExploreBrowseSection: View {
    let language: String
    let select: (ExploreBrowseDestination) -> Void
    @ScaledMetric(relativeTo: .body) private var rowHeight = 66

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ExploreHeading(title: appLocalizedString("explore.browse", languageCode: language))
            VStack(spacing: 0) {
                ForEach(ExploreBrowseDestination.allCases) { destination in
                    if destination != ExploreBrowseDestination.allCases.first { Divider() }
                    Button { select(destination) } label: {
                        HStack {
                            Group {
                                if destination == .highlights { Text(exploreHomeString("interesting", language: language)) }
                                else { Text(LocalizedStringKey(destination.titleKey)) }
                            }
                            Spacer(minLength: 8)
                            ExploreChevron()
                        }
                        .font(.body).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("explore-browse-\(destination.rawValue)")
                }
            }
        }
    }
}

struct ExploreBrowseView: View {
    let destination: ExploreBrowseDestination
    @Environment(\.exploreCompetitionSearchContext) private var searchContext
    @AppStorage("appLanguage") private var language = "en"
    @ViewBuilder
    var body: some View {
        switch destination {
        case .competitions:
            if let searchContext {
                CompetitionBrowserView(
                    usesSystemBottomAccessory: searchContext.usesSystemBottomAccessory,
                    isBottomAccessoryVisible: searchContext.isVisible,
                    searchRequestID: searchContext.requestID
                )
            } else {
                CompetitionBrowserView()
            }
        case .rankings:
            ExploreRankingsView(language: language)
        case .records:
            ExploreRecordsView(language: language)
        case .stats: ExploreStatsView(language: language)
        case .highlights: ExploreDiscoveriesView(language: language)
        }
    }
}

private struct ExploreSearchView: View {
    @ObservedObject var store: ExploreStore
    let language: String
    @State private var query = ""

    private var results: [CompetitionSummary] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return [] }
        return store.competitions.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.locationLine.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            Section {
                Text("explore.search_scope")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                NavigationLink {
                    ExploreBrowseView(destination: .competitions)
                } label: {
                    Text("explore.all_competitions")
                }
            }
            Section {
                ForEach(results) { competition in
                    NavigationLink {
                        CompetitionDetailView(competition: competition, appLanguage: language)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(competition.name).font(.headline)
                            Text(competition.locationLine).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                if !query.isEmpty && results.isEmpty {
                    Text("explore.no_results").foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $query, prompt: Text("explore.search_prompt"))
        .navigationTitle("explore.search")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

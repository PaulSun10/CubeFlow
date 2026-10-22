import Foundation
import Combine

nonisolated struct ExploreCompetitionSnapshot: Codable, Sendable {
    let competitions: [CompetitionSummary]
    let fetchedAt: Date
}

@MainActor
protocol ExploreCompetitionProviding {
    func cached(language: String, regionCode: String?) async -> ExploreCompetitionSnapshot?
    func refresh(language: String, regionCode: String?) async throws -> ExploreCompetitionSnapshot
}

/// Shares WCA requests and browser caches; stores a bounded Home snapshot
/// separately so a first-page refresh never overwrites the browser's full cache.
struct ExploreCompetitionProvider: ExploreCompetitionProviding {
    func cached(language: String, regionCode: String?) async -> ExploreCompetitionSnapshot? {
        let own = await ExploreCompetitionCache.shared.load(language: language, regionCode: regionCode)
        let browser = await CompetitionService.cachedCompetitions(for: query(language, regionCode: regionCode))
        if let browser, browser.lastUpdated > (own?.fetchedAt ?? .distantPast) {
            return ExploreCompetitionSnapshot(competitions: Array(browser.competitions.prefix(100)), fetchedAt: browser.lastUpdated)
        }
        return own
    }

    func refresh(language: String, regionCode: String?) async throws -> ExploreCompetitionSnapshot {
        let query = query(language, regionCode: regionCode)
        return try await ExploreCompetitionCache.shared.refresh(language: language, regionCode: regionCode) {
            try await CompetitionService.fetchCompetitionsPage(query: query, page: 1).competitions
        }
    }

    func query(_ language: String, regionCode: String?) -> CompetitionQuery {
        CompetitionQuery(languageCode: language, region: regionCode.map(CompetitionRegionFilter.country) ?? .all,
                         events: Set(CompetitionEventFilter.selectableCases), year: .all, status: .present)
    }
}

actor ExploreCompetitionCache {
    static let shared = ExploreCompetitionCache()
    nonisolated static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CubeFlowExplore", isDirectory: true)
    }
    nonisolated static var diskBytes: Int64 { PublicDataSnapshotStore.diskBytes(at: directory) }
    private let storage: PublicDataSnapshotStore
    private let root: URL
    private let now: @Sendable () -> Date
    private let requests = CompetitionRequestPool<ExploreCompetitionSnapshot>()
    private var generation = UUID()
    init(directory: URL = ExploreCompetitionCache.directory, now: @escaping @Sendable () -> Date = { Date() }) {
        root = directory; self.now = now
        storage = PublicDataSnapshotStore(directory: directory, countLimit: 24, diskLimit: 8 * 1024 * 1024,
            entryLimit: 2 * 1024 * 1024, memoryLimit: 4 * 1024 * 1024, retention: 30 * 86400, now: now)
    }
    nonisolated static func key(language: String, regionCode: String?) -> String {
        PublicDataSnapshotStore.key(["wca", "home-competitions-v3", language, regionCode ?? "all",
            "present", "all-events", "all-years", "page-1"])
    }
    func clear() async {
        generation = UUID()
        await requests.cancelAll(); await storage.clear()
    }
    func refresh(language: String, regionCode: String?,
                 loader: @escaping @Sendable () async throws -> [CompetitionSummary]) async throws -> ExploreCompetitionSnapshot {
        let epoch = generation
        return try await requests.value(key: Self.key(language: language, regionCode: regionCode)) { [self] in
            let rows = try await loader()
            return try await commit(rows, language: language, regionCode: regionCode, epoch: epoch)
        }
    }
    private func commit(_ rows: [CompetitionSummary], language: String, regionCode: String?, epoch: UUID) async throws -> ExploreCompetitionSnapshot {
        try Task.checkCancellation()
        guard generation == epoch else { throw CancellationError() }
        let value = ExploreCompetitionSnapshot(competitions: rows, fetchedAt: now())
        await save(value, language: language, regionCode: regionCode)
        try Task.checkCancellation()
        guard generation == epoch else { throw CancellationError() }
        return value
    }
    func load(language: String, regionCode: String?) async -> ExploreCompetitionSnapshot? {
        let epoch = generation
        let key = Self.key(language: language, regionCode: regionCode)
        await storage.maintain()
        if let entry = await storage.load(key), let value = try? JSONDecoder().decode(ExploreCompetitionSnapshot.self, from: entry.body) {
            return generation == epoch ? value : nil
        }
        // Only the app's finite language + ISO region domain has a provably exact old path.
        guard ["en", "zh-Hans", "zh-Hant"].contains(language),
              regionCode == nil || (regionCode?.count == 2 && Locale.isoRegionCodes.contains(regionCode!)) else { return nil }
        let legacy = root.appendingPathComponent("competitions-v2-\(language)-\(regionCode ?? "all").json")
        guard let size = try? legacy.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2 * 1024 * 1024,
              let body = try? Data(contentsOf: legacy),
              let value = try? JSONDecoder().decode(ExploreCompetitionSnapshot.self, from: body) else { return nil }
        guard generation == epoch else { return nil }
        if await storage.save(body, key: key, fetchedAt: value.fetchedAt) {
            try? FileManager.default.removeItem(at: legacy)
            return value
        }
        return nil
    }
    func save(_ snapshot: ExploreCompetitionSnapshot, language: String, regionCode: String?) async {
        guard let body = try? JSONEncoder().encode(snapshot) else { return }
        await storage.save(body, key: Self.key(language: language, regionCode: regionCode), fetchedAt: snapshot.fetchedAt)
        let legacy = root.appendingPathComponent("competitions-v2-\(language)-\(regionCode ?? "all").json")
        // Retire only the exact known legacy identity after a successful v3 write.
        if ["en", "zh-Hans", "zh-Hant"].contains(language),
           regionCode == nil || (regionCode?.count == 2 && Locale.isoRegionCodes.contains(regionCode!)),
           await storage.load(Self.key(language: language, regionCode: regionCode)) != nil {
            try? FileManager.default.removeItem(at: legacy)
        }
    }
}

nonisolated struct ExploreRecentRecordsSnapshot: Codable, Sendable {
    let records: [WCARecentRecord]
    let fetchedAt: Date
    var hasPartialFailure: Bool? = nil
}

@MainActor
protocol ExploreRecentRecordsProviding {
    func cached() async -> ExploreRecentRecordsSnapshot?
    func refresh() async throws -> ExploreRecentRecordsSnapshot
}

struct ExploreRecentRecordsProvider: ExploreRecentRecordsProviding {
    private let cacheKey = "wca-recent-records-v2"

    func cached() async -> ExploreRecentRecordsSnapshot? {
        guard let cached = await WCAExplorePublicDataCache.shared.load([WCARecentRecord].self, key: cacheKey) else {
            return nil
        }
        return ExploreRecentRecordsSnapshot(records: cached.value, fetchedAt: cached.fetchedAt)
    }

    func refresh() async throws -> ExploreRecentRecordsSnapshot {
        try await WCAExplorePublicDataCache.shared.recentRecords(key: cacheKey) {
            try await loadSources()
        }
    }

    private func loadSources() async throws -> ExploreRecentRecordsSnapshot {
        async let live = WCAExplorePublicDataService.fetchRecentRecords()
        async let official = WCAExplorePublicDataService.fetchRecords(
            WCARecordsQuery(region: .all, gender: .all, show: .history), force: true)
        let liveRows = try? await live
        let officialRows = try? await official
        try Task.checkCancellation()
        guard liveRows != nil || officialRows != nil else { throw URLError(.cannotLoadFromNetwork) }
        let partialFailure = liveRows == nil || officialRows == nil
        let previous = partialFailure ? await cached() : nil
        let records = ExploreRecentRecordMerge.merge(live: liveRows ?? previous?.records.filter { $0.officialResult == nil } ?? [],
            official: officialRows?.records.values.flatMap { $0 } ?? previous?.records.compactMap(\.officialResult) ?? [])
        let fetchedAt = Date()
        return ExploreRecentRecordsSnapshot(records: records, fetchedAt: fetchedAt, hasPartialFailure: partialFailure)
    }
}

nonisolated enum ExploreLoadState: Equatable {
    case loading, loaded, empty, stale, failedWithCache, failed
}

@MainActor
final class ExploreStore: ObservableObject {
    @Published private(set) var modules: [ExploreModule] = []
    @Published private(set) var state: ExploreLoadState = .loading
    @Published private(set) var isRefreshing = false
    @Published private(set) var fetchedAt: Date?
    private(set) var competitions: [CompetitionSummary] = []
    private let provider: any ExploreCompetitionProviding
    private let recentRecordsProvider: any ExploreRecentRecordsProviding
    private var language: String?
    private var lastAttempt: Date?
    private var supplementalCandidates: [ExploreCandidate] = []
    private var recentRecordCandidates: [ExploreCandidate] = []
    @Published private(set) var recentRecords: [WCARecentRecord] = []
    @Published private(set) var recordsState: ExploreLoadState = .loading
    private var recentRecordsLanguage: String?
    @Published private(set) var recentRecordsFetchedAt: Date?
    private var recordsLoadID = UUID()
    private var isLoadingRecords = false
    private var loadID = UUID()
    private var compositionNow = Date()
    private var wcaRegionCode: String?

    var showsSavedDataNotice: Bool {
        state == .failedWithCache && !isRefreshing && !modules.isEmpty
            && fetchedAt.map { compositionNow.timeIntervalSince($0) > 24 * 3600 } == true
    }

    var canRetry: Bool {
        !isRefreshing && (state == .failed || showsSavedDataNotice)
    }

    init(
        provider: (any ExploreCompetitionProviding)? = nil,
        recentRecordsProvider: (any ExploreRecentRecordsProviding)? = nil,
        wcaRegionCode: String? = nil
    ) {
        self.provider = provider ?? ExploreCompetitionProvider()
        self.recentRecordsProvider = recentRecordsProvider ?? ExploreRecentRecordsProvider()
        self.wcaRegionCode = wcaRegionCode
    }

    func setWCARegionCode(_ regionCode: String?, now: Date = Date()) {
        let normalized = regionCode?.uppercased()
        guard wcaRegionCode != normalized else { return }
        wcaRegionCode = normalized
        loadID = UUID()
        isRefreshing = false
        lastAttempt = nil
        fetchedAt = nil
        competitions = []
        compose(now: now)
        state = modules.isEmpty ? .loading : .loaded
    }

    func load(language: String, force: Bool = false, now: Date = Date()) async {
        guard !isRefreshing || self.language != language else { return }
        if self.language == language, !force, let lastAttempt,
           now.timeIntervalSince(lastAttempt) < 300 {
            compose(now: now)
            return
        }
        isRefreshing = true
        let requestID = UUID()
        loadID = requestID
        defer { if loadID == requestID { isRefreshing = false } }
        if self.language != language {
            self.language = language
            lastAttempt = nil
            fetchedAt = nil
            competitions = []
            compose(now: now)
        }
        if fetchedAt == nil, let cached = await provider.cached(language: language, regionCode: wcaRegionCode) {
            guard loadID == requestID else { return }
            apply(cached, now: now)
            state = now.timeIntervalSince(cached.fetchedAt) > 6 * 3600 ? .stale : .loaded
        }
        guard loadID == requestID else { return }
        if !force, let fetchedAt, now.timeIntervalSince(fetchedAt) < 6 * 3600 {
            compose(now: now)
            state = modules.isEmpty ? .empty : .loaded
            return
        }
        lastAttempt = now
        if fetchedAt == nil { state = .loading }
        do {
            let snapshot = try await provider.refresh(language: language, regionCode: wcaRegionCode)
            guard loadID == requestID else { return }
            try Task.checkCancellation()
            apply(snapshot, now: now)
            state = modules.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            guard loadID == requestID else { return }
            lastAttempt = nil
            state = fetchedAt == nil ? .loading : .stale
        } catch {
            guard loadID == requestID else { return }
            compose(now: now)
            // A valid snapshot with no relevant candidates is an editorial empty state,
            // not a page failure. Irrelevant cached competitions must not become filler.
            state = modules.isEmpty ? (fetchedAt == nil ? .failed : .empty) : .failedWithCache
        }
    }

    func competition(id: String) -> CompetitionSummary? {
        competitions.first { $0.id == id }
    }

    func loadRecentRecords(language: String, force: Bool = false, now: Date = Date()) async {
        let changedLanguage = recentRecordsLanguage != language
        recentRecordsLanguage = language
        if changedLanguage, !recentRecords.isEmpty {
            recentRecordCandidates = WCAExplorePublicDataService.recentRecordsCandidate(recentRecords, language: language)
            compose(now: now)
        }
        if !force, recordsState != .failedWithCache, let recentRecordsFetchedAt, now.timeIntervalSince(recentRecordsFetchedAt) < 15 * 60 {
            return
        }
        guard !isLoadingRecords else { return }
        isLoadingRecords = true
        let requestID = UUID()
        recordsLoadID = requestID
        defer { if recordsLoadID == requestID { isLoadingRecords = false } }
        if recentRecords.isEmpty { recordsState = .loading }
        if recentRecordsFetchedAt == nil, let cached = await recentRecordsProvider.cached() {
            guard recordsLoadID == requestID, !Task.isCancelled else { return }
            recentRecordsFetchedAt = cached.fetchedAt
            recentRecords = cached.records
            recentRecordCandidates = WCAExplorePublicDataService.recentRecordsCandidate(recentRecords,
                language: recentRecordsLanguage ?? language)
            compose(now: now)
            recordsState = now.timeIntervalSince(cached.fetchedAt) >= 900 ? .stale : (recentRecords.isEmpty ? .empty : .loaded)
        }
        if !force, recordsState != .failedWithCache, let recentRecordsFetchedAt, now.timeIntervalSince(recentRecordsFetchedAt) < 15 * 60 {
            return
        }
        do {
            let snapshot = try await recentRecordsProvider.refresh()
            try Task.checkCancellation()
            guard recordsLoadID == requestID else { return }
            recentRecordsFetchedAt = snapshot.fetchedAt
            recentRecords = snapshot.records
            recentRecordCandidates = WCAExplorePublicDataService.recentRecordsCandidate(recentRecords,
                language: recentRecordsLanguage ?? language)
            compose(now: now)
            recordsState = snapshot.hasPartialFailure == true ? .failedWithCache : (recentRecords.isEmpty ? .empty : .loaded)
        } catch is CancellationError {
            guard recordsLoadID == requestID else { return }
            recordsState = recentRecords.isEmpty ? .empty : .stale
            return
        } catch {
            guard recordsLoadID == requestID else { return }
            recordsState = recentRecords.isEmpty ? .failed : .failedWithCache
        }
    }

    var recentRecordItems: [ExploreItem] {
        WCAExplorePublicDataService.recentRecordsCandidate(recentRecords, language: recentRecordsLanguage ?? "en")
            .first(where: { $0.id == "records.recent" })?.items ?? []
    }

    /// Each source supplies independent candidates; one failure can omit that
    /// source while other available content continues to compose normally.
    func setSupplementalCandidates(_ candidates: [ExploreCandidate], now: Date) {
        supplementalCandidates = candidates
        compose(now: now)
    }

    private func apply(_ snapshot: ExploreCompetitionSnapshot, now: Date) {
        competitions = snapshot.competitions
        fetchedAt = snapshot.fetchedAt
        compose(now: now)
    }

    private func compose(now: Date) {
        compositionNow = now
        modules = ExploreComposer.compose(
            ExploreCompetitionCandidates.make(competitions, now: now, wcaRegionCode: wcaRegionCode)
                + recentRecordCandidates + supplementalCandidates,
            context: ExploreCompositionContext(now: now, wcaRegionCode: wcaRegionCode)
        )
    }
}

nonisolated enum ExploreCompetitionCandidates {
    static func make(_ competitions: [CompetitionSummary], now: Date, wcaRegionCode: String? = nil) -> [ExploreCandidate] {
        // Region means a verified public WCA country/region, never locale or GPS.
        let region = wcaRegionCode.flatMap { value -> String? in
            let normalized = value.uppercased()
            return normalized.count == 2 && Locale.isoRegionCodes.contains(normalized) ? normalized : nil
        }
        let query = CompetitionQuery(languageCode: "en", region: .all,
            events: Set(CompetitionEventFilter.selectableCases), year: .all, status: .present)
        let upcoming = CompetitionService.filterCompetitions(competitions, for: query, now: now)
            .filter { region == nil || $0.countryISO2.uppercased() == region }
            .sorted { $0.startDate == $1.startDate ? $0.id < $1.id : $0.startDate < $1.startDate }
        guard !upcoming.isEmpty else { return [] }
        return [ExploreCandidate(id: region == nil ? "competition.upcoming" : "competition.nearby",
            titleKey: region == nil ? "explore.upcoming" : "explore.in_region",
            items: upcoming.prefix(8).map { item($0, now: now) }, presentation: .carousel,
            importance: 30, regionCode: region, seeAll: .competitions, titleTable: "ExploreHome")]
    }

    private static func item(_ competition: CompetitionSummary, now: Date) -> ExploreItem {
        let registrationOpen = competition.registrationStatus == .open
            && competition.registrationOpen.map { $0 <= now } == true
            && competition.registrationClose.map { $0 > now } == true
        return ExploreItem(id: "competition.\(competition.id)", content: .competition(id: competition.id),
            title: competition.name, subtitle: competition.locationLine, date: competition.startDate,
            competition: ExploreCompetitionPresentation(start: competition.startDate, end: competition.endDate,
                eventCount: competition.eventIDs.count, registrationOpen: registrationOpen,
                eventIDs: competition.eventIDs))
    }
}

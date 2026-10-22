import Foundation

nonisolated struct WCAPublicIdentityResponse: Sendable {
    let identity: WCAPersonProfileIdentity
    let complete: Bool
}

/// Public, typed fields only. Authenticated profile/Keychain storage is unrelated.
actor WCAPublicProfileCache {
    static let shared = WCAPublicProfileCache()
    nonisolated static let pageFreshness: TimeInterval = 15 * 60
    nonisolated static let identityFreshness: TimeInterval = 3600
    nonisolated static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CubeFlow/wca-public-profiles-v2", isDirectory: true)
    }
    private struct LegacyPage: Codable { let page: WCAPersonResultsPage; let lastUpdated: Date }
    private struct StoredIdentity: Codable, Sendable {
        let identity: WCAPersonProfileIdentity
        let complete: Bool
    }
    private let storage: PublicDataSnapshotStore
    private let pages = CompetitionRequestPool<WCAPersonResultsPage>()
    private let identities = CompetitionRequestPool<WCAPersonProfileIdentity>()
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let legacyURL: URL?
    private var migration: Task<Void, Never>?
    private var generation = UUID()
    private let pageLoader: (@Sendable (String, String) async throws -> WCAPersonResultsPage)?
    private let identityLoader: (@Sendable (String) async throws -> WCAPublicIdentityResponse)?

    init(directory: URL = WCAPublicProfileCache.directory, legacyURL: URL? = nil,
         session: URLSession? = nil, now: @escaping @Sendable () -> Date = { Date() },
         pageLoader: (@Sendable (String, String) async throws -> WCAPersonResultsPage)? = nil,
         identityLoader: (@Sendable (String) async throws -> WCAPublicIdentityResponse)? = nil) {
        storage = PublicDataSnapshotStore(directory: directory, countLimit: 64, diskLimit: 32 * 1024 * 1024,
            retention: 30 * 86400, now: now)
        self.legacyURL = legacyURL ?? (directory == Self.directory
            ? directory.deletingLastPathComponent().appendingPathComponent("wca-person-results-cache-v1.json") : nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        self.session = session ?? URLSession(configuration: configuration)
        self.now = now; self.pageLoader = pageLoader; self.identityLoader = identityLoader
    }

    nonisolated static func canonicalID(_ input: String) -> String? {
        let id = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return id.range(of: #"^[0-9]{4}[A-Z]{4}[0-9]{2}$"#, options: .regularExpression) != nil ? id : nil
    }
    nonisolated static func key(_ resource: String, _ id: String, _ language: String = "") -> String {
        PublicDataSnapshotStore.key(["wca-public", "v2", resource, id, language])
    }

    func cachedPage(_ input: String, language: String) async -> WCAResultsService.CachedPersonResultsSnapshot? {
        guard let id = Self.canonicalID(input) else { return nil }
        let epoch = generation
        await migrate()
        guard let entry = await storage.load(Self.key("page", id, language)),
              let page = try? JSONDecoder().decode(WCAPersonResultsPage.self, from: entry.body),
              generation == epoch, Self.canonicalID(page.summary.wcaId) == id, page.contentLanguage == language else { return nil }
        return WCAResultsService.CachedPersonResultsSnapshot(page: page, lastUpdated: entry.fetchedAt)
    }

    func page(_ input: String, language: String, force: Bool = false) async throws -> WCAPersonResultsPage {
        guard let id = Self.canonicalID(input) else { throw WCAResultsFetchError.missingWCAID }
        let epoch = generation
        if !force, let cached = await cachedPage(id, language: language),
           generation == epoch, now().timeIntervalSince(cached.lastUpdated) < Self.pageFreshness { return cached.page }
        guard generation == epoch else { throw CancellationError() }
        let key = Self.key("page", id, language)
        return try await pages.value(key: key) { [self] in
            let page: WCAPersonResultsPage
            if let pageLoader { page = try await pageLoader(id, language) }
            else {
                var request = URLRequest(url: URL(string: "https://www.worldcubeassociation.org/persons/\(id)")!)
                request.timeoutInterval = 25
                request.setValue(appAcceptLanguageHeader(for: language), forHTTPHeaderField: "Accept-Language")
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode,
                      let html = String(data: data, encoding: .utf8) else { throw WCAResultsFetchError.requestFailed }
                page = try WCAResultsService.parsePersonResultsHTML(html, requestedLanguageCode: language)
            }
            guard Self.canonicalID(page.summary.wcaId) == id, page.contentLanguage == language else {
                throw WCAResultsFetchError.invalidHTML
            }
            try await self.persist(page, key: key, epoch: epoch)
            return page
        }
    }

    func identity(_ input: String, force: Bool = false) async throws -> WCAPersonProfileIdentity {
        guard let id = Self.canonicalID(input) else { throw WCAResultsFetchError.missingWCAID }
        let epoch = generation, key = Self.key("identity", id)
        let entry = await storage.load(key)
        let stored = entry.flatMap { entry -> StoredIdentity? in
            guard let value = try? JSONDecoder().decode(StoredIdentity.self, from: entry.body),
                  Self.canonicalID(value.identity.wcaId) == id else { return nil }
            return value
        }
        let cached = stored?.identity
        guard generation == epoch else { throw CancellationError() }
        if !force, stored?.complete == true, let cached, let entry,
           now().timeIntervalSince(entry.fetchedAt) < Self.identityFreshness { return cached }
        return try await identities.value(key: key) { [self] in
            do {
                let response: WCAPublicIdentityResponse
                if let identityLoader { response = try await identityLoader(id) }
                else { response = try await WCAResultsService.loadPublicIdentity(wcaId: id, session: session) }
                try Task.checkCancellation()
                guard await self.isCurrent(epoch) else { throw CancellationError() }
                guard Self.canonicalID(response.identity.wcaId) == id else { throw WCAResultsFetchError.invalidHTML }
                if response.complete {
                    try await self.persist(StoredIdentity(identity: response.identity, complete: true), key: key, epoch: epoch)
                } else if let cached {
                    return cached // A failed roles fetch is not an authoritative role deletion or a new validation date.
                } else {
                    // A cold successful public base response is still useful offline.
                    // Persist its incompleteness explicitly so roles are retried, not treated as verified empty.
                    try await self.persist(StoredIdentity(identity: response.identity, complete: false), key: key, epoch: epoch)
                }
                return response.identity
            } catch {
                try Task.checkCancellation()
                guard await self.isCurrent(epoch) else { throw CancellationError() }
                if let cached { return cached }
                throw error
            }
        }
    }
    private func isCurrent(_ epoch: UUID) -> Bool { generation == epoch }
    private func persist<Value: Encodable & Sendable>(_ value: Value, key: String, epoch: UUID) async throws {
        try Task.checkCancellation()
        guard generation == epoch else { throw CancellationError() }
        let body = try JSONEncoder().encode(value)
        await storage.save(body, key: key, fetchedAt: now())
        try Task.checkCancellation()
        guard generation == epoch else { throw CancellationError() }
    }
    func clear() async {
        generation = UUID()
        await pages.cancelAll(); await identities.cancelAll()
        await migration?.value
        await storage.clear()
        if let legacyURL { try? FileManager.default.removeItem(at: legacyURL) }
    }

    private func migrate() async {
        if migration == nil {
            let storage = storage, legacyURL = legacyURL, now = now
            migration = Task {
                guard let legacyURL,
                      let size = try? legacyURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return }
                guard size <= 32 * 1024 * 1024, let data = try? Data(contentsOf: legacyURL) else {
                    try? FileManager.default.removeItem(at: legacyURL); return
                }
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                guard let entries = try? decoder.decode([String: LegacyPage].self, from: data) else {
                    try? FileManager.default.removeItem(at: legacyURL); return
                }
                // Keep the newest bounded valid snapshots; never revive evicted legacy entries.
                var complete = true
                for (key, snapshot) in entries.sorted(by: {
                    $0.value.lastUpdated == $1.value.lastUpdated ? $0.key < $1.key : $0.value.lastUpdated > $1.value.lastUpdated
                }).prefix(64) {
                    let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                    guard parts.count == 2, let id = Self.canonicalID(parts[0]),
                          Self.canonicalID(snapshot.page.summary.wcaId) == id,
                          snapshot.page.contentLanguage == parts[1],
                          now().timeIntervalSince(snapshot.lastUpdated) >= -60,
                          now().timeIntervalSince(snapshot.lastUpdated) <= 30 * 86400,
                          let body = try? JSONEncoder().encode(snapshot.page) else { continue }
                    if !(await storage.save(body, key: Self.key("page", id, parts[1]), fetchedAt: snapshot.lastUpdated)) { complete = false }
                }
                if complete { try? FileManager.default.removeItem(at: legacyURL) }
                await storage.maintain()
            }
        }
        await migration?.value
    }
}

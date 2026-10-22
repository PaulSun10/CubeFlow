import Foundation

nonisolated struct CompetitionCachedDetail: Sendable {
    let content: CompetitionDetailContent
    let validatedAt: Date
    func isStale(resource: CompetitionDetailResource, now: Date = Date()) -> Bool {
        now.timeIntervalSince(validatedAt) > resource.lifetime
    }
}

nonisolated enum CompetitionCachePolicy {
    static let retention: TimeInterval = 30 * 24 * 3600
    static let maximumQueryCount = 16
    static let maximumJSONBytes = 32 * 1024 * 1024

    /// Current discovery changes frequently. Past catalogues use the existing
    /// one-hour public-results window, closed years the six-hour metadata window.
    static func canReuseList(_ snapshot: CompetitionCacheSnapshot, query: CompetitionQuery, now: Date = Date()) -> Bool {
        guard let total = snapshot.totalCount, total == snapshot.competitions.count else { return false }
        let age = now.timeIntervalSince(snapshot.lastUpdated)
        let historical: Bool
        if case let .year(year) = query.year {
            historical = query.status == .past && year < Calendar(identifier: .gregorian).component(.year, from: now)
        } else { historical = false }
        let lifetime: TimeInterval = historical ? 6 * 3600 : (query.status == .past ? 3600 : 60)
        return age >= 0 && age < lifetime
    }

    static func persists(_ resource: CompetitionDetailResource) -> Bool {
        resource != .live && resource != .competitors && resource != .tickets
    }
}

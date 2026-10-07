import Foundation

/// A dated, complete export summary, not a live or GPS-based discovery index.
nonisolated struct ExploreHistory: Codable, Sendable {
    struct Count: Codable, Identifiable, Sendable {
        let id: String
        let count: Int
    }
    struct Place: Codable, Identifiable, Sendable {
        let id: String
        let name: String
        let city: String
        let country: String
        let start: String
        let end: String
        let latitude: Double?
        let longitude: Double?
        let events: [String]
    }
    let exportDate: String
    let sourceCommit: String
    let sourceURL: String
    let inputCount: Int
    let completedCount: Int
    let locatedCount: Int
    let countries: [Count]
    let years: [Count]
    let events: [Count]
    let northernmost: [Place]
    let southernmost: [Place]
    let earliest: [Place]
    let eventRich: [Place]

    static let bundled: ExploreHistory? = {
        guard let url = Bundle.main.url(forResource: "ExploreHistorySummary", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }()
}

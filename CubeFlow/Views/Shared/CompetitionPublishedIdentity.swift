import Foundation

/// A provider slug is never a WCA ID. Prefer explicitly canonical identity or an official URL.
nonisolated enum CompetitionPublishedIdentity {
    static func resolve(_ competition: CompetitionSummary, embeddedID: String? = nil) -> String? {
        for value in [competition.url, competition.website].compactMap({ $0 }) {
            guard let url = URL(string: value), let host = url.host?.lowercased(),
                  host == "worldcubeassociation.org" || host.hasSuffix(".worldcubeassociation.org") else { continue }
            let parts = url.path.split(separator: "/").map(String.init)
            if let index = parts.firstIndex(of: "competitions"), parts.indices.contains(index + 1),
               PublishedCompetitionService.validCompetitionID(parts[index + 1]) {
                return parts[index + 1]
            }
        }
        return [competition.wcaCompetitionID, embeddedID].compactMap { $0 }
            .first { PublishedCompetitionService.validCompetitionID($0) }
    }
}

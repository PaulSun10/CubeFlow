import Foundation

/// Cubing Live's explicit result flags, not position or world-rank markers.
/// Keep regional-only badges separate from display PRs so global discovery
/// does not acquire personal-only records.
nonisolated enum CubingLiveRecordIndicators {
    static func regional(_ raw: String?) -> String? {
        PublishedCompetitionResult.recordBadge(raw?.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    static func display(regional raw: String?, personal: String?) -> String? {
        regional(raw) ?? (personal?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "PR" ? "PR" : nil)
    }
    static func highestDisplay(_ tags: [String?]) -> String? {
        PublishedCompetitionResult.highestBadge(tags) ?? (tags.contains("PR") ? "PR" : nil)
    }

    /// Personal selector evidence is user-scoped; regional records are not.
    static func selector(_ evidence: [(single: String?, average: String?, wcaID: String?)], ownWCAID: String?) -> String? {
        let regional = PublishedCompetitionResult.highestBadge(evidence.flatMap { [$0.single, $0.average] })
        if let regional { return regional }
        return evidence.contains {
            CompetitionPersonalIdentity.matches(signedInWCAID: ownWCAID, competitorWCAID: $0.wcaID)
                && [$0.single, $0.average].contains("PR")
        } ? "PR" : nil
    }

    static func isOwnPR(_ tag: String?, ownWCAID: String?, competitorWCAID: String?) -> Bool {
        tag?.uppercased() == "PR"
            && CompetitionPersonalIdentity.matches(signedInWCAID: ownWCAID, competitorWCAID: competitorWCAID)
    }
}

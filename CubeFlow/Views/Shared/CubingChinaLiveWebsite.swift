import Foundation

/// Verified current-site archive metadata. This is not a replacement native Live transport.
nonisolated struct CubingChinaLiveWebsite: Hashable, Sendable, Codable {
    struct Round: Hashable, Sendable, Codable {
        let eventID: String
        let number: Int
    }
    let url: URL
    let rounds: [Round]

    static func parse(html: String, slug: String, expectedWCAID: String?) -> Self? {
        guard let ticketURL = CubingChinaTicket.website(slug: slug),
              let state = CubingChinaPageState(html: html),
              let competition = CubingChinaDetailAdapter.competition(in: html),
              competition["alias"] as? String == slug,
              competition["live"] as? Bool == true,
              let wcaID = competition["wcaCompetitionId"] as? String,
              PublishedCompetitionService.validCompetitionID(wcaID),
              expectedWCAID == nil || expectedWCAID == wcaID,
              let records = state.objects(containing: "live-records:\(slug)").first?["live-records:\(slug)"] as? [[String: Any]],
              !records.isEmpty else { return nil }
        var seen: Set<Round> = []
        let rounds = records.compactMap { row -> Round? in
            guard let event = row["eventId"] as? String, !event.isEmpty,
                  let number = row["roundNumber"] as? Int, number > 0 else { return nil }
            let round = Round(eventID: event, number: number)
            return seen.insert(round).inserted ? round : nil
        }
        guard !rounds.isEmpty else { return nil }
        return Self(url: ticketURL.deletingLastPathComponent().appendingPathComponent("live"), rounds: rounds)
    }

    func targetURL(for target: CompetitionWCALiveResultDeepLink?) -> URL? {
        guard let target else { return url }
        guard let event = target.eventID, let number = target.roundNumber,
              rounds.contains(Round(eventID: event, number: number)),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        // These are the current website's observed selection parameters, not provider IDs.
        components.queryItems = [URLQueryItem(name: "eventId", value: event),
                                 URLQueryItem(name: "roundNumber", value: String(number))]
        return components.url
    }
}

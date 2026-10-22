import Foundation

nonisolated struct PublishedRecordFlags: Hashable, Sendable {
    let single: Bool
    let average: Bool
}

/// WCA's competition JSON contains regional flags only. Its public person page
/// supplies server-authored historical PB cells (pb/wr/cr/nr). Join those cells,
/// never calculate a personal best by comparing numerical performances here.
nonisolated enum PublishedCompetitionPR {
    static func flags(page: WCAPersonResultsPage, data: PublishedCompetitionData) -> [Int: PublishedRecordFlags] {
        guard page.contentLanguage == "en", let person = CompetitionPersonalIdentity.canonical(page.summary.wcaId) else { return [:] }
        let rows = data.results.filter { CompetitionPersonalIdentity.canonical($0.wcaID) == person }
        var evidence: [Int: [PublishedRecordFlags]] = [:]
        for section in page.resultsSections {
            for value in section.results where competitionID(value.competitionPath) == data.competitionID {
                let matches = rows.filter { row in
                    row.eventID == section.event.code && roundTitle(row.roundTypeID) == clean(value.roundName)
                        && clean(value.single ?? "") == clean(row.formatted(row.best))
                        && (row.average == 0
                            ? ["", "\u{2014}"].contains(clean(value.average ?? ""))
                            : clean(value.average ?? "") == clean(row.formatted(row.average, average: true)))
                }
                guard matches.count == 1, let row = matches.first else { continue }
                // Per the provider's pb_type_class_for_result, regional CSS classes
                // replace "pb" only when the same authoritative PB marker is true.
                evidence[row.id, default: []].append(PublishedRecordFlags(single: row.best > 0 && value.singleEmphasis != nil,
                    average: row.average > 0 && value.averageEmphasis != nil))
            }
        }
        return evidence.compactMapValues { $0.count == 1 ? $0[0] : nil }
    }

    static func applying(_ flags: [Int: PublishedRecordFlags], to data: PublishedCompetitionData) -> PublishedCompetitionData {
        let rows = data.results.map { source in
            var row = source
            row.personalSingleRecord = flags[row.id]?.single == true ? "PR" : nil
            row.personalAverageRecord = flags[row.id]?.average == true ? "PR" : nil
            return row
        }
        return PublishedCompetitionData(competitionID: data.competitionID, results: rows, eventOrder: data.eventIDs)
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private static func competitionID(_ raw: String?) -> String? {
        guard let raw, let url = URL(string: raw),
              url.host == nil || ["www.worldcubeassociation.org", "worldcubeassociation.org"].contains(url.host?.lowercased() ?? "") else { return nil }
        let path = url.path.split(separator: "/").map(String.init)
        guard path.count == 2, path[0] == "competitions" else { return nil }
        return path[1]
    }
    private static func roundTitle(_ type: String) -> String? {
        // WCA config/locales/en.yml: rounds.<type>.cell_name.
        switch type {
        case "0", "h": "qualification round"
        case "1", "d": "first round"
        case "2", "e": "second round"
        case "3", "g": "semi final"
        case "b": "b final"
        case "c", "f": "final"
        default: nil
        }
    }
}

import Foundation

nonisolated struct CompetitionSharingArtwork: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case banner, logo }
    let kind: Kind
    let url: URL
}

nonisolated struct CompetitionSharingContext: Hashable, Sendable {
    var name: String?
    var details: String? = nil
    var artwork: CompetitionSharingArtwork? = nil
    var chinaStages = false
}

nonisolated struct CompetitionShareRow: Identifiable, Hashable, Sendable {
    let id: String
    let eventID: String
    let eventName: String
    let round: String
    let rank: String
    let average: String?
    let single: String?
    let attempts: [String]
    let averageBadge: String?
    let singleBadge: String?
    let isMean: Bool
    var attemptOrdinals: [Int] = []

    @MainActor static func make(_ value: CompetitionWCALiveCompetitorResult, language: String, chinaStages: Bool = false) -> Self {
        func text(_ number: Int, average: Bool = false) -> String {
            WCAResultFormatter.string(from: number, eventID: value.eventID, resultType: average ? "average" : "single", zeroRepresentation: "-")
        }
        return .init(id: value.id, eventID: value.eventID,
            eventName: CompetitionEventPresentation.localizedFullName(for: value.eventID, languageCode: language, fallback: value.eventName),
            round: reportRoundName(value, language: language, chinaStages: chinaStages),
            rank: value.ranking.map(String.init) ?? "-", average: value.average == 0 ? nil : text(value.average, average: true),
            single: value.best == 0 ? nil : text(value.best), attempts: value.attempts.filter { $0 != 0 }.map { text($0) },
            averageBadge: CubingLiveRecordIndicators.highestDisplay([value.averageRecordTag]),
            singleBadge: CubingLiveRecordIndicators.highestDisplay([value.singleRecordTag]), isMean: value.formatID == "m",
            attemptOrdinals: value.attempts.enumerated().filter { $0.element != 0 }.map { $0.offset + 1 })
    }

    @MainActor static func reportRoundName(_ row: CompetitionWCALiveCompetitorResult, language: String, chinaStages: Bool) -> String {
        guard let type = row.officialRoundType else { return row.roundName }
        let stages = Set(row.eventRoundTypes ?? [])
        if chinaStages, language.hasPrefix("zh"), !stages.isDisjoint(with: ["f", "c"]) {
            let ordinaryStages = Set(stages.map(PublishedCompetitionRound.order)).subtracting([0, 4])
            if [2, 3].contains(ordinaryStages.count), ["1", "d"].contains(type) {
                return language == "zh-Hans" ? "初赛" : "初賽"
            }
            if ordinaryStages == [1, 2, 5], ["2", "e"].contains(type) {
                return language == "zh-Hans" ? "复赛" : "複賽"
            }
        }
        return PublishedCompetitionStrings.round(type, language: language)
    }

    @MainActor static func make(_ value: WCACompetitionResult, event: WCAEventDescriptor, language: String) -> Self {
        func badge(_ emphasis: WCAResultEmphasis?) -> String? { emphasis == .personalBest ? "PR" : emphasis?.marker }
        return .init(id: value.id, eventID: event.code,
            eventName: CompetitionEventPresentation.localizedFullName(for: event.code, languageCode: language, fallback: event.name), round: value.roundName,
            rank: value.place ?? "-", average: value.average, single: value.single, attempts: value.solves.map(\.value),
            averageBadge: badge(value.averageEmphasis), singleBadge: badge(value.singleEmphasis),
            isMean: value.average != nil && value.solves.count == 3)
    }
}

nonisolated struct CompetitionShareRequest: Identifiable, Sendable {
    enum Mode: Sendable { case report, highlight }
    let id = UUID()
    let mode: Mode
    let context: CompetitionSharingContext
    let name: String
    var identity: String? = nil
    let rows: [CompetitionShareRow]
}

enum CompetitionHighlightMetric: Hashable {
    case average, single, attempt(Int)
    static func choices(for row: CompetitionShareRow) -> [Self] {
        (row.average == nil ? [] : [.average]) + (row.single == nil ? [] : [.single]) + row.attempts.indices.map { .attempt($0) }
    }
    func value(_ row: CompetitionShareRow) -> String? {
        switch self { case .average: row.average; case .single: row.single
        case .attempt(let index): row.attempts.indices.contains(index) ? row.attempts[index] : nil }
    }
    func badge(_ row: CompetitionShareRow) -> String? {
        switch self { case .average: row.averageBadge; case .single: row.singleBadge
        case .attempt: nil } // Aggregate record evidence does not identify a particular attempt.
    }
    func label(_ row: CompetitionShareRow, language: String) -> String {
        switch self {
        case .average: return PublishedCompetitionStrings.text(row.isMean ? "mean" : "average", language)
        case .single: return appLocalizedString("wca.results_single", languageCode: language)
        case .attempt(let index):
            let ordinal = row.attemptOrdinals.indices.contains(index) ? row.attemptOrdinals[index] : index + 1
            return appLocalizedString("share.solve.\(ordinal)", languageCode: language)
        }
    }
}

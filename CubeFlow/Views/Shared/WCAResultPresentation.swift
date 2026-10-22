import Foundation

nonisolated enum WCAResultFormatter {
    static func string(
        from value: Int,
        eventID: String,
        resultType: String? = nil,
        zeroRepresentation: String = ""
    ) -> String {
        if value == 0 { return zeroRepresentation }
        if value == -1 { return "DNF" }
        if value == -2 { return "DNS" }
        guard value > 0 else { return zeroRepresentation }

        switch eventID {
        case "333fm":
            if resultType == "average" || value >= 1_000 {
                return String(format: "%.2f", Double(value) / 100)
            }
            return String(value)
        case "333mbf", "333mbo":
            return multiBlindString(from: value)
        default:
            return centisecondString(value)
        }
    }

    private static func multiBlindString(from value: Int) -> String {
        let leadingDigit = value / 1_000_000_000
        let solved: Int
        let attempted: Int
        let seconds: Int

        if leadingDigit == 1 {
            // Historical format: 1SSAATTTTT.
            solved = 99 - ((value / 10_000_000) % 100)
            attempted = (value / 100_000) % 100
            seconds = value % 100_000
        } else {
            // Current format: 0DDTTTTTMM.
            let difference = 99 - ((value / 10_000_000) % 100)
            seconds = (value / 100) % 100_000
            let missed = value % 100
            solved = difference + missed
            attempted = solved + missed
        }

        return "\(solved)/\(attempted) \(secondString(seconds))"
    }

    private static func secondString(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private static func centisecondString(_ value: Int) -> String {
        let hours = value / 360_000
        let minutes = (value % 360_000) / 6_000
        let seconds = (value % 6_000) / 100
        let hundredths = value % 100
        if hours > 0 { return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, hundredths) }
        if minutes > 0 { return String(format: "%d:%02d.%02d", minutes, seconds, hundredths) }
        return String(format: "%d.%02d", seconds, hundredths)
    }
}

nonisolated struct CompetitionWCALiveResultDeepLink: Hashable, Sendable {
    let roundID: String
    let personID: String?
    let personWCAID: String?
    var eventID: String? = nil
    var roundNumber: Int? = nil
    var finalRoundNumber: Int? = nil

    func cubingChinaRound(in options: [CompetitionLiveRoundOption]) -> CompetitionLiveRoundOption? {
        guard let eventID, let roundNumber, let finalRoundNumber,
              roundNumber > 0, roundNumber <= finalRoundNumber else { return nil }
        var types = roundNumber == finalRoundNumber ? ["f", "c"] :
            [1: ["1", "d"], 2: ["2", "e"], 3: ["3", "g"]][roundNumber] ?? []
        if roundNumber > 1, roundNumber == finalRoundNumber - 1 { types += ["3", "g"] }
        let matches = options.filter { $0.eventID == eventID && types.contains($0.roundID) }
        // Provider IDs are not interchangeable. Match only verified event/round semantics.
        return matches.count == 1 ? matches[0] : nil
    }

    func result(in round: CompetitionWCALiveRound) -> CompetitionWCALiveResultPreview? {
        guard round.id == roundID else { return nil }
        if let personID, let result = round.results.first(where: { $0.personID == personID }) {
            return result
        }
        if let personWCAID, let result = round.results.first(where: { $0.personWCAID == personWCAID }) {
            return result
        }
        return nil
    }
}

extension CompetitionWCALiveRecord {
    var resultDeepLink: CompetitionWCALiveResultDeepLink {
        CompetitionWCALiveResultDeepLink(
            roundID: roundID,
            personID: personID,
            personWCAID: personWCAID
        )
    }
}

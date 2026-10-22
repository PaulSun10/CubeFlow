import Foundation

nonisolated enum CompetitionLiveScheduleColor {
    static func matches(_ code: String?, event: String, round: Int) -> Bool {
        guard let code else { return false }
        let prefix = "\(event)-r\(round)"
        return code == prefix || code.hasPrefix(prefix + "-")
    }

    /// The list summarizes a round: use its first scheduled, colored block (not today's color).
    static func hex(activities: [CompetitionWCALiveActivity], event: String, round: Int) -> String? {
        activities.filter { matches($0.activityCode, event: event, round: round) }
            .sorted { $0.startTime == $1.startTime ? $0.id < $1.id : $0.startTime < $1.startTime }
            .compactMap { validated($0.roomColorHex) }.first
    }

    static func validated(_ hex: String?) -> String? {
        guard let hex else { return nil }
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard value.count == 6, value.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + value.uppercased()
    }
}

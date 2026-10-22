import Foundation

/// WCA list dates are UTC-encoded civil dates, not venue timestamps. Project
/// the user's Gregorian "today" into that same date domain before comparing.
nonisolated struct CompetitionDateWindow: Hashable, Sendable {
    static let lookbackDays = 30
    let today: Date
    let recentStart: Date
    let yesterday: Date
    let timeZoneID: String

    init?(now: Date, calendar: Calendar = .current) {
        guard now.timeIntervalSince1970.isFinite else { return nil }
        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendar.timeZone
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let day = utc.date(from: local.dateComponents([.year, .month, .day], from: now)),
              let previous = utc.date(byAdding: .day, value: -1, to: day),
              let recent = utc.date(byAdding: .day, value: -Self.lookbackDays, to: day) else { return nil }
        today = day; yesterday = previous; recentStart = recent; timeZoneID = local.timeZone.identifier
    }
    private func civilDay(_ value: Date) -> Date? {
        guard value.timeIntervalSince1970.isFinite else { return nil }
        return Date(timeIntervalSince1970: floor(value.timeIntervalSince1970 / 86_400) * 86_400)
    }
    func contains(_ competition: CompetitionSummary, status: CompetitionStatusFilter) -> Bool {
        guard let start = civilDay(competition.startDate), let end = civilDay(competition.endDate), end >= start else { return false }
        switch status {
        case .present: return start >= today
        case .recent: return start >= recentStart && start <= today
        case .past: return end < today
        }
    }
    func isAfterToday(_ date: Date) -> Bool { civilDay(date).map { $0 > today } ?? false }
    func queryItems(status: CompetitionStatusFilter) -> [URLQueryItem] {
        switch status {
        case .present:
            return [.init(name: "start", value: isoDay(today)), .init(name: "sort", value: "start_date,end_date,name")]
        case .recent:
            return [.init(name: "start", value: isoDay(recentStart)), .init(name: "sort", value: "start_date,end_date,name")]
        case .past:
            return [.init(name: "end", value: isoDay(yesterday)), .init(name: "sort", value: "-end_date,-start_date,name")]
        }
    }
    func isoDay(_ date: Date) -> String {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let fields = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", fields.year ?? 0, fields.month ?? 0, fields.day ?? 0)
    }
    func key(status: CompetitionStatusFilter, year: CompetitionYearFilter) -> String {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        if status == .past, case .year(let value) = year, value < utc.component(.year, from: today) {
            return "start-date-v1|closed-year-\(value)"
        }
        return "start-date-v1|\(isoDay(today))|\(timeZoneID)"
    }
}

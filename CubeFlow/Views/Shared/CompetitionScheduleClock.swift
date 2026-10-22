import Foundation

nonisolated struct CompetitionScheduleClock {
    let start: Date
    let end: Date
    init?(entries: [CompetitionScheduleEntry]) {
        let starts = entries.compactMap(\.startTime)
        let ends = entries.compactMap(\.endTime)
        guard let start = starts.min(), let end = ends.max(), end > start else { return nil }
        self.start = start
        self.end = end
    }
    var durationMinutes: Double { end.timeIntervalSince(start) / 60 }
    func offsetMinutes(at now: Date) -> Double? {
        guard now >= start, now < end else { return nil }
        return now.timeIntervalSince(start) / 60
    }
    func isToday(at now: Date, timeZone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.isDate(start, inSameDayAs: now)
    }
    func y(at now: Date, headerHeight: Double, pointsPerMinute: Double) -> Double? {
        offsetMinutes(at: now).map { headerHeight + $0 * pointsPerMinute }
    }
}

nonisolated struct CompetitionScheduleLane: Identifiable {
    let entry: CompetitionScheduleEntry
    let lane: Int
    let count: Int
    var id: String { entry.id }
    static func placements(_ entries: [CompetitionScheduleEntry]) -> [Self] {
        let sorted = entries.filter { $0.startTime != nil && $0.endTime != nil }.sorted { $0.startTime! < $1.startTime! }
        var ends: [Date] = [], placed: [(CompetitionScheduleEntry, Int)] = []
        for entry in sorted {
            let lane = ends.firstIndex { $0 <= entry.startTime! } ?? ends.count
            if lane == ends.count { ends.append(entry.endTime!) } else { ends[lane] = entry.endTime! }
            placed.append((entry, lane))
        }
        return placed.map { Self(entry: $0.0, lane: $0.1, count: max(ends.count, 1)) }
    }
}

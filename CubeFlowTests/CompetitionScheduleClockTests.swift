import XCTest
@testable import CubeFlow

final class CompetitionScheduleClockTests: XCTestCase {
    private func entry(id: String, start: Date, duration: TimeInterval = 3600) -> CompetitionScheduleEntry {
        CompetitionScheduleEntry(id: id, timeText: "", title: "", detailText: nil, venueName: nil, eventCode: nil,
            group: nil, round: nil, format: nil, cutoff: nil, timeLimit: nil, advancingCount: nil,
            startTime: start, endTime: start.addingTimeInterval(duration))
    }
    func testNowLineUsesSharedAbsoluteTimeAndSuppressesOutOfRangeTimes() throws {
        let start = try XCTUnwrap(CubingChinaDetailAdapter.date("2026-10-05T00:00:00Z"))
        let rows = [entry(id: "room-a", start: start), entry(id: "room-b", start: start.addingTimeInterval(1800))]
        let clock = try XCTUnwrap(CompetitionScheduleClock(entries: rows))
        XCTAssertNil(clock.offsetMinutes(at: start.addingTimeInterval(-1)))
        XCTAssertNil(clock.offsetMinutes(at: clock.end))
        XCTAssertEqual(clock.y(at: start.addingTimeInterval(1800), headerHeight: 36, pointsPerMinute: 1.4), 78)
        XCTAssertTrue(clock.isToday(at: start.addingTimeInterval(1800), timeZone: CubingChinaDetailAdapter.timeZone))
        XCTAssertEqual(clock.durationMinutes, 90)
    }
    func testRoomOverlapLanesDoNotPaintOverAnotherScheduledActivity() {
        let start = Date(timeIntervalSince1970: 0)
        let placements = CompetitionScheduleLane.placements([entry(id: "a", start: start),
            entry(id: "b", start: start.addingTimeInterval(1800)), entry(id: "c", start: start.addingTimeInterval(3600))])
        XCTAssertEqual(placements.map(\.lane), [0, 1, 0])
        XCTAssertEqual(placements.map(\.count), [2, 2, 2])
    }
}

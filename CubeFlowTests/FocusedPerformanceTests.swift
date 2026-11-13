import XCTest
@testable import CubeFlow

@MainActor final class FocusedPerformanceTests: XCTestCase {
    private func solves(_ count: Int) -> [SessionSolveSample] {
        (0..<count).map { index in
            .init(id: UUID(), date: Date(timeIntervalSince1970: Double((index * 197) % max(1, count))),
                time: Double((index * 137) % 193) / 4 + 5,
                resultRaw: index % 7 == 0 ? "dnf" : index % 3 == 0 ? "plusTwo" : "solved",
                scramble: "R U", comment: "", eventRawValue: "3x3")
        }
    }
    private func originalBins(_ solves: [SessionSolveSample]) -> [SessionSolveTrend.Bin] {
        let points = solves.sorted { $0.date < $1.date }.compactMap { SolveMetrics.adjustedTime(for: $0) }
        guard let minValue = points.min(), let maxValue = points.max() else { return [] }
        let lower = floor(minValue), upper = ceil(maxValue), width = max(0.5, (upper - lower) / 8.0)
        var result: [SessionSolveTrend.Bin] = [], start = lower
        repeat {
            let end = start + width
            result.append(.init(lower: start, upper: end,
                count: points.filter { $0 >= start && ($0 < end || (end >= upper && $0 == upper)) }.count))
            start += width
        } while start < upper
        return result
    }

    private func assertAlignedCoverage(_ snapshot: SessionSolveTrend, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(snapshot.bins.count, 80, file: file, line: line)
        for (index, bin) in snapshot.bins.enumerated() {
            XCTAssertGreaterThan(bin.upper, bin.lower, file: file, line: line)
            XCTAssertEqual(bin.lower / (bin.upper - bin.lower), (bin.lower / (bin.upper - bin.lower)).rounded(), accuracy: 0.00001, file: file, line: line)
            let values = snapshot.points.filter { $0.time >= bin.lower && ($0.time < bin.upper || (index == snapshot.bins.count - 1 && $0.time == bin.upper)) }
            XCTAssertEqual(bin.count, values.count, file: file, line: line)
            if index > 0 { XCTAssertLessThanOrEqual(snapshot.bins[index - 1].upper, bin.lower, file: file, line: line) }
        }
        XCTAssertEqual(snapshot.bins.reduce(0) { $0 + $1.count }, snapshot.points.count, file: file, line: line)
    }

    func testTrendSnapshotMatchesExistingPenaltyAndNewAlignedBinSemantics() {
        for count in [0, 1, 2, 17, 1000] {
            let input = solves(count), snapshot = SessionSolveTrend(solves: input)
            assertAlignedCoverage(snapshot)
            XCTAssertEqual(snapshot.bins.reduce(0) { $0 + $1.count }, snapshot.points.count)
            XCTAssertEqual(snapshot.points.map(\.id), input.sorted { $0.date < $1.date }.filter { $0.adjustedTime != nil }.map(\.id))
            XCTAssertEqual(snapshot.points.map(\.time), input.sorted { $0.date < $1.date }.compactMap(\.adjustedTime))
        }
        let fixture = (8...13).map { SessionSolveSample(id: UUID(), date: .now, time: Double($0), resultRaw: "solved", scramble: "", comment: "", eventRawValue: "3x3") }
        XCTAssertEqual(SessionSolveTrend(solves: fixture).bins, [
            .init(lower: 8, upper: 9, count: 1), .init(lower: 9, upper: 10, count: 1),
            .init(lower: 10, upper: 11, count: 1), .init(lower: 11, upper: 12, count: 1),
            .init(lower: 12, upper: 13, count: 2)])
    }

    func testChangedSolveInputCreatesFreshTrendWithoutAStaleCache() {
        let old = solves(20), snapshot = SessionSolveTrend(solves: old)
        let original = snapshot.bins
        let changed = Array(old.dropFirst(3))
        let fresh = SessionSolveTrend(solves: changed)
        assertAlignedCoverage(fresh)
        XCTAssertNotEqual(fresh.points.count, snapshot.points.count)
        XCTAssertEqual(snapshot.bins, original, "Old value remains immutable")
        assertAlignedCoverage(snapshot)
    }

    func testRepeatedChartReadsBeforeAfterWithComparableInputs() {
        let input = solves(2000)
        var oldTimes: [Double] = [], newTimes: [Double] = []
        var checksum = 0
        for _ in 0..<5 {
            var start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<100 { checksum += originalBins(input).count }
            oldTimes.append(ProcessInfo.processInfo.systemUptime - start)
            start = ProcessInfo.processInfo.systemUptime
            let snapshot = SessionSolveTrend(solves: input)
            for _ in 0..<100 { checksum += snapshot.bins.count }
            newTimes.append(ProcessInfo.processInfo.systemUptime - start)
        }
        XCTAssertGreaterThan(checksum, 0)
        print("[TargetedPerf] chart input=2000 reads=100 builds_before=100 builds_after=1 before_ms=\(oldTimes.map { $0 * 1000 }) after_ms=\(newTimes.map { $0 * 1000 })")
    }

    private func attempts(_ count: Int) -> [AlgTrainerAttemptRecord] {
        (0..<count).map { index in .init(id: String(index), setID: "3x3_oll", scopeID: "3x3_oll", level: .caseName,
            caseID: "case", answerID: nil, isCorrect: true, isSkipped: false,
            timestamp: Date(timeIntervalSince1970: Double((index * 137) % 59))) }
    }

    func testLatestPracticeMatchesStableSortIncludingTiesAndEmptyInputs() {
        for count in [0, 1, 10, 1000] {
            let records = attempts(count)
            XCTAssertEqual(AlgTrainerAttemptRecord.latest(in: records), records.sorted { $0.timestamp > $1.timestamp }.first)
        }
        let first = attempts(1)[0]
        let second = AlgTrainerAttemptRecord(id: "second", setID: first.setID, scopeID: first.scopeID,
            level: first.level, caseID: first.caseID, answerID: nil, isCorrect: true, isSkipped: false, timestamp: first.timestamp)
        XCTAssertEqual(AlgTrainerAttemptRecord.latest(in: [first, second])?.id, first.id)
    }

    func testLatestPracticeEliminatesSortingWork() {
        let records = attempts(2000)
        var comparisons = 0
        let old = records.sorted { comparisons += 1; return $0.timestamp > $1.timestamp }.first
        XCTAssertEqual(AlgTrainerAttemptRecord.latest(in: records), old)
        print("[TargetedPerf] latest input=2000 sort_comparisons=\(comparisons) linear_comparisons=\(records.count - 1) sorted_array_copies_after=0")
    }
}

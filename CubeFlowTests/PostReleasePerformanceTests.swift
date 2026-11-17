import XCTest
import CryptoKit
@testable import CubeFlow

@MainActor final class PostReleasePerformanceTests: XCTestCase {
    func testWCAProfileResultsHTMLWorkload() throws {
        let rowCount = 1_600
        let rows = (0..<rowCount).map { index in
            let competition = index.isMultiple(of: 2)
                ? "<a href=\"/competitions/Fixture\(index)\">Fixture &amp; Open \(index)</a>" : ""
            return """
            <tr class="result gold-place">
                <td class="competition">\(competition)</td><td class="round">\(index.isMultiple(of: 2) ? "First round" : "Final")</td>
                <td class="place">1</td><td class="single pb">5.00</td><td class="regional-single-record"></td>
                <td class="average wr">6.00</td><td class="regional-average-record">WR</td>
                <td class="solve trimmed">5.00</td><td class="solve">6.10</td><td class="solve">6.20</td>
                <td class="solve">5.70</td><td class="solve trimmed">DNF</td><td class="solve"></td>
            </tr>
            """
        }.joined(separator: "\n")
        let html = """
        <div class="details"><table><tbody>
        <tr><td>Australia</td><td>2009TEST01</td><td>Male</td><td>800</td><td>8000</td></tr>
        </tbody></table></div>
        <div class="personal-records"><table><tbody>
        <tr><td data-event="333">3x3x3 Cube</td><td>1</td><td>2</td><td>3</td><td>5.00</td><td>6.00</td><td>4</td><td>3</td><td>2</td></tr>
        </tbody></table></div>
        <table><tbody class="event-333"><tr><td colspan="12" class="event"><i></i>3x3x3 Cube</td></tr>
        \(rows)
        </tbody></table>
        """
        func parse() throws -> WCAPersonResultsPage {
            try WCAResultsService.parsePersonResultsHTML(html, requestedLanguageCode: "en")
        }
        let expected = try parse()
        var times: [Double] = []
        for _ in 0..<5 {
            let start = ProcessInfo.processInfo.systemUptime
            let actual = try parse()
            times.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            XCTAssertEqual(actual.resultsSections, expected.resultsSections)
        }
        let results = try XCTUnwrap(expected.resultsSections.first?.results)
        XCTAssertEqual(results.count, rowCount)
        XCTAssertEqual(results[1].competitionPath, "/competitions/Fixture0")
        XCTAssertEqual(results[1].competitionName, "Fixture & Open 0")
        XCTAssertEqual(results[1].roundName, "Final")
        XCTAssertEqual(results[1].solves.map(\.value), ["5.00", "6.10", "6.20", "5.70", "DNF"])
        XCTAssertEqual(results[1].solves.map(\.isTrimmed), [true, false, false, false, true])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let digest = SHA256.hash(data: try encoder.encode(expected))
        XCTAssertEqual(digest.map { String(format: "%02x", $0) }.joined(),
            "2e0293037f6008410a1b2f2318cf70db47a3a1fa0a880785cdaaad7e39b4053a")
        print("[PostReleasePerf] wca rows=\(rowCount) bytes=\(html.utf8.count) \(digest) ms=\(times)")
    }

    func testChartHistoryWorkload() throws {
        for count in [1_000, 10_000, 50_000, 100_000] {
            let input = (0..<count).reversed().map { index in
                SessionSolveSample(id: UUID(), date: Date(timeIntervalSince1970: Double(index)),
                    time: Double(810 + (index * 73) % 1900) / 100,
                    resultRaw: index % 31 < 2 ? "dnf" : index % 17 == 0 ? "plusTwo" : "solved",
                    scramble: "R U F2", comment: "", eventRawValue: "3x3")
            }
            _ = try SessionPerformanceHistory(input)
            var times: [Double] = []
            var measured: SessionPerformanceHistory?
            for _ in 0..<5 {
                measured = nil
                let start = ProcessInfo.processInfo.systemUptime
                measured = try SessionPerformanceHistory(input)
                times.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            }
            let history = try XCTUnwrap(measured)
            XCTAssertEqual(history.observations.count, count)
            XCTAssertLessThanOrEqual(history.buckets.count, 192)
            let chronological = Array(input.reversed())
            let step = count == 1_000 ? 1 : 113
            for index in stride(from: 0, to: count, by: step) {
                let row = history.observations[index]
                for (window, actual) in [(5, row.ao5), (12, row.ao12)] {
                    let expected = index + 1 < window ? nil : SolveMetrics.averageValue(
                        from: Array(chronological[(index + 1 - window)...index]), trimmingCount: 1)
                    XCTAssertEqual(actual?.bitPattern, expected?.bitPattern, "row \(index + 1), ao\(window)")
                }
            }
            print("[PostReleasePerf] chart rows=\(count) ms=\(times)")
        }
    }

    func testChartWindowsPreserveExceptionalValuesAndTimestampTieOrder() throws {
        let times: [Double] = [0, -0.0, 12.1, .nan, 10, .infinity, -5,
                              -Double.infinity, .greatestFiniteMagnitude, 12.1, 15.5, 6]
        let input = (0..<96).reversed().map { index in
            SessionSolveSample(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
                date: Date(timeIntervalSince1970: Double(index / 4)),
                time: times[(index * 5 + index / 3) % times.count],
                resultRaw: index % 11 < 2 ? "dnf" : index % 7 == 0 ? "plusTwo" : "solved",
                scramble: "", comment: "", eventRawValue: "3x3")
        }
        let chronological = Array(input.reversed())
        let history = try SessionPerformanceHistory(input)
        for (index, row) in history.observations.enumerated() {
            for (count, actual) in [(5, row.ao5), (12, row.ao12)] {
                guard index + 1 >= count else { XCTAssertNil(actual); continue }
                let ranked = chronological[(index + 1 - count)...index].map { sample -> (Double, Bool) in
                    sample.adjustedTime.map { ($0, false) } ?? (.greatestFiniteMagnitude, true)
                }.sorted { $0.0 < $1.0 }
                let inner = ranked.dropFirst().dropLast()
                let expected = inner.contains(where: \.1) ? Double.nan : inner.reduce(0) { $0 + $1.0 } / Double(inner.count)
                XCTAssertEqual(actual?.bitPattern, expected.bitPattern, "row \(index + 1), ao\(count)")
            }
        }
    }

    func testLearnedCaseRowWorkload() {
        let ids = (0..<493).map { "case-\($0)" }
        let sets = ["fixture-zbll", "fixture-oll", "fixture-pll"]
        let map = Dictionary(uniqueKeysWithValues: sets.enumerated().map { index, set in
            (set, Set(ids.enumerated().filter { $0.offset.isMultiple(of: index + 2) }.map(\.element)))
        })
        let storage = learnedCaseStorage(from: map)
        let set = sets[0]
        let expected = ids.map { map[set, default: []].contains($0) }
        func rows() -> [Bool] { ids.map { isAlgCaseLearned(setID: set, caseID: $0, storage: storage) } }
        XCTAssertEqual(rows(), expected)
        var times: [Double] = []
        for _ in 0..<7 {
            let start = ProcessInfo.processInfo.systemUptime
            let actual = rows()
            times.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            XCTAssertEqual(actual, expected)
        }
        XCTAssertEqual(learnedCaseCount(setID: set, caseIDs: ids + ids, storage: storage),
            expected.filter { $0 }.count)
        let changed = updatedLearnedCaseStorage(storage: storage, setID: set, caseID: ids[0], learned: false)
        XCTAssertFalse(isAlgCaseLearned(setID: set, caseID: ids[0], storage: changed))
        XCTAssertFalse(isAlgCaseLearned(setID: set, caseID: ids[0], storage: "invalid"))
        XCTAssertTrue(isAlgCaseLearned(setID: set, caseID: ids[0], storage: storage))
        print("[PostReleasePerf] alg rows=\(ids.count) bytes=\(storage.utf8.count) ms=\(times)")
    }

    func testTwoByTwoCheckpointWorkload() throws {
        let moves = try ["R", "U'", "F", "L2", "D", "B'", "R2", "U", "F2", "L", "D'", "B2"].map {
            try XCTUnwrap(CubeLayerTurn($0))
        }
        var state = CubeSurface.solved(size: 2)
        var states: [String] = []
        for index in 0..<1_024 {
            state = try XCTUnwrap(moves[(index * 7 + index / 13) % moves.count].applying(to: state, size: 2))
            states.append(state)
        }
        func keys() -> [[UInt8]?] { states.map(CubeStateEquivalence.twoByTwoCheckpointKey) }
        let expected = keys()
        var times: [Double] = []
        for _ in 0..<7 {
            let start = ProcessInfo.processInfo.systemUptime
            let actual = keys()
            times.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            XCTAssertEqual(actual, expected)
        }
        var digest: UInt64 = 14_695_981_039_346_656_037
        for key in expected {
            let bytes = try XCTUnwrap(key)
            XCTAssertEqual(bytes.count, 24)
            for byte in bytes { digest = (digest ^ UInt64(byte)) &* 1_099_511_628_211 }
        }
        XCTAssertNil(CubeStateEquivalence.twoByTwoCheckpointKey("invalid"))
        XCTAssertEqual(digest, 17_568_467_078_597_314_821, "Must preserve the baseline checkpoint bytes")
        print("[PostReleasePerf] checkpoint states=\(states.count) digest=\(digest) ms=\(times)")
    }
}

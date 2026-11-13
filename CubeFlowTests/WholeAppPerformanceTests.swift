import XCTest
import SwiftUI
import CoreData
@testable import CubeFlow

@MainActor final class WholeAppPerformanceTests: XCTestCase {
    private func samples(_ count: Int) -> [SessionSolveSample] {
        (0..<count).map { index in
            .init(id: UUID(), date: Date(timeIntervalSince1970: Double(count - index)),
                time: Double(800 + index % 379) / 100, resultRaw: index % 47 == 0 ? "dnf" : "solved",
                scramble: "R U F2", comment: "Fixture", eventRawValue: "3x3")
        }
    }
    func testLargeAverageWindowConstructionBenchmark() throws {
        let input = samples(8000)
        var times: [Double] = []
        for _ in 0..<3 {
            let start = ProcessInfo.processInfo.systemUptime
            let entries = DataTabComputation.buildAverageEntriesSnapshot(from: input, averageType: .ao100)
            times.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            XCTAssertEqual(entries.count, 7901)
            XCTAssertEqual(entries.first?.solves.map(\.id), Array(input.prefix(100)).map(\.id))
            XCTAssertEqual(entries.last?.solves.map(\.id), Array(input.suffix(100)).map(\.id))
        }
        print("[WholeAppPerf] average_entries solves=8000 window=100 trials_ms=\(times)")
    }

    func testHistoryRecordSummariesBenchmark() {
        let input = samples(16_000)
        let metrics = RecordAverageMetric.defaultMetrics
        let expected = metrics.map {
            DataTabComputation.evaluateRecordMetric(metric: $0, solves: input, includeWindowValues: true)
        }
        var times: [Double] = []
        for _ in 0..<5 {
            let start = ProcessInfo.processInfo.systemUptime
            let actual = DataTabComputation.evaluateRecordSummaries(metrics: metrics, solves: input)
            times.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            XCTAssertEqual(actual.count, expected.count)
            for (result, reference) in zip(actual, expected) {
                XCTAssertEqual(result.currentValue?.bitPattern, reference.currentValue?.bitPattern)
                XCTAssertEqual(result.bestValue?.bitPattern, reference.bestValue?.bitPattern)
                XCTAssertEqual(result.bestFiniteIndex, reference.windowValues.indices.first {
                    let value = reference.windowValues[$0]
                    return value?.isFinite == true && value == reference.bestValue
                })
            }
        }
        print("[Nov10Perf] history_summaries rows=16000 metrics=\(metrics.count) ms=\(times)")
    }

    func testRecordCancellationStopsWorkAndCompletedResultsRemainEqual() throws {
        let input = samples(16_000)
        let expected = DataTabComputation.buildRecordSnapshotData(
            from: input, notAvailable: "--", languageCode: "en", timeDecimals: 3)
        let completed = try DataTabComputation.buildRecordSnapshotData(
            from: input, notAvailable: "--", languageCode: "en", timeDecimals: 3,
            checkCancellation: { try Task.checkCancellation() })
        func values(_ snapshot: RecordSnapshot) -> [String] {
            [snapshot.sessionMeanText, snapshot.sessionMeanSuffix ?? "", snapshot.bestTimeText, snapshot.worstTimeText] +
                (snapshot.currentStats + snapshot.bestStats).flatMap { [$0.id, $0.title, $0.secondaryTitle ?? "", $0.value] }
        }
        XCTAssertEqual(values(completed), values(expected))

        var checks = 0
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try DataTabComputation.buildRecordSnapshotData(
            from: input, notAvailable: "--", languageCode: "en", timeDecimals: 3,
            checkCancellation: {
                checks += 1
                if checks == 8 { throw CancellationError() }
            })) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(checks, 8)
        print("[PerfAudit] records_cancellation checkpoint=\(checks) ms=\((ProcessInfo.processInfo.systemUptime - start) * 1_000)")
    }

    func testNativeRootTabFirstEntryAndWarmReturn() async throws {
        let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
        let session = Session(name: "First entry fixture", context: context)
        for sample in samples(1000) {
            _ = Solve(time: sample.time, date: sample.date, scramble: sample.scramble, event: sample.eventRawValue,
                result: SolveResult(rawValue: sample.resultRaw)!, session: session, context: context)
        }
        try context.save()
        let defaults = UserDefaults.standard
        let values: [String: Any] = ["selectedSessionID": session.id.uuidString, "appLanguage": "en",
            "enteringTimesWith": "timer", "requestedIPhoneTab": "", "smartCubeReadySound": false]
        let previous = values.map { ($0.key, defaults.object(forKey: $0.key)) }
        values.forEach { defaults.set($0.value, forKey: $0.key) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let probe = AppPerformanceProbe()
        window.rootViewController = UIHostingController(rootView: IPhoneContentView()
            .environment(\.managedObjectContext, context).environment(\.appPerformanceProbe, probe))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer {
            window.isHidden = true; window.rootViewController = nil
            previous.forEach { defaults.set($0.1, forKey: $0.0) }
        }
        func controller(_ root: UIViewController?) -> UITabBarController? {
            guard let root else { return nil }
            return (root as? UITabBarController) ?? root.children.compactMap { controller($0) }.first
        }
        for _ in 0..<500 where controller(window.rootViewController) == nil { try await Task.sleep(nanoseconds: 1_000_000) }
        let tabs = try XCTUnwrap(controller(window.rootViewController))
        for cycle in 0..<2 {
            for (index, name) in ["timer", "data", "algs", "explore", "settings"].enumerated() {
                let start = ProcessInfo.processInfo.systemUptime
                defaults.set(name, forKey: "requestedIPhoneTab")
                for _ in 0..<1000 where tabs.selectedIndex != index { try await Task.sleep(nanoseconds: 1_000_000) }
                XCTAssertEqual(tabs.selectedIndex, index)
                window.layoutIfNeeded()
                _ = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                print("[WholeAppPerf] tab=\(name) cycle=\(cycle) first_draw_ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000)")
                if name == "data" {
                    for _ in 0..<1000 where probe.dataCount == nil { try await Task.sleep(nanoseconds: 1_000_000) }
                    print("[WholeAppPerf] data_ready_ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000) rows=\(probe.dataCount ?? -1) fetches=\(probe.dataRequests)")
                    XCTAssertEqual(probe.dataCount, 1000, "The deferred Data tab must read its actual environment store")
                }
            }
        }
    }

    func testSnapshotReaderUsesItsOwnStoreAndReloadsSameCountCorrections() async throws {
        let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
        let session = Session(name: "Isolated", context: context)
        let solve = Solve(time: 10, event: "3x3", session: session, context: context)
        try context.save()
        let reader = SessionSolveSnapshotReader(viewContext: context)
        let first = try await reader.load(sessionID: session.id)
        XCTAssertEqual(first.map(\.id), [solve.id]); XCTAssertEqual(first.first?.time, 10)
        solve.time = 14; solve.resultRaw = "plusTwo"; try context.save()
        let corrected = try await reader.load(sessionID: session.id)
        XCTAssertEqual(corrected.count, 1); XCTAssertEqual(corrected.first?.adjustedTime, 16)
        let other = try await reader.load(sessionID: UUID()); XCTAssertTrue(other.isEmpty)
    }

    func testRepeatedDateFormattingMatchesUncachedLocaleSemanticsAndMeasuresBothPaths() async throws {
        let dates = (0..<500).map { Date(timeIntervalSince1970: 1_780_000_000 + Double($0 * 7777)) }
        var referenceTimes: [Double] = [], cachedTimes: [Double] = []
        for language in ["en", "zh-Hant", "ar"] {
            var start = ProcessInfo.processInfo.systemUptime
            let expected = dates.map { date -> String in
                let f = DateFormatter(); f.locale = appLocale(for: language); f.dateStyle = .medium; f.timeStyle = .short
                return f.string(from: date)
            }
            referenceTimes.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            start = ProcessInfo.processInfo.systemUptime
            let actual = dates.map { SolveMetrics.displayDate($0, languageCode: language) }
            cachedTimes.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            XCTAssertEqual(actual, expected)
        }
        let cache = SolveDisplayDateCache()
        let before = cache.string(dates[0], language: "en")
        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        XCTAssertEqual(cache.string(dates[0], language: "en"), before)
        let expected = SolveMetrics.displayDate(dates[0], languageCode: "en")
        let results = await withTaskGroup(of: String.self) { group in
            for _ in 0..<40 { group.addTask { SolveMetrics.displayDate(dates[0], languageCode: "en") } }
            var values: [String] = []; for await value in group { values.append(value) }; return values
        }
        XCTAssertEqual(Set(results), [expected])
        print("[WholeAppPerf] dates=500 locales=3 uncached_ms=\(referenceTimes) cached_ms=\(cachedTimes)")
    }
}

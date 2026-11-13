#if DEBUG && os(iOS)
import CoreData
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import CubeFlow

@MainActor final class NativeUIRecoveryTests: XCTestCase {
    private var artifacts: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(DataSearchIsolation.isDisabled
                ? "build/native-compositing-nov09/search-off" : "build/native-compositing-nov09/search-on")
    }
    private func window<Content: View>(_ view: Content, appearance: UIUserInterfaceStyle = .light, width: CGFloat = 393, useSceneBounds: Bool = false) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = useSceneBounds ? scene.coordinateSpace.bounds : CGRect(x: 0, y: 0, width: width, height: 852)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = appearance
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        return window
    }
    private func waitFor(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Mounted view did not reach the expected state", file: file, line: line)
        throw CancellationError()
    }
    private func image(_ window: UIWindow, named name: String) throws -> UIImage {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        try image.pngData()?.write(to: artifacts.appendingPathComponent(name + ".png"))
        return image
    }

    private func result(_ event: String, number: Int = 1, id: String? = nil, rank: Int? = nil,
                        type: String? = nil, types: [String]? = nil) -> CompetitionWCALiveCompetitorResult {
        .init(id: id ?? "\(event)-\(number)", ranking: 1, isAdvancing: nil, isAdvancingQuestionable: nil,
            attempts: [905, 999, -1, 1120, 1040], best: 905, average: 1050,
            singleRecordTag: "PR", averageRecordTag: "NR", roundID: "\(event)-\(number)",
            roundName: "Round \(number)", roundNumber: number, eventID: event, eventName: event,
            eventRank: rank, formatID: "a", numberOfAttempts: 5, sortBy: "average",
            officialRoundType: type, eventRoundTypes: types)
    }

    func testAllResultsStableForUnknownAndEqualRanksRegardlessOfCompletionOrder() {
        let ids = ["333oh", "222", "pyram", "333", "minx", "unexpected-z", "unexpected-a"]
        let expected = ["333", "222", "333oh", "minx", "pyram", "unexpected-a", "unexpected-z"]
        let rows = ids.flatMap { [result($0, number: 2, rank: nil), result($0, rank: nil)] }
        for pivot in rows.indices {
            let arrival = Array(rows[pivot...] + rows[..<pivot])
            let groups = CompetitionWCALiveCompetitorEventGroup.ordered(arrival)
            XCTAssertEqual(groups.map(\.id), expected)
            XCTAssertTrue(groups.allSatisfy { $0.results.map(\.roundNumber) == [1, 2] })
            for count in 1...arrival.count {
                let partial = CompetitionWCALiveCompetitorEventGroup.ordered(Array(arrival.prefix(count))).map(\.id)
                XCTAssertEqual(partial, expected.filter(partial.contains))
            }
        }
        XCTAssertEqual(CompetitionWCALiveCompetitorEventGroup.ordered([
            result("333", rank: 2), result("pyram", rank: 0), result("222", rank: 2)
        ]).map(\.id), ["pyram", "333", "222"], "Preserve provider rank; use canonical order only for ties")
    }

    func testEarlyRecentRecordPreviewRequiresExactProviderIdentityEventAndRound() throws {
        let wanted = result("333", number: 2)
        let person = CompetitionWCALiveCompetitorContent(id: "live-42", name: "Fixture",
            wcaID: "2020TEST01", countryISO2: "US", results: [result("333"), result("222", number: 2), wanted])
        let link = CompetitionWCALiveResultDeepLink(roundID: wanted.roundID, personID: "live-42",
            personWCAID: "2020test01", eventID: "333")
        let preview = try XCTUnwrap(link.result(in: person, region: "United States"))
        XCTAssertEqual(preview.id, wanted.id)
        XCTAssertEqual(preview.attempts, wanted.attempts)
        XCTAssertEqual(preview.singleRecordTag, wanted.singleRecordTag)
        XCTAssertEqual(preview.averageRecordTag, wanted.averageRecordTag)
        for mismatch in [
            CompetitionWCALiveResultDeepLink(roundID: wanted.roundID, personID: "live-99", personWCAID: "2020TEST01", eventID: "333"),
            .init(roundID: wanted.roundID, personID: "live-42", personWCAID: "2020TEST02", eventID: "333"),
            .init(roundID: wanted.roundID, personID: "live-42", personWCAID: nil, eventID: "222"),
            .init(roundID: "333-3", personID: "live-42", personWCAID: nil, eventID: "333")
        ] { XCTAssertNil(mismatch.result(in: person, region: nil)) }
    }

    func testSharePlacementAndToolbarDeleteAdaptToMeasuredText() {
        XCTAssertFalse(CompetitionResultShareActionLayout(title: "Short #1", cardWidth: 330, showsShare: true).shareBelowClose)
        XCTAssertTrue(CompetitionResultShareActionLayout(title: "A much longer competitor name #42", cardWidth: 330, showsShare: true).shareBelowClose)
        let wide = DataSelectionButtonLayout(availableWidth: 500, allTitle: "Select All", moveTitle: "Move 42", deleteTitle: "Delete")
        let narrow = DataSelectionButtonLayout(availableWidth: 245, allTitle: "Alle abwählen", moveTitle: "42 Zeiten verschieben", deleteTitle: "Löschen")
        XCTAssertFalse(wide.useTrash)
        XCTAssertTrue(narrow.useTrash)
        XCTAssertGreaterThanOrEqual(narrow.height, 44)
        XCTAssertGreaterThanOrEqual(narrow.width, 44)
        let localized = DataSelectionButtonLayout(availableWidth: 402, allTitle: "取消全选", moveTitle: "移动 81", deleteTitle: "删除")
        XCTAssertEqual(localized.iconActions, [false, false])
        let asymmetric = DataSelectionButtonLayout(availableWidth: 390, allTitle: "Deselect All", moveTitle: "Move",
            deleteTitle: "An exceptionally long destructive action")
        XCTAssertEqual(asymmetric.iconActions, [false, false])
        XCTAssertTrue(asymmetric.useTrash)
        let full = DataSelectionButtonLayout(availableWidth: 350, allTitle: "Deselect All", moveTitle: "Move 4,128",
            deleteTitle: "Delete", textScale: 1.1)
        XCTAssertEqual(full.iconActions, [false, false])
        let empty = DataSelectionButtonLayout(availableWidth: 350, allTitle: "Select All", moveTitle: nil,
            deleteTitle: "Delete", textScale: 1.1)
        XCTAssertEqual(empty.actionWidths[1], 0)
    }

    func testRoundLabelsUseOfficialTypesAndChinaSpecificEventStructure() {
        let stages = ["h", "d", "e", "c"]
        for (type, expected) in [("d", "初賽"), ("e", "複賽"), ("c", "決賽")] {
            let row = result("333", type: type, types: stages)
            XCTAssertEqual(CompetitionShareRow.reportRoundName(row, language: "zh-Hant", chinaStages: true), expected)
        }
        let second = result("333", type: "2", types: ["1", "2", "3", "f"])
        XCTAssertEqual(CompetitionShareRow.reportRoundName(second, language: "zh-Hant", chinaStages: true), PublishedCompetitionStrings.round("2", language: "zh-Hant"))
        let qualification = result("333", type: "h", types: stages)
        XCTAssertEqual(CompetitionShareRow.reportRoundName(qualification, language: "zh-Hant", chinaStages: true), PublishedCompetitionStrings.round("h", language: "zh-Hant"))
        let onlyFinal = result("333", type: "c", types: ["c"])
        XCTAssertEqual(CompetitionShareRow.reportRoundName(onlyFinal, language: "en", chinaStages: true), "Final")
        let unknown = result("333")
        XCTAssertEqual(CompetitionShareRow.reportRoundName(unknown, language: "zh-Hant", chinaStages: true), unknown.roundName)
    }

    func testMountedAllResultsMaintainsOrderAcrossAppearanceAndReplacement() async throws {
        let rows = ["333oh", "222", "pyram", "333", "minx"].map { result($0) }
        let expected = ["333", "222", "333oh", "minx", "pyram"]
        func content(_ results: [CompetitionWCALiveCompetitorResult]) -> CompetitionWCALiveCompetitorContent {
            .init(id: "ordering", name: "Stable event order", wcaID: nil, countryISO2: nil, results: results)
        }
        let card = CompetitionResultCardState()
        card.presentCompetition(id: "ordering", name: "Stable event order", content: content(rows))
        let round = try XCTUnwrap(card.selection?.round)
        CompetitionResultSeparatorDiagnostics.rows = [:]
        let window = try window(CompetitionResultExperience(round: round, languageCode: "en", cardState: card, mode: .card))
        defer { card.close(); window.isHidden = true; window.rootViewController = nil }
        try await waitFor { rows.allSatisfy { CompetitionResultSeparatorDiagnostics.rows[$0.id] != nil } }
        for (index, appearance) in [UIUserInterfaceStyle.light, .dark, .light].enumerated() {
            window.overrideUserInterfaceStyle = appearance
            card.selectedCompetitorContent = content(index.isMultiple(of: 2) ? rows : Array(rows.reversed()))
            try await Task.sleep(nanoseconds: 150_000_000)
            let frames = try rows.map { row in (row.eventID, try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows[row.id])) }
            XCTAssertEqual(frames.sorted { $0.1.minY < $1.1.minY }.map(\.0), expected)
            _ = try image(window, named: "all-results-order-\(index)")
        }
    }

    func testStackedAllResultsHeaderUsesAvailableSpaceBesideShare() async throws {
        let name = "Yiheng Wang 王艺衡 Long Mixed Name"
        let rows = (1...20).map { result("333", number: $0) }
        let content = CompetitionWCALiveCompetitorContent(id: "layout", name: name,
            wcaID: "2020TEST01", countryISO2: "CN", results: rows)
        let card = CompetitionResultCardState()
        card.presentCompetition(id: "layout", name: name, content: content)
        let round = try XCTUnwrap(card.selection?.round)
        let layout = CompetitionResultShareActionLayout(title: name, cardWidth: 288, showsShare: true)
        XCTAssertTrue(layout.shareBelowClose)
        XCTAssertEqual(layout.headerClearanceBeforeTable(spacing: 18) + 18
                       + CompetitionResultCardTitleStyle.contentInset,
                       CompetitionResultShareActionLayout.inset + 2 * CompetitionResultShareActionLayout.button
                       + CompetitionResultShareActionLayout.gap)
        XCTAssertGreaterThan(layout.followingFieldTrailingInset, 0)
        let window = try window(CompetitionResultExperience(round: round, languageCode: "zh-Hans", cardState: card, mode: .card)
            .environment(\.dynamicTypeSize, .xxLarge), appearance: .dark, width: 320)
        defer { card.close(); window.isHidden = true; window.rootViewController = nil }
        try await waitFor { card.allResultsHeight > 0 }
        XCTAssertGreaterThan(card.allResultsHeight, CompetitionResultCardGeometry.maximumHeight(in: window.bounds.size))
        _ = try image(window, named: "all-results-stacked-after")
    }

    func testStackedRoundHeaderFlowsBesideShare() async throws {
        let name = "Yiheng Wang 王艺衡 Long Mixed Name"
        let result = CompetitionWCALiveResultPreview(id: "result", ranking: 11, personID: "test",
            personWCAID: "2020TEST01", name: name, region: "China", attempts: [990, 1080, 1010, 1100, 1050],
            best: 990, average: 1047, isAdvancing: nil, isAdvancingQuestionable: nil,
            singleRecordTag: nil, averageRecordTag: "PR")
        let round = CompetitionWCALiveRound(id: "round", eventID: "333", eventName: "3x3", roundName: "Final",
            number: 1, formatID: "a", numberOfAttempts: 5, sortBy: "average", isFinished: true,
            advancementType: nil, advancementLevel: nil, isActive: false, isOpen: false, results: [result])
        let card = CompetitionResultCardState()
        card.present(result: result, round: round, loader: nil)
        let window = try window(CompetitionResultExperience(round: round, languageCode: "en", cardState: card, mode: .card),
                                appearance: .light, width: 320)
        defer { card.close(); window.isHidden = true; window.rootViewController = nil }
        try await waitFor { card.resultSummaryHeight > 0 }
        _ = try image(window, named: "round-stacked-after")
    }

    func testSharedAllResultsColumnsBenchmark() {
        let rounds = (0..<68).map { "Round \($0 % 4)" }
        let best = (0..<68).map { "\($0).20" }, averages = (0..<68).map { "\($0 + 5).40" }
        func plan() -> CompetitionAllResultsColumns {
            .init(roundNames: rounds, averageTexts: averages, bestTexts: best, hasAverage: true)
        }
        var before: [Double] = [], after: [Double] = []
        for _ in 0..<5 {
            var start = ProcessInfo.processInfo.systemUptime
            let repeated = (0..<17).map { _ in plan().minimumWidth }
            before.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            start = ProcessInfo.processInfo.systemUptime
            let shared = plan()
            let reused = (0..<17).map { _ in shared.minimumWidth }
            after.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            XCTAssertEqual(repeated, reused)
        }
        print("[NativeUIResults] rows=68 events=17 per_event_ms=\(before) shared_ms=\(after)")
    }

    func testColdMountedMyCompetitionsReadsModernIndexDespitePartialDetailCache() async throws {
        let html = #"""
        <script type="application/json" id="__NUXT_DATA__">[{"wcaCompetitionId":1,"nameZh":2,"alias":3,"name":4},"Fixture2026","東莞魔方比賽","dongguan-unrelated-slug","English Fixture"]</script>
        """#
        let names = CompetitionService.modernCompetitionNameIndex(html)
        XCTAssertEqual(names["fixture2026"]?.name, "東莞魔方比賽")
        XCTAssertEqual(names["dongguanunrelatedslug"]?.name, "東莞魔方比賽")
        let page = WCAMyCompetitionsPage(futureCompetitions: [.init(id: "Fixture2026", name: "English Fixture", website: nil,
            startDate: "2027-01-01", endDate: "2027-01-01", registrationOpen: nil, url: nil, city: nil,
            countryISO2: "CN", shortDisplayName: nil, registrationStatus: nil)], pastCompetitions: [],
            bookmarkedCompetitions: [], registrationsByCompetition: [:])
        let previous = CompetitionService.localizedCompetitionNamesForTesting
        let language = UserDefaults.standard.object(forKey: "appLanguage")
        defer {
            CompetitionService.localizedCompetitionNamesForTesting = previous
            UserDefaults.standard.set(language, forKey: "appLanguage")
        }
        for code in ["zh-Hans", "zh-Hant"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = CompetitionLocalizedNameStore(directory: directory)
            await store.merge(["unrelated": try XCTUnwrap(names["fixture2026"])])
            CompetitionService.localizedCompetitionNamesForTesting = (store, { _ in names })
            UserDefaults.standard.set(code, forKey: "appLanguage")
            let viewModel = WCAMyCompetitionsViewModel(fetch: { page })
            let window = try window(CompatibleNavigationContainer { WCAMyCompetitionsView(profile: nil, viewModel: viewModel) })
            defer { window.isHidden = true; window.rootViewController = nil }
            try await waitFor { viewModel.page != nil }
            let expected = code == "zh-Hans" ? "东莞魔方比赛" : "東莞魔方比賽"
            XCTAssertEqual(viewModel.localizedNames["Fixture2026"], expected)
            try await Task.sleep(nanoseconds: 120_000_000)
            let capture = try image(window, named: "my-competitions-\(code)")
            let request = VNRecognizeTextRequest()
            request.recognitionLanguages = [code, "en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: try XCTUnwrap(capture.cgImage)).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
                .replacingOccurrences(of: " ", with: "")
            XCTAssertTrue(text.contains(expected), "Actual mounted text: \(text)")
            XCTAssertFalse(text.contains("EnglishFixture"))
        }
    }

    private func sample(_ index: Int, time: Double? = nil, penalty: SolveResult = .solved) -> SessionSolveSample {
        .init(id: UUID(), date: Date(timeIntervalSince1970: Double(index) * 60), time: time ?? (10 + Double(index % 27) / 4),
            resultRaw: penalty.rawValue, scramble: "", comment: "", eventRawValue: "3x3")
    }

    func testChartPreservesSpikesRecordsPenaltiesAndExactSelection() async throws {
        var input = (0..<8000).map { sample($0) }
        input[798] = sample(798, time: 7, penalty: .plusTwo)
        input[799] = sample(799, time: 8, penalty: .dnf)
        input[811] = sample(811, time: 87)
        input[812] = sample(812, time: 6)
        let clock = ProcessInfo.processInfo.systemUptime
        let history = try await Task.detached { [input] in try SessionPerformanceHistory(input) }.value
        let layout = (ProcessInfo.processInfo.systemUptime - clock) * 1000
        XCTAssertEqual(history.observations.count, input.count)
        XCTAssertLessThanOrEqual(history.buckets.count, 192)
        XCTAssertEqual(history.observation(at: 799)?.time, 9)
        XCTAssertEqual(history.observation(at: 800)?.penalty, .dnf)
        XCTAssertNil(history.observation(at: 800)?.time)
        XCTAssertTrue(history.buckets.contains { $0.highest?.time == 87 })
        XCTAssertTrue(history.buckets.contains { $0.record?.time == 6 })
        XCTAssertEqual(history.observation(at: 813)?.ao12, SolveMetrics.averageValue(from: Array(input[801...812]), trimmingCount: 1))
        let points = SessionSolveTrend(solves: input).points
        let queries = (0..<256).map { $0 * 29 }.filter { $0 != 799 }
        var before: [Double] = [], after: [Double] = []
        for _ in 0..<5 {
            var start = ProcessInfo.processInfo.systemUptime
            let scanned = queries.map { index in
                let date = input[index].date
                return points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?.time
            }
            before.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            start = ProcessInfo.processInfo.systemUptime
            let indexed = queries.map { history.observation(at: $0 + 1)?.time }
            after.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            XCTAssertEqual(scanned, indexed)
        }
        print("[NativeUIChart] solves=8000 queries=\(queries.count) off_main_history_ms=\(layout) scan_ms=\(before) indexed_ms=\(after)")
    }

    @available(iOS 16.0, *)
    func testLineChartScreenshots() async throws {
        let rows = (0..<96).map { index in sample(index, time: 19 - Double(index) / 12 + Double(index % 7) * 0.5,
            penalty: index % 19 == 0 ? .dnf : index % 11 == 0 ? .plusTwo : .solved) }
        let history = try SessionPerformanceHistory(rows)
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            let window = try window(CompatibleNavigationContainer {
                ScrollView { SessionPerformanceLineChart(history: history, language: "en").padding(20) }
                    .navigationTitle("Solve Trend")
            }, appearance: appearance)
            defer { window.isHidden = true; window.rootViewController = nil }
            try await Task.sleep(nanoseconds: 120_000_000)
            _ = try image(window, named: "line-chart-\(appearance.rawValue)")
            let renderer = ImageRenderer(content: SessionPerformanceLineChart(history: history, language: "en")
                .padding(20).frame(width: 393)
                .environment(\.colorScheme, appearance == .dark ? .dark : .light)
                .background(appearance == .dark ? Color.black : Color.white))
            renderer.scale = 2
            let rendered = try XCTUnwrap(renderer.uiImage)
            try XCTUnwrap(rendered.pngData())
                .write(to: artifacts.appendingPathComponent("line-chart-rendered-\(appearance.rawValue).png"))
        }
    }

    func testMountedLargeSessionSheetPublishesEachChoiceAndLoadsOnlyFinalSelection() async throws {
        let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
        let first = Session(name: "Large 3x3", context: context)
        let second = Session(name: "Large Square-1", selectedEventRawValue: "sq1", context: context)
        for (session, count) in [(first, 3_569), (second, 4_505)] {
            for index in 0..<count {
                _ = Solve(time: 9 + Double(index % 100) / 5, date: Date(timeIntervalSince1970: Double(index)),
                    scramble: "R U", event: session.selectedEventRawValue, session: session, context: context)
            }
        }
        try context.save()
        let defaults = UserDefaults.standard
        let values: [String: Any] = ["selectedSessionID": first.id.uuidString, "enteringTimesWith": "timer",
            "dataSolveResultFilter": "all", "dataSolveSortOption": "newest"]
        let prior = values.map { ($0.key, defaults.object(forKey: $0.key)) }
        values.forEach { defaults.set($0.value, forKey: $0.key) }
        let probe = AppPerformanceProbe()
        let window = try window(VStack {
            TimerTabView(isActive: false).frame(height: 0).clipped().allowsHitTesting(false)
            DataTabView(isSelectingSolves: .constant(false))
        }.environment(\.managedObjectContext, context).environment(\.appPerformanceProbe, probe))
        defer {
            probe.dataOpenSessionSheet = nil; probe.dataSelection = nil; probe.dataSelect = nil; probe.dataToggleAll = nil
            probe.dataChooseSession = nil; probe.dataSessionSelection = nil; probe.dataCloseSessionSheet = nil
            window.isHidden = true; window.rootViewController = nil
            prior.forEach { defaults.set($0.1, forKey: $0.0) }
        }
        try await waitFor { probe.dataCount == 3_569 && probe.dataOpenSessionSheet != nil }
        let initialLoads = probe.dataRequests
        try XCTUnwrap(probe.dataOpenSessionSheet)()
        try await waitFor { probe.dataChooseSession != nil }
        _ = try image(window, named: "session-selector")
        var selectionMilliseconds: [Double] = []
        for id in [second.id, first.id, second.id, first.id, second.id] {
            let start = ProcessInfo.processInfo.systemUptime
            try XCTUnwrap(probe.dataChooseSession)(id)
            XCTAssertEqual(probe.dataSessionSelection?(), id.uuidString)
            XCTAssertEqual(defaults.string(forKey: "selectedSessionID"), id.uuidString)
            selectionMilliseconds.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            await Task.yield()
        }
        XCTAssertEqual(probe.dataRequests, initialLoads)
        XCTAssertEqual(probe.timerStatisticsReads, 0)
        XCTAssertEqual(probe.dataCount, 3_569, "Hidden destination must not publish intermediate lists")
        let dismissal = ProcessInfo.processInfo.systemUptime
        try XCTUnwrap(probe.dataCloseSessionSheet)()
        try await waitFor { probe.dataCount == 4_505 && probe.dataSelection?().visible.count == 4_505 }
        XCTAssertEqual(probe.dataRequests, initialLoads + 1)
        XCTAssertEqual(probe.timerStatisticsReads, 0)
        print("[LargeSessionSheet] synchronous_selection_ms=\(selectionMilliseconds) dismissal_to_visible_snapshot_ms=\((ProcessInfo.processInfo.systemUptime - dismissal) * 1_000)")
    }

    func testMountedDataRapidTransitionsPreserveNativeAccessoryAndSelection() async throws {
        let traceDirectory = artifacts.appendingPathComponent("nov11")
        try FileManager.default.createDirectory(at: traceDirectory, withIntermediateDirectories: true)
        print("[DataSearchIsolation] disabled=\(DataSearchIsolation.isDisabled)")
        let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
        let session = Session(name: "Native toolbar fixture", context: context)
        _ = Solve(time: 9.24, scramble: "R U F2", event: "3x3", session: session, context: context)
        let total = 1_021
        for value in 1..<total { _ = Solve(time: 9 + Double(value) / 5, scramble: "F R U'", event: "3x3", session: session, context: context) }
        try context.save()
        let suite = "NativeUIRecoveryTests.DataToolbar.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let values: [String: Any] = ["selectedSessionID": session.id.uuidString, "dataSolveResultFilter": "all",
            "dataSolveSortOption": "newest", "appLanguage": "en", "requestedIPhoneTab": "data",
            "enteringTimesWith": "timer", "smartCubeReadySound": false]
        values.forEach { defaults.set($0.value, forKey: $0.key) }
        let probe = AppPerformanceProbe()
        let window = try window(IPhoneContentView()
            .environment(\.managedObjectContext, context).environment(\.appPerformanceProbe, probe)
            .defaultAppStorage(defaults).environment(\.dynamicTypeSize, .xxLarge), useSceneBounds: true)
        defer {
            probe.dataSelect = nil; probe.dataToggleAll = nil; probe.dataToggleOne = nil; probe.dataSelection = nil
            window.isHidden = true; window.rootViewController = nil
        }
        func views(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(views) }
        func solveList() -> UIScrollView? {
            views(window).compactMap { $0 as? UIScrollView }.max { $0.contentSize.height < $1.contentSize.height }
        }
        func deleteToolbar() -> UIToolbar? {
            views(window).lazy.compactMap { $0 as? UIToolbar }.first { toolbar in
                toolbar.items?.contains { $0.accessibilityIdentifier == "data-selection-delete" } == true
            }
        }
        func deleteItem() -> UIBarButtonItem? {
            deleteToolbar()?.items?.first { $0.accessibilityIdentifier == "data-selection-delete" }
        }
        func assertLastSolveAboveBar(in list: UIScrollView, bar: UIView) async throws {
            let collection = try XCTUnwrap(list as? UICollectionView)
            let count = collection.numberOfItems(inSection: 0)
            XCTAssertGreaterThan(count, 0)
            let last = IndexPath(item: max(0, count - 1), section: 0)
            // Mount the self-sizing tail before measuring the true scroll limit.
            collection.scrollToItem(at: last, at: .bottom, animated: false)
            func bottom() -> CGFloat {
                collection.contentSize.height - collection.bounds.height + collection.adjustedContentInset.bottom
            }
            try await waitFor {
                collection.layoutIfNeeded()
                if abs(collection.contentOffset.y - bottom()) > 1 {
                    collection.setContentOffset(CGPoint(x: collection.contentOffset.x, y: bottom()), animated: false)
                    return false
                }
                return collection.indexPathsForVisibleItems.contains(last)
            }
            let cell = try XCTUnwrap(collection.cellForItem(at: last))
            print("[DataLastRow] rowBottom=\(cell.convert(cell.bounds, to: window).maxY) barTop=\(bar.convert(bar.bounds, to: window).minY) content=\(collection.contentSize.height) offset=\(collection.contentOffset.y)")
            XCTAssertLessThanOrEqual(cell.convert(cell.bounds, to: window).maxY,
                bar.convert(bar.bounds, to: window).minY + 1, "The last row must scroll clear of the native bar")
        }
        defer { _ = try? image(window, named: "data-native-toolbar-endpoint") }
        func tabOwner(_ controller: UIViewController?) -> UITabBarController? {
            (controller as? UITabBarController) ?? controller?.children.lazy.compactMap { tabOwner($0) }.first
        }
        try await waitFor { probe.dataSelection?().visible.count == total }
        let nativeTab: UITabBarController?
        if #available(iOS 26.0, *) { nativeTab = try XCTUnwrap(tabOwner(window.rootViewController)) }
        else { nativeTab = nil }
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            if #available(iOS 26.0, *), let nativeTab, !DataSearchIsolation.isDisabled {
                try await waitFor { nativeTab.bottomAccessory != nil }
            }
            window.overrideUserInterfaceStyle = appearance
            var signatures: Set<String> = []
            var geometrySamples: [[String: Double]] = []
            var bottomLayers: [[String]] = []
            let start = ProcessInfo.processInfo.systemUptime
            _ = try image(window, named: "data-search-\(appearance.rawValue)")
            let list = try XCTUnwrap(solveList())
            let initialHeight = list.bounds.height
            for atBottom in [false, true] {
                let scroll = try XCTUnwrap(solveList())
                let top = -scroll.adjustedContentInset.top
                let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: atBottom ? bottom : top), animated: false)
                for (transition, selection) in [true, false, true, false].enumerated() {
                  probe.dataSelect?(selection)
                  for sampleIndex in 0..<4 {
                    try await Task.sleep(nanoseconds: 16_000_000)
                    if !atBottom, transition < 2, sampleIndex == 1 {
                        let frame = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
                        }
                        try frame.pngData()?.write(to: traceDirectory.appendingPathComponent("data-\(appearance.rawValue)-\(transition)-intermediate.png"))
                        let windowLayer = window.layer.presentation() ?? window.layer
                        bottomLayers.append(views(window).compactMap { view -> String? in
                            let layer = view.layer.presentation() ?? view.layer
                            let frame = layer.convert(layer.bounds, to: windowLayer)
                            guard frame.width >= window.bounds.width * 0.9,
                                  frame.maxY > window.bounds.maxY - 150, frame.minY < window.bounds.maxY,
                                  !view.isHidden, layer.opacity > 0 else { return nil }
                            let parent = view.superview.map { String(describing: type(of: $0)) } ?? "-"
                            return "\(parent)/\(type(of: view)) \(frame.integral) opacity=\(layer.opacity) background=\(String(describing: layer.backgroundColor))"
                        })
                    }
                    let all = views(window)
                    let bars = all.filter { $0 is UINavigationBar || $0 is UIToolbar || $0 is UITabBar }
                    let frames = bars.flatMap { views($0) }.map { view -> String in
                        let layer = view.layer.presentation() ?? view.layer
                        return "\(layer.frame.integral):\(Int(layer.opacity * 100))"
                    }.joined(separator: "|")
                    signatures.insert(frames)
                    let scroll = all.compactMap { $0 as? UIScrollView }.max { $0.contentSize.height < $1.contentSize.height }
                    geometrySamples.append(["ms": (ProcessInfo.processInfo.systemUptime - start) * 1000,
                        "atBottom": atBottom ? 1 : 0, "windowBottom": window.safeAreaInsets.bottom,
                        "selecting": selection ? 1 : 0, "offsetY": scroll?.contentOffset.y ?? 0,
                        "bottomInset": scroll?.adjustedContentInset.bottom ?? 0, "height": scroll?.bounds.height ?? 0,
                        "tabY": nativeTab.map { ($0.tabBar.layer.presentation() ?? $0.tabBar.layer).frame.minY } ?? 0,
                        "tabOpacity": nativeTab.map { Double(($0.tabBar.layer.presentation() ?? $0.tabBar.layer).opacity) } ?? 0])
                  }
                }
            }
            try JSONSerialization.data(withJSONObject: geometrySamples, options: [.prettyPrinted, .sortedKeys])
                .write(to: traceDirectory.appendingPathComponent("data-toolbar-\(appearance.rawValue).json"))
            try JSONSerialization.data(withJSONObject: bottomLayers, options: [.prettyPrinted])
                .write(to: traceDirectory.appendingPathComponent("data-bottom-layers-\(appearance.rawValue).json"))
            print("[NativeUIToolbar] appearance=\(appearance.rawValue) samples=\(geometrySamples.count) distinct_geometry_states=\(signatures.count)")
            if #available(iOS 26.0, *) {
                // Losing the underlap briefly clips the list and exposes the tab
                // controller background, even if the final frame looks correct.
                let heights = geometrySamples.compactMap { $0["height"] }
                XCTAssertEqual(try XCTUnwrap(heights.min()), initialHeight, accuracy: 1)
                XCTAssertEqual(try XCTUnwrap(heights.max()), initialHeight, accuracy: 1)
            }
            probe.dataSelect?(true)
            if #available(iOS 26.0, *), let nativeTab {
                try await waitFor { (nativeTab.isTabBarHidden || nativeTab.tabBar.isHidden) && nativeTab.bottomAccessory == nil }
            }
            let ids = Array(try XCTUnwrap(probe.dataSelection?().visible))
            if #available(iOS 26.0, *) {
                try await waitFor { deleteItem()?.isEnabled == false }
                let item = try XCTUnwrap(deleteItem())
                try await assertLastSolveAboveBar(in: list, bar: XCTUnwrap(deleteToolbar()))
                // Wait only for each model state to reach UIKit, not for the
                // preceding presentation animation to finish.
                for enabled in [true, false, true, false] {
                    probe.dataToggleOne?(ids[0])
                    try await waitFor { deleteItem()?.isEnabled == enabled }
                    XCTAssertTrue(deleteItem() === item)
                }
                try await Task.sleep(nanoseconds: 400_000_000)
                XCTAssertFalse(item.isEnabled)
                XCTAssertTrue(deleteItem() === item)
            }
            probe.dataToggleOne?(ids[0])
            XCTAssertEqual(probe.dataSelection?().selected, [ids[0]])
            probe.dataToggleOne?(ids[0])
            XCTAssertEqual(probe.dataSelection?().selected, [])
            for id in ids.prefix(9) { probe.dataToggleOne?(id) }
            XCTAssertEqual(probe.dataSelection?().selected, Set(ids.prefix(9)))
            probe.dataToggleAll?()
            XCTAssertEqual(probe.dataSelection?().selected, Set(ids))
            probe.dataToggleAll?()
            XCTAssertEqual(probe.dataSelection?().selected, [])
            XCTAssertEqual(try context.count(for: Solve.fetchRequest()), total)
            probe.dataSelect?(false)
            try await waitFor { probe.dataSelection?().selected.isEmpty == true }
            if #available(iOS 26.0, *), let nativeTab {
                try await waitFor { !nativeTab.isTabBarHidden && !nativeTab.tabBar.isHidden &&
                    (DataSearchIsolation.isDisabled || nativeTab.bottomAccessory != nil) }
                try await waitFor { deleteItem() == nil }
                XCTAssertTrue(solveList() === list)
                if let accessory = nativeTab.bottomAccessory {
                    try await assertLastSolveAboveBar(in: list, bar: accessory.contentView)
                }
            }
        }
    }

    func testMountedSessionsTitleOnEdit() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Native Sessions alignment is used on iOS 26+") }
        let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
        let rowCount = 32
        for index in 0..<rowCount { _ = Session(name: "Session fixture \(index)", context: context) }
        try context.save()
        let probe = AppPerformanceProbe()
        for (appearance, language) in [(UIUserInterfaceStyle.light, "en"), (.dark, "ar")] {
            let suite = "NativeUIRecoveryTests.Sessions.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defaults.set(language, forKey: "appLanguage")
            defaults.set("data", forKey: "requestedIPhoneTab")
            let title = appLocalizedString("common.session", languageCode: language)
            let edit = appLocalizedString("common.edit", languageCode: language)
            let done = appLocalizedString("common.done", languageCode: language)
            let window = try window(IPhoneContentView()
                .environment(\.managedObjectContext, context).environment(\.appPerformanceProbe, probe)
                .defaultAppStorage(defaults), appearance: appearance, useSceneBounds: true)
            defer {
                probe.dataOpenSessionSheet = nil
                window.isHidden = true
                window.rootViewController = nil
                defaults.removePersistentDomain(forName: suite)
            }
            try await waitFor { probe.dataOpenSessionSheet != nil }
            try XCTUnwrap(probe.dataOpenSessionSheet)()

            func views(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(views) }
            func bar() -> UINavigationBar? {
                views(window).compactMap { $0 as? UINavigationBar }.first {
                    $0.topItem?.rightBarButtonItems?.first?.title == edit
                }
            }
            try await waitFor { bar() != nil }
            let navigation = try XCTUnwrap(bar())
            let item = try XCTUnwrap(navigation.topItem)
            let label = try XCTUnwrap(views(navigation).compactMap { $0 as? UILabel }.first { $0.text == title })
            func frame() -> CGRect {
                let layer = label.layer.presentation() ?? label.layer
                return layer.convert(layer.bounds, to: navigation.layer.presentation() ?? navigation.layer)
            }
            try await Task.sleep(nanoseconds: 420_000_000)
            let list = try XCTUnwrap(views(window).compactMap { $0 as? UICollectionView }.first {
                $0.numberOfSections == 1 && $0.numberOfItems(inSection: 0) == rowCount
            })
            let listFrame = list.convert(list.bounds, to: window)
            func deleteToolbar() -> UIToolbar? {
                views(window).compactMap { $0 as? UIToolbar }.first {
                    $0.items?.contains { $0.accessibilityIdentifier == "sessions-edit-delete" } == true
                }
            }
            let centered = frame()
            XCTAssertEqual(centered.midX, navigation.bounds.midX, accuracy: 1)
            for expected in [edit, done] {
                let start = frame()
                let button = try XCTUnwrap(item.rightBarButtonItems?.first)
                XCTAssertEqual(button.title, expected)
                XCTAssertEqual(button.style, .prominent)
                try XCTUnwrap(button.target as? NSObject).perform(try XCTUnwrap(button.action), with: button)
                var frames: [CGRect] = []
                for _ in 0..<24 {
                    try await Task.sleep(nanoseconds: 17_000_000)
                    XCTAssertNil(item.titleView)
                    XCTAssertTrue(label.isDescendant(of: navigation))
                    XCTAssertEqual(list.convert(list.bounds, to: window).maxY, listFrame.maxY, accuracy: 1)
                    frames.append(frame())
                }
                let model = label.convert(label.bounds, to: navigation)
                try await waitFor { abs(frame().midX - model.midX) < 0.5 }
                let end = frame()
                let minX = min(start.midX, end.midX), maxX = max(start.midX, end.midX)
                let yDrift = frames.map { abs($0.midY - centered.midY) }.max() ?? .infinity
                XCTAssertLessThanOrEqual(yDrift, 1)
                XCTAssertTrue(frames.contains { $0.midX > minX + 2 && $0.midX < maxX - 2 },
                    "A horizontal transition must have an intermediate presentation frame")
                if expected == done {
                    XCTAssertEqual(end.midX, centered.midX, accuracy: 1)
                    try await waitFor { deleteToolbar() == nil }
                } else if language == "en" {
                    XCTAssertLessThan(end.midX, centered.midX)
                } else {
                    XCTAssertGreaterThan(end.midX, centered.midX)
                }
                if expected == edit {
                    let toolbar = try XCTUnwrap(deleteToolbar())
                    let delete = try XCTUnwrap(toolbar.items?.first { $0.accessibilityIdentifier == "sessions-edit-delete" })
                    XCTAssertEqual(delete.style, .prominent)
                    XCTAssertEqual(delete.tintColor, .systemRed)
                    XCTAssertFalse(delete.isEnabled)
                    let toolbarFrame = toolbar.convert(toolbar.bounds, to: window)
                    XCTAssertGreaterThanOrEqual(listFrame.maxY + 1, toolbarFrame.maxY)
                    let last = IndexPath(item: rowCount - 1, section: 0)
                    list.scrollToItem(at: last, at: .bottom, animated: false)
                    try await waitFor {
                        list.layoutIfNeeded()
                        let bottom = list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom
                        if abs(list.contentOffset.y - bottom) > 1 {
                            list.setContentOffset(CGPoint(x: list.contentOffset.x, y: bottom), animated: false)
                            return false
                        }
                        return list.indexPathsForVisibleItems.contains(last)
                    }
                    let lastCell = try XCTUnwrap(list.cellForItem(at: last))
                    XCTAssertLessThanOrEqual(lastCell.convert(lastCell.bounds, to: window).maxY, toolbarFrame.minY + 1)
                    _ = try image(window, named: "sessions-native-bottom-\(appearance.rawValue)")
                }
                print("[SessionsTitle] appearance=\(appearance.rawValue) language=\(language) direction=\(navigation.effectiveUserInterfaceLayoutDirection.rawValue) \(expected) x=\(start.midX)->\(end.midX) maxVerticalDrift=\(yDrift)")
            }
            try XCTUnwrap(probe.dataCloseSessionSheet)()
            try await waitFor { probe.dataChooseSession == nil }
        }
    }

    func testBulkSolveLookupMatchesIndividualRequestsAcrossPredicateBatches() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let first = Session(name: "Bulk fixture", context: context)
        let other = Session(name: "Other session", context: context)
        let selected = Set((0..<1024).map { Solve(time: Double($0 + 1), scramble: "R U", event: "3x3",
            session: first, context: context).id })
        let unselected = Solve(time: 1, scramble: "F U", event: "3x3", session: other, context: context).id
        try context.save()
        let ids = selected.union([UUID()]) // A vanished ID is ignored as before.
        var before: [Double] = [], after: [Double] = []
        for _ in 0..<3 {
            let start = ProcessInfo.processInfo.systemUptime
            let individual = try ids.compactMap { try context.fetchSolve(with: $0)?.id }
            let middle = ProcessInfo.processInfo.systemUptime
            let batch = try context.fetchSolves(with: ids).map(\.id)
            before.append((middle - start) * 1000)
            after.append((ProcessInfo.processInfo.systemUptime - middle) * 1000)
            XCTAssertEqual(Set(individual), selected)
            XCTAssertEqual(Set(batch), selected)
            XCTAssertFalse(batch.contains(unselected))
        }
        print("[DataBulkLookup] ids=\(ids.count) individual_ms=\(before) batch_ms=\(after)")
    }

    func testDataSearchIndexMatchesReferenceAndRespondsToCancellation() async throws {
        let workload = (0..<4000).map { sample($0, time: 10 + Double($0) / 100,
            penalty: $0.isMultiple(of: 5) ? .dnf : $0.isMultiple(of: 3) ? .plusTwo : .solved) }
        let language = "en", decimals = 3
        func reference() -> [UUID: String] {
            let display = DateFormatter()
            display.locale = appLocale(for: language)
            display.dateStyle = .medium
            display.timeStyle = .short
            let iso = ISO8601DateFormatter()
            return Dictionary(uniqueKeysWithValues: workload.map { solve in
                let key = (SolveResult(rawValue: solve.resultRaw) ?? .solved)
                let result = key == .plusTwo ? "+2" : appLocalizedString(
                    key == .dnf ? "common.dnf" : "common.solved", languageCode: language)
                let event = PuzzleEvent(rawValue: solve.eventRawValue).map {
                    appLocalizedString($0.localizationKey, languageCode: language)
                } ?? solve.eventRawValue
                let text = [SolveMetrics.displayTime(for: solve, decimals: decimals), String(format: "%.3f", solve.time),
                    solve.comment, solve.scramble, display.string(from: solve.date), iso.string(from: solve.date),
                    result, solve.eventRawValue, event].joined(separator: " ")
                return (solve.id, DataSolveSearchIndex.normalized(text, locale: appLocale(for: language)))
            })
        }
        var before: [Double] = [], after: [Double] = []
        for _ in 0..<3 {
            let start = ProcessInfo.processInfo.systemUptime
            let old = reference()
            before.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            let worker = Task.detached {
                let start = ProcessInfo.processInfo.systemUptime
                let index = try DataSolveSearchIndex.make(workload, language: language, decimals: decimals)
                return (index, (ProcessInfo.processInfo.systemUptime - start) * 1000, pthread_main_np() != 0)
            }
            let (current, milliseconds, main) = try await worker.value
            after.append(milliseconds)
            XCTAssertFalse(main)
            XCTAssertEqual(current, old)
        }
        let cancelled = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try DataSolveSearchIndex.make(workload, language: language, decimals: decimals)
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled search index unexpectedly completed") }
        catch is CancellationError {}
        print("[DataSearchIndex] rows=\(workload.count) before_ms=\(before) after_ms=\(after)")
    }

    func testMountedSolveDetailDeleteUsesNativeRedConfiguration() async throws {
        let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
        let session = Session(name: "Detail fixture", context: context)
        let solve = Solve(time: 8.42, scramble: "R U", event: "3x3", session: session, context: context)
        try context.save()
        let detail = try window(SolveDetailAcceptance.view(for: solve).environment(\.managedObjectContext, context))
        defer { detail.isHidden = true; detail.rootViewController = nil }
        func delete(in view: UIView) -> UIButton? {
            if let button = view as? UIButton, button.accessibilityIdentifier == "solve-detail-delete" { return button }
            return view.subviews.lazy.compactMap { delete(in: $0) }.first
        }
        try await waitFor { delete(in: detail)?.isEnabled == true }
        let button = try XCTUnwrap(delete(in: detail))
        XCTAssertEqual(button.tintColor, .systemRed)
        XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
        _ = try image(detail, named: "solve-detail-delete")
    }

    func testRecordSummariesReuseIndexAndMatchFullWindowReference() {
        let solves = (0..<8_000).map { index in
            sample(8_000 - index, time: 3 + Double((index * 263) % 12_107) / 100,
                penalty: index % 11 == 0 ? .dnf : index % 7 == 0 ? .plusTwo : .solved)
        }
        let metrics = RecordAverageMetric.defaultMetrics
        var baseline: [Double] = [], after: [Double] = []
        func equalValue(_ lhs: Double?, _ rhs: Double?) -> Bool {
            lhs == rhs || (lhs?.isNaN == true && rhs?.isNaN == true)
        }
        for _ in 0..<5 {
            let start = ProcessInfo.processInfo.systemUptime
            let reference = metrics.map { metric in
                let evaluation = DataTabComputation.evaluateRecordMetric(metric: metric, solves: solves, includeWindowValues: true)
                let best = evaluation.windowValues.enumerated().compactMap { index, value in
                    value.flatMap { $0.isFinite ? (index, $0) : nil }
                }.min { $0.1 < $1.1 }?.0
                return (evaluation, best)
            }
            let middle = ProcessInfo.processInfo.systemUptime
            let summaries = DataTabComputation.evaluateRecordSummaries(metrics: metrics, solves: solves)
            let end = ProcessInfo.processInfo.systemUptime
            baseline.append((middle - start) * 1000)
            after.append((end - middle) * 1000)
            XCTAssertEqual(summaries.count, reference.count)
            for (summary, original) in zip(summaries, reference) {
                XCTAssertTrue(equalValue(summary.currentValue, original.0.currentValue))
                XCTAssertTrue(equalValue(summary.bestValue, original.0.bestValue))
                XCTAssertEqual(summary.bestFiniteIndex, original.1)
                XCTAssertTrue(summary.windowValues.isEmpty)
            }
        }
        print("[RecordSummaries] rows=\(solves.count) metrics=\(metrics.count) old_ms=\(baseline) new_ms=\(after)")
    }

    func testLargeDeselectAllSkipsRebuildingTheVisibleIDSet() {
        let rows = (0..<8_000).map { sample($0) }
        let visible = Set(rows.map(\.id))
        XCTAssertEqual(DataSelectionButtonLayout.toggledAll(selected: 0, visible: rows), visible)
        var previous: [Double] = [], current: [Double] = []
        for _ in 0..<5 {
            var oldCount = 0, newCount = 0
            let start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<30 {
                var selected = visible
                selected.subtract(Set(rows.map(\.id)))
                oldCount += selected.count
            }
            let middle = ProcessInfo.processInfo.systemUptime
            for _ in 0..<30 {
                newCount += DataSelectionButtonLayout.toggledAll(selected: visible.count, visible: rows).count
            }
            let end = ProcessInfo.processInfo.systemUptime
            XCTAssertEqual(oldCount, 0); XCTAssertEqual(newCount, oldCount)
            previous.append((middle - start) * 1_000); current.append((end - middle) * 1_000)
        }
        print("[DataDeselectBenchmark] rows=8000 repetitions=30 before_ms=\(previous) after_ms=\(current)")
    }

    func testDataFilterBoundsMatchReferenceWithoutTemporaryArrays() {
        let rows = (0..<8_000).map { index in
            sample(8_000 - index, time: Double(index % 60),
                   penalty: index % 7 == 0 ? .dnf : index % 5 == 0 ? .plusTwo : .solved)
        }
        var old: [Double] = [], current: [Double] = []
        for _ in 0..<5 {
            let start = ProcessInfo.processInfo.systemUptime
            let lower = rows.compactMap(\.adjustedTime).min()
            let upper = rows.compactMap(\.adjustedTime).max()
            let earliest = rows.map(\.date).min()
            let latest = rows.map(\.date).max()
            old.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            let next = ProcessInfo.processInfo.systemUptime
            let bounds = DataSolveFilterBounds(rows, includeTimes: true, includeDates: true)
            current.append((ProcessInfo.processInfo.systemUptime - next) * 1000)
            XCTAssertEqual(bounds.times?.lowerBound, lower)
            XCTAssertEqual(bounds.times?.upperBound, upper)
            XCTAssertEqual(bounds.dates?.lowerBound, earliest)
            XCTAssertEqual(bounds.dates?.upperBound, latest)
        }
        XCTAssertNil(DataSolveFilterBounds(rows, includeTimes: false, includeDates: true).times)
        XCTAssertNil(DataSolveFilterBounds([], includeTimes: true, includeDates: true).dates)
        print("[FilterBounds] rows=8000 old_ms=\(old) new_ms=\(current)")
    }

    func testSelectAllPredicateAvoidsRebuildingLargeVisibleIDSet() {
        let ids = (0..<10_000).map { _ in UUID() }
        let states = [Set<UUID>(), Set(ids.prefix(3000)), Set(ids)]
        var reference: [Double] = [], optimized: [Double] = []
        for _ in 0..<5 {
            var start = ProcessInfo.processInfo.systemUptime
            var before: [Bool] = []
            for _ in 0..<24 {
                for selected in states { before.append(selected.count >= ids.count && ids.allSatisfy(selected.contains)) }
            }
            reference.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            start = ProcessInfo.processInfo.systemUptime
            var after: [Bool] = []
            for _ in 0..<24 {
                for selected in states { after.append(DataSelectionButtonLayout.allSelected(selected: selected.count, visible: ids.count)) }
            }
            optimized.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            XCTAssertEqual(before, after)
        }
        print("[NativeUIData] rows=10000 updates=72 scan_ms=\(reference) count_ms=\(optimized)")
    }

    func testSessionDerivedIndexMatchesReferenceAndCancels() async throws {
        let rows: [SessionSolveSample] = (0..<16_000).reversed().map { index in
            let date = Date(timeIntervalSince1970: Double(index / 2))
            let time = 8 + Double((index * 17) % 1009) / 100
            let penalty = index.isMultiple(of: 11) ? "dnf" : (index.isMultiple(of: 7) ? "plusTwo" : "solved")
            return SessionSolveSample(id: UUID(), date: date, time: time, resultRaw: penalty,
                scramble: "R U", comment: "", eventRawValue: "3x3")
        }
        var baseline: [Double] = [], optimized: [Double] = []
        for _ in 0..<5 {
            var start = ProcessInfo.processInfo.systemUptime
            let positions = Dictionary(uniqueKeysWithValues: rows.enumerated().map {
                ($0.element.id, rows.count - $0.offset)
            })
            let bounds = DataSolveFilterBounds(rows, includeTimes: true, includeDates: true)
            var recordIDs: Set<UUID> = []
            var best: Double?
            for solve in rows.reversed() {
                guard let time = solve.adjustedTime else { continue }
                if best == nil || time < best! { recordIDs.insert(solve.id); best = time }
            }
            baseline.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            let result = try await Task.detached {
                let start = ProcessInfo.processInfo.systemUptime
                let value = try DataSessionDerivedIndex(rows)
                return (value, (ProcessInfo.processInfo.systemUptime - start) * 1000)
            }.value
            optimized.append(result.1)
            XCTAssertEqual(result.0.positions, positions)
            XCTAssertEqual(result.0.personalBests, recordIDs)
            XCTAssertEqual(result.0.bounds.times, bounds.times)
            XCTAssertEqual(result.0.bounds.dates, bounds.dates)
        }
        let worker = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try DataSessionDerivedIndex(rows)
        }
        worker.cancel()
        do { _ = try await worker.value; XCTFail("Cancelled derivation unexpectedly completed") }
        catch is CancellationError {}
        print("[DataSessionDerivedIndex] rows=\(rows.count) before_ms=\(baseline) worker_ms=\(optimized)")
    }

    func testAlgorithmSliceOrderingComputesKeysOnceAndPreservesStableOrder() throws {
        let payload = try XCTUnwrap(AlgLibraryLoader.load(.sq1CSP))
        let cases = payload.cases
        XCTAssertEqual(cases.count, 340)
        var baseline: [Double] = [], optimized: [Double] = []
        for _ in 0..<5 {
            var start = ProcessInfo.processInfo.systemUptime
            let old = cases.enumerated().sorted {
                let a = Double($0.element.sliceCount ?? Int.max)
                let b = Double($1.element.sliceCount ?? Int.max)
                return a == b ? $0.offset < $1.offset : a < b
            }.map(\.element)
            baseline.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            start = ProcessInfo.processInfo.systemUptime
            let new = AlgCaseOrdering.sorted(cases, by: "slices")
            optimized.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            XCTAssertEqual(new, old)
        }
        for key in ["likely", "unlikely"] {
            let ordered = cases.enumerated().sorted {
                let lhs = $0.element.probabilityExact?.value ?? $0.element.probability
                let rhs = $1.element.probabilityExact?.value ?? $1.element.probability
                let a = key == "likely" ? -(lhs ?? -.infinity) : (lhs ?? .infinity)
                let b = key == "likely" ? -(rhs ?? -.infinity) : (rhs ?? .infinity)
                return a == b ? $0.offset < $1.offset : a < b
            }
            XCTAssertEqual(AlgCaseOrdering.sorted(cases, by: key), ordered.map(\.element))
        }
        print("[AlgCaseOrdering] rows=\(cases.count) before_ms=\(baseline) after_ms=\(optimized)")
    }

    func testNativeCheckmarkIdentityAndSharedDeleteConfiguration() {
        XCTAssertEqual(SolveSelectionCheckmark(selected: true).symbol, "checkmark.circle.fill")
        XCTAssertEqual(SolveSelectionCheckmark(selected: false).symbol, "circle")
        XCTAssertNotNil(UIImage(systemName: "checkmark.circle.fill"))
        XCTAssertEqual(SessionNativeActionStyle.configuration(tint: .systemRed), SessionNativeActionStyle.configuration(tint: .systemBlue))
    }
}
#endif

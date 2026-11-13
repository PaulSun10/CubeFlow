import XCTest
import SwiftUI
import Combine
@testable import CubeFlow

@MainActor final class AlgSearchPerformanceTests: XCTestCase {
    func testGroupedCaseCountsAndSortedIDsBenchmark() {
        let cases = (0..<1_200).map { index in
            AlgCase(id: "case-\(index)", displayName: "", name: "", subgroup: "", imageKey: "",
                recognition: "", notes: "", setup: nil, algorithms: [])
        }
        let groups = (0..<12).map { group in
            AlgSubsetGroup(id: "group-\(group)", title: "", subsets: (0..<8).map { subset in
                let start = (group * 53 + subset * 31) % 900
                return AlgSubset(id: "subset-\(subset)", title: "", cases: Array(cases[start..<start + 250]))
            })
        } + [AlgSubsetGroup(id: "empty", title: "", subsets: [])]
        let expected = groups.map { group in Set(group.subsets.flatMap { $0.cases.map(\.id) }).sorted() }
        var times: [Double] = []
        for _ in 0..<5 {
            let start = ProcessInfo.processInfo.systemUptime
            let counts = groups.map(\.uniqueCaseCount)
            let ids = groups.map(\.uniqueCaseIDs)
            times.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            XCTAssertEqual(counts, expected.map(\.count))
            XCTAssertEqual(ids, expected)
        }
        print("[PerfAudit] alg_group_counts case_references=24000 ms=\(times)")
    }

    private func items(_ count: Int) -> [AlgSearchItem] {
        (0..<count).map { index in
            AlgSearchItem(id: String(index), kind: index % 3 == 0 ? .set : index % 3 == 1 ? .subset : .caseName,
                title: "Case \(index)", subtitle: "PLL", searchableText: ["PLL", "Category \(index)", "R U R' U'", "Éclair", "正面"],
                destination: .set(AlgSetPayload(puzzle: "3x3", set: "PLL", version: 1, source: "fixture", cases: [])))
        }
    }
    func testSearchGroupsStableIdentityNotationUnicodeAndEmptyResults() {
        let input = items(30)
        for query in ["pll", " R U R' ", "category 1", "正面"] {
            let expected = input.filter { $0.matches(query) }
            let result = AlgSearchResults(items: input, query: query)
            XCTAssertEqual(result.sets.map(\.id), expected.filter { $0.kind == .set }.map(\.id))
            XCTAssertEqual(result.subsets.map(\.id), expected.filter { $0.kind == .subset }.map(\.id))
            XCTAssertEqual(result.cases.map(\.id), expected.filter { $0.kind == .caseName }.map(\.id))
        }
        XCTAssertEqual(AlgSearchResults(items: input, query: "eclair").sets.count, 10)
        XCTAssertEqual(AlgSearchResults(items: input, query: "ＰＬＬ").sets.count, 10)
        XCTAssertTrue(AlgSearchResults(items: input, query: "not present").isEmpty)
        XCTAssertTrue(AlgSearchResults(items: input, query: "  ").isEmpty)
    }
    func testComparableRepeatedQueriesBeforeAndAfter() {
        let input = items(2000), queries = ["pll", "category 10", "R U", "missing"]
        var before: [Double] = [], after: [Double] = [], checksum = 0
        for _ in 0..<3 {
            var start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<5 { for query in queries { for kind in [AlgSearchItemKind.set, .subset, .caseName] {
                checksum += input.filter { $0.searchableText.joined(separator: " ").lowercased().contains(query.lowercased()) }.filter { $0.kind == kind }.count
            } } }
            before.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<5 { for query in queries {
                let result = AlgSearchResults(items: input, query: query)
                checksum += result.sets.count + result.subsets.count + result.cases.count
            } }
            after.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        XCTAssertGreaterThan(checksum, 0)
        print("[ExperiencePerf] alg_search items=2000 queries=20 trials=3 before_ms=\(before) after_ms=\(after) minimum_full_scans_before=3 after=1")
    }

    func testNavigationControllerSurvivesInactiveTabAndReactivation() async throws {
        let activity = AlgActivityFixtureModel()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: AlgActivityFixture(activity: activity))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func navigation(_ controller: UIViewController?) -> UINavigationController? {
            guard let controller else { return nil }
            return (controller as? UINavigationController) ?? controller.children.compactMap { navigation($0) }.first
        }
        for _ in 0..<100 { if navigation(window.rootViewController) != nil { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        let original = try XCTUnwrap(navigation(window.rootViewController))
        activity.active = false
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(navigation(window.rootViewController) === original)
        activity.active = true
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(navigation(window.rootViewController) === original)
    }
}

@MainActor private final class AlgActivityFixtureModel: ObservableObject { @Published var active = true }
private struct AlgActivityFixture: View {
    @ObservedObject var activity: AlgActivityFixtureModel
    var body: some View { AlgsTabView(isActive: activity.active) }
}

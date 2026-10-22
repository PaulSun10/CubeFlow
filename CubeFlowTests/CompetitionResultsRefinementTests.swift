import XCTest
import SwiftUI
import Combine
@testable import CubeFlow

@MainActor private final class TopDisclosureState: ObservableObject {
    @Published var expanded = false
    var visibility: CompetitionTopCubersVisibility?
}
@MainActor private final class ScrambleGroupState: ObservableObject {
    @Published var group = "A"
}
private struct ScrambleGroupHarness: View {
    @ObservedObject var state: ScrambleGroupState
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CompetitionResultsSelectorGroup {
                PublishedEventSelector(eventIDs: ["333", "222"], selection: .constant("333"), effectiveEvent: "333", language: "en")
            } rounds: {
                PublishedRoundSelector(rounds: [("final", "f")], selection: .constant("final"), language: "en",
                    trailingOptions: ["A", "B", "C"], trailingSelection: $state.group)
            }
            PublishedScrambleGroupHeading(group: state.group, language: "en")
        }.padding(16)
    }
}
private struct TopDisclosureHarness: View {
    @ObservedObject var state: TopDisclosureState
    let values: [CompetitionTopCuberPreview]
    var body: some View {
        CompetitionExpandableTopCubers(previews: values, language: "en", expansion: $state.expanded) { person in
            Text(person.name).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 8)
        }.onPreferenceChange(CompetitionTopCubersVisibilityKey.self) { state.visibility = $0 }.padding(16)
    }
}

@MainActor final class CompetitionResultsRefinementTests: XCTestCase {
    private func sums() throws -> [CubingChinaLiveSumRank] {
        try JSONDecoder().decode(CubingChinaLiveData<[CubingChinaLiveSumRank]>.self, from: CubingChinaUnifiedFixtures.sums).data
    }
    func testSumRankGenderRetainedAndUnknownIncludedOnlyInAll() throws {
        let values = try sums()
        XCTAssertEqual(values.first?.gender, "male")
        let bytes = String(data: CubingChinaUnifiedFixtures.sums, encoding: .utf8)!
            .replacingOccurrences(of: "\"gender\":\"male\"", with: "\"gender\":\"unspecified\"")
        let unknown = try JSONDecoder().decode(CubingChinaLiveData<[CubingChinaLiveSumRank]>.self, from: Data(bytes.utf8)).data
        XCTAssertEqual(CubingChinaSumRankDisplay.filtered(unknown, gender: "all").count, unknown.count)
        XCTAssertTrue(CubingChinaSumRankDisplay.filtered(unknown, gender: "male").isEmpty)
        XCTAssertTrue(CubingChinaSumRankDisplay.filtered(unknown, gender: "female").isEmpty)
    }
    func testSumRankWebsiteTieRequiresBothSumAndCountAndPreservesOrder() throws {
        let source = try sums()[0]
        func entry(_ sum: Int, _ count: Int) -> CubingChinaLiveSumRank {
            .init(competitor: source.competitor, sum: sum, count: count, ranks: source.ranks,
                enteredEventIds: source.enteredEventIds, gender: "female")
        }
        let values = [entry(100, 4), entry(100, 4), entry(100, 3), entry(120, 4)]
        XCTAssertEqual(CubingChinaSumRankDisplay.positions(values), [1, 1, 3, 4])
        XCTAssertEqual(CubingChinaSumRankDisplay.filtered(values, gender: "female").map(\.sum), [100, 100, 100, 120])
        XCTAssertEqual(CubingChinaSumRankDisplay.events([source]), CubingChinaSumRankDisplay.eventOrder)
        XCTAssertGreaterThan(source.ranks.count, source.enteredEventIds.count)
    }
    func testPersonalShortcutUsesVerifiedSumCompetitorEvenWhenSelectedRoundHasNoPersonalRow() throws {
        let values = try sums(), wcaID = try XCTUnwrap(values.first?.competitor.wcaId)
        XCTAssertEqual(CubingChinaPersonalShortcut.competitor(signedInWCAID: wcaID, results: [], sums: values)?.id, values.first?.competitor.id)
        for wrong in [wcaID.lowercased(), " " + wcaID, "Not an ID", "1999NONE01"] {
            XCTAssertNil(CubingChinaPersonalShortcut.competitor(signedInWCAID: wrong, results: [], sums: values))
        }
        XCTAssertNil(CubingChinaPersonalShortcut.competitor(signedInWCAID: wcaID, results: [], sums: []))
    }
    func testSmartDisplayIsExactAndNeverChangesNativeKeys() throws {
        XCTAssertEqual(CubingChinaEventDisplay.name("smart", language: "en"), "Smart Cube")
        XCTAssertNotEqual(CubingChinaEventDisplay.name("smart-other", language: "en"), "Smart Cube")
        let rounds = try JSONDecoder().decode([CubingChinaLiveRound].self, from: CubingChinaUnifiedFixtures.rounds)
        let smart = try XCTUnwrap(rounds.first { $0.eventId == "smart" })
        XCTAssertEqual(CubingChinaLivePresentation.options([smart], snapshot: nil, language: "en").first?.eventName, "Smart Cube")
        XCTAssertEqual(smart.key.eventID, "smart")
    }
    func testVisualRowsCountActualCompleteEntriesRatherThanThreePeople() {
        let ids = (0..<10).map(String.init)
        let frames = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, CGRect(x: CGFloat(index % 2) * 120, y: CGFloat(index / 2) * 35, width: 110, height: 25))
        })
        XCTAssertEqual(CompetitionTopCuberRows.visibleCount(ids: ids, frames: frames), 6)
        let wide = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, CGRect(x: CGFloat(index % 4) * 120, y: CGFloat(index / 4) * 35, width: 110, height: 25))
        })
        XCTAssertEqual(CompetitionTopCuberRows.visibleCount(ids: ids, frames: wide), 10)
        XCTAssertNil(CompetitionTopCuberRows.visibleCount(ids: ids, frames: [:]))
    }
    func testRepeatedDisclosureDoesNotDriftTheNativeScrollView() async throws {
        let values = (0..<24).map { CompetitionTopCuberPreview(id: String($0), name: "Competitor \($0)", badges: []) }
        for animated in [true, false] {
            let state = TopDisclosureState()
            try await mount(ScrollView {
                VStack(alignment: .leading) {
                    Color.clear.frame(height: 200)
                    TopDisclosureHarness(state: state, values: values)
                    Color.clear.frame(height: 1800)
                }
            }.transaction { if !animated { $0.disablesAnimations = true } }, name: "disclosure-scroll-\(animated)", width: 320) { window in
                let scroll = try XCTUnwrap(self.descendants(window).compactMap { $0 as? UIScrollView }.first { $0.contentSize.height > $0.bounds.height })
                scroll.setContentOffset(CGPoint(x: 0, y: 100), animated: false)
                let origin = scroll.contentOffset.y
                for _ in 0..<6 {
                    for expanded in [true, false] {
                        withAnimation(animated ? .easeInOut(duration: 0.32) : nil) { state.expanded = expanded }
                        try await Task.sleep(nanoseconds: 420_000_000)
                        XCTAssertEqual(scroll.contentOffset.y, origin, accuracy: 1, "Disclosure must only change content height, not accumulate offsets")
                        XCTAssertEqual(state.visibility?.visible, expanded ? values.count : state.visibility?.collapsed)
                    }
                }
            }
        }
    }
    func testSelectorSurfaceExactlyReusesResultsListDecoration() async throws {
        for dark in [false, true] {
            try await mount(HStack(spacing: 0) {
                Color.clear.frame(width: 180, height: 50).modifier(CompetitionResultsSurface()).padding(20)
                Color.clear.frame(width: 180, height: 50)
                    .modifier(CompetitionResultListDecoration(enabled: true, darkShadow: true)).padding(20)
            }.background(Color.gray), name: "selector-list-shadow-equal-\(dark)", width: 440, dark: dark) { window in
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                let source = try XCTUnwrap(image.cgImage)
                var bytes = [UInt8](repeating: 0, count: source.width * source.height * 4)
                let context = try XCTUnwrap(CGContext(data: &bytes, width: source.width, height: source.height,
                    bitsPerComponent: 8, bytesPerRow: source.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
                let half = source.width / 2
                var maximumDifference = 0
                for y in 0..<source.height {
                    for x in 0..<half {
                        let left = (y * source.width + x) * 4, right = (y * source.width + x + half) * 4
                        for channel in 0..<4 {
                            maximumDifference = max(maximumDifference, abs(Int(bytes[left + channel]) - Int(bytes[right + channel])))
                        }
                    }
                }
                XCTAssertLessThanOrEqual(maximumDifference, dark ? 0 : 1,
                    "Identical shadow styles may differ by one 8-bit quantization step in light-mode rasterization")
            }
        }
    }
    func testLiveHeadingInkCentersMatchTextForCubeAndBluetoothSymbols() async throws {
        let rounds = try JSONDecoder().decode([CubingChinaLiveRound].self, from: CubingChinaUnifiedFixtures.rounds)
        for event in ["333", "777", "smart"] {
            let round = try XCTUnwrap(rounds.first { $0.eventId == event })
            try await mount(CubingChinaResultsHeading(round: round, rounds: rounds, language: "en")
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .background(Color.white), name: "heading-aligned-\(event)", width: 640) { window in
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                    let glyph = try self.inkCenter(image, xRange: 16..<29)
                    let title = try self.inkCenter(image, xRange: 60..<600)
                    XCTAssertEqual(glyph, title, accuracy: 1.5, "Glyph ink must align to the title's capital-height center")
                }
        }
    }
    func testScrambleGroupHeadingTracksTheExistingGroupSelection() async throws {
        let state = ScrambleGroupState()
        try await mount(ScrambleGroupHarness(state: state), name: "scramble-group-A", width: 320) { window in
            state.group = "B"; try await Task.sleep(nanoseconds: 100_000_000)
            try self.snapshot(window, name: "scramble-group-B")
            state.group = "C"; try await Task.sleep(nanoseconds: 100_000_000)
            try self.snapshot(window, name: "scramble-group-C")
        }
    }
    func testPersonalBadgeKeepsSharedRowHeightAndLocalizes() async throws {
        XCTAssertEqual(PublishedCompetitionStrings.text("me", "en"), "Me")
        XCTAssertEqual(PublishedCompetitionStrings.text("me", "zh-Hans"), "我")
        for language in ["en", "zh-Hans"] {
            let row = CompetitionResultTableRow(rank: "1", name: "Very Long Competitor Name That Must Truncate",
                values: [.init(id: "average", text: "7.88", recordTag: "WR", width: 72), .init(id: "best", text: "6.52", recordTag: nil, width: 62)],
                isOwn: true, language: language)
                .modifier(CompetitionPersonalRowTreatment(isOwn: true)).frame(width: 320)
            let host = UIHostingController(rootView: row)
            XCTAssertEqual(host.sizeThatFits(in: CGSize(width: 320, height: 300)).height, 34, accuracy: 0.5)
            try await mount(row, name: "me-320-" + language, width: 320)
        }
    }
    func testSharedSelectorsScramblesGroupsAndNativeCapsulesMounted() async throws {
        for dark in [false, true] {
            try await mount(VStack(spacing: 12) {
                CompetitionResultsSelectorGroup {
                    PublishedEventSelector(eventIDs: ["333", "222", "skewb", "sq1", "smart"], selection: .constant("smart"), effectiveEvent: "smart", language: "en", cubingChinaLive: true)
                } rounds: {
                    PublishedRoundSelector(rounds: [("final", "f")], selection: .constant("final"), language: "en",
                        trailingOptions: ["A", "B", "C"], trailingSelection: .constant("B"))
                }
                PublishedScrambleGroupHeading(group: "B", language: "en")
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(["Official Results", "Live", "My Results"], id: \.self) { title in
                            Text(title).modifier(CompetitionNativeActionCapsule(tint: title == "Official Results"
                                ? CubingChinaNavigationColors.Section.results.foreground : title == "Live" ? .orange : .blue))
                        }
                    }
                }
            }.padding(16), name: "selectors-actions-\(dark)", width: 320, dark: dark)
        }
    }
    func testFullSumRankTableAndAccessibilityTextMounted() async throws {
        let values = try sums()
        for language in ["en", "zh-Hans", "zh-Hant"] {
            try await mount(CubingChinaSumRankTable(entries: values, language: language, ownWCAID: values.first?.competitor.wcaId).padding(16),
                name: "sum-ranks-" + language, width: 320, dark: language == "zh-Hant")
        }
        try await mount(CubingChinaSumRankTable(entries: values, language: "en").environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge),
            name: "sum-ranks-accessibility", width: 768)
    }
    func testReal362RowSumRankFixtureRetainsEveryColumnAndFilteredOrder() async throws {
        let values = try JSONDecoder().decode(CubingChinaLiveData<[CubingChinaLiveSumRank]>.self, from: CubingChinaSumRankLargeFixture.data).data
        XCTAssertEqual(values.count, 362); XCTAssertEqual(Set(values.map(\.id)).count, 362)
        XCTAssertEqual(CubingChinaSumRankDisplay.filtered(values, gender: "male").count, 309)
        XCTAssertEqual(CubingChinaSumRankDisplay.filtered(values, gender: "female").count, 53)
        XCTAssertEqual(CubingChinaSumRankDisplay.events(values).count, 18)
        XCTAssertEqual(CubingChinaSumRankDisplay.filtered(values, gender: "female").first?.competitor.name, "Xintong Wang")
        try await mount(ScrollView { CubingChinaSumRankTable(entries: values, language: "en").padding(16) }, name: "sum-ranks-362", width: 320)
    }
    func testTopCubersActualWrappingMeasuredAtCompactAndRegularWidths() async throws {
        let values = (0..<18).map { CompetitionTopCuberPreview(id: String($0), name: $0.isMultiple(of: 3) ? "Long Competitor Name \($0)" : "Cuber \($0)", badges: []) }
        for width in [CGFloat(320), 768] {
            let state = TopDisclosureState()
            try await mount(TopDisclosureHarness(state: state, values: values), name: "top-cubers-\(Int(width))", width: width) { window in
                let value = try XCTUnwrap(state.visibility)
                XCTAssertEqual(value.total, 18)
                XCTAssertEqual(value.visible, value.collapsed)
                XCTAssertGreaterThan(value.visible, 3, "Three rows are not three individual cubers")
                XCTAssertLessThanOrEqual(value.visible, value.total, "A wide layout may fit everyone in three rows and needs no disclosure")
                withAnimation(.easeInOut(duration: 0.32)) { state.expanded = true }
                try await Task.sleep(nanoseconds: 400_000_000)
                XCTAssertEqual(state.visibility?.visible, values.count)
                withAnimation(.easeInOut(duration: 0.32)) { state.expanded = false }
                try await Task.sleep(nanoseconds: 400_000_000)
                XCTAssertEqual(state.visibility?.visible, value.collapsed)
            }
            // A headless drawHierarchy call can capture a stale presentation layer
            // during animation. Mount the settled state separately for visual evidence.
            let settled = TopDisclosureState(); settled.expanded = true
            try await mount(TopDisclosureHarness(state: settled, values: values),
                name: "top-cubers-expanded-\(Int(width))", width: width) { _ in
                    XCTAssertEqual(settled.visibility?.visible, values.count)
                }
        }
    }
    private func mount<V: View>(_ view: V, name: String, width: CGFloat, dark: Bool = false,
        check: (UIWindow) async throws -> Void = { _ in }) async throws {
        let host = UIHostingController(rootView: view.frame(maxHeight: .infinity, alignment: .top))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 850)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(nanoseconds: 350_000_000)
        host.view.layoutIfNeeded()
        try snapshot(window, name: name)
        XCTAssertGreaterThan(host.view.bounds.width, 0)
        try await check(window)
        host.beginAppearanceTransition(false, animated: false); host.endAppearanceTransition()
    }
    private func snapshot(_ window: UIWindow, name: String) throws {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let directory = URL(fileURLWithPath: "/tmp/cubeflow-results-refinement-oct12/screenshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(image.pngData()).write(to: directory.appendingPathComponent(name + ".png"))
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private func inkCenter(_ image: UIImage, xRange: Range<Int>) throws -> CGFloat {
        let source = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: source.width * source.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: source.width, height: source.height,
            bitsPerComponent: 8, bytesPerRow: source.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        var rows: [Int] = []
        for y in 0..<source.height {
            for x in Int(CGFloat(xRange.lowerBound) * image.scale)..<Int(CGFloat(xRange.upperBound) * image.scale) {
                let offset = (y * source.width + x) * 4
                if bytes[offset] < 100 && bytes[offset + 1] < 100 && bytes[offset + 2] < 100 && bytes[offset + 3] > 200 {
                    rows.append(y); break
                }
            }
        }
        return CGFloat(try XCTUnwrap(rows.first) + XCTUnwrap(rows.last)) / (2 * image.scale)
    }
}

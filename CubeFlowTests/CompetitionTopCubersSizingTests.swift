import XCTest
import SwiftUI
import Combine
@testable import CubeFlow

@MainActor private final class TopSizingState: ObservableObject {
    @Published var expanded = false
    var visibility: CompetitionTopCubersVisibility?
}

private struct LoadedTopSizingRow: View {
    let values: [CompetitionTopCuberPreview]
    let glass: Bool
    let fixedEntries: Bool
    var productionEntries = false
    let language: String
    let textSize: DynamicTypeSize
    @ObservedObject var state: TopSizingState

    var body: some View {
        competitionDisclosureAcceptanceCard(glass: glass) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Competition").font(.headline)
                CompetitionLoadedTopCubers(competition: CompetitionPhysicalRegressionFixtures.beijing,
                    language: language, initial: .loaded(values), onState: { _ in },
                    cache: { _ in XCTFail("Loaded content must not fetch"); return nil },
                    fetch: { _, _ in XCTFail("Loaded content must not fetch"); return nil }) { previews in
                    Text("Top Cubers").font(.subheadline)
                    CompetitionExpandableTopCubers(previews: previews, language: language, expansion: $state.expanded) { item in
                        if productionEntries {
                            CompetitionTopCuberProfileChip(preview: item, language: language, iconsReady: true, open: { _ in })
                        } else if fixedEntries {
                            Text(item.name).frame(width: 100, height: 39)
                        } else {
                            Text(item.name).font(.body).padding(.horizontal, 10).padding(.vertical, 8)
                        }
                    }.onPreferenceChange(CompetitionTopCubersVisibilityKey.self) { state.visibility = $0 }
                        .competitionSizeDebug("section available", color: .blue)
                } placeholder: { Text("Unexpected loading") }
            }.padding(16)
        }.dynamicTypeSize(textSize)
    }
}

@available(iOS 16.0, *)
@MainActor private final class TopSizingCollection: NSObject, UICollectionViewDataSource {
    let window: UIWindow
    let collection: UICollectionView
    var root: AnyView

    init(width: CGFloat, root: AnyView) throws {
        self.root = root
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 900)
        collection = UICollectionView(frame: window.bounds, collectionViewLayout: CompetitionVerticalListLayout())
        super.init()
        collection.selfSizingInvalidation = .enabledIncludingConstraints
        collection.contentInsetAdjustmentBehavior = .never
        collection.register(CompetitionHostingCollectionViewCell.self, forCellWithReuseIdentifier: "row")
        collection.dataSource = self
        let controller = UIViewController(); controller.view = collection
        window.rootViewController = controller; window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        collection.reloadData(); collection.layoutIfNeeded()
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 2 }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "row", for: indexPath) as! CompetitionHostingCollectionViewCell
        cell.setRootView(indexPath.item == 0 ? root : AnyView(Text("Downstream row").frame(height: 200)))
        return cell
    }
    func recreate(_ root: AnyView) throws {
        self.root = root
        let cell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 0, section: 0)) as? CompetitionHostingCollectionViewCell)
        cell.prepareForReuse(); cell.setRootView(root)
        // Exercise the production fitting method before preferences have another run-loop turn.
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        attributes.frame = cell.frame
        _ = cell.preferredLayoutAttributesFitting(attributes)
        collection.collectionViewLayout.invalidateLayout(); collection.layoutIfNeeded()
    }
    func close() { window.isHidden = true; window.rootViewController = nil }
}

@available(iOS 16.0, *)
@MainActor final class CompetitionTopCubersSizingTests: XCTestCase {
    private func values(_ count: Int, long: Bool = false) -> [CompetitionTopCuberPreview] {
        (0..<count).map { .init(id: String($0), name: long ? "Long localized competitor name \($0)" : "Cuber \($0)", badges: []) }
    }
    private func row(_ values: [CompetitionTopCuberPreview], _ state: TopSizingState, glass: Bool = false,
                     fixed: Bool = true, production: Bool = false, language: String = "en", textSize: DynamicTypeSize = .large) -> AnyView {
        AnyView(LoadedTopSizingRow(values: values, glass: glass, fixedEntries: fixed, productionEntries: production,
                                  language: language, textSize: textSize, state: state))
    }
    private func settle(_ fixture: TopSizingCollection) async throws {
        for _ in 0..<12 {
            fixture.collection.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
    private func height(_ fixture: TopSizingCollection) throws -> CGFloat {
        try XCTUnwrap(fixture.collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))).size.height
    }
    private func recordedHeights() -> [Double] {
        CompetitionScrollOwnerDiagnostics.events.compactMap { event in
            guard event["event"] as? String == "preferred-size", event["row"] as? Int == 0,
                  let frame = event["preferred"] as? [Double] else { return nil }
            return frame[3]
        }
    }
    private func withRecording(_ work: () async throws -> Void) async throws {
        let key = CompetitionScrollOwnerDiagnostics.enabledKey
        let old = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key); CompetitionScrollOwnerDiagnostics.clear()
        defer {
            CompetitionScrollOwnerDiagnostics.clear()
            if let old { UserDefaults.standard.set(old, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        try await work()
    }
    private func assertStableFits(_ expected: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        let heights = recordedHeights()
        XCTAssertFalse(heights.isEmpty, file: file, line: line)
        for height in heights {
            XCTAssertEqual(height, expected, accuracy: 1, "No provisional empty-prefix height: \(heights)", file: file, line: line)
        }
    }

    func testFirstLoadedFitAndRepeatedHostingRecreationStayStableInBothAppearances() async throws {
        try await withRecording {
            for glass in [false, true] {
                CompetitionScrollOwnerDiagnostics.clear()
                let state = TopSizingState(), entries = values(12)
                let fixture = try TopSizingCollection(width: 390, root: row(entries, state, glass: glass))
                defer { fixture.close() }
                try await settle(fixture)
                let expected = try height(fixture)
                XCTAssertEqual(state.visibility?.collapsed, 9)
                XCTAssertEqual(state.visibility?.visible, 9)
                assertStableFits(expected)
                let downstream = try XCTUnwrap(fixture.collection.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))).frame.minY
                for _ in 0..<3 {
                    CompetitionScrollOwnerDiagnostics.clear()
                    let recreated = TopSizingState()
                    try fixture.recreate(row(entries, recreated, glass: glass))
                    try await settle(fixture)
                    assertStableFits(expected)
                    XCTAssertEqual(recreated.visibility?.visible, 9)
                    XCTAssertEqual(try XCTUnwrap(fixture.collection.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))).frame.minY,
                                   downstream, accuracy: 1)
                }
            }
        }
    }

    func testWidthAndContentChangesRecomputeExactRowsRatherThanReuseStaleSizing() async throws {
        let state = TopSizingState(), entries = values(12)
        let fixture = try TopSizingCollection(width: 390, root: row(entries, state))
        defer { fixture.close() }
        try await settle(fixture)
        XCTAssertEqual(state.visibility?.collapsed, 9)
        for (width, count) in [(CGFloat(220), 3), (CGFloat(600), 12), (CGFloat(390), 9)] {
            fixture.window.frame.size.width = width; fixture.collection.frame.size.width = width
            fixture.collection.collectionViewLayout.invalidateLayout()
            try await settle(fixture)
            XCTAssertEqual(state.visibility?.collapsed, count)
            XCTAssertEqual(state.visibility?.visible, count)
        }
        let before = try height(fixture)
        try fixture.recreate(row(values(2), state))
        try await settle(fixture)
        XCTAssertEqual(state.visibility?.visible, 2)
        XCTAssertEqual(state.visibility?.collapsed, 2)
        XCTAssertLessThan(try height(fixture), before)
    }

    func testDynamicTypeLocalizationAndChangedItemSizesAreMeasuredOnFirstFit() async throws {
        try await withRecording {
            for textSize in [DynamicTypeSize.large, .accessibility3] {
                for language in ["en", "zh-Hans"] {
                    CompetitionScrollOwnerDiagnostics.clear()
                    let state = TopSizingState()
                    let fixture = try TopSizingCollection(width: 320,
                        root: row(values(12, long: true), state, fixed: false, language: language, textSize: textSize))
                    defer { fixture.close() }
                    try await settle(fixture)
                    assertStableFits(try height(fixture))
                    XCTAssertGreaterThan(try XCTUnwrap(state.visibility).visible, 0)
                    CompetitionScrollOwnerDiagnostics.clear()
                    try fixture.recreate(row(values(12), state, fixed: false, language: language, textSize: textSize))
                    try await settle(fixture)
                    assertStableFits(try height(fixture))
                    let referenceState = TopSizingState()
                    let reference = try TopSizingCollection(width: 320,
                        root: row(values(12), referenceState, fixed: false, language: language, textSize: textSize))
                    defer { reference.close() }
                    try await settle(reference)
                    XCTAssertEqual(try height(fixture), try height(reference), accuracy: 1)
                    XCTAssertEqual(state.visibility, referenceState.visibility)
                }
            }
        }
    }

    func testExpandedSizingAndCollapseRetainAllEntriesAndOriginalHeight() async throws {
        let state = TopSizingState(), entries = values(12)
        let fixture = try TopSizingCollection(width: 390, root: row(entries, state))
        defer { fixture.close() }
        try await settle(fixture)
        let collapsed = try height(fixture)
        state.expanded = true
        try await settle(fixture)
        XCTAssertEqual(state.visibility?.visible, 12)
        XCTAssertGreaterThan(try height(fixture), collapsed)
        try fixture.recreate(row(entries, state))
        try await settle(fixture)
        XCTAssertEqual(state.visibility?.visible, 12)
        state.expanded = false
        try await settle(fixture)
        XCTAssertEqual(state.visibility?.visible, 9)
        XCTAssertEqual(try height(fixture), collapsed, accuracy: 1)
    }

    func testProductionChipsKeepFirstFitOnReuseAndEnvironmentChangesInBothAppearances() async throws {
        let defaults = UserDefaults.standard
        let debugKey = CompetitionTopCubersDebugBounds.key
        let savedBounds = defaults.object(forKey: debugKey)
        defaults.set(false, forKey: debugKey)
        defer {
            if let savedBounds { defaults.set(savedBounds, forKey: debugKey) }
            else { defaults.removeObject(forKey: debugKey) }
        }
        let entries: [CompetitionTopCuberPreview] = (0..<14).map { index in
            .init(id: String(format: "2019TEST%02d", index), name: index.isMultiple(of: 2) ? "Max Park" : "\u{738b}\u{827a}\u{8861} Yiheng Wang",
                  badges: [.init(id: "333", eventID: "333", tier: index < 3 ? .wr : index < 7 ? .cr : .nr)])
        }
        try await withRecording {
            for glass in [false, true] {
                for (language, size) in [("en", DynamicTypeSize.large), ("zh-Hans", .accessibility3)] {
                    CompetitionScrollOwnerDiagnostics.clear()
                    let state = TopSizingState()
                    let fixture = try TopSizingCollection(width: 390,
                        root: row(entries, state, glass: glass, production: true, language: language, textSize: size))
                    defer { fixture.close() }
                    try await settle(fixture)
                    let initial = try height(fixture)
                    assertStableFits(initial)
                    let visible = try XCTUnwrap(state.visibility?.visible)
                    XCTAssertGreaterThan(visible, 0)
                    XCTAssertLessThan(visible, entries.count)
                    for enabled in [true, false] {
                        CompetitionScrollOwnerDiagnostics.clear()
                        defaults.set(enabled, forKey: debugKey)
                        try await settle(fixture)
                        // An overlay-only update need not invalidate preferred
                        // sizing at all. If it does fit, no height may change.
                        for measured in recordedHeights() { XCTAssertEqual(measured, initial, accuracy: 1) }
                        XCTAssertEqual(try height(fixture), initial, accuracy: 1)
                        XCTAssertEqual(state.visibility?.visible, visible)
                    }
                    for _ in 0..<2 {
                        CompetitionScrollOwnerDiagnostics.clear()
                        try fixture.recreate(row(entries, state, glass: glass, production: true, language: language, textSize: size))
                        try await settle(fixture)
                        assertStableFits(initial)
                        XCTAssertEqual(state.visibility?.visible, visible)
                    }
                    state.expanded = true
                    try await settle(fixture)
                    XCTAssertEqual(state.visibility?.visible, entries.count)
                    XCTAssertGreaterThan(try height(fixture), initial)
                    state.expanded = false
                    try await settle(fixture)
                    XCTAssertEqual(try height(fixture), initial, accuracy: 1)
                }
            }
        }
    }
}

import XCTest
import SwiftUI
@testable import CubeFlow

nonisolated private struct IdentityFrameKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

@MainActor final class TargetedSmallUILayoutTests: XCTestCase {
    private let events = ["333", "222", "444", "555", "666", "777", "333bf", "333fm", "333oh", "clock", "minx", "pyram", "sq1"]
    func testPackingKeepsAllEntriesAcrossFirstFilledRowsWithoutOverflowMarkers() {
        let widths: [CGFloat] = [18, 19, 21, 18, 22, 18, 26, 18, 19, 18, 24, 20, 18]
        for available in [CGFloat(120), 180, 248, 278, 350] {
            let rows = ExploreEventPacking.rows(widths: widths, available: available)
            XCTAssertEqual(rows.flatMap { Array($0.indices) }, Array(widths.indices))
            for row in rows {
                let used = row.indices.map { widths[$0] }.reduce(0, +) + CGFloat(row.indices.count - 1) * row.spacing
                XCTAssertLessThanOrEqual(used, available + 0.001)
            }
        }
    }
    func testMountedRegionStripReservesFamilyRowsAtRealCardWidthsAndTextSizes() {
        for size in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
            for width in [CGFloat(120), 180, 248, 278] {
                let many = UIHostingController(rootView: ExploreCompetitionEventStrip(eventIDs: events, language: "en", availableWidth: width).environment(\.dynamicTypeSize, size))
                let one = UIHostingController(rootView: ExploreCompetitionEventStrip(eventIDs: ["333"], language: "en", availableWidth: width).environment(\.dynamicTypeSize, size))
                let manySize = many.sizeThatFits(in: CGSize(width: width, height: 1000))
                let oneSize = one.sizeThatFits(in: CGSize(width: width, height: 1000))
                XCTAssertEqual(manySize.height, oneSize.height, accuracy: 0.1)
                XCTAssertLessThanOrEqual(manySize.width, width)
                XCTAssertGreaterThan(manySize.height, 0)
            }
        }
    }
    func testIdentityTopIsAnchoredWithoutEstimatedRowHeightForDifferentTextSizes() async throws {
        for type in [DynamicTypeSize.large, .accessibility3] {
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 320, height: 320)
            var frame = CGRect.zero
            let view = ZStack(alignment: .topLeading) {
                SmartCubeIdentityAnchor(width: 180, origin: CGPoint(x: 160, y: 84)) {
                    HStack {
                        Text("WeiPo V5 AI").font(.subheadline.weight(.medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        DeviceBatteryIndicator(percentage: 86, isProminent: true)
                    }
                    .background(GeometryReader { proxy in Color.clear.preference(key: IdentityFrameKey.self,
                        value: proxy.frame(in: .named("identity-layout"))) })
                }
            }.frame(width: 320, height: 320).coordinateSpace(name: "identity-layout")
                .environment(\.dynamicTypeSize, type).onPreferenceChange(IdentityFrameKey.self) { frame = $0 }
            window.rootViewController = UIHostingController(rootView: view); window.windowLevel = .alert + 1; window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            for _ in 0..<50 where frame == .zero { window.layoutIfNeeded(); try await Task.sleep(nanoseconds: 10_000_000) }
            XCTAssertEqual(frame.minY, 84, accuracy: 0.5)
            XCTAssertEqual(frame.minX, 70, accuracy: 0.5)
            XCTAssertEqual(frame.width, 180, accuracy: 0.5)
            XCTAssertGreaterThan(frame.height, 10)
        }
    }
    func testCompactBatteryProminenceIsModerateAndClampingIsUnchanged() {
        let normal = UIHostingController(rootView: DeviceBatteryIndicator(percentage: 86))
        let prominent = UIHostingController(rootView: DeviceBatteryIndicator(percentage: 86, isProminent: true))
        let limit = CGSize(width: 200, height: 1000)
        let a = normal.sizeThatFits(in: limit), b = prominent.sizeThatFits(in: limit)
        XCTAssertGreaterThan(b.height, a.height)
        XCTAssertLessThan(b.height, a.height * 1.5)
        XCTAssertEqual(DeviceBatteryLevel.clamped(-1), 0)
        XCTAssertEqual(DeviceBatteryLevel.clamped(101), 100)
    }
}

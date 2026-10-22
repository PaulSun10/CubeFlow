import XCTest
import SwiftUI
import Combine
@testable import CubeFlow

@MainActor final class CompetitionProfileDiagnosticsTests: XCTestCase {
    @MainActor private final class RouteState: ObservableObject {
        @Published var selection: CompetitionTopCuberProfileSelection?
        let disclosure = CompetitionTopCuberDisclosure()
    }
    private struct LegacyProfileRoute: View {
        @ObservedObject var state: RouteState
        var body: some View {
            NavigationView {
                ScrollView { Text("Retained browser context").frame(height: 1600) }
                    .navigationTitle("Competitions")
                    .competitionTopCuberProfileDestination(selection: $state.selection)
            }.navigationViewStyle(.stack)
        }
    }
    private func preview(_ id: String) -> CompetitionTopCuberPreview {
        .init(id: id, name: "Same name is not identity", badges: [.init(id: "333", eventID: "333", tier: .wr)])
    }
    private func mount<V: View>(_ root: V) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIHostingController(rootView: root)
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return window
    }
    private func settle(_ window: UIWindow) async throws {
        for _ in 0..<10 { window.layoutIfNeeded(); try await Task.sleep(nanoseconds: 30_000_000) }
    }
    func testProfileSelectionUsesOnlyActualWCAIDAndRejectsMissingOrMalformedIDs() throws {
        XCTAssertEqual(CompetitionTopCuberProfileSelection(preview: preview(" 2019WANY36 "))?.id, "2019WANY36")
        XCTAssertNotEqual(CompetitionTopCuberProfileSelection(preview: preview("2019WANY36")),
                          CompetitionTopCuberProfileSelection(preview: preview("2015BORR01")))
        for invalid in ["", " ", "17", "person:2019WANY36", "2019wany36", "2019WANY36/", "2019WANY36\nwrong", "\u{738b}\u{827a}\u{8861}"] {
            XCTAssertNil(CompetitionTopCuberProfileSelection(preview: preview(invalid)), invalid)
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let bytes = try Data(contentsOf: root.appendingPathComponent("build/competition-final-ui-oct14/makati-wcif.json"))
        let values = CompetitionService.decodeCompetitionTopCuberPreviews(bytes, eventIDs: ["333", "222", "444", "555", "pyram", "skewb"]) ?? []
        XCTAssertFalse(values.isEmpty)
        XCTAssertTrue(values.allSatisfy { CompetitionTopCuberProfileSelection(preview: $0)?.id == $0.id })
    }

    func testProfileInteractionWrapperPreservesExactChipIntrinsicGeometry() {
        for size in [DynamicTypeSize.large, .accessibility3] {
            for id in ["2019WANY36", "missing"] {
                let value = preview(id)
                let plain = UIHostingController(rootView: CompetitionTopCuberChip(preview: value, language: "en", iconsReady: true).dynamicTypeSize(size))
                let routed = UIHostingController(rootView: CompetitionTopCuberProfileChip(preview: value, language: "en", iconsReady: true, open: { _ in }).dynamicTypeSize(size))
                let proposal = CGSize(width: 320, height: 10000)
                XCTAssertEqual(plain.sizeThatFits(in: proposal), routed.sizeThatFits(in: proposal))
            }
        }
    }

    func testExistingNativeLinkAlsoPushesFullPageInLegacyNavigationContainer() async throws {
        let state = RouteState()
        state.disclosure.expanded = true
        let window = try mount(LegacyProfileRoute(state: state))
        defer { window.isHidden = true; window.rootViewController = nil }
        try await settle(window)
        func controllers(_ root: UIViewController) -> [UIViewController] { [root] + root.children.flatMap(controllers) }
        let navigation = try XCTUnwrap(controllers(window.rootViewController!).compactMap { $0 as? UINavigationController }.first)
        let retained = try XCTUnwrap(navigation.viewControllers.first)
        state.selection = CompetitionTopCuberProfileSelection(preview: preview("2015BORR01"))
        try await settle(window)
        XCTAssertEqual(navigation.viewControllers.count, 2)
        XCTAssertNil(navigation.presentedViewController, "The existing route must never fall back to a sheet")
        XCTAssertEqual(navigation.topViewController?.view.bounds.width ?? 0, navigation.view.bounds.width, accuracy: 1)
        navigation.popViewController(animated: false)
        try await settle(window)
        XCTAssertTrue(navigation.viewControllers.first === retained)
        XCTAssertEqual(navigation.viewControllers.count, 1)
        XCTAssertTrue(state.disclosure.expanded)
        XCTAssertNil(state.selection)
    }

    func testDebugBoundsDefaultPersistenceLiveUpdatesAndLayoutNeutrality() async throws {
        let suite = "TopCuberBounds-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(defaults.bool(forKey: CompetitionTopCubersDebugBounds.key))
        let root = AnyView(VStack {
            CompetitionTopCuberChip(preview: preview("2019WANY36"), language: "en", iconsReady: true)
        }.competitionSizeDebug("section available", color: .blue).padding(30).defaultAppStorage(defaults))
        let window = try mount(root)
        defer { window.isHidden = true; window.rootViewController = nil }
        window.rootViewController?.view.backgroundColor = .white
        try await settle(window)
        let host = try XCTUnwrap(window.rootViewController as? UIHostingController<AnyView>)
        let proposal = CGSize(width: 320, height: 10000)
        let beforeSize = host.sizeThatFits(in: proposal)
        let before = try overlayPixels(window)
        let target = window.hitTest(CGPoint(x: 195, y: 422), with: nil)
        defaults.set(true, forKey: CompetitionTopCubersDebugBounds.key)
        try await settle(window)
        XCTAssertTrue(try XCTUnwrap(UserDefaults(suiteName: suite)).bool(forKey: CompetitionTopCubersDebugBounds.key))
        let shown = try overlayPixels(window)
        XCTAssertGreaterThan(shown.red, before.red + 100, "Chip outline/labels must appear live")
        XCTAssertGreaterThan(shown.blue, before.blue + 100, "Section outline/labels share the same setting")
        XCTAssertEqual(host.sizeThatFits(in: proposal), beforeSize)
        XCTAssertTrue(target === window.hitTest(CGPoint(x: 195, y: 422), with: nil))
        defaults.set(false, forKey: CompetitionTopCubersDebugBounds.key)
        try await settle(window)
        let hidden = try overlayPixels(window)
        XCTAssertEqual(hidden.red, before.red, accuracy: 10)
        XCTAssertEqual(hidden.blue, before.blue, accuracy: 10)
        XCTAssertEqual(host.sizeThatFits(in: proposal), beforeSize)
    }

    private func overlayPixels(_ window: UIWindow) throws -> (red: Int, blue: Int) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image {
            _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let bitmap = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: bitmap.width * bitmap.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: bitmap.width, height: bitmap.height,
                bitsPerComponent: 8, bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        }
        var red = 0, blue = 0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let r = bytes[index], g = bytes[index + 1], b = bytes[index + 2]
            if r > 200 && g < 120 && b < 120 { red += 1 }
            if b > 180 && r < 150 && g < 210 { blue += 1 }
        }
        return (red, blue)
    }

    func testPassiveWindowObserversNeverRecognizeDelayOrPreventTouchesAndDetach() throws {
        let store = CompetitionDebugStore.shared
        let wasEnabled = store.enabled
        store.setEnabled(true); store.start(.filter)
        defer { store.stop(.filter); store.setEnabled(wasEnabled) }
        let window = try mount(Color.white)
        defer { window.isHidden = true; window.rootViewController = nil }
        let anchor = CompetitionFilterInputAnchor(frame: CGRect(x: 320, y: 50, width: 44, height: 44), recordingEnabled: true)
        window.addSubview(anchor)
        anchor.refreshWindows()
        let extra = try mount(Color.clear)
        defer { extra.isHidden = true; extra.rootViewController = nil }
        for owner in [window, extra] {
            let observers = owner.gestureRecognizers?.compactMap { $0 as? CompetitionFilterTouchObserver } ?? []
            XCTAssertEqual(observers.count, 1)
            let observer = try XCTUnwrap(observers.first)
            XCTAssertFalse(observer.cancelsTouchesInView)
            XCTAssertFalse(observer.delaysTouchesBegan)
            XCTAssertFalse(observer.delaysTouchesEnded)
            XCTAssertFalse(observer.canPrevent(UITapGestureRecognizer()))
            XCTAssertFalse(observer.canBePrevented(by: UITapGestureRecognizer()))
            XCTAssertEqual(observer.state, .possible)
        }
        extra.frame.origin = CGPoint(x: 10.25, y: 20.5)
        let target = UIButton(type: .system)
        target.accessibilityIdentifier = "native-overlay-target"
        extra.rootViewController?.view.addSubview(target)
        let point = anchor.convert(CGPoint(x: 22, y: 22), to: extra)
        let metadata = CompetitionFilterTouchObserver.context(anchor: anchor, actualTarget: target, point: point, in: extra)
        XCTAssertEqual(metadata["insideFilterTarget"] as? Bool, true)
        XCTAssertEqual(metadata["window"] as? String, String(describing: ObjectIdentifier(extra)))
        XCTAssertEqual(metadata["anchorWindow"] as? String, String(describing: ObjectIdentifier(window)))
        XCTAssertEqual((metadata["presentedAnchorOnScreen"] as? [Double])?.count, 4)
        XCTAssertTrue((metadata["actualTargetPath"] as? [String])?.first?.contains("native-overlay-target") ?? false)
        XCTAssertEqual(CompetitionFilterTouchObserver.context(anchor: anchor, actualTarget: target, point: .zero,
            in: extra)["insideFilterTarget"] as? Bool, false)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(metadata))
        anchor.detach()
        for owner in [window, extra] {
            XCTAssertFalse(owner.gestureRecognizers?.contains { $0 is CompetitionFilterTouchObserver } ?? false)
        }
    }

    func testSeparatorSnapshotMeasuresNativeTransformsWithoutChangingGeometry() async throws {
        let window = try mount(Color.white)
        defer { window.isHidden = true; window.rootViewController = nil }
        let parent = UIView(frame: CGRect(x: 17.25, y: 100.125, width: 320, height: 160))
        window.addSubview(parent)
        parent.transform = CGAffineTransform(scaleX: 1, y: 1.015)
        let anchor = CompetitionSeparatorScreenAnchor(frame: CGRect(x: 0, y: 36, width: 300, height: 36.333333))
        anchor.layoutOriginY = 136.125; anchor.displayScale = window.screen.scale
        parent.addSubview(anchor)
        try await settle(window)
        let original = anchor.frame
        let values = CompetitionSeparatorScreenCapture.snapshot()
        let rows = try XCTUnwrap(values["boundaries"] as? [[String: Any]])
        let row = try XCTUnwrap(rows.first { ($0["id"] as? String) == String(describing: ObjectIdentifier(anchor)) })
        let pixels = try XCTUnwrap(row["modelScreenPixels"] as? [CGFloat])
        XCTAssertEqual(pixels[1] - pixels[0], 1.015, accuracy: 0.001)
        XCTAssertEqual(anchor.frame, original)
        XCTAssertFalse(anchor.isUserInteractionEnabled)
        XCTAssertNotNil(row["ancestors"])
        XCTAssertNotNil(row["presentedScreenPixels"])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(values))
    }

    func testActualRoundBoundaryMarkersAreLayoutNeutralAcrossTwoThreeAndFourRounds() async throws {
        let store = CompetitionDebugStore.shared
        let original = store.enabled
        store.setEnabled(true)
        defer { store.stop(.separator); store.setEnabled(original) }
        for rounds in [2, 3, 4] {
            let root = AnyView(VStack(spacing: 0) {
                CompetitionResultRoundRow(showsBoundary: true, boundaryAtBottom: true) { Text("Round header").frame(width: 320, height: 30) }
                ForEach(0..<rounds, id: \.self) { index in
                    CompetitionResultRoundRow(showsBoundary: index > 0) { Color.clear.frame(width: 320, height: 36) }
                }
            }.frame(width: 320))
            store.stop(.separator)
            let baselineWindow = try mount(root)
            try await settle(baselineWindow)
            let baselineHost = try XCTUnwrap(baselineWindow.rootViewController as? UIHostingController<AnyView>)
            let baseline = baselineHost.sizeThatFits(in: CGSize(width: 320, height: 10000))
            baselineWindow.isHidden = true; baselineWindow.rootViewController = nil
            store.start(.separator)
            let window = try mount(root)
            defer { window.isHidden = true; window.rootViewController = nil }
            try await settle(window)
            let host = try XCTUnwrap(window.rootViewController as? UIHostingController<AnyView>)
            XCTAssertEqual(host.sizeThatFits(in: CGSize(width: 320, height: 10000)), baseline)
            let values = try XCTUnwrap(CompetitionSeparatorScreenCapture.snapshot()["boundaries"] as? [[String: Any]])
                .filter { ($0["window"] as? String) == String(describing: ObjectIdentifier(window)) }
            XCTAssertEqual(values.count, rounds)
            for value in values {
                let frame = try XCTUnwrap(value["modelFrameInWindow"] as? [Double])
                XCTAssertEqual(frame[2], 320, accuracy: 0.01)
                XCTAssertGreaterThan(frame[3], 30)
            }
        }
    }
}

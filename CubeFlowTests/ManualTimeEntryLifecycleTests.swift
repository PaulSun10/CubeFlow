#if DEBUG && os(iOS)
import XCTest
import SwiftUI
import CoreData
@testable import CubeFlow

@MainActor final class ManualTimeEntryLifecycleTests: XCTestCase {
    func testBothInterfacesSaveAutomaticDisplayedValueOnceInEveryArrangement() async throws {
        for interface in ManualInputInterface.allCases {
            for arrangement in TimerArrangement.allCases {
                let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
                let session = Session(name: "Manual fixture", context: context)
                session.selectedTimingMethodRawValue = "typing"; try context.save()
                let defaults = UserDefaults.standard
                let settings: [String: Any] = ["selectedSessionID": session.id.uuidString, "enteringTimesWith": "typing",
                    "manualInputInterface": interface.rawValue, "manualTimeInterpretation": "smart",
                    "manualSmartDefault": 3, "timerArrangement": arrangement.rawValue,
                    "appLanguage": "en",
                    "smartCubeReadySound": false, "wcaInspectionEnabled": false]
                let old = settings.map { ($0.key, defaults.object(forKey: $0.key)) }
                settings.forEach { defaults.set($0.value, forKey: $0.key) }
                defer { old.forEach { defaults.set($0.1, forKey: $0.0) } }
                let probe = ManualTimeEntryProbe(), generator = SmartCubeTimerGuidanceProbe()
                generator.generate = { request, _, complete in complete(.init(context: request, scrambles: ["R U"])) }
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
                window.rootViewController = UIHostingController(rootView: TimerTabView().environment(\.managedObjectContext, context)
                    .environment(\.manualTimeEntryProbe, probe).environment(\.smartCubeTimerGuidanceProbe, generator))
                window.windowLevel = .alert + 1; window.makeKeyAndVisible()
                defer {
                    probe.edit = nil; probe.save = nil; probe.snapshot = nil
                    generator.reset(); window.isHidden = true; window.rootViewController = nil
                }
                try await wait { probe.edit != nil && generator.snapshot?().scramble == "R U" }
                probe.edit?("3512")
                XCTAssertEqual(probe.snapshot?().value, 3.512)
                probe.edit?("9210")
                XCTAssertEqual(probe.snapshot?().value, 9.21)
                if interface == .keypad {
                    try await wait("keypad frames \(arrangement.rawValue)", diagnostics: { "height=\(probe.measuredHeight) frames=\(probe.frames)" }) {
                        window.layoutIfNeeded()
                        guard let raw = probe.frames["display"], let save = probe.frames["save"], let viewport = probe.frames["viewport"] else { return false }
                        return raw.height > 0 && raw.minY >= viewport.minY - 1 && save.maxY <= viewport.maxY + 1
                    }
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                    let attachment = XCTAttachment(image: image); attachment.name = "manual-\(arrangement.rawValue)"; attachment.lifetime = .keepAlways; add(attachment)
                    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                        .appendingPathComponent("build/post-device-ux-nov02/manual-\(arrangement.rawValue).png")
                    try image.pngData()?.write(to: url)
                }
                probe.save?(); probe.save?()
                try await wait { session.solveList.count == 1 }
                let saved = try XCTUnwrap(session.solveList.first)
                XCTAssertEqual(saved.time, 9.21, accuracy: 0.000001)
                XCTAssertEqual(saved.scramble, "R U"); XCTAssertEqual(saved.inputSource, .manualEntry)
                XCTAssertEqual(probe.snapshot?().raw, "")
                probe.edit?("1:10.013"); XCTAssertEqual(probe.snapshot?().value, 70.013)
                XCTAssertEqual(saved.time, 9.21, accuracy: 0.000001, "Editing must not reinterpret saved solves")
            }
        }
    }

    func testDeleteRepeatStopsAfterReleaseAndRemoval() async throws {
        let button = ManualDeleteKey.DeleteButton()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        window.rootViewController = UIViewController()
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        window.rootViewController?.view.addSubview(button); window.makeKeyAndVisible()
        defer { button.stop(); window.isHidden = true; window.rootViewController = nil }
        var count = 0; button.delete = { count += 1 }
        button.begin(); XCTAssertEqual(count, 1)
        try await Task.sleep(nanoseconds: 430_000_000)
        XCTAssertGreaterThan(count, 1, "Holding a mounted key must repeat")
        button.stop()
        let stopped = count
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(count, stopped)
        button.begin(); button.removeFromSuperview()
        let removed = count
        try await Task.sleep(nanoseconds: 430_000_000)
        XCTAssertEqual(count, removed)
    }

    func testInlineEntryFitsCompactRegularAndAccessibilityContainers() async throws {
        for width in [CGFloat(320), 768] {
            let host = UIHostingController(rootView: ManualAdaptiveFixture()
                .environment(\.dynamicTypeSize, .accessibility2))
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: 1600)
            let size = host.sizeThatFits(in: CGSize(width: width, height: 1600))
            XCTAssertLessThanOrEqual(size.width, width + 1)
            XCTAssertGreaterThan(size.height, 200)
            XCTAssertLessThan(size.height, 1600)
        }
    }

    func testLongScramblesAndKeypadUseDisjointAllocatedRegions() async throws {
        let longScramble = Array(repeating: "3Rw2 U' Fw2 D B2 Lw' U2 Rw F2 D'", count: 10).joined(separator: " ")
        for arrangement in [TimerArrangement.cards, .split, .classic] {
            for event in [PuzzleEvent.threeByThree, .square1, .sevenBySeven] {
                let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
                let session = Session(name: "Layout", context: context)
                session.selectedTimingMethodRawValue = "typing"; session.selectedEventRawValue = event.rawValue
                try context.save()
                let defaults = UserDefaults.standard
                let settings: [String: Any] = ["selectedSessionID": session.id.uuidString, "enteringTimesWith": "typing",
                    "manualInputInterface": "keypad", "timerArrangement": arrangement.rawValue,
                    "scrambleDisplayMode": "shrinkFont", "appLanguage": "en"]
                let old = settings.map { ($0.key, defaults.object(forKey: $0.key)) }
                settings.forEach { defaults.set($0.value, forKey: $0.key) }
                defer { old.forEach { defaults.set($0.1, forKey: $0.0) } }
                let probe = ManualTimeEntryProbe(), generator = SmartCubeTimerGuidanceProbe()
                let scramble = event == .sevenBySeven ? longScramble : event == .square1
                    ? "(1,0) / (3,-3) / (0,3) / (-3,0) / (6,3) / (0,-3) /" : "R U2 F' L2 D B2 R' U F2 D2 L B'"
                generator.generate = { request, _, done in done(.init(context: request, scrambles: [scramble])) }
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 320, height: 852)
                window.rootViewController = UIHostingController(rootView: TimerTabView()
                    .environment(\.managedObjectContext, context).environment(\.dynamicTypeSize, .accessibility2)
                    .environment(\.manualTimeEntryProbe, probe).environment(\.smartCubeTimerGuidanceProbe, generator))
                window.windowLevel = .alert + 1; window.makeKeyAndVisible()
                defer { generator.reset(); probe.edit = nil; probe.save = nil; probe.snapshot = nil
                    window.isHidden = true; window.rootViewController = nil }
                try await wait("assigned \(event) scramble") { generator.snapshot?().scramble == scramble }
                try await wait("non-overlapping \(event) \(arrangement)", diagnostics: { "\(probe.frames)" }) {
                    window.layoutIfNeeded()
                    guard let header = probe.frames["scramble"], let text = probe.frames["scramble-text"], let entry = probe.frames["viewport"],
                          let display = probe.frames["display"], let save = probe.frames["save"] else { return false }
                    return header.height >= 44 && text.height > 0 && header.insetBy(dx: -1, dy: -1).contains(text)
                        && text.maxY < entry.minY && header.maxY < entry.minY && entry.contains(display) && entry.contains(save)
                }
                XCTAssertEqual(defaults.string(forKey: "timerArrangement"), arrangement.rawValue,
                    "Classic fallback must not overwrite the stored preference")
                XCTAssertEqual(generator.snapshot?().scramble, scramble)
                func saveButton(in view: UIView) -> UIButton? {
                    if let button = view as? UIButton, button.accessibilityIdentifier == "manual-time-save" { return button }
                    return view.subviews.compactMap { saveButton(in: $0) }.first
                }
                let save = try XCTUnwrap(saveButton(in: window))
                XCTAssertEqual(save.titleLabel?.numberOfLines, 1)
                XCTAssertLessThanOrEqual(save.titleLabel?.font.pointSize ?? .infinity, 22)
                if event == .sevenBySeven {
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                        .appendingPathComponent("build/post-device-ux-nov02/manual-long-7x7-\(arrangement.rawValue).png")
                    try image.pngData()?.write(to: url)
                }
            }
        }
    }

    private func wait(_ label: String = #function, diagnostics: () -> String = { "" }, _ condition: () -> Bool) async throws {
        for _ in 0..<500 { if condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTFail("Manual input mounted lifecycle timeout: \(label) \(diagnostics())"); throw CancellationError()
    }
}

private struct ManualAdaptiveFixture: View {
    @State private var draft = ManualTimeDraft(raw: "110013")
    @FocusState private var focus: Bool
    var body: some View {
        ManualTimeEntry(draft: $draft, interface: .keypad,
            selected: ManualTimeCandidate(seconds: 70.013, decimals: 3), canSave: true,
            compact: true, save: {}, focus: $focus)
            .padding(16)
    }
}
#endif

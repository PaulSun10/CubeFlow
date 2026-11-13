#if DEBUG && os(iOS)
import XCTest
import SwiftUI
import CoreData
import CoreBluetooth
import Vision
@testable import CubeFlow

@MainActor final class BattleMixedInputTests: XCTestCase {
    func testSignedHandicapPenalizesOnlyTheGivingPlayer() {
        var handicap = LocalBattleHandicap()
        XCTAssertEqual(handicap.adjusted(8, for: .first), 8)
        XCTAssertEqual(handicap.adjusted(10, for: .second), 10)
        handicap.set(5, for: .first)
        XCTAssertEqual(handicap.seconds(for: .second), -5)
        XCTAssertEqual(handicap.adjusted(8, for: .first), 13)
        XCTAssertEqual(handicap.adjusted(10, for: .second), 10)
        handicap.set(4, for: .second)
        XCTAssertEqual(handicap.seconds(for: .first), -4)
        XCTAssertEqual(handicap.adjusted(8, for: .first), 8)
        XCTAssertEqual(handicap.adjusted(10, for: .second), 14)
        handicap.set(-20, for: .first)
        XCTAssertEqual(handicap.seconds(for: .second), 10)
    }

    func testSmartTimerAcceptsOnlyOwnedRunAndUsesHardwareResult() {
        let devices = LocalBattleDevices()
        var starts: [LocalBattlePlayer] = [], stops: [Double] = [], cancellations: [LocalBattlePlayer] = []
        var scrambleReady = false
        devices.setEnabled(true)
        devices.setConfiguration(.init(input: .smartTimer), for: .second)
        devices.setConfiguration(.init(input: .smartTimer), for: .first)
        XCTAssertEqual(devices.configuration(.first).input, .touch)
        devices.start = { player, _ in starts.append(player); return scrambleReady }
        devices.finishSmartTimer = { _, solve in stops.append(solve.seconds) }
        devices.invalidate = { cancellations.append($0) }
        devices.receiveSmartTimerState(.running, startedAt: .distantPast)
        XCTAssertTrue(starts.isEmpty)
        let start = Date.now.addingTimeInterval(1), stop = start.addingTimeInterval(2)
        devices.receiveSmartTimerState(.ready, startedAt: nil)
        devices.receiveSmartTimerState(.running, startedAt: start)
        scrambleReady = true
        devices.receiveSmartTimerState(.running, startedAt: start.addingTimeInterval(0.05))
        devices.receiveSmartTimerCompletion(.init(seconds: 1, startedAt: start, stoppedAt: stop))
        XCTAssertEqual(starts, [.second], "The current run cannot start again when the scramble becomes ready")
        XCTAssertTrue(stops.isEmpty)
        devices.receiveSmartTimerState(.ready, startedAt: nil)
        let repeatedStart = start.addingTimeInterval(0.1)
        let solve = GANTimerCompletedSolve(seconds: 1.894, startedAt: repeatedStart, stoppedAt: stop)
        devices.receiveSmartTimerState(.running, startedAt: start)
        devices.receiveSmartTimerState(.running, startedAt: repeatedStart)
        XCTAssertEqual(starts, [.second, .second])
        devices.receiveSmartTimerCompletion(.init(seconds: 1, startedAt: .distantPast, stoppedAt: stop))
        XCTAssertTrue(stops.isEmpty)
        devices.receiveSmartTimerCompletion(solve)
        devices.receiveSmartTimerCompletion(solve)
        devices.receiveSmartTimerState(.finished, startedAt: nil)
        XCTAssertEqual(stops, [1.894])
        XCTAssertTrue(cancellations.isEmpty)
        devices.receiveSmartTimerState(.running, startedAt: stop)
        devices.receiveSmartTimerState(.disconnected, startedAt: nil)
        devices.receiveSmartTimerCompletion(.init(seconds: 2, startedAt: stop, stoppedAt: stop))
        XCTAssertEqual(cancellations, [.second])
        XCTAssertEqual(stops, [1.894])
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTFail("Battle did not reach expected state")
    }

    func testMountedManualAndTouchAreIndependentAndManualCanStartNextRound() async throws {
        let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
        let session = Session(name: "Mixed input", context: context); try context.save()
        let defaults = UserDefaults.standard
        let settings: [String: Any] = ["selectedSessionID": session.id.uuidString, "enteringTimesWith": "timer",
            "appLanguage": "en", "smartCubeReadySound": false, "wcaInspectionEnabled": false]
        let previous = settings.map { ($0.key, defaults.object(forKey: $0.key)) }
        settings.forEach { defaults.set($0.value, forKey: $0.key) }
        defer { previous.forEach { defaults.set($0.1, forKey: $0.0) }; AppOrientationManager.reset() }
        let probe = LocalBattleTestProbe(), generation = SmartCubeTimerGuidanceProbe()
        generation.generate = { context, _, complete in complete(.init(context: context, scrambles: ["R U"])) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let host = UIHostingController(rootView: TimerTabView().environment(\.managedObjectContext, context)
            .environment(\.smartCubeTimerGuidanceProbe, generation).environment(\.localBattleTestProbe, probe))
        let tabs = UITabBarController()
        tabs.viewControllers = [host, UIViewController()]
        window.rootViewController = tabs; window.makeKeyAndVisible()
        defer { probe.mode?(.solo); probe.configure = nil; probe.manual = nil; generation.reset(); window.isHidden = true; window.rootViewController = nil }
        try await wait { probe.mode != nil && probe.configure != nil }
        probe.mode?(.headToHead)
        try await wait { probe.snapshot?().scrambles.displayed.count == 2 }
        window.layoutIfNeeded()
        let capture = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let recognition = VNRecognizeTextRequest()
        try VNImageRequestHandler(cgImage: try XCTUnwrap(capture.cgImage)).perform([recognition])
        let labels = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        XCTAssertFalse(labels.contains("Touch Timer"), "Do not render the redundant input footer")
        probe.configure?(.first, .init(input: .manual))
        let originalSecond = probe.snapshot?().scrambles.displayed[.second]
        XCTAssertEqual(probe.manual?(.first, "1234"), true)
        XCTAssertEqual(probe.manual?(.first, "5678"), false, "First player's finished round cannot be overwritten")
        XCTAssertEqual(probe.snapshot?().scrambles.displayed[.second], originalSecond)
        probe.press?(.second); probe.release?(.second)
        XCTAssertNotNil(probe.snapshot?().secondStart, "A touch player does not require the manual player to hold a timer")
        XCTAssertNil(probe.snapshot?().firstStart)
        try await Task.sleep(nanoseconds: 20_000_000)
        probe.release?(.second)
        XCTAssertEqual(probe.snapshot?().scrambles.completed.count, 2)
        let priorFirst = probe.snapshot?().scrambles.completed[.first]
        probe.configure?(.second, .init(input: .manual))
        XCTAssertEqual(probe.manual?(.first, "1567"), true, "A fully scored round permits the next manual solve")
        XCTAssertNotEqual(probe.snapshot?().scrambles.completed[.first], priorFirst)
        XCTAssertEqual(probe.manual?(.second, "1765"), true)
        XCTAssertEqual(probe.manual?(.first, "invalid"), false)
        // A fully scored round is displayed until the next legal start. It
        // must not be reclassified as a finished NEW round after tab return.
        let manager = SmartCubeBluetoothManager.shared
        let ids = [UUID(), UUID()]
        let target = try XCTUnwrap(SmartCubeBluetoothManager.facelets(afterApplying: "R U"))
        defer { ids.forEach { manager.disconnect(deviceID: $0) } }
        // Keep simulated peripherals independent of the simulator radio's
        // asynchronous unsupported-state callback. Battle uses these same
        // per-device canonical feeds through the production manager lookup.
        let cubes = ids.map { id in
            let cube = SmartCubePeripheralSession(central: CBCentralManager(delegate: nil, queue: nil))
            cube.debugSeedConnectedState(deviceID: id, attemptID: UUID(), facelets: target)
            manager.debugInstallSession(cube, for: id)
            return cube
        }
        for (index, player) in LocalBattlePlayer.allCases.enumerated() {
            probe.configure?(player, .init(input: .smartCube, deviceID: ids[index]))
        }
        let appearance = probe.appearanceCount
        let disappearance = probe.disappearanceCount
        tabs.selectedIndex = 1
        try await wait { probe.disappearanceCount > disappearance }
        tabs.selectedIndex = 0
        try await wait { probe.appearanceCount > appearance }
        XCTAssertEqual(probe.snapshot?().scrambles.displayed[.first]?.text, "R U")
        XCTAssertEqual(probe.snapshot?().scrambles.displayed[.second]?.text, "R U")
        for cube in cubes { XCTAssertTrue(cube.isReadyForMoveObservation, "Fixture observation readiness: \(cube.observationReadiness)") }
        try await wait { probe.snapshot?().ready.count == 2 }
        cubes[0].debugEmitPhysicalMove("F")
        XCTAssertNotNil(probe.snapshot?().firstStart, "Both ready cubes may start a fresh round after returning")
        XCTAssertNil(probe.snapshot?().secondStart)
    }

    func testSettledBattlePanelsAndSimultaneousConfigurationSnapshots() async throws {
        let probe = LocalBattleTestProbe()
        let owner = LocalBattleDevices()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let content = LocalBattleContent(mode: .headToHead, firstEvent: .sevenBySeven, secondEvent: .threeByThree,
            firstScramble: Array(repeating: "3Rw2 U' Fw2 D B2 Lw' U2 Rw F2 D'", count: 6).joined(separator: " "), secondScramble: "R U F2 L' B U2 R2 F D'",
            firstElapsed: 12.345, secondElapsed: 8.765, isFirstRunning: false, isSecondRunning: false,
            isFirstPressing: false, isSecondPressing: false, firstScore: 2, secondScore: 1,
            firstHandicapSeconds: 0, secondHandicapSeconds: 0, firstFinishedTime: nil, secondFinishedTime: nil,
            timerTextStyle: AnyShapeStyle(.primary), scrambleTextStyle: AnyShapeStyle(.primary),
            formatDisplayedTime: { String(format: "%.3f", $0) }, canSelectEvent: { _ in true }, onExit: {},
            onSelectEvent: { _, _ in }, onSelectHandicap: { _, _ in }, onPressPlayer: { _ in },
            onReleasePlayer: { _ in }, onCancelPlayer: { _ in }, devices: owner)
        window.rootViewController = UIHostingController(rootView: content.background(Color(uiColor: .systemBackground))
            .environment(\.localBattleTestProbe, probe))
        window.windowLevel = .alert + 2; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await wait { probe.selectorOpen != nil }
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/native-recovery-nov09")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func snapshot(_ name: String) throws {
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            try image.pngData()?.write(to: directory.appendingPathComponent(name))
        }
        try snapshot("battle-panels.png")
        probe.selectorOpen?(.first); probe.selectorOpen?(.second)
        XCTAssertEqual(probe.selectorSnapshot?(), .second)
        try await Task.sleep(nanoseconds: 350_000_000)
        try snapshot("battle-dual-configuration.png")
        probe.selectorDismiss?()
        XCTAssertNil(probe.selectorSnapshot?())
        try await Task.sleep(nanoseconds: 350_000_000)
        try snapshot("battle-one-configuration.png")

        window.frame = CGRect(x: 0, y: 0, width: 320, height: 700)
        window.overrideUserInterfaceStyle = .dark
        probe.selectorOpen = nil
        probe.overrideReduceMotion = true
        window.rootViewController = UIHostingController(rootView: content.background(Color(uiColor: .systemBackground))
            .environment(\.localBattleTestProbe, probe))
        try await wait { probe.selectorOpen != nil }
        probe.selectorOpen?(.first)
        probe.selectorDismiss?()
        probe.selectorOpen?(.second)
        XCTAssertEqual(probe.selectorSnapshot?(), .second)
        window.layoutIfNeeded()
        await Task.yield()
        try snapshot("battle-small-dark-reduce-motion.png")
        probe.selectorDismiss?()
        XCTAssertNil(probe.selectorSnapshot?())
    }
}
#endif

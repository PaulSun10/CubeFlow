#if DEBUG && os(iOS)
import XCTest
import SwiftUI
import SceneKit
import CoreBluetooth
import CoreData
@testable import CubeFlow

@MainActor final class PhysicalRecoveryRegressionTests: XCTestCase {
    private func wait(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Mounted production state did not converge", file: file, line: line)
        throw CancellationError()
    }
    private func cubes(_ root: UIView) -> [SCNView] {
        (root as? SCNView).map { [$0] } ?? root.subviews.flatMap(cubes)
    }
    private func window<V: View>(_ content: V) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: content)
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        return window
    }
    private func apply(_ move: String, _ state: String) throws -> String {
        try XCTUnwrap(CubeLayerTurn(move)?.applying(to: state, size: state.count == 24 ? 2 : 3))
    }
    func testTwentyTPSForTenSecondsKeepsEveryCanonicalMoveAndBoundsVisualLagAtMultipleRefreshRates() throws {
        for refresh in [30, 60, 120] {
            for size in [2, 3] {
                var presentation = CubeTurnPresentation(size: size, facelets: CubeSurface.solved(size: size))
                presentation.tps = 10
                var state = presentation.canonical, turns = 0, maximumPending = 0
                var now = 0.0
                while now <= 10.5 {
                    while turns < 200, Double(turns) * 0.05 <= now {
                        let move = ["R", "U", "F2", "L'", "D", "B'"][turns % 6]
                        state = try apply(move, state)
                        presentation.enqueue(move, target: state, timestamp: Double(turns) * 0.05, now: now)
                        XCTAssertEqual(presentation.canonical, state, "Animation can never delay physical state")
                        turns += 1
                    }
                    presentation.advance(at: now)
                    maximumPending = max(maximumPending, presentation.pending.count)
                    if turns == 200, presentation.current == nil, presentation.pending.isEmpty { break }
                    now += 1 / Double(refresh)
                }
                XCTAssertEqual(turns, 200)
                XCTAssertEqual(presentation.settled, state)
                XCTAssertNil(presentation.current)
                XCTAssertLessThan(now - 9.95, 0.4, "No long replay after the last physical turn")
                XCTAssertLessThan(maximumPending, 12)
                print("[PhysicalRecovery] size=\(size) input=200 refresh=\(refresh) max_pending=\(maximumPending) stop_lag_ms=\((now - 9.95) * 1000) visual_coalesced=\(presentation.coalescedVisualTurns)")
            }
        }
    }
    func testSlowAndNormalTurnsPreserveEveryAnimationAndOldBurstConvergesWithoutReplayingIt() throws {
        for interval in [0.5, 0.125] {
            var value = CubeTurnPresentation(facelets: CubeSurface.solved(size: 3))
            var state = value.canonical
            for index in 0..<20 {
                let now = Double(index) * interval
                state = try apply(index.isMultiple(of: 2) ? "R" : "U", state)
                value.enqueue(index.isMultiple(of: 2) ? "R" : "U", target: state, timestamp: now, now: now)
                let animation = try XCTUnwrap(value.current)
                XCTAssertGreaterThan(animation.progress(at: now + animation.duration / 2), 0)
                value.advance(at: now + animation.duration + 0.0001)
                XCTAssertEqual(value.settled, state)
                XCTAssertEqual(value.coalescedVisualTurns, 0)
            }
        }
        var value = CubeTurnPresentation(facelets: CubeSurface.solved(size: 3))
        var state = value.canonical
        for _ in 0..<100 { state = try apply("R", state); value.enqueue("R", target: state, timestamp: 0, now: 0) }
        value.advance(at: 1)
        XCTAssertLessThanOrEqual(value.pending.count, 2)
        XCTAssertGreaterThan(value.coalescedVisualTurns, 90)
        for frame in 1...30 { value.advance(at: 1 + Double(frame) / 120) }
        XCTAssertEqual(value.settled, state); XCTAssertNil(value.current)
    }

    func testTwoActualMountedRenderersWakeImmediatelyAndConvergeAfterTwoHundredPhysicalEvents() async throws {
        let owners = [SmartCube3DView.Coordinator(), SmartCube3DView.Coordinator()]
        let feeds = [SmartCubeCanonicalFeed(), SmartCubeCanonicalFeed()]
        let container = UIViewController()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.rootViewController = container
        let views = owners.map { $0.makeView(owner: "physical-recovery-stress") }
        var states = [CubeSurface.solved(size: 3), CubeSurface.solved(size: 3)]
        for index in owners.indices {
            views[index].frame = CGRect(x: 0, y: index * 200, width: 190, height: 190)
            container.view.addSubview(views[index])
            owners[index].update(facelets: states[index], stateRevision: 0, fixedView: .urf, size: 3,
                events: feeds[index].events, attemptID: UUID(), trusted: true, tps: 10,
                appearance: .classic, plastic: .black, reflections: false, customColor: .blue, canonicalSequence: 0)
        }
        window.makeKeyAndVisible()
        defer { owners.forEach { $0.stop() }; window.isHidden = true; window.rootViewController = nil }
        for index in owners.indices {
            let range = try XCTUnwrap(owners[index].debugRequestedFrameRange)
            XCTAssertEqual(range.preferred, Float(window.screen.maximumFramesPerSecond))
            XCTAssertTrue(owners[index].debugClockIsPaused)
        }
        for turn in 0..<200 {
            for index in owners.indices {
                let move = index == 0 ? ["R", "U", "F2"][turn % 3] : ["L'", "D", "B"][turn % 3]
                states[index] = try apply(move, states[index])
                feeds[index].send(move: .init(move: move, serial: nil, face: nil, direction: nil,
                    localTimestamp: .now, cubeTimestampMilliseconds: nil), facelets: states[index])
                XCTAssertEqual(owners[index].debugPresentation.canonical, states[index])
                XCTAssertFalse(owners[index].debugClockIsPaused)
                XCTAssertTrue(views[index].rendersContinuously)
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let stopped = ProcessInfo.processInfo.systemUptime
        try await wait { owners.allSatisfy { $0.debugPresentation.current == nil && $0.debugPresentation.pending.isEmpty } }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - stopped, 0.5)
        for index in owners.indices {
            XCTAssertEqual(owners[index].debugPresentation.settled, states[index])
            XCTAssertEqual(feeds[index].history.count, min(120, 200))
            XCTAssertTrue(owners[index].debugClockIsPaused)
            XCTAssertFalse(views[index].rendersContinuously)
        }
    }

    func testConnectedManagementRemainsAvailableWithoutBatteryOrResolvedPolicy() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let saved = SavedSmartCubeDevices(defaults: defaults)
        let manager = SmartCubeBluetoothManager(testSavedDevices: saved), id = UUID(), attempt = UUID()
        let session = SmartCubePeripheralSession(central: CBCentralManager(delegate: nil, queue: nil))
        session.debugSeedConnectedState(deviceID: id, attemptID: attempt, facelets: CubeSurface.solved(size: 3), name: "GAN Fixture")
        session.debugAwaitConnectionPolicy()
        manager.debugInstallSession(session, for: id)
        var selected: UUID?
        let window = try window(SmartCubeManagementCard(manager: manager, saved: saved, selectedID: id, dismiss: {})
            .environment(\.smartCubeManagementSelection, { id, _ in selected = id }))
        defer { window.isHidden = true; window.rootViewController = nil; manager.disconnect(deviceID: id) }
        try await wait { selected == id }
        XCTAssertNil(session.batteryLevel)
        XCTAssertFalse(session.observationReadiness.isReady, "Management is not permission to weaken observation readiness")
        func button(_ view: UIView) -> UIButton? {
            if let button = view as? UIButton, button.accessibilityIdentifier == "smart-cube-management-disconnect" { return button }
            return view.subviews.compactMap(button).first
        }
        try await wait { button(window) != nil }
        let disconnect = try XCTUnwrap(button(window)); XCTAssertTrue(disconnect.isEnabled)
        disconnect.sendActions(for: .touchUpInside)
        XCTAssertFalse(session.isConnected)
    }

    func testActualTimerBindsSelectedTwoByTwoAcrossRemountAndDeviceChanges() async throws {
        let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
        let selected = Session(name: "Physical recovery", selectedTimingMethodRawValue: "smartCube", context: context)
        try context.save()
        let values: [String: Any] = ["selectedSessionID": selected.id.uuidString, "enteringTimesWith": "smartCube",
            "smartCubeShowVirtualCube": true, "smartCubeReadySound": false, "wcaInspectionEnabled": false]
        let defaults = UserDefaults.standard, prior = values.map { ($0.key, defaults.object(forKey: $0.key)) }
        values.forEach { defaults.set($0.value, forKey: $0.key) }
        let manager = SmartCubeBluetoothManager.shared, ids = [UUID(), UUID()]
        manager.prepareIfNeeded(); try await Task.sleep(nanoseconds: 150_000_000)
        for (index, id) in ids.enumerated() {
            let session = manager.debugMakeRoutedSession(for: id)
            session.debugSeedConnectedState(deviceID: id, attemptID: UUID(), facelets: CubeSurface.solved(size: index == 0 ? 2 : 3),
                name: index == 0 ? "WeiPo V5 AI" : "GAN Fixture")
        }
        manager.selectActiveDevice(ids[0])
        defer { ids.forEach { manager.disconnect(deviceID: $0) }; prior.forEach { defaults.set($0.1, forKey: $0.0) } }
        for pass in 0..<2 {
            let probe = SmartCubeTimerGuidanceProbe()
            probe.generate = { context, _, completion in completion(.init(context: context, scrambles: ["R U"])) }
            let window = try window(TimerTabView().environment(\.managedObjectContext, context)
                .environment(\.smartCubeTimerGuidanceProbe, probe))
            defer { probe.reset(); window.isHidden = true; window.rootViewController = nil }
            try await wait { probe.snapshot?().event == .twoByTwo && probe.snapshot?().progress?.puzzleSize == 2 }
            XCTAssertEqual(selected.selectedEventRawValue, PuzzleEvent.twoByTwo.rawValue)
            XCTAssertEqual(probe.snapshot?().progress?.targetFacelets.count, 24)
            if pass == 1 {
                manager.selectActiveDevice(ids[1])
                try await wait { probe.snapshot?().event == .threeByThree && probe.snapshot?().progress?.puzzleSize == 3 }
                manager.selectActiveDevice(ids[0])
                try await wait { probe.snapshot?().event == .twoByTwo && probe.snapshot?().progress?.puzzleSize == 2 }
            }
            window.isHidden = true; window.rootViewController = nil; probe.reset()
        }
    }

    func testLateWeiPoIdentificationWithPersistedThreeByThreeCompletesMountedTwoByTwoSolve() async throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let selected = Session(name: "WeiPo timing", selectedTimingMethodRawValue: "smartCube", context: context)
        try context.save()
        let defaults = UserDefaults.standard
        let values: [String: Any] = ["selectedSessionID": selected.id.uuidString, "enteringTimesWith": "smartCube",
            "smartCubeReadySound": false, "wcaInspectionEnabled": false, "smartCubeShowVirtualCube": true,
            "scrambleDisplayMode": "scroll"]
        let prior = values.map { ($0.key, defaults.object(forKey: $0.key)) }
        values.forEach { defaults.set($0.value, forKey: $0.key) }
        let manager = SmartCubeBluetoothManager.shared, id = UUID()
        let previousScanDriver = manager.debugScanDriver
        // Do not let the simulator's asynchronous radio state reset a seeded peripheral.
        manager.debugScanDriver = SmartCubeScanTestDriver()
        manager.prepareIfNeeded()
        let session = manager.debugMakeRoutedSession(for: id)
        let diagnostics = SmartCubeDiagnostics.shared
        diagnostics.clearGuidance()
        diagnostics.recordGuidance(true)
        defer {
            diagnostics.recordGuidance(false)
            if selected.solveList.isEmpty { print(diagnostics.guidanceExport()) }
            manager.forgetDevice(id)
            manager.setTimerPuzzleSize(3)
            manager.debugScanDriver = previousScanDriver
            SmartCubeTimerPresentationStore.shared.discardScramble(timerSessionID: selected.id, puzzleSize: 2)
            prior.forEach { defaults.set($0.1, forKey: $0.0) }
        }
        manager.setTimerPuzzleSize(3)
        let parser = GANCubeProtocolParser(kind: .moyu, puzzleSize: 2)
        let solved: [UInt8] = [0, 2, 0x49, 0x49, 0x26, 0xDB, 0x92, 0x4B, 0x6D]
        let f: [UInt8] = [0, 2, 0x49, 0x4A, 0x4B, 0x5B, 0x8E, 0x35, 0x55]
        let fu: [UInt8] = [0x54, 8, 0xC9, 0x8A, 0x2B, 0x5B, 2, 0x32, 0x55]
        func snapshot(_ payload: [UInt8], counter: UInt8) {
            for event in parser.handleStateEvent([0xA3] + payload + [counter] + Array(repeating: 0, count: 9)) {
                session.debugApplyProtocolEvent(event, protocolKind: .moyu)
            }
        }
        func turn(_ code: UInt8, counter: UInt8, payload: [UInt8]) {
            var packet = [UInt8](repeating: 0, count: 20)
            packet[0] = 0xA5
            packet[13] = counter
            packet[14] = code << 5
            for event in parser.handleStateEvent(packet) {
                session.debugApplyProtocolEvent(event, protocolKind: .moyu)
            }
            snapshot(payload, counter: counter)
        }
        func renderedSize(in view: UIView) -> Int? {
            cubes(view).first.flatMap { SmartCube3DView.debugCoordinator(of: $0)?.debugPresentation.size }
        }
        XCTAssertEqual(selected.selectedEventRawValue, "3x3")
        session.debugSeedConnectedState(deviceID: id, attemptID: UUID(), facelets: CubeSurface.solved(size: 3),
            name: "WeiPo V5 AI")
        manager.debugReconcileConnectedDevice(id, userInitiated: false)
        XCTAssertEqual(manager.activeDeviceID, id)
        for pass in 0..<2 {
            let probe = SmartCubeTimerGuidanceProbe()
            var foregroundEvents: [PuzzleEvent] = []
            var completeStaleRequest: (() -> Void)?
            probe.generate = { context, reason, completion in
                if reason == "foreground" { foregroundEvents.append(context.event) }
                if context.event == .threeByThree {
                    if reason == "foreground" {
                        completeStaleRequest = { completion(.init(context: context, scrambles: ["R U R'"])) }
                    }
                    return
                }
                completion(.init(context: context, scrambles: ["F U"]))
            }
            let window = try window(TimerTabView().environment(\.managedObjectContext, context)
                .environment(\.smartCubeTimerGuidanceProbe, probe))
            defer { window.isHidden = true; window.rootViewController = nil; probe.reset() }
            if pass == 0 {
                try await wait { completeStaleRequest != nil }
                XCTAssertEqual(manager.puzzleSize, 3)
                try await wait { renderedSize(in: window) == 3 }
                session.debugApplyProtocolEvent(.hardware("WCU_MY22 HW 2.1 SW 2.1"), protocolKind: .moyu)
                snapshot(solved, counter: 10)
            }
            try await wait { probe.snapshot?().event == .twoByTwo && probe.snapshot?().progress?.puzzleSize == 2 }
            try await wait { renderedSize(in: window) == 2 }
            completeStaleRequest?()
            XCTAssertEqual(manager.activeDeviceID, id)
            XCTAssertEqual(selected.selectedEventRawValue, "2x2")
            XCTAssertEqual(probe.snapshot?().scramble, "F U")
            XCTAssertEqual(probe.snapshot?().progress?.targetFacelets,
                SmartCubeBluetoothManager.facelets(afterApplying: "F U", puzzleSize: 2))
            if pass != 0 { XCTAssertFalse(foregroundEvents.contains(.threeByThree)) }
            if pass == 0 { continue }
            // A late incompatible event callback must not evict the connected owner.
            probe.selectEvent?(.threeByThree)
            try await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertEqual(manager.activeDeviceID, id)
            XCTAssertEqual(selected.selectedEventRawValue, "2x2")
            turn(0, counter: 11, payload: f)
            turn(2, counter: 12, payload: fu)
            try await wait { probe.snapshot?().progress?.isComplete == true }
            turn(3, counter: 13, payload: f)
            try await wait { probe.snapshot?().assignment?.event == .twoByTwo }
            turn(1, counter: 14, payload: solved)
            try await wait { selected.solveList.count == 1 }
            let solve = try XCTUnwrap(selected.solveList.first)
            XCTAssertEqual(solve.event, "2x2")
            XCTAssertEqual(solve.scramble, "F U")
            XCTAssertEqual(solve.resultRaw, SolveResult.solved.rawValue)
            XCTAssertEqual(solve.inputSourceRaw, SolveInputSource.smartCube.rawValue)
            XCTAssertGreaterThan(solve.time, 0)
        }
    }

    func testWeiPoLastLayerPermutationSurvivesNativeSnapshotBoundaryAndSavesOnce() async throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let selected = Session(name: "WeiPo last layer", selectedTimingMethodRawValue: "smartCube", context: context)
        try context.save()
        let defaults = UserDefaults.standard
        let values: [String: Any] = ["selectedSessionID": selected.id.uuidString, "enteringTimesWith": "smartCube",
            "smartCubeReadySound": false, "wcaInspectionEnabled": false, "scrambleDisplayMode": "scroll"]
        let previous = values.map { ($0.key, defaults.object(forKey: $0.key)) }
        values.forEach { defaults.set($0.value, forKey: $0.key) }
        let manager = SmartCubeBluetoothManager.shared, id = UUID(), driver = manager.debugScanDriver
        manager.debugScanDriver = SmartCubeScanTestDriver()
        manager.prepareIfNeeded()
        let session = manager.debugMakeRoutedSession(for: id)
        defer {
            manager.forgetDevice(id); manager.setTimerPuzzleSize(3); manager.debugScanDriver = driver
            SmartCubeTimerPresentationStore.shared.discardScramble(timerSessionID: selected.id, puzzleSize: 2)
            previous.forEach { defaults.set($0.1, forKey: $0.0) }
        }
        let solved = CubeSurface.solved(size: 2)
        session.debugSeedConnectedState(deviceID: id, attemptID: UUID(), facelets: solved, name: "WCU_MY22")
        session.debugApplyProtocolEvent(.hardware("WCU_MY22 HW 2.1 SW 2.1"), protocolKind: .moyu)
        manager.selectActiveDevice(id)
        let parser = GANCubeProtocolParser(kind: .moyu, puzzleSize: 2)
        let destination = [8, 9, 10, 11, 20, 21, 22, 23, 0, 1, 2, 3,
                           12, 13, 14, 15, 16, 17, 18, 19, 4, 5, 6, 7]
        var counter: UInt8 = 10
        func receive(_ packet: [UInt8]) {
            for event in parser.handleStateEvent(packet) { session.debugApplyProtocolEvent(event, protocolKind: .moyu) }
        }
        func snapshot(_ facelets: String) throws {
            let faces = Array(facelets), colors = Array("FBUDLR")
            var bytes = Array(repeating: UInt8(0), count: 9)
            for (index, target) in destination.enumerated() {
                let color = try XCTUnwrap(colors.firstIndex(of: faces[target]))
                for bit in 0..<3 {
                    let offset = index * 3 + bit
                    bytes[offset / 8] |= UInt8((color >> (2 - bit)) & 1) << (7 - offset % 8)
                }
            }
            receive([0xA3] + bytes + [counter])
        }
        func turn(_ code: UInt8, _ state: String) throws {
            counter &+= 1
            var a5 = [UInt8](repeating: 0, count: 20)
            a5[0] = 0xA5; a5[13] = counter; a5[14] = code << 5
            receive(a5)
            try snapshot(state)
        }
        try snapshot(solved)
        let permutation = "R U R' U' R' F R R U' R' U' R U R' F'".split(separator: " ").map(String.init)
        let scramble = permutation.reversed().map { $0.hasSuffix("'") ? String($0.dropLast()) : $0 + "'" }.joined(separator: " ")
        let target = try XCTUnwrap(SmartCubeBluetoothManager.facelets(afterApplying: scramble, puzzleSize: 2))
        XCTAssertFalse(CubeStateEquivalence.isSolved(target, puzzleSize: 2))
        XCTAssertEqual(Set(target.prefix(4)).count, 1, "Last-layer orientation must already be solved")
        let probe = SmartCubeTimerGuidanceProbe()
        probe.generate = { request, _, completion in completion(.init(context: request, scrambles: [scramble])) }
        let window = try window(TimerTabView().environment(\.managedObjectContext, context)
            .environment(\.smartCubeTimerGuidanceProbe, probe))
        defer { window.isHidden = true; window.rootViewController = nil; probe.reset() }
        try await wait { probe.snapshot?().progress?.targetFacelets == target }
        // The captured F/U sequence first disambiguates the native layout.
        let f = try apply("F", solved), fu = try apply("U", f)
        try turn(0, f); try turn(2, fu)
        counter &+= 2
        try turn(4, target) // An observed A5 and A3 confirm state, not every preceding move.
        try await wait { probe.snapshot?().progress?.isComplete == true }
        let lastSequence = try XCTUnwrap(session.canonicalHistory.last?.sequence)
        try turn(4, target) // New counter, same normalized state, no certifiable move.
        guard case .boundary(let boundary)? = session.canonicalHistory.last else {
            return XCTFail("An observed same-state native turn must publish a snapshot boundary")
        }
        XCTAssertGreaterThan(boundary.sequence, lastSequence)
        XCTAssertEqual(boundary.reason, .weiPoSnapshot)
        XCTAssertEqual(boundary.facelets, target)
        XCTAssertNotNil(boundary.observedWeiPoTurnAt)
        var state = target
        let codes: [String: UInt8] = ["F": 0, "F'": 1, "U": 2, "U'": 3, "R": 4, "R'": 5]
        for (index, notation) in permutation.enumerated() {
            state = try apply(notation, state)
            if index < permutation.count - 1 {
                XCTAssertFalse(CubeStateEquivalence.isSolved(state, puzzleSize: 2))
            }
            let code = try XCTUnwrap(codes[notation])
            try turn(index == 3 || index == permutation.count - 1 ? (code ^ 1) : code, state)
            if index == 0 { try await wait { probe.snapshot?().assignment?.event == .twoByTwo } }
            if index < permutation.count - 1 { XCTAssertTrue(selected.solveList.isEmpty) }
        }
        try snapshot(state) // A duplicate A3 cannot complete twice.
        try await wait { selected.solveList.count == 1 }
        let solve = try XCTUnwrap(selected.solveList.first)
        XCTAssertEqual(solve.event, "2x2")
        XCTAssertEqual(solve.resultRaw, SolveResult.solved.rawValue)
        XCTAssertEqual(solve.reconstruction?.completeness, .incomplete)
        XCTAssertGreaterThan(solve.time, 0)
    }

    func testDiscoveryReplacementRetainsConnectionPolicyOwnerWithoutBatteryMetadata() async throws {
        let defaults = UserDefaults.standard, key = "smartCubeResetPolicy", previous = defaults.object(forKey: key)
        defaults.set(SmartCubeResetPolicy.never.rawValue, forKey: key)
        defer { defaults.set(previous, forKey: key) }
        let saved = SavedSmartCubeDevices(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let manager = SmartCubeBluetoothManager(testSavedDevices: saved), id = UUID(), attempt = UUID()
        manager.debugScanDriver = SmartCubeScanTestDriver()
        let session = manager.debugMakeRoutedSession(for: id)
        session.debugSeedConnectionPhase(.connecting, deviceID: id, attemptID: attempt)
        var displayed: UUID?
        let window = try window(SmartCubeManagementCard(manager: manager, saved: saved, selectedID: id, dismiss: {})
            .environment(\.smartCubeManagementSelection, { value, _ in displayed = value }))
        defer { window.isHidden = true; window.rootViewController = nil; manager.disconnect(deviceID: id) }
        try await wait { manager.pendingPolicyAttemptID == nil }
        XCTAssertNil(displayed)
        session.debugSeedConnectedState(deviceID: id, attemptID: attempt, facelets: CubeSurface.solved(size: 3))
        session.debugAwaitConnectionPolicy()
        XCTAssertFalse(session.observationReadiness.isReady)
        try await wait { displayed == id && session.connectionPolicyResolvedAttemptID == attempt }
        XCTAssertTrue(session.observationReadiness.isReady)
        XCTAssertNil(session.batteryLevel)
        XCTAssertEqual(session.facelets, CubeSurface.solved(size: 3), "Keep Cube State must not reset the device")
    }

    func testWeiPoResetStaysEnabledWhileAwaitingSnapshotAndUsesLatestAuthoritativeState() async throws {
        let saved = SavedSmartCubeDevices(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let manager = SmartCubeBluetoothManager(testSavedDevices: saved), id = UUID()
        manager.debugScanDriver = SmartCubeScanTestDriver()
        let session = manager.debugMakeRoutedSession(for: id)
        session.debugSeedConnectedState(deviceID: id, attemptID: UUID(), facelets: CubeSurface.solved(size: 2), name: "WeiPo V5 AI")
        let baseline = (0..<6).flatMap { Array(repeating: UInt8($0), count: 4) }
        session.debugApplyProtocolEvent(.weiPo2State(.init(stickerValues: baseline, turnCounter: 0)), protocolKind: .moyu)
        let window = try window(SmartCubeManagementCard(manager: manager, saved: saved, selectedID: id, dismiss: {}))
        defer { window.isHidden = true; window.rootViewController = nil; manager.disconnect(deviceID: id) }
        func resetButton(_ root: UIView) -> UIButton? {
            if let button = root as? UIButton, button.accessibilityIdentifier == "smart-cube-management-reset" { return button }
            return root.subviews.compactMap(resetButton).first
        }
        try await wait { resetButton(window)?.isEnabled == true }
        session.debugApplyProtocolEvent(.weiPo2Turn(.init(code: 0, turnCounter: 1, missedTurnCount: 0)), protocolKind: .moyu)
        XCTAssertEqual(session.weiPo2PendingSnapshotCount, 1)
        XCTAssertTrue(session.hasTrustedCanonicalState)
        window.layoutIfNeeded()
        XCTAssertTrue(try XCTUnwrap(resetButton(window)).isEnabled)
        session.resetCubeStateToSolved()
        XCTAssertEqual(session.weiPo2PendingSnapshotCount, 1, "Reset must wait for authoritative state, not redefine a stale baseline")
        // The captured native F endpoint, also used by CubeStateEquivalenceTests.
        let parser = GANCubeProtocolParser(kind: .moyu, puzzleSize: 2)
        let packet: [UInt8] = [0xA3, 0, 2, 0x49, 0x4A, 0x4B, 0x5B, 0x8E, 0x35, 0x55, 1] + Array(repeating: 0, count: 9)
        guard case .weiPo2State(let endpoint) = try XCTUnwrap(parser.handleStateEvent(packet).first) else {
            return XCTFail("Expected the verified native F endpoint")
        }
        let turned = endpoint.stickerValues
        session.debugApplyProtocolEvent(.weiPo2State(.init(stickerValues: turned, turnCounter: 1)), protocolKind: .moyu)
        XCTAssertEqual(session.weiPo2PendingSnapshotCount, 0)
        XCTAssertEqual(session.weiPo2LastNativeSnapshot?.turnCounter, 1)
        XCTAssertEqual(session.facelets, CubeSurface.solved(size: 2))
        XCTAssertTrue(session.hasTrustedCanonicalState)
        // A later snapshot must preserve the reference created from counter 1.
        session.debugApplyProtocolEvent(.weiPo2State(.init(stickerValues: turned, turnCounter: 1)), protocolKind: .moyu)
        XCTAssertEqual(session.facelets, CubeSurface.solved(size: 2))
    }

    func testMountedTimerPublishesEqualLengthRecoveryOnFirstDeviationAndImmediatelyAfterTarget() async throws {
        let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
        let selected = Session(name: "Combined guidance", selectedTimingMethodRawValue: "smartCubeAndGAN", context: context)
        try context.save()
        let defaults = UserDefaults.standard
        let values: [String: Any] = ["selectedSessionID": selected.id.uuidString, "enteringTimesWith": "smartCubeAndGAN",
            "smartCubeShowVirtualCube": false, "smartCubeReadySound": false, "wcaInspectionEnabled": false]
        let prior = values.map { ($0.key, defaults.object(forKey: $0.key)) }
        values.forEach { defaults.set($0.value, forKey: $0.key) }
        let manager = SmartCubeBluetoothManager.shared, id = UUID()
        manager.prepareIfNeeded(); try await Task.sleep(nanoseconds: 150_000_000)
        let cube = manager.debugMakeRoutedSession(for: id)
        cube.debugSeedConnectedState(deviceID: id, attemptID: UUID(), facelets: CubeSurface.solved(size: 3))
        manager.selectActiveDevice(id)
        let probe = SmartCubeTimerGuidanceProbe()
        probe.generate = { context, _, completion in completion(.init(context: context, scrambles: ["R U"])) }
        let window = try window(TimerTabView().environment(\.managedObjectContext, context).environment(\.smartCubeTimerGuidanceProbe, probe))
        defer {
            probe.reset(); window.isHidden = true; window.rootViewController = nil
            manager.disconnect(deviceID: id); prior.forEach { defaults.set($0.1, forKey: $0.0) }
        }
        try await wait { probe.prepare != nil }
        probe.prepare?("R U")
        cube.debugEmitPhysicalMove("R")
        cube.debugEmitPhysicalMove("F")
        XCTAssertFalse(probe.snapshot?().progress?.isComplete ?? true)
        XCTAssertEqual(probe.snapshot?().request?.sourceFacelets, cube.facelets)
        XCTAssertFalse(probe.snapshot?().request?.keepsEqualPath ?? true)
        try await wait { probe.snapshot?().progress?.replanGeneration == 1 }
        var current = try XCTUnwrap(cube.facelets)
        for move in try XCTUnwrap(probe.snapshot?().progress?.remainingGuidanceMoves) {
            current = try apply(move, current); cube.debugEmitPhysicalMove(move)
        }
        XCTAssertTrue(probe.snapshot?().progress?.isComplete ?? false)
        for _ in 0..<3 {
            cube.debugEmitPhysicalMove("B")
            XCTAssertFalse(probe.snapshot?().progress?.isComplete ?? true)
            XCTAssertEqual(probe.snapshot?().request?.sourceFacelets, cube.facelets)
            try await wait { probe.snapshot?().progress?.tokens == ["B'"] && probe.snapshot?().progress?.completedTokenIndices.isEmpty == true }
            cube.debugEmitPhysicalMove("B'")
            XCTAssertTrue(probe.snapshot?().progress?.isComplete ?? false)
        }
        for move in ["R", "U", "U'", "R'", "F"] { cube.debugEmitPhysicalMove(move) }
        XCTAssertNotNil(cube.facelets)
        try await wait { probe.snapshot?().progress?.tokens == ["F'"] && probe.snapshot?().progress?.isDeviated == false }
        probe.prepare?("D")
        try await wait { probe.snapshot?().progress?.targetFacelets == SmartCubeBluetoothManager.facelets(afterApplying: "D") }
        XCTAssertNotEqual(probe.snapshot?().progress?.targetFacelets, current)
    }
}
#endif

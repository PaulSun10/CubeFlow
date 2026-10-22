#if DEBUG
import XCTest
import SwiftUI
import CoreBluetooth
import CoreData
@testable import CubeFlow

private actor VirtualGuidanceSettle {
    private var now: Double = 0
    private var advanced = false
    private var waiting: [(Double, CheckedContinuation<Void, Never>)] = []
    func settle() async {
        if advanced { return }
        let deadline = now + 0.12
        await withCheckedContinuation { waiting.append((deadline, $0)) }
    }
    func advance(seconds: Double) {
        now += seconds
        advanced = true
        let ready = waiting.filter { $0.0 <= now }
        waiting.removeAll { $0.0 <= now }
        ready.forEach { $0.1.resume() }
    }
    var count: Int { waiting.count }
    func arm() { advanced = false }
}

@MainActor final class SmartCubeTimerIntegrationTests: XCTestCase {
    private func wait(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Actual Timer failed to reach expected state", file: file, line: line)
    }

    func testActualTimerSevenThenNineteenTurnsWithStationaryVirtualPausesAndOriginalTarget() async throws {
        let persistence = PersistenceController(inMemory: true)
        let selected = Session(name: "Stationary guidance", selectedTimingMethodRawValue: "smartCube",
            context: persistence.container.viewContext)
        try persistence.container.viewContext.save()
        let defaults = UserDefaults.standard
        let keys = ["selectedSessionID", "enteringTimesWith", "smartCubeShowVirtualCube",
            "smartCubeCompletedMovesBehavior", "smartCubeRecoveryDisplay"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defaults.set(selected.id.uuidString, forKey: keys[0]); defaults.set("smartCube", forKey: keys[1])
        defaults.set(false, forKey: keys[2]); defaults.set("collapse", forKey: keys[3]); defaults.set("inline", forKey: keys[4])
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        let manager = SmartCubeBluetoothManager.shared, device = UUID()
        manager.prepareIfNeeded(); try await Task.sleep(nanoseconds: 150_000_000)
        let session = manager.debugMakeRoutedSession(for: device)
        session.debugSeedConnectedState(deviceID: device, attemptID: UUID(), facelets: CubeSurface.solved(size: 3))
        manager.selectActiveDevice(device)
        defer { manager.disconnect(deviceID: device) }
        let clock = VirtualGuidanceSettle()
        let controller = SmartCubeGuidanceController(settle: { await clock.settle() })
        defer { controller.cancel(); Task { await clock.advance(seconds: 100) } }
        let capture = SmartCubeGuidanceCaptureStore.shared
        capture.clear(); capture.setRecording(true)
        defer { capture.setRecording(false) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let probe = SmartCubeTimerGuidanceProbe()
        window.rootViewController = UIHostingController(rootView: TimerTabView(guidanceController: controller)
            .environment(\.managedObjectContext, persistence.container.viewContext)
            .environment(\.smartCubeTimerGuidanceProbe, probe)
            .transaction { $0.animation = nil; $0.disablesAnimations = true })
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; probe.reset() }
        try await wait { probe.prepare != nil }
        let original = "R U2 F B R B2 R U2 L B2 R2 D F2 L2 U' B2 U2 L2 D F2 U"
        let target = try XCTUnwrap(SmartCubeBluetoothManager.facelets(afterApplying: original))
        probe.prepare?(original)
        try await wait { probe.snapshot?().progress?.targetFacelets == target }
        let moves = "U R F L B D R2 U' F2 L2 D' B2 R' U2 F' L' D2 B U".split(separator: " ").map(String.init)
        var generationAtSeven = 0
        for (index, move) in moves.enumerated() {
            await clock.arm()
            session.debugEmitPhysicalMove(move)
            XCTAssertEqual(probe.snapshot?().progress?.targetFacelets, target)
            guard [7, 12, 17, 18, 19].contains(index + 1) else { continue }
            let before = try XCTUnwrap(probe.snapshot?())
            let oldProgress = try XCTUnwrap(before.progress)
            let oldPath = (before.recovery.plan ?? before.recovery.fallbackPlan)?.executableMoves(originalTokens: oldProgress.tokens)
                ?? oldProgress.remainingGuidanceMoves
            // Let the real scheduling task register, then advance its 120ms
            // trailing-settle clock by five seconds without five-second sleeps.
            for _ in 0..<30 {
                if await clock.count > 0 { break }
                await Task.yield()
            }
            await clock.advance(seconds: 5)
            try await wait { !controller.isUpdating && probe.snapshot?().request == nil }
            let state = try XCTUnwrap(probe.snapshot?()), progress = try XCTUnwrap(state.progress)
            let path = (state.recovery.plan ?? state.recovery.fallbackPlan)?.executableMoves(originalTokens: progress.tokens)
                ?? progress.remainingGuidanceMoves
            let current = try XCTUnwrap(manager.facelets)
            XCTAssertEqual(path.reduce(Optional(current)) { s, m in s.flatMap { SmartCubeBluetoothManager.facelets($0, applying: m) } }, target)
            XCTAssertEqual(state.scramble, original); XCTAssertEqual(progress.targetFacelets, target)
            XCTAssertLessThanOrEqual(path.count, oldPath.count)
            try await wait { probe.displayedPathText == path.joined(separator: " ") }
            print("[ActualTimerStationary] turns=\(index + 1) shownBefore=\(oldPath.count) selected=\(path.count) generation=\(progress.replanGeneration) text=\(probe.displayedPathText ?? "nil")")
            if index + 1 == 7 {
                generationAtSeven = progress.replanGeneration
                XCTAssertGreaterThan(generationAtSeven, oldProgress.replanGeneration,
                    "The real Timer must visibly improve this long fallback without another turn")
                XCTAssertLessThan(path.count, oldPath.count)
            }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image); attachment.name = "Actual Timer after \(index + 1) turns and stationary settle"
            attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertGreaterThan(generationAtSeven, 0)
        let export = SmartCubeDiagnostics.shared.guidanceExport()
        let evidence = XCTAttachment(string: export); evidence.name = "actual-timer-seven-nineteen.tsv"
        evidence.lifetime = .keepAlways; add(evidence)
        XCTAssertTrue(export.contains("guidance.adoption-accepted"))
        XCTAssertTrue(export.contains("guidance.swiftui-update"))
    }

    func testPenultimateOriginalScrambleThenTwentyDeviations() async throws {
        try await runPenultimate(deviations: "U R F L B D R2 U' F2 L2 D' B2 R' U2 F' L' D2 B U L".split(separator: " ").map(String.init))
    }

    func testPenultimateRepeatedDeviationsRetainOnlyActionableCost() async throws {
        try await runPenultimate(deviations: Array(repeating: ["R", "U", "R'", "U'"], count: 5).flatMap { $0 })
    }

    private func runPenultimate(deviations: [String]) async throws {
        let persistence = PersistenceController(inMemory: true)
        let selected = Session(name: "Stationary guidance", selectedTimingMethodRawValue: "smartCube",
            context: persistence.container.viewContext)
        try persistence.container.viewContext.save()
        let defaults = UserDefaults.standard
        let keys = ["selectedSessionID", "enteringTimesWith", "smartCubeShowVirtualCube",
            "smartCubeCompletedMovesBehavior", "smartCubeRecoveryDisplay"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defaults.set(selected.id.uuidString, forKey: keys[0]); defaults.set("smartCube", forKey: keys[1])
        defaults.set(false, forKey: keys[2]); defaults.set("trail", forKey: keys[3]); defaults.set("inline", forKey: keys[4])
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        let manager = SmartCubeBluetoothManager.shared, device = UUID()
        manager.prepareIfNeeded(); try await Task.sleep(nanoseconds: 150_000_000)
        let session = manager.debugMakeRoutedSession(for: device)
        session.debugSeedConnectedState(deviceID: device, attemptID: UUID(), facelets: CubeSurface.solved(size: 3))
        manager.selectActiveDevice(device)
        defer { manager.disconnect(deviceID: device) }
        let clock = VirtualGuidanceSettle()
        let controller = SmartCubeGuidanceController(settle: { await clock.settle() })
        defer { controller.cancel(); Task { await clock.advance(seconds: 100) } }
        let capture = SmartCubeGuidanceCaptureStore.shared
        capture.clear(); capture.setRecording(true)
        defer { capture.setRecording(false) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let probe = SmartCubeTimerGuidanceProbe()
        window.rootViewController = UIHostingController(rootView: TimerTabView(guidanceController: controller)
            .environment(\.managedObjectContext, persistence.container.viewContext)
            .environment(\.smartCubeTimerGuidanceProbe, probe)
            .transaction { $0.animation = nil; $0.disablesAnimations = true })
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; probe.reset() }
        try await wait { probe.prepare != nil }
        let original = "R U2 F B R B2 R U2 L B2 R2 D F2 L2 U' B2 U2 L2 D F2"
        let target = try XCTUnwrap(SmartCubeBluetoothManager.facelets(afterApplying: original))
        probe.prepare?(original)
        try await wait { probe.snapshot?().progress?.targetFacelets == target }
        let originalMoves = original.split(separator: " ").map(String.init)
        for move in originalMoves.dropLast() { session.debugEmitPhysicalMove(move) }
        let penultimate = try XCTUnwrap(probe.snapshot?().progress)
        XCTAssertEqual(penultimate.completedTokenIndices.count, originalMoves.count - 1)
        XCTAssertEqual(penultimate.remainingGuidanceMoves, [originalMoves.last!])
        XCTAssertEqual(manager.facelets, SmartCubeBluetoothManager.facelets(afterApplying: originalMoves.dropLast().joined(separator: " ")))
        let moves = deviations
        var generationAtSeven = 0
        for (index, move) in moves.enumerated() {
            await clock.arm()
            session.debugEmitPhysicalMove(move)
            XCTAssertEqual(probe.snapshot?().progress?.targetFacelets, target)
            guard [1, 2, 3, 5, 7, 10, 12, 15, 17, 19, 20].contains(index + 1) else { continue }
            let before = try XCTUnwrap(probe.snapshot?())
            let oldProgress = try XCTUnwrap(before.progress)
            let oldPath = (before.recovery.plan ?? before.recovery.fallbackPlan)?.executableMoves(originalTokens: oldProgress.tokens)
                ?? oldProgress.remainingGuidanceMoves
            // Let the real scheduling task register, then advance its 120ms
            // trailing-settle clock by five seconds without five-second sleeps.
            for _ in 0..<30 {
                if await clock.count > 0 { break }
                await Task.yield()
            }
            await clock.advance(seconds: 5)
            try await wait { !controller.isUpdating && probe.snapshot?().request == nil }
            let state = try XCTUnwrap(probe.snapshot?()), progress = try XCTUnwrap(state.progress)
            let path = (state.recovery.plan ?? state.recovery.fallbackPlan)?.executableMoves(originalTokens: progress.tokens)
                ?? progress.remainingGuidanceMoves
            let current = try XCTUnwrap(manager.facelets)
            XCTAssertEqual(path.reduce(Optional(current)) { s, m in s.flatMap { SmartCubeBluetoothManager.facelets($0, applying: m) } }, target)
            XCTAssertEqual(state.scramble, original); XCTAssertEqual(progress.targetFacelets, target)
            XCTAssertLessThanOrEqual(path.count, oldPath.count)
            let expectedText = state.recovery.plan != nil || state.recovery.fallbackPlan != nil
                ? (Array(originalMoves.dropLast()) + path).joined(separator: " ")
                : progress.tokens.joined(separator: " ")
            try await wait { probe.displayedPathText == expectedText }
            print("[PenultimateGuidance] turns=\(index + 1) shownBefore=\(oldPath.count) selected=\(path.count) generation=\(progress.replanGeneration) dimmed=\(progress.completedTokenIndices.count) orange=\(state.recovery.plan?.correctionMoves.count ?? state.recovery.fallbackPlan?.correctionMoves.count ?? 0) source=\(SmartCubeGuidanceTrace.digest(current)) target=\(SmartCubeGuidanceTrace.digest(target)) text=\(probe.displayedPathText ?? "nil")")
            if index + 1 == 7 {
                generationAtSeven = progress.replanGeneration
            }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image); attachment.name = "Actual Timer after \(index + 1) turns and stationary settle"
            attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertGreaterThanOrEqual(generationAtSeven, 0)
        let export = SmartCubeDiagnostics.shared.guidanceExport()
        let evidence = XCTAttachment(string: export); evidence.name = "actual-timer-penultimate-twenty.tsv"
        evidence.lifetime = .keepAlways; add(evidence)
        XCTAssertTrue(export.contains("guidance.adoption-accepted"))
        XCTAssertTrue(export.contains("guidance.swiftui-update"))
    }

    func testActualTimerConsumesRoutedMovesAndDisplaysExactCurrentTargetPathWithoutExtraTurn() async throws {
        let persistence = PersistenceController(inMemory: true)
        let selected = Session(name: "Guidance fixture", selectedTimingMethodRawValue: "smartCube",
                               context: persistence.container.viewContext)
        try persistence.container.viewContext.save()
        let defaults = UserDefaults.standard
        let keys = ["selectedSessionID", "enteringTimesWith", "smartCubeShowVirtualCube"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defaults.set(selected.id.uuidString, forKey: keys[0]); defaults.set("smartCube", forKey: keys[1])
        defaults.set(false, forKey: keys[2])
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        let manager = SmartCubeBluetoothManager.shared, device = UUID()
        manager.prepareIfNeeded()
        // Complete the simulator's unsupported-radio callback before seeding
        // the fixture; it must not invalidate the synthetic connected session.
        try await Task.sleep(nanoseconds: 150_000_000)
        let session = manager.debugMakeRoutedSession(for: device)
        session.debugSeedConnectedState(deviceID: device, attemptID: UUID(), facelets: CubeSurface.solved(size: 3))
        manager.selectActiveDevice(device)
        defer { manager.disconnect(deviceID: device) }
        let capture = SmartCubeGuidanceCaptureStore.shared
        capture.clear(); capture.setRecording(true)
        defer { capture.setRecording(false) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let probe = SmartCubeTimerGuidanceProbe()
        window.rootViewController = UIHostingController(rootView: TimerTabView()
            .environment(\.managedObjectContext, persistence.container.viewContext)
            .environment(\.smartCubeTimerGuidanceProbe, probe))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; probe.reset() }
        try await wait { probe.prepare != nil }
        let originalTarget = try XCTUnwrap(SmartCubeBluetoothManager.facelets(afterApplying: "R L R' U"))
        probe.prepare?("R L R' U")
        try await wait { probe.snapshot?().progress?.replanGeneration == 1 }
        XCTAssertEqual(probe.snapshot?().progress?.remainingGuidanceMoves.count, 2,
            "The actual Timer must adopt a shortened known continuation, not retain four displayed moves")
        XCTAssertEqual(probe.snapshot?().scramble, "R L R' U")
        XCTAssertEqual(probe.snapshot?().progress?.targetFacelets, originalTarget)
        let scramble = "R U F L D B R2 U2 F2"
        probe.prepare?(scramble)
        try await wait { probe.snapshot?().progress?.tokens.joined(separator: " ") == scramble }
        let target = try XCTUnwrap(probe.snapshot?().progress?.targetFacelets)
        for move in ["R", "U", "F", "L", "D", "B", "R2", "U2"] {
            session.debugEmitPhysicalMove(move)
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        for move in ["R", "U", "U'", "R'", "L", "L'"] {
            let previous = manager.canonicalSequence
            session.debugEmitPhysicalMove(move)
            XCTAssertEqual(manager.canonicalSequence, previous + 1)
            try await wait {
                let state = probe.snapshot?()
                return state?.request?.sourceFacelets == manager.facelets
                    || state?.recovery.sourceFacelets == manager.facelets
                    || (state?.progress?.replanGeneration ?? 0) > 0
            }
            try await Task.sleep(nanoseconds: 160_000_000)
            let state = try XCTUnwrap(probe.snapshot?()), progress = try XCTUnwrap(state.progress)
            let route = (state.recovery.plan ?? state.recovery.fallbackPlan)?.executableMoves(originalTokens: progress.tokens)
                ?? progress.remainingGuidanceMoves
            let end = route.reduce(manager.facelets) { state, move in
                state.flatMap { SmartCubeBluetoothManager.facelets($0, applying: move) }
            }
            XCTAssertEqual(end, target, "Displayed instructions must apply to this exact current state after \(move)")
            XCTAssertEqual(progress.targetFacelets, target)
        }
        // No run-loop pause between these canonical turns: exercise the actual
        // Timer's burst ingestion, rather than a separate scheduler harness.
        for move in Array(repeating: ["R", "U", "F", "D", "L"], count: 4).flatMap({ $0 }) {
            session.debugEmitPhysicalMove(move)
            let state = try XCTUnwrap(probe.snapshot?()), progress = try XCTUnwrap(state.progress)
            let route = (state.recovery.plan ?? state.recovery.fallbackPlan)?.executableMoves(originalTokens: progress.tokens)
                ?? progress.remainingGuidanceMoves
            let end = route.reduce(manager.facelets) { state, turn in
                state.flatMap { SmartCubeBluetoothManager.facelets($0, applying: turn) }
            }
            XCTAssertEqual(end, target, "A burst must never reuse instructions for an older state")
        }
        try await wait { probe.snapshot?().request == nil }
        let exported = SmartCubeDiagnostics.shared.guidanceExport()
        for stage in ["guidance.active-route", "timer.consume", "guidance.display-path", "guidance.swiftui-update"] {
            XCTAssertTrue(exported.contains(stage), stage)
        }
        XCTAssertFalse(exported.contains(target))
        let attachment = XCTAttachment(string: exported); attachment.name = "actual-timer-guidance.tsv"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    func testCaptureIsIndependentOfProtocolToggleAndSurvivesLeavingSettings() {
        let capture = SmartCubeGuidanceCaptureStore.shared, diagnostics = SmartCubeDiagnostics.shared
        capture.clear(); capture.setRecording(true)
        diagnostics.setEnabled(false)
        XCTAssertTrue(diagnostics.enabled)
        diagnostics.mark("guidance.navigation-fixture", detail: "sequence=1 valid=true")
        capture.setRecording(false); capture.refresh()
        XCTAssertFalse(diagnostics.enabled)
        XCTAssertGreaterThan(capture.count, 0)
        XCTAssertTrue(diagnostics.guidanceExport().contains("guidance.navigation-fixture"))
    }
}
#endif

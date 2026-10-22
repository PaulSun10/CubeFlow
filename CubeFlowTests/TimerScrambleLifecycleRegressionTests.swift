#if DEBUG
import XCTest
import SwiftUI
import CoreData
import UIKit
import Vision
@testable import CubeFlow

@MainActor final class TimerScrambleLifecycleRegressionTests: XCTestCase {
    func testPresentationStoreRefusesTextFromDifferentCanonicalTarget() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TargetAffinity." + UUID().uuidString))
        let store = SmartCubeTimerPresentationStore(defaults: defaults)
        let progress = try XCTUnwrap(SmartCubeScrambleProgress(scramble: "R U'"))
        store.save(scramble: "L D2", progress: progress, epoch: SmartCubeScrambleEpoch(), recoveryState: .inactive)
        XCTAssertNil(store.snapshot, "A new text label cannot make the previous target restorable under that label")
    }
    private struct Generation {
        let context: TimerScrambleGenerationContext
        let reason: String
        let complete: @MainActor (TimerScrambleGenerationPayload) -> Void
    }
    private func wait(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Mounted Timer did not reach requested lifecycle state", file: file, line: line)
        throw NSError(domain: "TimerLifecycleTimeout", code: 1)
    }
    private func assertPixels(_ window: UIWindow, show scramble: String, name: String,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let recognition = VNRecognizeTextRequest(); recognition.recognitionLevel = .accurate
        recognition.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: try XCTUnwrap(image.cgImage)).perform([recognition])
        let labels = recognition.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
        func normalize(_ value: String) -> String {
            let quotes = value.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "′", with: "'")
            return String(quotes.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "'" })
        }
        XCTAssertTrue(normalize(labels.joined()).contains(normalize(scramble)), "Rendered pixels: \(labels)", file: file, line: line)
    }
    private func assertDetail(_ solve: Solve, shows scramble: String, scene: UIWindowScene,
                              context: NSManagedObjectContext) async throws {
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: SolveDetailAcceptance.view(for: solve)
            .environment(\.managedObjectContext, context))
        window.windowLevel = .alert + 2; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(nanoseconds: 100_000_000)
        try assertPixels(window, show: scramble, name: "Saved Solve Detail \(scramble)")
    }
    func testMountedTimerConsecutiveSolvesKeepVisibleAndPersistedScramblesIdentical() async throws {
        let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
        let session = Session(name: "Lifecycle fixture", context: context)
        try context.save()
        let defaults = UserDefaults.standard
        let settings: [String: Any] = ["selectedSessionID": session.id.uuidString, "enteringTimesWith": "timer",
            "timerArrangement": "cards", "scrambleDisplayMode": "shrinkFont", "wcaInspectionEnabled": false,
            "appLanguage": "en", "scrambleTextFontSize": 22.0]
        let previous = settings.keys.map { ($0, defaults.object(forKey: $0)) }
        for (key, value) in settings { defaults.set(value, forKey: key) }
        defer { for (key, value) in previous { defaults.set(value, forKey: key) } }
        let probe = SmartCubeTimerGuidanceProbe()
        var pending: [Generation] = []
        probe.generate = { pending.append(.init(context: $0, reason: $1, complete: $2)) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: TimerTabView()
            .environment(\.managedObjectContext, context).environment(\.smartCubeTimerGuidanceProbe, probe))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer {
            window.isHidden = true; window.rootViewController = nil
            probe.reset()
        }
        let scrambles = ["R U' F2 L2 D B2", "L D2 B' R2 U F", "F D' R2 B2 L U2", "B L2 U' F2 R D2"]
        try await wait { !pending.isEmpty && probe.next != nil }
        let first = pending.removeFirst()
        first.complete(.init(context: first.context, scrambles: [scrambles[0]]))
        try await wait { probe.snapshot?().scramble == scrambles[0] }
        for index in 0..<3 {
            let assigned = scrambles[index]
            try await wait { pending.contains { $0.reason == "prefetch" } }
            let next = pending.remove(at: pending.firstIndex { $0.reason == "prefetch" }!)
            next.complete(.init(context: next.context, scrambles: [scrambles[index + 1]]))
            try await Task.sleep(nanoseconds: 100_000_000)
            window.layoutIfNeeded()
            try assertPixels(window, show: assigned, name: "Timer visible scramble \(index)")
            probe.start?()
            probe.next?()
            XCTAssertEqual(probe.snapshot?().scramble, assigned, "Next must not change an in-flight solve's assignment")
            probe.finish?(10 + Double(index))
            try await wait { session.solveList.count == index + 1 && probe.snapshot?().scramble == scrambles[index + 1] }
            let saved = try XCTUnwrap(session.solveList.first)
            XCTAssertEqual(saved.scramble, assigned)
            // Solve Detail reads this same saved managed object; reload it from
            // Core Data rather than asserting only a mocked persistence call.
            context.refresh(saved, mergeChanges: false)
            XCTAssertEqual(saved.scramble, assigned)
            try await assertDetail(saved, shows: assigned, scene: scene, context: context)
        }
    }

    func testSmartCubeCompletionAndImmediateNextTurnCannotPairNewTextWithPreviousGuidanceTarget() async throws {
        let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
        let selected = Session(name: "Smart lifecycle fixture", selectedTimingMethodRawValue: "smartCube", context: context)
        try context.save()
        let defaults = UserDefaults.standard
        let settings: [String: Any] = ["selectedSessionID": selected.id.uuidString, "enteringTimesWith": "smartCube",
            "smartCubeShowVirtualCube": false, "wcaInspectionEnabled": false, "smartCubeReadySound": false]
        let previous = settings.keys.map { ($0, defaults.object(forKey: $0)) }
        for (key, value) in settings { defaults.set(value, forKey: key) }
        defer { for (key, value) in previous { defaults.set(value, forKey: key) } }
        let manager = SmartCubeBluetoothManager.shared, device = UUID()
        manager.prepareIfNeeded(); try await Task.sleep(nanoseconds: 150_000_000)
        let cube = manager.debugMakeRoutedSession(for: device)
        cube.debugSeedConnectedState(deviceID: device, attemptID: UUID(), facelets: CubeSurface.solved(size: 3))
        manager.selectActiveDevice(device)
        defer { manager.disconnect(deviceID: device) }
        let probe = SmartCubeTimerGuidanceProbe()
        var pending: [Generation] = []
        probe.generate = { pending.append(.init(context: $0, reason: $1, complete: $2)) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: TimerTabView()
            .environment(\.managedObjectContext, context).environment(\.smartCubeTimerGuidanceProbe, probe))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer {
            window.isHidden = true; window.rootViewController = nil
            probe.reset()
        }
        try await wait { !pending.isEmpty && probe.next != nil }
        let first = pending.removeFirst()
        first.complete(.init(context: first.context, scrambles: ["R U'"]))
        try await wait { probe.snapshot?().scramble == "R U'" && probe.snapshot?().progress?.tokens == ["R", "U'"] }
        try await wait { pending.contains { $0.reason == "prefetch" } }
        let next = pending.remove(at: pending.firstIndex { $0.reason == "prefetch" }!)
        next.complete(.init(context: next.context, scrambles: ["L D2"]))
        for move in ["R", "U'", "U", "R'", "L"] { cube.debugEmitPhysicalMove(move) }
        try await wait { selected.solveList.count == 1 && probe.snapshot?().scramble == "L D2" }
        let target = SmartCubeBluetoothManager.facelets(afterApplying: "L D2")
        XCTAssertEqual(probe.snapshot?().progress?.targetFacelets, target, "The first next-scramble turn must already belong to the new target")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(probe.snapshot?().progress?.targetFacelets, target, "Rehydration must not make the previous target authoritative again")
        XCTAssertEqual(selected.solveList.first?.scramble, "R U'")
        try assertPixels(window, show: "D2", name: "Next visible Guidance after first L")
        try await assertDetail(try XCTUnwrap(selected.solveList.first), shows: "R U'", scene: scene, context: context)
        for (assigned, nextText, moves, count) in [
            ("L D2", "F B'", ["D2", "D2", "L'", "F"], 2),
            ("F B'", "U R2", ["B'", "B", "F'", "U"], 3)
        ] {
            try await wait { pending.contains { $0.reason == "prefetch" } }
            let generation = pending.remove(at: pending.firstIndex { $0.reason == "prefetch" }!)
            generation.complete(.init(context: generation.context, scrambles: [nextText]))
            for move in moves { cube.debugEmitPhysicalMove(move) }
            try await wait { selected.solveList.count == count && probe.snapshot?().scramble == nextText }
            XCTAssertEqual(probe.snapshot?().progress?.targetFacelets, SmartCubeBluetoothManager.facelets(afterApplying: nextText))
            let saved = try XCTUnwrap(selected.solveList.first)
            XCTAssertEqual(saved.scramble, assigned)
            XCTAssertEqual(saved.reconstruction?.initialFacelets, SmartCubeBluetoothManager.facelets(afterApplying: assigned))
            try await assertDetail(saved, shows: assigned, scene: scene, context: context)
        }
    }

    func testActualTimerRejectsGenerationFromPreviousDeviceAndConnectionAttempt() async throws {
        let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
        let session = Session(name: "Device ownership fixture", selectedTimingMethodRawValue: "smartCube", context: context)
        try context.save()
        let defaults = UserDefaults.standard
        let settings: [String: Any] = ["selectedSessionID": session.id.uuidString, "enteringTimesWith": "smartCube",
                                      "smartCubeShowVirtualCube": false, "smartCubeReadySound": false]
        let previous = settings.keys.map { ($0, defaults.object(forKey: $0)) }
        for (key, value) in settings { defaults.set(value, forKey: key) }
        defer { for (key, value) in previous { defaults.set(value, forKey: key) } }
        let manager = SmartCubeBluetoothManager.shared, a = UUID(), b = UUID()
        manager.prepareIfNeeded(); try await Task.sleep(nanoseconds: 150_000_000)
        let first = manager.debugMakeRoutedSession(for: a), second = manager.debugMakeRoutedSession(for: b)
        first.debugSeedConnectedState(deviceID: a, attemptID: UUID(), facelets: CubeSurface.solved(size: 3))
        second.debugSeedConnectedState(deviceID: b, attemptID: UUID(), facelets: CubeSurface.solved(size: 3))
        manager.selectActiveDevice(a)
        defer { manager.disconnect(deviceID: a); manager.disconnect(deviceID: b) }
        let probe = SmartCubeTimerGuidanceProbe(); var pending: [Generation] = []
        probe.generate = { pending.append(.init(context: $0, reason: $1, complete: $2)) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: TimerTabView()
            .environment(\.managedObjectContext, context).environment(\.smartCubeTimerGuidanceProbe, probe))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; probe.reset() }
        try await wait { pending.contains { $0.reason == "foreground" && $0.context.deviceID == a } }
        manager.selectActiveDevice(b)
        try await wait { pending.contains { $0.reason == "foreground" && $0.context.deviceID == b } }
        let newAttempt = UUID()
        second.debugSeedConnectedState(deviceID: b, attemptID: newAttempt, facelets: CubeSurface.solved(size: 3))
        try await wait { pending.contains { $0.reason == "foreground" && $0.context.connectionAttemptID == newAttempt } }
        let freshIndex = try XCTUnwrap(pending.lastIndex { $0.reason == "foreground" && $0.context.connectionAttemptID == newAttempt })
        let fresh = pending.remove(at: freshIndex), obsolete = pending
        pending.removeAll()
        for old in obsolete { old.complete(.init(context: old.context, scrambles: ["R U'"])) }
        XCTAssertEqual(probe.snapshot?().scramble, "…")
        fresh.complete(.init(context: fresh.context, scrambles: ["L D2"]))
        try await wait { probe.snapshot?().scramble == "L D2" }
        XCTAssertEqual(probe.snapshot?().progress?.targetFacelets, SmartCubeBluetoothManager.facelets(afterApplying: "L D2"))
        for old in obsolete { old.complete(.init(context: old.context, scrambles: ["F B'"])) }
        XCTAssertEqual(probe.snapshot?().scramble, "L D2")
        try await wait { pending.contains { $0.reason == "prefetch" } }
        XCTAssertTrue(pending.filter { $0.reason == "prefetch" }.allSatisfy {
            $0.context.deviceID == b && $0.context.connectionAttemptID == newAttempt
        })
    }

    func testActualTimerRejectsStaleCallbacksAcrossNextSessionPuzzleAndRemount() async throws {
        let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
        let firstSession = Session(name: "First owner", context: context)
        let secondSession = Session(name: "Second owner", context: context)
        let historical = Solve(time: 18, scramble: "B U2", event: "3x3", session: firstSession, context: context)
        try context.save()
        let defaults = UserDefaults.standard
        let settings: [String: Any] = ["selectedSessionID": firstSession.id.uuidString, "enteringTimesWith": "timer",
                                      "appLanguage": "en", "wcaInspectionEnabled": false, "timerArrangement": "classic"]
        let previous = settings.keys.map { ($0, defaults.object(forKey: $0)) }
        for (key, value) in settings { defaults.set(value, forKey: key) }
        defer { for (key, value) in previous { defaults.set(value, forKey: key) } }
        let probe = SmartCubeTimerGuidanceProbe(); var pending: [Generation] = []
        probe.generate = { pending.append(.init(context: $0, reason: $1, complete: $2)) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let host = UIHostingController(rootView: TimerTabView().environment(\.managedObjectContext, context)
            .environment(\.smartCubeTimerGuidanceProbe, probe))
        let tabs = UITabBarController()
        tabs.viewControllers = [host, UIViewController()]
        window.rootViewController = tabs; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; probe.reset() }
        try await wait { pending.contains { $0.reason == "foreground" } && probe.next != nil }
        let old = pending.remove(at: pending.firstIndex { $0.reason == "foreground" }!)
        probe.next?()
        try await wait { pending.contains { $0.reason == "foreground" } }
        let latest = pending.remove(at: pending.firstIndex { $0.reason == "foreground" }!)
        latest.complete(.init(context: latest.context, scrambles: ["L D2"]))
        old.complete(.init(context: old.context, scrambles: ["R U'"]))
        try await wait { probe.snapshot?().scramble == "L D2" }
        defaults.set(secondSession.id.uuidString, forKey: "selectedSessionID")
        try await wait { pending.contains { $0.reason == "foreground" && $0.context.sessionID == secondSession.id } }
        let sessionRequest = pending.remove(at: pending.firstIndex { $0.reason == "foreground" && $0.context.sessionID == secondSession.id }!)
        sessionRequest.complete(.init(context: sessionRequest.context, scrambles: ["F D'"]))
        for stale in pending { stale.complete(.init(context: stale.context, scrambles: ["B R2"])) }
        pending.removeAll()
        try await wait { probe.snapshot?().scramble == "F D'" }
        probe.selectEvent?(.twoByTwo)
        try await wait { pending.contains { $0.context.event == .twoByTwo && $0.reason == "foreground" } }
        let puzzleRequest = pending.remove(at: pending.firstIndex { $0.context.event == .twoByTwo && $0.reason == "foreground" }!)
        puzzleRequest.complete(.init(context: puzzleRequest.context, scrambles: ["U2 R F'"]))
        try await wait { probe.snapshot?().scramble == "U2 R F'" }
        XCTAssertEqual(probe.snapshot?().event, .twoByTwo)
        try await wait { pending.contains { $0.reason == "prefetch" } }
        let beforeRemount = pending.remove(at: pending.firstIndex { $0.reason == "prefetch" }!)
        probe.next?()
        try await wait { probe.snapshot?().scramble == "…" }
        tabs.selectedIndex = 1
        try await Task.sleep(nanoseconds: 100_000_000)
        tabs.selectedIndex = 0
        try await wait { pending.contains { $0.reason == "foreground" } }
        let resumed = pending.remove(at: pending.firstIndex { $0.reason == "foreground" }!)
        resumed.complete(.init(context: resumed.context, scrambles: ["F2 U R'"]))
        beforeRemount.complete(.init(context: beforeRemount.context, scrambles: ["B D2"]))
        try await wait { probe.snapshot?().scramble == "F2 U R'" }
        probe.start?(); probe.stop?(12)
        defaults.set(firstSession.id.uuidString, forKey: "selectedSessionID")
        try await wait { probe.snapshot?().sessionID == firstSession.id }
        XCTAssertEqual(probe.snapshot?().assignment?.sessionID, secondSession.id)
        XCTAssertEqual(probe.snapshot?().assignment?.event, .twoByTwo)
        probe.save?()
        try await wait { secondSession.solveList.count == 1 }
        XCTAssertEqual(secondSession.solveList.first?.scramble, "F2 U R'")
        XCTAssertEqual(secondSession.solveList.first?.event, PuzzleEvent.twoByTwo.rawValue)
        XCTAssertEqual(historical.scramble, "B U2", "Never silently rewrite historical solves")
    }
}
#endif

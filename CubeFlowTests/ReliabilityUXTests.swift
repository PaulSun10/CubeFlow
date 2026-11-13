#if DEBUG && os(iOS)
import XCTest
import SwiftUI
import CoreData
@testable import CubeFlow

@MainActor final class LocalBattleReliabilityTests: XCTestCase {
    func testPerPlayerAssignmentsAdvanceOnlyAfterCompletion() throws {
        var state = LocalBattleScrambleState()
        let a = state.request(.first, event: .threeByThree), b = state.request(.second, event: .threeByThree)
        XCTAssertTrue(state.receive("R U", for: a)); XCTAssertTrue(state.receive("F D", for: b))
        XCTAssertEqual(state.displayed[.first]?.text, "R U")
        XCTAssertTrue(state.begin(.first, event: .threeByThree))
        XCTAssertTrue(state.begin(.second, event: .threeByThree))
        XCTAssertEqual(state.finish(.first)?.text, "R U")
        let next = state.request(.first, event: .threeByThree)
        XCTAssertEqual(state.displayed[.first]?.text, "R U", "Keep prior text while replacement is pending")
        XCTAssertFalse(state.begin(.first, event: .threeByThree), "Never reuse a consumed scramble")
        XCTAssertEqual(state.active[.second]?.text, "F D")
        XCTAssertTrue(state.receive("B L", for: next))
        XCTAssertEqual(state.displayed[.second]?.request, b)
        XCTAssertEqual(state.finish(.second)?.text, "F D")
        XCTAssertNil(state.finish(.second), "No double advancement")
    }

    func testSwitchResetAndOutOfOrderRequestsCannotLeakBetweenPlayers() {
        var state = LocalBattleScrambleState()
        let old = state.request(.first, event: .threeByThree)
        let new = state.request(.first, event: .pyraminx)
        XCTAssertFalse(state.receive("R U", for: old))
        XCTAssertTrue(state.receive("R U r'", for: new))
        XCTAssertFalse(state.begin(.first, event: .threeByThree))
        XCTAssertNil(state.active[.second])
        state = LocalBattleScrambleState()
        XCTAssertFalse(state.receive("R U r'", for: new))
    }

    func testGenerationFailureIsNotAnAssignmentAndStaleFailuresCannotEraseNewContent() {
        var state = LocalBattleScrambleState()
        let old = state.request(.first, event: .threeByThree)
        state.fail("Unavailable", for: old)
        XCTAssertNil(state.displayed[.first]); XCTAssertFalse(state.begin(.first, event: .threeByThree))
        let new = state.request(.first, event: .threeByThree)
        XCTAssertTrue(state.receive("R U", for: new))
        state.fail("Unavailable", for: old)
        XCTAssertEqual(state.displayed[.first]?.text, "R U"); XCTAssertNil(state.failures[.first])
    }

    func testContactIsImmediateAndCancellationIsTerminal() {
        let view = BattleContactSurface.ContactView()
        var events: [(Bool, Bool)] = []
        view.changed = { events.append(($0, $1)) }
        view.begin(); XCTAssertTrue(view.isContactActive); XCTAssertEqual(events.count, 1)
        view.begin(); XCTAssertEqual(events.count, 1)
        view.finish(cancelled: true); XCTAssertFalse(view.isContactActive)
        XCTAssertEqual(events.count, 2); XCTAssertTrue(events[1].1)
        view.finish(cancelled: false); XCTAssertEqual(events.count, 2)
        view.begin(); view.finish(cancelled: false)
        XCTAssertEqual(events.count, 4); XCTAssertFalse(events[3].1)
    }

    func testMountedBattlePreservesIndependentOriginsAndOnlyFinisherAdvances() async throws {
        let defaults = UserDefaults.standard
        let keys: [String: Any] = ["enteringTimesWith": "timer", "appLanguage": "en", "wcaInspectionEnabled": false,
            "timerArrangement": "classic", "selectedSessionID": defaults.string(forKey: "selectedSessionID") ?? ""]
        let previous = keys.map { ($0.key, defaults.object(forKey: $0.key)) }
        keys.forEach { defaults.set($0.value, forKey: $0.key) }
        defer { previous.forEach { defaults.set($0.1, forKey: $0.0) }; AppOrientationManager.reset() }
        let persistence = PersistenceController(inMemory: true)
        _ = Session(name: "Battle", context: persistence.container.viewContext)
        try persistence.container.viewContext.save()
        let probe = LocalBattleTestProbe(), generation = SmartCubeTimerGuidanceProbe()
        var pending: [(TimerScrambleGenerationContext, String, @MainActor (TimerScrambleGenerationPayload) -> Void)] = []
        generation.generate = { pending.append(($0, $1, $2)) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: TimerTabView()
            .environment(\.managedObjectContext, persistence.container.viewContext)
            .environment(\.smartCubeTimerGuidanceProbe, generation).environment(\.localBattleTestProbe, probe))
        window.makeKeyAndVisible()
        defer {
            probe.mode?(.solo); probe.mode = nil; probe.press = nil; probe.release = nil; probe.cancel = nil; probe.snapshot = nil
            generation.reset(); window.isHidden = true; window.rootViewController = nil
        }
        try await wait { probe.mode != nil }
        for mode in [LocalBattleMode.headToHead, .sideBySide] {
            pending.removeAll(); probe.mode?(mode)
            try await wait { pending.filter { $0.1 == "battle" }.count == 2 }
            let requests = pending.filter { $0.1 == "battle" }; pending.removeAll()
            for (index, request) in requests.enumerated() { request.2(.init(context: request.0, scrambles: [index == 0 ? "R U" : "F D"])) }
            try await wait { probe.snapshot?().scrambles.displayed.count == 2 }
            window.layoutIfNeeded()
            func contacts(_ view: UIView) -> [BattleContactSurface.ContactView] {
                (view as? BattleContactSurface.ContactView).map { [$0] } ?? view.subviews.flatMap(contacts)
            }
            // Mode replacement keeps outgoing views during the accepted native
            // transition. Observe its completed layout, not its first frame.
            try await wait {
                window.layoutIfNeeded()
                let views = contacts(window)
                return views.count == 2 && views.allSatisfy { surface in
                    guard surface.bounds.width > 0, surface.bounds.height > 0 else { return false }
                    let point = surface.convert(CGPoint(x: surface.bounds.midX, y: surface.bounds.midY), to: window)
                    return window.hitTest(point, with: nil) === surface
                }
            }
            let surfaces = contacts(window)
            XCTAssertEqual(surfaces.count, 2)
            for surface in surfaces {
                let point = surface.convert(CGPoint(x: surface.bounds.midX, y: surface.bounds.midY), to: window)
                XCTAssertTrue(window.hitTest(point, with: nil) === surface, "Timer contact must reach the native surface, not be swallowed by the text stack")
            }
            probe.press?(.first); probe.cancel?(.first)
            XCTAssertNil(probe.snapshot?().firstStart)
            XCTAssertTrue(pending.isEmpty, "Preparation/cancellation must never advance")
            probe.press?(.first); probe.press?(.second); probe.release?(.first)
            let firstStart = try XCTUnwrap(probe.snapshot?().firstStart)
            XCTAssertNil(probe.snapshot?().secondStart); XCTAssertTrue(probe.snapshot?().secondPressing == true)
            try await Task.sleep(nanoseconds: 20_000_000)
            probe.release?(.second)
            XCTAssertGreaterThan(try XCTUnwrap(probe.snapshot?().secondStart), firstStart)
            let second = probe.snapshot?().scrambles.active[.second]
            probe.release?(.first)
            XCTAssertEqual(pending.filter { $0.1 == "battle" }.count, 1)
            XCTAssertEqual(probe.snapshot?().scrambles.active[.second], second)
            XCTAssertEqual(probe.snapshot?().scrambles.completed[.first]?.text, "R U")
            probe.release?(.second)
            XCTAssertEqual(pending.filter { $0.1 == "battle" }.count, 2)
        }
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTFail("Mounted battle timeout"); throw CancellationError()
    }
}

@MainActor final class ReliabilityPresentationTests: XCTestCase {
    func testPRUsesMeasuredFreeIntervalAboveClassicAndBelowCardsSplit() throws {
        let container = CGRect(x: 0, y: 0, width: 393, height: 800)
        let timer = CGRect(x: 100, y: 350, width: 193, height: 80)
        let bottom = CGRect(x: 10, y: 600, width: 180, height: 180)
        let classic = try XCTUnwrap(TimerPBPlacement.center(container: container, timer: timer, upperBottom: 230,
            obstacles: [bottom], bannerHeight: 24, aboveTimer: true))
        XCTAssertGreaterThan(classic.y - 12, 230); XCTAssertLessThan(classic.y + 12, timer.minY)
        for _ in ["cards", "split"] {
            let point = try XCTUnwrap(TimerPBPlacement.center(container: container, timer: timer, upperBottom: 230,
                obstacles: [bottom], bannerHeight: 24, aboveTimer: false))
            XCTAssertGreaterThan(point.y - 12, timer.maxY); XCTAssertLessThan(point.y + 12, bottom.minY)
        }
        XCTAssertNil(TimerPBPlacement.center(container: container, timer: timer, upperBottom: 345,
            obstacles: [], bannerHeight: 24, aboveTimer: true))
    }

    func testSystemLanguageAndManualOverridesRemainIndependent() throws {
        let domain = "Language." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        registerSystemAppLanguage(in: defaults, preferred: ["zh-HK"])
        XCTAssertTrue(followsSystemAppLanguage(in: defaults, domain: domain))
        XCTAssertEqual(defaults.string(forKey: "appLanguage"), "zh-Hant")
        let reader = AppStorage(wrappedValue: "en", "appLanguage", store: defaults)
        XCTAssertEqual(reader.wrappedValue, "zh-Hant", "Existing view defaults must honor the registered system fallback")
        defaults.set("ja", forKey: "appLanguage")
        registerSystemAppLanguage(in: defaults, preferred: ["zh-CN"])
        XCTAssertFalse(followsSystemAppLanguage(in: defaults, domain: domain))
        XCTAssertEqual(defaults.string(forKey: "appLanguage"), "ja")
        defaults.removeObject(forKey: "appLanguage")
        XCTAssertEqual(defaults.string(forKey: "appLanguage"), "zh-Hans")
        registerSystemAppLanguage(in: defaults, preferred: ["fr-FR"])
        XCTAssertEqual(defaults.string(forKey: "appLanguage"), "fr")
        XCTAssertEqual(systemAppLanguageCode(preferred: ["xx-XX"]), "en")
    }

    func testSpecialRegionsAndOrdinaryCountries() {
        XCTAssertEqual(WCARegionPresentation.name("XW", language: "en"), "Multiple Countries (World)")
        XCTAssertEqual(WCARegionPresentation.name("XW", language: "zh-Hant"), "多個國家 (世界)")
        for (code, name) in WCARegionPresentation.specialRegions {
            XCTAssertEqual(WCARegionPresentation.name(code, language: "en"), "Multiple Countries (\(name))")
        }
        XCTAssertEqual(WCARegionPresentation.name("US", language: "en"), "United States")
    }

    func testPenaltyButtonsReuseNativeSessionStyleAndEqualWidths() async throws {
        let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
        let session = Session(name: "Penalty", context: context)
        let solve = Solve(time: 10, scramble: "R U", event: "3x3", session: session, context: context)
        let notes = SolveNotesTestProbe()
        try context.save()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: SolveDetailAcceptance.view(for: solve, notesProbe: notes).environment(\.managedObjectContext, context))
        window.makeKeyAndVisible(); defer {
            notes.edit = nil; notes.done = nil; notes.isFocused = nil
            window.isHidden = true; window.rootViewController = nil
        }
        try await Task.sleep(nanoseconds: 200_000_000); window.layoutIfNeeded()
        notes.edit?("  Retain my notes  ")
        notes.done?()
        XCTAssertFalse(notes.isFocused?() ?? true)
        XCTAssertEqual(solve.comment, "Retain my notes")
        XCTAssertNotNil(window.rootViewController, "Done ends editing, not the detail presentation")
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        let buttons = descendants(window).compactMap { $0 as? UIButton }.filter { $0.accessibilityIdentifier?.hasPrefix("solve-penalty-") == true }
        XCTAssertEqual(buttons.count, 3)
        let widths = buttons.map { $0.bounds.width }
        XCTAssertLessThan((widths.max() ?? 0) - (widths.min() ?? 0), 1)
        XCTAssertTrue(buttons.allSatisfy { $0.bounds.height >= 44 })
        XCTAssertLessThan((buttons.map { $0.bounds.height }.max() ?? 0) - (buttons.map { $0.bounds.height }.min() ?? 0), 1)
        XCTAssertTrue(buttons.allSatisfy { $0.configuration?.cornerStyle == .capsule })
        let plus = try XCTUnwrap(buttons.first { $0.accessibilityIdentifier == "solve-penalty-plusTwo" })
        plus.sendActions(for: .touchUpInside)
        XCTAssertEqual(solve.result, .plusTwo)
        XCTAssertEqual(solve.time, 10, "Only penalty changes, not base result")
    }
}
#endif

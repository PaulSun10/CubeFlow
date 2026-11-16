#if DEBUG && os(iOS)
import Combine
import CoreData
import SwiftUI
import XCTest
@testable import CubeFlow

@MainActor final class ScreenAwakeTests: XCTestCase {
    func testDefaultOnAndNativePreferencePersistence() throws {
        let name = "ScreenAwake." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preference = AppStorage(wrappedValue: ScreenAwakePreference.defaultValue, ScreenAwakePreference.key, store: defaults)
        XCTAssertTrue(preference.wrappedValue)
        defaults.set("existing session", forKey: "selectedSessionID")
        XCTAssertTrue(ScreenAwakePreference.isEnabled(in: defaults))
        XCTAssertNil(defaults.object(forKey: ScreenAwakePreference.key), "No migration or persisted override needed")
        preference.wrappedValue = false
        let relaunched = try XCTUnwrap(UserDefaults(suiteName: name))
        XCTAssertFalse(ScreenAwakePreference.isEnabled(in: relaunched))
        preference.wrappedValue = true
        XCTAssertTrue(ScreenAwakePreference.isEnabled(in: relaunched))
    }

    func testOverlappingScenesCannotOverridePreferenceOrReviveRemovedRegistration() throws {
        let name = "ScreenAwake." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var writes: [Bool] = []
        let owner = ScreenAwakeCoordinator(defaults: defaults) { writes.append($0) }
        let first = owner.register(eligible: true)
        let second = owner.register(eligible: true)
        owner.update(first, eligible: false)
        XCTAssertEqual(writes, [true])
        defaults.set(false, forKey: ScreenAwakePreference.key)
        owner.update(first, eligible: false)
        XCTAssertEqual(writes, [true, false], "Disable globally even before the eligible scene updates")
        owner.unregister(first)
        owner.update(first, eligible: true)
        owner.update(second, eligible: true)
        XCTAssertEqual(writes, [true, false])
        defaults.set(true, forKey: ScreenAwakePreference.key)
        owner.update(second, eligible: true)
        owner.unregister(second)
        owner.update(first, eligible: true)
        XCTAssertEqual(writes, [true, false, true, false])
    }

    func testMountedRootTracksTabsSceneAndPreferenceNotTimerOrBattleModes() async throws {
        let name = "ScreenAwake." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PersistenceController(inMemory: true)
        let session = Session(name: "Screen awake", context: store.container.viewContext)
        defaults.set(session.id.uuidString, forKey: "selectedSessionID")
        try store.container.viewContext.save()
        let phase = MutablePhase(), battle = LocalBattleTestProbe()
        let generation = SmartCubeTimerGuidanceProbe()
        generation.generate = { context, _, finish in finish(.init(context: context, scrambles: ["R U"])) }
        var writes: [Bool] = []
        let owner = ScreenAwakeCoordinator(defaults: defaults) { writes.append($0) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: PhaseHost(phase: phase) {
            IPhoneContentView(screenAwakeCoordinator: owner)
                .environment(\.managedObjectContext, store.container.viewContext)
                .environment(\.localBattleTestProbe, battle)
                .environment(\.smartCubeTimerGuidanceProbe, generation)
                .defaultAppStorage(defaults)
        })
        window.makeKeyAndVisible()
        defer { battle.mode?(.solo); generation.reset(); window.isHidden = true; window.rootViewController = nil }
        try await wait { writes.last == true && battle.mode != nil }
        XCTAssertEqual(writes, [true])
        let arrangement = AppStorage(wrappedValue: "cards", "timerArrangement", store: defaults)
        let input = AppStorage(wrappedValue: "timer", "enteringTimesWith", store: defaults)
        arrangement.wrappedValue = "classic"; await settle()
        arrangement.wrappedValue = "cards"; await settle()
        for method in SessionTimingMethod.allCases {
            input.wrappedValue = method.rawValue
            await settle()
        }
        input.wrappedValue = "timer"; await settle()
        for mode in [LocalBattleMode.headToHead, .sideBySide] {
            battle.mode?(mode)
            try await wait { battle.snapshot?().scrambles.displayed.count == 2 }
            battle.configure?(.first, .init(input: .manual))
            battle.configure?(.second, .init(input: .smartCube))
            await settle()
        }
        battle.mode?(.solo)
        await settle()
        XCTAssertEqual(writes, [true], "Timer stays selected throughout, including after exiting Battle")
        let request = AppStorage(wrappedValue: "", "requestedIPhoneTab", store: defaults)
        for tab in ["data", "algs", "explore", "settings"] {
            request.wrappedValue = tab
            try await wait { writes.last == false }
            request.wrappedValue = "timer"
            try await wait { writes.last == true }
        }
        phase.value = .inactive
        try await wait { writes.last == false }
        phase.value = .background
        await settle()
        phase.value = .active
        try await wait { writes.last == true }
        let preference = AppStorage(wrappedValue: true, ScreenAwakePreference.key, store: defaults)
        preference.wrappedValue = false
        try await wait { writes.last == false }
        let count = writes.count
        phase.value = .background; await settle()
        phase.value = .active; await settle()
        battle.mode?(.headToHead); await settle()
        battle.mode?(.solo); await settle()
        request.wrappedValue = "settings"; await settle()
        request.wrappedValue = "timer"; await settle()
        XCTAssertEqual(writes.count, count, "A disabled preference stays disabled through navigation and lifecycle changes")
        preference.wrappedValue = true
        try await wait { writes.last == true }
    }

    private func wait(_ condition: () -> Bool, line: UInt = #line) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Idle timer lifecycle did not reach expected state", line: line)
        throw CancellationError()
    }

    private func settle() async { try? await Task.sleep(nanoseconds: 80_000_000) }

    private final class MutablePhase: ObservableObject {
        @Published var value: ScenePhase = .active
    }

    private struct PhaseHost<Content: View>: View {
        @ObservedObject var phase: MutablePhase
        @ViewBuilder let content: () -> Content
        var body: some View { content().environment(\.scenePhase, phase.value) }
    }
}
#endif

import Foundation
import Combine
import Testing
@testable import CubeFlow

@Suite("Smart cube experience closeout")
struct SmartCubeCloseoutTests {
    @Test func activeSelectionPreservesCurrentThenRememberedThenSoleCandidate() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(SavedSmartCubeSelection.activeID(current: a, remembered: b, compatibleIDs: [a, b]) == a)
        #expect(SavedSmartCubeSelection.activeID(current: c, remembered: b, compatibleIDs: [a, b]) == b)
        #expect(SavedSmartCubeSelection.activeID(current: a, remembered: a, compatibleIDs: [b]) == b)
        #expect(SavedSmartCubeSelection.activeID(current: nil, remembered: c, compatibleIDs: [a, b]) == nil)
        #expect(SavedSmartCubeSelection.activeID(current: a, remembered: a, compatibleIDs: []) == nil)
    }

    @Test @MainActor func onlyActiveConnectedSessionReachesTimerAndSequenceNeverResets() {
        let a = UUID(), b = UUID()
        let router = SmartCubeActiveFeedRouter()
        let first = SmartCubeCanonicalFeed(), second = SmartCubeCanonicalFeed()
        let solved = CubeSurface.solved(size: 3)
        let one = first.events.sink { router.consume($0, from: a, connected: true) }
        let two = second.events.sink { router.consume($0, from: b, connected: true) }
        defer { one.cancel(); two.cancel() }
        router.activate(a, facelets: solved, trusted: true)
        let initialSequence = router.feed.sequence
        second.send(move: SmartCubeMoveEvent(move: "U", serial: 1, face: 0, direction: 0, localTimestamp: .now, cubeTimestampMilliseconds: nil), facelets: solved)
        #expect(router.feed.sequence == initialSequence)
        first.send(move: SmartCubeMoveEvent(move: "R", serial: 1, face: 1, direction: 0, localTimestamp: .now, cubeTimestampMilliseconds: nil), facelets: solved)
        #expect(router.feed.sequence == initialSequence + 1)
        router.activate(b, facelets: solved, trusted: true)
        let switched = router.feed.sequence
        first.breakContinuity(.historyGap, facelets: nil)
        #expect(router.feed.sequence == switched)
        #expect(router.feed.isStateTrusted)
        second.send(move: SmartCubeMoveEvent(move: "F", serial: 2, face: 2, direction: 0, localTimestamp: .now, cubeTimestampMilliseconds: nil), facelets: solved)
        #expect(router.feed.sequence == switched + 1)
        router.consume(.boundary(.init(sequence: 99, reason: .disconnected, facelets: nil)), from: b, connected: false)
        #expect(router.feed.sequence == switched + 1)
        #expect(first.sequence == 2)
        #expect(second.sequence == 2)
    }

    @Test func modelRedundancyIgnoresPeripheralSuffixAndIncidentalDigits() {
        let model = "GAN 16 ui"
        for name in ["GAN16ui_C0Y14", "gan-16-ui_C0Y16", "GAN 16 UI"] {
            #expect(!SmartCubeDeviceNamePresentation.showsModel(originalName: name, customName: nil, model: model))
        }
        for alias in ["Competition 16", "Practice 16", "My GAN 16 ui"] {
            #expect(!SmartCubeDeviceNamePresentation.showsModel(originalName: "GAN16ui_C0Y16", customName: alias, model: model))
        }
        for alias in ["Paul's GAN", "Box 16", "Shelf 16", "Competition 160", "2016 cube"] {
            #expect(SmartCubeDeviceNamePresentation.showsModel(originalName: "GAN16ui_C0Y16", customName: alias, model: model))
        }
        #expect(SmartCubeDeviceNamePresentation.showsModel(originalName: "GAN_C0Y16", customName: nil, model: model))
        #expect(SmartCubeDeviceNamePresentation.showsModel(originalName: "WCU_MY32", customName: "Competition 16", model: "MoYu Smart Cube"))
    }

    @Test @MainActor func devicePreferencesRoundTripWithoutOverwritingFactoryIdentity() throws {
        let suite = "CubeFlow.SmartCubeCloseoutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SavedSmartCubeDevices(defaults: defaults)
        let a = UUID(), b = UUID()
        let gan = SmartCubeIdentity.resolve(advertisedName: "GAN16ui_C0Y14", protocolFamily: .ganGen4,
            protocolConfirmed: true, protocolInfo: nil, serviceIdentifiers: [])
        let weiPo = SmartCubeIdentity.resolve(advertisedName: "WCU_MY22", protocolFamily: .moyu,
            protocolConfirmed: true, protocolInfo: nil, serviceIdentifiers: [])
        store.remember(id: a, identity: gan, fallbackName: nil)
        store.remember(id: b, identity: weiPo, fallbackName: nil)
        store.rename(a, to: " Paul's GAN ")
        store.setAutoConnect(true, for: a)
        store.setAutoConnect(true, for: b)
        store.setIconColor(StoredColorData(r: 0.2, g: 0.6, b: 0.8), for: a)
        store.rememberTransport(id: a, salt: [1, 2, 3, 4, 5, 6], manufacturerDataHex: "AABB", macAddress: "06:05:04:03:02:01")
        store.markActive(a)
        store.markActive(b)
        let restored = SavedSmartCubeDevices(defaults: defaults)
        #expect(restored.device(a)?.originalName == "GAN16ui_C0Y14")
        #expect(restored.device(a)?.displayName == "Paul's GAN")
        #expect(restored.device(a)?.autoConnect == true && restored.device(b)?.autoConnect == true)
        #expect(restored.lastActiveID(puzzleSize: 3) == a)
        #expect(restored.lastActiveID(puzzleSize: 2) == b)
        #expect(restored.device(a)?.encryptionSalt == [1, 2, 3, 4, 5, 6])
        #expect(restored.device(a)?.iconColor == StoredColorData(r: 0.2, g: 0.6, b: 0.8))
        #expect(restored.device(b)?.iconColor == nil)
        restored.rename(a, to: nil)
        restored.setIconColor(nil, for: a)
        #expect(restored.device(a)?.displayName == "GAN16ui_C0Y14")
        #expect(restored.device(a)?.autoConnect == true)
    }

    @Test func oldSavedDeviceDataRemainsDecodable() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","originalName":"WCU_MY22","modelName":"MoYu WeiPo V5 AI","protocolFamily":"MoYu/WCU","puzzleSize":2,"autoConnect":true}
        """
        let old = try JSONDecoder().decode(SavedSmartCubeDevice.self, from: Data(json.utf8))
        #expect(old.iconColor == nil && old.encryptionSalt == nil)
        #expect(old.puzzleSize == 2 && old.autoConnect)
    }

    @Test @MainActor func scrambleRestorationIsScopedToTimerSessionAndPuzzleNotBLEState() throws {
        let suite = "CubeFlow.ScrambleRestorationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let timerSession = UUID(), otherSession = UUID()
        let store = SmartCubeTimerPresentationStore(defaults: defaults)
        store.saveScramble("R U F", timerSessionID: timerSession, puzzleSize: 3)
        store.saveScramble("R U", timerSessionID: timerSession, puzzleSize: 2)
        let restored = SmartCubeTimerPresentationStore(defaults: defaults)
        #expect(restored.restoredScramble(timerSessionID: timerSession, puzzleSize: 3) == "R U F")
        #expect(restored.restoredScramble(timerSessionID: timerSession, puzzleSize: 2) == "R U")
        #expect(restored.restoredScramble(timerSessionID: otherSession, puzzleSize: 3) == nil)
        #expect(restored.snapshot == nil)
    }

    @Test @MainActor func inspectionUsesExistingThresholdsAndExpiresWithoutPreventingPhysicalStart() {
        #expect(InspectionPenaltyPolicy.penalty(for: 15) == .plusTwo)
        #expect(InspectionPenaltyPolicy.penalty(for: 15.001) == .plusTwo)
        #expect(InspectionPenaltyPolicy.penalty(for: 16.999) == .plusTwo)
        #expect(InspectionPenaltyPolicy.penalty(for: 17) == .dnf)
        var lifecycle = SmartCubeSolveLifecycle()
        let action = lifecycle.scrambleDidComplete(inspectionEnabled: true, completingMoveID: nil)
        #expect(action == .beginInspection)
        lifecycle.inspectionDidAdvance(elapsed: 16)
        #expect(lifecycle.phase == .inspecting)
        lifecycle.inspectionDidAdvance(elapsed: 17)
        #expect(lifecycle.phase == .inspectionExpired)
        let move = SmartCubeMoveEvent(move: "R", serial: 1, face: 1, direction: 0, localTimestamp: .now, cubeTimestampMilliseconds: nil)
        let start = lifecycle.physicalMoveDidOccur(move)
        #expect(start == .startTiming(move))
        #expect(lifecycle.phase == .timing)
        var combined = SmartCubeSolveLifecycle()
        let combinedAction = combined.scrambleDidComplete(inspectionEnabled: false, completingMoveID: nil)
        combined.inspectionDidAdvance(elapsed: 100)
        #expect(combinedAction == .enteredReady && combined.phase == .ready)
    }

    @Test func moyuAmbiguousThreeByThreeModelsRemainUnknown() {
        let identity = SmartCubeIdentity.resolve(advertisedName: "WCU_MY32", protocolFamily: .moyu,
            protocolConfirmed: true, protocolInfo: nil, serviceIdentifiers: [])
        #expect(identity.puzzleKind == .threeByThree)
        #expect(identity.resolvedModel == nil)
        let weiPo = SmartCubeIdentity.resolve(advertisedName: "WCU_MY22", protocolFamily: .moyu,
            protocolConfirmed: true, protocolInfo: nil, serviceIdentifiers: [])
        #expect(weiPo.puzzleKind == .twoByTwo)
        #expect(weiPo.resolvedModel == "MoYu WeiPo V5 AI")
    }
}

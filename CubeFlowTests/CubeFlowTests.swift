//
//  CubeFlowTests.swift
//  CubeFlowTests
//
//  Created by Paul Sun on 3/2/26.
//

import Foundation
import CoreData
import SwiftUI
import Testing
#if canImport(UIKit)
import UIKit
#endif
@testable import CubeFlow

struct CubeFlowTests {

    @Test func smartCubeScrambleProgressAdvancesByPhysicalState() throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: "R U D"))
        let afterR = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "R"))
        let afterRU = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "R U"))

        #expect(progress.update(with: afterR) == .advanced)
        #expect(progress.verifiedMoveCount == 1)
        #expect(progress.update(with: afterRU) == .advanced)
        #expect(progress.verifiedMoveCount == 2)
    }

    @Test func smartCubeScrambleProgressAcceptsCommutingLaterState() throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: "R U D"))
        let afterR = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "R"))
        let afterRD = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "R D"))
        let afterRDU = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "R D U"))

        #expect(progress.update(with: afterR) == .advanced)
        #expect(progress.update(with: afterRD) == .matchedLater)
        #expect(progress.completedTokenIndices == [0, 2])
        #expect(progress.update(with: afterRDU) == .completed)
        #expect(progress.verifiedMoveCount == 3)
    }

    @Test func smartCubeScrambleProgressAttributesOppositeFaceMoveToItsToken() throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: "D2 U2"))
        let afterU2 = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "U2"))
        let afterU2D2 = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "U2 D2"))

        #expect(progress.update(with: afterU2) == .matchedLater)
        #expect(progress.completedTokenIndices == [1])
        #expect(progress.update(with: afterU2D2) == .completed)
        #expect(progress.completedTokenIndices == [0, 1])
    }

    @Test func smartCubeScrambleProgressRejectsNoncommutingLaterMove() throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: "R U"))
        let afterU = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "U"))

        #expect(progress.update(with: afterU) == .deviated)
        #expect(progress.isDeviated)
        #expect(progress.completedTokenIndices.isEmpty)
    }

    @Test func smartCubeScrambleProgressReturnsToExpectedState() throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: "R U D"))
        let afterR = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "R"))
        let deviation = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "R F"))

        #expect(progress.update(with: afterR) == .advanced)
        #expect(progress.update(with: deviation) == .deviated)
        #expect(progress.isDeviated)
        #expect(progress.update(with: afterR) == .returned)
        #expect(!progress.isDeviated)
        #expect(progress.verifiedMoveCount == 1)
    }

    @Test(arguments: ["U2", "D2", "R2", "L2", "F2", "B2"])
    func smartCubeHalfTurnAcceptsEitherQuarterTurnAsPartialProgress(token: String) throws {
        for suffix in ["", "'"] {
            var progress = try #require(SmartCubeScrambleProgress(scramble: token))
            let quarterTurn = String(token.prefix(1)) + suffix
            let intermediate = try #require(SmartCubeBluetoothManager.facelets(afterApplying: quarterTurn))
            let completed = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "\(quarterTurn) \(quarterTurn)"))

            #expect(progress.update(with: intermediate) == .partial)
            #expect(progress.completedTokenIndices.isEmpty)
            #expect(!progress.isDeviated)
            #expect(progress.update(with: completed) == .completed)
            #expect(progress.completedTokenIndices == [0])
        }
    }

    @Test func smartCubeHalfTurnCanReturnFromPartialCheckpoint() throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: "L2 U"))
        let afterL = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "L"))
        let incompatible = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "L F"))

        #expect(progress.update(with: afterL) == .partial)
        #expect(progress.update(with: incompatible) == .deviated)
        #expect(progress.update(with: afterL) == .returned)
        #expect(!progress.isDeviated)
        #expect(progress.update(with: SmartCubeBluetoothManager.solvedFacelets) == .returned)
        #expect(progress.completedTokenIndices.isEmpty)
        #expect(!progress.isDeviated)
    }

    @Test func smartCubeHalfTurnPartialProgressPreservesCommutingAttribution() throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: "D2 U2"))
        let afterU = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "U"))
        let afterUU = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "U U"))
        let completed = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "U U D2"))

        #expect(progress.update(with: afterU) == .partial)
        #expect(progress.update(with: afterUU) == .matchedLater)
        #expect(progress.completedTokenIndices == [1])
        #expect(progress.update(with: completed) == .completed)
    }

    @Test func smartCubeCompletionDoesNotStartTimerUntilNextMove() {
        var lifecycle = SmartCubeSolveLifecycle()
        let finalScrambleMoveID = UUID()
        let completionAction = lifecycle.scrambleDidComplete(
            inspectionEnabled: false,
            completingMoveID: finalScrambleMoveID
        )
        let startDate = Date(timeIntervalSince1970: 123)

        #expect(completionAction == .enteredReady)
        #expect(lifecycle.phase == .ready)
        let completingMove = smartCubeMove(id: finalScrambleMoveID, timestamp: startDate)
        let solveMove = smartCubeMove(timestamp: startDate)
        #expect(lifecycle.physicalMoveDidOccur(completingMove) == .none)
        #expect(lifecycle.phase == .ready)
        #expect(lifecycle.physicalMoveDidOccur(solveMove) == .startTiming(solveMove))
        #expect(lifecycle.phase == .timing)
    }

    @Test func smartCubeInspectionBeginsAtCompletionAndHandsOffOnFirstMove() {
        var lifecycle = SmartCubeSolveLifecycle()
        let finalScrambleMoveID = UUID()
        let startDate = Date(timeIntervalSince1970: 456)

        #expect(lifecycle.scrambleDidComplete(
            inspectionEnabled: true,
            completingMoveID: finalScrambleMoveID
        ) == .beginInspection)
        #expect(lifecycle.phase == .inspecting)
        let completingMove = smartCubeMove(id: finalScrambleMoveID, timestamp: startDate)
        let solveMove = smartCubeMove(timestamp: startDate)
        #expect(lifecycle.physicalMoveDidOccur(completingMove) == .none)
        #expect(lifecycle.phase == .inspecting)
        #expect(lifecycle.physicalMoveDidOccur(solveMove) == .startTiming(solveMove))
        #expect(lifecycle.phase == .timing)
    }

    @Test func smartCubeTimingUsesDeviceClockInsteadOfDelayedSolvedObservation() throws {
        let start = smartCubeMove(
            timestamp: Date(timeIntervalSince1970: 100.050),
            cubeMilliseconds: 10_000,
            source: .deviceClock
        )
        let end = smartCubeMove(
            timestamp: Date(timeIntervalSince1970: 108.421),
            cubeMilliseconds: 18_371,
            source: .deviceClock
        )
        let observed = Date(timeIntervalSince1970: 108.610)

        let timing = try #require(SmartCubeSolveTiming.resolved(
            startMove: start,
            endMove: end,
            solvedObservedAt: observed
        ))
        #expect(abs(timing.duration - 8.371) < 0.000_001)
        #expect(timing.startDate == start.localTimestamp)
        #expect(timing.endDate == end.localTimestamp)
    }

    @Test func smartCubeTimingUsesReconstructedHostTimeAsExplicitFallback() throws {
        let start = smartCubeMove(
            timestamp: Date(timeIntervalSince1970: 200),
            source: .hostReceipt
        )
        let end = smartCubeMove(
            timestamp: Date(timeIntervalSince1970: 207.25),
            source: .reconstructed
        )

        let timing = try #require(SmartCubeSolveTiming.resolved(
            startMove: start,
            endMove: end,
            solvedObservedAt: Date(timeIntervalSince1970: 208)
        ))
        #expect(timing.duration == 7.25)
    }

    @Test func smartCubeTimingFallsBackToObservationForNonmonotonicMoveTime() throws {
        let start = smartCubeMove(timestamp: Date(timeIntervalSince1970: 300))
        let staleEnd = smartCubeMove(timestamp: Date(timeIntervalSince1970: 299))

        let timing = try #require(SmartCubeSolveTiming.resolved(
            startMove: start,
            endMove: staleEnd,
            solvedObservedAt: Date(timeIntervalSince1970: 301)
        ))
        #expect(timing.duration == 1)
        #expect(timing.endDate == Date(timeIntervalSince1970: 301))
    }

    @Test func smartCubeTransitionOptionsRespectCompletedMoveBehavior() {
        #expect(SmartCubeScrambleTransition.allowed(for: .collapse) == SmartCubeScrambleTransition.allCases)
        #expect(SmartCubeScrambleTransition.allowed(for: .trail) == [.blur, .instant])
        #expect(SmartCubeScrambleTransition.resolved(storedRawValue: "slide", behavior: .trail) == .blur)
        #expect(SmartCubeScrambleTransition.resolved(storedRawValue: "instant", behavior: .trail) == .instant)
    }

    @Test func smartCubeIdentityFallsBackWithoutInventingConsumerModel() {
        let identity = SmartCubeIdentity.resolve(
            advertisedName: "GAN16ui_C014",
            protocolFamily: .ganGen4,
            protocolConfirmed: true,
            protocolInfo: nil,
            serviceIdentifiers: ["00000001-0000-1000-8000-00805F9B34FB"]
        )

        #expect(identity.manufacturer == .gan)
        #expect(identity.protocolFamily == .ganGen4)
        #expect(identity.advertisedName == "GAN16ui_C014")
        #expect(identity.resolvedModel == nil)
        #expect(identity.displayName == "GAN Smart Cube")
        #expect(identity.identificationConfidence == .protocolFamily)
    }

    @Test func smartCubeIdentityResolvesVerifiedGANGen4HardwareIdentifiers() throws {
        let cases = [
            (protocolIdentifier: "GAN16ui", consumerModel: "GAN 16 ui"),
            (protocolIdentifier: "GAN12uiM", consumerModel: "GAN 12 ui MagLev"),
            (protocolIdentifier: "GANi4", consumerModel: "GAN i4 MagLev")
        ]

        for model in cases {
            let info = try #require(SmartCubeProtocolIdentityInfo(
                hardwareSummary: "\(model.protocolIdentifier) HW 1.0 SW 2.3 2026-01-09"
            ))
            let identity = SmartCubeIdentity.resolve(
                advertisedName: "Renamed Cube",
                protocolFamily: .ganGen4,
                protocolConfirmed: true,
                protocolInfo: info,
                serviceIdentifiers: []
            )

            #expect(identity.protocolModelIdentifier == model.protocolIdentifier)
            #expect(identity.resolvedModel == model.consumerModel)
            #expect(identity.displayName == model.consumerModel)
            #expect(identity.advertisedName == "Renamed Cube")
            #expect(identity.identificationConfidence == .protocolReportedIdentity)
        }
    }

    @Test func smartCubeIdentityDoesNotResolveUnverifiedGANHardwareIdentifier() throws {
        let info = try #require(SmartCubeProtocolIdentityInfo(
            hardwareSummary: "GANFutureModel HW 1.0 SW 1.0 2026-01-01"
        ))
        let identity = SmartCubeIdentity.resolve(
            advertisedName: "GANFutureModel_1234",
            protocolFamily: .ganGen4,
            protocolConfirmed: true,
            protocolInfo: info,
            serviceIdentifiers: []
        )

        #expect(identity.protocolModelIdentifier == "GANFutureModel")
        #expect(identity.resolvedModel == nil)
        #expect(identity.displayName == "GAN Smart Cube")
    }

    @Test func smartCubeIdentityUsesConfirmedProtocolAfterAdvertisementRename() {
        let identity = SmartCubeIdentity.resolve(
            advertisedName: "Paul's Cube",
            protocolFamily: .moyu,
            protocolConfirmed: true,
            protocolInfo: nil,
            serviceIdentifiers: ["0783B03E-7735-B5A0-1760-A305D2795CB0"]
        )

        #expect(identity.advertisedName == "Paul's Cube")
        #expect(identity.manufacturer == .moYu)
        #expect(identity.protocolFamily == .moyu)
        #expect(identity.displayName == "MoYu Smart Cube")
        #expect(identity.identificationConfidence == .protocolFamily)
    }

    @Test func smartCubeIdentityPreservesMoYuProtocolSignatureWithoutFalseMapping() throws {
        let info = try #require(SmartCubeProtocolIdentityInfo(
            hardwareSummary: "WCU_MY32 HW 1.2 SW 3.4"
        ))
        let identity = SmartCubeIdentity.resolve(
            advertisedName: "WCU_MY32_A388",
            protocolFamily: .moyu,
            protocolConfirmed: true,
            protocolInfo: info,
            serviceIdentifiers: []
        )

        #expect(identity.protocolModelIdentifier == "WCU_MY32")
        #expect(identity.hardwareVersion == "1.2")
        #expect(identity.firmwareVersion == "3.4")
        #expect(identity.resolvedModel == nil)
        #expect(identity.identificationConfidence == .protocolReportedIdentity)
    }

    @Test(arguments: ["2.7", "2.11"])
    func smartCubeIdentityKeepsObservedMoYuSignaturesGeneric(firmwareVersion: String) throws {
        let info = try #require(SmartCubeProtocolIdentityInfo(
            hardwareSummary: "WCU_MY32 HW 2.1 SW \(firmwareVersion)"
        ))
        let identity = SmartCubeIdentity.resolve(
            advertisedName: "Custom BLE Name",
            protocolFamily: .moyu,
            protocolConfirmed: true,
            protocolInfo: info,
            serviceIdentifiers: []
        )

        #expect(identity.protocolModelIdentifier == "WCU_MY32")
        #expect(identity.hardwareVersion == "2.1")
        #expect(identity.firmwareVersion == firmwareVersion)
        #expect(identity.resolvedModel == nil)
        #expect(identity.displayName == "MoYu Smart Cube")
    }

    @Test func smartCubeHighlightToneLightensDarkColorsWithoutChangingColorFamily() {
        let background = StoredColorData(r: 0.55, g: 0.02, b: 0.02)
        let foreground = SmartCubeHighlightToneResolver.contrastingTone(for: background)

        #expect(foreground.r > background.r)
        #expect(foreground.g > background.g)
        #expect(foreground.b > background.b)
        #expect(foreground.r > foreground.g)
        #expect(foreground.r > foreground.b)
        #expect(SmartCubeHighlightToneResolver.contrastRatio(background, foreground) >= 3.49)
    }

    @Test func smartCubeHighlightToneDarkensLightColorsWithoutChangingColorFamily() {
        let background = StoredColorData(r: 1.0, g: 0.72, b: 0.72)
        let foreground = SmartCubeHighlightToneResolver.contrastingTone(for: background)

        #expect(foreground.r < background.r)
        #expect(foreground.g < background.g)
        #expect(foreground.b < background.b)
        #expect(foreground.r > foreground.g)
        #expect(foreground.r > foreground.b)
        #expect(SmartCubeHighlightToneResolver.contrastRatio(background, foreground) >= 3.49)
    }

    @Test func smartCubeHighlightToneKeepsNeutralColorsNeutral() {
        let blackOnWhite = SmartCubeHighlightToneResolver.contrastingTone(
            for: StoredColorData(r: 1, g: 1, b: 1)
        )
        let whiteOnBlack = SmartCubeHighlightToneResolver.contrastingTone(
            for: StoredColorData(r: 0, g: 0, b: 0)
        )

        #expect(blackOnWhite == StoredColorData(r: 0, g: 0, b: 0))
        #expect(whiteOnBlack == StoredColorData(r: 1, g: 1, b: 1))
    }

    @Test func smartCubeHighlightCapsuleStaysCenteredAtContainerEdges() {
        let container = CGSize(width: 100, height: 30)
        let leftToken = CGRect(x: 0, y: 5, width: 20, height: 18)
        let rightToken = CGRect(x: 80, y: 5, width: 20, height: 18)

        let leftCapsule = SmartCubeHighlightCapsuleGeometry.frame(
            around: leftToken,
            containerSize: container
        )
        let rightCapsule = SmartCubeHighlightCapsuleGeometry.frame(
            around: rightToken,
            containerSize: container
        )

        #expect(leftCapsule.minX == 0)
        #expect(rightCapsule.maxX == container.width)
        #expect(leftCapsule.midX == leftToken.midX)
        #expect(rightCapsule.midX == rightToken.midX)
        #expect(leftCapsule.width == leftToken.width)
        #expect(rightCapsule.width == rightToken.width)
        #expect(leftToken == CGRect(x: 0, y: 5, width: 20, height: 18))
        #expect(rightToken == CGRect(x: 80, y: 5, width: 20, height: 18))
    }

    @Test func smartCubeEffectiveEventDoesNotMutateNormalSelection() {
        let normalEvent = PuzzleEvent.fourByFour

        #expect(SmartCubeTimerEventPolicy.effectiveEvent(
            normalEvent: normalEvent,
            isSmartCubeTiming: true
        ) == .threeByThree)
        #expect(SmartCubeTimerEventPolicy.effectiveEvent(
            normalEvent: normalEvent,
            isSmartCubeTiming: false
        ) == normalEvent)
    }

    @Test func smartCubeScrambleReplacementRequiresANewPhysicalMove() {
        let previousMoveID = UUID()
        let establishedAt = Date(timeIntervalSince1970: 500)
        var epoch = SmartCubeScrambleEpoch()
        var lifecycle = SmartCubeSolveLifecycle()

        epoch.establish(at: establishedAt, latestMoveID: previousMoveID)
        #expect(epoch.completionAction(
            inspectionEnabled: true,
            completingMoveID: previousMoveID,
            lifecycle: &lifecycle
        ) == .none)
        #expect(lifecycle.phase == .scrambling)

        let staleMove = smartCubeMove(
            timestamp: establishedAt.addingTimeInterval(-0.01)
        )
        let acceptedStaleMove = epoch.observePhysicalMove(staleMove)
        let acceptedBaselineMove = epoch.observePhysicalMove(smartCubeMove(
            id: previousMoveID,
            timestamp: establishedAt.addingTimeInterval(0.01)
        ))
        #expect(!acceptedStaleMove)
        #expect(!acceptedBaselineMove)
        #expect(lifecycle.phase == .scrambling)

        let finalPhysicalScrambleMove = smartCubeMove(
            timestamp: establishedAt.addingTimeInterval(0.02)
        )
        let acceptedFinalScrambleMove = epoch.observePhysicalMove(finalPhysicalScrambleMove)
        #expect(acceptedFinalScrambleMove)
        #expect(epoch.completionAction(
            inspectionEnabled: true,
            completingMoveID: finalPhysicalScrambleMove.id,
            lifecycle: &lifecycle
        ) == .beginInspection)
        #expect(lifecycle.phase == .inspecting)
    }

    @Test func smartCubeNewScrambleEpochRejectsPreviousEpochPublications() {
        let firstEstablishedAt = Date(timeIntervalSince1970: 700)
        let oldMove = smartCubeMove(timestamp: firstEstablishedAt.addingTimeInterval(1))
        var epoch = SmartCubeScrambleEpoch()

        epoch.establish(at: firstEstablishedAt, latestMoveID: nil)
        let acceptedFirstEpochMove = epoch.observePhysicalMove(oldMove)
        #expect(acceptedFirstEpochMove)
        #expect(epoch.hasAcceptedPhysicalMove)

        epoch.establish(
            at: firstEstablishedAt.addingTimeInterval(2),
            latestMoveID: oldMove.id
        )
        #expect(!epoch.hasAcceptedPhysicalMove)
        let acceptedPreviousEpochMove = epoch.observePhysicalMove(oldMove)
        #expect(!acceptedPreviousEpochMove)
    }

    @Test func smartCubeCurrentMoveHighlightTracksNormalProgress() throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: "R U D"))
        #expect(progress.currentMoveTokenIndex == 0)

        let afterR = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "R"))
        #expect(progress.update(with: afterR) == .advanced)
        #expect(progress.currentMoveTokenIndex == 1)
    }

    @Test func smartCubeCurrentMoveHighlightUsesAuthoritativeCommutingState() throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: "D2 U2"))
        let afterU2 = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "U2"))

        #expect(progress.update(with: afterU2) == .matchedLater)
        #expect(progress.completedTokenIndices == [1])
        #expect(progress.currentMoveTokenIndex == 0)
    }

    @Test func smartCubeCurrentMoveHighlightStaysOnPartialHalfTurn() throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: "L2 U"))
        let afterL = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "L"))

        #expect(progress.update(with: afterL) == .partial)
        #expect(progress.completedTokenIndices.isEmpty)
        #expect(progress.currentMoveTokenIndex == 0)
    }

    @Test func smartCubeCurrentMoveHighlightClearsAfterCompletion() throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: "R"))
        let afterR = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "R"))

        #expect(progress.update(with: afterR) == .completed)
        #expect(progress.currentMoveTokenIndex == nil)
    }

    @Test func smartCubeCurrentMoveHighlightIsSuppressedDuringDeviation() throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: "R U"))
        let afterF = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "F"))

        #expect(progress.update(with: afterF) == .deviated)
        #expect(progress.currentMoveTokenIndex == nil)
    }

    private func smartCubeMove(
        id: UUID = UUID(),
        timestamp: Date,
        cubeMilliseconds: Int? = nil,
        source: SmartCubeMoveTimestampSource = .hostReceipt
    ) -> SmartCubeMoveEvent {
        SmartCubeMoveEvent(
            id: id,
            move: "R",
            serial: nil,
            face: nil,
            direction: nil,
            localTimestamp: timestamp,
            cubeTimestampMilliseconds: cubeMilliseconds,
            timestampSource: source
        )
    }

    @Test func solveTimeAccuracyChangesPresentationWithoutChangingStoredPrecision() {
        let storedTime = 9.517

        #expect(SolveMetrics.formatTime(storedTime, decimals: 2) == "9.51")
        #expect(SolveMetrics.formatTime(storedTime, decimals: 3) == "9.517")
        #expect(storedTime == 9.517)
        #expect(SolveMetrics.formatTime(61.999, decimals: 2) == "1:01.99")
        #expect(SolveMetrics.formatTime(61.999, decimals: 3) == "1:01.999")
    }

    @Test func solveTimeAccuracyAppliesToAveragePresentation() {
        #expect(SolveMetrics.formatAverage(10.243, decimals: 2) == "10.24")
        #expect(SolveMetrics.formatAverage(10.243, decimals: 3) == "10.243")
    }

    @Test func numeralPreferencesDefaultAndInheritanceResolution() {
        let suiteName = "NumeralPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = NumeralPreferencesSnapshot.load(from: defaults)
        #expect(initial.app.system == .systemDefault)
        #expect(initial.resolved(for: .timer) == initial.app)
        #expect(initial.resolved(for: .statistics) == initial.app)

        defaults.set(NumeralSystem.bangla.rawValue, forKey: NumeralPreferenceKeys.appSystem)
        defaults.set(NumeralSystem.urdu.rawValue, forKey: NumeralPreferenceKeys.timerSystem)
        let overridden = NumeralPreferencesSnapshot.load(from: defaults)
        #expect(overridden.resolved(for: .app).system == .bangla)
        #expect(overridden.resolved(for: .timer).system == .urdu)
        #expect(overridden.resolved(for: .statistics).system == .bangla)
    }

    @Test func unicodeNumeralSystemsUseDistinctFoundationNumberingSystems() {
        let cases: [(NumeralSystem, String)] = [
            (.westernArabic, "1024.08"),
            (.easternArabic, "١٠٢٤٫٠٨"),
            (.urdu, "۱۰۲۴٫۰۸"),
            (.bangla, "১০২৪.০৮"),
            (.burmese, "၁၀၂၄.၀၈"),
            (.devanagari, "१०२४.०८"),
            (.gujarati, "૧૦૨૪.૦૮"),
            (.gurmukhi, "੧੦੨੪.੦੮"),
            (.kannada, "೧೦೨೪.೦೮"),
            (.khmer, "១០២៤.០៨"),
            (.malayalam, "൧൦൨൪.൦൮"),
            (.meitei, "꯱꯰꯲꯴.꯰꯸"),
            (.odia, "୧୦୨୪.୦୮"),
            (.olChiki, "᱑᱐᱒᱔.᱐᱘"),
            (.telugu, "౧౦౨౪.౦౮")
        ]

        for (system, expected) in cases {
            #expect(NumeralPresentation.presentNumericText(
                "1024.08",
                scope: .app,
                preferences: numeralSnapshot(appSystem: system)
            ) == expected)
        }
    }

    @Test func chineseNumeralDimensionsRemainIndependent() {
        let simplifiedDigits = numeralSnapshot(
            appSystem: .simplifiedChinese,
            appChinese: ChineseNumeralOptions(
                financial: false,
                numberFormat: .digits,
                decimalStyle: .period
            )
        )
        #expect(numeralText("0", preferences: simplifiedDigits) == "零")
        #expect(numeralText("9.28", preferences: simplifiedDigits) == "九.二八")
        #expect(numeralText("10.24", preferences: simplifiedDigits) == "一零.二四")
        #expect(SolveMetrics.formatTime(
            80.899,
            decimals: 2,
            numeralScope: .app,
            numeralPreferences: simplifiedDigits
        ) == "一分二零.八九")

        let simplifiedPositional = numeralSnapshot(
            appSystem: .simplifiedChinese,
            appChinese: ChineseNumeralOptions(
                financial: false,
                numberFormat: .chineseNumerals,
                decimalStyle: .chineseDecimal
            )
        )
        #expect(numeralText("10.24", preferences: simplifiedPositional) == "十点二四")
        #expect(numeralText("11.42", preferences: simplifiedPositional) == "十一点四二")
        #expect(numeralText("21.08", preferences: simplifiedPositional) == "二十一点零八")
        #expect(numeralText("128.05", preferences: simplifiedPositional) == "一百二十八点零五")
        #expect(SolveMetrics.formatTime(
            80.899,
            decimals: 2,
            numeralScope: .app,
            numeralPreferences: simplifiedPositional
        ) == "一分二十点八九")

        let traditionalFinancial = numeralSnapshot(
            appSystem: .traditionalChinese,
            appChinese: ChineseNumeralOptions(
                financial: true,
                numberFormat: .chineseNumerals,
                decimalStyle: .chineseDecimal
            )
        )
        #expect(numeralText("10.24", preferences: traditionalFinancial) == "壹拾點貳肆")
        #expect(numeralText("11.42", preferences: traditionalFinancial) == "壹拾壹點肆貳")
        #expect(numeralText("21.08", preferences: traditionalFinancial) == "貳拾壹點零捌")
        #expect(SolveMetrics.formatTime(
            80.899,
            decimals: 2,
            numeralScope: .app,
            numeralPreferences: traditionalFinancial
        ) == "壹分貳拾點捌玖")
    }

    @Test func appTimerAndStatisticsNumeralsCanResolveIndependently() {
        let snapshot = NumeralPreferencesSnapshot(
            app: NumeralScopePreference(system: .bangla, chineseOptions: ChineseNumeralOptions()),
            timerOverride: NumeralScopePreference(
                system: .traditionalChinese,
                chineseOptions: ChineseNumeralOptions(
                    financial: true,
                    numberFormat: .chineseNumerals,
                    decimalStyle: .chineseDecimal
                )
            ),
            statisticsOverride: NumeralScopePreference(
                system: .simplifiedChinese,
                chineseOptions: ChineseNumeralOptions(
                    financial: false,
                    numberFormat: .digits,
                    decimalStyle: .period
                )
            )
        )

        #expect(NumeralPresentation.presentNumericText("10.24", scope: .app, preferences: snapshot) == "১০.২৪")
        #expect(NumeralPresentation.presentNumericText("10.24", scope: .timer, preferences: snapshot) == "壹拾點貳肆")
        #expect(NumeralPresentation.presentNumericText("10.24", scope: .statistics, preferences: snapshot) == "一零.二四")
        #expect(SolveMetrics.formatTime(10.249, decimals: 2, numeralScope: .timer, numeralPreferences: snapshot) == "壹拾點貳肆")
    }

    @Test func numeralPresentationDoesNotMutateProtectedIdentifiers() {
        #expect(NumeralPresentation.verbatimIdentifier("2025SUNP01") == "2025SUNP01")
        #expect(NumeralPresentation.verbatimIdentifier("550E8400-E29B-41D4-A716-446655440000") == "550E8400-E29B-41D4-A716-446655440000")
    }

    private func numeralSnapshot(
        appSystem: NumeralSystem,
        appChinese: ChineseNumeralOptions = ChineseNumeralOptions()
    ) -> NumeralPreferencesSnapshot {
        NumeralPreferencesSnapshot(
            app: NumeralScopePreference(system: appSystem, chineseOptions: appChinese),
            timerOverride: nil,
            statisticsOverride: nil
        )
    }

    private func numeralText(
        _ value: String,
        preferences: NumeralPreferencesSnapshot
    ) -> String {
        NumeralPresentation.presentNumericText(value, scope: .app, preferences: preferences)
    }

    @Test func timerStatisticsSelectionMigratesLegacyAveragePreference() {
        #expect(TimerStatisticMetric.resolvedSelection(storedValue: "", legacyDisplayOption: .none).isEmpty)
        #expect(TimerStatisticMetric.resolvedSelection(storedValue: "", legacyDisplayOption: .ao5) == [.ao5])
        #expect(TimerStatisticMetric.resolvedSelection(storedValue: "", legacyDisplayOption: .ao12) == [.ao12])
        #expect(
            TimerStatisticMetric.resolvedSelection(storedValue: "", legacyDisplayOption: .ao5AndAo12)
                == [.ao5, .ao12]
        )

        let stored = TimerStatisticMetric.storedValue(for: [.solveCount, .best, .ao5])
        #expect(stored == "best,ao5,solveCount")
        #expect(
            TimerStatisticMetric.resolvedSelection(storedValue: stored, legacyDisplayOption: .none)
                == [.best, .ao5, .solveCount]
        )
        #expect(TimerStatisticMetric.storedValue(for: []) == "none")
        #expect(
            TimerStatisticMetric.resolvedSelection(storedValue: "none", legacyDisplayOption: .ao5AndAo12)
                .isEmpty
        )
    }

    @Test func classicStatisticsMigrationPreservesCanonicalFirstTwoWithoutChangingSharedSelection() {
        let cases: [([TimerStatisticMetric], [TimerStatisticMetric])] = [
            ([], []),
            ([.ao12], [.ao12]),
            ([.best, .ao5], [.best, .ao5]),
            ([.mean, .best, .ao5, .ao12], [.mean, .best])
        ]

        for (sharedSelection, expectedClassicSelection) in cases {
            let sharedStoredValue = TimerStatisticMetric.storedValue(for: sharedSelection)
            let migratedClassicStoredValue = TimerStatisticSelection.migratedClassicStoredValue(
                sharedStoredValue: sharedStoredValue,
                classicStoredValue: "",
                legacyDisplayOption: .none
            )

            #expect(
                TimerStatisticMetric.resolvedSelection(
                    storedValue: migratedClassicStoredValue,
                    legacyDisplayOption: .none
                ) == expectedClassicSelection
            )
            #expect(TimerStatisticMetric.storedValue(for: sharedSelection) == sharedStoredValue)
        }
    }

    @Test func classicAndNonClassicStatisticsSelectionsRemainIndependent() {
        let shared = TimerStatisticMetric.storedValue(for: [.mean, .ao5, .ao12, .ao100])
        let classic = TimerStatisticMetric.storedValue(for: [.best, .ao5])

        #expect(
            TimerStatisticSelection.resolved(
                arrangement: .classic,
                sharedStoredValue: shared,
                classicStoredValue: classic,
                legacyDisplayOption: .none
            ) == [.best, .ao5]
        )
        #expect(
            TimerStatisticSelection.resolved(
                arrangement: .cards,
                sharedStoredValue: shared,
                classicStoredValue: classic,
                legacyDisplayOption: .none
            ) == [.mean, .ao5, .ao12, .ao100]
        )
    }

    @Test func classicStatisticsSelectionCannotExceedTwoMetrics() {
        let selected: [TimerStatisticMetric] = [.ao5, .ao12]
        #expect(
            TimerStatisticSelection.updating(
                selected,
                metric: .ao100,
                isSelected: true,
                arrangement: .classic
            ) == selected
        )
        #expect(
            TimerStatisticSelection.updating(
                selected,
                metric: .ao5,
                isSelected: false,
                arrangement: .classic
            ) == [.ao12]
        )

        let corruptClassicValue = TimerStatisticMetric.storedValue(for: [.mean, .best, .ao5, .ao12])
        #expect(
            TimerStatisticSelection.resolved(
                arrangement: .classic,
                sharedStoredValue: "none",
                classicStoredValue: corruptClassicValue,
                legacyDisplayOption: .none
            ) == [.mean, .best]
        )
    }

    @Test func drawScrambleSizeUses275DefaultAndSanitizesOnlyInvalidValues() {
        #expect(TimerCustomizationDefaults.drawScrambleSize == 275)
        #expect(TimerCustomizationDefaults.resolvedDrawScrambleSize(.nan) == 275)
        #expect(TimerCustomizationDefaults.resolvedDrawScrambleSize(132) == 132)
        #expect(TimerCustomizationDefaults.resolvedDrawScrambleSize(95) == 96)
        #expect(TimerCustomizationDefaults.resolvedDrawScrambleSize(501) == 500)
    }

    @Test func timerSessionStatisticsMatchDataAverageForCompleteHistoricalSession() throws {
        let samples = (0..<27).map { index in
            SessionSolveSample(
                id: UUID(),
                date: Date(timeIntervalSince1970: TimeInterval(27 - index)),
                time: 8 + Double(index) * 0.17,
                resultRaw: SolveResult.solved.rawValue,
                scramble: "",
                comment: "",
                eventRawValue: index < 26 ? "legacy-event" : PuzzleEvent.threeByThree.rawValue
            )
        }

        let snapshot = DataTabComputation.buildSessionStatisticsSnapshot(from: samples)
        let ao5Entry = try #require(
            DataTabComputation.buildAverageEntriesSnapshot(from: samples, averageType: .ao5).first
        )
        let ao12Entry = try #require(
            DataTabComputation.buildAverageEntriesSnapshot(from: samples, averageType: .ao12).first
        )

        #expect(snapshot.solveCount == 27)
        #expect(snapshot.mean != nil)
        let snapshotAo5 = try #require(snapshot.currentAverage(for: .ao5))
        let snapshotAo12 = try #require(snapshot.currentAverage(for: .ao12))
        let entryAo5 = try #require(ao5Entry.value)
        let entryAo12 = try #require(ao12Entry.value)
        #expect(abs(snapshotAo5 - entryAo5) < 1e-12)
        #expect(abs(snapshotAo12 - entryAo12) < 1e-12)
        #expect(snapshot.currentAverage(for: .ao100) == nil)
    }

    @Test func timerSessionStatisticsExposeAo100WhenSessionHasEnoughHistory() throws {
        let samples = (0..<128).map { index in
            SessionSolveSample(
                id: UUID(),
                date: Date(timeIntervalSince1970: TimeInterval(128 - index)),
                time: 9 + Double(index % 19) * 0.11,
                resultRaw: SolveResult.solved.rawValue,
                scramble: "",
                comment: "",
                eventRawValue: PuzzleEvent.threeByThree.rawValue
            )
        }

        let snapshot = DataTabComputation.buildSessionStatisticsSnapshot(from: samples)
        let ao100Entry = try #require(
            DataTabComputation.buildAverageEntriesSnapshot(from: samples, averageType: .ao100).first
        )

        #expect(snapshot.solveCount == 128)
        #expect(snapshot.currentAverage(for: .ao100) == ao100Entry.value)
    }

    @Test func timerArrangementOwnsDiagramPlacementWhereRequired() {
        #expect(TimerArrangement.classic.resolvedDiagramPlacement(from: .bottomLeft, splitOrder: .statisticsLeading) == .bottomLeft)
        #expect(TimerArrangement.classic.resolvedDiagramPlacement(from: .inline, splitOrder: .statisticsLeading) == nil)
        #expect(
            TimerArrangement.split.resolvedDiagramPlacement(from: .bottomLeft, splitOrder: .statisticsLeading)
                == .bottomRight
        )
        #expect(
            TimerArrangement.split.resolvedDiagramPlacement(from: .bottomRight, splitOrder: .diagramLeading)
                == .bottomLeft
        )
        #expect(TimerArrangement.cards.resolvedDiagramPlacement(from: .bottomCenter, splitOrder: .statisticsLeading) == nil)
    }

    @Test func legacyMinimalArrangementMigratesOnceWithoutOverwritingLaterChoices() {
        let migration = TimerArrangementMigration.resolve(
            storedArrangement: "minimal",
            minimalMode: false,
            completed: false
        )
        #expect(migration.arrangement == .classic)
        #expect(migration.minimalMode)
        #expect(migration.completed)

        let laterChoice = TimerArrangementMigration.resolve(
            storedArrangement: TimerArrangement.cards.rawValue,
            minimalMode: false,
            completed: true
        )
        #expect(laterChoice.arrangement == .cards)
        #expect(!laterChoice.minimalMode)
    }

    @Test func minimalModeSuppressesPresentationWithoutChangingArrangement() {
        let presentation = TimerEffectivePresentation(arrangement: .split, minimalMode: true)
        #expect(presentation.arrangement == .split)
        #expect(!presentation.showsStatistics)
        #expect(!presentation.showsScrambleDiagram)
        #expect(presentation.resolvedDiagramPlacement(from: .bottomLeft, splitOrder: .statisticsLeading) == nil)
    }

    @Test func classicAndCardsStatisticsSelectionsRemainIndependentAndBounded() {
        let classic = TimerStatisticMetric.storedValue(for: [.best, .ao5])
        let cards = TimerStatisticMetric.storedValue(for: [.mean, .mo3, .ao12, .solveCount])
        #expect(TimerStatisticSelection.resolved(
            arrangement: .classic,
            sharedStoredValue: "none",
            classicStoredValue: classic,
            cardsStoredValue: cards,
            legacyDisplayOption: .none
        ) == [.best, .ao5])
        #expect(TimerStatisticSelection.resolved(
            arrangement: .cards,
            sharedStoredValue: "none",
            classicStoredValue: classic,
            cardsStoredValue: cards,
            legacyDisplayOption: .none
        ) == [.mean, .mo3, .ao12, .solveCount])

        let unchanged = TimerStatisticSelection.updating(
            [.mean, .best, .ao5, .ao12],
            metric: .ao100,
            isSelected: true,
            arrangement: .cards
        )
        #expect(unchanged == [.mean, .best, .ao5, .ao12])
    }

    @Test func cardsLayoutsResolveForEverySupportedSelectionCount() {
        #expect(TimerCardsStatisticsLayout.resolved(count: 1, two: .horizontal, three: .bottomEmphasis) == .full)
        #expect(TimerCardsStatisticsLayout.resolved(count: 2, two: .vertical, three: .bottomEmphasis) == .vertical)
        #expect(TimerCardsStatisticsLayout.resolved(count: 2, two: .horizontal, three: .topEmphasis) == .horizontal)
        #expect(TimerCardsStatisticsLayout.resolved(count: 3, two: .vertical, three: .topEmphasis) == .topEmphasis)
        #expect(TimerCardsStatisticsLayout.resolved(count: 3, two: .vertical, three: .bottomEmphasis) == .bottomEmphasis)
        #expect(TimerCardsStatisticsLayout.resolved(count: 4, two: .vertical, three: .topEmphasis) == .grid)
    }

    @Test func cardsPositionAssignmentsStayUniqueAndSwapOccupiedSlots() {
        let selected: [TimerStatisticMetric] = [.mean, .ao5, .ao12]
        let store = TimerCardsPositionStore()
            .normalizing(layout: .topEmphasis, selectedMetrics: selected)
        #expect(store.resolvedMetrics(for: .topEmphasis, selectedMetrics: selected) == selected)

        let swapped = store.assigning(
            metric: .ao12,
            to: 0,
            layout: .topEmphasis,
            selectedMetrics: selected
        )
        #expect(swapped.resolvedMetrics(for: .topEmphasis, selectedMetrics: selected) == [.ao12, .ao5, .mean])
        #expect(Set(swapped.resolvedMetrics(for: .topEmphasis, selectedMetrics: selected)).count == 3)
    }

    @Test func cardsPositionAssignmentsRecoverAfterSelectionChanges() {
        var store = TimerCardsPositionStore()
        store.assignments[TimerCardsStatisticsLayout.grid.rawValue] = ["ao100", "mean", "ao5", "ao12"]
        let changed: [TimerStatisticMetric] = [.best, .ao5, .ao12, .ao100]
        let resolved = store.resolvedMetrics(for: .grid, selectedMetrics: changed)
        #expect(resolved == [.ao100, .ao5, .ao12, .best])
        #expect(Set(resolved) == Set(changed))
    }

    @Test func legacySplitArrangementsMigrateWithoutLosingOrder() {
        #expect(TimerArrangement.resolved(storedRawValue: "splitStatisticsLeading") == .split)
        #expect(TimerArrangement.resolved(storedRawValue: "splitDiagramLeading") == .split)
        #expect(
            TimerSplitOrder.resolved(
                storedRawValue: TimerSplitOrder.statisticsLeading.rawValue,
                legacyArrangementRawValue: "splitDiagramLeading"
            ) == .diagramLeading
        )
    }

    @Test func timerScramblePositionUsesNormalizedAvailableGeometry() {
        #expect(TimerArrangementLayout.normalizedScramblePosition(-1) == 0)
        #expect(TimerArrangementLayout.normalizedScramblePosition(2) == 1)
        #expect(TimerArrangementLayout.normalizedScramblePosition(.nan) == 0)
        #expect(
            TimerArrangementLayout.scrambleTop(
                availableHeight: 200,
                contentHeight: 80,
                normalizedPosition: 0.5
            ) == 60
        )
    }

    @Test func manualEntryGroupOnlyMovesEnoughToClearDiagram() {
        #expect(
            TimerArrangementLayout.collisionAvoidingGroupTop(
                containerHeight: 800,
                groupHeight: 180,
                obstructionMinY: 700,
                minimumSpacing: 12
            ) == 310
        )
        #expect(
            TimerArrangementLayout.collisionAvoidingGroupTop(
                containerHeight: 800,
                groupHeight: 180,
                obstructionMinY: 440,
                minimumSpacing: 12
            ) == 248
        )
        #expect(
            TimerArrangementLayout.collisionAvoidingGroupTop(
                containerHeight: 260,
                groupHeight: 220,
                obstructionMinY: 120,
                minimumSpacing: 12
            ) == 0
        )
    }

    @Test func timerGeometryRejectsTransientInvalidDimensions() {
        #expect(
            TimerArrangementLayout.contentWidth(
                containerWidth: 0,
                horizontalInsets: 48,
                maximum: 420
            ) == 0
        )
        #expect(
            TimerArrangementLayout.contentWidth(
                containerWidth: .nan,
                horizontalInsets: 48,
                maximum: 420
            ) == 0
        )

        let geometry = TimerArrangementLayout.geometry(
            containerSize: CGSize(width: -10, height: CGFloat.infinity),
            timerVerticalOffset: 18,
            classicStatisticsHeight: 120,
            classicStatisticsOffset: 80,
            diagramPreferredWidth: 132,
            diagramAspectRatio: 0
        )
        let frames = [
            geometry.classicStatisticsFrame,
            geometry.splitLeadingFrame,
            geometry.splitTrailingFrame,
            geometry.leadingCardFrame,
            geometry.trailingCardFrame
        ]
        #expect(frames.allSatisfy { frame in
            frame.origin.x.isFinite
                && frame.origin.y.isFinite
                && frame.width.isFinite
                && frame.height.isFinite
                && frame.width >= 0
                && frame.height >= 0
        })
        #expect(geometry.leadingCardFrame.size == geometry.trailingCardFrame.size)
    }

    #if DEBUG && os(iOS)
    @Test @MainActor func marketingTimerHeroUsesIsolatedDeterministicData() throws {
        let environment = MarketingPreviewEnvironment(preset: .timerThreeByThreeHero)
        let context = environment.persistenceController.container.viewContext
        let solves = try context.fetchSolvesSortedByDateDescending()
        let heroSolves = Array(solves.prefix(12))

        #expect(solves.count == 28)
        #expect(environment.defaults.string(forKey: "timerAccuracy") == SolveTimeAccuracy.hundredths.rawValue)
        #expect(environment.defaults.string(forKey: "timerTextFontDesign") == TimerFontDesignOption.serif.rawValue)
        #expect(environment.defaults.string(forKey: "drawScramblePlacement") == DrawScramblePlacement.bottomRight.rawValue)
        #expect(abs((SolveMetrics.trimmedAverage(from: heroSolves, count: 5) ?? 0) - 10.24) < 0.000_001)
        #expect(abs((SolveMetrics.trimmedAverage(from: heroSolves, count: 12) ?? 0) - 10.71) < 0.000_001)
        #expect(Set(solves.map { Calendar.current.startOfDay(for: $0.date) }).count == 17)
        #expect(MarketingPreviewPreset.timerThreeByThreeHero.timerConfiguration.scramble == "R U2 F' L2 D B2 R2 U' F2 D2 L' B U R' F D' L2 U2 B' R2")
    }
    #endif

    @Test @MainActor func timerFontRegistryContainsEverySupportedDesign() {
        let expected: Set<TimerFontDesignOption> = [
            .default, .rounded, .expanded, .condensed, .compressed, .serif, .monospaced,
            .academyEngraved, .georgia, .futura, .menlo, .courierNew, .americanTypewriter,
            .skia, .copperplate, .herculanum, .chakraPetch, .impact, .chalkboardSE,
            .chalkduster, .noteworthy, .snellRoundhand, .comicSansMS, .papyrus,
            .dbLCDTempBlack
        ]

        #expect(Set(TimerFontDesignOption.allCases) == expected)
    }

    @Test @MainActor func timerFontStylesHaveUniqueResolvedSelections() {
        for design in TimerFontDesignOption.availableOptions {
            let styles = design.availableStyles(preferredLegacyWeight: .regular)
            #expect(!styles.isEmpty)
            #expect(Set(styles.map(\.id)).count == styles.count)
            #expect(Set(styles.map(\.resolvedFaceSignature)).count == styles.count)
        }
    }

    @Test @MainActor func appleDownloadableTimerFontsRemainSelectable() {
        let downloadableDesigns: Set<TimerFontDesignOption> = [
            .herculanum, .chakraPetch, .comicSansMS, .skia
        ]
        #expect(Set(TimerFontDesignOption.availableOptions).isSuperset(of: downloadableDesigns))
    }

#if canImport(UIKit)
    @Test @MainActor func selectableInlineControlsReloadSafelyAcrossDocumentChanges() {
        func document(controlIDs: [String]) -> NSAttributedString {
            let result = NSMutableAttributedString(string: "Selectable ", attributes: [
                .font: UIFont.systemFont(ofSize: 16),
                .foregroundColor: UIColor.label
            ])
            for id in controlIDs {
                result.append(NSAttributedString(string: "\u{FFFC}", attributes: [
                    .font: UIFont.systemFont(ofSize: 18),
                    .foregroundColor: UIColor.clear,
                    .selectableInlineControlID: id
                ]))
                result.append(NSAttributedString(string: " text ", attributes: [
                    .font: UIFont.systemFont(ofSize: 16),
                    .foregroundColor: UIColor.label
                ]))
            }
            return result
        }

        func control(_ id: String) -> SelectableInlineControl {
            SelectableInlineControl(
                id: id,
                content: .systemImage("circle.fill", pointSize: 18, weight: .regular),
                accessibilityLabel: id,
                minimumHitSize: CGSize(width: 30, height: 32)
            )
        }

        let textView = SelectableAttributedContent.IntrinsicTextView.makeTextKit1View()
        textView.frame = CGRect(x: 0, y: 0, width: 320, height: 160)
        textView.textContainer.size = CGSize(
            width: 320,
            height: CGFloat.greatestFiniteMagnitude
        )

        let initialControls = [control("a"), control("b")]
        textView.attributedText = document(controlIDs: ["a", "b"])
        textView.reloadInlineControls(initialControls)
        textView.layoutIfNeeded()
        #expect(textView.installedInlineControlIDs == ["a", "b"])
        #expect(textView.inlineControlInstallationGeneration == 1)

        for _ in 0..<20 {
            textView.reloadInlineControls(initialControls)
            textView.layoutIfNeeded()
        }
        #expect(textView.inlineControlInstallationGeneration == 1)

        textView.attributedText = document(controlIDs: ["b", "a"])
        textView.reloadInlineControls(initialControls)
        textView.layoutIfNeeded()
        #expect(textView.inlineControlInstallationGeneration == 1)
        #expect(textView.isInlineControlHidden(id: "a") == false)
        #expect(textView.isInlineControlHidden(id: "b") == false)

        let changedControls = [control("b"), control("c"), control("missing-range")]
        textView.attributedText = document(controlIDs: ["b", "c"])
        textView.reloadInlineControls(changedControls)
        textView.layoutIfNeeded()
        #expect(textView.installedInlineControlIDs == ["b", "c", "missing-range"])
        #expect(textView.isInlineControlHidden(id: "missing-range") == true)

        textView.reloadInlineControls([control("c")])
        textView.attributedText = document(controlIDs: ["c"])
        textView.layoutIfNeeded()
        #expect(textView.installedInlineControlIDs == ["c"])
        #expect(textView.isInlineControlHidden(id: "c") == false)

        textView.attributedText = NSAttributedString(string: "Plain selectable text")
        textView.reloadInlineControls([])
        textView.layoutIfNeeded()
        #expect(textView.installedInlineControlIDs.isEmpty)
    }

    @Test @MainActor func skiaAppearsWheneverUIKitCanResolveIt() {
        let runtimeHasSkia = UIFont(name: "Skia", size: 16) != nil
            || UIFont(name: "Skia-Regular", size: 16) != nil

        if runtimeHasSkia {
            #expect(TimerFontDesignOption.skia.isAvailable)
        }
    }

    @Test @MainActor func solveScrambleCompositeRendererDrawsNotationForEveryBackground() throws {
        let diagram = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 96)).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 96))
        }
        let design = TimerFontDesignOption.default
        let style = design.resolvedStyle(
            rawValue: TimerFontWeightOption.medium.rawValue,
            preferredLegacyWeight: .medium
        )

        for background in SolveShareBackground.allCases {
            let rendered = try ScrambleCompositeImageRenderer.render(
                diagram: diagram,
                scramble: "R U R' U' F2",
                font: design.uiFont(size: 22, style: style),
                background: background
            )
            let pixels = try rgbaPixels(from: rendered)

            if background == .dark {
                #expect(pixels.bytes[3] == 255)
                #expect(pixels.containsOpaqueLightPixel(inBottomFraction: 1.0))
            } else {
                #expect(pixels.bytes[3] == 255)
                #expect(pixels.containsOpaqueDarkPixel(inBottomFraction: 1.0))
            }
        }
    }

    @Test @MainActor func timerScrambleCompositeUsesVisibleAppearanceAndIncludesNotation() throws {
        let diagram = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 96)).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 96))
        }
        var background = AppearanceConfiguration.defaultBackground
        background.style = .color
        background.lightColor = StoredColorData(r: 0, g: 0, b: 0)
        var text = AppearanceConfiguration.defaultScrambleText
        text.style = .color
        text.lightColor = StoredColorData(r: 1, g: 1, b: 1)
        let design = TimerFontDesignOption.serif
        let style = design.resolvedStyle(
            rawValue: TimerFontWeightOption.medium.rawValue,
            preferredLegacyWeight: .medium
        )

        let rendered = try TimerScrambleCompositeRenderer.render(
            diagram: diagram,
            scramble: "R U R' U' F2",
            configuration: TimerScrambleExportConfiguration(
                backgroundAppearance: background,
                backgroundImage: nil,
                textAppearance: text,
                fontDesign: design,
                fontStyle: style,
                fontSize: 24,
                colorScheme: .light
            )
        )
        let pixels = try rgbaPixels(from: rendered)

        #expect(pixels.bytes[0] < 10)
        #expect(pixels.bytes[1] < 10)
        #expect(pixels.bytes[2] < 10)
        #expect(pixels.bytes[3] == 255)
        #expect(pixels.containsOpaqueLightPixel(inBottomFraction: 0.35))
    }

    @Test @MainActor func timerScrambleExportChoosesLargestComfortableNotationSize() {
        let design = TimerFontDesignOption.default
        let style = design.resolvedStyle(
            rawValue: TimerFontWeightOption.medium.rawValue,
            preferredLegacyWeight: .medium
        )
        let configuration = TimerScrambleExportConfiguration(
            backgroundAppearance: .defaultBackground,
            backgroundImage: nil,
            textAppearance: .defaultScrambleText,
            fontDesign: design,
            fontStyle: style,
            fontSize: 14,
            colorScheme: .light
        )
        let shortSize = TimerScrambleExportLayout.notationFontSize(
            for: "R U R' U' F2",
            configuration: configuration
        )
        let longSize = TimerScrambleExportLayout.notationFontSize(
            for: Array(repeating: "Rw U2 Fw' L2 D B2", count: 12).joined(separator: " "),
            configuration: configuration
        )

        #expect(shortSize == TimerScrambleExportLayout.maximumNotationFontSize)
        #expect(longSize < shortSize)
        #expect(longSize >= TimerScrambleExportLayout.minimumNotationFontSize)
    }

    @Test func competitionContentImageSourceResolverNormalizesRemoteURLs() throws {
        let protocolRelative = try #require(
            CompetitionContentImageSourceResolver.remoteURL(
                from: "  //assets.example.com/banner image.png?one=1&amp;two=2  "
            )
        )
        #expect(
            protocolRelative.absoluteString
                == "https://assets.example.com/banner%20image.png?one=1&two=2"
        )

        let cubingRelative = try #require(
            CompetitionContentImageSourceResolver.remoteURL(from: "/uploads/banner.png")
        )
        #expect(cubingRelative.absoluteString == "https://cubing.com/uploads/banner.png")

        let wcaRelative = try #require(
            CompetitionContentImageSourceResolver.remoteURL(
                from: "/rails/active_storage/blobs/banner.png",
                baseURL: URL(string: "https://www.worldcubeassociation.org")
            )
        )
        #expect(
            wcaRelative.absoluteString
                == "https://www.worldcubeassociation.org/rails/active_storage/blobs/banner.png"
        )
    }

    @Test func wcaGeneralInfoKeepsRichBlocksAndImagesOutsideSelectableDefinitionDocument() throws {
        let html = """
        <dl class="dl-horizontal">
          <dt>Information</dt>
          <dd>
            <p>Intro paragraph</p>
            <p><img src="https://images.example.com/banner.png" alt="Banner"><br>
              <img src="/rails/active_storage/blobs/map.png" alt="Map"></p>
            <h3>Important information</h3>
            <p>First line<br><strong>Bold</strong> and <em>italic</em>
              <a href="https://example.com/details">link</a>.</p>
            <ol><li>First item</li><li><strong>Second item</strong></li></ol>
            <hr>
            <p>Final paragraph</p>
          </dd>
        </dl>
        """

        let root = try #require(CompetitionRichHTMLElement.parse(html).first)
        #expect(!root.isSelectableDocumentElement)
        guard case .definitionList(let rows) = root.kind else {
            Issue.record("WCA General Info should retain its definition-list structure")
            return
        }

        let information = try #require(rows.first)
        #expect(information.prefersExpandedLayout)
        let nested = CompetitionRichHTMLElement.parse(information.valueHTML)
        #expect(nested.count == 8)

        guard case .paragraph(let introText) = nested[0].kind else {
            Issue.record("The leading WCA paragraph was discarded or reordered")
            return
        }
        #expect(introText == "Intro paragraph")

        guard case .image(let imageSource) = nested[1].kind else {
            Issue.record("The first WCA image was discarded or reordered")
            return
        }
        #expect(imageSource == "https://images.example.com/banner.png")

        guard case .image(let secondImageSource) = nested[2].kind else {
            Issue.record("The second WCA image was discarded or reordered")
            return
        }
        #expect(secondImageSource == "/rails/active_storage/blobs/map.png")

        guard case .heading(let title, let level) = nested[3].kind else {
            Issue.record("The WCA heading lost its semantic block")
            return
        }
        #expect(title == "Important information")
        #expect(level == 3)

        guard case .linkedText(let runs) = nested[4].kind else {
            Issue.record("The formatted WCA paragraph was flattened")
            return
        }
        #expect(runs.contains { $0.text.contains("\n") })
        #expect(runs.contains { $0.text == "Bold" && $0.isBold })
        #expect(runs.contains { $0.text == "italic" && $0.isItalic })
        #expect(runs.contains { $0.text == "link" && $0.url?.absoluteString == "https://example.com/details" })

        guard case .list(let items) = nested[5].kind else {
            Issue.record("The ordered list was flattened")
            return
        }
        #expect(items.map(\.marker) == ["1.", "2."])
        #expect(items[1].runs.contains { $0.text == "Second item" && $0.isBold })

        guard case .separator = nested[6].kind else {
            Issue.record("The WCA separator was discarded")
            return
        }
        guard case .paragraph(let finalText) = nested[7].kind else {
            Issue.record("The final paragraph was discarded")
            return
        }
        #expect(finalText == "Final paragraph")
    }

    @Test func shortWCAInfoWithMultipleParagraphsKeepsParagraphBoundaries() throws {
        let html = """
        <dl class="dl-horizontal">
          <dt>Information</dt>
          <dd><p>First paragraph.</p><p>Second paragraph.</p></dd>
        </dl>
        """

        let root = try #require(CompetitionRichHTMLElement.parse(html).first)
        guard case .definitionList(let rows) = root.kind else {
            Issue.record("WCA information should retain its definition-list structure")
            return
        }

        let information = try #require(rows.first)
        #expect(information.prefersExpandedLayout)
        let nested = CompetitionRichHTMLElement.parse(information.valueHTML)
        #expect(nested.count == 2)
        guard case .paragraph(let first) = nested[0].kind,
              case .paragraph(let second) = nested[1].kind else {
            Issue.record("Adjacent WCA paragraphs were flattened")
            return
        }
        #expect(first == "First paragraph.")
        #expect(second == "Second paragraph.")
    }

    @Test func simpleWCAInfoDefinitionRowsRemainOneSelectableTextKitDocument() throws {
        let html = """
        <dl class="dl-horizontal">
          <dt>Date</dt><dd>August 17, 2026</dd>
          <dt>Address</dt><dd><a href="https://maps.example.com">Venue</a></dd>
        </dl>
        """
        let element = try #require(CompetitionRichHTMLElement.parse(html).first)
        #expect(element.isSelectableDocumentElement)
    }

    @Test func wcaInfoUsesVerticalFieldsOnlyForOfficialStackedSemantics() throws {
        let html = """
        <dl class="dl-horizontal">
          <dt>Date</dt><dd>August 17, 2026</dd>
          <dt>City</dt><dd>Seoul</dd>
        </dl>
        <dl><dt>Events</dt><dd class="competition-events-list">[[event-icon:333]]</dd></dl>
        <dl><dt>Main Event</dt><dd class="competition-events-list">[[event-icon:333]]</dd></dl>
        <dl><dt>Competitor Limit</dt><dd>120</dd></dl>
        <dl><dt>Number of times bookmarked</dt><dd>42</dd></dl>
        """

        let rows = CompetitionRichHTMLElement.parse(html).flatMap { element -> [CompetitionRichHTMLDefinitionRow] in
            guard case .definitionList(let rows) = element.kind else { return [] }
            return rows
        }
        let rowsByTerm = Dictionary(uniqueKeysWithValues: rows.map { ($0.term, $0) })

        #expect(rowsByTerm["Date"]?.prefersVerticalFieldLayout == false)
        #expect(rowsByTerm["City"]?.prefersVerticalFieldLayout == false)
        #expect(rowsByTerm["Events"]?.prefersVerticalFieldLayout == true)
        #expect(rowsByTerm["Main Event"]?.prefersVerticalFieldLayout == true)
        #expect(rowsByTerm["Competitor Limit"]?.prefersVerticalFieldLayout == true)
        #expect(rowsByTerm["Number of times bookmarked"]?.prefersVerticalFieldLayout == true)
        #expect(rowsByTerm["Events"]?.isTermSecondary == false)
        #expect(rowsByTerm["Main Event"]?.isTermSecondary == false)
        #expect(rowsByTerm["Competitor Limit"]?.isTermSecondary == false)
        #expect(rowsByTerm["Number of times bookmarked"]?.isTermSecondary == false)
    }

    @Test func wcaRichTextAddsSpacingOnlyForASingleSemanticBreak() {
        let singleBreak = "First line\nSecond line" as NSString
        let singleRange = NSRange(location: 0, length: singleBreak.length)
        let firstSingleParagraph = singleBreak.paragraphRange(
            for: NSRange(location: 0, length: 0)
        )
        #expect(
            CompetitionRichTextParagraphLayout.addsSpacingAfterParagraph(
                in: singleBreak,
                paragraphRange: firstSingleParagraph,
                contentRange: singleRange
            )
        )

        let blankLine = "First paragraph\n\nSecond paragraph" as NSString
        let blankLineRange = NSRange(location: 0, length: blankLine.length)
        let firstBlankLineParagraph = blankLine.paragraphRange(
            for: NSRange(location: 0, length: 0)
        )
        #expect(
            !CompetitionRichTextParagraphLayout.addsSpacingAfterParagraph(
                in: blankLine,
                paragraphRange: firstBlankLineParagraph,
                contentRange: blankLineRange
            )
        )
    }

    @Test func wcaScheduleUsesOfficialRoomMetadataAndIgnoresChildGroups() throws {
        let html = #"""
        <script data-component-name="Schedule" type="application/json">
        {
          "wcifSchedule": {
            "venues": [{
              "id": 1,
              "name": "Convention Center",
              "timezone": "Asia/Seoul",
              "rooms": [{
                "id": 1,
                "name": "Main Venue",
                "color": "#673b6d",
                "activities": [{
                  "id": 100,
                  "name": "3x3x3 Cube, Round 1",
                  "activityCode": "333-r1",
                  "startTime": "2026-08-17T01:00:00Z",
                  "endTime": "2026-08-17T02:00:00Z",
                  "childActivities": [{
                    "id": 101,
                    "name": "3x3x3 Cube, Round 1, Group 1",
                    "activityCode": "333-r1-g1",
                    "startTime": "2026-08-17T01:00:00Z",
                    "endTime": "2026-08-17T01:30:00Z",
                    "childActivities": []
                  }]
                }]
              }, {
                "id": 2,
                "name": "Red Stage",
                "color": "#cd2e3a",
                "activities": [{
                  "id": 200,
                  "name": "4x4x4 Cube, Round 1",
                  "activityCode": "444-r1",
                  "startTime": "2026-08-17T02:00:00Z",
                  "endTime": "2026-08-17T03:00:00Z",
                  "childActivities": []
                }]
              }, {
                "id": 5,
                "name": "Blue Stage",
                "color": "#0047a0",
                "activities": [{
                  "id": 300,
                  "name": "5x5x5 Cube, Round 1",
                  "activityCode": "555-r1",
                  "startTime": "2026-08-17T03:00:00Z",
                  "endTime": "2026-08-17T04:00:00Z",
                  "childActivities": []
                }]
              }]
            }]
          }
        }
        </script>
        """#

        let days = CompetitionService.decodeWCAScheduleDays(from: html, languageCode: "en")
        let day = try #require(days.first)
        let entry = try #require(day.entries.first)
        let rooms = CompetitionScheduleRoomFilter.rooms(in: days)

        #expect(days.count == 1)
        #expect(day.entries.count == 3)
        #expect(entry.roomID == "1")
        #expect(entry.venueName == "Main Venue")
        #expect(entry.roomColorHex == "#673b6d")
        #expect(entry.group == nil)
        #expect(day.venues.map(\.title) == ["Main Venue", "Red Stage", "Blue Stage"])
        #expect(rooms.map(\.id) == ["1", "2", "5"])
        #expect(rooms.map(\.name) == ["Main Venue", "Red Stage", "Blue Stage"])

        let withoutRedStage = CompetitionScheduleRoomFilter.filteredDays(
            days,
            selectedRoomIDs: ["1", "5"]
        )
        let filteredDay = try #require(withoutRedStage.first)
        #expect(filteredDay.entries.map(\.roomID) == ["1", "5"])
        #expect(filteredDay.venues.map(\.title) == ["Main Venue", "Blue Stage"])
    }

    @Test func wcaScheduleLegendUsesOfficialTimeLimitInformationBlock() {
        let html = """
        <div class="time-limit-information">
          <h4>Time limit</h4><p>Time limit explanation.</p>
          <h4>Cutoff</h4><p>Cutoff explanation.</p>
          <h4>Format</h4><p>Format explanation.</p>
          <h4>Advancement Condition</h4><p>Advancement explanation.</p>
        </div>
        """

        let legend = CompetitionService.extractWCAScheduleLegendHTML(from: html)
        #expect(legend.contains("Time limit"))
        #expect(legend.contains("Cutoff"))
        #expect(legend.contains("Format"))
        #expect(legend.contains("Advancement Condition"))
        #expect(CompetitionService.extractWCAScheduleLegendHTML(from: "<p>No legend</p>").isEmpty)
    }

#endif

    @Test func cubingChinaSourceRecognizesCurrentDomainsAndSlug() {
        let currentDomainCompetition = competitionSummary(
            website: "https://cubingchina.com/competition/Maoming-Open-2026/registration"
        )
        let legacyDomainCompetition = competitionSummary(
            website: "https://www.cubing.com/competition/Guangzhou-Special-2026"
        )

        #expect(currentDomainCompetition.usesCubingChinaDetailSource)
        #expect(currentDomainCompetition.cubingChinaCompetitionSlug == "Maoming-Open-2026")
        #expect(legacyDomainCompetition.usesCubingChinaDetailSource)
        #expect(legacyDomainCompetition.cubingChinaCompetitionSlug == "Guangzhou-Special-2026")
    }

    @Test func chineseWCACompetitionDoesNotAutomaticallyUseCubingChina() {
        let competition = competitionSummary(
            website: "https://www.worldcubeassociation.org/competitions/ExampleOpen2026"
        )

        #expect(!competition.usesCubingChinaDetailSource)
        #expect(competition.cubingChinaCompetitionSlug == nil)
    }

    @Test func missingLocalizationKeyNeverLeaksToTheUI() {
        let result = appLocalizedString(
            "competition.detail.unavailable",
            languageCode: "en"
        )

        #expect(result != "competition.detail.unavailable")
        #expect(result.localizedCaseInsensitiveContains("unavailable"))
    }

    @Test func eventPresentationUsesFullNamesAndStableCapitalization() {
        #expect(
            CompetitionEventPresentation.localizedFullName(
                for: "333oh",
                languageCode: "en"
            ) == "3x3x3 One-Handed"
        )
        #expect(
            CompetitionEventPresentation.normalizedName(
                for: "clock",
                fallback: "CLOCK",
                languageCode: "en"
            ) == "Clock"
        )
        #expect(
            CompetitionEventPresentation.normalizedName(
                for: "skewb",
                fallback: "SKEWB",
                languageCode: "en"
            ) == "Skewb"
        )
    }

    @Test func wcaProfileParserPreservesCollectionsPodiumsAndResultSemantics() throws {
        let html = #"""
        <div class="details"><table><tbody>
          <tr><td>Australia</td><td>2009TEST01</td><td>Male</td><td>42</td><td>900</td></tr>
        </tbody></table></div>
        <!-- Handle multiple sub ids. -->
        <h4>(Previously Test Person - India, Earlier Test Person - Canada)</h4>
        <div class="personal-records"><table><tbody>
          <tr><td data-event="333">3x3x3 Cube</td><td>1</td><td>2</td><td>3</td><td>5.00</td><td>6.00</td><td>4</td><td>3</td><td>2</td><td><i title="Ranks can differ after changing regions" class="icon question circle"></i></td></tr>
        </tbody></table></div>
        <div class="col-md-6 medal-collection">
          <h3>Medal Collection</h3><table><thead><tr><th>Gold</th><th>Silver</th><th>Bronze</th></tr></thead>
          <tbody><tr><td><a data-place="gold">7</a></td><td><a data-place="silver">3</a></td><td><a data-place="bronze">1</a></td></tr></tbody></table>
        </div>
        <div class="col-md-6 record-collection">
          <h3>Record Collection</h3><table><thead><tr><th>WR</th><th>CR</th><th>NR</th></tr></thead>
          <tbody><tr><td>2</td><td></td><td>5</td></tr></tbody></table>
        </div>
        <table><tbody class="event-333">
          <tr><td colspan="12" class="event"><i></i>3x3x3 Cube</td></tr>
          <tr class="result gold-place">
            <td class="competition"><a href="/competitions/TestOpen2026">Test Open 2026</a></td>
            <td class="round">Final</td><td class="place">1</td>
            <td class="single pb">5.00</td><td class="regional-single-record"></td>
            <td class="average wr">6.00</td><td class="regional-average-record">WR</td>
            <td class="solve 0">5.00</td>
          </tr>
        </tbody></table>
        """#

        let page = try WCAResultsService.parsePersonResultsHTML(html, requestedLanguageCode: "en")
        #expect(page.medalCollection?.goldCount == 7)
        #expect(page.medalCollection?.silverCount == 3)
        #expect(page.medalCollection?.bronzeCount == 1)
        #expect(page.recordCollection?.worldCount == 2)
        #expect(page.recordCollection?.continentCount == nil)
        #expect(page.recordCollection?.nationalCount == 5)
        #expect(page.previousIdentityText == "Previously Test Person - India, Earlier Test Person - Canada")
        #expect(page.personalRecords.first?.oddRankReason == "Ranks can differ after changing regions")

        let result = try #require(page.resultsSections.first?.results.first)
        #expect(result.podiumPlace == .gold)
        #expect(result.singleEmphasis == .personalBest)
        #expect(result.averageEmphasis == .worldRecord)
    }

    @Test func wcaLiveProbeRequiresARealCompetitionDetail() throws {
        let valid = try #require(
            #"{"data":{"competition":{"id":"11089","name":"Egypt National 2026","wcaId":"EgyptNational2026"}}}"#
                .data(using: .utf8)
        )
        let missing = try #require(
            #"{"data":{"competition":null},"errors":[{"message":"detail not found"}]}"#
                .data(using: .utf8)
        )
        let malformed = try #require(#"{"data":null}"#.data(using: .utf8))

        #expect(CompetitionService.wcaLiveProbeContainsCompetition(valid))
        #expect(
            CompetitionService.wcaLiveProbeMatchesCompetition(
                valid,
                wcaCompetitionID: "EgyptNational2026"
            )
        )
        #expect(
            !CompetitionService.wcaLiveProbeMatchesCompetition(
                valid,
                wcaCompetitionID: "DifferentCompetition2026"
            )
        )
        #expect(!CompetitionService.wcaLiveProbeContainsCompetition(missing))
        #expect(!CompetitionService.wcaLiveProbeContainsCompetition(malformed))
    }

    @Test func wcaLiveAvailabilityDependsOnlyOnValidatedLookup() throws {
        let mappedURL = try #require(URL(string: "https://live.worldcubeassociation.org/competitions/11145"))

        #expect(
            CompetitionService.wcaLiveAvailability(
                for: .available(competitionID: 11145, url: mappedURL)
            ) == .available
        )
        #expect(CompetitionService.wcaLiveAvailability(for: .unavailable) == .unavailable)
        #expect(CompetitionService.wcaLiveAvailability(for: .failed) == .failed)
        #expect(CompetitionService.wcaLiveAvailability(for: .loading) == .loading)
    }

    @Test func wcaLiveSubscriptionPayloadUpdatesOnlyTheMatchingRound() throws {
        let fallback = CompetitionWCALiveRound(
            id: "round-1",
            eventID: "333",
            eventName: "3x3x3 Cube",
            roundName: "Final",
            number: 2,
            formatID: "a",
            numberOfAttempts: 5,
            sortBy: "average",
            isFinished: false,
            advancementType: nil,
            advancementLevel: nil,
            isActive: true,
            isOpen: true,
            results: []
        )
        let payload = try #require(
            #"{"data":{"roundUpdated":{"id":"round-1","results":[{"id":"result-1","ranking":1,"advancing":true,"advancingQuestionable":false,"attempts":[{"result":912},{"result":945}],"best":912,"average":928,"person":{"id":"person-1","name":"Test Cuber","country":{"iso2":"US","name":"United States"}},"singleRecordTag":"PR","averageRecordTag":null}]}}}"#
                .data(using: .utf8)
        )

        let updated = try #require(
            CompetitionService.decodeWCALiveRoundSubscriptionResult(payload, fallback: fallback)
        )
        #expect(updated.id == fallback.id)
        #expect(updated.eventID == fallback.eventID)
        #expect(updated.isActive == fallback.isActive)
        #expect(updated.results.count == 1)
        #expect(updated.results[0].name == "Test Cuber")
        #expect(updated.results[0].attempts == [912, 945])
        #expect(updated.results[0].singleRecordTag == "PR")

        let wrongRoundPayload = try #require(
            #"{"data":{"roundUpdated":{"id":"round-2","results":[]}}}"#
                .data(using: .utf8)
        )
        #expect(
            CompetitionService.decodeWCALiveRoundSubscriptionResult(
                wrongRoundPayload,
                fallback: fallback
            ) == nil
        )
    }

    @Test func wcaLiveSubscriptionKeepsParticipantsWithoutResults() throws {
        let fallback = CompetitionWCALiveRound(
            id: "round-1",
            eventID: "333",
            eventName: "3x3x3 Cube",
            roundName: "First round",
            number: 1,
            formatID: "a",
            numberOfAttempts: 5,
            sortBy: "average",
            isFinished: false,
            advancementType: "percent",
            advancementLevel: 75,
            isActive: false,
            isOpen: false,
            results: []
        )
        let payload = try #require(
            #"{"data":{"roundUpdated":{"id":"round-1","results":[{"id":"result-2","ranking":null,"advancing":false,"advancingQuestionable":false,"attempts":[],"best":0,"average":0,"person":{"id":"person-2","name":"Zoe Cuber","country":{"name":"Canada"}},"singleRecordTag":null,"averageRecordTag":null},{"id":"result-1","ranking":null,"advancing":false,"advancingQuestionable":false,"attempts":[],"best":0,"average":0,"person":{"id":"person-1","name":"Alex Cuber","country":{"name":"United States"}},"singleRecordTag":null,"averageRecordTag":null}]}}}"#
                .data(using: .utf8)
        )

        let updated = try #require(
            CompetitionService.decodeWCALiveRoundSubscriptionResult(payload, fallback: fallback)
        )
        #expect(updated.results.map(\.name) == ["Alex Cuber", "Zoe Cuber"])
        #expect(updated.results.allSatisfy { $0.ranking == nil })
        #expect(updated.results.allSatisfy { $0.attempts.isEmpty })
        #expect(updated.results.allSatisfy { $0.best == 0 && $0.average == 0 })
    }

    @Test func wcaLiveReconnectUsesCappedBackoff() {
        #expect(CompetitionWCALiveRealtimeManager.retryDelayNanoseconds(after: 1) == 1_000_000_000)
        #expect(CompetitionWCALiveRealtimeManager.retryDelayNanoseconds(after: 3) == 4_000_000_000)
        #expect(CompetitionWCALiveRealtimeManager.retryDelayNanoseconds(after: 6) == 30_000_000_000)
        #expect(CompetitionWCALiveRealtimeManager.retryDelayNanoseconds(after: 20) == 60_000_000_000)
    }

    @Test func competitionStatusFiltersUseWCACalendarDayBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) throws -> Date {
            try #require(calendar.date(from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour
            )))
        }

        let now = try date(2026, 8, 18, hour: 12)
        let todayCompetition = datedCompetitionSummary(
            id: "Today2026",
            startDate: try date(2026, 8, 18),
            endDate: try date(2026, 8, 18)
        )
        let boundaryCompetition = datedCompetitionSummary(
            id: "RecentWindowBoundary2026",
            startDate: try date(2026, 7, 19),
            endDate: try date(2026, 7, 19)
        )
        let staleCompetition = datedCompetitionSummary(
            id: "OutsideRecentWindow2026",
            startDate: try date(2026, 7, 18),
            endDate: try date(2026, 7, 18)
        )
        let yesterdayCompetition = datedCompetitionSummary(
            id: "Yesterday2026",
            startDate: try date(2026, 8, 17),
            endDate: try date(2026, 8, 17)
        )
        let ongoingCompetition = datedCompetitionSummary(
            id: "Ongoing2026",
            startDate: try date(2026, 8, 17),
            endDate: try date(2026, 8, 19)
        )
        let futureCompetition = datedCompetitionSummary(
            id: "FutureCompetition2026",
            startDate: try date(2026, 8, 22),
            endDate: try date(2026, 8, 23)
        )
        let recentQuery = CompetitionQuery(
            languageCode: "en",
            region: .all,
            events: Set(CompetitionEventFilter.selectableCases),
            year: .all,
            status: .recent
        )

        let allCompetitions = [
            staleCompetition,
            futureCompetition,
            ongoingCompetition,
            todayCompetition,
            yesterdayCompetition,
            boundaryCompetition
        ]
        let recentIDs = Set(CompetitionService.filterCompetitions(
            allCompetitions,
            for: recentQuery,
            now: now
        ).map(\.id))

        #expect(recentIDs.contains("Today2026"))
        #expect(recentIDs.contains("Yesterday2026"))
        #expect(recentIDs.contains("RecentWindowBoundary2026"))
        #expect(!recentIDs.contains("OutsideRecentWindow2026"))
        #expect(!recentIDs.contains("Ongoing2026"))
        #expect(!recentIDs.contains("FutureCompetition2026"))

        let presentQuery = CompetitionQuery(
            languageCode: "en",
            region: .all,
            events: Set(CompetitionEventFilter.selectableCases),
            year: .all,
            status: .present
        )
        let presentIDs = Set(CompetitionService.filterCompetitions(
            allCompetitions,
            for: presentQuery,
            now: now
        ).map(\.id))
        #expect(presentIDs.contains("Today2026"))
        #expect(presentIDs.contains("Ongoing2026"))
        #expect(presentIDs.contains("FutureCompetition2026"))
        #expect(!presentIDs.contains("Yesterday2026"))
    }

    @Test func pastCompetitionYearFilterHonorsYearBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
        }

        let query = CompetitionQuery(
            languageCode: "en",
            region: .all,
            events: Set(CompetitionEventFilter.selectableCases),
            year: .year(2025),
            status: .past
        )
        let competitions = [
            datedCompetitionSummary(id: "Start2025", startDate: try date(2025, 1, 1), endDate: try date(2025, 1, 1)),
            datedCompetitionSummary(id: "End2025", startDate: try date(2025, 12, 31), endDate: try date(2025, 12, 31)),
            datedCompetitionSummary(id: "Old2024", startDate: try date(2024, 12, 31), endDate: try date(2024, 12, 31)),
            datedCompetitionSummary(id: "New2026", startDate: try date(2026, 1, 1), endDate: try date(2026, 1, 1))
        ]
        let ids = Set(CompetitionService.filterCompetitions(
            competitions,
            for: query,
            now: try date(2026, 8, 18)
        ).map(\.id))

        #expect(ids == Set(["Start2025", "End2025"]))
    }

    @Test func crossYearCompetitionsMatchWCAEndDateYearGrouping() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
        }

        let crossYear = datedCompetitionSummary(
            id: "AllroundersKatowiceIV2026",
            startDate: try date(2026, 12, 31),
            endDate: try date(2027, 1, 1)
        )
        let first2027Competition = datedCompetitionSummary(
            id: "FirstCompetition2027",
            startDate: try date(2027, 1, 1),
            endDate: try date(2027, 1, 1)
        )
        let query = CompetitionQuery(
            languageCode: "en",
            region: .all,
            events: Set(CompetitionEventFilter.selectableCases),
            year: .all,
            status: .past
        )

        #expect(CompetitionService.officialCompetitionYear(for: crossYear) == 2027)
        #expect(CompetitionService.filterCompetitions(
            [crossYear, first2027Competition],
            for: query,
            now: try date(2027, 2, 1)
        ).map(\.id) == ["FirstCompetition2027", "AllroundersKatowiceIV2026"])
    }

    @Test func faceTurningOctahedronUsesTheCanonicalCompetitionEventRegistry() {
        #expect(CompetitionEventFilter.faceTurningOctahedron.wcaEventID == "fto")
        #expect(CompetitionEventFilter.selectableCases.contains(.faceTurningOctahedron))
        #expect(CompetitionEventPresentation.officialName(for: "fto") == "Face Turning Octahedron")
        #expect(CompetitionEventIconFont.glyph(for: "fto") != nil)
        #expect(CompetitionEventIconFont.templateImage(for: "333") != nil)
        #expect(CompetitionEventIconFont.templateImage(for: "sq1") != nil)
        #expect(CompetitionEventIconFont.templateImage(for: "fto") != nil)
    }

    @Test func competitionPaginationStopsAtReportedTotal() {
        #expect(CompetitionService.nextCompetitionPage(currentPage: 1, receivedCount: 25, totalCount: 60) == 2)
        #expect(CompetitionService.nextCompetitionPage(currentPage: 2, receivedCount: 25, totalCount: 60) == 3)
        #expect(CompetitionService.nextCompetitionPage(currentPage: 3, receivedCount: 10, totalCount: 60) == nil)
        #expect(CompetitionService.nextCompetitionPage(currentPage: 1, receivedCount: 24, totalCount: nil) == nil)
        #expect(CompetitionService.nextCompetitionPage(currentPage: 1, receivedCount: 25, totalCount: nil) == 2)
        #expect(CompetitionService.nextCompetitionPage(
            currentPage: 35,
            receivedCount: 500,
            totalCount: 17_946,
            pageSize: 500
        ) == 36)
        #expect(CompetitionService.nextCompetitionPage(
            currentPage: 36,
            receivedCount: 446,
            totalCount: 17_946,
            pageSize: 500
        ) == nil)
    }

    @Test func competitionLoadingProgressCollapsesToFinalCount() {
        #expect(CompetitionService.listCountPresentation(
            loadedCount: 184,
            visibleCount: 184,
            totalCount: 600,
            hasPendingPages: true
        ) == .progress(loaded: 184, total: 600))
        #expect(CompetitionService.listCountPresentation(
            loadedCount: 600,
            visibleCount: 600,
            totalCount: 600,
            hasPendingPages: false
        ) == .count(600))
        #expect(CompetitionService.listCountPresentation(
            loadedCount: 600,
            visibleCount: 594,
            totalCount: 600,
            hasPendingPages: false
        ) == .count(594))
    }

    @Test func competitionMarkdownAddressKeepsItsDestinationWithoutDisplayingTheURL() throws {
        let destination = "https://maps.example.com/place?id=42"
        let segments = CompetitionService.inlineLinkSegments(
            in: "Venue: [Building C, Greenland Lanhai International Mansion](\(destination))"
        )

        #expect(segments.map(\.text).joined() == "Venue: Building C, Greenland Lanhai International Mansion")
        #expect(!segments.map(\.text).joined().contains(destination))
        #expect(try #require(segments.first(where: { $0.url != nil })?.url?.absoluteString) == destination)
        #expect(
            CompetitionService.addressDisplayText(
                in: "Building C, Greenland Lanhai International Mansion (\(destination))"
            ) == "Building C, Greenland Lanhai International Mansion"
        )
        #expect(CompetitionService.addressDisplayText(in: destination).isEmpty)
    }

    @Test func competitionAddressParserSupportsMarkdownVenueWithOptionalWhitespace() throws {
        let bc = CompetitionService.parseAddress(
            "Canada, Vancouver, British Columbia, [Pinnacle Hotel Harbourfront] (https://www.pinnacleharbourfronthotel.com/)"
        )
        #expect(bc.displayText == "Canada, Vancouver, British Columbia, Pinnacle Hotel Harbourfront")
        #expect(
            try #require(bc.destinationURL?.absoluteString)
                == "https://www.pinnacleharbourfronthotel.com/"
        )
        #expect(bc.segments.count == 2)
        #expect(bc.segments[0].text == "Canada, Vancouver, British Columbia, ")
        #expect(bc.segments[0].destinationURL == nil)
        #expect(bc.segments[1].text == "Pinnacle Hotel Harbourfront")
        #expect(
            try #require(bc.segments[1].destinationURL?.absoluteString)
                == "https://www.pinnacleharbourfronthotel.com/"
        )

        let svealand = CompetitionService.parseAddress(
            "Sweden, Uppsala, [Fyris Park](https://fyrispark.se/)"
        )
        #expect(svealand.displayText == "Sweden, Uppsala, Fyris Park")
        #expect(try #require(svealand.destinationURL?.absoluteString) == "https://fyrispark.se/")
        #expect(svealand.segments.map(\.text) == ["Sweden, Uppsala, ", "Fyris Park"])

        let projected = bc.projected(
            onto: "Canada, Vancouver, British Columbia, Pinnacle Hotel Harbourfront"
        )
        #expect(projected.segments.count == 2)
        #expect(projected.segments[0].destinationURL == nil)
        #expect(projected.segments[1].text == "Pinnacle Hotel Harbourfront")
        #expect(projected.segments[1].destinationURL == bc.destinationURL)

        let plain = CompetitionService.parseAddress("Malaysia, Kuala Lumpur, Convention Centre")
        #expect(plain.displayText == "Malaysia, Kuala Lumpur, Convention Centre")
        #expect(plain.destinationURL == nil)
        #expect(plain.segments.count == 1)
        #expect(plain.segments[0].destinationURL == nil)
    }

    private func competitionSummary(website: String?) -> CompetitionSummary {
        CompetitionSummary(
            id: "ExampleOpen2026",
            name: "Example Open 2026",
            shortDisplayName: nil,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 0),
            registrationOpen: nil,
            registrationClose: nil,
            competitorLimit: nil,
            venue: "",
            venueAddress: "",
            venueDetails: nil,
            city: "",
            countryISO2: "CN",
            latitude: nil,
            longitude: nil,
            url: "https://www.worldcubeassociation.org/competitions/ExampleOpen2026",
            website: website,
            dateRange: "",
            eventIDs: [],
            championshipTypes: nil,
            localizedRegionLineOverride: nil,
            localizedAddressLineOverride: nil,
            localizedStatusOverride: nil,
            localizedRegistrationStartOverride: nil,
            localizedWaitlistStartOverride: nil
        )
    }

    private func datedCompetitionSummary(
        id: String,
        startDate: Date,
        endDate: Date
    ) -> CompetitionSummary {
        CompetitionSummary(
            id: id,
            name: id,
            shortDisplayName: nil,
            startDate: startDate,
            endDate: endDate,
            registrationOpen: nil,
            registrationClose: nil,
            competitorLimit: nil,
            venue: "",
            venueAddress: "",
            venueDetails: nil,
            city: "",
            countryISO2: "KR",
            latitude: nil,
            longitude: nil,
            url: "https://www.worldcubeassociation.org/competitions/\(id)",
            website: nil,
            dateRange: "",
            eventIDs: [],
            championshipTypes: nil,
            localizedRegionLineOverride: nil,
            localizedAddressLineOverride: nil,
            localizedStatusOverride: nil,
            localizedRegistrationStartOverride: nil,
            localizedWaitlistStartOverride: nil
        )
    }

#if canImport(UIKit)
    private func rgbaPixels(from image: UIImage) throws -> RGBAPixelBuffer {
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(
            CGContext(
                data: &bytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return RGBAPixelBuffer(width: width, height: height, bytes: bytes)
    }
#endif

}

#if canImport(UIKit)
private struct RGBAPixelBuffer {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    func containsOpaqueDarkPixel(inBottomFraction fraction: Double) -> Bool {
        containsPixel(inBottomFraction: fraction) { red, green, blue, alpha in
            alpha > 220 && red < 70 && green < 70 && blue < 70
        }
    }

    func containsOpaqueLightPixel(inBottomFraction fraction: Double) -> Bool {
        containsPixel(inBottomFraction: fraction) { red, green, blue, alpha in
            alpha > 220 && red > 190 && green > 190 && blue > 190
        }
    }

    private func containsPixel(
        inBottomFraction fraction: Double,
        matching predicate: (UInt8, UInt8, UInt8, UInt8) -> Bool
    ) -> Bool {
        let firstRow = max(0, Int(Double(height) * (1 - fraction)))
        for row in firstRow..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                if predicate(
                    bytes[offset],
                    bytes[offset + 1],
                    bytes[offset + 2],
                    bytes[offset + 3]
                ) {
                    return true
                }
            }
        }
        return false
    }
}
#endif

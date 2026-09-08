#if os(iOS)
import Testing
import Foundation
@testable import CubeFlow

@MainActor
struct SmartCubeReplacementTests {
    private let scramble = "U2 D R F L B U R2 F2 D2 L2 B2 U' R' F' D' L' B' U R"
    private let deviation = ["R", "F", "L", "B", "R", "F", "L", "B", "R", "F", "L", "B"]

    private func fixture(
        scramble: String? = nil,
        deviation: [String]? = nil
    ) throws -> (SmartCubeScrambleProgress, SmartCubeRecoveryPlan) {
        var progress = try #require(SmartCubeScrambleProgress(scramble: scramble ?? self.scramble))
        var source = SmartCubeBluetoothManager.solvedFacelets
        for turn in deviation ?? self.deviation {
            source = try #require(SmartCubeBluetoothManager.facelets(source, applying: turn))
            _ = progress.update(with: source, canonicalMove: turn)
        }
        let plan = try #require(progress.guaranteedRecoveryPlan(
            identity: .init(scrambleEpochID: UUID(), stateVersion: 1), sourceFacelets: source))
        return (progress, plan)
    }

    private func recoveryPlan(cost: Int) -> SmartCubeRecoveryPlan {
        let identity = SmartCubeRecoveryPlanIdentity(scrambleEpochID: UUID(), stateVersion: 1)
        return SmartCubeRecoveryPlan(
            identity: identity,
            sourceFacelets: SmartCubeBluetoothManager.solvedFacelets,
            checkpoint: SmartCubeRecoveryCheckpoint(
                facelets: SmartCubeBluetoothManager.solvedFacelets,
                completedTokenIndices: [],
                partialCompletionMoves: [:],
                totalTokenCount: 20
            ),
            correctionMoves: Array(repeating: "R", count: cost),
            totalCost: cost
        )
    }

    @Test(arguments: [
        (["F", "F"], ["F2"]),
        (["F'", "F'"], ["F2"]),
        (["F", "F'"], []),
        (["F'", "F"], []),
        (["F2", "F"], ["F'"]),
        (["F2", "F'"], ["F"]),
        (["F2", "F2"], []),
        (["F", "R", "R'", "F"], ["F2"])
    ])
    func adjacentSameFaceMovesNormalizeModuloFour(
        input: [String],
        expected: [String]
    ) {
        #expect(SmartCubeRecoveryEngine.normalizedAdjacent(input) == expected)
    }

    @Test func recoveryBoundaryNormalizationAdvancesExecutableCheckpoint() throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: "F' U"))
        let source = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "F"))
        _ = progress.update(with: source, canonicalMove: "F")
        let rawPlan = try #require(progress.guaranteedRecoveryPlan(
            identity: .init(scrambleEpochID: UUID(), stateVersion: 1),
            sourceFacelets: source
        ))

        let normalizedPlan = progress.normalizeRecoveryBoundary(rawPlan)
        let normalized = try #require(normalizedPlan)
        #expect(normalized.correctionMoves == ["F2"])
        #expect(normalized.totalCost == 1)
        #expect(normalized.checkpoint.completedTokenIndices == [0])
        #expect(normalized.remainingOriginalWorkload == 1)

        let afterGuidance = try #require(SmartCubeBluetoothManager.facelets(source, applying: "F2"))
        #expect(progress.update(with: afterGuidance, canonicalMove: "F2") == .returned)
        #expect(progress.currentMoveTokenIndex == 1)
        let target = try #require(SmartCubeBluetoothManager.facelets(afterGuidance, applying: "U"))
        #expect(progress.update(with: target, canonicalMove: "U") == .completed)
        #expect(progress.isComplete)
    }

    @Test func inverseQuarterTurnReplacesOriginalMoveWithOnlyHalfTurnGuidance() throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: "F"))
        let source = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "F'"))
        #expect(progress.update(with: source, canonicalMove: "F'") == .deviated)
        let rawPlan = try #require(progress.guaranteedRecoveryPlan(
            identity: .init(scrambleEpochID: UUID(), stateVersion: 1),
            sourceFacelets: source
        ))
        let normalizedPlan = progress.normalizeRecoveryBoundary(rawPlan)
        let plan = try #require(normalizedPlan)

        #expect(plan.correctionMoves == ["F2"])
        #expect(plan.supersededOriginalTokenIndices == [0])
        #expect(plan.executableMoves(originalTokens: progress.tokens) == ["F2"])
        #expect(plan.checkpoint.completedTokenIndices == [0])

        let target = try #require(SmartCubeBluetoothManager.facelets(source, applying: "F2"))
        #expect(progress.update(with: target, canonicalMove: "F2") == .completed)
        #expect(progress.isComplete)
    }

    @Test func resetCapabilitiesAndGANCommandsMatchEstablishedProtocolFamilies() throws {
        #expect(SmartCubeProtocolKind.ganGen2.stateResetCapability == .deviceResetWithAuthoritativeReadback)
        #expect(SmartCubeProtocolKind.ganGen3.stateResetCapability == .deviceResetWithAuthoritativeReadback)
        #expect(SmartCubeProtocolKind.ganGen4.stateResetCapability == .deviceResetWithAuthoritativeReadback)
        #expect(SmartCubeProtocolKind.moyu.stateResetCapability == .softwareReference)

        let gen2 = try #require(GANCubeProtocolParser(kind: .ganGen2).commandMessage(for: .requestReset))
        let gen3 = try #require(GANCubeProtocolParser(kind: .ganGen3).commandMessage(for: .requestReset))
        let gen4 = try #require(GANCubeProtocolParser(kind: .ganGen4).commandMessage(for: .requestReset))
        #expect(Array(gen2.prefix(12)) == [0x0A, 0x05, 0x39, 0x77, 0x00, 0x00, 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB])
        #expect(Array(gen3.prefix(12)) == [0x68, 0x05, 0x05, 0x39, 0x77, 0x00, 0x00, 0x01, 0x23, 0x45, 0x67, 0x89])
        #expect(Array(gen4.prefix(12)) == [0xD2, 0x0D, 0x05, 0x39, 0x77, 0x00, 0x00, 0x01, 0x23, 0x45, 0x67, 0x89])
        #expect(GANCubeProtocolParser(kind: .moyu).commandMessage(for: .requestReset) == nil)
    }

    @Test func softwareResetReferenceSurvivesUnchangedReconnectAndRejectsDivergence() throws {
        let deviceID = UUID()
        let rawAtReset = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "R U"))
        var reference = SmartCubeSoftwareResetReference(
            deviceID: deviceID,
            expectedDeviceFacelets: rawAtReset,
            localFacelets: SmartCubeBluetoothManager.solvedFacelets
        )
        let applied = reference.apply("F")
        #expect(applied)
        let expectedRaw = try #require(SmartCubeBluetoothManager.facelets(rawAtReset, applying: "F"))
        let expectedLocal = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "F"))

        #expect(reference.resolve(deviceID: deviceID, snapshot: expectedRaw, forceAuthoritative: false) == .preserveLocal(expectedLocal))

        let movedWhileDisconnected = try #require(SmartCubeBluetoothManager.facelets(expectedRaw, applying: "R"))
        #expect(reference.resolve(deviceID: deviceID, snapshot: movedWhileDisconnected, forceAuthoritative: false) == .useAuthoritative(movedWhileDisconnected))
        #expect(reference.resolve(deviceID: UUID(), snapshot: expectedRaw, forceAuthoritative: false) == .useAuthoritative(expectedRaw))
        #expect(reference.resolve(deviceID: deviceID, snapshot: expectedRaw, forceAuthoritative: true) == .useAuthoritative(expectedRaw))
    }

    @Test func resetIdentityAndCanonicalTrustRejectStaleAttempts() {
        let attemptID = UUID()
        let deviceID = UUID()
        let identity = SmartCubeResetRequestIdentity(id: UUID(), connectionAttemptID: attemptID, deviceID: deviceID)
        #expect(identity.matches(connectionAttemptID: attemptID, deviceID: deviceID))
        #expect(!identity.matches(connectionAttemptID: UUID(), deviceID: deviceID))
        #expect(!identity.matches(connectionAttemptID: attemptID, deviceID: UUID()))

        let feed = SmartCubeCanonicalFeed()
        feed.breakContinuity(.reset, facelets: nil)
        #expect(!feed.isStateTrusted)
        feed.acceptAuthoritativeSnapshot(SmartCubeBluetoothManager.solvedFacelets, stateChanged: true)
        #expect(feed.isStateTrusted)
        guard case .boundary(let boundary) = feed.eventHistory.last else {
            Issue.record("Authoritative reset read-back did not establish a continuity boundary")
            return
        }
        #expect(boundary.reason == .resync)
        #expect(boundary.facelets == SmartCubeBluetoothManager.solvedFacelets)
    }

    @Test func resetFailureAndNoResponsePoliciesNeverInventDeviceState() {
        let previous = SmartCubeBluetoothManager.solvedFacelets
        #expect(SmartCubeResetFailureDisposition.restorePreviousState.resolvedFacelets(previousFacelets: previous) == previous)
        #expect(SmartCubeResetFailureDisposition.requireAuthoritativeState.resolvedFacelets(previousFacelets: previous) == nil)
        #expect(SmartCubeResetReadbackPolicy.shouldRetry(afterAttempt: 1))
        #expect(SmartCubeResetReadbackPolicy.shouldRetry(afterAttempt: 2))
        #expect(!SmartCubeResetReadbackPolicy.shouldRetry(afterAttempt: 3))
    }

    @Test func timerReadinessRequiresBLEAuthoritativeStateAndTrustedContinuity() {
        let attemptID = UUID()
        let lowLevelConnected = SmartCubeObservationReadiness(
            attemptID: attemptID,
            isBLEConnected: true,
            hasAuthoritativeState: false,
            hasTrustedCanonicalState: false
        )
        #expect(!lowLevelConnected.isReady)
        #expect(SmartCubeTimerConnectionPresentation.resolve(
            readiness: lowLevelConnected,
            isAttemptApproved: true,
            connectionState: .connected
        ) == .loading)

        let untrustedSnapshot = SmartCubeObservationReadiness(
            attemptID: attemptID,
            isBLEConnected: true,
            hasAuthoritativeState: true,
            hasTrustedCanonicalState: false
        )
        #expect(!untrustedSnapshot.isReady)

        let decisionPending = SmartCubeObservationReadiness(
            attemptID: attemptID,
            isBLEConnected: true,
            hasResolvedConnectionPolicy: false,
            hasAuthoritativeState: true,
            hasTrustedCanonicalState: true
        )
        #expect(!decisionPending.isReady)
        #expect(SmartCubeTimerConnectionPresentation.resolve(
            readiness: decisionPending,
            isAttemptApproved: false,
            connectionState: .connected
        ) == .loading)

        let ready = SmartCubeObservationReadiness(
            attemptID: attemptID,
            isBLEConnected: true,
            hasAuthoritativeState: true,
            hasTrustedCanonicalState: true
        )
        #expect(ready.isReady)
        #expect(SmartCubeTimerConnectionPresentation.resolve(
            readiness: ready,
            isAttemptApproved: true,
            connectionState: .connected
        ) == .ready)
    }

    @Test func timerReadinessAnnouncementIsAttemptBoundAndExactlyOnce() {
        let currentAttempt = UUID()
        let staleAttempt = UUID()
        var tracker = SmartCubeReadinessAnnouncementTracker()

        let untrackedReady = SmartCubeObservationReadiness(
            attemptID: currentAttempt,
            isBLEConnected: true,
            hasAuthoritativeState: true,
            hasTrustedCanonicalState: true
        )
        let announcedUntrackedAttempt = tracker.shouldAnnounce(untrackedReady)
        #expect(!announcedUntrackedAttempt)

        tracker.begin(currentAttempt)

        let staleReady = SmartCubeObservationReadiness(
            attemptID: staleAttempt,
            isBLEConnected: true,
            hasAuthoritativeState: true,
            hasTrustedCanonicalState: true
        )
        let announcedStaleAttempt = tracker.shouldAnnounce(staleReady)
        #expect(!announcedStaleAttempt)

        let currentReady = SmartCubeObservationReadiness(
            attemptID: currentAttempt,
            isBLEConnected: true,
            hasAuthoritativeState: true,
            hasTrustedCanonicalState: true
        )
        let announcedBeforeApproval = tracker.shouldAnnounce(currentReady)
        #expect(!announcedBeforeApproval)
        tracker.approve(currentAttempt)
        let announcedCurrentAttempt = tracker.shouldAnnounce(currentReady)
        let announcedCurrentAttemptAgain = tracker.shouldAnnounce(currentReady)
        #expect(announcedCurrentAttempt)
        #expect(!announcedCurrentAttemptAgain)

        tracker.end(currentAttempt)
        let announcedEndedAttempt = tracker.shouldAnnounce(currentReady)
        #expect(!announcedEndedAttempt)
    }

    @Test func reconnectRequiresAndAnnouncesANewReadyAttempt() {
        let firstAttempt = UUID()
        let secondAttempt = UUID()
        var tracker = SmartCubeReadinessAnnouncementTracker()

        tracker.begin(firstAttempt)
        tracker.approve(firstAttempt)
        let firstReady = SmartCubeObservationReadiness(
            attemptID: firstAttempt,
            isBLEConnected: true,
            hasAuthoritativeState: true,
            hasTrustedCanonicalState: true
        )
        let announcedFirstAttempt = tracker.shouldAnnounce(firstReady)
        #expect(announcedFirstAttempt)
        tracker.end(firstAttempt)

        tracker.begin(secondAttempt)
        let secondLowLevelConnection = SmartCubeObservationReadiness(
            attemptID: secondAttempt,
            isBLEConnected: true,
            hasAuthoritativeState: false,
            hasTrustedCanonicalState: false
        )
        let announcedLowLevelConnection = tracker.shouldAnnounce(secondLowLevelConnection)
        #expect(!announcedLowLevelConnection)
        #expect(SmartCubeTimerConnectionPresentation.resolve(
            readiness: secondLowLevelConnection,
            isAttemptApproved: false,
            connectionState: .connected
        ) == .loading)

        let secondReady = SmartCubeObservationReadiness(
            attemptID: secondAttempt,
            isBLEConnected: true,
            hasAuthoritativeState: true,
            hasTrustedCanonicalState: true
        )
        let announcedBeforeSecondApproval = tracker.shouldAnnounce(secondReady)
        #expect(!announcedBeforeSecondApproval)
        tracker.approve(secondAttempt)
        let announcedSecondAttempt = tracker.shouldAnnounce(secondReady)
        #expect(announcedSecondAttempt)
    }

    @Test func sharedPolicyResolutionConvergesSettingsAndTimerReadiness() {
        let firstAttempt = UUID()
        let secondAttempt = UUID()
        var tracker = SmartCubeReadinessAnnouncementTracker()

        let pendingDecision = SmartCubeObservationReadiness(
            attemptID: firstAttempt,
            isBLEConnected: true,
            hasResolvedConnectionPolicy: false,
            hasAuthoritativeState: true,
            hasTrustedCanonicalState: true
        )
        tracker.synchronize(attemptID: firstAttempt, isApproved: false)
        #expect(!pendingDecision.isReady)
        let announcedPendingDecision = tracker.shouldAnnounce(pendingDecision)
        #expect(!announcedPendingDecision)

        let readyAfterSettingsDecision = SmartCubeObservationReadiness(
            attemptID: firstAttempt,
            isBLEConnected: true,
            hasResolvedConnectionPolicy: true,
            hasAuthoritativeState: true,
            hasTrustedCanonicalState: true
        )
        tracker.synchronize(attemptID: firstAttempt, isApproved: true)
        let announcedReady = tracker.shouldAnnounce(readyAfterSettingsDecision)
        let announcedRepeatedSnapshot = tracker.shouldAnnounce(readyAfterSettingsDecision)
        #expect(announcedReady)
        #expect(!announcedRepeatedSnapshot)

        tracker.synchronize(attemptID: secondAttempt, isApproved: false)
        let announcedStaleFirstAttempt = tracker.shouldAnnounce(readyAfterSettingsDecision)
        #expect(!announcedStaleFirstAttempt)

        let secondReady = SmartCubeObservationReadiness(
            attemptID: secondAttempt,
            isBLEConnected: true,
            hasResolvedConnectionPolicy: true,
            hasAuthoritativeState: true,
            hasTrustedCanonicalState: true
        )
        tracker.synchronize(attemptID: secondAttempt, isApproved: true)
        let announcedSecondAttempt = tracker.shouldAnnounce(secondReady)
        #expect(announcedSecondAttempt)
    }

    @Test func timerConnectionUsesTheSharedResetPolicyRouting() {
        #expect(SmartCubeResetPolicy.always.connectionAction == .reset)
        #expect(SmartCubeResetPolicy.prompt.connectionAction == .prompt)
        #expect(SmartCubeResetPolicy.never.connectionAction == .continueWithoutReset)
    }

    @Test func oneAndTwoMoveCorrectionsPresentRecoveryImmediately() {
        for cost in 1...2 {
            let plan = recoveryPlan(cost: cost)
            let state = SmartCubeReplacementPlanner.initialPresentation(
                recovery: plan,
                identity: plan.identity,
                sourceFacelets: plan.sourceFacelets
            )
            #expect(state.plan == plan)
            #expect(state.fallbackPlan == nil)
        }
    }

    @Test func threeOrMoreMovesMakeReplanPrimaryWithoutPublishingLongRecovery() {
        for cost in [3, 8, 20] {
            let plan = recoveryPlan(cost: cost)
            let state = SmartCubeReplacementPlanner.initialPresentation(
                recovery: plan,
                identity: plan.identity,
                sourceFacelets: plan.sourceFacelets
            )
            #expect(state.plan == nil)
            #expect(state.fallbackPlan == plan)
            #expect(state.identity == plan.identity)
            #expect(state.sourceFacelets == plan.sourceFacelets)
        }
    }

    @Test func rejectedOrUnavailableReplanRestoresRecoveryFallback() {
        let plan = recoveryPlan(cost: 3)
        let pending = SmartCubeReplacementPlanner.initialPresentation(
            recovery: plan,
            identity: plan.identity,
            sourceFacelets: plan.sourceFacelets
        )
        let fallback = SmartCubeReplacementPlanner.fallbackPresentation(from: pending)
        #expect(fallback.plan == plan)

        let shortcut = recoveryPlan(cost: 2)
        let optimizedFallback = SmartCubeReplacementPlanner.fallbackPresentation(
            recovery: shortcut,
            from: pending
        )
        #expect(optimizedFallback.plan == shortcut)

        let directIdentity = SmartCubeRecoveryPlanIdentity(scrambleEpochID: UUID(), stateVersion: 2)
        let direct = SmartCubeReplacementPlanner.initialPresentation(
            recovery: nil,
            identity: directIdentity,
            sourceFacelets: SmartCubeBluetoothManager.solvedFacelets
        )
        let unavailable = SmartCubeReplacementPlanner.fallbackPresentation(from: direct)
        #expect(unavailable.plan == nil)
        #expect(unavailable.identity == directIdentity)
        #expect(unavailable.sourceFacelets == SmartCubeBluetoothManager.solvedFacelets)
    }

    @Test func successivePendingRequestsKeepFallbacksBoundToTheirOwnIdentity() {
        let first = recoveryPlan(cost: 3)
        let secondIdentity = SmartCubeRecoveryPlanIdentity(
            scrambleEpochID: first.identity.scrambleEpochID,
            stateVersion: first.identity.stateVersion + 1
        )
        let second = SmartCubeRecoveryPlan(
            identity: secondIdentity,
            sourceFacelets: first.sourceFacelets,
            checkpoint: first.checkpoint,
            correctionMoves: ["U", "R", "F"],
            totalCost: 3
        )
        let firstPending = SmartCubeReplacementPlanner.initialPresentation(
            recovery: first, identity: first.identity, sourceFacelets: first.sourceFacelets
        )
        let secondPending = SmartCubeReplacementPlanner.initialPresentation(
            recovery: second, identity: second.identity, sourceFacelets: second.sourceFacelets
        )
        #expect(firstPending.identity != secondPending.identity)
        #expect(SmartCubeReplacementPlanner.fallbackPresentation(from: firstPending).plan == first)
        #expect(SmartCubeReplacementPlanner.fallbackPresentation(from: secondPending).plan == second)
    }

    @Test func normalCommutingAndSmallMistakesKeepRecovery() throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: scramble))
        let u = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "U"))
        #expect(progress.update(with: u, canonicalMove: "U") == .partial)
        #expect(!progress.isDeviated && progress.replanGeneration == 0)

        var commuting = try #require(SmartCubeScrambleProgress(scramble: scramble))
        let d = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "D"))
        #expect(commuting.update(with: d, canonicalMove: "D") == .matchedLater)
        for correction in 1...2 {
            #expect(SmartCubeReplacementPlanner.costDecision(
                correction: correction, remaining: 20, candidateCost: 10,
                lastDeviationMove: nil, firstCandidateMove: nil
            ) == .correctionBelowThreshold)
        }
    }

    @Test func oneMoveSavingsReplansWithoutLegacySavingsGates() {
        #expect(SmartCubeReplacementPlanner.costDecision(
            correction: 3, remaining: 8, candidateCost: 10,
            lastDeviationMove: nil, firstCandidateMove: nil
        ) == .adopted)
        #expect(SmartCubeReplacementPlanner.costDecision(
            correction: 3, remaining: 8, candidateCost: 11,
            lastDeviationMove: nil, firstCandidateMove: nil
        ) == .candidateNotShorter)
    }

    @Test func inverseHysteresisOnlyRejectsMarginalUndo() {
        #expect(SmartCubeReplacementPlanner.costDecision(
            correction: 3, remaining: 8, candidateCost: 10,
            lastDeviationMove: "B'", firstCandidateMove: "B"
        ) == .inverseMoveHysteresis)
        #expect(SmartCubeReplacementPlanner.costDecision(
            correction: 3, remaining: 8, candidateCost: 9,
            lastDeviationMove: "B'", firstCandidateMove: "B"
        ) == .adopted)
    }

    @Test func arbitraryTrustedStateCanRestoreGuidanceWithoutTrail() async throws {
        let (progress, plan) = try fixture()
        var interrupted = progress
        interrupted.breakContinuity(at: nil)
        interrupted.breakContinuity(at: plan.sourceFacelets)
        #expect(interrupted.isDeviated)
        #expect(interrupted.guaranteedRecoveryPlan(
            identity: plan.identity,
            sourceFacelets: plan.sourceFacelets
        ) == nil)

        let decision = await SmartCubeReplacementPlanner.restorationDecision(
            identity: plan.identity,
            sourceFacelets: plan.sourceFacelets,
            targetFacelets: interrupted.targetFacelets,
            currentGeneration: interrupted.replanGeneration
        )
        let replacement = try #require(decision.replacement)
        #expect(replacement.targetFacelets == progress.targetFacelets)
        #expect(replacement.expectedFacelets.first == plan.sourceFacelets)
        #expect(replacement.expectedFacelets.last == progress.targetFacelets)
        #expect(replacement.canAdopt(
            identity: plan.identity,
            facelets: plan.sourceFacelets,
            targetFacelets: progress.targetFacelets,
            trusted: true,
            deviated: true,
            currentGeneration: 0
        ))
    }

    @Test func authoritativeSnapshotRestoresTrustEvenWhenFaceletsAreUnchanged() throws {
        let feed = SmartCubeCanonicalFeed()
        feed.breakContinuity(.historyGap, facelets: nil)
        #expect(!feed.isStateTrusted)
        let sequence = feed.sequence
        feed.acceptAuthoritativeSnapshot(SmartCubeBluetoothManager.solvedFacelets, stateChanged: false)
        #expect(feed.isStateTrusted)
        #expect(feed.sequence == sequence + 1)
        guard case .boundary(let boundary) = feed.eventHistory.last,
              boundary.reason == .resync,
              boundary.facelets == SmartCubeBluetoothManager.solvedFacelets else {
            Issue.record("Equal authoritative snapshot did not publish a trusted resync boundary")
            return
        }
    }

    @Test func newScrambleCanAnchorFromAnAlreadyScrambledTrustedCube() async throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: scramble))
        let source = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "R U F L D"))
        _ = progress.update(with: source)
        #expect(progress.isDeviated)
        let identity = SmartCubeRecoveryPlanIdentity(scrambleEpochID: UUID(), stateVersion: 1)
        #expect(progress.guaranteedRecoveryPlan(identity: identity, sourceFacelets: source) == nil)

        let decision = await SmartCubeReplacementPlanner.restorationDecision(
            identity: identity,
            sourceFacelets: source,
            targetFacelets: progress.targetFacelets,
            currentGeneration: 0
        )
        let replacement = try #require(decision.replacement)
        #expect(replacement.sourceFacelets == source)
        #expect(replacement.targetFacelets == progress.targetFacelets)
        #expect(replacement.expectedFacelets.last == progress.targetFacelets)
    }

    @Test func expensiveRecoveryReplansDirectlyToOriginalTarget() async throws {
        let (progress, plan) = try fixture()
        let originalTarget = progress.targetFacelets
        #expect(SmartCubeBluetoothManager.facelets(afterApplying: scramble) == originalTarget)
        let decision = await SmartCubeReplacementPlanner.decision(
            recovery: plan,
            targetFacelets: originalTarget,
            currentGeneration: progress.replanGeneration,
            lastDeviationMove: progress.deviationMoves.last
        )
        let replacement = try #require(decision.replacement)
        #expect(decision.reason == .adopted)
        #expect(replacement.sourceFacelets == plan.sourceFacelets)
        #expect(replacement.targetFacelets == originalTarget)
        #expect(replacement.expectedFacelets.first == plan.sourceFacelets)
        #expect(replacement.expectedFacelets.last == originalTarget)

        var replanned = SmartCubeScrambleProgress(replacement: replacement)
        #expect(replanned.targetFacelets == originalTarget)
        #expect(replanned.replanGeneration == 1)
        var state = replacement.sourceFacelets
        for (index, token) in replacement.tokens.enumerated() {
            state = try #require(SmartCubeBluetoothManager.facelets(state, applying: token))
            _ = replanned.update(with: state, canonicalMove: token)
            #expect(replanned.completedTokenIndices.contains(index))
        }
        #expect(replanned.isComplete)
        #expect(state == originalTarget)
    }

    @Test func laterLargeDeviationCanReplanAgainWithoutOldPlan() async throws {
        let (initial, firstRecovery) = try fixture()
        let firstDecision = await SmartCubeReplacementPlanner.decision(
            recovery: firstRecovery,
            targetFacelets: initial.targetFacelets,
            currentGeneration: 0,
            lastDeviationMove: initial.deviationMoves.last
        )
        let first = try #require(firstDecision.replacement)
        var current = SmartCubeScrambleProgress(replacement: first)
        var state = first.sourceFacelets
        for move in deviation {
            state = try #require(SmartCubeBluetoothManager.facelets(state, applying: move))
            _ = current.update(with: state, canonicalMove: move)
        }
        let secondRecovery = try #require(current.guaranteedRecoveryPlan(
            identity: .init(scrambleEpochID: UUID(), stateVersion: 1), sourceFacelets: state))
        let secondDecision = await SmartCubeReplacementPlanner.decision(
            recovery: secondRecovery,
            targetFacelets: current.targetFacelets,
            currentGeneration: current.replanGeneration,
            lastDeviationMove: current.deviationMoves.last
        )
        let second = try #require(secondDecision.replacement)
        #expect(second.generation == 2)
        #expect(second.sourceFacelets == state)
        #expect(second.targetFacelets == initial.targetFacelets)
        #expect(second.expectedFacelets.last == initial.targetFacelets)
        #expect(!second.canAdopt(
            identity: first.identity, facelets: first.sourceFacelets,
            targetFacelets: first.targetFacelets, trusted: true, deviated: true,
            currentGeneration: 1
        ))
    }

    @Test func replannedProgressPreservesCollapseAndTrailState() async throws {
        let (progress, plan) = try fixture()
        let decision = await SmartCubeReplacementPlanner.decision(
            recovery: plan,
            targetFacelets: progress.targetFacelets,
            currentGeneration: 0,
            lastDeviationMove: progress.deviationMoves.last
        )
        let replacement = try #require(decision.replacement)
        var replanned = SmartCubeScrambleProgress(replacement: replacement)
        let firstState = try #require(SmartCubeBluetoothManager.facelets(
            replacement.sourceFacelets, applying: replacement.tokens[0]))
        _ = replanned.update(with: firstState, canonicalMove: replacement.tokens[0])
        #expect(replanned.completedTokenIndices == [0])
        #expect(replanned.currentMoveTokenIndex != 0)
        // The shared view derives Collapse visibility and Trail dimming from this same set.
        #expect(replanned.replanGeneration == 1)
    }

    @Test func staleResetContinuityAndCancellationCannotAdopt() async throws {
        let (progress, plan) = try fixture()
        let decision = await SmartCubeReplacementPlanner.decision(
            recovery: plan,
            targetFacelets: progress.targetFacelets,
            currentGeneration: 0,
            lastDeviationMove: progress.deviationMoves.last
        )
        let candidate = try #require(decision.replacement)
        #expect(candidate.canAdopt(
            identity: plan.identity, facelets: plan.sourceFacelets,
            targetFacelets: progress.targetFacelets, trusted: true, deviated: true,
            currentGeneration: 0
        ))
        #expect(!candidate.canAdopt(
            identity: .init(scrambleEpochID: plan.identity.scrambleEpochID, stateVersion: 2),
            facelets: plan.sourceFacelets, targetFacelets: progress.targetFacelets,
            trusted: true, deviated: true, currentGeneration: 0
        ))
        #expect(!candidate.canAdopt(
            identity: plan.identity, facelets: SmartCubeBluetoothManager.solvedFacelets,
            targetFacelets: progress.targetFacelets, trusted: true, deviated: true,
            currentGeneration: 0
        ))
        #expect(!candidate.canAdopt(
            identity: plan.identity, facelets: plan.sourceFacelets,
            targetFacelets: SmartCubeBluetoothManager.solvedFacelets,
            trusted: true, deviated: true, currentGeneration: 0
        ))
        #expect(!candidate.canAdopt(
            identity: plan.identity, facelets: plan.sourceFacelets,
            targetFacelets: progress.targetFacelets, trusted: false, deviated: true,
            currentGeneration: 0
        ))
        #expect(!candidate.canAdopt(
            identity: plan.identity, facelets: plan.sourceFacelets,
            targetFacelets: progress.targetFacelets, trusted: true, deviated: true,
            currentGeneration: 1
        ))

        var broken = progress
        broken.breakContinuity(at: nil)
        #expect(broken.guaranteedRecoveryPlan(
            identity: plan.identity, sourceFacelets: plan.sourceFacelets
        ) == nil)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await SmartCubeReplacementPlanner.decision(
                recovery: plan, targetFacelets: progress.targetFacelets,
                currentGeneration: 0, lastDeviationMove: progress.deviationMoves.last
            )
        }
        #expect(await cancelled.value.reason == .cancelled)
    }

    @Test func solveLifecycleStillExcludesFinalScrambleMove() {
        var epoch = SmartCubeScrambleEpoch()
        epoch.establish(at: .distantPast, latestMoveID: nil)
        let finalMove = SmartCubeMoveEvent(
            move: "R", serial: 1, face: nil, direction: nil,
            localTimestamp: .now, cubeTimestampMilliseconds: 100
        )
        _ = epoch.observePhysicalMove(finalMove)
        var lifecycle = SmartCubeSolveLifecycle()
        #expect(epoch.completionAction(
            inspectionEnabled: false, completingMoveID: finalMove.id, lifecycle: &lifecycle
        ) == .enteredReady)
        #expect(lifecycle.physicalMoveDidOccur(finalMove) == .none)
        let next = SmartCubeMoveEvent(
            move: "U", serial: 2, face: nil, direction: nil,
            localTimestamp: .now, cubeTimestampMilliseconds: 200
        )
        #expect(lifecycle.physicalMoveDidOccur(next) == .startTiming(next))
    }
}
#endif

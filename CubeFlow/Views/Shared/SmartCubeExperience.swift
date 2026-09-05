#if os(iOS)
import Foundation
import SwiftUI
import AVFoundation

nonisolated final class SmartCubeReadySoundPlayer: @unchecked Sendable {
    static let shared = SmartCubeReadySoundPlayer()

    // All AVFoundation objects, including construction, belong to this queue.
    private let queue = DispatchQueue(label: "CubeFlow.ready-sound", qos: .userInitiated)
    private var audio: Audio?

    func prepare() {
        queue.async { self.prepareAudio() }
    }

    func play() {
        queue.async {
            self.prepareAudio()
            self.audio?.play()
        }
    }

    private func prepareAudio() {
        dispatchPrecondition(condition: .onQueue(queue))
        if audio == nil { audio = Audio() }
        audio?.prepare()
    }

    private final class Audio {
        private let engine = AVAudioEngine()
        private let player = AVAudioPlayerNode()
        private let buffer: AVAudioPCMBuffer?

        init() {
            let sampleRate = 44_100.0
            let frameCount = AVAudioFrameCount(sampleRate * 0.12)
            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                self.buffer = nil
                return
            }

            buffer.frameLength = frameCount
            if let samples = buffer.floatChannelData?[0] {
                for frame in 0..<Int(frameCount) {
                    let progress = Double(frame) / Double(frameCount)
                    let frequency = progress < 0.48 ? 880.0 : 1_174.66
                    let attack = min(progress / 0.08, 1)
                    let release = min((1 - progress) / 0.18, 1)
                    let envelope = min(attack, release) * 0.2
                    samples[frame] = Float(sin(2 * .pi * frequency * Double(frame) / sampleRate) * envelope)
                }
            }

            self.buffer = buffer
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }

        func prepare() {
            guard buffer != nil, !engine.isRunning else { return }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
                if !engine.isRunning {
                    try engine.start()
                }
            } catch {
                // A ready cue is optional; timer state never depends on audio availability.
            }
        }

        func play() {
            guard let buffer, engine.isRunning else { return }
            player.stop()
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            player.play()
        }
    }
}

nonisolated enum SmartCubeLayoutDimensions {
    static func length(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(0, value) : 0
    }

    static func statusWidth(containerWidth: CGFloat, inset: CGFloat, cubeSize: CGFloat) -> CGFloat {
        min(length(containerWidth - inset * 2), length(cubeSize + 80))
    }
}

enum SmartCubeCompletedMovesBehavior: String, CaseIterable, Identifiable {
    case collapse
    case trail

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .collapse: "settings.smart_cube.completed_moves.collapse"
        case .trail: "settings.smart_cube.completed_moves.trail"
        }
    }
}

enum SmartCubeScrambleTransition: String, CaseIterable, Identifiable {
    case blur
    case fade
    case slide
    case bounce
    case instant

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .blur: "settings.smart_cube.transition.blur"
        case .fade: "settings.smart_cube.transition.fade"
        case .slide: "settings.smart_cube.transition.slide"
        case .bounce: "settings.smart_cube.transition.bounce"
        case .instant: "settings.smart_cube.transition.instant"
        }
    }

    static func allowed(for behavior: SmartCubeCompletedMovesBehavior) -> [Self] {
        switch behavior {
        case .collapse: allCases
        case .trail: [.blur, .instant]
        }
    }

    static func resolved(
        storedRawValue: String,
        behavior: SmartCubeCompletedMovesBehavior
    ) -> Self {
        let stored = Self(rawValue: storedRawValue) ?? .blur
        return allowed(for: behavior).contains(stored) ? stored : .blur
    }
}

enum SmartCubeCurrentMovePresentation: String, CaseIterable, Identifiable {
    case none
    case highlight

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .none: "settings.smart_cube.current_move.none"
        case .highlight: "settings.smart_cube.current_move.highlight"
        }
    }
}

enum SmartCubeRecoveryDisplay: String, CaseIterable, Identifiable {
    case separate
    case inline

    static func resolved(_ rawValue: String) -> Self {
        rawValue == "focus" ? .inline : (Self(rawValue: rawValue) ?? .separate)
    }

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .separate: "settings.smart_cube.recovery_display.separate"
        case .inline: "settings.smart_cube.recovery_display.inline"
        }
    }
}

enum SmartCubeHighlightAnimation: String, CaseIterable, Identifiable {
    case instant
    case animated

    var id: String { rawValue }

    var updatesImmediately: Bool { self == .instant }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .instant: "settings.smart_cube.highlight_animation.instant"
        case .animated: "settings.smart_cube.highlight_animation.animated"
        }
    }
}

enum SmartCubeHighlightColorMode: String, CaseIterable, Identifiable {
    case automatic
    case custom

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .automatic: "settings.smart_cube.highlight_mode.automatic"
        case .custom: "settings.smart_cube.highlight_mode.custom"
        }
    }
}

enum SmartCubeHighlightColorDefaults {
    static let background = StoredColorData(r: 0.0, g: 0.48, b: 1.0)
    static let text = StoredColorData(r: 1.0, g: 1.0, b: 1.0)
}

enum SmartCubeHighlightToneResolver {
    static func contrastingTone(for background: StoredColorData) -> StoredColorData {
        let background = background.sanitized()
        let target = relativeLuminance(of: background) < 0.36
            ? StoredColorData(r: 1, g: 1, b: 1)
            : StoredColorData(r: 0, g: 0, b: 0)
        let chroma = max(background.r, background.g, background.b)
            - min(background.r, background.g, background.b)

        // Neutral colors should use the true opposite extreme. Chromatic colors
        // retain their family through a strong tint/shade rather than inversion.
        let tonalAmount = chroma < 0.035 ? 1.0 : 0.82
        let tonalCandidate = mix(background, toward: target, amount: tonalAmount)
        let requiredContrast = min(3.0, contrastRatio(background, target))
        guard contrastRatio(background, tonalCandidate) < requiredContrast else {
            return tonalCandidate
        }

        var lowerBound = tonalAmount
        var upperBound = 1.0
        for _ in 0..<18 {
            let amount = (lowerBound + upperBound) / 2
            let candidate = mix(background, toward: target, amount: amount)
            if contrastRatio(background, candidate) >= requiredContrast {
                upperBound = amount
            } else {
                lowerBound = amount
            }
        }
        return mix(background, toward: target, amount: upperBound)
    }

    static func contrastRatio(_ first: StoredColorData, _ second: StoredColorData) -> Double {
        let firstLuminance = relativeLuminance(of: first)
        let secondLuminance = relativeLuminance(of: second)
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private static func mix(
        _ color: StoredColorData,
        toward target: StoredColorData,
        amount: Double
    ) -> StoredColorData {
        let amount = max(0, min(1, amount))
        return StoredColorData(
            r: color.r + (target.r - color.r) * amount,
            g: color.g + (target.g - color.g) * amount,
            b: color.b + (target.b - color.b) * amount,
            a: 1
        )
    }

    private static func relativeLuminance(of color: StoredColorData) -> Double {
        let color = color.sanitized()
        return 0.2126 * linearComponent(color.r)
            + 0.7152 * linearComponent(color.g)
            + 0.0722 * linearComponent(color.b)
    }

    private static func linearComponent(_ value: Double) -> Double {
        value <= 0.04045
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }
}

enum SmartCubeTimerPosition: String, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .left: "settings.smart_cube.timer_position.left"
        case .right: "settings.smart_cube.timer_position.right"
        }
    }
}

nonisolated struct SmartCubePartialHalfTurnPresentation: Equatable, Sendable {
    let tokenIndex: Int
    let targetMove: String
    let completedQuarterTurn: String

    var remainingMove: String {
        completedQuarterTurn
    }
}

nonisolated enum SmartCubeScrambleMatch: Equatable {
    case unchanged
    case partial
    case advanced
    case matchedLater
    case deviated
    case returned
    case completed
}

struct SmartCubeScrambleProgress: Equatable {
    private struct VerificationState: Equatable {
        var completedTokenIndices: Set<Int> = []
        var partialCompletionMoves: [Int: String] = [:]
    }

    private struct DeviationTrail: Equatable {
        let checkpointFacelets: String
        let checkpointState: VerificationState
        var moves: [String]
        var faceletStates: [String]
    }

    let tokens: [String]
    let expectedFacelets: [String]
    private(set) var completedTokenIndices: Set<Int> = []
    private(set) var highestVerifiedMoveCount = 0
    private(set) var isDeviated = false
    private var lastValidFacelets = SmartCubeBluetoothManager.solvedFacelets
    private var partialCompletionMoves: [Int: String] = [:]
    private var deviationTrail: DeviationTrail?
    private var validCheckpoints: [String: VerificationState] = [
        SmartCubeBluetoothManager.solvedFacelets: VerificationState()
    ]

    init?(scramble: String) {
        let tokens = scramble.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty,
              let expectedFacelets = SmartCubeBluetoothManager.faceletStates(afterApplying: tokens)
        else { return nil }
        self.tokens = tokens
        self.expectedFacelets = expectedFacelets
    }

    var isComplete: Bool {
        completedTokenIndices.count == tokens.count
            && partialCompletionMoves.isEmpty
            && lastValidFacelets == targetFacelets
            && !isDeviated
    }

    var verifiedMoveCount: Int {
        completedTokenIndices.count
    }

    var currentMoveTokenIndex: Int? {
        guard !isDeviated, !isComplete else { return nil }
        if let partialIndex = partialCompletionMoves.keys.min() {
            return partialIndex
        }
        return tokens.indices.first { !completedTokenIndices.contains($0) }
    }

    var partialHalfTurnPresentation: SmartCubePartialHalfTurnPresentation? {
        guard let index = partialCompletionMoves.keys.min(),
              let completedQuarterTurn = partialCompletionMoves[index]
        else { return nil }
        return SmartCubePartialHalfTurnPresentation(
            tokenIndex: index,
            targetMove: tokens[index],
            completedQuarterTurn: completedQuarterTurn
        )
    }

    var recoveryCheckpoints: [SmartCubeRecoveryCheckpoint] {
        var checkpoints = validCheckpoints.reduce(into: [String: SmartCubeRecoveryCheckpoint]()) {
            result, entry in
            result[entry.key] = SmartCubeRecoveryCheckpoint(
                facelets: entry.key,
                completedTokenIndices: entry.value.completedTokenIndices,
                partialCompletionMoves: entry.value.partialCompletionMoves,
                totalTokenCount: tokens.count
            )
        }

        for (facelets, state) in originalCheckpoints {
            let checkpoint = SmartCubeRecoveryCheckpoint(
                facelets: facelets,
                completedTokenIndices: state.completedTokenIndices,
                partialCompletionMoves: state.partialCompletionMoves,
                totalTokenCount: tokens.count
            )
            if let existing = checkpoints[checkpoint.facelets],
               existing.progressScore >= checkpoint.progressScore {
                continue
            }
            checkpoints[checkpoint.facelets] = checkpoint
        }

        return checkpoints.values.sorted {
            if $0.progressScore != $1.progressScore {
                return $0.progressScore > $1.progressScore
            }
            return $0.facelets < $1.facelets
        }
    }

    func guaranteedRecoveryPlan(
        identity: SmartCubeRecoveryPlanIdentity,
        sourceFacelets: String
    ) -> SmartCubeRecoveryPlan? {
        guard isDeviated,
              let deviationTrail,
              deviationTrail.faceletStates.last == sourceFacelets
        else { return nil }

        let checkpoint = SmartCubeRecoveryCheckpoint(
            facelets: deviationTrail.checkpointFacelets,
            completedTokenIndices: deviationTrail.checkpointState.completedTokenIndices,
            partialCompletionMoves: deviationTrail.checkpointState.partialCompletionMoves,
            totalTokenCount: tokens.count
        )
        return SmartCubeRecoveryEngine.guaranteedTrailPlan(
            identity: identity,
            sourceFacelets: sourceFacelets,
            deviationMoves: deviationTrail.moves,
            checkpoint: checkpoint
        )
    }

    var deviationMoves: [String] {
        deviationTrail?.moves ?? []
    }

    mutating func breakContinuity(at facelets: String?) {
        deviationTrail = nil
        isDeviated = true
        if let facelets {
            // A known checkpoint may establish a new starting state, never a
            // fictitious path through the missing moves.
            _ = updateState(with: facelets)
        }
    }

    mutating func update(
        with facelets: String,
        canonicalMove: String? = nil
    ) -> SmartCubeScrambleMatch {
        let previousFacelets = deviationTrail?.faceletStates.last ?? lastValidFacelets
        let previousWasDeviated = isDeviated
        let match = updateState(with: facelets)

        guard isDeviated else {
            deviationTrail = nil
            return match
        }

        if !previousWasDeviated {
            deviationTrail = DeviationTrail(
                checkpointFacelets: lastValidFacelets,
                checkpointState: verificationState,
                moves: [],
                faceletStates: [lastValidFacelets]
            )
        }

        if let canonicalMove {
            recordDeviationMove(
                canonicalMove,
                from: previousFacelets,
                to: facelets
            )
        }
        return match
    }

    private mutating func recordDeviationMove(
        _ canonicalMove: String,
        from previousFacelets: String,
        to sourceFacelets: String
    ) {
        guard var trail = deviationTrail else { return }

        let trailSource = trail.faceletStates.last ?? trail.checkpointFacelets
        if trailSource == sourceFacelets {
            return
        }

        let actualPrevious = previousFacelets == sourceFacelets ? trailSource : previousFacelets
        guard actualPrevious == trailSource,
              SmartCubeBluetoothManager.facelets(
                trailSource,
                applying: canonicalMove
              ) == sourceFacelets
        else { return }

        if let earlierStateIndex = trail.faceletStates.lastIndex(of: sourceFacelets) {
            trail.moves.removeSubrange(earlierStateIndex...)
            trail.faceletStates.removeSubrange((earlierStateIndex + 1)...)
        } else {
            trail.moves.append(canonicalMove)
            trail.faceletStates.append(sourceFacelets)
        }
        deviationTrail = trail
    }

    private mutating func updateState(with facelets: String) -> SmartCubeScrambleMatch {
        if let checkpoint = validCheckpoints[facelets] {
            let previous = verificationState
            let wasDeviated = isDeviated
            completedTokenIndices = checkpoint.completedTokenIndices
            partialCompletionMoves = checkpoint.partialCompletionMoves
            lastValidFacelets = facelets
            isDeviated = false
            highestVerifiedMoveCount = max(highestVerifiedMoveCount, completedTokenIndices.count)
            if isComplete { return .completed }
            if wasDeviated || checkpoint != previous { return .returned }
            return .unchanged
        }

        let firstRemainingIndex = tokens.indices.first { !completedTokenIndices.contains($0) }
        let completionCandidates = tokens.indices.filter { index in
            guard !completedTokenIndices.contains(index) else { return false }
            let move = partialCompletionMoves[index] ?? tokens[index]
            guard SmartCubeBluetoothManager.facelets(lastValidFacelets, applying: move) == facelets else {
                return false
            }

            var candidateState = verificationState
            candidateState.completedTokenIndices.insert(index)
            candidateState.partialCompletionMoves[index] = nil
            return canReachTarget(from: facelets, state: candidateState)
        }

        if let matchedIndex = completionCandidates.first {
            completedTokenIndices.insert(matchedIndex)
            partialCompletionMoves[matchedIndex] = nil
            highestVerifiedMoveCount = max(highestVerifiedMoveCount, completedTokenIndices.count)
            recordCheckpoint(facelets)

            if isComplete { return .completed }
            return matchedIndex == firstRemainingIndex ? .advanced : .matchedLater
        }

        let partialCandidates = tokens.indices.compactMap { index -> (Int, String)? in
            guard !completedTokenIndices.contains(index),
                  partialCompletionMoves[index] == nil,
                  let quarterTurns = halfTurnQuarterTurns(for: tokens[index])
            else { return nil }

            for quarterTurn in quarterTurns {
                guard SmartCubeBluetoothManager.facelets(lastValidFacelets, applying: quarterTurn) == facelets else {
                    continue
                }
                var candidateState = verificationState
                candidateState.partialCompletionMoves[index] = quarterTurn
                if canReachTarget(from: facelets, state: candidateState) {
                    return (index, quarterTurn)
                }
            }
            return nil
        }

        guard let partialCandidate = partialCandidates.first else {
            if isDeviated, let checkpoint = originalCheckpoints[facelets] {
                completedTokenIndices = checkpoint.completedTokenIndices
                partialCompletionMoves = checkpoint.partialCompletionMoves
                highestVerifiedMoveCount = max(highestVerifiedMoveCount, completedTokenIndices.count)
                recordCheckpoint(facelets)
                return isComplete ? .completed : .returned
            }
            isDeviated = true
            return .deviated
        }

        partialCompletionMoves[partialCandidate.0] = partialCandidate.1
        recordCheckpoint(facelets)
        return .partial
    }

    private var verificationState: VerificationState {
        VerificationState(
            completedTokenIndices: completedTokenIndices,
            partialCompletionMoves: partialCompletionMoves
        )
    }

    private var originalCheckpoints: [String: VerificationState] {
        var checkpoints: [String: VerificationState] = [:]
        for moveCount in 0...tokens.count {
            let state = VerificationState(
                completedTokenIndices: Set(tokens.indices.prefix(moveCount)),
                partialCompletionMoves: [:]
            )
            let facelets = expectedFacelets[moveCount]
            if let existing = checkpoints[facelets],
               existing.completedTokenIndices.count >= state.completedTokenIndices.count {
                continue
            }
            checkpoints[facelets] = state
        }
        return checkpoints
    }

    private func canReachTarget(
        from facelets: String,
        state: VerificationState
    ) -> Bool {
        var projectedFacelets = facelets
        for index in tokens.indices where !state.completedTokenIndices.contains(index) {
            let move = state.partialCompletionMoves[index] ?? tokens[index]
            guard let next = SmartCubeBluetoothManager.facelets(
                projectedFacelets,
                applying: move
            ) else { return false }
            projectedFacelets = next
        }
        return projectedFacelets == targetFacelets
    }

    private mutating func recordCheckpoint(_ facelets: String) {
        lastValidFacelets = facelets
        validCheckpoints[facelets] = verificationState
        isDeviated = false
        deviationTrail = nil
    }

    private func halfTurnQuarterTurns(for token: String) -> [String]? {
        guard token.count == 2,
              token.last == "2",
              let face = token.first,
              "UDRLFB".contains(face)
        else { return nil }
        return [String(face), String(face) + "'"]
    }

    private var targetFacelets: String {
        expectedFacelets[expectedFacelets.index(before: expectedFacelets.endIndex)]
    }
}

nonisolated enum SmartCubeSolvePhase: Equatable {
    case scrambling
    case ready
    case inspecting
    case timing
}

nonisolated enum SmartCubeSolveAction: Equatable {
    case none
    case beginInspection
    case enteredReady
    case startTiming(SmartCubeMoveEvent)
}

nonisolated enum SmartCubeTimerEventPolicy {
    static func effectiveEvent(
        normalEvent: PuzzleEvent,
        isSmartCubeTiming: Bool
    ) -> PuzzleEvent {
        isSmartCubeTiming ? .threeByThree : normalEvent
    }
}

enum SmartCubeCanonicalConsumption {
    case ignored
    case move(SmartCubeCanonicalUpdate)
    case boundary(SmartCubeContinuityReason, String?)
}

struct SmartCubeScrambleEpoch: Equatable {
    private(set) var establishedAt: Date?
    private(set) var baselineMoveID: UUID?
    private(set) var hasAcceptedPhysicalMove = false
    private(set) var recoveryScrambleID = UUID()
    private(set) var recoveryStateVersion: UInt64 = 0
    private(set) var consumedCanonicalSequence: UInt64 = 0

    var currentRecoveryIdentity: SmartCubeRecoveryPlanIdentity {
        SmartCubeRecoveryPlanIdentity(
            scrambleEpochID: recoveryScrambleID,
            stateVersion: recoveryStateVersion
        )
    }

    mutating func establish(at date: Date, latestMoveID: UUID?, canonicalSequence: UInt64 = 0) {
        establishedAt = date
        baselineMoveID = latestMoveID
        hasAcceptedPhysicalMove = false
        recoveryScrambleID = UUID()
        recoveryStateVersion = 0
        consumedCanonicalSequence = canonicalSequence
    }

    mutating func reset() {
        consumedCanonicalSequence = 0
        establishedAt = nil
        baselineMoveID = nil
        hasAcceptedPhysicalMove = false
        recoveryScrambleID = UUID()
        recoveryStateVersion = 0
    }

    mutating func advanceRecoveryStateVersion() -> SmartCubeRecoveryPlanIdentity {
        recoveryStateVersion &+= 1
        return currentRecoveryIdentity
    }

    @discardableResult
    mutating func consume(_ update: SmartCubeCanonicalUpdate) -> Bool {
        guard update.sequence > consumedCanonicalSequence else { return false }
        consumedCanonicalSequence = update.sequence
        return observePhysicalMove(update.move)
    }

    mutating func consumeEvent(_ event: SmartCubeCanonicalEvent) -> SmartCubeCanonicalConsumption {
        guard event.sequence > consumedCanonicalSequence else { return .ignored }
        let isTruncated = event.sequence - consumedCanonicalSequence > 1
        switch event {
        case .boundary(let boundary):
            consumedCanonicalSequence = boundary.sequence
            hasAcceptedPhysicalMove = false
            _ = advanceRecoveryStateVersion()
            return .boundary(boundary.reason, boundary.facelets)
        case .move(let update):
            if isTruncated || !update.isStateTrusted {
                consumedCanonicalSequence = update.sequence
                hasAcceptedPhysicalMove = false
                _ = advanceRecoveryStateVersion()
                return .boundary(
                    isTruncated ? .truncatedHistory : .historyGap,
                    update.isStateTrusted ? update.facelets : nil
                )
            }
            return consume(update) ? .move(update) : .ignored
        }
    }

    @discardableResult
    mutating func observePhysicalMove(_ move: SmartCubeMoveEvent) -> Bool {
        guard let establishedAt,
              move.id != baselineMoveID,
              move.localTimestamp >= establishedAt
        else { return false }
        hasAcceptedPhysicalMove = true
        return true
    }

    func completionAction(
        inspectionEnabled: Bool,
        completingMoveID: UUID?,
        lifecycle: inout SmartCubeSolveLifecycle
    ) -> SmartCubeSolveAction {
        guard hasAcceptedPhysicalMove else { return .none }
        return lifecycle.scrambleDidComplete(
            inspectionEnabled: inspectionEnabled,
            completingMoveID: completingMoveID
        )
    }
}

@MainActor
final class SmartCubeTimerPresentationStore {
    struct Snapshot: Equatable {
        let scramble: String
        let progress: SmartCubeScrambleProgress
        let epoch: SmartCubeScrambleEpoch
        let recoveryState: SmartCubeRecoveryPresentationState
    }

    static let shared = SmartCubeTimerPresentationStore()

    private(set) var snapshot: Snapshot?

    func save(
        scramble: String,
        progress: SmartCubeScrambleProgress,
        epoch: SmartCubeScrambleEpoch,
        recoveryState: SmartCubeRecoveryPresentationState
    ) {
        snapshot = Snapshot(
            scramble: scramble,
            progress: progress,
            epoch: epoch,
            recoveryState: recoveryState
        )
    }

    func snapshot(matching scramble: String) -> Snapshot? {
        guard snapshot?.scramble == scramble else { return nil }
        return snapshot
    }

    func clear() {
        snapshot = nil
    }
}

struct SmartCubeSolveLifecycle: Equatable {
    private(set) var phase: SmartCubeSolvePhase = .scrambling
    private(set) var completingMoveID: UUID?

    mutating func reset() {
        phase = .scrambling
        completingMoveID = nil
    }

    mutating func scrambleDidComplete(
        inspectionEnabled: Bool,
        completingMoveID: UUID?
    ) -> SmartCubeSolveAction {
        guard phase == .scrambling else { return .none }
        self.completingMoveID = completingMoveID
        if inspectionEnabled {
            phase = .inspecting
            return .beginInspection
        }
        phase = .ready
        return .enteredReady
    }

    mutating func physicalMoveDidOccur(
        _ move: SmartCubeMoveEvent
    ) -> SmartCubeSolveAction {
        guard move.id != completingMoveID else { return .none }
        switch phase {
        case .ready, .inspecting:
            phase = .timing
            return .startTiming(move)
        case .scrambling, .timing:
            return .none
        }
    }

    mutating func solveDidFinish() {
        phase = .scrambling
        completingMoveID = nil
    }
}

nonisolated struct SmartCubeSolveTiming: Equatable {
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval

    static func resolved(
        startMove: SmartCubeMoveEvent,
        endMove: SmartCubeMoveEvent?,
        solvedObservedAt: Date
    ) -> Self? {
        let reportedEndDate = endMove?.localTimestamp ?? solvedObservedAt

        if let endMove,
           startMove.timestampSource == .deviceClock,
           endMove.timestampSource == .deviceClock,
           let startMilliseconds = startMove.cubeTimestampMilliseconds,
           let endMilliseconds = endMove.cubeTimestampMilliseconds,
           let milliseconds = positiveDeviceDelta(
               from: startMilliseconds,
               to: endMilliseconds
           ) {
            return Self(
                startDate: startMove.localTimestamp,
                endDate: reportedEndDate,
                duration: TimeInterval(milliseconds) / 1_000
            )
        }

        let endDate = reportedEndDate > startMove.localTimestamp
            ? reportedEndDate
            : solvedObservedAt
        let fallbackDuration = endDate.timeIntervalSince(startMove.localTimestamp)
        guard fallbackDuration > 0, fallbackDuration.isFinite else { return nil }
        return Self(
            startDate: startMove.localTimestamp,
            endDate: endDate,
            duration: fallbackDuration
        )
    }

    static func positiveDeviceDelta(from start: Int, to end: Int) -> Int? {
        let direct = end - start
        if direct > 0 { return direct }

        let modulus = Int(UInt32.max) + 1
        let wrapped = end + modulus - start
        guard start >= 0, end >= 0, wrapped > 0, wrapped < modulus / 2 else { return nil }
        return wrapped
    }
}
#endif

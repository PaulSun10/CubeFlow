#if os(iOS)
import SwiftUI
import Combine

enum LocalBattleInput: String, CaseIterable, Identifiable {
    case touch, manual, smartCube, smartTimer
    var id: String { rawValue }
    var key: String { self == .smartTimer ? "connected_devices.smart_timer" : "battle.input.\(rawValue)" }
}

struct LocalBattleHandicap: Equatable {
    private(set) var first = 0

    func seconds(for player: LocalBattlePlayer) -> Int { player == .first ? first : -first }

    mutating func set(_ seconds: Int, for player: LocalBattlePlayer) {
        let value = min(10, max(-10, seconds))
        first = player == .first ? value : -value
    }

    func adjusted(_ raw: Double, for player: LocalBattlePlayer) -> Double {
        raw + Double(max(0, seconds(for: player)))
    }
}

struct LocalBattleConfiguration: Equatable {
    var input = LocalBattleInput.touch
    var deviceID: UUID?
    var format = ManualTimeFormat.defaultFormat
}

/// Per-player subscriptions never route through Timer's globally selected cube.
/// Timer remains the timing/scoring owner; this object emits only validated intents.
@MainActor final class LocalBattleDevices: ObservableObject {
    @Published private(set) var configurations: [LocalBattlePlayer: LocalBattleConfiguration] = [:]
    @Published private(set) var ready: Set<LocalBattlePlayer> = []
    var start: ((LocalBattlePlayer, Date) -> Bool)?
    var finish: ((LocalBattlePlayer, Date) -> Void)?
    var invalidate: ((LocalBattlePlayer) -> Void)?
    var finishSmartTimer: ((LocalBattlePlayer, GANTimerCompletedSolve) -> Void)?
    private let manager: SmartCubeBluetoothManager
    private struct Target {
        let assignment: UUID
        let text: String
        let progress: SmartCubeScrambleProgress
    }
    private var targets: [LocalBattlePlayer: Target] = [:]
    private var bindings: [LocalBattlePlayer: UUID] = [:]
    private var subscriptions: [LocalBattlePlayer: Set<AnyCancellable>] = [:]
    private var sequences: [LocalBattlePlayer: UInt64] = [:]
    private var started: Set<LocalBattlePlayer> = []
    private var finished: Set<LocalBattlePlayer> = []
    private var roundHasStarted = false
    private var enabled = false
    private var timerEligibleSince = Date.distantFuture
    private var timerWasRunning = false
    private var timerRun: (player: LocalBattlePlayer, latestHardwareStart: Date)?
    init(manager: SmartCubeBluetoothManager? = nil) { self.manager = manager ?? .shared }
    func configuration(_ player: LocalBattlePlayer) -> LocalBattleConfiguration { configurations[player] ?? .init() }
    func setConfiguration(_ value: LocalBattleConfiguration, for player: LocalBattlePlayer) {
        guard timerRun?.player != player, !started.contains(player) || finished.contains(player) else { return }
        var value = value
        if value.input != .smartCube { value.deviceID = nil }
        if value.input == .smartTimer, !canUseSmartTimer(for: player) { return }
        if let id = value.deviceID, configurations[other(player)]?.deviceID == id { return }
        guard configuration(player) != value else { return }
        if value.input == .smartTimer && configuration(player).input != .smartTimer { timerEligibleSince = .now }
        configurations[player] = value
        bind(player)
    }
    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value; subscriptions = [:]; bindings = [:]; ready = []; started = []; finished = []
        timerRun = nil
        timerWasRunning = false
        timerEligibleSince = .now
        roundHasStarted = false
        if value { LocalBattlePlayer.allCases.forEach(bind) }
        else { targets = [:]; start = nil; finish = nil; invalidate = nil; finishSmartTimer = nil }
    }
    func setTarget(_ text: String?, event: PuzzleEvent, assignment: UUID?, for player: LocalBattlePlayer) {
        let size = event == .twoByTwo ? 2 : 3
        let supported = [.twoByTwo, .threeByThree, .threeByThreeOH, .threeByThreeBLD].contains(event)
        if let target = targets[player], target.assignment == assignment, target.text == text,
           supported, target.progress.puzzleSize == size { refreshReadiness(player); return }
        setReady(false, player: player)
        if supported, let text, let assignment, let progress = SmartCubeScrambleProgress(scramble: text, puzzleSize: size) {
            targets[player] = Target(assignment: assignment, text: text, progress: progress)
        } else { targets[player] = nil }
        refreshReadiness(player)
    }
    func complete(_ player: LocalBattlePlayer) { finished.insert(player); roundHasStarted = true }
    func nextRound() { started = []; finished = []; roundHasStarted = false; LocalBattlePlayer.allCases.forEach(refreshReadiness) }
    func canUseSmartCube(_ event: PuzzleEvent) -> Bool { [.twoByTwo, .threeByThree, .threeByThreeOH, .threeByThreeBLD].contains(event) }
    func canUseSmartTimer(for player: LocalBattlePlayer) -> Bool { configuration(other(player)).input != .smartTimer }

    func receiveSmartTimerState(_ state: GANTimerConnectionState, startedAt: Date?) {
        guard enabled else { return }
        guard state == .running else {
            timerWasRunning = false
            if let run = timerRun {
                timerRun = nil
                invalidate?(run.player)
            }
            return
        }
        guard let startedAt else { return }
        if let run = timerRun {
            // The existing GAN parser re-stamps repeated running packets. Keep
            // the Battle clock running, but correlate the stop with that stamp.
            if startedAt > run.latestHardwareStart { timerRun = (run.player, startedAt) }
            return
        }
        guard !timerWasRunning else { return }
        timerWasRunning = true
        guard startedAt >= timerEligibleSince,
              let player = LocalBattlePlayer.allCases.first(where: { configuration($0).input == .smartTimer }),
              start?(player, startedAt) == true else { return }
        timerRun = (player, startedAt)
    }

    func receiveSmartTimerCompletion(_ solve: GANTimerCompletedSolve) {
        guard enabled, let run = timerRun, solve.startedAt == run.latestHardwareStart,
              solve.stoppedAt >= run.latestHardwareStart, solve.seconds.isFinite, solve.seconds > 0 else { return }
        timerRun = nil
        finishSmartTimer?(run.player, solve)
    }
    func devices(for event: PuzzleEvent, player: LocalBattlePlayer) -> [UUID] {
        manager.connectedDeviceIDs.filter { id in
            manager.session(for: id)?.puzzleSize == (event == .twoByTwo ? 2 : 3) && configuration(other(player)).deviceID != id
        }
    }
    func deviceName(_ id: UUID) -> String { manager.session(for: id)?.connectedDeviceName ?? SavedSmartCubeDevices.shared.device(id)?.displayName ?? "Smart Cube" }
    func session(for player: LocalBattlePlayer) -> SmartCubePeripheralSession? {
        guard configuration(player).input == .smartCube, let id = configuration(player).deviceID else { return nil }
        return manager.session(for: id)
    }

    private func bind(_ player: LocalBattlePlayer) {
        subscriptions[player] = nil; setReady(false, player: player)
        let binding = UUID(); bindings[player] = binding
        guard enabled, configuration(player).input == .smartCube,
              let id = configuration(player).deviceID, let session = manager.session(for: id) else { return }
        sequences[player] = session.canonicalSequence
        var tokens = Set<AnyCancellable>()
        session.canonicalEvents.sink { [weak self, weak session] event in
            guard let self, let session, self.bindings[player] == binding else { return }
            self.receive(event, player: player, session: session)
        }.store(in: &tokens)
        Publishers.CombineLatest3(session.$connectionState, session.$connectionAttemptID, session.$connectionPolicyResolvedAttemptID)
            .receive(on: DispatchQueue.main).sink { [weak self] state, attempt, resolved in
                guard let self, self.bindings[player] == binding else { return }
                // Do not lose a brief disconnect/policy transition by reading
                // only the session's newer state after this queued delivery.
                if state != .connected || attempt != resolved || !session.isReadyForMoveObservation { self.interrupt(player) }
                self.refreshReadiness(player)
            }.store(in: &tokens)
        subscriptions[player] = tokens
        refreshReadiness(player)
    }
    private func refreshReadiness(_ player: LocalBattlePlayer) {
        guard enabled, configuration(player).input == .smartCube,
              let id = configuration(player).deviceID, configuration(other(player)).deviceID != id,
              let session = manager.session(for: id), session.isReadyForMoveObservation,
              let state = session.facelets, let target = targets[player]?.progress,
              session.puzzleSize == target.puzzleSize,
              CubeStateEquivalence.matches(state, target.targetFacelets, puzzleSize: target.puzzleSize) else { setReady(false, player: player); return }
        setReady(true, player: player)
    }
    private func receive(_ event: SmartCubeCanonicalEvent, player: LocalBattlePlayer, session: SmartCubePeripheralSession) {
        guard enabled, event.sequence > (sequences[player] ?? 0) else { return }
        sequences[player] = event.sequence
        switch event {
        case .boundary:
            interrupt(player); refreshReadiness(player)
        case .move(let update):
            let bothSmart = LocalBattlePlayer.allCases.allSatisfy { configuration($0).input == .smartCube }
            let mayStart = ready.contains(player) && (!bothSmart || roundHasStarted || ready.count == 2)
            setReady(false, player: player)
            guard update.isStateTrusted, session.isReadyForMoveObservation else { interrupt(player); return }
            if !started.contains(player), !finished.contains(player), mayStart, start?(player, update.move.localTimestamp) == true {
                started.insert(player)
                roundHasStarted = true
            }
            if started.contains(player), !finished.contains(player), update.isSolved {
                finished.insert(player); finish?(player, update.move.localTimestamp)
            }
            if !started.contains(player) { refreshReadiness(player) }
        }
    }
    private func interrupt(_ player: LocalBattlePlayer) {
        setReady(false, player: player)
        if started.contains(player), !finished.contains(player) {
            started.remove(player); invalidate?(player)
        }
    }
    private func setReady(_ value: Bool, player: LocalBattlePlayer) {
        guard ready.contains(player) != value else { return }
        if value { ready.insert(player) } else { ready.remove(player) }
    }
    private func other(_ player: LocalBattlePlayer) -> LocalBattlePlayer { player == .first ? .second : .first }
}
#endif

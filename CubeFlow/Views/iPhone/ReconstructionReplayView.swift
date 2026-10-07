#if os(iOS)
import Combine
import SwiftUI

@MainActor
private final class ReconstructionReplayController: ObservableObject {
    let reconstruction: SolveReconstruction
    let events = PassthroughSubject<SmartCubeCanonicalEvent, Never>()
    @Published private(set) var facelets: String
    @Published private(set) var moveIndex = 0
    @Published private(set) var bindingID = UUID()
    @Published private(set) var stateRevision = 0
    @Published private(set) var isPlaying = false
    @Published var speed = 1.0
    private var playbackTask: Task<Void, Never>?

    init(reconstruction: SolveReconstruction) {
        self.reconstruction = reconstruction
        facelets = reconstruction.initialFacelets
    }

    deinit {
        playbackTask?.cancel()
    }

    var currentTimestamp: TimeInterval {
        guard moveIndex > 0 else { return 0 }
        return reconstruction.moves[moveIndex - 1].relativeTimestamp
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard !isPlaying, moveIndex < reconstruction.moves.count else { return }
        isPlaying = true
        playbackTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.moveIndex < self.reconstruction.moves.count {
                let next = self.reconstruction.moves[self.moveIndex]
                let previousTime = self.moveIndex == 0
                    ? 0
                    : self.reconstruction.moves[self.moveIndex - 1].relativeTimestamp
                let delay = max(0, next.relativeTimestamp - previousTime) / max(0.1, self.speed)
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                guard !Task.isCancelled else { break }
                self.stepForward()
            }
            self.isPlaying = false
        }
    }

    func pause() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }

    func stepForward() {
        guard moveIndex < reconstruction.moves.count else {
            pause()
            return
        }
        let storedMove = reconstruction.moves[moveIndex]
        guard let turn = CubeLayerTurn(storedMove.canonicalMove),
              let target = turn.applying(to: facelets, size: reconstruction.puzzleSize) else {
            pause()
            return
        }
        let event = SmartCubeMoveEvent(
            move: storedMove.canonicalMove,
            serial: nil,
            face: nil,
            direction: nil,
            localTimestamp: .now,
            cubeTimestampMilliseconds: storedMove.deviceTimestampMilliseconds,
            timestampSource: .hostReceipt
        )
        moveIndex += 1
        facelets = target
        events.send(.move(SmartCubeCanonicalUpdate(
            sequence: UInt64(moveIndex),
            move: event,
            facelets: target,
            isStateTrusted: true
        )))
    }

    func stepBackward() {
        seek(to: moveIndex - 1)
    }

    func seek(to requestedIndex: Int) {
        pause()
        let targetIndex = min(max(0, requestedIndex), reconstruction.moves.count)
        guard let target = reconstruction.facelets(afterMoveCount: targetIndex) else { return }
        moveIndex = targetIndex
        facelets = target
        stateRevision &+= 1
        bindingID = UUID()
    }
}

struct ReconstructionReplayView: View {
    @StateObject private var controller: ReconstructionReplayController
    let actualSolveDuration: TimeInterval?

    init(reconstruction: SolveReconstruction, actualSolveDuration: TimeInterval? = nil) {
        _controller = StateObject(wrappedValue: ReconstructionReplayController(reconstruction: reconstruction))
        self.actualSolveDuration = actualSolveDuration
    }

    var body: some View {
        VStack(spacing: 18) {
            SmartCube3DView(
                facelets: controller.facelets,
                stateRevision: controller.stateRevision,
                fixedView: .urf,
                cubeSize: controller.reconstruction.puzzleSize,
                events: controller.events.eraseToAnyPublisher(),
                connectionAttemptID: controller.bindingID,
                isStateTrusted: true,
                diagnosticOwner: "replay",
                animationTPSOverride: 10,
                temporaryVerticalPeek: true
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)

            HStack(spacing: 20) {
                if let actualSolveDuration, actualSolveDuration.isFinite, actualSolveDuration > 0 {
                    analysisMetric("Time", value: SolveMetrics.formatTime(actualSolveDuration, decimals: 2))
                }
                analysisMetric("Moves", value: "\(controller.reconstruction.moves.count)")
                if let actualSolveDuration,
                   let tps = controller.reconstruction.turnsPerSecond(actualDuration: actualSolveDuration) {
                    analysisMetric("TPS", value: String(format: "%.2f", tps))
                }
            }
            .frame(maxWidth: .infinity)

            if let metrics = controller.reconstruction.combinedTimingMetrics {
                timingSection(metrics)
            }

            VStack(spacing: 10) {
                HStack {
                    Text("Move \(controller.moveIndex) of \(controller.reconstruction.moves.count)")
                    Spacer()
                    Text(SolveMetrics.formatTime(controller.currentTimestamp, decimals: 3))
                        .monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))

                Slider(
                    value: Binding(
                        get: { Double(controller.moveIndex) },
                        set: { controller.seek(to: Int($0.rounded())) }
                    ),
                    in: 0...Double(max(1, controller.reconstruction.moves.count)),
                    step: 1
                )

                HStack(spacing: 28) {
                    Button { controller.stepBackward() } label: {
                        Image(systemName: "backward.end.fill")
                    }
                    .disabled(controller.moveIndex == 0)

                    Button { controller.togglePlayback() } label: {
                        Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Circle())
                    .disabled(controller.moveIndex == controller.reconstruction.moves.count && !controller.isPlaying)

                    Button { controller.stepForward() } label: {
                        Image(systemName: "forward.end.fill")
                    }
                    .disabled(controller.moveIndex == controller.reconstruction.moves.count)
                }

                Picker("Playback Speed", selection: $controller.speed) {
                    Text("0.5x").tag(0.5)
                    Text("1x").tag(1.0)
                    Text("2x").tag(2.0)
                }
                .pickerStyle(.segmented)
            }

            if controller.reconstruction.completeness == .incomplete {
                Text("Incomplete replay")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .navigationTitle("Replay")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { controller.pause() }
    }

    @ViewBuilder
    private func timingSection(_ metrics: SolveReconstruction.CombinedTimingMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timing")
                .font(.headline)
            if let startDelay = metrics.startDelay {
                timingRow("Start delay", value: startDelay)
            }
            if let stopDelay = metrics.stopDelay {
                timingRow("Stop delay", value: stopDelay)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timingRow(_ label: String, value: TimeInterval) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.2f s", value))
                .monospacedDigit()
        }
        .font(.subheadline)
    }

    private func analysisMetric(_ title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}
#endif

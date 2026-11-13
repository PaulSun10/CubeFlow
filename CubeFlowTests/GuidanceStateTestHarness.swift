#if os(iOS)
import SwiftUI
import Combine
@testable import CubeFlow

@MainActor final class GuidanceStateTestHarness: ObservableObject {
    @Published private(set) var target: String?
    @Published private(set) var route: SmartCubeReplacement?
    @Published private(set) var reached = false
    let guidance: SmartCubeGuidanceController
    private var epoch = UUID()
    private var version: UInt64 = 0
    private var source: String?
    private var device: UUID?
    private var attempt: UUID?
    private var sequence: UInt64 = 0
    private var trusted = false
    private var subscription: AnyCancellable?

    init(guidance: SmartCubeGuidanceController? = nil) {
        self.guidance = guidance ?? SmartCubeGuidanceController()
        subscription = self.guidance.$publication.sink { [weak self] publication in
            guard let self, self.trusted, let publication, let candidate = publication.decision.replacement,
                  candidate.identity == .init(scrambleEpochID: self.epoch, stateVersion: self.version),
                  candidate.sourceFacelets == self.source, candidate.targetFacelets == self.target,
                  publication.request.deviceID == self.device,
                  publication.request.canonicalSequence == self.sequence else { return }
            self.route = candidate
        }
    }

    func setScramble(_ text: String) {
        cancel(); epoch = UUID(); version = 0
        let moves = text.split(whereSeparator: \.isWhitespace).map(String.init)
        target = !moves.isEmpty && moves.count <= 120 && moves.allSatisfy(SmartCubeTargetPath.moves.contains)
            ? SmartCubeBluetoothManager.facelets(afterApplying: moves.joined(separator: " ")) : nil
    }

    func update(facelets: String?, trusted: Bool, deviceID: UUID?, attemptID: UUID?, sequence: UInt64) {
        guard source != facelets || device != deviceID || attempt != attemptID || self.sequence != sequence || self.trusted != trusted else { return }
        guidance.cancel(); route = nil; reached = false
        source = facelets; device = deviceID; attempt = attemptID; self.sequence = sequence; self.trusted = trusted; version &+= 1
        guard trusted, let source = facelets, source.count == 54, let target, deviceID != nil, attemptID != nil else { return }
        if source == target { reached = true; return }
        guidance.submit(.init(identity: .init(scrambleEpochID: epoch, stateVersion: version), sourceFacelets: source,
            targetFacelets: target, generation: 0, knownPath: nil, deviceID: deviceID, canonicalSequence: sequence))
    }

    func cancel() { guidance.cancel(); route = nil; source = nil; reached = false }
}

#endif

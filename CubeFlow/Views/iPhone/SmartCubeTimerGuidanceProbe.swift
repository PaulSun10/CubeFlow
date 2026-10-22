#if os(iOS) && DEBUG
import SwiftUI

/// Test observation/actions on the actual mounted Timer, not a second guidance
/// harness. No effect unless explicitly supplied by a test's environment.
@MainActor final class SmartCubeTimerGuidanceProbe {
    struct Snapshot {
        let scramble: String
        let sessionID: UUID?
        let event: PuzzleEvent
        let assignment: TimerSolveAssignment?
        let progress: SmartCubeScrambleProgress?
        let recovery: SmartCubeRecoveryPresentationState
        let request: SmartCubeGuidanceController.Request?
        let identity: SmartCubeRecoveryPlanIdentity
        var diagram: ScrambleDiagramSnapshot? = nil
        var prefetchIsReady: Bool = false
    }
    var prepare: ((String) -> Void)?
    var snapshot: (() -> Snapshot)?
    var displayedPathText: String?
    var next: (() -> Void)?
    var start: (() -> Void)?
    var finish: ((Double) -> Void)?
    var stop: ((Double) -> Void)?
    var save: (() -> Void)?
    var selectEvent: ((PuzzleEvent) -> Void)?
    var generate: ((TimerScrambleGenerationContext, String,
                    @escaping @MainActor (TimerScrambleGenerationPayload) -> Void) -> Void)?
    func reset() {
        prepare = nil; snapshot = nil; displayedPathText = nil; next = nil; start = nil; finish = nil
        stop = nil; save = nil; selectEvent = nil; generate = nil
    }
}
private struct SmartCubeTimerGuidanceProbeKey: EnvironmentKey {
    static let defaultValue: SmartCubeTimerGuidanceProbe? = nil
}
extension EnvironmentValues {
    var smartCubeTimerGuidanceProbe: SmartCubeTimerGuidanceProbe? {
        get { self[SmartCubeTimerGuidanceProbeKey.self] }
        set { self[SmartCubeTimerGuidanceProbeKey.self] = newValue }
    }
}
#endif

#if os(iOS)
import SwiftUI

struct TimerPBCelebration: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").foregroundStyle(.orange)
            Text("timer.personal_best").foregroundStyle(Color.accentColor)
        }
        .font(.subheadline.weight(.semibold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("timer.personal_best"))
    }
}

/// Keeps the upstream Default Rain emitter, not a Canvas approximation.
struct TimerPBConfetti: View {
    var onFinished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !reduceMotion && scenePhase == .active {
                TimerPBDefaultRain(onFinished: onFinished).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .onAppear { if reduceMotion { onFinished() } }
        .onChange(of: reduceMotion) { if $0 { onFinished() } }
    }
}

private struct TimerPBDefaultRain: UIViewRepresentable {
    let onFinished: () -> Void

    func makeCoordinator() -> TimerPBConfettiLifecycle { TimerPBConfettiLifecycle() }

    func makeUIView(context: Context) -> SwiftConfettiView {
        let view = SwiftConfettiView(frame: .zero)
        view.applyPreset(.rain)
        view.colors = [
            UIColor(red: 1, green: 0.16, blue: 0.25, alpha: 1),
            UIColor(red: 1, green: 0.73, blue: 0.02, alpha: 1),
            UIColor(red: 0.04, green: 0.83, blue: 0.35, alpha: 1),
            UIColor(red: 0.02, green: 0.53, blue: 1, alpha: 1),
            UIColor(red: 0.83, green: 0.10, blue: 0.87, alpha: 1)
        ]
        view.playSound = false
        view.hapticFeedback = false
        view.startConfetti()
        context.coordinator.start(view: view, onFinished: onFinished)
        return view
    }

    func updateUIView(_ view: SwiftConfettiView, context: Context) {}

    static func dismantleUIView(_ view: SwiftConfettiView, coordinator: TimerPBConfettiLifecycle) {
        coordinator.cancel()
        view.cancelConfetti()
    }
}

@MainActor
final class TimerPBConfettiLifecycle {
    private(set) var task: Task<Void, Never>?
    private weak var view: SwiftConfettiView?

    func start(view: SwiftConfettiView, emissionDuration: TimeInterval = 3.2, onFinished: @escaping () -> Void) {
        cancel()
        self.view = view
        task = Task { @MainActor [weak self, weak view] in
            do {
                try await Task.sleep(nanoseconds: UInt64(emissionDuration * 1_000_000_000))
                guard let drain = view?.stopEmissionAndDrain() else { return }
                // One display-frame margin after the last possible particle expiration.
                try await Task.sleep(nanoseconds: UInt64((drain + 0.1) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                view?.cancelConfetti()
                self?.task = nil
                self?.view = nil
                onFinished()
            } catch { }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        view?.cancelConfetti()
        view = nil
    }
}
#endif

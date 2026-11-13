#if os(iOS)
import SwiftUI
import UIKit

/// Direct contact delivery, without DragGesture's recognition/update batching.
struct BattleContactSurface: UIViewRepresentable {
    let changed: (Bool, Bool) -> Void
    func makeUIView(context: Context) -> ContactView { ContactView() }
    func updateUIView(_ view: ContactView, context: Context) { view.changed = changed }
    static func dismantleUIView(_ view: ContactView, coordinator: ()) { view.finish(cancelled: true) }

    final class ContactView: UIView {
        var changed: ((Bool, Bool) -> Void)?
        private(set) var isContactActive = false
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isMultipleTouchEnabled = false
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func begin() {
            guard !isContactActive else { return }
            isContactActive = true
            changed?(true, false)
        }
        func finish(cancelled: Bool) {
            guard isContactActive else { return }
            isContactActive = false
            changed?(false, cancelled)
        }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { begin() }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(cancelled: false) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(cancelled: true) }
        override func didMoveToWindow() { if window == nil { finish(cancelled: true) } }
    }
}

@MainActor final class TimerReadyFeedback {
    static let shared = TimerReadyFeedback()
    // Same rigid, full-intensity feedback for regular and battle timers; retain
    // and prepare the engine instead of allocating it at the contact boundary.
    private let generator = UIImpactFeedbackGenerator(style: .rigid)
    func prepare() { generator.prepare() }
    func impact() { generator.impactOccurred(intensity: 1); generator.prepare() }
}
#endif

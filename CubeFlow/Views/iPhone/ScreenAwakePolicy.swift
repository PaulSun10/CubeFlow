#if os(iOS)
import SwiftUI
import UIKit

enum ScreenAwakePreference {
    static let key = "keepScreenAwake"
    static let defaultValue = true

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
    }
}

/// One writer for the application-wide idle timer. Each mounted scene contributes independently.
@MainActor final class ScreenAwakeCoordinator {
    static let shared = ScreenAwakeCoordinator(defaults: .standard) {
        UIApplication.shared.isIdleTimerDisabled = $0
    }

    private let defaults: UserDefaults
    private let write: (Bool) -> Void
    private var scenes: [UUID: Bool] = [:]
    private var applied = false

    init(defaults: UserDefaults, write: @escaping (Bool) -> Void) {
        self.defaults = defaults
        self.write = write
    }

    func register(eligible: Bool) -> UUID {
        let id = UUID()
        scenes[id] = eligible
        reconcile()
        return id
    }

    func update(_ id: UUID, eligible: Bool) {
        guard scenes[id] != nil else { return }
        scenes[id] = eligible
        reconcile()
    }

    func unregister(_ id: UUID) {
        scenes[id] = nil
        reconcile()
    }

    private func reconcile() {
        // Read the common preference, not the first scene's cached AppStorage value.
        // A toggle must take effect even before the remaining scenes update.
        let desired = ScreenAwakePreference.isEnabled(in: defaults) && scenes.values.contains(true)
        guard desired != applied else { return }
        applied = desired
        write(desired)
    }
}

struct ScreenAwakeScenePolicy: ViewModifier {
    let timerSelected: Bool
    let coordinator: ScreenAwakeCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ScreenAwakePreference.key) private var enabled = ScreenAwakePreference.defaultValue

    func body(content: Content) -> some View {
        content.background {
            ScreenAwakeSceneRegistration(
                owner: coordinator, eligible: enabled && timerSelected && scenePhase == .active
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Root lifetime, not visibility callbacks from views covered by a sheet or replaced by Battle.
private struct ScreenAwakeSceneRegistration: UIViewRepresentable {
    let owner: ScreenAwakeCoordinator
    let eligible: Bool

    final class Coordinator {
        let owner: ScreenAwakeCoordinator
        var id: UUID?
        init(owner: ScreenAwakeCoordinator) { self.owner = owner }
    }

    func makeCoordinator() -> Coordinator { Coordinator(owner: owner) }

    func makeUIView(context: Context) -> UIView {
        context.coordinator.id = owner.register(eligible: eligible)
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let id = context.coordinator.id else { return }
        owner.update(id, eligible: eligible)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        guard let id = coordinator.id else { return }
        coordinator.id = nil
        coordinator.owner.unregister(id)
    }
}
#endif

import SwiftUI
import UIKit

#if os(iOS)
struct SpacebarKeyCommandHandler: UIViewControllerRepresentable {
    let onSpaceDown: () -> Void
    let onSpaceUp: () -> Void
    let onSpaceTap: () -> Void

    func makeUIViewController(context: Context) -> SpacebarKeyCommandViewController {
        let controller = SpacebarKeyCommandViewController()
        controller.onSpaceDown = onSpaceDown
        controller.onSpaceUp = onSpaceUp
        controller.onSpaceTap = onSpaceTap
        return controller
    }

    func updateUIViewController(_ uiViewController: SpacebarKeyCommandViewController, context: Context) {
        uiViewController.onSpaceDown = onSpaceDown
        uiViewController.onSpaceUp = onSpaceUp
        uiViewController.onSpaceTap = onSpaceTap
    }
}

final class SpacebarKeyCommandViewController: UIViewController {
    var onSpaceDown: (() -> Void)?
    var onSpaceUp: (() -> Void)?
    var onSpaceTap: (() -> Void)?

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if shouldAutomaticallyBecomeFirstResponder {
            becomeFirstResponder()
        }
    }

    private var shouldAutomaticallyBecomeFirstResponder: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    override var keyCommands: [UIKeyCommand]? {
        let command = UIKeyCommand(
            input: " ",
            modifierFlags: [],
            action: #selector(spacePressed)
        )
        command.discoverabilityTitle = "Start/Stop Timer"
        return [command]
    }

    @objc private func spacePressed() {
        onSpaceTap?()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.key?.charactersIgnoringModifiers == " " }) {
            onSpaceDown?()
            return
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.key?.charactersIgnoringModifiers == " " }) {
            onSpaceUp?()
            return
        }
        super.pressesEnded(presses, with: event)
    }
}
#endif

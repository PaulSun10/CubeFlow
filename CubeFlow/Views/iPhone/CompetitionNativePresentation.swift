import SwiftUI
import UIKit
import Combine

struct CompetitionResultBackdrop: View {
    var body: some View { Color.black.opacity(0.42) }
}

enum CompetitionResultCardGeometry {
    static func width(in size: CGSize) -> CGFloat { min(max(size.width - 32, 280), 430) }
    static func maximumHeight(in size: CGSize) -> CGFloat { min(max(size.height - 64, 180), 680) }
}

private struct CompetitionResultCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.55), lineWidth: 0.5)
            }
    }
}

struct CompetitionResultCardCloseButton: View {
    let label: String
    let action: () -> Void
    @ViewBuilder var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Image(systemName: "xmark").font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary).frame(width: 38, height: 38)
                    .contentShape(Circle()).glassEffect(.regular.interactive(), in: .circle)
            }.buttonStyle(.plain).frame(width: 44, height: 44).accessibilityLabel(label)
        } else {
            Button(action: action) {
                Image(systemName: "xmark").font(.body.weight(.semibold))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel(label)
        }
    }
}

private struct CompetitionProfilePresenterKey: EnvironmentKey {
    static let defaultValue: ((String, String) -> Void)? = nil
}
extension EnvironmentValues {
    var competitionProfilePresenter: ((String, String) -> Void)? {
        get { self[CompetitionProfilePresenterKey.self] }
        set { self[CompetitionProfilePresenterKey.self] = newValue }
    }
}

@MainActor final class CompetitionResultCardMotion: ObservableObject {
    @Published var visible = false
    func setVisible(_ value: Bool, reduceMotion: Bool) {
        withAnimation(reduceMotion ? nil : (value ? .easeOut(duration: 0.18) : .easeIn(duration: 0.16))) {
            visible = value
        }
    }
}
private struct CompetitionResultCardMotionKey: EnvironmentKey {
    static let defaultValue: CompetitionResultCardMotion? = nil
}
extension EnvironmentValues {
    var competitionResultCardMotion: CompetitionResultCardMotion? {
        get { self[CompetitionResultCardMotionKey.self] }
        set { self[CompetitionResultCardMotionKey.self] = newValue }
    }
}
private struct CompetitionMovingCard<Content: View>: View {
    @ObservedObject var motion: CompetitionResultCardMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let content: Content
    var body: some View { content.scaleEffect(reduceMotion || motion.visible ? 1 : 0.97) }
}
private struct CompetitionResultMotionModifier: ViewModifier {
    @Environment(\.competitionResultCardMotion) private var motion
    @ViewBuilder func body(content: Content) -> some View {
        if let motion { CompetitionMovingCard(motion: motion, content: content) }
        else { content }
    }
}
extension View {
    func competitionResultCardMotion() -> some View { modifier(CompetitionResultMotionModifier()) }
    func competitionResultCardSurface() -> some View { modifier(CompetitionResultCardSurface()) }
    func competitionResultCardShadow() -> some View { shadow(color: .black.opacity(0.24), radius: 24, y: 10) }
}

/// One native presentation owner. Reopening during dismissal waits for UIKit's
/// completion, not a timer or a second presentation controller.
struct CompetitionNativePresentation<Content: View>: UIViewRepresentable {
    typealias Style = CompetitionNativePresentationStyle
    typealias Coordinator = CompetitionPresentationCoordinator
    @Binding var isPresented: Bool
    let style: Style
    @ViewBuilder let content: (@escaping () -> Void) -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> Anchor {
        let view = Anchor()
        view.isUserInteractionEnabled = false
        view.ready = { [weak coordinator = context.coordinator] in coordinator?.reconcile() }
        context.coordinator.anchor = view
        return view
    }
    func updateUIView(_ view: Anchor, context: Context) {
        let coordinator = context.coordinator
        coordinator.binding = $isPresented
        coordinator.style = style
        coordinator.makeContent = { [weak coordinator] in
            AnyView(content { coordinator?.requestDismissal() })
        }
        coordinator.desired = isPresented
        if let host = coordinator.host, coordinator.desired, !coordinator.dismissing {
            host.rootView = coordinator.rootContent()
        }
        coordinator.reconcile()
    }
    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) {
        view.ready = nil
        coordinator.desired = false
        coordinator.binding = nil
        coordinator.reconcile()
    }

    final class Anchor: UIView {
        var ready: (() -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); ready?() }
    }

}

enum CompetitionNativePresentationStyle { case results }

@MainActor final class CompetitionPresentationCoordinator: NSObject, UIAdaptivePresentationControllerDelegate, UIViewControllerTransitioningDelegate {
    weak var anchor: UIView?
    var binding: Binding<Bool>?
    var style: CompetitionNativePresentationStyle = .results
    var makeContent: (() -> AnyView)?
    var desired = false
    private(set) var host: UIHostingController<AnyView>?
    private var modal: UIViewController?
    private var navigation: CompetitionResultsNavigationController?
    private var presenting = false
    fileprivate var dismissing = false
    private var dismissRequested = false
    private var afterDismissal: (() -> Void)?
    private let motion = CompetitionResultCardMotion()

    func rootContent() -> AnyView {
        AnyView((makeContent?() ?? AnyView(EmptyView()))
            .environment(\.competitionResultCardMotion, motion)
            .environment(\.competitionProfilePresenter,
                { [weak self] id, name in self?.openProfile(id: id, name: name) }))
    }
    func openProfile(id: String, name: String) {
        guard let navigation else { return }
        let profile = UIHostingController(rootView: WCAProfileView(wcaID: id, displayName: name))
        profile.title = name
        navigation.pushViewController(profile, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    func reconcile() {
        guard !presenting, !dismissing else { return }
        if let modal {
            guard !desired || dismissRequested else { return }
            dismissing = true
            modal.dismiss(animated: !UIAccessibility.isReduceMotionEnabled) { [weak self, weak modal] in
                guard let self, self.modal === modal else { return }
                let requested = self.dismissRequested
                let completion = self.afterDismissal
                self.host = nil; self.modal = nil; self.navigation = nil; self.dismissing = false; self.dismissRequested = false
                self.afterDismissal = nil
                if requested { self.desired = false; self.binding?.wrappedValue = false }
                if let completion { completion() } else { self.reconcile() }
            }
        } else if desired, let anchor, let root = anchor.window?.rootViewController {
            var presenter = root
            while let next = presenter.presentedViewController { presenter = next }
            guard makeContent != nil else { return }
            if presenter.isBeingDismissed || presenter.isBeingPresented {
                // A pending selection must wake after a foreign modal's transition.
                // Reconcile on the next main turn, after UIKit updates the hierarchy.
                let resume: () -> Void = { [weak self] in
                    DispatchQueue.main.async { [weak self] in self?.reconcile() }
                }
                presenter.transitionCoordinator?.animate(alongsideTransition: nil,
                    completion: { _ in resume() })
                return
            }
            let host = UIHostingController(rootView: rootContent())
            host.view.backgroundColor = .clear
            let navigation = CompetitionResultsNavigationController(rootViewController: host)
            self.navigation = navigation
            navigation.modalPresentationStyle = .custom
            navigation.transitioningDelegate = self
            navigation.detailBackTarget = CompetitionDetailBackTarget.find(from: anchor)
            navigation.returnToDetailParent = { [weak self, weak navigation] in
                guard let self, self.afterDismissal == nil, let target = navigation?.detailBackTarget else { return }
                self.afterDismissal = { target.activate() }
                self.requestDismissal()
            }
            motion.visible = false
            let modal: UIViewController = navigation
            modal.view.accessibilityViewIsModal = true
            self.host = host; self.modal = modal; presenting = true
            presenter.present(modal, animated: !UIAccessibility.isReduceMotionEnabled) { [weak self, weak modal] in
                guard let self, self.modal === modal else { return }
                self.presenting = false
                if UIAccessibility.isReduceMotionEnabled { self.motion.visible = true }
                modal?.presentationController?.delegate = self
                self.reconcile()
            }
        }
    }

    func requestDismissal() {
        dismissRequested = true
        reconcile()
    }
    func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        CompetitionResultsTransition(presenting: true, motion: motion)
    }
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        CompetitionResultsTransition(presenting: false, motion: motion)
    }
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?,
                                source: UIViewController) -> UIPresentationController? {
        CompetitionResultsScenePresentation(presentedViewController: presented, presenting: presenting)
    }
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle { .none }
    func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === modal, !dismissing else { return }
        dismissing = true; desired = false; binding?.wrappedValue = false
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === modal else { return }
        host = nil; modal = nil; navigation = nil; dismissing = false; dismissRequested = false
        let completion = afterDismissal; afterDismissal = nil
        if let completion { completion(); return }
        reconcile()
    }

}

final class CompetitionResultsNavigationController: UINavigationController, UINavigationControllerDelegate {
    var detailBackTarget: CompetitionDetailBackTarget?
    var returnToDetailParent: (() -> Void)?
    private let detailBack = UIButton(type: .custom)
    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        view.backgroundColor = .clear
        setNavigationBarHidden(true, animated: false)
        detailBack.accessibilityIdentifier = "competition-detail-back"
        detailBack.isAccessibilityElement = true
        detailBack.accessibilityLabel = detailBackTarget?.label
        detailBack.addTarget(self, action: #selector(returnToParent), for: .touchUpInside)
        detailBack.addTarget(self, action: #selector(highlightBack), for: [.touchDown, .touchDragEnter])
        detailBack.addTarget(self, action: #selector(unhighlightBack), for: [.touchCancel, .touchUpOutside, .touchDragExit])
        view.addSubview(detailBack)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        detailBack.frame = detailBackTarget?.frame(in: view) ?? .zero
        detailBack.accessibilityLabel = detailBackTarget?.label
        detailBack.isHidden = detailBackTarget == nil || viewControllers.first !== topViewController
        view.bringSubviewToFront(detailBack)
    }
    @objc private func highlightBack() { detailBackTarget?.setHighlighted(true) }
    @objc private func unhighlightBack() { detailBackTarget?.setHighlighted(false) }
    @objc private func returnToParent() { unhighlightBack(); returnToDetailParent?() }
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        setNavigationBarHidden(viewController === viewControllers.first, animated: animated)
        detailBack.isHidden = viewController !== viewControllers.first || detailBackTarget == nil
    }
}

/// Keep the native Back's drawing/action; intercept only its measured hit region.
/// No private selectors, guessed toolbar rectangle or background touch-through.
@MainActor final class CompetitionDetailBackTarget {
    private weak var control: UIControl?
    private weak var navigation: UINavigationController?
    private weak var source: UIViewController?
    let label: String
    private let event: UIControl.Event
    private init(control: UIControl, navigation: UINavigationController, source: UIViewController, event: UIControl.Event) {
        self.control = control; self.navigation = navigation; self.source = source; self.event = event
        label = control.accessibilityLabel ?? navigation.navigationBar.backItem?.title ?? "Back"
    }
    static func find(from anchor: UIView) -> CompetitionDetailBackTarget? {
        // Hosting views can route the responder chain past their owning detail
        // controller. Use public containment and the actual source view instead.
        func containingNavigation(_ controller: UIViewController) -> UINavigationController? {
            for child in controller.children {
                if let match = containingNavigation(child) { return match }
            }
            if let navigation = controller as? UINavigationController,
               let view = navigation.topViewController?.viewIfLoaded,
               anchor === view || anchor.isDescendant(of: view) { return navigation }
            return nil
        }
        if let root = anchor.window?.rootViewController,
           let navigation = containingNavigation(root),
           let source = navigation.topViewController, navigation.viewControllers.count > 1 {
                let bar = navigation.navigationBar
                guard !bar.isHidden, bar.backItem != nil, bar.topItem?.hidesBackButton == false,
                      bar.topItem?.leftBarButtonItems?.isEmpty != false else { return nil }
                bar.layoutIfNeeded()
                func controls(_ view: UIView) -> [UIControl] {
                    view.subviews.flatMap { child -> [UIControl] in
                        // UIKit's glass hosting wrappers can have empty bounds
                        // while their native controls remain correctly laid out.
                        guard !child.isHidden, child.alpha > 0 else { return [] }
                        let descendants = controls(child)
                        if let control = child as? UIControl, descendants.isEmpty,
                           !control.isHidden, control.alpha > 0, !control.bounds.isEmpty,
                           control.allControlEvents.contains(.touchUpInside) || control.allControlEvents.contains(.primaryActionTriggered) {
                            return [control]
                        }
                        return descendants
                    }
                }
                let rtl = bar.effectiveUserInterfaceLayoutDirection == .rightToLeft
                let candidates = controls(bar).sorted {
                    let a = $0.convert($0.bounds, to: bar), b = $1.convert($1.bounds, to: bar)
                    return rtl ? a.maxX > b.maxX : a.minX < b.minX
                }
                guard let control = candidates.first else { return nil }
                let bounds = control.convert(control.bounds, to: bar)
                guard rtl ? bounds.midX > bar.bounds.midX : bounds.midX < bar.bounds.midX else { return nil }
                let event: UIControl.Event = control.allControlEvents.contains(.touchUpInside) ? .touchUpInside : .primaryActionTriggered
                return Self(control: control, navigation: navigation, source: source, event: event)
        }
        return nil
    }
    func frame(in view: UIView) -> CGRect {
        let window = (view as? UIWindow) ?? view.window
        guard let control = currentTarget()?.control, control.window === window else { return .zero }
        return control.convert(control.bounds, to: view)
    }
    func setHighlighted(_ highlighted: Bool) { currentTarget()?.control?.isHighlighted = highlighted }
    private func currentTarget() -> CompetitionDetailBackTarget? {
        // UIKit may replace its Back control while keeping the source controller.
        guard let navigation, let source, navigation.topViewController === source,
              let view = source.viewIfLoaded, view.window != nil else { return nil }
        return Self.find(from: view)
    }
    func activate() {
        guard let target = currentTarget(), let control = target.control,
              control.window != nil else { return }
        control.sendActions(for: target.event)
    }
}

private final class CompetitionResultsScenePresentation: UIPresentationController {
    override var shouldRemovePresentersView: Bool { false }
    override var frameOfPresentedViewInContainerView: CGRect { containerView?.bounds ?? .zero }
    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        presentedView?.frame = frameOfPresentedViewInContainerView
    }
}

final class CompetitionResultsTransition: NSObject, UIViewControllerAnimatedTransitioning {
    let presenting: Bool
    private let motion: CompetitionResultCardMotion
    init(presenting: Bool, motion: CompetitionResultCardMotion) { self.presenting = presenting; self.motion = motion }
    func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0 : (presenting ? 0.18 : 0.16)
    }
    func animateTransition(using context: UIViewControllerContextTransitioning) {
        let key: UITransitionContextViewControllerKey = presenting ? .to : .from
        guard let controller = context.viewController(forKey: key), let view = controller.view else {
            context.completeTransition(false); return
        }
        if presenting {
            view.frame = context.finalFrame(for: controller)
            context.containerView.addSubview(view)
            view.alpha = 0
            view.layoutIfNeeded()
        }
        motion.setVisible(presenting, reduceMotion: UIAccessibility.isReduceMotionEnabled)
        UIView.animate(withDuration: transitionDuration(using: context), delay: 0,
            options: presenting ? [.curveEaseOut] : [.curveEaseIn]) {
                view.alpha = self.presenting ? 1 : 0
            } completion: { _ in
                let completed = !context.transitionWasCancelled
                if !self.presenting, completed { view.removeFromSuperview() }
                context.completeTransition(completed)
            }
    }
}

private struct CompetitionResultsPresentationModifier: ViewModifier {
    @ObservedObject var state: CompetitionResultCardState
    let language: String
    let round: CompetitionWCALiveRound?
    #if DEBUG
    @Environment(\.competitionDebugCompetitionID) private var diagnosticCompetitionID
    #endif
    func body(content: Content) -> some View {
        content.background {
            CompetitionNativePresentation(isPresented: Binding(get: { state.selection != nil }, set: { if !$0 { state.close() } }), style: .results) { dismiss in
                if let selection = state.selection {
                    CompetitionResultExperience(round: round ?? selection.round, languageCode: language,
                        cardState: state, mode: .card, isPublished: selection.isPublished, onRequestDismiss: dismiss)
                        #if DEBUG
                        .competitionDebugCompetition(diagnosticCompetitionID)
                        #endif
                }
            }
        }
    }
}

extension View {
    func competitionResultsPresentation(state: CompetitionResultCardState, language: String,
                                        round: CompetitionWCALiveRound? = nil) -> some View {
        modifier(CompetitionResultsPresentationModifier(state: state, language: language, round: round))
    }
}

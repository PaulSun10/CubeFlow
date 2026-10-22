import SwiftUI
import UIKit
import Combine

#if DEBUG
@MainActor enum CompetitionFilterTrace {
    static var enabled: Bool { CompetitionDebugStore.shared.enabled && CompetitionDebugStore.shared.filterRecording }
    static func event(_ name: String, generation: Int = -1, detail: String = "", timestamp: Double? = nil,
                      fields: [String: Any] = [:]) {
        guard enabled else { return }
        let time = timestamp ?? CACurrentMediaTime()
        var value = fields
        value.merge(["time": time, "event": name, "generation": generation, "detail": detail], uniquingKeysWith: { _, new in new })
        CompetitionDebugStore.shared.recordFilter(value)
    }
}

/// Passive DEBUG observation only: never recognizes, delays, or prevents a touch.
private struct CompetitionFilterInputProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> CompetitionFilterInputAnchor {
        CompetitionFilterInputAnchor(recordingEnabled: CompetitionFilterTrace.enabled)
    }
    func updateUIView(_ view: CompetitionFilterInputAnchor, context: Context) {}
    static func dismantleUIView(_ view: CompetitionFilterInputAnchor, coordinator: Void) { view.detach() }
}
#endif

/// Keep user intent separate from SwiftUI's acknowledgement of an older dismissal.
@MainActor final class CompetitionFilterPresentation: ObservableObject {
    @Published private(set) var isPresented = false
    private(set) var generation = 0
    private(set) var isDismissing = false
    private var requested = false
    private var hasNativeContent = false

    func open() {
        #if DEBUG
        CompetitionFilterTrace.event("open-request", generation: generation, detail: "dismissing=\(isDismissing) presented=\(isPresented)")
        #endif
        requested = true
        guard !isDismissing, !isPresented else { return }
        generation += 1
        isPresented = true
        #if DEBUG
        CompetitionFilterTrace.event("intent-published", generation: generation)
        #endif
    }

    func close() {
        #if DEBUG
        CompetitionFilterTrace.event("close-request", generation: generation)
        #endif
        requested = false
        guard isPresented else { return }
        isDismissing = hasNativeContent
        isPresented = false
    }

    func frameworkChanged(_ value: Bool, generation: Int) {
        #if DEBUG
        CompetitionFilterTrace.event("framework-binding", generation: generation, detail: "value=\(value)")
        #endif
        guard generation == self.generation, !value, !isDismissing else { return }
        close()
    }

    func contentMounted(generation: Int) {
        guard generation == self.generation else { return }
        hasNativeContent = true
    }

    func nativeDismissalBegan(generation: Int) {
        #if DEBUG
        CompetitionFilterTrace.event("native-dismissal-began", generation: generation)
        #endif
        guard generation == self.generation, !isDismissing else { return }
        requested = false
        isDismissing = true
        isPresented = false
    }

    func nativeDismissalCancelled(generation: Int) {
        guard generation == self.generation, isDismissing else { return }
        // The native popover still exists after a cancelled transition. Start a
        // new acknowledgement epoch so the cancelled dismissal cannot close it.
        self.generation += 1
        isDismissing = false
        hasNativeContent = true
        requested = true
        isPresented = true
    }

    func dismissalFinished(generation: Int) {
        #if DEBUG
        CompetitionFilterTrace.event("dismissal-finished", generation: generation)
        #endif
        guard generation == self.generation else { return }
        let reopen = isDismissing && requested
        hasNativeContent = false
        isDismissing = false
        if isPresented { isPresented = false }
        requested = reopen
        if reopen { open() }
    }
}

private struct CompetitionPopoverCompletion: UIViewControllerRepresentable {
    let mounted: () -> Void
    let isDismissing: () -> Bool
    let began: () -> Void
    let cancelled: () -> Void
    let finished: () -> Void
    func makeUIViewController(context: Context) -> Controller {
        #if DEBUG
        CompetitionFilterTrace.event("content-make")
        #endif
        let controller = Controller()
        controller.finished = finished
        controller.isDismissing = isDismissing
        controller.began = began
        controller.cancelled = cancelled
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        mounted()
        return controller
    }
    func updateUIViewController(_ controller: Controller, context: Context) {}
    static func dismantleUIViewController(_ controller: Controller, coordinator: Void) {
        #if DEBUG
        CompetitionFilterTrace.event("content-dismantle")
        #endif
        controller.completeAfterTransition()
    }
    final class Controller: UIViewController {
        var finished: (() -> Void)?
        var isDismissing: (() -> Bool)?
        var began: (() -> Void)?
        var cancelled: (() -> Void)?
        private weak var nativeContainer: UIViewController?
        private var waitingForCompletion = false
        #if DEBUG
        private var visibilityLink: CADisplayLink?
        private var visibilityStart = 0.0
        private var dismissalLink: CADisplayLink?
        private var dismissalStart = 0.0
        private func observeDismissalSurface() {
            guard CompetitionFilterTrace.enabled else { return }
            dismissalLink?.invalidate()
            dismissalStart = CACurrentMediaTime()
            let link = CADisplayLink(target: self, selector: #selector(sampleDismissalSurface))
            link.preferredFramesPerSecond = 12
            dismissalLink = link
            link.add(to: .main, forMode: .common)
            sampleDismissalSurface()
        }
        private func stopDismissalObservation() {
            dismissalLink?.invalidate(); dismissalLink = nil
        }
        @objc private func sampleDismissalSurface() {
            guard CompetitionFilterTrace.enabled, CACurrentMediaTime() - dismissalStart <= 8 else {
                stopDismissalObservation(); return
            }
            var fields = diagnosticState()
            fields["elapsed"] = CACurrentMediaTime() - dismissalStart
            // UIKit's actual presented surface can wrap the content controller.
            if let surface = nativeContainer?.presentationController?.presentedView ?? nativeContainer?.viewIfLoaded {
                fields["surfaceOwner"] = "\(type(of: surface)):\(ObjectIdentifier(surface))"
                let layer = surface.layer.presentation() ?? surface.layer
                fields["surfaceBounds"] = [layer.bounds.origin.x, layer.bounds.origin.y, layer.bounds.width, layer.bounds.height]
                fields["surfacePosition"] = [layer.position.x, layer.position.y]
                fields["surfaceOpacity"] = layer.opacity
                fields["surfaceHidden"] = layer.isHidden
                if let window = surface.window {
                    let origin = CompetitionDisclosureViewportProbe.shared.projectedOrigin(surface.layer, in: window.layer)
                        ?? surface.convert(surface.bounds.origin, to: window)
                    fields["windowOrigin"] = [origin.x, origin.y]
                    fields["windowAttached"] = true
                } else { fields["windowAttached"] = false }
                let t = layer.transform
                fields["surfaceTransform"] = [t.m11, t.m12, t.m13, t.m14, t.m21, t.m22, t.m23, t.m24,
                    t.m31, t.m32, t.m33, t.m34, t.m41, t.m42, t.m43, t.m44]
                var ancestors: [[String: Any]] = []
                var cursor: UIView? = surface
                while let view = cursor, ancestors.count < 16 {
                    let current = view.layer.presentation() ?? view.layer, transform = current.transform
                    ancestors.append(["owner": "\(type(of: view)):\(ObjectIdentifier(view))",
                        "windowAttached": view.window != nil, "hidden": current.isHidden,
                        "opacity": current.opacity, "position": [current.position.x, current.position.y],
                        "bounds": [current.bounds.origin.x, current.bounds.origin.y, current.bounds.width, current.bounds.height],
                        "transform": [transform.m11, transform.m12, transform.m13, transform.m14,
                            transform.m21, transform.m22, transform.m23, transform.m24,
                            transform.m31, transform.m32, transform.m33, transform.m34,
                            transform.m41, transform.m42, transform.m43, transform.m44],
                        "animationKeys": view.layer.animationKeys() ?? []])
                    cursor = view.superview
                }
                fields["surfaceAncestors"] = ancestors
            }
            CompetitionFilterTrace.event("dismissal-native-surface", fields: fields)
        }
        private func diagnosticState() -> [String: Any] {
            guard CompetitionFilterTrace.enabled else { return [:] }
            func identity(_ controller: UIViewController?) -> String {
                controller.map { "\(type(of: $0)):\(ObjectIdentifier($0))" } ?? "none"
            }
            func coordinator(_ value: (any UIViewControllerTransitionCoordinator)?) -> [String: Any] {
                guard let value else { return ["present": false] }
                return ["present": true, "identity": String(describing: ObjectIdentifier(value as AnyObject)),
                    "type": String(describing: type(of: value)), "duration": value.transitionDuration,
                    "animated": value.isAnimated, "interactive": value.isInteractive,
                    "cancelled": value.isCancelled, "percentComplete": value.percentComplete,
                    "from": identity(value.viewController(forKey: .from)),
                    "to": identity(value.viewController(forKey: .to))]
            }
            return ["observer": identity(self), "parent": identity(parent),
                "observerWindowAttached": viewIfLoaded?.window != nil,
                "nativeContainer": identity(nativeContainer),
                "nativePresenter": identity(nativeContainer?.presentingViewController),
                "nativeWindowAttached": nativeContainer?.viewIfLoaded?.window != nil,
                "nativeBeingPresented": nativeContainer?.isBeingPresented ?? false,
                "nativeBeingDismissed": nativeContainer?.isBeingDismissed ?? false,
                "waitingForCompletion": waitingForCompletion,
                "observerCoordinator": coordinator(transitionCoordinator),
                "nativeCoordinator": coordinator(nativeContainer?.transitionCoordinator)]
        }
        private func observeFirstVisibleFrame() {
            guard CompetitionFilterTrace.enabled else { return }
            NotificationCenter.default.removeObserver(self, name: CompetitionDebugStore.changed, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(captureChanged), name: CompetitionDebugStore.changed, object: nil)
            visibilityLink?.invalidate()
            visibilityStart = CACurrentMediaTime()
            let link = CADisplayLink(target: self, selector: #selector(sampleVisibility))
            visibilityLink = link
            link.add(to: .main, forMode: .common)
        }
        @objc private func captureChanged() {
            if !CompetitionFilterTrace.enabled {
                visibilityLink?.invalidate(); visibilityLink = nil
                stopDismissalObservation()
                NotificationCenter.default.removeObserver(self, name: CompetitionDebugStore.changed, object: nil)
            }
        }
        @objc private func sampleVisibility() {
            guard visibilityLink != nil else { return }
            guard CompetitionFilterTrace.enabled else { captureChanged(); return }
            if CACurrentMediaTime() - visibilityStart > 2 {
                visibilityLink?.invalidate(); visibilityLink = nil; return
            }
            guard let surface = nativeContainer?.view, let window = surface.window else { return }
            var opacity: Float = 1
            var cursor: CALayer? = surface.layer
            while let layer = cursor, layer !== window.layer {
                if layer.isHidden { return }
                opacity *= layer.presentation()?.opacity ?? layer.opacity
                cursor = layer.superlayer
            }
            let origin = CompetitionDisclosureViewportProbe.shared.projectedOrigin(surface.layer, in: window.layer)
                ?? surface.convert(surface.bounds.origin, to: window)
            let bounds = surface.layer.presentation()?.bounds ?? surface.bounds
            guard opacity > 0.01, CGRect(origin: origin, size: bounds.size).intersects(window.bounds) else { return }
            // First observable native surface, not a claim about subjective visibility.
            CompetitionFilterTrace.event("first-visible-native-surface", detail: "opacity=\(opacity)")
            visibilityLink?.invalidate(); visibilityLink = nil
        }
        #endif
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            identifyNativeContainer()
            #if DEBUG
            CompetitionFilterTrace.event("native-will-appear", fields: diagnosticState())
            observeFirstVisibleFrame()
            #endif
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            identifyNativeContainer()
            #if DEBUG
            CompetitionFilterTrace.event("native-did-appear", fields: diagnosticState())
            sampleVisibility()
            visibilityLink?.invalidate(); visibilityLink = nil
            #endif
        }
        override func viewWillDisappear(_ animated: Bool) {
            #if DEBUG
            CompetitionFilterTrace.event("native-will-disappear", detail: "animated=\(animated) duration=\(transitionCoordinator?.transitionDuration ?? -1) alreadyClosing=\(isDismissing?() ?? false)", fields: diagnosticState())
            visibilityLink?.invalidate(); visibilityLink = nil
            #endif
            super.viewWillDisappear(animated)
            identifyNativeContainer()
            #if DEBUG
            if nativeContainer?.isBeingDismissed == true { observeDismissalSurface() }
            #endif
            if nativeContainer?.isBeingDismissed == true { began?() }
            completeAfterTransition()
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            #if DEBUG
            CompetitionFilterTrace.event("native-did-disappear", fields: diagnosticState())
            if dismissalLink != nil { sampleDismissalSurface() }
            stopDismissalObservation()
            #endif
            if !waitingForCompletion { complete() }
        }
        func completeAfterTransition() {
            guard !waitingForCompletion else { return }
            if let transitionCoordinator {
                let ownsDismissal = nativeContainer?.isBeingDismissed == true
                // Retain this observer until its registered transition completes,
                // even if SwiftUI dismantles the representable in the meantime.
                waitingForCompletion = transitionCoordinator.animate(alongsideTransition: nil) { context in
                    #if DEBUG
                    CompetitionFilterTrace.event("transition-completion", detail: "cancelled=\(context.isCancelled) duration=\(context.transitionDuration)", fields: self.diagnosticState())
                    #endif
                    self.waitingForCompletion = false
                    if !context.isCancelled { self.complete() }
                    else if ownsDismissal, self.nativeContainer?.presentingViewController != nil {
                        #if DEBUG
                        self.stopDismissalObservation()
                        #endif
                        self.cancelled?()
                    }
                }
                #if DEBUG
                CompetitionFilterTrace.event("completion-registration", detail: "accepted=\(waitingForCompletion)", fields: diagnosticState())
                #endif
            } else if view.window == nil { complete() }
        }
        private func identifyNativeContainer() {
            var cursor: UIViewController? = self
            while let controller = cursor {
                if controller.presentingViewController != nil { nativeContainer = controller }
                cursor = controller.parent
            }
        }
        private func complete() {
            // A Region sheet can cover the popover without dismissing it.
            if let nativeContainer {
                guard nativeContainer.isBeingDismissed || nativeContainer.presentingViewController == nil else { return }
            } else {
                guard view.window == nil, isDismissing?() == true else { return }
            }
            #if DEBUG
            stopDismissalObservation()
            CompetitionFilterTrace.event("completion-accepted", fields: diagnosticState())
            #endif
            let callback = finished; finished = nil; callback?()
        }
    }
}

/// Framework writes can outlive the presentation binding that produced them.
/// Keep the captured epoch on the native binding as well as on user intent.
struct CompetitionFilterNativeBindingState {
    private(set) var presented = false
    private(set) var generation = 0
    private(set) var dismissedGeneration: Int?

    mutating func request(_ presented: Bool, generation: Int) {
        if presented { self.generation = generation }
        self.presented = presented
    }

    mutating func acknowledge(_ value: Bool, generation: Int, currentGeneration: Int) {
        guard generation == self.generation, generation == currentGeneration else { return }
        presented = value
        if !value { dismissedGeneration = generation }
    }
}

private struct CompetitionFilterPopoverModifier<Popover: View>: ViewModifier {
    @ObservedObject var presentation: CompetitionFilterPresentation
    @ViewBuilder let popover: (Binding<Bool>) -> Popover
    @State private var native = CompetitionFilterNativeBindingState()
    private func synchronizeIntent() {
        // Let SwiftUI/UIKit own the original popover transition. Only lifecycle
        // acknowledgement is mediated; never replace or disable its animation.
        native.request(presentation.isPresented, generation: presentation.generation)
        #if DEBUG
        CompetitionFilterTrace.event("native-binding-request", generation: native.generation, detail: "value=\(native.presented)")
        #endif
    }
    func body(content: Content) -> some View {
        let generation = native.generation
        content
        #if DEBUG
        .background {
            CompetitionFilterInputProbe()
        }
        #endif
        .popover(isPresented: Binding(get: { native.presented }, set: {
            native.acknowledge($0, generation: generation, currentGeneration: presentation.generation)
            #if DEBUG
            CompetitionFilterTrace.event("native-binding-ack", generation: generation, detail: "value=\($0)")
            #endif
        }), attachmentAnchor: .point(.bottom), arrowEdge: .top) {
            popover(Binding(get: { presentation.isPresented }, set: {
                if $0 { presentation.open() } else { presentation.close() }
            })).background {
                CompetitionPopoverCompletion(mounted: { presentation.contentMounted(generation: generation) },
                    isDismissing: { presentation.generation == generation && presentation.isDismissing },
                    began: { presentation.nativeDismissalBegan(generation: generation) },
                    cancelled: { presentation.nativeDismissalCancelled(generation: generation) },
                    finished: { presentation.dismissalFinished(generation: generation) })
                    .id(generation)
            }
        }
        .onAppear { synchronizeIntent() }
        .onChange(of: presentation.isPresented) { _ in synchronizeIntent() }
        .onChange(of: native.dismissedGeneration) { generation in
            // Framework binding acknowledgement may arrive during view updates.
            // Consume the captured epoch as a SwiftUI lifecycle event instead.
            if let generation { presentation.frameworkChanged(false, generation: generation) }
        }
    }
}

extension View {
    func competitionFilterPopover<Popover: View>(presentation: CompetitionFilterPresentation,
        @ViewBuilder content: @escaping (Binding<Bool>) -> Popover) -> some View {
        modifier(CompetitionFilterPopoverModifier(presentation: presentation, popover: content))
    }
}

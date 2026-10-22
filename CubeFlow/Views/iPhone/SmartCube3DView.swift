#if os(iOS)
import SceneKit
import SwiftUI
import Combine

private final class SmartCubeSceneView: SCNView {
    #if DEBUG
    weak var debugOwner: SmartCube3DView.Coordinator?
    #endif
    var windowChanged: ((Bool) -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        windowChanged?(window != nil)
    }
}

struct SmartCube3DView: UIViewRepresentable {
    #if DEBUG
    static func debugCoordinator(of view: SCNView) -> Coordinator? { (view as? SmartCubeSceneView)?.debugOwner }
    #endif
    let facelets: String?
    let stateRevision: Int
    let fixedView: SmartCubeFixedView
    var cubeSize: Int = 3
    var events: AnyPublisher<SmartCubeCanonicalEvent, Never>?
    var connectionAttemptID: UUID?
    var isStateTrusted: Bool = true
    var diagnosticOwner = "unspecified"
    var animationTPSOverride: Int?
    var canonicalSequence: UInt64? = nil
    var temporaryVerticalPeek = false
    var onTap: (() -> Void)?
    var renderingEnabled = true
    @AppStorage("smartCubeAnimationTPS") private var animationTPS = 10
    @AppStorage("smartCubeAppearance") private var appearanceRawValue = VirtualCubeAppearance.classic.rawValue
    @AppStorage("smartCubeInternalPlastic") private var plasticRawValue = VirtualCubePlastic.black.rawValue
    @AppStorage("smartCubeReflections") private var reflections = false
    @AppStorage("smartCubePlasticColorData") private var plasticColorData: Data?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        context.coordinator.makeView(owner: diagnosticOwner)
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.setRenderingEnabled(renderingEnabled)
        context.coordinator.onTap = onTap
        context.coordinator.managementTap?.isEnabled = onTap != nil
        context.coordinator.update(
            facelets: facelets ?? CubeSurface.solved(size: cubeSize == 2 ? 2 : 3),
            stateRevision: stateRevision,
            fixedView: fixedView,
            size: cubeSize,
            events: events,
            attemptID: connectionAttemptID,
            trusted: isStateTrusted,
            tps: animationTPSOverride ?? animationTPS,
            temporaryVerticalPeek: temporaryVerticalPeek,
            appearance: VirtualCubeAppearance(rawValue: appearanceRawValue) ?? .classic,
            plastic: VirtualCubePlastic(rawValue: plasticRawValue) ?? .black,
            reflections: reflections,
            customColor: UIColor(StoredColorData.decode(from: plasticColorData, fallback: StoredColorData(r: 0.5, g: 0, b: 0.5)).color),
            canonicalSequence: canonicalSequence
        )
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.stop()
    }

    private static let solvedFacelets = "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB"

    final class Coordinator: NSObject {
        var onTap: (() -> Void)?
        private(set) var managementTap: UITapGestureRecognizer?
        private let scene = SCNScene()
        private let interactionNode = SCNNode()
        private let cubeNode = SCNNode()
        private let cameraNode = SCNNode()
        private var lastStateRevision = -1
        private var dragYaw = SmartCubeFixedView.urf.yaw
        private var dragPitch: Float = 0
        private var temporaryVerticalPeek = false
        private var selectedFixedView: SmartCubeFixedView = .urf
        private var presentation = CubeTurnPresentation(facelets: SmartCube3DView.solvedFacelets)
        private var subscription: AnyCancellable?
        private var clock: Timer?
        private var wantsRendering = true
        private var isInWindow = false
        private var hasBeenInWindow = false
        private var renderingWasSuspended = false
        private var attemptID: UUID?
        private var bindingGeneration = 0
        private var lastSequence: UInt64?
        private var pendingSnapshot: (facelets: String, trusted: Bool, sequence: UInt64)?
        private var snapshotReconciliation: DispatchWorkItem?
        private var hasBound = false
        private var renderedState: String?
        private var renderedAnimationID: UInt64?
        private var pivot: SCNNode?
        private var cubies: [(SIMD3<Int>, SCNNode)] = []
        private var appearance: VirtualCubeAppearance = .classic
        private var resources = VirtualCubeMaterials(appearance: .classic, plastic: .black, reflections: false, customColor: .purple)
        private var builtResources: VirtualCubeMaterials?
        private var builtSize = 0
        private var faceNodes: [(node: SCNNode, color: Character)] = []
        private weak var perfView: SCNView?
        private var perfOwner = "unspecified"

        // Temporary diagnostics hold only scalars, never nodes or animation snapshots.
        private var perfCompleted = 0
        private var perfInterrupted = 0
        private var perfResetPending = false

        #if DEBUG
        var debugPresentation: CubeTurnPresentation { presentation }
        func debugRender(at time: TimeInterval) { tick(at: time) }
        var debugPivotAngle: Float? { pivot?.rotation.w }
        var debugClockIsActive: Bool { clock != nil }
        var debugLifecycle: String {
            "window=\(isInWindow) enabled=\(wantsRendering) suspended=\(renderingWasSuspended) clock=\(clock != nil) sequence=\(lastSequence ?? 0) trust=\(presentation.isTrusted) tps=\(presentation.tps) generation=\(presentation.generation)"
        }
        #endif

        override init() {
            super.init()
            #if DEBUG
            print("[VirtualCubeLifecycle] event=coordinator_init coordinator=\(ObjectIdentifier(self))")
            #endif
        }

        deinit {
            #if DEBUG
            print("[VirtualCubeLifecycle] owner=\(perfOwner) event=coordinator_deinit coordinator=\(ObjectIdentifier(self)) view=\(perfView.map { String(describing: ObjectIdentifier($0)) } ?? "nil")")
            #endif
        }

        private func observeTransition(from previous: CubeTurnPresentation.Animation?) {
            guard let previous, previous.id != presentation.current?.id else { return }
            if presentation.settled == previous.move.target && previous.progress(at: ProcessInfo.processInfo.systemUptime) >= 1 {
                perfCompleted += 1
                if perfCompleted.isMultiple(of: 50) { perfSnapshotPending = true }
            } else {
                perfInterrupted += 1
                logPerformance("interrupted")
            }
        }

        private var perfSnapshotPending = false

        private func logPerformance(_ event: String) {
            #if DEBUG
            var nodes = 1, actionNodes = scene.rootNode.hasActions ? 1 : 0
            scene.rootNode.enumerateChildNodes { node, _ in
                nodes += 1
                if node.hasActions { actionNodes += 1 }
            }
            let pivots = cubeNode.childNodes.filter { $0.geometry == nil }.count
            let cache = resources.diagnosticCacheCounts
            print("[VirtualCubePerf] owner=\(perfOwner) renderer=\(ObjectIdentifier(self)) view=\(perfView.map { String(describing: ObjectIdentifier($0)) } ?? "nil") event=\(event) completed=\(perfCompleted) interrupted=\(perfInterrupted) nodes=\(nodes) actionNodes=\(actionNodes) pivots=\(pivots) pivotRef=\(pivot != nil) pending=\(presentation.pending.count) current=\(presentation.current != nil) cubies=\(cubies.count) faces=\(faceNodes.count) geometryCache=\(cache.geometry) materialCache=\(cache.material)")
            #endif
        }

        func stop() {
            onTap = nil
            #if DEBUG
            print("[VirtualCubeLifecycle] owner=\(perfOwner) event=stop coordinator=\(ObjectIdentifier(self)) view=\(perfView.map { String(describing: ObjectIdentifier($0)) } ?? "nil") subscribed=\(subscription != nil) timer=\(clock != nil)")
            #endif
            bindingGeneration += 1
            snapshotReconciliation?.cancel(); snapshotReconciliation = nil; pendingSnapshot = nil
            subscription = nil
            clock?.invalidate()
            clock = nil
            (perfView as? SmartCubeSceneView)?.windowChanged = nil
            perfView?.isPlaying = false
            perfView?.rendersContinuously = false
        }

        func setRenderingEnabled(_ enabled: Bool) {
            guard wantsRendering != enabled else { return }
            wantsRendering = enabled
            updateRenderActivity()
        }

        private func updateRenderActivity() {
            let active = wantsRendering && isInWindow
            perfView?.rendersContinuously = active
            perfView?.isPlaying = active
            guard active else {
                if clock != nil { renderingWasSuspended = true }
                clock?.invalidate(); clock = nil
                return
            }
            guard clock == nil else { return }
            if renderingWasSuspended {
                presentation.resync(presentation.canonical, trusted: presentation.isTrusted)
                renderedState = nil
                renderingWasSuspended = false
            }
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            clock = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        func makeView(owner: String = "test") -> SCNView {
            perfOwner = owner
            let view = SmartCubeSceneView(frame: .zero)
            #if DEBUG
            view.debugOwner = self
            #endif
            perfView = view
            view.windowChanged = { [weak self] visible in
                guard let self else { return }
                self.isInWindow = visible
                self.hasBeenInWindow = self.hasBeenInWindow || visible
                self.updateRenderActivity()
            }
            #if DEBUG
            print("[VirtualCubeLifecycle] owner=\(perfOwner) event=make_view coordinator=\(ObjectIdentifier(self)) view=\(ObjectIdentifier(view))")
            #endif
            view.scene = scene
            view.backgroundColor = .clear
            view.allowsCameraControl = false
            view.autoenablesDefaultLighting = false
            view.isJitteringEnabled = false
            view.antialiasingMode = .multisampling2X
            view.rendersContinuously = false
            view.preferredFramesPerSecond = UIScreen.main.maximumFramesPerSecond

            scene.rootNode.addChildNode(interactionNode)
            interactionNode.addChildNode(cubeNode)
            interactionNode.eulerAngles = SCNVector3(0, dragYaw, 0)
            interactionNode.scale = SCNVector3(0.88, 0.88, 0.88)
            installCamera()
            installLights()
            buildCube(facelets: SmartCube3DView.solvedFacelets)
            logPerformance("initial")
            installGestures(on: view)
            return view
        }

        func update(
            facelets: String,
            stateRevision: Int,
            fixedView: SmartCubeFixedView,
            size: Int,
            events: AnyPublisher<SmartCubeCanonicalEvent, Never>?,
            attemptID: UUID?,
            trusted: Bool,
            tps: Int,
            temporaryVerticalPeek: Bool = false,
            appearance: VirtualCubeAppearance,
            plastic: VirtualCubePlastic,
            reflections: Bool,
            customColor: UIColor,
            canonicalSequence: UInt64? = nil
        ) {
            self.temporaryVerticalPeek = temporaryVerticalPeek
            if fixedView != selectedFixedView {
                selectedFixedView = fixedView
                dragYaw = fixedView.yaw
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.2
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                interactionNode.eulerAngles = SCNVector3(dragPitch, dragYaw, 0)
                positionCamera()
                SCNTransaction.commit()
            }
            let size = size == 2 ? 2 : 3
            if !hasBound || self.attemptID != attemptID || presentation.size != size {
                bindingGeneration += 1
                snapshotReconciliation?.cancel(); snapshotReconciliation = nil; pendingSnapshot = nil
                let binding = bindingGeneration
                subscription = nil
                self.attemptID = attemptID
                hasBound = true
                lastSequence = canonicalSequence
                presentation = CubeTurnPresentation(size: size, facelets: CubeSurface.solved(size: size))
                presentation.resync(facelets, trusted: trusted)
                renderedState = nil
                subscription = events?.sink { [weak self] event in
                    // CanonicalFeed publishes synchronously on MainActor, before SwiftUI can coalesce moves.
                    MainActor.assumeIsolated {
                        guard let self, self.bindingGeneration == binding else { return }
                        self.receive(event)
                    }
                }
                #if DEBUG
                print("[VirtualCubeLifecycle] owner=\(perfOwner) event=subscription_attach coordinator=\(ObjectIdentifier(self)) view=\(perfView.map { String(describing: ObjectIdentifier($0)) } ?? "nil") attached=\(subscription != nil)")
                #endif
            }
            presentation.tps = min(20, max(0, tps))
            if self.appearance != appearance || resources.plastic != plastic ||
                resources.reflections != reflections || !resources.customColor.isEqual(customColor) {
                self.appearance = appearance
                resources = VirtualCubeMaterials(appearance: appearance, plastic: plastic, reflections: reflections, customColor: customColor)
                renderedState = nil
            }
            // SwiftUI may deliver a body snapshot after newer synchronous BLE
            // events. That older snapshot is not an authoritative correction.
            let isOlderSnapshot = canonicalSequence.flatMap { snapshot in lastSequence.map { snapshot < $0 } } ?? false
            if !isOlderSnapshot {
                if subscription != nil, let sequence = canonicalSequence,
                   sequence > (lastSequence ?? sequence) || facelets != presentation.canonical || trusted != presentation.isTrusted {
                    // A model subscriber can render this event's new snapshot
                    // before our later subscriber receives its executable turn.
                    // Reconcile only after synchronous event delivery completes.
                    stageSnapshot(facelets, trusted: trusted, sequence: sequence)
                } else if facelets != presentation.canonical || trusted != presentation.isTrusted {
                    presentation.resync(trusted ? facelets : nil, trusted: trusted)
                    if let canonicalSequence { lastSequence = canonicalSequence }
                } else if let canonicalSequence {
                    lastSequence = canonicalSequence
                }
                lastStateRevision = stateRevision
            }
            if wantsRendering && (isInWindow || !hasBeenInWindow) { tick() }
        }

        private func receive(_ event: SmartCubeCanonicalEvent) {
            if let lastSequence, event.sequence <= lastSequence { return }
            if let pendingSnapshot, pendingSnapshot.sequence <= event.sequence { self.pendingSnapshot = nil }
            let hasGap = lastSequence.map { event.sequence != $0 + 1 } ?? false
            lastSequence = event.sequence
            let perfPrevious = presentation.current
            switch event {
            case .boundary(let boundary):
                presentation.resync(boundary.facelets, trusted: boundary.facelets != nil)
                if boundary.reason == .reset {
                    perfCompleted = 0
                    perfInterrupted = 0
                    perfSnapshotPending = false
                    perfResetPending = true
                    logPerformance("reset_received_scene_not_yet_settled")
                } else {
                    logPerformance("boundary_\(boundary.reason.rawValue)")
                }
            case .move(let update):
                if hasGap || !update.isStateTrusted || !wantsRendering || (hasBeenInWindow && !isInWindow) {
                    presentation.resync(update.isStateTrusted ? update.facelets : nil, trusted: update.isStateTrusted)
                } else {
                    let now = ProcessInfo.processInfo.systemUptime
                    presentation.enqueue(update.move.move, target: update.facelets, timestamp: now, now: now)
                }
            }
            if case .move = event { observeTransition(from: perfPrevious) }
        }

        private func stageSnapshot(_ facelets: String, trusted: Bool, sequence: UInt64) {
            pendingSnapshot = (facelets, trusted, sequence)
            guard snapshotReconciliation == nil else { return }
            let binding = bindingGeneration
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.bindingGeneration == binding else { return }
                self.snapshotReconciliation = nil
                guard let snapshot = self.pendingSnapshot else { return }
                self.pendingSnapshot = nil
                guard snapshot.sequence >= (self.lastSequence ?? 0) else { return }
                // A snapshot with no corresponding event chain remains an
                // authoritative correction, never a fabricated animation.
                self.presentation.resync(snapshot.trusted ? snapshot.facelets : nil, trusted: snapshot.trusted)
                self.lastSequence = snapshot.sequence
                if self.wantsRendering && self.isInWindow { self.tick() }
            }
            snapshotReconciliation = work
            DispatchQueue.main.async(execute: work)
        }

        private func tick(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
            if perfResetPending && renderedState == presentation.settled && renderedAnimationID == nil {
                logPerformance("reset_settled")
                perfResetPending = false
            }
            guard presentation.current != nil || !presentation.pending.isEmpty ||
                renderedState != presentation.settled || renderedAnimationID != nil else { return }
            let perfPrevious = presentation.current
            presentation.advance(at: now)
            observeTransition(from: perfPrevious)
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            if renderedState != presentation.settled || renderedAnimationID != presentation.current?.id {
                buildCube(facelets: presentation.settled)
                renderedState = presentation.settled
                renderedAnimationID = presentation.current?.id
                pivot = nil
                if let animation = presentation.current {
                    let layer = SCNNode()
                    cubeNode.addChildNode(layer)
                    for (position, node) in cubies where animation.move.turn.contains(position, size: presentation.size) {
                        layer.addChildNode(node)
                    }
                    pivot = layer
                }
            }
            if let animation = presentation.current, let pivot {
                let progress = animation.progress(at: now)
                // Smoothstep preserves the current angle when the remaining duration is compressed.
                let eased = progress * progress * (3 - 2 * progress)
                var axis = SCNVector3Zero
                switch animation.move.turn.axis {
                case 0: axis.x = 1
                case 1: axis.y = 1
                default: axis.z = 1
                }
                pivot.rotation = SCNVector4(axis.x, axis.y, axis.z, Float(animation.move.turn.angle * eased))
            }
            SCNTransaction.commit()
            if perfResetPending {
                logPerformance("reset_settled")
                perfResetPending = false
            }
            if perfSnapshotPending {
                logPerformance("periodic_settled")
                perfSnapshotPending = false
            }
        }

        private func installGestures(on view: SCNView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.name = "CubeFlow.SmartCube.Drag"
            pan.maximumNumberOfTouches = 1
            view.addGestureRecognizer(pan)
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.require(toFail: pan)
            tap.isEnabled = false
            view.addGestureRecognizer(tap)
            managementTap = tap
        }

        @objc private func handleTap() { onTap?() }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: recognizer.view)
            recognizer.setTranslation(.zero, in: recognizer.view)

            switch recognizer.state {
            case .began, .changed:
                dragYaw = Self.normalizedAngle(dragYaw + Float(translation.x) * 0.008)
                if temporaryVerticalPeek {
                    dragPitch = min(0.85, max(-0.85, dragPitch + Float(translation.y) * 0.008))
                }
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0
                interactionNode.eulerAngles = SCNVector3(dragPitch, dragYaw, 0)
                SCNTransaction.commit()
            case .ended, .cancelled, .failed:
                guard temporaryVerticalPeek else { return }
                dragPitch = 0
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.28
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
                interactionNode.eulerAngles = SCNVector3(0, dragYaw, 0)
                SCNTransaction.commit()
            default:
                break
            }
        }

        private static func normalizedAngle(_ value: Float) -> Float {
            var angle = value
            while angle > Float.pi { angle -= Float.pi * 2 }
            while angle < -Float.pi { angle += Float.pi * 2 }
            return angle
        }

        private func installCamera() {
            cameraNode.camera = SCNCamera()
            cameraNode.camera?.fieldOfView = 34
            positionCamera()
            scene.rootNode.addChildNode(cameraNode)
        }

        private func positionCamera() {
            cameraNode.position = SCNVector3(0, selectedFixedView == .uf ? 3.9 : 3.5, 7.2)
            cameraNode.look(at: SCNVector3(0, 0, 0))
        }

        private func installLights() {
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 300
            ambient.light?.color = UIColor.white
            scene.rootNode.addChildNode(ambient)
            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.intensity = 550
            key.eulerAngles = SCNVector3(-0.6, -0.5, 0)
            scene.rootNode.addChildNode(key)
        }

        private func buildCube(facelets: String) {
            let size = presentation.size
            let chars = Array(facelets)
            if builtSize == size, builtResources === resources {
                // Cubies retain their original local coordinates under the temporary pivot.
                // Reparent without preserving world transforms to restore the settled layout.
                for (_, node) in cubies where node.parent !== cubeNode {
                    cubeNode.addChildNode(node)
                }
                pivot?.removeFromParentNode()
                for index in faceNodes.indices {
                    let color = index < chars.count ? chars[index] : "U"
                    if faceNodes[index].color != color {
                        faceNodes[index].node.geometry = resources.face(index: index, size: size, color: Self.color(for: color), colorKey: color)
                        faceNodes[index].color = color
                    }
                }
                return
            }
            cubeNode.childNodes.forEach { $0.removeFromParentNode() }

            cubies.removeAll(keepingCapacity: true)
            faceNodes.removeAll(keepingCapacity: true)
            builtSize = size
            builtResources = resources
            let pitch = CGFloat(3) / CGFloat(size)
            let surfaces = CubeSurface.all(size: size)
            var pieces: [SIMD3<Int>: SCNNode] = [:]
            for (index, surface) in surfaces.enumerated() {
                let piece: SCNNode
                if let existing = pieces[surface.position] {
                    piece = existing
                } else {
                    piece = SCNNode(geometry: resources.body(pitch: pitch, position: surface.position, size: size))
                    piece.position = SCNVector3(
                        Float(surface.position.x) * Float(pitch) / 2,
                        Float(surface.position.y) * Float(pitch) / 2,
                        Float(surface.position.z) * Float(pitch) / 2
                    )
                    cubeNode.addChildNode(piece)
                    pieces[surface.position] = piece
                    cubies.append((surface.position, piece))
                }
                let colorKey = index < chars.count ? chars[index] : "U"
                let sticker = SCNNode(geometry: resources.face(index: index, size: size, color: Self.color(for: colorKey), colorKey: colorKey))
                let distance = resources.faceDistance(pitch: pitch, size: size)
                let normal = surface.normal
                sticker.position = SCNVector3(Float(normal.x) * distance, Float(normal.y) * distance, Float(normal.z) * distance)
                switch (normal.x, normal.y, normal.z) {
                case (0, 1, 0): sticker.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
                case (0, -1, 0): sticker.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
                case (1, 0, 0): sticker.eulerAngles = SCNVector3(0, Float.pi / 2, 0)
                case (-1, 0, 0): sticker.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)
                case (0, 0, -1): sticker.eulerAngles = SCNVector3(0, Float.pi, 0)
                default: break
                }
                piece.addChildNode(sticker)
                faceNodes.append((sticker, colorKey))
            }
        }

        private static func color(for facelet: Character) -> UIColor {
            switch facelet {
            case "U": return UIColor(red: 1, green: 1, blue: 1, alpha: 1)
            case "R": return UIColor(red: 1, green: 0, blue: 0, alpha: 1)
            case "F": return UIColor(red: 0, green: 0.87, blue: 0, alpha: 1)
            case "D": return UIColor(red: 1, green: 1, blue: 0, alpha: 1)
            case "L": return UIColor(red: 1, green: 0.67, blue: 0, alpha: 1)
            case "B": return UIColor(red: 0, green: 0, blue: 1, alpha: 1)
            default: return UIColor(white: 0.5, alpha: 1)
            }
        }
    }
}
#endif

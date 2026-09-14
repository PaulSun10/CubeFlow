#if os(iOS)
import SceneKit
import SwiftUI
import Combine

struct SmartCube3DView: UIViewRepresentable {
    let facelets: String?
    let stateRevision: Int
    let fixedView: SmartCubeFixedView
    var cubeSize: Int = 3
    var events: AnyPublisher<SmartCubeCanonicalEvent, Never>?
    var connectionAttemptID: UUID?
    var isStateTrusted: Bool = true
    var diagnosticOwner = "unspecified"
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
        context.coordinator.update(
            facelets: facelets ?? CubeSurface.solved(size: cubeSize == 2 ? 2 : 3),
            stateRevision: stateRevision,
            fixedView: fixedView,
            size: cubeSize,
            events: events,
            attemptID: connectionAttemptID,
            trusted: isStateTrusted,
            tps: animationTPS,
            appearance: VirtualCubeAppearance(rawValue: appearanceRawValue) ?? .classic,
            plastic: VirtualCubePlastic(rawValue: plasticRawValue) ?? .black,
            reflections: reflections,
            customColor: UIColor(StoredColorData.decode(from: plasticColorData, fallback: StoredColorData(r: 0.5, g: 0, b: 0.5)).color)
        )
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.stop()
    }

    private static let solvedFacelets = "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB"

    final class Coordinator: NSObject {
        private let scene = SCNScene()
        private let interactionNode = SCNNode()
        private let cubeNode = SCNNode()
        private let cameraNode = SCNNode()
        private var lastStateRevision = -1
        private var dragYaw = SmartCubeFixedView.urf.yaw
        private var selectedFixedView: SmartCubeFixedView = .urf
        private var presentation = CubeTurnPresentation(facelets: SmartCube3DView.solvedFacelets)
        private var subscription: AnyCancellable?
        private var clock: Timer?
        private var attemptID: UUID?
        private var bindingGeneration = 0
        private var lastSequence: UInt64?
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

        override init() {
            super.init()
            print("[VirtualCubeLifecycle] event=coordinator_init coordinator=\(ObjectIdentifier(self))")
        }

        deinit {
            print("[VirtualCubeLifecycle] owner=\(perfOwner) event=coordinator_deinit coordinator=\(ObjectIdentifier(self)) view=\(perfView.map { String(describing: ObjectIdentifier($0)) } ?? "nil")")
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
            var nodes = 1, actionNodes = scene.rootNode.hasActions ? 1 : 0
            scene.rootNode.enumerateChildNodes { node, _ in
                nodes += 1
                if node.hasActions { actionNodes += 1 }
            }
            let pivots = cubeNode.childNodes.filter { $0.geometry == nil }.count
            let cache = resources.diagnosticCacheCounts
            print("[VirtualCubePerf] owner=\(perfOwner) renderer=\(ObjectIdentifier(self)) view=\(perfView.map { String(describing: ObjectIdentifier($0)) } ?? "nil") event=\(event) completed=\(perfCompleted) interrupted=\(perfInterrupted) nodes=\(nodes) actionNodes=\(actionNodes) pivots=\(pivots) pivotRef=\(pivot != nil) pending=\(presentation.pending.count) current=\(presentation.current != nil) cubies=\(cubies.count) faces=\(faceNodes.count) geometryCache=\(cache.geometry) materialCache=\(cache.material)")
        }

        func stop() {
            print("[VirtualCubeLifecycle] owner=\(perfOwner) event=stop coordinator=\(ObjectIdentifier(self)) view=\(perfView.map { String(describing: ObjectIdentifier($0)) } ?? "nil") subscribed=\(subscription != nil) timer=\(clock != nil)")
            bindingGeneration += 1
            subscription = nil
            clock?.invalidate()
            clock = nil
        }

        func makeView(owner: String = "test") -> SCNView {
            perfOwner = owner
            let view = SCNView(frame: .zero)
            perfView = view
            print("[VirtualCubeLifecycle] owner=\(perfOwner) event=make_view coordinator=\(ObjectIdentifier(self)) view=\(ObjectIdentifier(view))")
            view.scene = scene
            view.backgroundColor = .clear
            view.allowsCameraControl = false
            view.autoenablesDefaultLighting = false
            view.isJitteringEnabled = false
            view.antialiasingMode = .multisampling2X
            view.rendersContinuously = true
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
            clock = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            if let clock { RunLoop.main.add(clock, forMode: .common) }
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
            appearance: VirtualCubeAppearance,
            plastic: VirtualCubePlastic,
            reflections: Bool,
            customColor: UIColor
        ) {
            if fixedView != selectedFixedView {
                selectedFixedView = fixedView
                dragYaw = fixedView.yaw
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.2
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                interactionNode.eulerAngles = SCNVector3(0, dragYaw, 0)
                positionCamera()
                SCNTransaction.commit()
            }
            let size = size == 2 ? 2 : 3
            if !hasBound || self.attemptID != attemptID || presentation.size != size {
                bindingGeneration += 1
                let binding = bindingGeneration
                subscription = nil
                self.attemptID = attemptID
                hasBound = true
                lastSequence = nil
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
                print("[VirtualCubeLifecycle] owner=\(perfOwner) event=subscription_attach coordinator=\(ObjectIdentifier(self)) view=\(perfView.map { String(describing: ObjectIdentifier($0)) } ?? "nil") attached=\(subscription != nil)")
            }
            presentation.tps = min(20, max(0, tps))
            if self.appearance != appearance || resources.plastic != plastic ||
                resources.reflections != reflections || !resources.customColor.isEqual(customColor) {
                self.appearance = appearance
                resources = VirtualCubeMaterials(appearance: appearance, plastic: plastic, reflections: reflections, customColor: customColor)
                renderedState = nil
            }
            if trusted != presentation.isTrusted || facelets != presentation.canonical || stateRevision != lastStateRevision {
                // A state correction without an executable event chain is a snap, never an invented turn.
                if facelets != presentation.canonical || trusted != presentation.isTrusted {
                    presentation.resync(trusted ? facelets : nil, trusted: trusted)
                }
            }
            lastStateRevision = stateRevision
            tick()
        }

        private func receive(_ event: SmartCubeCanonicalEvent) {
            if let lastSequence, event.sequence <= lastSequence { return }
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
                if hasGap || !update.isStateTrusted {
                    presentation.resync(update.isStateTrusted ? update.facelets : nil, trusted: update.isStateTrusted)
                } else {
                    let now = ProcessInfo.processInfo.systemUptime
                    presentation.enqueue(update.move.move, target: update.facelets, timestamp: now, now: now)
                }
            }
            if case .move = event { observeTransition(from: perfPrevious) }
        }

        private func tick() {
            if perfResetPending && renderedState == presentation.settled && renderedAnimationID == nil {
                logPerformance("reset_settled")
                perfResetPending = false
            }
            guard presentation.current != nil || !presentation.pending.isEmpty ||
                renderedState != presentation.settled || renderedAnimationID != nil else { return }
            let now = ProcessInfo.processInfo.systemUptime
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
            pan.maximumNumberOfTouches = 1
            view.addGestureRecognizer(pan)
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: recognizer.view)
            recognizer.setTranslation(.zero, in: recognizer.view)

            // Only yaw is user-controlled. The top/bottom alignment stays stable.
            dragYaw += Float(translation.x) * 0.008
            dragYaw = Self.normalizedAngle(dragYaw)

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            interactionNode.eulerAngles = SCNVector3(0, dragYaw, 0)
            SCNTransaction.commit()
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
                let distance = resources.faceDistance(pitch: pitch)
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

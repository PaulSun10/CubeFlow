#if os(iOS)
import SceneKit
import SwiftUI

struct SmartCube3DView: UIViewRepresentable {
    let facelets: String?
    let stateRevision: Int
    let fixedView: SmartCubeFixedView

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        context.coordinator.makeView()
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(
            facelets: facelets ?? Self.solvedFacelets,
            stateRevision: stateRevision,
            fixedView: fixedView
        )
    }

    private static let solvedFacelets = "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB"

    final class Coordinator: NSObject {
        private let scene = SCNScene()
        private let interactionNode = SCNNode()
        private let cubeNode = SCNNode()
        private var stickerNodes: [SCNNode] = []
        private var lastExternalFacelets: String?
        private var lastStateRevision = -1
        private var dragYaw = SmartCubeFixedView.urf.yaw
        private var selectedFixedView: SmartCubeFixedView = .urf

        func makeView() -> SCNView {
            let view = SCNView(frame: .zero)
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
            installGestures(on: view)
            return view
        }

        func update(
            facelets: String,
            stateRevision: Int,
            fixedView: SmartCubeFixedView
        ) {
            if fixedView != selectedFixedView {
                selectedFixedView = fixedView
                dragYaw = fixedView.yaw
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.2
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                interactionNode.eulerAngles = SCNVector3(0, dragYaw, 0)
                SCNTransaction.commit()
            }
            if stateRevision != lastStateRevision {
                lastStateRevision = stateRevision
                lastExternalFacelets = facelets
                buildCube(facelets: facelets)
                return
            }
            guard facelets != lastExternalFacelets else { return }
            updateStickerColors(facelets: facelets)
            lastExternalFacelets = facelets
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
            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.camera?.fieldOfView = 34
            cameraNode.position = SCNVector3(0, 2.8, 7.2)
            cameraNode.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(cameraNode)
        }

        private func installLights() {
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 1_000
            ambient.light?.color = UIColor.white
            scene.rootNode.addChildNode(ambient)
        }

        private func buildCube(facelets: String) {
            cubeNode.childNodes.forEach { $0.removeFromParentNode() }
            stickerNodes.removeAll(keepingCapacity: true)

            let body = SCNNode(geometry: SCNBox(width: 3.05, height: 3.05, length: 3.05, chamferRadius: 0.16))
            let bodyMaterial = SCNMaterial()
            bodyMaterial.diffuse.contents = UIColor.black
            bodyMaterial.lightingModel = .constant
            body.geometry?.materials = [bodyMaterial]
            body.opacity = 0.95
            cubeNode.addChildNode(body)

            let chars = Array(facelets)
            for index in 0..<54 {
                let sticker = Sticker(faceletIndex: index)
                let color = Self.color(for: index < chars.count ? chars[index] : "U")
                let node = makeStickerNode(sticker: sticker, color: color)
                cubeNode.addChildNode(node)
                stickerNodes.append(node)
            }
        }

        private func updateStickerColors(facelets: String) {
            guard stickerNodes.count == 54 else {
                buildCube(facelets: facelets)
                return
            }
            let chars = Array(facelets)
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            for index in stickerNodes.indices {
                let color = Self.color(for: index < chars.count ? chars[index] : "U")
                stickerNodes[index].geometry?.firstMaterial?.diffuse.contents = color
            }
            SCNTransaction.commit()
        }

        private func makeStickerNode(sticker: Sticker, color: UIColor) -> SCNNode {
            let plane = SCNPlane(width: 0.86, height: 0.86)
            plane.cornerRadius = 0.055
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.lightingModel = .constant
            material.isDoubleSided = true
            plane.materials = [material]

            let node = SCNNode(geometry: plane)
            node.name = "sticker-\(sticker.faceletIndex)"
            node.position = Self.position(for: sticker)
            node.eulerAngles = Self.eulerAngles(for: sticker)
            return node
        }

        private struct Sticker {
            let faceletIndex: Int
            var x: Int
            var y: Int
            var z: Int
            var nx: Int
            var ny: Int
            var nz: Int

            init(faceletIndex: Int) {
                self.faceletIndex = faceletIndex
                let face = faceletIndex / 9
                let offset = faceletIndex % 9
                let row = offset / 3
                let column = offset % 3
                switch face {
                case 0:
                    x = column - 1; y = 1; z = row - 1; nx = 0; ny = 1; nz = 0
                case 1:
                    x = 1; y = 1 - row; z = 1 - column; nx = 1; ny = 0; nz = 0
                case 2:
                    x = column - 1; y = 1 - row; z = 1; nx = 0; ny = 0; nz = 1
                case 3:
                    x = column - 1; y = -1; z = 1 - row; nx = 0; ny = -1; nz = 0
                case 4:
                    x = -1; y = 1 - row; z = column - 1; nx = -1; ny = 0; nz = 0
                default:
                    x = 1 - column; y = 1 - row; z = -1; nx = 0; ny = 0; nz = -1
                }
            }

        }

        private static func position(for sticker: Sticker) -> SCNVector3 {
            let spacing: Float = 0.93
            let surface: Float = 1.56
            let x = sticker.nx == 0 ? Float(sticker.x) * spacing : Float(sticker.nx) * surface
            let y = sticker.ny == 0 ? Float(sticker.y) * spacing : Float(sticker.ny) * surface
            let z = sticker.nz == 0 ? Float(sticker.z) * spacing : Float(sticker.nz) * surface
            return SCNVector3(x, y, z)
        }

        private static func eulerAngles(for sticker: Sticker) -> SCNVector3 {
            switch (sticker.nx, sticker.ny, sticker.nz) {
            case (0, 1, 0): return SCNVector3(-Float.pi / 2, 0, 0)
            case (0, -1, 0): return SCNVector3(Float.pi / 2, 0, 0)
            case (1, 0, 0): return SCNVector3(0, Float.pi / 2, 0)
            case (-1, 0, 0): return SCNVector3(0, -Float.pi / 2, 0)
            case (0, 0, -1): return SCNVector3(0, Float.pi, 0)
            default: return SCNVector3Zero
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

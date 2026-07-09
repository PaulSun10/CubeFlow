#if os(iOS)
import SceneKit
import SwiftUI

struct SmartCube3DView: UIViewRepresentable {
    let facelets: String?
    let latestMove: SmartCubeMoveEvent?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        context.coordinator.makeView()
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(facelets: facelets ?? Self.solvedFacelets, latestMove: latestMove)
    }

    private static let solvedFacelets = "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB"

    final class Coordinator: NSObject {
        private let scene = SCNScene()
        private let rootNode = SCNNode()
        private var stickerNodes: [StickerNode] = []
        private var lastExternalFacelets: String?
        private var lastMoveID: UUID?
        private var pendingMoves: [SmartCubeMoveEvent] = []
        private var isAnimating = false

        func makeView() -> SCNView {
            let view = SCNView(frame: .zero)
            view.scene = scene
            view.backgroundColor = .clear
            view.allowsCameraControl = true
            view.autoenablesDefaultLighting = false
            view.isJitteringEnabled = true
            view.antialiasingMode = .multisampling4X

            scene.rootNode.addChildNode(rootNode)
            installCamera()
            installLights()
            rebuildCube(facelets: SmartCube3DView.solvedFacelets)
            return view
        }

        func update(facelets: String, latestMove: SmartCubeMoveEvent?) {
            if let latestMove, latestMove.id != lastMoveID {
                lastMoveID = latestMove.id
                lastExternalFacelets = facelets
                pendingMoves.append(latestMove)
                startNextMoveIfNeeded()
                return
            }

            guard !isAnimating, pendingMoves.isEmpty, facelets != lastExternalFacelets else { return }
            lastExternalFacelets = facelets
            rebuildCube(facelets: facelets)
        }

        private func installCamera() {
            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.camera?.fieldOfView = 34
            cameraNode.position = SCNVector3(4.2, 3.6, 5.2)
            cameraNode.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(cameraNode)
        }

        private func installLights() {
            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .omni
            key.light?.intensity = 650
            key.position = SCNVector3(2.5, 4.5, 5)
            scene.rootNode.addChildNode(key)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 450
            ambient.light?.color = UIColor.secondaryLabel
            scene.rootNode.addChildNode(ambient)
        }

        private func rebuildCube(facelets: String) {
            rootNode.childNodes.forEach { $0.removeFromParentNode() }
            stickerNodes = []

            let body = SCNNode(geometry: SCNBox(width: 3.05, height: 3.05, length: 3.05, chamferRadius: 0.16))
            body.geometry?.firstMaterial?.diffuse.contents = UIColor.black
            body.geometry?.firstMaterial?.roughness.contents = 0.78
            body.opacity = 0.92
            rootNode.addChildNode(body)

            let chars = Array(facelets)
            for index in 0..<54 {
                let sticker = Sticker(faceletIndex: index)
                let color = Self.color(for: index < chars.count ? chars[index] : "U")
                let node = makeStickerNode(sticker: sticker, color: color)
                rootNode.addChildNode(node)
                stickerNodes.append(StickerNode(sticker: sticker, node: node))
            }
        }

        private func makeStickerNode(sticker: Sticker, color: UIColor) -> SCNNode {
            let plane = SCNPlane(width: 0.86, height: 0.86)
            plane.cornerRadius = 0.055
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.roughness.contents = 0.72
            material.lightingModel = .physicallyBased
            material.isDoubleSided = true
            plane.materials = [material]

            let node = SCNNode(geometry: plane)
            node.name = "sticker-\(sticker.faceletIndex)"
            node.position = Self.position(for: sticker)
            node.eulerAngles = Self.eulerAngles(for: sticker)
            return node
        }

        private func startNextMoveIfNeeded() {
            guard !isAnimating, !pendingMoves.isEmpty else { return }
            let move = pendingMoves.removeFirst()
            guard let descriptor = MoveDescriptor(move.move) else {
                startNextMoveIfNeeded()
                return
            }
            animate(descriptor: descriptor)
        }

        private func animate(descriptor: MoveDescriptor) {
            let affectedIndices = stickerNodes.indices.filter { descriptor.affects(stickerNodes[$0].sticker) }
            guard !affectedIndices.isEmpty else {
                startNextMoveIfNeeded()
                return
            }

            isAnimating = true
            let pivot = SCNNode()
            rootNode.addChildNode(pivot)

            for index in affectedIndices {
                let stickerNode = stickerNodes[index]
                let transform = stickerNode.node.transform
                stickerNode.node.removeFromParentNode()
                pivot.addChildNode(stickerNode.node)
                stickerNode.node.transform = transform
            }

            SCNTransaction.begin()
            SCNTransaction.animationDuration = descriptor.animationDuration
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            SCNTransaction.completionBlock = { [weak self, weak pivot] in
                guard let self, let pivot else { return }
                for index in affectedIndices {
                    let node = self.stickerNodes[index].node
                    let worldTransform = node.worldTransform
                    node.removeFromParentNode()
                    self.rootNode.addChildNode(node)
                    node.transform = self.rootNode.convertTransform(worldTransform, from: nil)
                    self.stickerNodes[index].sticker.apply(descriptor: descriptor)
                }
                pivot.removeFromParentNode()
                self.isAnimating = false
                self.startNextMoveIfNeeded()
            }
            pivot.rotation = descriptor.sceneRotation
            SCNTransaction.commit()
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

            mutating func apply(descriptor: MoveDescriptor) {
                for _ in 0..<descriptor.modelTurns {
                    rotateClockwise(face: descriptor.face)
                }
            }

            private mutating func rotateClockwise(face: Character) {
                switch face {
                case "U":
                    (x, z) = (-z, x)
                    (nx, nz) = (-nz, nx)
                case "D", "E":
                    (x, z) = (z, -x)
                    (nx, nz) = (nz, -nx)
                case "F", "S":
                    (x, y) = (y, -x)
                    (nx, ny) = (ny, -nx)
                case "B":
                    (x, y) = (-y, x)
                    (nx, ny) = (-ny, nx)
                case "R":
                    (y, z) = (z, -y)
                    (ny, nz) = (nz, -ny)
                case "L", "M":
                    (y, z) = (-z, y)
                    (ny, nz) = (-nz, ny)
                default:
                    break
                }
            }
        }

        private struct StickerNode {
            var sticker: Sticker
            let node: SCNNode
        }

        private struct MoveDescriptor {
            let face: Character
            let modelTurns: Int
            let axis: SCNVector3
            let baseAngle: Float

            init?(_ move: String) {
                guard let face = move.first, "URFDLBMES".contains(face) else { return nil }
                self.face = face
                if move.hasSuffix("2") {
                    modelTurns = 2
                } else if move.contains("'") {
                    modelTurns = 3
                } else {
                    modelTurns = 1
                }

                switch face {
                case "U": axis = SCNVector3(0, 1, 0); baseAngle = -.pi / 2
                case "D", "E": axis = SCNVector3(0, 1, 0); baseAngle = .pi / 2
                case "F", "S": axis = SCNVector3(0, 0, 1); baseAngle = -.pi / 2
                case "B": axis = SCNVector3(0, 0, 1); baseAngle = .pi / 2
                case "R": axis = SCNVector3(1, 0, 0); baseAngle = -.pi / 2
                case "L", "M": axis = SCNVector3(1, 0, 0); baseAngle = .pi / 2
                default: return nil
                }
            }

            var sceneRotation: SCNVector4 {
                SCNVector4(axis.x, axis.y, axis.z, baseAngle * Float(modelTurns))
            }

            var animationDuration: TimeInterval {
                modelTurns == 2 ? 0.13 : 0.09
            }

            func affects(_ sticker: Sticker) -> Bool {
                switch face {
                case "U": return sticker.y == 1
                case "R": return sticker.x == 1
                case "F": return sticker.z == 1
                case "D": return sticker.y == -1
                case "L": return sticker.x == -1
                case "B": return sticker.z == -1
                case "M": return sticker.x == 0
                case "E": return sticker.y == 0
                case "S": return sticker.z == 0
                default: return false
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
            case "U": return .white
            case "R": return .systemRed
            case "F": return .systemGreen
            case "D": return .systemYellow
            case "L": return .systemOrange
            case "B": return .systemBlue
            default: return .systemGray
            }
        }
    }
}
#endif

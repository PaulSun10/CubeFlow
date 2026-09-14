#if os(iOS)
import SceneKit
import SwiftUI
import Combine
import Testing
@testable import CubeFlow

@MainActor
struct VirtualCubeMaterialsTests {
    @Test func minimalMaterialsRemainFrozen() throws {
        for reflections in [false, true] {
            let clear = try #require(VirtualCubeMaterials(appearance: .minimal, plastic: .clear, reflections: reflections, customColor: .purple).body(pitch: 1).firstMaterial)
            #expect(clear.blendMode == .alpha)
            #expect(clear.shaderModifiers == nil)
            #expect((clear.diffuse.contents as? UIColor) == UIColor(white: 0.96, alpha: 1))
            #expect(abs(clear.transparency - 0.36) < 0.000001)
        }
        let white = try #require(VirtualCubeMaterials(appearance: .minimal, plastic: .white, reflections: true, customColor: .purple).body(pitch: 1).firstMaterial)
        #expect((white.emission.contents as? UIColor) == UIColor(white: 0.16, alpha: 1))
        #expect(white.diffuse.intensity == 1)
    }

    @Test func clearCompositingPreservesBackdropWithoutGrayAttenuation() throws {
        func pixels(_ image: UIImage) throws -> [UInt8] {
            let cgImage = try #require(image.cgImage)
            var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
            let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try #require(CGContext(data: buffer.baseAddress, width: 64, height: 64,
                                                    bitsPerComponent: 8, bytesPerRow: 64 * 4, space: space,
                                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            }
            return bytes
        }
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.24, green: 0.48, blue: 0.70, alpha: 1)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 1.4
        camera.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(camera)
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .directional
        light.light?.intensity = 550
        light.eulerAngles = SCNVector3(-0.6, -0.5, 0)
        scene.rootNode.addChildNode(light)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        let baseline = try pixels(renderer.snapshot(atTime: 0, with: CGSize(width: 64, height: 64), antialiasingMode: .none))
        for reflections in [false, true] {
            let resources = VirtualCubeMaterials(appearance: .classic, plastic: .clear, reflections: reflections, customColor: .purple)
            let node = SCNNode(geometry: resources.body(pitch: 1))
            node.eulerAngles = SCNVector3(0.2, 0.4, 0)
            scene.rootNode.addChildNode(node)
            let result = try pixels(renderer.snapshot(atTime: 0, with: CGSize(width: 64, height: 64), antialiasingMode: .none))
            var changed = 0
            var minimumDelta = 0
            for offset in stride(from: 0, to: result.count, by: 4) {
                for channel in 0..<3 {
                    minimumDelta = min(minimumDelta, Int(result[offset + channel]) - Int(baseline[offset + channel]))
                    if Int(result[offset + channel]) > Int(baseline[offset + channel]) + 2 { changed += 1 }
                }
            }
            #expect(changed > 0)
            #expect(minimumDelta >= -2)
            node.removeFromParentNode()
        }
    }

    @Test func stickerlessBodiesLeaveDeepRecessesAndBlockLongSightlines() throws {
        for size in [2, 3] {
            let pitch = CGFloat(3) / CGFloat(size)
            let resources = VirtualCubeMaterials(appearance: .stickerless, plastic: .black, reflections: false, customColor: .purple)
            let scene = SCNScene()
            let root = scene.rootNode
            var materialIDs: Set<ObjectIdentifier> = []
            var meshStats: [Int: Set<String>] = [:]
            for position in Set(CubeSurface.all(size: size).map(\.position)) {
                let body = resources.body(pitch: pitch, position: position, size: size)
                #expect(body === resources.body(pitch: pitch, position: position, size: size))
                let source = try #require(body.sources(for: .vertex).first)
                let element = try #require(body.elements.first)
                #expect(source.vectorCount > 24 && source.vectorCount <= 192)
                #expect(body.elements.count == 1 && element.primitiveCount <= 380)
                let faceCount = CubeSurface.all(size: size).filter { $0.position == position }.count
                meshStats[faceCount, default: []].insert("\(source.vectorCount) vertices / \(element.primitiveCount) triangles")
                let indices = element.data.withUnsafeBytes { bytes in
                    (0..<(element.primitiveCount * 3)).map { Int(bytes.loadUnaligned(fromByteOffset: $0 * 2, as: UInt16.self)) }
                }
                var edges: [String: Int] = [:]
                for index in stride(from: 0, to: indices.count, by: 3) {
                    let triangle = Array(indices[index..<(index + 3)])
                    #expect(Set(triangle).count == 3)
                    for offset in 0..<3 {
                        let a = triangle[offset], b = triangle[(offset + 1) % 3]
                        edges["\(min(a, b))-\(max(a, b))", default: 0] += 1
                    }
                }
                #expect(edges.values.allSatisfy { $0 == 2 })
                #expect(source.vectorCount - edges.count + element.primitiveCount == 2)
                let normals = try #require(body.sources(for: .normal).first)
                normals.data.withUnsafeBytes { bytes in
                    for index in 0..<normals.vectorCount {
                        let offset = normals.dataOffset + index * normals.dataStride
                        let x = bytes.loadUnaligned(fromByteOffset: offset, as: Float.self)
                        let y = bytes.loadUnaligned(fromByteOffset: offset + 4, as: Float.self)
                        let z = bytes.loadUnaligned(fromByteOffset: offset + 8, as: Float.self)
                        #expect(x.isFinite && y.isFinite && z.isFinite)
                        #expect(abs(x * x + y * y + z * z - 1) < 0.00001)
                    }
                }
                let bounds = body.boundingBox
                let lower = [bounds.min.x, bounds.min.y, bounds.min.z]
                let upper = [bounds.max.x, bounds.max.y, bounds.max.z]
                for axis in 0..<3 {
                    let half = Float(pitch) / 2
                    #expect(lower[axis] >= -half && upper[axis] <= half)
                    if position[axis] != -(size - 1) { #expect(lower[axis] == -half) }
                    if position[axis] != size - 1 { #expect(upper[axis] == half) }
                    if position[axis] == size - 1 {
                        #expect(upper[axis] >= Float(pitch) * 0.418 - 0.000001)
                        #expect(upper[axis] <= Float(pitch) * 0.48)
                    }
                    if position[axis] == -(size - 1) {
                        #expect(lower[axis] <= -Float(pitch) * 0.418 + 0.000001)
                        #expect(lower[axis] >= -Float(pitch) * 0.48)
                    }
                }
                materialIDs.insert(ObjectIdentifier(try #require(body.firstMaterial)))
                let node = SCNNode(geometry: body)
                node.position = SCNVector3(Float(position.x) * Float(pitch) / 2,
                                          Float(position.y) * Float(pitch) / 2,
                                          Float(position.z) * Float(pitch) / 2)
                root.addChildNode(node)
            }
            #expect(materialIDs.count == 1)
            for count in meshStats.keys.sorted() {
                print("Stickerless \(size)x\(size), \(count) exposed faces: \(meshStats[count]!.sorted())")
            }
            SCNTransaction.flush()
            let seams: [Float] = size == 2 ? [0] : [-0.5, 0.5]
            for axis in 0..<3 {
                for sign in [Float(-1), Float(1)] {
                    // SceneKit rejects exact shared triangle edges even on touching SCNBoxes.
                    // Test the mesh on both sides of each seam; exact coverage is checked above.
                    for seam in seams.flatMap({ [$0 - 0.005, $0 + 0.005] }) {
                        var from = SIMD3<Float>(repeating: seam)
                        // Avoid coplanar triangle diagonals as well as shared cell edges.
                        from[(axis + 1) % 3] += 0.001
                        var to = from
                        from[axis] = 4 * sign
                        to[axis] = -4 * sign
                        let hits = root.hitTestWithSegment(from: SCNVector3(from.x, from.y, from.z),
                                                          to: SCNVector3(to.x, to.y, to.z),
                                                          options: [SCNHitTestOption.backFaceCulling.rawValue: true,
                                                                    SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.all.rawValue,
                                                                    SCNHitTestOption.clipToZRange.rawValue: false])
                        let hit = try #require(hits.max {
                            let a = $0.worldCoordinates, b = $1.worldCoordinates
                            return [a.x, a.y, a.z][axis] * sign < [b.x, b.y, b.z][axis] * sign
                        })
                        let point = hit.worldCoordinates
                        let coordinate = [point.x, point.y, point.z][axis]
                        #expect(coordinate * sign >= sqrt(1 - seam * seam - (seam + 0.001) * (seam + 0.001)) - 0.002)
                        #expect(coordinate * sign <= 1.5 - Float(pitch) * 0.18)
                    }
                }
            }
        }
    }

    @Test func stickerlessProfilesDistinguishPieceTypes() throws {
        for size in [2, 3] {
            let pitch = CGFloat(3) / CGFloat(size)
            let half = pitch * 0.49
            let resources = VirtualCubeMaterials(appearance: .stickerless, plastic: .black, reflections: false, customColor: .purple)
            let corners: [(Int, CGPoint)] = [(0, CGPoint(x: half, y: -half)),
                                             (size - 1, CGPoint(x: -half, y: -half)),
                                             ((size - 1) * size, CGPoint(x: half, y: half)),
                                             (size * size - 1, CGPoint(x: -half, y: half))]
            for (index, innerPoint) in corners {
                let shape = try #require(resources.face(index: index, size: size, color: .red, colorKey: "R") as? SCNShape)
                let path = try #require(shape.path)
                var curves: [CGPoint] = []
                var lineEnds: [CGPoint] = []
                path.cgPath.applyWithBlock { element in
                    if element.pointee.type == .addQuadCurveToPoint { curves.append(element.pointee.points[0]) }
                    if element.pointee.type == .addLineToPoint { lineEnds.append(element.pointee.points[0]) }
                }
                #expect(curves.count == 3)
                #expect(!curves.contains(innerPoint) && lineEnds.contains(innerPoint))
                #expect(abs(shape.extrusionDepth - pitch * 0.085) < 0.000001)
                #expect(abs(shape.chamferRadius - pitch * 0.008) < 0.000001)
            }
            if size == 3 {
                for (index, radius) in [(1, 0.24), (4, 0.40)] {
                    let shape = try #require(resources.face(index: index, size: size, color: .red, colorKey: "R") as? SCNShape)
                    let path = try #require(shape.path)
                    var start = CGPoint.zero
                    path.cgPath.applyWithBlock { element in
                        if element.pointee.type == .moveToPoint { start = element.pointee.points[0] }
                    }
                    #expect(abs(start.x - (-half + radius)) < 0.000001)
                }
            }
        }
    }

    @Test func whiteFillIsNeutralAndClearRetainsIndependentTransparency() throws {
        let white = try #require(VirtualCubeMaterials(appearance: .classic, plastic: .white, reflections: true, customColor: .purple).body(pitch: 1).firstMaterial)
        #expect((white.diffuse.contents as? UIColor) == UIColor.white)
        #expect(white.transparency == 1 && white.writesToDepthBuffer)
        let emission = try #require(white.emission.contents as? UIColor)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #expect(emission.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        #expect(red == 0 && green == 0 && blue == 0)
        #expect(!white.locksAmbientWithDiffuse)
        #expect((white.ambient.contents as? UIColor) == UIColor.white)
        #expect(white.ambient.intensity == 2)
        #expect(abs(white.diffuse.intensity - 0.65) < 0.000001)
        for appearance in [VirtualCubeAppearance.classic, .stickerless] {
            for reflections in [false, true] {
                let clear = try #require(VirtualCubeMaterials(appearance: appearance, plastic: .clear, reflections: reflections, customColor: .purple).body(pitch: 1).firstMaterial)
                #expect(abs(clear.transparency - 0.68) < 0.000001)
                #expect(clear.transparencyMode == .dualLayer)
                #expect(clear.blendMode == .add)
                #expect((clear.diffuse.contents as? UIColor) == UIColor.black)
                #expect(abs(clear.shininess - 0.35) < 0.000001)
                #expect((clear.specular.contents as? UIColor) == (reflections ? UIColor(white: 0.16, alpha: 1) : UIColor.black))
                #expect(clear.shaderModifiers?[.surface]?.contains("0.055 + 0.30 * rim * rim") == true)
            }
        }
    }

    @Test func activeTurnResyncRestoresReusableCubies() throws {
        for size in [2, 3] {
            for appearance in VirtualCubeAppearance.allCases {
                let events = PassthroughSubject<SmartCubeCanonicalEvent, Never>()
                let coordinator = SmartCube3DView.Coordinator()
                let view = coordinator.makeView()
                defer { coordinator.stop() }
                let solved = CubeSurface.solved(size: size)
                func update(_ state: String, revision: Int) {
                    coordinator.update(facelets: state, stateRevision: revision, fixedView: .urf, size: size,
                                       events: events.eraseToAnyPublisher(), attemptID: nil, trusted: true, tps: 1,
                                       appearance: appearance, plastic: .black, reflections: false, customColor: .purple)
                }
                update(solved, revision: 0)
                let cube = try #require(view.scene?.rootNode.childNodes.first?.childNodes.first)
                let cubies = cube.childNodes
                let positions = cubies.map(\.position)
                let target = try #require(CubeLayerTurn("R2")?.applying(to: solved, size: size))
                events.send(.move(.init(sequence: 1, move: .init(move: "R2", serial: nil, face: nil, direction: nil,
                                                               localTimestamp: Date(), cubeTimestampMilliseconds: nil), facelets: target)))
                update(target, revision: 1)
                #expect(cube.childNodes.contains { $0.geometry == nil && !$0.childNodes.isEmpty })
                events.send(.boundary(.init(sequence: 2, reason: .resync, facelets: target)))
                update(target, revision: 2)
                #expect(Set(cube.childNodes.map(ObjectIdentifier.init)) == Set(cubies.map(ObjectIdentifier.init)))
                for (node, position) in zip(cubies, positions) {
                    #expect(node.parent === cube)
                    #expect(node.position.x == position.x && node.position.y == position.y && node.position.z == position.z)
                }
            }
        }
    }

    @Test func stickerlessClosedShellsStayOpaqueAndCached() throws {
        for size in [2, 3] {
            let resources = VirtualCubeMaterials(appearance: .stickerless, plastic: .black, reflections: false, customColor: .purple)
            for index in 0..<(size * size) {
                let red = resources.face(index: index, size: size, color: .red, colorKey: "R")
                let blue = resources.face(index: index, size: size, color: .blue, colorKey: "B")
                #expect(red is SCNShape)
                #expect(!red.sources.isEmpty && !red.elements.isEmpty)
                #expect(red === resources.face(index: index, size: size, color: .red, colorKey: "R"))
                #expect(red.firstMaterial !== blue.firstMaterial)
                #expect(red.firstMaterial?.isDoubleSided == false)
                #expect(red.firstMaterial?.writesToDepthBuffer == true)
                #expect(red.firstMaterial?.transparency == 1)
            }
        }
    }

    @Test func naturalUsesSofterSinglePassResponseThanWhite() throws {
        for reflections in [false, true] {
            let white = try #require(VirtualCubeMaterials(appearance: .classic, plastic: .white, reflections: reflections, customColor: .purple).body(pitch: 1).firstMaterial)
            let natural = try #require(VirtualCubeMaterials(appearance: .classic, plastic: .natural, reflections: reflections, customColor: .purple).body(pitch: 1).firstMaterial)
            #expect(white.transparency == 1 && white.writesToDepthBuffer)
            #expect(natural.transparency < 1)
            #expect(natural.transparencyMode == .aOne)
            #expect((natural.diffuse.contents as? UIColor) != (white.diffuse.contents as? UIColor))
            if reflections {
                #expect(natural.shininess < white.shininess)
                #expect((natural.specular.contents as? UIColor) != (white.specular.contents as? UIColor))
            }
        }
    }

    @Test func settledMovesReuseAllVisualNodes() throws {
        func identities(_ node: SCNNode) -> Set<ObjectIdentifier> {
            node.childNodes.reduce(into: [ObjectIdentifier(node)]) { result, child in
                result.formUnion(identities(child))
            }
        }
        for size in [2, 3] {
            for appearance in VirtualCubeAppearance.allCases {
                let coordinator = SmartCube3DView.Coordinator()
                let view = coordinator.makeView()
                defer { coordinator.stop() }
                var state = CubeSurface.solved(size: size)
                var revision = 0
                func update() {
                    coordinator.update(facelets: state, stateRevision: revision, fixedView: .urf, size: size,
                                       events: nil, attemptID: nil, trusted: true, tps: 10,
                                       appearance: appearance, plastic: .black, reflections: false, customColor: .purple)
                }
                update()
                let root = try #require(view.scene?.rootNode)
                let original = identities(root)
                for face in "URFDLB" {
                    for suffix in ["", "'", "2"] {
                        state = try #require(CubeLayerTurn("\(face)\(suffix)")?.applying(to: state, size: size))
                        revision += 1
                        update()
                        #expect(identities(root) == original)
                    }
                }
            }
        }
    }

    @Test func transparencyIsIndependentOfReflectionsAndCapsStayOpaque() throws {
        for appearance in VirtualCubeAppearance.allCases {
            for reflections in [false, true] {
                let resources = VirtualCubeMaterials(appearance: appearance, plastic: .clear, reflections: reflections, customColor: .purple)
                let body = try #require(resources.body(pitch: 1).firstMaterial)
                #expect(body.transparency > 0 && body.transparency < 1)
                #expect(body.transparencyMode == .dualLayer)
                let cap = try #require(resources.face(index: 0, size: 3, color: .red, colorKey: "R").firstMaterial)
                #expect(cap.transparency == 1)
            }
        }
    }

    @Test func flatPlasticColorsAndMaterialReuse() throws {
        for plastic in [VirtualCubePlastic.black, .white, .custom] {
            let resources = VirtualCubeMaterials(appearance: .classic, plastic: plastic, reflections: false, customColor: .purple)
            let body = resources.body(pitch: 1)
            #expect(body === resources.body(pitch: 1))
            let material = try #require(body.firstMaterial)
            #expect(material.lightingModel == .constant)
            let expected: UIColor = plastic == .black ? .black : (plastic == .white ? .white : .purple)
            #expect((material.diffuse.contents as? UIColor)?.isEqual(expected) == true)
            let cap = resources.face(index: 0, size: 3, color: .red, colorKey: "R")
            #expect(cap === resources.face(index: 0, size: 3, color: .red, colorKey: "R"))
        }
    }

    @Test func classicDimensionsAndMinimalFlushPatches() throws {
        let classic = VirtualCubeMaterials(appearance: .classic, plastic: .black, reflections: false, customColor: .purple)
        let body = try #require(classic.body(pitch: 1) as? SCNBox)
        #expect(abs(body.width - 0.94) < 0.000001)
        #expect(abs(body.chamferRadius - 0.94 * 0.045) < 0.000001)
        for size in [2, 3] {
            let minimal = VirtualCubeMaterials(appearance: .minimal, plastic: .black, reflections: true, customColor: .purple)
            let cap = try #require(minimal.face(index: 0, size: size, color: .white, colorKey: "U") as? SCNPlane)
            #expect(cap.width == CGFloat(3) / CGFloat(size))
            #expect(cap.cornerRadius == 0)
            #expect(cap.firstMaterial?.lightingModel == .constant)
        }
    }

    @Test func customColorSurvivesIndependentPreferenceSwitches() throws {
        let suite = "VirtualCubeMaterialsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let appearance = AppStorage(wrappedValue: "classic", "smartCubeAppearance", store: defaults)
        let plastic = AppStorage(wrappedValue: "black", "smartCubeInternalPlastic", store: defaults)
        let reflections = AppStorage(wrappedValue: false, "smartCubeReflections", store: defaults)
        let color = AppStorage<Data?>("smartCubePlasticColorData", store: defaults)
        let purple = StoredColorData(r: 0.5, g: 0, b: 0.5)
        color.wrappedValue = purple.encodedData
        plastic.wrappedValue = "custom"
        reflections.wrappedValue = true
        for value in VirtualCubeAppearance.allCases { appearance.wrappedValue = value.rawValue }
        #expect(plastic.wrappedValue == "custom" && reflections.wrappedValue)
        plastic.wrappedValue = "black"
        plastic.wrappedValue = "custom"
        #expect(StoredColorData.decode(from: color.wrappedValue, fallback: .init(r: 0, g: 0, b: 0)) == purple)
    }
}
#endif

#if os(iOS)
import SceneKit
import SwiftUI

nonisolated enum VirtualCubePlastic: String, CaseIterable, Identifiable {
    case black, white, natural, clear, custom
    var id: String { rawValue }
    var localizedKey: String { "smart_cube.plastic.\(rawValue)" }
}

/// Only visual resources live here; logical cubies and layer membership are unchanged.
final class VirtualCubeMaterials {
    private var geometryCache: [String: SCNGeometry] = [:]
    private var materialCache: [String: SCNMaterial] = [:]
    private var cachedBodyMaterial: SCNMaterial?
    var diagnosticCacheCounts: (geometry: Int, material: Int) {
        (geometryCache.count, materialCache.count + (cachedBodyMaterial == nil ? 0 : 1))
    }
    let appearance: VirtualCubeAppearance
    let plastic: VirtualCubePlastic
    let reflections: Bool
    let customColor: UIColor

    init(appearance: VirtualCubeAppearance, plastic: VirtualCubePlastic, reflections: Bool, customColor: UIColor) {
        self.appearance = appearance
        self.plastic = plastic
        self.reflections = reflections
        self.customColor = customColor
    }

    func body(pitch: CGFloat, position: SIMD3<Int> = .zero, size: Int = 3) -> SCNGeometry {
        let key = appearance == .stickerless ? "body-\(pitch)-\(size)-\(position)" : "body-\(pitch)"
        if let cached = geometryCache[key] { return cached }
        let geometry: SCNGeometry
        if appearance == .stickerless {
            geometry = solidBody(pitch: Float(pitch), position: position, size: size)
        } else {
            let width = appearance == .classic ? pitch - 0.06 : pitch - 0.004
            let radius = appearance == .minimal ? 0 : width * 0.045
            let box = SCNBox(width: width, height: width, length: width, chamferRadius: radius)
            if appearance == .minimal { box.chamferSegmentCount = 3 }
            geometry = box
        }
        geometry.materials = [bodyMaterial()]
        geometryCache[key] = geometry
        return geometry
    }

    private func bodyMaterial() -> SCNMaterial {
        if let cachedBodyMaterial { return cachedBodyMaterial }
        let color: UIColor
        switch plastic {
        case .black: color = .black
        case .white: color = .white
        case .natural: color = UIColor(red: 0.94, green: 0.90, blue: 0.81, alpha: 1)
        case .clear:
            // Minimal is frozen; physical appearances have no pigmented transmission layer.
            color = appearance == .minimal ? UIColor(white: 0.96, alpha: 1) : .black
        case .custom: color = customColor
        }
        let material = makeMaterial(color: color, physical: reflections)
        if plastic == .clear {
            // Add only neutral surface cues; alpha-blending a shaded diffuse color would
            // attenuate the background into smoky gray. No refraction or framebuffer reads.
            material.transparency = appearance == .minimal ? 0.36 : 0.68
            material.transparencyMode = .dualLayer
            material.writesToDepthBuffer = false
            if appearance != .minimal {
                material.blendMode = .add
                material.specular.contents = reflections ? UIColor(white: 0.16, alpha: 1) : UIColor.black
                material.shininess = 0.35
                material.shaderModifiers = [.surface: """
                    #pragma body
                    float rim = 1.0 - clamp(abs(dot(normalize(_surface.normal), normalize(_surface.view))), 0.0, 1.0);
                    _surface.emission.rgb = float3(0.055 + 0.30 * rim * rim);
                    """
                ]
            }
        } else if plastic == .natural {
            material.transparency = 0.94
            material.transparencyMode = .aOne
            material.writesToDepthBuffer = false
            if reflections {
                material.specular.contents = UIColor(white: 0.035, alpha: 1)
                material.shininess = 0.08
            }
        } else if plastic == .white && reflections {
            if appearance == .classic {
                // Neutral ambient illumination, not self-emission. Reduce the direct diffuse
                // term to leave headroom for broad highlights rather than clipping to white.
                material.locksAmbientWithDiffuse = false
                material.ambient.contents = UIColor.white
                material.ambient.intensity = 2
                material.diffuse.intensity = 0.65
                material.specular.contents = UIColor(white: 0.10, alpha: 1)
            } else {
                material.emission.contents = UIColor(white: 0.16, alpha: 1)
            }
        }
        cachedBodyMaterial = material
        return material
    }

    private func solidBody(pitch: Float, position: SIMD3<Int>, size: Int) -> SCNGeometry {
        // A rounded deep foundation is clipped to this cell and merged into its body.
        // It blocks long sightlines without exposing a square wall or a shared plate.
        var points = VirtualCubieBodyMesh.deepFoundation(pitch: pitch, position: position, size: size)
        for (index, surface) in CubeSurface.all(size: size).enumerated() where surface.position == position {
            let width = CGFloat(pitch)
            let radii = junctionRadii(index: index, size: size, pitch: width)
            let path = radii.allSatisfy { $0 == width * 0.40 }
                ? roundedCenter(pitch: width)
                : roundedPatch(width: width * 0.98, radii: radii)
            // Stay inset under the approved shell and overlap its back by 0.003 pitch.
            // Multiple support contours become one closed, connected corner/edge body.
            for point in VirtualCubieBodyMesh.sample(path: path) {
                let u = Float(point.x) * 0.96
                let v = Float(point.y) * 0.96
                let d = pitch * 0.418
                switch (surface.normal.x, surface.normal.y, surface.normal.z) {
                case (0, 1, 0): points.append(SIMD3(u, d, -v))
                case (0, -1, 0): points.append(SIMD3(u, -d, v))
                case (1, 0, 0): points.append(SIMD3(d, v, -u))
                case (-1, 0, 0): points.append(SIMD3(-d, v, u))
                case (0, 0, -1): points.append(SIMD3(-u, v, -d))
                default: points.append(SIMD3(u, v, d))
                }
            }
        }
        return VirtualCubieBodyMesh.geometry(enclosing: points, tolerance: pitch * 0.00001)
    }

    func face(index: Int, size: Int, color: UIColor, colorKey: Character) -> SCNGeometry {
        let pitch = CGFloat(3) / CGFloat(size)
        let radii = junctionRadii(index: index, size: size, pitch: pitch)
        let key = "face-\(size)-\(radii)-\(colorKey)"
        if let cached = geometryCache[key] { return cached }
        let geometry: SCNGeometry
        switch appearance {
        case .classic:
            let plane = SCNPlane(width: (pitch - 0.06) * 0.88, height: (pitch - 0.06) * 0.88)
            plane.cornerRadius = (pitch - 0.06) * 0.055
            geometry = plane
        case .minimal:
            // Flush opaque patches meet without deliberately exposing a seam at rest.
            geometry = SCNPlane(width: pitch, height: pitch)
        case .stickerless:
            let path = radii.allSatisfy { $0 == pitch * 0.40 }
                ? roundedCenter(pitch: pitch)
                : roundedPatch(width: pitch * 0.98, radii: radii)
            let shape = SCNShape(path: path, extrusionDepth: pitch * 0.085)
            shape.chamferRadius = pitch * 0.008
            shape.chamferMode = .both
            geometry = shape
        }
        let materialKey = String(colorKey)
        let material: SCNMaterial
        if let cached = materialCache[materialKey] { material = cached }
        else {
            material = makeMaterial(color: color, physical: reflections && appearance == .stickerless)
            // Planes need both sides during turns; closed shells do not.
            material.isDoubleSided = appearance != .stickerless
            materialCache[materialKey] = material
        }
        geometry.materials = [material]
        geometryCache[key] = geometry
        return geometry
    }

    func faceDistance(pitch: CGFloat) -> Float {
        switch appearance {
        case .classic: return Float((pitch - 0.06) / 2 + 0.001)
        case .minimal: return Float(pitch / 2)
        case .stickerless: return Float(pitch * (0.5 - 0.085 / 2))
        }
    }

    private func makeMaterial(color: UIColor, physical: Bool) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = physical ? .blinn : .constant
        material.specular.contents = physical ? UIColor(white: 0.14, alpha: 1) : UIColor.black
        material.shininess = 0.16
        return material
    }

    /// Piece type changes only inward junctions; outer silhouette rounding stays fixed.
    private func junctionRadii(index: Int, size: Int, pitch: CGFloat) -> [CGFloat] {
        let row = (index % (size * size)) / size
        let column = index % size
        let isCorner = (row == 0 || row == size - 1) && (column == 0 || column == size - 1)
        let isCenter = row > 0 && row < size - 1 && column > 0 && column < size - 1
        return [(row + 1, column), (row + 1, column + 1), (row, column + 1), (row, column)].map { r, c in
            let interior = r > 0 && r < size && c > 0 && c < size
            if !interior { return pitch * 0.025 }
            if isCorner { return 0 }
            return pitch * (isCenter ? 0.40 : 0.24)
        }
    }

    private func roundedCenter(pitch: CGFloat) -> UIBezierPath {
        let h = pitch * 0.49
        let r = pitch * 0.40
        let k: CGFloat = 0.70
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -h + r, y: -h))
        // Four tangent-continuous cubics approximate a generous rounded square, not an
        // exact icon mask. Short straight sides keep the center distinctly square.
        for turn in 0..<4 {
            func rotated(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                switch turn {
                case 1: return CGPoint(x: -y, y: x)
                case 2: return CGPoint(x: -x, y: -y)
                case 3: return CGPoint(x: y, y: -x)
                default: return CGPoint(x: x, y: y)
                }
            }
            path.addLine(to: rotated(h - r, -h))
            path.addCurve(to: rotated(h, -h + r),
                          controlPoint1: rotated(h - r + k * r, -h),
                          controlPoint2: rotated(h, -h + r - k * r))
        }
        path.close()
        path.flatness = 0.008
        return path
    }

    private func roundedPatch(width: CGFloat, radii: [CGFloat]) -> UIBezierPath {
        let h = width / 2
        let r = radii
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -h + r[0], y: -h))
        path.addLine(to: CGPoint(x: h - r[1], y: -h))
        if r[1] > 0 { path.addQuadCurve(to: CGPoint(x: h, y: -h + r[1]), controlPoint: CGPoint(x: h, y: -h)) }
        path.addLine(to: CGPoint(x: h, y: h - r[2]))
        if r[2] > 0 { path.addQuadCurve(to: CGPoint(x: h - r[2], y: h), controlPoint: CGPoint(x: h, y: h)) }
        path.addLine(to: CGPoint(x: -h + r[3], y: h))
        if r[3] > 0 { path.addQuadCurve(to: CGPoint(x: -h, y: h - r[3]), controlPoint: CGPoint(x: -h, y: h)) }
        path.addLine(to: CGPoint(x: -h, y: -h + r[0]))
        if r[0] > 0 { path.addQuadCurve(to: CGPoint(x: -h + r[0], y: -h), controlPoint: CGPoint(x: -h, y: -h)) }
        path.close()
        path.flatness = 0.008
        return path
    }
}
#endif

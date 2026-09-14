#if os(iOS)
import SceneKit
import UIKit
import simd

/// Small setup-time convex envelopes join a cubie's supporting contours into one closed body.
enum VirtualCubieBodyMesh {
    static func deepFoundation(pitch: Float, position: SIMD3<Int>, size: Int) -> [SIMD3<Float>] {
        let center = SIMD3(Float(position.x), Float(position.y), Float(position.z)) * pitch / 2
        let lower = center - SIMD3<Float>(repeating: pitch / 2)
        let upper = center + SIMD3<Float>(repeating: pitch / 2)
        let radius = pitch * Float(size) / 3
        let epsilon = pitch * 0.00001
        var points: [SIMD3<Float>] = []
        func append(_ point: SIMD3<Float>) {
            guard (0..<3).allSatisfy({ point[$0] >= lower[$0] - epsilon && point[$0] <= upper[$0] + epsilon }) else { return }
            points.append(simd_min(upper, simd_max(lower, point)) - center)
        }
        for x in [lower.x, upper.x] {
            for y in [lower.y, upper.y] {
                for z in [lower.z, upper.z] {
                    let point = SIMD3(x, y, z)
                    if simd_length_squared(point) <= radius * radius { append(point) }
                }
            }
        }
        // Shared cell planes use identical circle samples and exact edge intersections,
        // keeping the rounded deep coverage continuous across independently owned bodies.
        for axis in 0..<3 {
            let u = (axis + 1) % 3, v = (axis + 2) % 3
            for side in [-radius, radius] {
                var point = SIMD3<Float>.zero
                point[axis] = side
                append(point)
            }
            for plane in [lower[axis], upper[axis]] where abs(plane) <= radius {
                let circle = sqrt(max(0, radius * radius - plane * plane))
                for step in 0..<16 {
                    let angle = Float(step) * .pi / 8
                    var point = SIMD3<Float>.zero
                    point[axis] = plane
                    point[u] = circle * cos(angle)
                    point[v] = circle * sin(angle)
                    append(point)
                }
            }
            for other in (axis + 1)..<3 {
                let remaining = 3 - axis - other
                for a in [lower[axis], upper[axis]] {
                    for b in [lower[other], upper[other]] {
                        let squared = radius * radius - a * a - b * b
                        guard squared >= 0 else { continue }
                        for c in [-sqrt(squared), sqrt(squared)] {
                            var point = SIMD3<Float>.zero
                            point[axis] = a; point[other] = b; point[remaining] = c
                            append(point)
                        }
                    }
                }
            }
        }
        return points
    }

    static func sample(path: UIBezierPath) -> [CGPoint] {
        var points: [CGPoint] = []
        var current = CGPoint.zero
        path.cgPath.applyWithBlock { element in
            let item = element.pointee
            switch item.type {
            case .moveToPoint, .addLineToPoint:
                current = item.points[0]
                points.append(current)
            case .addQuadCurveToPoint:
                let start = current, control = item.points[0], end = item.points[1]
                for step in 1...4 {
                    let t = CGFloat(step) / 4, s = 1 - t
                    points.append(CGPoint(x: s * s * start.x + 2 * s * t * control.x + t * t * end.x,
                                          y: s * s * start.y + 2 * s * t * control.y + t * t * end.y))
                }
                current = end
            case .addCurveToPoint:
                let start = current, a = item.points[0], b = item.points[1], end = item.points[2]
                for step in 1...6 {
                    let t = CGFloat(step) / 6, s = 1 - t
                    points.append(CGPoint(x: s * s * s * start.x + 3 * s * s * t * a.x + 3 * s * t * t * b.x + t * t * t * end.x,
                                          y: s * s * s * start.y + 3 * s * s * t * a.y + 3 * s * t * t * b.y + t * t * t * end.y))
                }
                current = end
            case .closeSubpath: break
            @unknown default: break
            }
        }
        return points
    }

    private struct Face {
        var a: Int
        var b: Int
        var c: Int
    }

    private struct Edge: Hashable, Comparable {
        let a: Int
        let b: Int
        init(_ a: Int, _ b: Int) { self.a = min(a, b); self.b = max(a, b) }
        static func < (lhs: Edge, rhs: Edge) -> Bool {
            lhs.a == rhs.a ? lhs.b < rhs.b : lhs.a < rhs.a
        }
    }

    static func geometry(enclosing input: [SIMD3<Float>], tolerance: Float) -> SCNGeometry {
        var points: [SIMD3<Float>] = []
        for point in input where !points.contains(where: { simd_distance_squared($0, point) < tolerance * tolerance }) {
            points.append(point)
        }
        // Every supported cell's rounded foundation has non-coplanar extent.
        let a = 0
        let b = points.indices.max { simd_distance_squared(points[$0], points[a]) < simd_distance_squared(points[$1], points[a]) }!
        let c = points.indices.max {
            simd_length_squared(simd_cross(points[b] - points[a], points[$0] - points[a])) <
                simd_length_squared(simd_cross(points[b] - points[a], points[$1] - points[a]))
        }!
        let normal = simd_normalize(simd_cross(points[b] - points[a], points[c] - points[a]))
        let d = points.indices.max { abs(simd_dot(normal, points[$0] - points[a])) < abs(simd_dot(normal, points[$1] - points[a])) }!
        let interior = (points[a] + points[b] + points[c] + points[d]) / 4
        func oriented(_ a: Int, _ b: Int, _ c: Int) -> Face {
            let n = simd_cross(points[b] - points[a], points[c] - points[a])
            return simd_dot(n, interior - points[a]) > 0 ? Face(a: a, b: c, c: b) : Face(a: a, b: b, c: c)
        }
        var faces = [oriented(a, b, c), oriented(a, d, b), oriented(b, d, c), oriented(c, d, a)]
        let seed: Set<Int> = [a, b, c, d]
        for index in points.indices where !seed.contains(index) {
            var horizon: [Edge: Int] = [:]
            var retained: [Face] = []
            for face in faces {
                let n = simd_cross(points[face.b] - points[face.a], points[face.c] - points[face.a])
                if simd_dot(n, points[index] - points[face.a]) > tolerance * simd_length(n) {
                    for edge in [Edge(face.a, face.b), Edge(face.b, face.c), Edge(face.c, face.a)] {
                        horizon[edge, default: 0] += 1
                    }
                } else {
                    retained.append(face)
                }
            }
            // Only the perimeter of the visible region connects to the new point.
            for edge in horizon.keys.sorted() where horizon[edge] == 1 {
                retained.append(oriented(edge.a, edge.b, index))
            }
            faces = retained
        }
        let used = Set(faces.flatMap { [$0.a, $0.b, $0.c] }).sorted()
        let remap = Dictionary(uniqueKeysWithValues: used.enumerated().map { ($0.element, UInt16($0.offset)) })
        var normals = [SIMD3<Float>](repeating: .zero, count: points.count)
        for face in faces {
            let n = simd_cross(points[face.b] - points[face.a], points[face.c] - points[face.a])
            for index in [face.a, face.b, face.c] { normals[index] += n }
        }
        func vector(_ point: SIMD3<Float>) -> SCNVector3 { SCNVector3(point.x, point.y, point.z) }
        let vertices = used.map { vector(points[$0]) }
        let smoothNormals = used.map { vector(simd_normalize(normals[$0])) }
        let indices = faces.flatMap { [remap[$0.a]!, remap[$0.b]!, remap[$0.c]!] }
        return SCNGeometry(sources: [.init(vertices: vertices), .init(normals: smoothNormals)],
                           elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }
}
#endif

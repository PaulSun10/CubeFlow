import Foundation

/// A centerless 2x2 can choose any proper initial color frame and any rigid
/// native/body reference pose. Neither freedom changes the logical scramble state.
/// Three-by-three comparisons deliberately remain exact.
nonisolated enum CubeStateEquivalence {
    static func matches(_ lhs: String, _ rhs: String, puzzleSize: Int) -> Bool {
        guard puzzleSize == 2 else { return lhs == rhs }
        let source = Array(lhs), target = Array(rhs)
        guard source.count == 24, target.count == 24,
              validColors(source), validColors(target) else { return false }
        if source == target { return true }
        let faces = Array("URFDLB")
        let sourceColorIndices = source.map { faces.firstIndex(of: $0)! }
        for frame in rotations {
            let renamedFaces = (0..<6).map { faces[frame[$0 * 4] / 4] }
            var inFrame = [Character](repeating: "?", count: 24)
            for index in source.indices {
                inFrame[frame[index]] = renamedFaces[sourceColorIndices[index]]
            }
            if rotations.contains(where: { pose in
                pose.indices.allSatisfy { inFrame[$0] == target[pose[$0]] }
            }) {
                return true
            }
        }
        return false
    }

    static func isSolved(_ facelets: String, puzzleSize: Int) -> Bool {
        matches(facelets, CubeSurface.solved(size: puzzleSize), puzzleSize: puzzleSize)
    }

    private static func validColors(_ stickers: [Character]) -> Bool {
        "URFDLB".allSatisfy { face in stickers.filter { $0 == face }.count == 4 }
    }

    private static let rotations: [[Int]] = {
        let surfaces = CubeSurface.all(size: 2)
        let indices = Dictionary(uniqueKeysWithValues: surfaces.enumerated().map { ($0.element, $0.offset) })
        func quarter(_ v: SIMD3<Int>, axis: Int) -> SIMD3<Int> {
            switch axis {
            case 0: return .init(v.x, -v.z, v.y)
            case 1: return .init(v.z, v.y, -v.x)
            default: return .init(-v.y, v.x, v.z)
            }
        }
        let generators = (0..<3).map { axis in
            surfaces.map { surface in
                indices[CubeSurface(
                    position: quarter(surface.position, axis: axis),
                    normal: quarter(surface.normal, axis: axis)
                )]!
            }
        }
        let identity = Array(0..<24)
        var result = [identity]
        var seen: Set<[Int]> = [identity]
        var cursor = 0
        while cursor < result.count {
            let current = result[cursor]
            for generator in generators {
                let next = current.map { generator[$0] }
                if seen.insert(next).inserted { result.append(next) }
            }
            cursor += 1
        }
        precondition(result.count == 24)
        return result
    }()
}

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
        if puzzleSize == 2 { return solvedTwoByTwoStates.contains(facelets) }
        return matches(facelets, CubeSurface.solved(size: puzzleSize), puzzleSize: puzzleSize)
    }

    /// Canonicalizes both allowed rotations without enumerating 576 complete
    /// sticker arrays. Once the URF colors are renamed, their ordered corner
    /// determines the unique body pose.
    static func twoByTwoCheckpointKey(_ facelets: String) -> [UInt8]? {
        let indices = facelets.utf8.compactMap { faceCodes[$0] }
        guard indices.count == 24, facelets.utf8.count == 24 else { return nil }
        var best: [UInt8]?
        for colors in colorFrames {
            guard let pose = inverseRotations.first(where: {
                colors[Int(indices[$0[urf.0]])] == 0 &&
                colors[Int(indices[$0[urf.1]])] == 1 &&
                colors[Int(indices[$0[urf.2]])] == 2
            }) else { continue }
            let normalized = pose.map { colors[Int(indices[$0])] }
            if best.map({ normalized.lexicographicallyPrecedes($0) }) ?? true { best = normalized }
        }
        return best
    }

    private static let faceCodes = Dictionary(uniqueKeysWithValues:
        "URFDLB".utf8.enumerated().map { ($0.element, UInt8($0.offset)) })
    private static let colorFrames = rotations.map { frame in (0..<6).map { UInt8(frame[$0 * 4] / 4) } }
    private static let inverseRotations = rotations.map { frame in
        var inverse = frame
        for (i, j) in frame.enumerated() { inverse[j] = i }
        return inverse
    }
    // Indices of the U, R and F stickers on the same corner in CubeSurface.
    private static let urf = (3, 4, 9)

    // The solved pattern's color-frame and body-pose actions close over the
    // same 24 proper rotations. Keep the full matcher for arbitrary targets.
    private static let solvedTwoByTwoStates: Set<String> = {
        let solved = Array(CubeSurface.solved(size: 2))
        return Set(rotations.map { pose in String(pose.map { solved[$0] }) })
    }()

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

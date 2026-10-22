#if os(iOS)
import Foundation

/// Exact face-turn metric (HTM): each face quarter/half/inverse turn costs one.
/// A 1+2 meet-in-the-middle search exhausts all routes through depth three.
nonisolated enum SmartCubeTargetPath {
    static let moves = ["U", "U'", "U2", "R", "R'", "R2", "F", "F'", "F2",
                        "D", "D'", "D2", "L", "L'", "L2", "B", "B'", "B2"]

    @concurrent static func shortestWithinThree(from source: String, to target: String) async -> [String]? {
        assert(!Thread.isMainThread)
        guard [24, 54].contains(source.count), source.count == target.count,
              plausible(source), plausible(target), !Task.isCancelled else { return nil }
        if source == target { return [] }
        var forwards: [(state: String, move: String)] = []
        for move in moves {
            guard !Task.isCancelled else { return nil }
            guard let state = SmartCubeBluetoothManager.facelets(source, applying: move) else { return nil }
            if state == target { return [move] }
            forwards.append((state, move))
        }
        var backwards = [target: [String]()]
        var firstLayer: [(state: String, path: [String])] = []
        for move in moves {
            guard !Task.isCancelled else { return nil }
            guard let state = SmartCubeBluetoothManager.facelets(target, applying: move) else { return nil }
            let path = [inverse(move)]
            if backwards[state] == nil { backwards[state] = path; firstLayer.append((state, path)) }
        }
        for node in forwards {
            if let tail = backwards[node.state] { return [node.move] + tail }
        }
        for node in firstLayer {
            guard !Task.isCancelled else { return nil }
            for move in moves {
                guard let state = SmartCubeBluetoothManager.facelets(node.state, applying: move) else { return nil }
                if backwards[state] == nil { backwards[state] = [inverse(move)] + node.path }
            }
        }
        for node in forwards {
            if let tail = backwards[node.state] { return [node.move] + tail }
        }
        return nil
    }

    private static func plausible(_ value: String) -> Bool {
        let colors = Array(value), count = value.count / 6
        return colors.allSatisfy { "URFDLB".contains($0) }
            && "URFDLB".allSatisfy { face in colors.filter { $0 == face }.count == count }
    }
    private static func inverse(_ move: String) -> String {
        move.hasSuffix("2") ? move : move.hasSuffix("'") ? String(move.dropLast()) : move + "'"
    }
}
#endif

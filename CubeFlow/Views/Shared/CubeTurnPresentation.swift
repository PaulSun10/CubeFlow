import Foundation

nonisolated enum VirtualCubeAppearance: String, CaseIterable, Identifiable {
    case classic, stickerless, minimal
    var id: String { rawValue }
    var localizedKey: String { "smart_cube.appearance.\(rawValue)" }
}

/// Integer coordinates preserve the existing URFDLB facelet convention for either size.
nonisolated struct CubeSurface: Hashable {
    var position: SIMD3<Int>
    var normal: SIMD3<Int>

    static func all(size: Int) -> [Self] {
        guard size == 2 || size == 3 else { return [] }
        let edge = size - 1
        return (0..<(6 * size * size)).map { index in
            let face = index / (size * size)
            let row = (index % (size * size)) / size
            let column = index % size
            let a = 2 * column - edge
            let b = 2 * row - edge
            switch face {
            case 0: return Self(position: .init(a, edge, b), normal: .init(0, 1, 0))
            case 1: return Self(position: .init(edge, -b, -a), normal: .init(1, 0, 0))
            case 2: return Self(position: .init(a, -b, edge), normal: .init(0, 0, 1))
            case 3: return Self(position: .init(a, -edge, -b), normal: .init(0, -1, 0))
            case 4: return Self(position: .init(-edge, -b, a), normal: .init(-1, 0, 0))
            default: return Self(position: .init(-a, -b, -edge), normal: .init(0, 0, -1))
            }
        }
    }

    static func solved(size: Int) -> String {
        "URFDLB".map { String(repeating: String($0), count: size * size) }.joined()
    }
}

nonisolated struct CubeLayerTurn: Equatable {
    let notation: String
    let axis: Int
    let side: Int
    let quarterTurns: Int

    init?(_ notation: String) {
        guard let face = notation.first,
              ["", "'", "2"].contains(String(notation.dropFirst())) else { return nil }
        switch face {
        case "R": axis = 0; side = 1
        case "L": axis = 0; side = -1
        case "U": axis = 1; side = 1
        case "D": axis = 1; side = -1
        case "F": axis = 2; side = 1
        case "B": axis = 2; side = -1
        default: return nil
        }
        self.notation = notation
        quarterTurns = notation.hasSuffix("2") ? 2 : (notation.hasSuffix("'") ? -1 : 1)
    }

    var angle: Double { Double(-side * quarterTurns) * .pi / 2 }
    func contains(_ position: SIMD3<Int>, size: Int) -> Bool {
        position[axis] == side * (size - 1)
    }

    func applying(to facelets: String, size: Int) -> String? {
        let surfaces = CubeSurface.all(size: size)
        let input = Array(facelets)
        guard !surfaces.isEmpty, input.count == surfaces.count else { return nil }
        let indices = Dictionary(uniqueKeysWithValues: surfaces.enumerated().map { ($0.element, $0.offset) })
        var output = input
        let turns = ((-side * quarterTurns) % 4 + 4) % 4
        func rotated(_ vector: SIMD3<Int>) -> SIMD3<Int> {
            var v = vector
            for _ in 0..<turns {
                switch axis {
                case 0: v = .init(v.x, -v.z, v.y)
                case 1: v = .init(v.z, v.y, -v.x)
                default: v = .init(-v.y, v.x, v.z)
                }
            }
            return v
        }
        for (index, surface) in surfaces.enumerated() where contains(surface.position, size: size) {
            let destination = CubeSurface(position: rotated(surface.position), normal: rotated(surface.normal))
            guard let target = indices[destination] else { return nil }
            output[target] = input[index]
        }
        return String(output)
    }
}

/// No BLE or wall-clock dependency. Replay callers can supply their own monotonic playback clock.
nonisolated struct CubeTurnPresentation {
    struct Policy {
        static let halfTurnMultiplier = 1.3
        static let interruptedRemaining = 0.055
        static let severeBacklog = 6
        static let retainedLiveEdge = 2
        static let maximumVisualLag = 0.35
    }

    struct Pending: Equatable {
        let turn: CubeLayerTurn
        let target: String
        let timestamp: TimeInterval
    }

    struct Animation: Equatable {
        let id: UInt64
        let move: Pending
        var startedAt: TimeInterval
        var duration: TimeInterval
        var startProgress: Double = 0

        func progress(at time: TimeInterval) -> Double {
            let t = min(1, max(0, (time - startedAt) / max(duration, 0.001)))
            return startProgress + (1 - startProgress) * t
        }
    }

    let size: Int
    private(set) var canonical: String
    private(set) var settled: String
    private(set) var current: Animation?
    private(set) var pending: [Pending] = []
    private(set) var generation: UInt64 = 0
    private(set) var isTrusted = true
    private var isCatchingUp = false
    var tps: Int = 10

    init(size: Int = 3, facelets: String) {
        self.size = size
        canonical = facelets
        settled = facelets
    }

    mutating func resync(_ facelets: String?, trusted: Bool) {
        generation &+= 1
        current = nil
        isCatchingUp = false
        pending.removeAll(keepingCapacity: true)
        isTrusted = trusted
        if let facelets, facelets.count == 6 * size * size {
            canonical = facelets
            settled = facelets
        } else {
            settled = canonical
        }
    }

    mutating func enqueue(_ notation: String, target: String, timestamp: TimeInterval, now: TimeInterval) {
        guard isTrusted, let turn = CubeLayerTurn(notation),
              turn.applying(to: canonical, size: size) == target else {
            resync(target, trusted: true)
            return
        }
        canonical = target
        guard tps > 0 else { resync(target, trusted: true); return }
        if current != nil { isCatchingUp = true }
        pending.append(Pending(turn: turn, target: target, timestamp: timestamp))
        if pending.count >= Policy.severeBacklog ||
            (pending.count > Policy.retainedLiveEdge && now - pending[0].timestamp > Policy.maximumVisualLag) {
            if let current { settled = current.move.target }
            current = nil
            while pending.count > Policy.retainedLiveEdge { settled = pending.removeFirst().target }
        } else if var animation = current {
            let progress = animation.progress(at: now)
            let remaining = animation.duration * (1 - progress) / max(0.001, 1 - animation.startProgress)
            animation.startedAt = now
            animation.startProgress = progress
            animation.duration = min(remaining, Policy.interruptedRemaining / Double(max(1, pending.count)))
            current = animation
        }
        advance(at: now)
    }

    mutating func advance(at now: TimeInterval) {
        if tps == 0 {
            if current != nil || !pending.isEmpty || settled != canonical {
                resync(canonical, trusted: isTrusted)
            }
            return
        }
        if let animation = current, animation.progress(at: now) >= 1 {
            settled = animation.move.target
            current = nil
        }
        if current == nil, !pending.isEmpty {
            let backlog = pending.count
            let move = pending.removeFirst()
            generation &+= 1
            let nominalDuration = (move.turn.quarterTurns == 2 ? Policy.halfTurnMultiplier : 1)
                / Double(min(20, max(1, tps))) / Double(max(1, backlog))
            current = Animation(
                id: generation, move: move, startedAt: now,
                duration: isCatchingUp ? min(nominalDuration, Policy.interruptedRemaining) : nominalDuration
            )
        }
        if current == nil && pending.isEmpty { isCatchingUp = false }
    }
}

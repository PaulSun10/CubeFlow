import Foundation

/// WeiPo's A3 frame is a valid 2x2 frame, but is not a fixed physical face frame.
/// It certifies native-frame turns only against an authoritative A3 endpoint.
nonisolated struct WeiPo2NativeVisualAdapter {
    struct ValidatedTurn: Equatable {
        let code: UInt8
        let turnCounter: UInt8
        let notation: String
        let facelets: String
    }

    private static let nativeNotation = ["F", "F'", "U", "U'", "R", "R'"]
    private enum Layout: CaseIterable, Hashable {
        case first, second

        // Fitted from the captured S0/S1/S2/S4 and A-prelude A3 transitions.
        // Native groups are four stickers each; destination indices use CubeSurface.all(size: 2).
        var destination: [Int] {
            switch self {
            case .first:
                return [8, 9, 10, 11, 20, 21, 22, 23, 0, 1, 2, 3,
                        12, 13, 14, 15, 16, 17, 18, 19, 4, 5, 6, 7]
            case .second:
                return [21, 20, 23, 22, 9, 8, 11, 10, 14, 15, 12, 13,
                        2, 3, 0, 1, 5, 4, 7, 6, 17, 16, 19, 18]
            }
        }

        var faceForValue: [Character] {
            Array(self == .first ? "FBUDLR" : "BFDURL")
        }

        func render(_ values: [UInt8]) -> String? {
            guard values.count == 24,
                  values.allSatisfy({ $0 < 6 }),
                  (0..<6).allSatisfy({ value in values.filter { $0 == value }.count == 4 }) else {
                return nil
            }
            let faces = faceForValue
            let positions = destination
            var result = [Character](repeating: "?", count: 24)
            for index in values.indices {
                result[positions[index]] = faces[Int(values[index])]
            }
            let stickers = CubeSurface.all(size: 2)
            var corners: [SIMD3<Int>: [Character]] = [:]
            for (index, sticker) in stickers.enumerated() {
                corners[sticker.position, default: []].append(result[index])
            }
            let triples = corners.values.map { Set($0) }
            guard triples.count == 8, Set(triples).count == 8,
                  triples.allSatisfy({ colors in
                      colors.count == 3 &&
                      colors.intersection(["U", "D"]).count == 1 &&
                      colors.intersection(["R", "L"]).count == 1 &&
                      colors.intersection(["F", "B"]).count == 1
                  }) else { return nil }
            return String(result)
        }
    }

    private var possibleLayouts = Set(Layout.allCases)
    private var lastSnapshot: WeiPo2NativeState?
    private var pendingTurns: [WeiPo2NativeTurn] = []
    private(set) var renderableFacelets: String?
    private(set) var validatedTurns: [ValidatedTurn] = []
    private(set) var acceptedNewSnapshot = false
    private(set) var rejectedNewSnapshot = false
    var possibleLayoutCount: Int { possibleLayouts.count }

    mutating func reset() { self = Self() }

    mutating func note(_ turn: WeiPo2NativeTurn) {
        pendingTurns.append(turn)
        if pendingTurns.count > 32 { pendingTurns.removeFirst(pendingTurns.count - 32) }
    }

    mutating func accept(_ state: WeiPo2NativeState) -> String? {
        validatedTurns = []
        acceptedNewSnapshot = false
        rejectedNewSnapshot = false
        let previousVisual = renderableFacelets
        let distance = lastSnapshot.map { Int((state.turnCounter &- $0.turnCounter)) } ?? 0
        if let previous = lastSnapshot {
            if distance > 127 { return renderableFacelets } // An older A3 response arrived late.
            if distance == 0, previous.stickerValues == state.stickerValues {
                return renderableFacelets
            }
        }

        var rendered = Dictionary(uniqueKeysWithValues: possibleLayouts.compactMap { layout -> (Layout, String)? in
            guard let facelets = layout.render(state.stickerValues) else { return nil }
            return (layout, facelets)
        })
        var validatedChain: [WeiPo2NativeTurn] = []
        if let previous = lastSnapshot, distance > 0 {
            let covered = pendingTurns.filter {
                let offset = Int($0.turnCounter &- previous.turnCounter)
                return offset > 0 && offset <= distance
            }
            let complete = covered.count == distance && covered.enumerated().allSatisfy {
                index, turn in turn.missedTurnCount == 0 &&
                    turn.turnCounter == previous.turnCounter &+ UInt8(index + 1)
            }
            if complete {
                rendered = rendered.filter { layout, target in
                    guard var projected = layout.render(previous.stickerValues) else { return false }
                    for turn in covered {
                        // These are native preferred-side axes, never physical move names.
                        guard Int(turn.code) < Self.nativeNotation.count,
                              let next = CubeLayerTurn(Self.nativeNotation[Int(turn.code)])?.applying(to: projected, size: 2) else {
                            return false
                        }
                        projected = next
                    }
                    return projected == target
                }
                validatedChain = covered
            }
            pendingTurns.removeAll {
                let offset = Int($0.turnCounter &- previous.turnCounter)
                return offset > 0 && offset <= distance
            }
        } else if lastSnapshot == nil {
            pendingTurns.removeAll()
        }

        guard !rendered.isEmpty else {
            reset()
            rejectedNewSnapshot = true
            return nil
        }
        lastSnapshot = state
        acceptedNewSnapshot = true
        possibleLayouts = Set(rendered.keys)
        let distinct = Set(rendered.values)
        renderableFacelets = distinct.count == 1 ? distinct.first : nil
        if var projected = previousVisual, let endpoint = renderableFacelets {
            var steps: [ValidatedTurn] = []
            for turn in validatedChain {
                guard Int(turn.code) < Self.nativeNotation.count,
                      let next = CubeLayerTurn(Self.nativeNotation[Int(turn.code)])?.applying(to: projected, size: 2) else {
                    steps = []
                    break
                }
                projected = next
                steps.append(ValidatedTurn(
                    code: turn.code,
                    turnCounter: turn.turnCounter,
                    notation: Self.nativeNotation[Int(turn.code)],
                    facelets: next
                ))
            }
            if projected == endpoint { validatedTurns = steps }
        }
        return renderableFacelets
    }
}

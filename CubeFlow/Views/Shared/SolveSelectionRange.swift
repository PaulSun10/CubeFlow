import Foundation
import CoreGraphics

/// Range order is the current filtered/sorted list, never UUID or solve number order.
nonisolated enum SolveSelectionRange {
    static func visuallyVisibleIDs(rowFrames: [UUID: CGRect], viewport: CGRect,
                                   control: CGRect = .zero, anchorIsAbove: Bool = true) -> Set<UUID> {
        let hasControl = !control.isEmpty && control.intersects(viewport)
        return Set(rowFrames.compactMap { id, frame in
            guard !frame.isEmpty, frame.intersects(viewport) else { return nil }
            // Include the row crossing the control's near edge, not only fully contained rows.
            if hasControl && (anchorIsAbove ? frame.minY >= control.minY : frame.maxY <= control.maxY) { return nil }
            return id
        })
    }

    static func ids(from anchor: UUID, through boundary: UUID, orderedIDs: [UUID]) -> Set<UUID> {
        guard let a = orderedIDs.firstIndex(of: anchor), let b = orderedIDs.firstIndex(of: boundary) else { return [] }
        return Set(orderedIDs[min(a, b)...max(a, b)])
    }

    struct Boundary: Equatable {
        let id: UUID
        let anchorIsAbove: Bool
    }

    static func boundary(anchor: UUID?, visibleIDs: Set<UUID>, orderedIDs: some Sequence<UUID>) -> Boundary? {
        guard let anchor, !visibleIDs.isEmpty, !visibleIDs.contains(anchor) else { return nil }
        var anchorIndex: Int?
        var first: (Int, UUID)?
        var last: (Int, UUID)?
        for (index, id) in orderedIDs.enumerated() {
            if id == anchor, anchorIndex == nil { anchorIndex = index }
            if visibleIDs.contains(id) {
                if first == nil { first = (index, id) }
                last = (index, id)
            }
        }
        guard let a = anchorIndex, let first, let last else { return nil }
        if a < first.0 { return Boundary(id: last.1, anchorIsAbove: true) }
        if a > last.0 { return Boundary(id: first.1, anchorIsAbove: false) }
        return nil
    }

    /// Display numbers descend in the unfiltered newest-first list.
    static func boundary(anchor: UUID?, visibleIDs: Set<UUID>, newestFirstPositions: [UUID: Int]) -> Boundary? {
        guard let anchor, !visibleIDs.contains(anchor), let a = newestFirstPositions[anchor] else { return nil }
        var first: (Int, UUID)?
        var last: (Int, UUID)?
        for id in visibleIDs {
            guard let position = newestFirstPositions[id] else { continue }
            if first.map({ position > $0.0 }) ?? true { first = (position, id) }
            if last.map({ position < $0.0 }) ?? true { last = (position, id) }
        }
        guard let first, let last else { return nil }
        if a > first.0 { return Boundary(id: last.1, anchorIsAbove: true) }
        if a < last.0 { return Boundary(id: first.1, anchorIsAbove: false) }
        return nil
    }

    static func anchorAfterDirectToggle(id: UUID, selected: Bool, previous: UUID?) -> UUID? {
        if selected { return id }
        return previous == id ? nil : previous
    }
}

nonisolated func solveMoveLabel(count: Int, languageCode: String) -> String {
    guard count > 0 else { return appLocalizedString("data.move.action", languageCode: languageCode) }
    let format = appLocalizedString("data.move.count", languageCode: languageCode)
    return String(format: format, locale: Locale(identifier: languageCode), count)
}

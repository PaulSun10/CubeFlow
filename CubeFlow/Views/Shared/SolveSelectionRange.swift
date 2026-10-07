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

    static func boundary(anchor: UUID?, visibleIDs: Set<UUID>, orderedIDs: [UUID]) -> Boundary? {
        guard let anchor, !visibleIDs.contains(anchor), let a = orderedIDs.firstIndex(of: anchor) else { return nil }
        let indices = orderedIDs.indices.filter { visibleIDs.contains(orderedIDs[$0]) }
        guard let first = indices.first, let last = indices.last else { return nil }
        if a < first { return Boundary(id: orderedIDs[last], anchorIsAbove: true) }
        if a > last { return Boundary(id: orderedIDs[first], anchorIsAbove: false) }
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

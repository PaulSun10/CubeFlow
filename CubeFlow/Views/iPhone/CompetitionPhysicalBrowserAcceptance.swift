#if DEBUG
import SwiftUI
import UIKit
import QuartzCore

/// Override only data seams; retain the normal active Browser and production cells.
@MainActor enum CompetitionPhysicalBrowserAcceptance {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--competition-physical-browser") }
    static var interior: Bool { ProcessInfo.processInfo.arguments.contains("--competition-physical-interior") }
    static var dragCount = 0
    private static var configured = false
    private static var previews: [String: [CompetitionTopCuberPreview]] = [:]
    static var invalidations: [[String: Any]] = []
    static func configure() {
        guard !configured else { return }; configured = true
        let environment = ProcessInfo.processInfo.environment
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let summaries = environment["CUBEFLOW_PHYSICAL_SUMMARIES"].flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
            .flatMap { try? decoder.decode([CompetitionSummary].self, from: $0) } ?? []
        for (id, key) in [("MakatiSpeedcubingOpenIX2026", "CUBEFLOW_MAKATI_WCIF"), ("TokaiAutumn2026", "CUBEFLOW_TOKAI_WCIF"),
                          ("BeijingAutumnRivalry2026", "CUBEFLOW_BEIJING_WCIF")] {
            if let path = environment[key], let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                previews[id] = CompetitionService.decodeCompetitionTopCuberPreviews(bytes,
                    eventIDs: summaries.first { $0.id == id }?.eventIDs ?? []) ?? []
            }
        }
        CompetitionBrowserPublicationAcceptance.cache = { query in
            let rows = CompetitionService.filterCompetitions(summaries, for: query)
            return CompetitionCacheSnapshot(competitions: rows, totalCount: rows.count, lastUpdated: Date())
        }
        CompetitionBrowserPublicationAcceptance.page = { query, _ in
            let rows = CompetitionService.filterCompetitions(summaries, for: query)
            return CompetitionPageResult(competitions: rows, receivedCount: rows.count, nextPage: nil, totalCount: rows.count)
        }
    }
    static func cached(_ id: String) async -> [CompetitionTopCuberPreview]? {
        guard let values = previews[id] else { return [] }
        return ProcessInfo.processInfo.arguments.contains("--competition-physical-warm") ? values : nil
    }
    static func fetched(_ competition: CompetitionSummary) async -> [CompetitionTopCuberPreview]? {
        while (interior ? dragCount < 2 : !CompetitionLongListAcceptance.firstDragStarted), !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        try? await Task.sleep(nanoseconds: 180_000_000)
        guard !Task.isCancelled else { return nil }
        CompetitionLongListAcceptance.responseReleasedAt = CACurrentMediaTime()
        return previews[competition.id] ?? []
    }
    static func record(_ preferred: UICollectionViewLayoutAttributes, original: UICollectionViewLayoutAttributes,
                       context: UICollectionViewLayoutInvalidationContext, collection: UICollectionView?) {
        guard enabled, invalidations.count < 240 else { return }
        invalidations.append(["time": CACurrentMediaTime(), "row": preferred.indexPath.item,
            "oldHeight": original.size.height, "newHeight": preferred.size.height,
            "adjustmentY": context.contentOffsetAdjustment.y, "offsetY": collection?.contentOffset.y ?? 0,
            "contentHeight": collection?.contentSize.height ?? 0,
            "dragging": collection?.isDragging ?? false, "decelerating": collection?.isDecelerating ?? false])
        flush()
    }
    static func recordFit(_ preferred: UICollectionViewLayoutAttributes, original: UICollectionViewLayoutAttributes,
                          collection: UICollectionView) {
        guard enabled, invalidations.count < 1000 else { return }
        invalidations.append(["kind": "fit", "time": CACurrentMediaTime(), "row": preferred.indexPath.item,
            "oldHeight": original.size.height, "newHeight": preferred.size.height,
            "offsetY": collection.contentOffset.y, "contentHeight": collection.contentSize.height,
            "dragging": collection.isDragging, "decelerating": collection.isDecelerating,
            "releasedAt": CompetitionLongListAcceptance.responseReleasedAt ?? 0])
    }
    static func flush() {
        guard enabled else { return }
        if let data = try? JSONSerialization.data(withJSONObject: invalidations) {
            try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("competition-physical-invalidations.json"), options: .atomic)
        }
    }
    static func recordUpdate(_ collection: UICollectionView, beforeOffset: CGFloat, beforeInset: CGFloat) {
        guard enabled, invalidations.count < 1000 else { return }
        invalidations.append(["kind": "native-update", "time": CACurrentMediaTime(),
            "beforeOffset": beforeOffset, "afterOffset": collection.contentOffset.y,
            "beforeInset": beforeInset, "afterInset": collection.adjustedContentInset.top,
            "dragging": collection.isDragging, "decelerating": collection.isDecelerating])
    }
}
#endif

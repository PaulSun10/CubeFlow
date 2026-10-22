#if DEBUG
import UIKit
import QuartzCore
import Combine

@MainActor final class CompetitionScrollCaptureStore: ObservableObject {
    static let shared = CompetitionScrollCaptureStore()
    @Published private(set) var captures: [[String: Any]] = []
    private(set) var generation = 0
    func archive(_ capture: [String: Any], generation expected: Int? = nil) {
        guard expected == nil || expected == generation else { return }
        captures = Array((captures + [capture]).suffix(4))
    }
    func clear() { generation += 1; captures = [] }
}

@MainActor enum CompetitionScrollOwnerDiagnostics {
    static let enabledKey = "competitionScrollOwnerDiagnostics"
    static var enabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--competition-scroll-owner-timing")
            || (CompetitionDebugStore.shared.enabled && UserDefaults.standard.bool(forKey: enabledKey))
    }
    static var events: [[String: Any]] = []
    static var states: [String: String] = [:]
    static var captures: [[String: Any]] { CompetitionScrollCaptureStore.shared.captures }
    private(set) static var droppedEvents = 0
    static func event(_ name: String, details: [String: Any] = [:]) {
        guard enabled else { return }
        var value = details
        value["event"] = name; value["time"] = CACurrentMediaTime()
        events.append(value)
        if events.count > 1024 {
            let removed = events.count - 1024
            droppedEvents += removed; events.removeFirst(removed)
        }
    }
    static func archive(_ capture: [String: Any], generation: Int? = nil) {
        CompetitionScrollCaptureStore.shared.archive(capture, generation: generation)
    }
    static func clear() { CompetitionScrollCaptureStore.shared.clear(); events = []; states = [:]; droppedEvents = 0 }
    static func export(to url: URL) throws {
        // Explicit export only, never file I/O from a scrolling/layout callback.
        let envelope: [String: Any] = ["schema": 2, "clock": "CACurrentMediaTime-seconds", "systemVersion": UIDevice.current.systemVersion,
            "os": ProcessInfo.processInfo.operatingSystemVersionString, "captures": captures]
        try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]).write(to: url, options: .atomic)
    }
    static func loading(_ id: String, state: CompetitionTopCuberLoadState, phase: String) {
        guard enabled else { return }
        let label: String
        switch state {
        case .idle: label = "idle"
        case .loading: label = "loading"
        case .empty: label = "empty"
        case .failed: label = "failed"
        case .loaded(let values): label = "loaded:\(values.count)"
        }
        if phase == "visible" { states[id] = label }
        event("top-cubers", details: ["id": id, "phase": phase, "state": label])
    }
    static func rect(_ frame: CGRect) -> [Double] {
        [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)]
    }
    static func presented(_ view: UIView, in window: UIWindow) -> [Double] {
        let point = CompetitionDisclosureViewportProbe.shared.projectedOrigin(view.layer, in: window.layer)
            ?? view.convert(view.bounds.origin, to: window)
        let bounds = view.layer.presentation()?.bounds ?? view.bounds
        return [Double(point.x), Double(point.y), Double(bounds.width), Double(bounds.height)]
    }
    static func viewState(_ view: UIView, in window: UIWindow, path: String) -> [String: Any] {
        let layer = view.layer
        let presentation = layer.presentation()
        let point = CompetitionDisclosureViewportProbe.shared.projectedOrigin(layer, in: window.layer)
        return ["path": path, "type": String(describing: type(of: view)),
            "identity": String(describing: ObjectIdentifier(view)),
            "model": rect(view.convert(view.bounds, to: window)), "presented": presented(view, in: window),
            "projectionSupported": point != nil, "hasPresentation": presentation != nil,
            "bounds": rect(view.bounds), "presentedBounds": rect(presentation?.bounds ?? view.bounds),
            "transform": [Double(view.transform.a), Double(view.transform.b), Double(view.transform.c),
                Double(view.transform.d), Double(view.transform.tx), Double(view.transform.ty)],
            "animationKeys": layer.animationKeys() ?? []]
    }
    private static func hostedHierarchy(_ root: UIView, in window: UIWindow) -> [[String: Any]] {
        var result: [[String: Any]] = []
        func visit(_ view: UIView, path: String, depth: Int) {
            guard depth <= 4, result.count < 20 else { return }
            result.append(viewState(view, in: window, path: path))
            for (index, child) in view.subviews.enumerated() { visit(child, path: path + ".\(index)", depth: depth + 1) }
        }
        visit(root, path: "contentView", depth: 0)
        return result
    }
    static func cellEvent(_ name: String, cell: UICollectionViewCell, details: [String: Any] = [:]) {
        guard enabled else { return }
        var fields = details
        fields["cellIdentity"] = String(describing: ObjectIdentifier(cell))
        fields["cellFrame"] = rect(cell.frame)
        event(name, details: fields)
    }
    static func sample(_ scroll: UIScrollView) -> [String: Any]? {
        guard enabled, let collection = scroll as? UICollectionView, let window = collection.window else { return nil }
        let data = collection.dataSource as? UICollectionViewDiffableDataSource<Int, String>
        let cells: [[String: Any]] = collection.indexPathsForVisibleItems.sorted { $0.item < $1.item }.compactMap { index in
            guard let cell = collection.cellForItem(at: index) else { return nil }
            let id = data?.itemIdentifier(for: index) ?? String(index.item)
            let logicalID = id.split(separator: ":").dropFirst().first.map(String.init) ?? id
            return ["id": id, "row": index.item,
                "cellIdentity": String(describing: ObjectIdentifier(cell)),
                "cellModel": rect(cell.convert(cell.bounds, to: window)),
                "cellPresented": presented(cell, in: window),
                "hostModel": rect(cell.contentView.convert(cell.contentView.bounds, to: window)),
                "hostPresented": presented(cell.contentView, in: window),
                "hostedHierarchy": hostedHierarchy(cell.contentView, in: window),
                "elements": CompetitionDisclosureViewportProbe.shared.ownerFrames(identity: logicalID, cell: cell, window: window),
                "topCubers": states[logicalID] ?? "unobserved"]
        }
        let pan = scroll.panGestureRecognizer
        return ["time": CACurrentMediaTime(), "offset": [Double(scroll.contentOffset.x), Double(scroll.contentOffset.y)],
            "minimumOffset": Double(-scroll.adjustedContentInset.top),
            "maximumOffset": Double(max(-scroll.adjustedContentInset.top,
                scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)),
            "scrollPresentedBoundsY": Double(scroll.layer.presentation()?.bounds.minY ?? scroll.bounds.minY),
            "contentSize": [Double(scroll.contentSize.width), Double(scroll.contentSize.height)],
            "insets": [Double(scroll.adjustedContentInset.top), Double(scroll.adjustedContentInset.bottom),
                Double(scroll.contentInset.top), Double(scroll.contentInset.bottom)],
            "viewport": rect(scroll.convert(scroll.bounds, to: window)),
            "scrollSurface": viewState(scroll, in: window, path: "scroll"),
            "decelerationRate": Double(scroll.decelerationRate.rawValue),
            "tracking": scroll.isTracking, "bounces": scroll.bounces,
            "dragging": scroll.isDragging, "decelerating": scroll.isDecelerating,
            "panState": pan.state.rawValue, "panY": Double(pan.translation(in: scroll).y),
            "panVelocityY": Double(pan.velocity(in: scroll).y), "cells": cells]
    }
}
#endif

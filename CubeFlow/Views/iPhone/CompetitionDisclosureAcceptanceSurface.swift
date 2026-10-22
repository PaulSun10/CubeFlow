import SwiftUI
#if DEBUG
import Combine

@MainActor final class CompetitionDisclosureAcceptanceState: ObservableObject {
    @Published var expanded = false
    @Published var topState: CompetitionTopCuberLoadState = .idle
    @Published var visibility: CompetitionTopCubersVisibility?
    var revealHeights: [String: CGFloat] = [:]
    var reduceMotionForAcceptance: Bool? = nil
}

struct CompetitionProductionTopAcceptanceInput {
    let competition: CompetitionSummary
    let values: [CompetitionTopCuberPreview]
}

/// Actual list coordinator, hosting cell, card action, materials and native scroll registration.
struct CompetitionDisclosureAcceptanceSurface: View {
    @ObservedObject var state = CompetitionDisclosureAcceptanceState()
    var controlled = false
    var boundary = ProcessInfo.processInfo.arguments.contains("--competition-disclosure-boundary")
    var edge = ProcessInfo.processInfo.arguments.contains("--competition-disclosure-edge")
    var glass = ProcessInfo.processInfo.arguments.contains("--competition-disclosure-glass")
    var productionTop: CompetitionProductionTopAcceptanceInput? = nil
    var body: some View {
        competitionDisclosureAcceptanceList(state: state, controlled: controlled, boundary: boundary, edge: edge, glass: glass,
            productionTop: productionTop)
            .onPreferenceChange(CompetitionTopCubersRevealKey.self) { state.revealHeights = $0 }
    }
}

struct CompetitionDisclosureAcceptanceRow: View {
    let index: Int
    @ObservedObject var state: CompetitionDisclosureAcceptanceState
    let controlled: Bool
    let boundary: Bool
    let edge: Bool
    let glass: Bool
    var productionTop: CompetitionProductionTopAcceptanceInput? = nil
    private var values: [CompetitionTopCuberPreview] {
        (0..<(boundary ? 72 : 24)).map { CompetitionTopCuberPreview(id: String($0), name: "Cuber \($0)", badges: []) }
    }
    @ViewBuilder var body: some View {
        switch index {
        case 0:
            Text("Viewport marker").frame(maxWidth: .infinity).frame(height: edge ? 300 : 160)
                .accessibilityIdentifier("competition-viewport-marker")
        case 1:
            competitionDisclosureAcceptanceCard(glass: glass) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Competition card").font(.headline).competitionDisclosureTitleProbe("fixture")
                        if let productionTop {
                            CompetitionLoadedTopCubers(competition: productionTop.competition, language: "en", initial: .idle,
                                onState: { state.topState = $0 }, cache: { _ in nil }, fetch: { _, _ in productionTop.values }) { previews in
                                Text("Top Cubers").font(.subheadline)
                                CompetitionExpandableTopCubers(previews: previews, language: "en",
                                    expansion: controlled ? $state.expanded : nil,
                                    traceIdentity: "fixture",
                                    onDisclosureTap: { CompetitionDisclosureViewportProbe.shared.begin() },
                                    reduceMotionForAcceptance: state.reduceMotionForAcceptance) { item in
                                    Text(item.name).font(.system(size: 13)).padding(8)
                                }.onPreferenceChange(CompetitionTopCubersVisibilityKey.self) { state.visibility = $0 }
                            } placeholder: { ProgressView() }
                        } else {
                        Text("Top Cubers").font(.subheadline)
                        CompetitionExpandableTopCubers(previews: values, language: "en",
                            expansion: controlled ? $state.expanded : nil,
                            traceIdentity: "fixture",
                            onDisclosureTap: { CompetitionDisclosureViewportProbe.shared.begin() },
                            reduceMotionForAcceptance: state.reduceMotionForAcceptance) { item in
                            Text(item.name).font(.system(size: 13)).padding(8)
                        }
                        }
                    }.padding(16)
            }
        default:
            Color.clear.frame(height: boundary && !ProcessInfo.processInfo.arguments.contains("--competition-disclosure-long-tail") ? 20 : 1800)
        }
    }
}

/// DEBUG-only, read-only animation sampling; never adjusts scroll state or focus.
@MainActor final class CompetitionDisclosureViewportProbe: NSObject {
    static let shared = CompetitionDisclosureViewportProbe()
    private weak var collection: UICollectionView?
    private var observation: NSKeyValueObservation?
    private var link: CADisplayLink?
    private var finishTask: Task<Void, Never>?
    private var start: CGFloat = 0
    private var samples: [[Double]] = []
    private var cellOrigin: CGFloat?
    private var cellOrigins: [Double] = []
    private var viewportOrigins: [Double] = []
    private var presentationSamples = 0
    private final class WeakTitle { weak var view: UIView?; init(_ view: UIView) { self.view = view } }
    private var titles: [String: WeakTitle] = [:]
    private weak var trackedTitle: UIView?
    private weak var trackedCell: UICollectionViewCell?
    private var layoutSamples: [[Double]] = []
    private var fitSamples: [[Double]] = []
    private var lastFrameTime: CFTimeInterval?
    private var maximumFrameGap = 0.0
    private var titleAncestors: [[String: Any]] = []
    private var projectedTitles: [[Double]] = []
    private var elementIdentity = ""
    private var initialElementIDs: Set<String> = []
    private var elementSamples: [String: [[Double]]] = [:]
    private var geometryObservations: [NSKeyValueObservation] = []
    private var geometryWrites: [[String: Any]] = []
    var capturesGeometryWrites = false
    private func observeGeometry(_ title: UIView, through cell: UIView) {
        geometryObservations = []; geometryWrites = []
        var current: UIView? = title
        while let view = current {
            let layer = view.layer
            let identity = String(describing: type(of: view))
            func record(_ property: String) {
                guard self.geometryWrites.count < 100 else { return }
                self.geometryWrites.append(["time": CACurrentMediaTime(), "view": identity,
                    "property": property, "position": String(describing: layer.position),
                    "bounds": String(describing: layer.bounds),
                    "sublayerTransform": String(describing: layer.sublayerTransform),
                    "stack": Thread.callStackSymbols])
            }
            geometryObservations.append(layer.observe(\.position) { _, _ in
                MainActor.assumeIsolated { record("position") }
            })
            geometryObservations.append(layer.observe(\.bounds) { _, _ in
                MainActor.assumeIsolated { record("bounds") }
            })
            geometryObservations.append(layer.observe(\.sublayerTransform) { _, _ in
                MainActor.assumeIsolated { record("sublayerTransform") }
            })
            if view === cell { break }
            current = view.superview
        }
    }
    func projectedOrigin(_ layer: CALayer, in ancestor: CALayer) -> CGPoint? {
        var model = layer
        let initial = model.presentation() ?? model
        var point = initial.bounds.origin
        while model !== ancestor {
            let state = model.presentation() ?? model
            guard CATransform3DIsAffine(state.transform), let parent = model.superlayer else { return nil }
            let anchor = CGPoint(x: state.bounds.minX + state.bounds.width * state.anchorPoint.x,
                y: state.bounds.minY + state.bounds.height * state.anchorPoint.y)
            point = CGPoint(x: point.x - anchor.x, y: point.y - anchor.y)
                .applying(CATransform3DGetAffineTransform(state.transform))
            point.x += state.position.x; point.y += state.position.y
            let parentState = parent.presentation() ?? parent
            guard CATransform3DIsAffine(parentState.sublayerTransform) else { return nil }
            let pivot = CGPoint(x: parentState.bounds.minX + parentState.bounds.width * parentState.anchorPoint.x,
                y: parentState.bounds.minY + parentState.bounds.height * parentState.anchorPoint.y)
            point = CGPoint(x: point.x - pivot.x, y: point.y - pivot.y)
                .applying(CATransform3DGetAffineTransform(parentState.sublayerTransform))
            point.x += pivot.x; point.y += pivot.y
            model = parent
        }
        return point
    }
    func registerTitle(_ view: UIView, identity: String) { titles[identity] = WeakTitle(view) }
    func ownerFrames(identity: String, cell: UIView, window: UIWindow) -> [[String: Any]] {
        titles.keys.sorted().filter { $0 == identity || $0.hasPrefix(identity + "|") }.compactMap { key in
            guard let view = titles[key]?.view, view.window === window, view.isDescendant(of: cell) else { return nil }
            var ancestors: [[String: Any]] = []
            var parent = view.superview
            while let current = parent, current !== cell {
                let name = String(describing: type(of: current))
                if name.contains("Glass") {
                    ancestors.append(["type": name,
                        "model": CompetitionScrollOwnerDiagnostics.rect(current.convert(current.bounds, to: window)),
                        "presented": CompetitionScrollOwnerDiagnostics.presented(current, in: window)])
                }
                parent = current.superview
            }
            return ["id": key, "model": CompetitionScrollOwnerDiagnostics.rect(view.convert(view.bounds, to: window)),
                "presented": CompetitionScrollOwnerDiagnostics.presented(view, in: window),
                "cellRelativeY": Double(view.convert(view.bounds.origin, to: cell).y),
                "glassAncestors": ancestors]
        }
    }
    func trackedCellOrigin(in window: UIWindow) -> CGFloat? {
        guard let trackedTitle, let trackedCell, trackedTitle.window === window,
              trackedTitle.isDescendant(of: trackedCell) else { return nil }
        return projectedOrigin(trackedCell.layer, in: window.layer)?.y
    }
    func removeTitle(_ view: UIView, identity: String) {
        if titles[identity]?.view === view { titles[identity] = nil }
    }
    func recordFit(_ cell: UICollectionViewCell, height: CGFloat, milliseconds: Double) {
        guard link != nil, fitSamples.count < 240 else { return }
        fitSamples.append([Double(height), milliseconds, cell === trackedCell ? 1 : 0])
    }
    private(set) var queryScrolls: [[String: Any]] = []
    func attach(_ collection: UICollectionView) {
        finishTask?.cancel(); link?.invalidate(); observation = nil
        geometryObservations = []; geometryWrites = []
        self.collection = collection
        queryScrolls = []
        if !CompetitionLongListAcceptance.traceEnabled { collection.accessibilityIdentifier = "competition-disclosure-list" }
    }
    func recordQueryScroll(from: String, to: String, before: CGFloat, after: CGFloat) {
        let value: [String: Any] = ["from": from, "to": to, "before": Double(before), "after": Double(after)]
        queryScrolls.append(value)
        print("[DisclosureQueryScroll] \(value)")
    }
    func begin(identity: String = "fixture") {
        guard let collection else { return }
        finishTask?.cancel(); link?.invalidate(); observation = nil
        start = collection.contentOffset.y; samples = []
        elementIdentity = identity
        initialElementIDs = Set(titles.compactMap { key, reference in
            key.hasPrefix(identity + "|") && reference.view?.window != nil ? key : nil
        })
        elementSamples = [:]
        trackedTitle = titles[identity]?.view
        trackedCell = trackedTitle.flatMap { title in
            sequence(first: title.superview, next: { $0?.superview }).compactMap { $0 as? UICollectionViewCell }.first
        } ?? collection.cellForItem(at: IndexPath(item: 1, section: 0))
        layoutSamples = []; fitSamples = []; lastFrameTime = nil; maximumFrameGap = 0
        titleAncestors = []; projectedTitles = []
        geometryObservations = []; geometryWrites = []
        if capturesGeometryWrites, let title = trackedTitle, let cell = trackedCell {
            observeGeometry(title, through: cell)
        }
        cellOrigin = collection.cellForItem(at: IndexPath(item: 1, section: 0))?.frame.minY
        cellOrigins = []; viewportOrigins = []; presentationSamples = 0
        if CompetitionLongListAcceptance.traceEnabled { collection.accessibilityLabel = "Recording" }
        else { collection.accessibilityValue = "Recording" }
        observation = collection.observe(\.contentOffset) { [weak self] _, _ in
            // UIKit changes this property on the main executor; keep KVO sampling synchronous.
            MainActor.assumeIsolated { self?.sample() }
        }
        let link = CADisplayLink(target: self, selector: #selector(sample)); self.link = link
        link.add(to: .main, forMode: .common)
        sample()
        finishTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }
    @objc private func sample() {
        guard let collection else { return }
        let lower = -collection.adjustedContentInset.top
        let upper = max(lower, collection.contentSize.height - collection.bounds.height + collection.adjustedContentInset.bottom)
        if collection.layer.presentation() != nil { presentationSamples += 1 }
        if let window = collection.window {
            for key in initialElementIDs {
                guard let reference = titles[key] else { continue }
                guard let view = reference.view, view.window === window,
                      let point = projectedOrigin(view.layer, in: window.layer) else { continue }
                elementSamples[key, default: []].append([CACurrentMediaTime(), Double(point.x), Double(point.y),
                    Double(view.convert(.zero, to: window).y), Double(view.bounds.height)])
            }
            let layer = collection.layer.presentation() ?? collection.layer
            let windowLayer = window.layer.presentation() ?? window.layer
            viewportOrigins.append(Double(layer.convert(layer.bounds.origin, to: windowLayer).y))
            if let title = trackedTitle, let cell = trackedCell {
                if let titlePoint = projectedOrigin(title.layer, in: window.layer),
                   let cellPoint = projectedOrigin(cell.layer, in: window.layer),
                   let relative = projectedOrigin(title.layer, in: cell.layer) {
                    projectedTitles.append([Double(titlePoint.y), Double(cellPoint.y), Double(relative.y)])
                }
                let titleLayer = title.layer.presentation() ?? title.layer
                let titleY = titleLayer.convert(titleLayer.bounds.origin, to: windowLayer).y
                let cellLayer = cell.layer.presentation() ?? cell.layer
                let cellY = cellLayer.convert(cellLayer.bounds.origin, to: windowLayer).y
                layoutSamples.append([CACurrentMediaTime(), Double(titleY), Double(cellY), Double(titleY - cellY),
                    Double(cell.frame.height), Double(cellLayer.bounds.height), Double(cell.contentView.bounds.height)])
                if titleAncestors.isEmpty, let initial = layoutSamples.first, abs(Double(titleY - cellY) - initial[3]) > 0.2 {
                    var current: UIView? = title
                    while let view = current {
                        let presented = view.layer.presentation() ?? view.layer
                        titleAncestors.append(["type": String(describing: type(of: view)),
                            "modelY": Double(view.layer.convert(view.layer.bounds.origin, to: cell.layer).y),
                            "presentedY": Double(presented.convert(presented.bounds.origin, to: cellLayer).y),
                            "height": Double(view.bounds.height), "presentedHeight": Double(presented.bounds.height),
                            "anchorY": Double(view.layer.anchorPoint.y),
                            "autoresizesSubviews": view.autoresizesSubviews,
                            "autoresizingMask": view.autoresizingMask.rawValue,
                            "contentMode": view.contentMode.rawValue,
                            "contentsGravity": view.layer.contentsGravity.rawValue,
                            "positionY": Double(view.layer.position.y),
                            "presentedPositionY": Double(presented.position.y),
                            "bounds": String(describing: view.bounds),
                            "presentedBounds": String(describing: presented.bounds),
                            "transform": String(describing: view.layer.transform),
                            "presentedTransform": String(describing: presented.transform),
                            "sublayerTransform": String(describing: view.layer.sublayerTransform),
                            "presentedSublayerTransform": String(describing: presented.sublayerTransform),
                            "interactions": view.interactions.map { String(describing: type(of: $0)) },
                            "animations": (view.layer.animationKeys() ?? []).map { key -> [String: Any] in
                                guard let animation = view.layer.animation(forKey: key) else { return ["key": key] }
                                var values: [String: Any] = ["key": key, "type": String(describing: type(of: animation)),
                                    "duration": animation.duration, "beginTime": animation.beginTime]
                                if let basic = animation as? CABasicAnimation {
                                    values["keyPath"] = basic.keyPath ?? ""
                                    values["from"] = String(describing: basic.fromValue)
                                    values["to"] = String(describing: basic.toValue)
                                    values["additive"] = basic.isAdditive
                                }
                                return values
                            }])
                        if view === cell { break }
                        current = view.superview
                    }
                }
            }
        }
        if let cell = collection.cellForItem(at: IndexPath(item: 1, section: 0)) {
            cellOrigins.append(Double(cell.layer.presentation()?.frame.minY ?? cell.frame.minY))
        }
        samples.append([Double(collection.contentOffset.y), Double(lower), Double(upper),
            Double(collection.layer.presentation()?.bounds.origin.y ?? collection.contentOffset.y)])
        let now = CACurrentMediaTime()
        if let lastFrameTime { maximumFrameGap = max(maximumFrameGap, (now - lastFrameTime) * 1000) }
        lastFrameTime = now
    }
    private func finish() {
        sample(); link?.invalidate(); link = nil; observation = nil; finishTask = nil
        geometryObservations = []
        guard let collection, let last = samples.last else { return }
        let unexpected = samples.map { abs($0[0] - min(max(Double(start), $0[1]), $0[2])) }.max() ?? 0
        // When clamping is required, its animated presentation can legitimately trail the model bounds.
        let presentationDrift = samples.filter { Double(start) >= $0[1] && Double(start) <= $0[2] }
            .map { abs($0[3] - Double(start)) }.max() ?? 0
        let value: [String: Any] = ["start": Double(start), "end": last[0], "minimum": last[1], "maximum": last[2],
            "unexpected": unexpected, "presentationDrift": presentationDrift, "samples": samples,
            "presentationSamples": presentationSamples,
            "viewportOriginDrift": viewportOrigins.first.map { first in viewportOrigins.map { abs($0 - first) }.max() ?? 0 } ?? 0,
            "cellOriginDrift": cellOrigin.map { initial in cellOrigins.map { abs($0 - Double(initial)) }.max() ?? 0 } ?? 0]
        var detailed = value
        detailed["elementSamples"] = elementSamples
        detailed["initialElementIDs"] = initialElementIDs.sorted()
        detailed["geometryWrites"] = geometryWrites
        detailed["titleLayoutSamples"] = layoutSamples
        detailed["fitSamples"] = fitSamples
        detailed["maximumFrameGapMS"] = maximumFrameGap
        detailed["titleAncestors"] = titleAncestors
        detailed["projectedTitles"] = projectedTitles
        detailed["projectedTitleDrift"] = projectedTitles.first.map { first in projectedTitles.map { abs($0[0] - first[0]) }.max() ?? 0 } ?? 0
        detailed["projectedRelativeDrift"] = projectedTitles.first.map { first in projectedTitles.map { abs($0[2] - first[2]) }.max() ?? 0 } ?? 0
        detailed["titleOriginDrift"] = layoutSamples.first.map { initial in layoutSamples.map { abs($0[1] - initial[1]) }.max() ?? 0 } ?? 0
        detailed["titleRelativeDrift"] = layoutSamples.first.map { initial in layoutSamples.map { abs($0[3] - initial[3]) }.max() ?? 0 } ?? 0
        if let data = try? JSONSerialization.data(withJSONObject: detailed), let string = String(data: data, encoding: .utf8) {
            if CompetitionLongListAcceptance.traceEnabled { collection.accessibilityLabel = string }
            else { collection.accessibilityValue = string }
        }
    }
}

private struct CompetitionDisclosureTitleAnchor: UIViewRepresentable {
    let identity: String
    final class Anchor: UIView { var identity = "" }
    func makeUIView(context: Context) -> Anchor {
        let view = Anchor(); view.backgroundColor = .clear
        view.isUserInteractionEnabled = false; view.accessibilityElementsHidden = true
        return view
    }
    func updateUIView(_ view: Anchor, context: Context) {
        if view.identity != identity { CompetitionDisclosureViewportProbe.shared.removeTitle(view, identity: view.identity) }
        view.identity = identity
        CompetitionDisclosureViewportProbe.shared.registerTitle(view, identity: identity)
    }
    static func dismantleUIView(_ view: Anchor, coordinator: Void) {
        CompetitionDisclosureViewportProbe.shared.removeTitle(view, identity: view.identity)
    }
}
#endif

extension View {
    @ViewBuilder func competitionDisclosureTitleProbe(_ identity: String) -> some View {
        #if DEBUG
        if identity.isEmpty { self }
        else { background { CompetitionDisclosureTitleAnchor(identity: identity) } }
        #else
        self
        #endif
    }
}

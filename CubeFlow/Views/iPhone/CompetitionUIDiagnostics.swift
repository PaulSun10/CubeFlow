#if DEBUG
import SwiftUI
import UIKit

enum CompetitionTopCubersDebugBounds {
    static let key = CompetitionDebugStore.key
}

/// Reuses the existing non-recognizing touch observer in every visible window
/// of the anchor's scene. Window notifications, not polling, maintain coverage.
final class CompetitionFilterInputAnchor: UIView {
    private struct Observation {
        weak var window: UIWindow?
        let recognizer: CompetitionFilterTouchObserver
    }
    private var observations: [ObjectIdentifier: Observation] = [:]
    private var recordingEnabled: Bool

    init(frame: CGRect = .zero, recordingEnabled: Bool) {
        self.recordingEnabled = recordingEnabled
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        isOpaque = false; backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        CompetitionFilterTrace.event("anchor-window-changed", fields: [
            "anchorOwner": String(describing: ObjectIdentifier(self)), "attached": window != nil,
            "parentType": superview.map { String(describing: type(of: $0)) } ?? "none"
        ])
        detach()
        guard window != nil else { return }
        recordingEnabled = CompetitionFilterTrace.enabled
        NotificationCenter.default.addObserver(self, selector: #selector(captureChanged(_:)), name: CompetitionDebugStore.changed, object: nil)
        attachWindows()
    }
    @objc private func captureChanged(_ notification: Notification) {
        recordingEnabled = CompetitionFilterTrace.enabled
        detachWindows()
        attachWindows()
    }
    private func attachWindows() {
        guard recordingEnabled else { return }
        for name in [UIWindow.didBecomeVisibleNotification, UIWindow.didBecomeHiddenNotification,
                     UIWindow.didBecomeKeyNotification, UIWindow.didResignKeyNotification,
                     UIApplication.didBecomeActiveNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowsChanged(_:)), name: name, object: nil)
        }
        refreshWindows()
    }
    @objc private func windowsChanged(_ notification: Notification) { refreshWindows() }

    func refreshWindows() {
        guard recordingEnabled, let root = window, let scene = root.windowScene else { return }
        let windows = scene.windows.filter { !$0.isHidden || $0 === root }
        let ids = Set(windows.map(ObjectIdentifier.init))
        for (id, observation) in observations where !ids.contains(id) {
            observation.window?.removeGestureRecognizer(observation.recognizer)
            observations.removeValue(forKey: id)
        }
        for window in windows where observations[ObjectIdentifier(window)] == nil {
            let observer = CompetitionFilterTouchObserver(target: nil, action: nil)
            observer.anchor = self
            observer.cancelsTouchesInView = false
            observer.delaysTouchesBegan = false
            observer.delaysTouchesEnded = false
            window.addGestureRecognizer(observer)
            observations[ObjectIdentifier(window)] = Observation(window: window, recognizer: observer)
        }
        CompetitionFilterTrace.event("window-coverage", fields: [
            "systemVersion": UIDevice.current.systemVersion, "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "screenScale": root.screen.scale, "nativeScale": root.screen.nativeScale,
            "sceneActivationState": scene.activationState.rawValue, "wallTime": Date().timeIntervalSince1970,
            "anchorWindow": String(describing: ObjectIdentifier(root)),
            "anchorOnScreen": CompetitionScrollOwnerDiagnostics.rect(root.convert(convert(bounds, to: root), to: root.screen.coordinateSpace)),
            "windows": windows.map { window in
                ["id": String(describing: ObjectIdentifier(window)), "type": String(describing: type(of: window)),
                 "key": window.isKeyWindow, "hidden": window.isHidden, "level": window.windowLevel.rawValue,
                 "bounds": CompetitionScrollOwnerDiagnostics.rect(window.bounds)] as [String: Any]
            }
        ])
    }
    func detach() {
        NotificationCenter.default.removeObserver(self)
        detachWindows()
    }
    private func detachWindows() {
        for name in [UIWindow.didBecomeVisibleNotification, UIWindow.didBecomeHiddenNotification,
                     UIWindow.didBecomeKeyNotification, UIWindow.didResignKeyNotification,
                     UIApplication.didBecomeActiveNotification] {
            NotificationCenter.default.removeObserver(self, name: name, object: nil)
        }
        for value in observations.values { value.window?.removeGestureRecognizer(value.recognizer) }
        observations = [:]
    }
}

final class CompetitionFilterTouchObserver: UIGestureRecognizer {
    weak var anchor: UIView?
    private var beganInside = false
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        beganInside = record(touch, phase: "began")
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { _ = record(touch, phase: "ended") }
        state = .failed
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { _ = record(touch, phase: "cancelled") }
        state = .failed
    }
    override func reset() { super.reset(); beganInside = false }

    @discardableResult private func record(_ touch: UITouch, phase: String) -> Bool {
        guard let anchor, let window = touch.window else { return false }
        var fields = Self.context(anchor: anchor, actualTarget: touch.view, point: touch.location(in: window), in: window)
        let inside = fields["insideFilterTarget"] as? Bool ?? false
        fields["deliveryTime"] = CACurrentMediaTime()
        fields["deliveryMs"] = (CACurrentMediaTime() - touch.timestamp) * 1000
        fields["touchID"] = String(describing: ObjectIdentifier(touch))
        CompetitionFilterTrace.event((inside || beganInside ? "filter-touch-" : "window-touch-") + phase,
            timestamp: touch.timestamp, fields: fields)
        return inside
    }

    static func context(anchor: UIView, actualTarget: UIView?, point: CGPoint, in window: UIWindow) -> [String: Any] {
        guard let root = anchor.window else { return [:] }
        let rect = root.convert(anchor.convert(anchor.bounds, to: root), to: root.screen.coordinateSpace)
        let target = rect.insetBy(dx: -max(0, (44 - rect.width) / 2), dy: -max(0, (44 - rect.height) / 2))
        let screenPoint = window.convert(point, to: window.screen.coordinateSpace)
        let inside = target.contains(screenPoint)
        var path: [String] = []
        var cursor = actualTarget
        while let view = cursor, path.count < 12 {
            path.append("\(type(of: view)):\(view.accessibilityIdentifier ?? "")")
            cursor = view.superview
        }
        var result: [String: Any] = ["insideFilterTarget": inside,
                "window": String(describing: ObjectIdentifier(window)), "windowLevel": window.windowLevel.rawValue,
                "anchorWindow": String(describing: ObjectIdentifier(root)),
                "pointInWindow": [point.x, point.y], "pointOnScreen": [screenPoint.x, screenPoint.y],
                "anchorOnScreen": CompetitionScrollOwnerDiagnostics.rect(rect),
                "targetOnScreen": CompetitionScrollOwnerDiagnostics.rect(target), "actualTargetPath": path
            ]
        if let presented = CompetitionUIDiagnosticGeometry.projectedRect(anchor, in: root) {
            result["presentedAnchorOnScreen"] = CompetitionScrollOwnerDiagnostics.rect(root.convert(presented, to: root.screen.coordinateSpace))
        } else { result["presentationProjectionUnsupported"] = true }
        return result
    }
}

struct CompetitionSeparatorScreenProbe: UIViewRepresentable {
    let layoutOriginY: CGFloat
    let displayScale: CGFloat
    let bottom: Bool
    @Environment(\.competitionSeparatorContext) private var identity
    @Environment(\.competitionDebugCompetitionID) private var competitionID
    func makeUIView(context: Context) -> CompetitionSeparatorScreenAnchor { CompetitionSeparatorScreenAnchor() }
    func updateUIView(_ view: CompetitionSeparatorScreenAnchor, context: Context) {
        view.layoutOriginY = layoutOriginY; view.displayScale = displayScale; view.bottom = bottom
        view.identity = identity
        if let competitionID { view.identity["competitionID"] = competitionID }
    }
}

final class CompetitionSeparatorScreenAnchor: UIView {
    var layoutOriginY: CGFloat = 0
    var displayScale: CGFloat = 1
    var bottom = false
    var identity: [String: String] = [:]
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false; isAccessibilityElement = false
        isOpaque = false; backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        CompetitionSeparatorScreenCapture.register(self)
    }
}

/// Explicit, one-shot capture while the physical table is stationary. This is a
/// sibling geometry marker, not access to SwiftUI's private Canvas texture.
@MainActor final class CompetitionSeparatorScreenCapture: NSObject {
    static var enabled: Bool { CompetitionDebugStore.shared.enabled && CompetitionDebugStore.shared.separatorRecording }
    private final class WeakAnchor {
        weak var value: CompetitionSeparatorScreenAnchor?
        init(_ value: CompetitionSeparatorScreenAnchor) { self.value = value }
    }
    private static var anchors: [ObjectIdentifier: WeakAnchor] = [:]
    static func register(_ anchor: CompetitionSeparatorScreenAnchor) {
        anchors = anchors.filter { $0.value.value?.window != nil }
        guard anchor.window != nil, anchors.count < 256 else { return }
        anchors[ObjectIdentifier(anchor)] = WeakAnchor(anchor)
    }
    static func snapshot(in owner: UIWindow? = nil, clip: CGRect? = nil) -> [String: Any] {
        let boundaries = anchors.values.compactMap(\.value).compactMap { view -> [String: Any]? in
            guard let window = view.window, owner == nil || owner === window else { return nil }
            var visible = view.convert(view.bounds, to: window).intersection(clip ?? window.bounds)
            var ancestor: UIView? = view
            while let current = ancestor {
                guard !current.isHidden, current.alpha > 0.01,
                      (current.layer.presentation()?.opacity ?? current.layer.opacity) > 0.01 else { return nil }
                if current.clipsToBounds { visible = visible.intersection(current.convert(current.bounds, to: window)) }
                ancestor = current.superview
            }
            guard !visible.isEmpty, !visible.isNull else { return nil }
            let scale = view.displayScale
            let paintY = CompetitionRoundBoundaryPaint.localY(origin: view.layoutOriginY,
                height: view.bounds.height, scale: scale, bottom: view.bottom)
            let top = CGPoint(x: view.bounds.midX, y: paintY)
            let bottom = CGPoint(x: top.x, y: paintY + 1 / scale)
            let modelTop = window.convert(view.convert(top, to: window), to: window.screen.coordinateSpace)
            let modelBottom = window.convert(view.convert(bottom, to: window), to: window.screen.coordinateSpace)
            let presentedTop = CompetitionUIDiagnosticGeometry.project(top, layer: view.layer, in: window.layer)
                .map { window.convert($0, to: window.screen.coordinateSpace) }
            let presentedBottom = CompetitionUIDiagnosticGeometry.project(bottom, layer: view.layer, in: window.layer)
                .map { window.convert($0, to: window.screen.coordinateSpace) }
            var ancestors: [[String: Any]] = []
            var cursor: CALayer? = view.layer
            while let layer = cursor, ancestors.count < 32 {
                let presented = layer.presentation() ?? layer
                ancestors.append(["type": String(describing: type(of: layer)),
                    "bounds": CompetitionScrollOwnerDiagnostics.rect(layer.bounds),
                    "position": [layer.position.x, layer.position.y],
                    "transform": String(describing: layer.transform),
                    "presentedTransform": String(describing: presented.transform),
                    "sublayerTransform": String(describing: presented.sublayerTransform),
                    "contentsScale": layer.contentsScale, "rasterizationScale": layer.rasterizationScale,
                    "shouldRasterize": layer.shouldRasterize, "masksToBounds": layer.masksToBounds,
                    "opacity": presented.opacity, "animationKeys": layer.animationKeys() ?? []])
                cursor = layer.superlayer
            }
            var result: [String: Any] = ["id": String(describing: ObjectIdentifier(view)),
                "boundary": view.bottom ? "header-bottom" : "round-top", "layoutOriginY": view.layoutOriginY,
                "canvasLocalPaintY": paintY, "environmentScale": scale,
                "screenScale": window.screen.scale, "nativeScale": window.screen.nativeScale,
                "screenBounds": CompetitionScrollOwnerDiagnostics.rect(window.screen.bounds),
                "nativeBounds": CompetitionScrollOwnerDiagnostics.rect(window.screen.nativeBounds),
                "window": String(describing: ObjectIdentifier(window)),
                "windowBounds": CompetitionScrollOwnerDiagnostics.rect(window.bounds),
                "modelFrameInWindow": CompetitionScrollOwnerDiagnostics.rect(view.convert(view.bounds, to: window)),
                "modelScreenY": [modelTop.y, modelBottom.y],
                "windowPaintY": Double(view.convert(top, to: window).y),
                "modelScreenPixels": [modelTop.y * window.screen.scale, modelBottom.y * window.screen.scale],
                "ancestors": ancestors, "identity": view.identity,
                "visibleFrameInWindow": CompetitionScrollOwnerDiagnostics.rect(visible)]
            if let presentedTop, let presentedBottom {
                result["presentedScreenY"] = [presentedTop.y, presentedBottom.y]
                result["presentedWindowPaintY"] = Double(window.convert(presentedTop, from: window.screen.coordinateSpace).y)
                result["presentedScreenPixels"] = [presentedTop.y * window.screen.scale, presentedBottom.y * window.screen.scale]
            } else { result["projectionUnsupported"] = true }
            return result
        }
        return ["time": CACurrentMediaTime(), "wallTime": Date().timeIntervalSince1970, "systemVersion": UIDevice.current.systemVersion,
            "measurementOwner": "Canvas sibling marker; private texture clipping/filtering is not observable",
            "boundaries": boundaries.sorted { ($0["windowPaintY"] as? Double ?? 0) < ($1["windowPaintY"] as? Double ?? 0) }]
    }


}

private enum CompetitionUIDiagnosticGeometry {
    static func projectedRect(_ view: UIView, in window: UIWindow) -> CGRect? {
        let bounds = view.layer.presentation()?.bounds ?? view.bounds
        let points = [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY)]
            .compactMap { project($0, layer: view.layer, in: window.layer) }
        guard points.count == 4, let first = points.first else { return nil }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
            CGRect(x: min(rect.minX, point.x), y: min(rect.minY, point.y),
                width: max(rect.maxX, point.x) - min(rect.minX, point.x),
                height: max(rect.maxY, point.y) - min(rect.minY, point.y))
        }
    }
    static func project(_ original: CGPoint, layer: CALayer, in ancestor: CALayer) -> CGPoint? {
        var model = layer
        var point = original
        while model !== ancestor {
            let state = model.presentation() ?? model
            guard CATransform3DIsAffine(state.transform), let parent = model.superlayer else { return nil }
            let anchor = CGPoint(x: state.bounds.minX + state.bounds.width * state.anchorPoint.x,
                y: state.bounds.minY + state.bounds.height * state.anchorPoint.y)
            point = CGPoint(x: point.x - anchor.x, y: point.y - anchor.y)
                .applying(CATransform3DGetAffineTransform(state.transform))
            point.x += state.position.x; point.y += state.position.y
            let next = parent.presentation() ?? parent
            guard CATransform3DIsAffine(next.sublayerTransform) else { return nil }
            let pivot = CGPoint(x: next.bounds.minX + next.bounds.width * next.anchorPoint.x,
                y: next.bounds.minY + next.bounds.height * next.anchorPoint.y)
            point = CGPoint(x: point.x - pivot.x, y: point.y - pivot.y)
                .applying(CATransform3DGetAffineTransform(next.sublayerTransform))
            point.x += pivot.x; point.y += pivot.y
            model = parent
        }
        return point
    }
}
#endif

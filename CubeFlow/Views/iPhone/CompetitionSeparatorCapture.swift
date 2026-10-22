import SwiftUI
#if DEBUG
import UIKit
import Combine

private struct CompetitionSeparatorContextKey: EnvironmentKey {
    static let defaultValue: [String: String] = [:]
}
private struct CompetitionDebugCompetitionKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    var competitionDebugCompetitionID: String? {
        get { self[CompetitionDebugCompetitionKey.self] }
        set { self[CompetitionDebugCompetitionKey.self] = newValue }
    }
    var competitionSeparatorContext: [String: String] {
        get { self[CompetitionSeparatorContextKey.self] }
        set { self[CompetitionSeparatorContextKey.self] = newValue }
    }
}

struct CompetitionSeparatorInstrumentation: ViewModifier {
    let origin: CGFloat
    let scale: CGFloat
    let bottom: Bool
    @ObservedObject private var store = CompetitionDebugStore.shared
    func body(content: Content) -> some View {
        content.background {
            if store.enabled && store.separatorRecording {
                CompetitionSeparatorScreenProbe(layoutOriginY: origin, displayScale: scale, bottom: bottom)
            }
        }
    }
}

/// Image-space line positions are derived from the *same* window/crop as the
/// snapshot. IDs describe real rows; missing source identity is explicit.
struct CompetitionSeparatorLine: Identifiable, Codable, Equatable {
    let id: String
    let label: String
    let x0: CGFloat
    let x1: CGFloat
    let y: CGFloat
    let identity: [String: String]
    static func mapped(_ boundaries: [[String: Any]], crop: CGRect) -> [Self] {
        boundaries.enumerated().compactMap { index, item in
            guard let frame = item["visibleFrameInWindow"] as? [Double], frame.count == 4,
                  let screenY = (item["presentedWindowPaintY"] ?? item["windowPaintY"]) as? Double else { return nil }
            let rect = CGRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3]).intersection(crop)
            guard !rect.isEmpty, !rect.isNull, screenY >= rect.minY, screenY <= rect.maxY else { return nil }
            let identity = item["identity"] as? [String: String] ?? [:]
            let label: String
            if let before = identity["beforeRound"], let after = identity["afterRound"] {
                label = before + " → " + after
            } else { label = "Separator \(identity["separatorIndex"] ?? String(index + 1)) — round identity unknown" }
            let id = identity["boundaryID"] ?? (item["id"] as? String) ?? "separator-\(index)"
            return Self(id: id, label: label, x0: (rect.minX - crop.minX) / crop.width,
                x1: (rect.maxX - crop.minX) / crop.width, y: (screenY - crop.minY) / crop.height, identity: identity)
        }
    }
    static func nearest(to point: CGPoint, size: CGSize, lines: [Self], tolerance: CGFloat = 14) -> Self? {
        lines.filter { point.x >= $0.x0 * size.width - tolerance && point.x <= $0.x1 * size.width + tolerance }
            .filter { abs(point.y - $0.y * size.height) <= tolerance }
            .min { abs(point.y - $0.y * size.height) < abs(point.y - $1.y * size.height) }
    }
}

struct CompetitionSeparatorSelection {
    var ids: [String] = []
    private var history: [[String]] = []
    var canUndo: Bool { !history.isEmpty }
    private mutating func remember() {
        history.append(ids)
        if history.count > 64 { history.removeFirst() }
    }
    mutating func toggle(_ id: String) {
        remember()
        if let index = ids.firstIndex(of: id) { ids.remove(at: index) } else { ids.append(id) }
    }
    mutating func clear() { remember(); ids = [] }
    mutating func undo() { if let last = history.popLast() { ids = last } }
}

final class CompetitionSeparatorCardAnchor: UIView {
    var competitionID: String?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false; isAccessibilityElement = false; backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func capture(store suppliedStore: CompetitionDebugStore? = nil) throws -> CompetitionDebugStore.Capture {
        let store = suppliedStore ?? CompetitionDebugStore.shared
        guard store.enabled, store.separatorRecording, let window else { throw CaptureError.unavailable }
        let crop = convert(bounds, to: window).intersection(window.bounds)
        guard crop.width > 0, crop.height > 0 else { throw CaptureError.unavailable }
        var metadata = CompetitionSeparatorScreenCapture.snapshot(in: window, clip: crop)
        let boundaries = metadata["boundaries"] as? [[String: Any]] ?? []
        guard !boundaries.isEmpty else { throw CaptureError.noTable }
        let format = UIGraphicsImageRendererFormat(); format.scale = window.screen.scale; format.opaque = false
        let image = UIGraphicsImageRenderer(size: crop.size, format: format).image { context in
            context.cgContext.translateBy(x: -crop.minX, y: -crop.minY)
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        guard let data = image.pngData() else { throw CaptureError.unavailable }
        let lines = CompetitionSeparatorLine.mapped(boundaries, crop: crop)
        guard !lines.isEmpty else { throw CaptureError.noTable }
        metadata["lines"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(lines))
        metadata["selectedSeparatorIDs"] = [String]()
        metadata["cropInWindow"] = CompetitionScrollOwnerDiagnostics.rect(crop)
        metadata["windowSize"] = [window.bounds.width, window.bounds.height]
        metadata["screenSize"] = [window.screen.bounds.width, window.screen.bounds.height]
        metadata["cropOnScreen"] = CompetitionScrollOwnerDiagnostics.rect(window.convert(crop, to: window.screen.coordinateSpace))
        metadata["competitionID"] = competitionID as Any? ?? NSNull()
        metadata["imageSize"] = [image.size.width, image.size.height]
        metadata["imageSource"] = "UIKit drawHierarchy snapshot (not final compositor pixels)"
        metadata["screenImageLimitation"] = "Geometry and snapshot sampled in one main-thread action, not an atomic compositor capture. Import a stationary original system screenshot if appearance differs."
        return try store.save(kind: .separator, metadata: metadata, image: data)
    }
    enum CaptureError: LocalizedError {
        case unavailable, noTable
        var errorDescription: String? {
            self == .noTable ? "Open All Results with visible round boundaries before capturing." : "The Result Card is not visible."
        }
    }
}
private final class CompetitionSeparatorCardReference: ObservableObject { weak var view: CompetitionSeparatorCardAnchor? }
private struct CompetitionSeparatorCardProbe: UIViewRepresentable {
    let reference: CompetitionSeparatorCardReference
    @Environment(\.competitionDebugCompetitionID) private var competitionID
    func makeUIView(context: Context) -> CompetitionSeparatorCardAnchor {
        let view = CompetitionSeparatorCardAnchor(); reference.view = view; return view
    }
    func updateUIView(_ uiView: CompetitionSeparatorCardAnchor, context: Context) { reference.view = uiView; uiView.competitionID = competitionID }
}
private struct CompetitionSeparatorCaptureOverlay: ViewModifier {
    @ObservedObject private var store = CompetitionDebugStore.shared
    @StateObject private var reference = CompetitionSeparatorCardReference()
    @State private var review: CompetitionDebugStore.Capture?
    func body(content: Content) -> some View {
        content.background {
            if store.enabled && store.separatorRecording { CompetitionSeparatorCardProbe(reference: reference) }
        }.overlay(alignment: .bottomLeading) {
            if store.enabled && store.separatorRecording {
                Button {
                    do { review = try reference.view?.capture() }
                    catch { store.failure = error.localizedDescription }
                } label: { Label("Capture Visible Table", systemImage: "camera").font(.caption).padding(8).background(.regularMaterial, in: Capsule()) }
                .offset(y: 38)
                .accessibilityIdentifier("separator-capture-visible")
            }
        }.sheet(item: $review) { capture in
            NavigationView { CompetitionSeparatorReview(capture: capture) }.navigationViewStyle(.stack)
        }.onChange(of: store.enabled) { if !$0 { review = nil } }
        .alert("Capture", isPresented: Binding(get: { store.failure != nil }, set: { if !$0 { store.failure = nil } })) {
            Button("OK") { store.failure = nil }
        } message: { Text(store.failure ?? "") }
    }
}
#endif

extension View {
    @ViewBuilder func competitionDebugCompetition(_ id: String?) -> some View {
        #if DEBUG
        environment(\.competitionDebugCompetitionID, id)
        #else
        self
        #endif
    }
    @ViewBuilder func competitionSeparatorIdentity(event: String, beforeID: String?, before: String?, afterID: String, after: String, index: Int = 0) -> some View {
        #if DEBUG
        environment(\.competitionSeparatorContext, ["eventID": event, "boundaryID": "\(event):\(beforeID ?? "header"):\(afterID)",
            "beforeRoundID": beforeID ?? "header", "beforeRound": before ?? "Header", "afterRoundID": afterID, "afterRound": after,
            "tableID": event, "separatorIndex": String(index)])
        #else
        self
        #endif
    }
    @ViewBuilder func competitionSeparatorCaptureControl() -> some View {
        #if DEBUG
        modifier(CompetitionSeparatorCaptureOverlay())
        #else
        self
        #endif
    }
}

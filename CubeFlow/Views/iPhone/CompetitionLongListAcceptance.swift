#if DEBUG
import SwiftUI
import UIKit
import QuartzCore

/// Captured public competition summaries and one verified WCIF, using the real browser rows.
enum CompetitionLongListAcceptance {
    static var firstDragStarted = false
    static var responseReleasedAt: Double?
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--competition-long-list-acceptance") }
    static var traceEnabled: Bool { enabled || CompetitionPhysicalBrowserAcceptance.enabled || CompetitionScrollOwnerDiagnostics.enabled }
    static let summaries: [CompetitionSummary] = {
        guard let path = ProcessInfo.processInfo.environment["CUBEFLOW_LONG_LIST_JSON"],
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode([CompetitionSummary].self, from: data) }
        catch { print("[LongListFixture] decode failed: \(error)"); return [] }
    }()
    static let topCubers: [CompetitionTopCuberPreview] = {
        guard let path = ProcessInfo.processInfo.environment["CUBEFLOW_LONG_WCIF_JSON"],
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }
        return CompetitionService.decodeCompetitionTopCuberPreviews(data,
            eventIDs: summaries.first { $0.id == "BeijingAutumnRivalry2026" }?.eventIDs ?? []) ?? []
    }()
    static func cached(_ id: String) async -> [CompetitionTopCuberPreview]? {
        guard id == "BeijingAutumnRivalry2026" else { return [] }
        return ProcessInfo.processInfo.arguments.contains("--competition-long-warm") ? topCubers : nil
    }
    static func fetched(_ competition: CompetitionSummary, _ language: String) async -> [CompetitionTopCuberPreview]? {
        // Release the response during a real drag, not during app-launch idling.
        while !firstDragStarted && !Task.isCancelled { try? await Task.sleep(nanoseconds: 20_000_000) }
        try? await Task.sleep(nanoseconds: 180_000_000)
        responseReleasedAt = CACurrentMediaTime()
        return Task.isCancelled ? nil : topCubers
    }
}

@MainActor final class CompetitionLongScrollTrace: NSObject {
    private var samples: [[Double]] = []
    private var start: Double = 0
    private var ended: Double?
    private var idleRecordingComplete = false
    private weak var scroll: UIScrollView?
    private var idleLink: CADisplayLink?
    private var owners: [[String: Any]] = []
    private var archived = false
    private var style = ""
    private var active = false
    private var retainsCapture = false
    private var storeGeneration = 0
    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(captureChanged), name: CompetitionDebugStore.changed, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func captureChanged() {
        if retainsCapture && !CompetitionScrollOwnerDiagnostics.enabled { finalize(reason: "recording-disabled") }
    }
    func begin(_ scroll: UIScrollView) {
        finalize(reason: "next-gesture")
        active = true
        retainsCapture = CompetitionScrollOwnerDiagnostics.enabled
        storeGeneration = CompetitionScrollCaptureStore.shared.generation
        self.scroll = scroll; ended = nil
        idleRecordingComplete = false
        archived = false
        style = UserDefaults.standard.string(forKey: "competitionCardStyle") ?? "list"
        scroll.accessibilityValue = "Recording"
        samples = []; owners = []; start = CACurrentMediaTime(); sample(scroll, capturesOwners: true)
        if CompetitionScrollOwnerDiagnostics.enabled {
            let link = CADisplayLink(target: self, selector: #selector(sampleIdle))
            idleLink = link; link.add(to: .main, forMode: .common)
        }
    }
    func sample(_ scroll: UIScrollView, capturesOwners: Bool = false) {
        guard active, samples.count < 1200 else { return }
        if capturesOwners, let owner = CompetitionScrollOwnerDiagnostics.sample(scroll) { owners.append(owner) }
        samples.append([CACurrentMediaTime() - start, scroll.contentOffset.y,
            -scroll.adjustedContentInset.top,
            max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom),
            scroll.adjustedContentInset.top])
        if let collection = scroll as? UICollectionView, let window = collection.window,
           let index = collection.indexPathsForVisibleItems.sorted(by: { $0.item < $1.item }).first,
           let cell = collection.cellForItem(at: index) {
            samples[samples.count - 1].append(contentsOf: [Double(index.item),
                cell.convert(.zero, to: window).y,
                collection.convert(collection.bounds.origin, to: window).y,
                CompetitionDisclosureViewportProbe.shared.projectedOrigin(cell.layer, in: window.layer)?.y ?? cell.convert(.zero, to: window).y])
        }

    }
    func finish(_ scroll: UIScrollView) {
        guard active, ended == nil else { return }
        ended = CACurrentMediaTime()
        idleRecordingComplete = false
        if !CompetitionScrollOwnerDiagnostics.enabled { publish(scroll) }
        // Read-only coverage of publication/layout just after dragging and
        // deceleration end. Do not delay or trigger any production state update.
        if idleLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(sampleIdle))
            idleLink = link; link.add(to: .main, forMode: .common)
        }
    }
    @objc private func sampleIdle() {
        guard active else { return }
        guard CompetitionLongListAcceptance.traceEnabled else { finalize(reason: "recording-disabled"); return }
        guard let scroll, scroll.window != nil else { finalize(reason: "view-detached"); return }
        guard CACurrentMediaTime() - start < 30 else { finalize(reason: "duration-limit"); return }
        guard let ended else { sample(scroll, capturesOwners: true); return }
        idleRecordingComplete = CACurrentMediaTime() - ended >= 0.65
        sample(scroll, capturesOwners: true)
        if idleRecordingComplete {
            finalize(reason: "post-idle-complete")
        }
    }
    private func finalize(reason: String) {
        guard active else { return }
        // The last valid frames outlive the weak scroll view. Never fabricate
        // post-idle measurements after tab detachment or recording stops.
        let visibleScroll = scroll.flatMap { $0.window != nil ? $0 : nil }
        if let visibleScroll { sample(visibleScroll, capturesOwners: true) }
        idleLink?.invalidate(); idleLink = nil
        publish(visibleScroll, finalizationReason: reason)
        active = false; scroll = nil
    }
    private func publish(_ scroll: UIScrollView?, finalizationReason: String? = nil) {
        let released = CompetitionLongListAcceptance.responseReleasedAt
        let overlap = released.map { $0 >= start && $0 <= (ended ?? CACurrentMediaTime()) } ?? false
        let capture: [String: Any] = ["samples": samples, "loadReleasedDuringGesture": overlap,
            "owners": owners, "loadingEvents": CompetitionScrollOwnerDiagnostics.events,
            "startTime": start, "style": style,
            "gestureCompleted": ended != nil,
            "captureFinalized": finalizationReason != nil,
            "finalizationReason": finalizationReason ?? "collecting",
            "truncated": samples.count >= 1200,
            "droppedTimelineEvents": CompetitionScrollOwnerDiagnostics.droppedEvents,
            "topCubersEnabled": UserDefaults.standard.bool(forKey: "competition_show_top_cubers"),
            "idleRecordingComplete": idleRecordingComplete,
            "idleAfterStart": ended.map { $0 - start } ?? -1,
            "releasedAfterStart": released.map { $0 - start } ?? -1]
        if finalizationReason != nil, retainsCapture, !archived, !owners.isEmpty {
            archived = true
            CompetitionScrollOwnerDiagnostics.archive(capture, generation: storeGeneration)
        }
        // Physical captures stay in memory until an explicit Share action. The
        // large accessibility JSON is needed only by automated fixture checks.
        guard let scroll, ProcessInfo.processInfo.arguments.contains("--competition-scroll-owner-timing")
            || CompetitionLongListAcceptance.enabled || CompetitionPhysicalBrowserAcceptance.enabled else { return }
        if let bytes = try? JSONSerialization.data(withJSONObject: capture),
           let text = String(data: bytes, encoding: .utf8) { scroll.accessibilityValue = text }
    }
}
#endif

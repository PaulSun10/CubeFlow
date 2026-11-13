#if DEBUG && os(iOS)
import SwiftUI
import os

@MainActor final class AppPerformanceProbe {
    var dataRequests = 0
    var dataCount: Int?
    var dataSelect: ((Bool) -> Void)?
    var dataToggleAll: (() -> Void)?
    var dataToggleOne: ((UUID) -> Void)?
    var dataSelection: (() -> (selected: Set<UUID>, visible: Set<UUID>))?
    var dataOpenSessionSheet: (() -> Void)?
    var dataChooseSession: ((UUID) -> Void)?
    var dataCloseSessionSheet: (() -> Void)?
    var dataSessionSelection: (() -> String)?
    var timerStatisticsReads = 0
}
private struct AppPerformanceProbeKey: EnvironmentKey {
    static let defaultValue: AppPerformanceProbe? = nil
}
extension EnvironmentValues {
    var appPerformanceProbe: AppPerformanceProbe? {
        get { self[AppPerformanceProbeKey.self] }
        set { self[AppPerformanceProbeKey.self] = newValue }
    }
}

/// Opt-in, allowlisted milestones; never records user data or OAuth material.
/// Times are relative to persistence initialization, not Apple's process-launch metric.
nonisolated enum AppExperienceTrace {
    private static let enabled = ProcessInfo.processInfo.environment["CUBEFLOW_EXPERIENCE_TRACE"] == "1"
    private static let start = ProcessInfo.processInfo.systemUptime
    private static let log = Logger(subsystem: "com.paulsun.cubeflow", category: "Experience")
    private static let signposter = OSSignposter(logger: log)
    static func mark(_ label: StaticString) {
        guard enabled else { return }
        let milestone = String(describing: label)
        let startedAt = start
        let elapsed = (ProcessInfo.processInfo.systemUptime - startedAt) * 1000
        let main = Thread.isMainThread ? 1 : 0
        signposter.emitEvent("Experience", "\(milestone, privacy: .public) elapsed_ms=\(elapsed) main=\(main)")
        log.info("milestone=\(milestone, privacy: .public) elapsed_ms=\(elapsed) main=\(main)")
    }
}

struct AppFirstFrameProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> FrameView { FrameView() }
    func updateUIView(_ view: FrameView, context: Context) {}
    static func dismantleUIView(_ view: FrameView, coordinator: ()) { view.stop() }
    final class FrameView: UIView {
        private var link: CADisplayLink?
        private var previous: CFTimeInterval?
        private var ticks = 0
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { stop() }
            else if link == nil, ticks == 0, ProcessInfo.processInfo.environment["CUBEFLOW_EXPERIENCE_TRACE"] == "1" {
                let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
                self.link = link; link.add(to: .main, forMode: .common)
            }
        }
        @objc private func frame(_ sender: CADisplayLink) {
            guard UIApplication.shared.applicationState == .active else { previous = nil; return }
            if ticks == 0 { AppExperienceTrace.mark("first_display_link") }
            if let previous, sender.timestamp - previous > 0.1 { AppExperienceTrace.mark("frame_gap_over_100ms") }
            previous = sender.timestamp; ticks += 1
            if ticks >= 180 { stop() }
        }
        func stop() { link?.invalidate(); link = nil }
    }
}

/// Launch with CUBEFLOW_DATA_SELECTION_TRACE=1. Samples geometry, not pixels or user data.
struct DataSelectionTransitionTrace: UIViewRepresentable {
    static let isEnabled = ProcessInfo.processInfo.environment["CUBEFLOW_DATA_SELECTION_TRACE"] == "1"
    let selecting: Bool
    func makeUIView(context: Context) -> Sampler { Sampler() }
    func updateUIView(_ view: Sampler, context: Context) { view.update(selecting) }
    static func dismantleUIView(_ view: Sampler, coordinator: ()) { view.stop() }

    final class Sampler: UIView {
        private let log = Logger(subsystem: "com.paulsun.cubeflow", category: "DataSelection")
        private var link: CADisplayLink?
        private weak var scroll: UIScrollView?
        private var lastSelection: Bool?
        private var start: CFTimeInterval = 0
        private var previous: CFTimeInterval?
        private var largestGap: CFTimeInterval = 0
        private var samples = 0
        private var geometry: [String] = []

        func update(_ selecting: Bool) {
            defer { lastSelection = selecting }
            guard let lastSelection, lastSelection != selecting, let window else { return }
            finish()
            func scrollViews(in view: UIView) -> [UIScrollView] {
                guard !view.isHidden, view.alpha > 0, view.convert(view.bounds, to: window).intersects(window.bounds) else { return [] }
                return (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
            }
            scroll = scrollViews(in: window).max(by: { $0.bounds.height < $1.bounds.height })
            start = CACurrentMediaTime()
            samples = 0; previous = nil; largestGap = 0; geometry = []
            let displayLink = CADisplayLink(target: self, selector: #selector(frame(_:)))
            link = displayLink
            displayLink.add(to: .main, forMode: .common)
        }

        @objc private func frame(_ link: CADisplayLink) {
            let elapsed = CACurrentMediaTime() - start
            if let previous { largestGap = max(largestGap, link.timestamp - previous) }
            previous = link.timestamp
            samples += 1
            if let scroll {
                let value = "\(Int(scroll.adjustedContentInset.bottom.rounded()))/\(Int(scroll.contentOffset.y.rounded()))/\(Int(scroll.bounds.height.rounded()))"
                if geometry.last?.hasSuffix(":" + value) != true {
                    geometry.append("\(Int(elapsed * 1000)):\(value)")
                }
            }
            if elapsed >= 0.55 || samples >= 72 { finish() }
        }

        private func finish() {
            guard link != nil else { return }
            let summary = "selecting=\(lastSelection == true) dark=\(traitCollection.userInterfaceStyle == .dark) samples=\(samples) gap_ms=\(largestGap * 1000) ms:inset/offset/height=\(geometry.joined(separator: ","))"
            log.info("\(summary, privacy: .public)")
            stop()
        }

        func stop() { link?.invalidate(); link = nil }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { stop() }
        }
    }
}
#endif

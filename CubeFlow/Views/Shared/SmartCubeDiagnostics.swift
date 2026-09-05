#if os(iOS) && DEBUG
import Foundation

// Diagnostic-only, bounded in-memory traces. No packets, scramble text or solve
// history are persisted. Formatting/console output never blocks the BLE/UI path.
nonisolated final class SmartCubeDiagnostics: @unchecked Sendable {
    static let shared = SmartCubeDiagnostics()

    private struct Entry: Sendable {
        let uptime: TimeInterval
        let stage: String
        let id: UUID?
        let detail: String
    }

    private let lock = NSLock()
    private let output = DispatchQueue(label: "CubeFlow.smart-cube-diagnostics", qos: .utility)
    private var entries: [Entry] = []
    private var activeStart: TimeInterval?
    private var liveWaitPrintedAt: TimeInterval = 0

    func mark(_ stage: String, id: UUID? = nil, detail: String = "") {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        entries.append(Entry(uptime: now, stage: stage, id: id, detail: detail))
        if entries.count > 2048 { entries.removeFirst(entries.count - 2048) }
        let shouldPrintWait = activeStart != nil
            && (stage == "history.gap" || stage == "history.retryExhausted")
            && now - liveWaitPrintedAt > 0.5
        if shouldPrintWait { liveWaitPrintedAt = now }
        lock.unlock()
        if shouldPrintWait {
            output.async { print("[SCDEBUG] WAIT uptime=\(now) stage=\(stage) \(detail)") }
        }
    }

    func begin(_ move: SmartCubeMoveEvent) {
        lock.lock()
        activeStart = ProcessInfo.processInfo.systemUptime
        lock.unlock()
        mark("solve.start", id: move.id)
        let description = Self.describe(move)
        output.async { print("[SCDEBUG] START \(description)") }
    }

    func interrupted(_ reason: SmartCubeContinuityReason) {
        lock.lock()
        let wasActive = activeStart != nil
        activeStart = nil
        lock.unlock()
        mark("continuity.break", detail: reason.rawValue)
        if wasActive {
            output.async { print("[SCDEBUG] ABORT continuity=\(reason.rawValue) no solve saved") }
        }
    }

    func finish(start: SmartCubeMoveEvent, end: SmartCubeMoveEvent?, recognizedAt: Date, storedSeconds: Double, displayedSeconds: Double) {
        lock.lock()
        let cutoff = (activeStart ?? ProcessInfo.processInfo.systemUptime) - 0.1
        let trace = entries.filter { $0.uptime >= cutoff }
        activeStart = nil
        lock.unlock()
        let summary = SmartCubeTimingDiagnosticSummary(
            start: start, end: end, recognizedAt: recognizedAt, storedSeconds: storedSeconds
        )
        let startDescription = Self.describe(start)
        let endDescription = end.map(Self.describe) ?? "none"
        output.async {
            print("[SCDEBUG] FINISH first={\(startDescription)} last={\(endDescription)}")
            print("[SCDEBUG] DISPLAY numeric_seconds=\(displayedSeconds) (before text formatting)")
            print("[SCDEBUG] TIMING recognized_epoch=\(recognizedAt.timeIntervalSince1970) stored_s=\(storedSeconds) local_first_last_s=\(Self.number(summary.localInterval)) device_first_last_s=\(Self.number(summary.deviceInterval)) selected_source=\(summary.selectedSource) stored_minus_move_s=\(Self.number(summary.storedMinusMove)) recognition_after_canonical_ms=\(Self.number(summary.recognitionLatency.map { $0 * 1000 }))")
            print("[SCDEBUG] NOTE recognition latency uses the canonical timestamp estimate, not an independent physical clock; reconstructed timestamps are not measured turn intervals.")
            Self.printPipeline(trace)
        }
    }

    private static func describe(_ move: SmartCubeMoveEvent) -> String {
        "id=\(move.id) move=\(move.move) serial=\(move.serial.map(String.init) ?? "nil") canonical_epoch=\(move.localTimestamp.timeIntervalSince1970) device_ms=\(move.cubeTimestampMilliseconds.map(String.init) ?? "nil") source=\(move.timestampSource)"
    }

    private static func number(_ value: Double?) -> String {
        value.map { String(format: "%.6f", $0) } ?? "unavailable"
    }

    private static func printPipeline(_ trace: [Entry]) {
        let stages = Dictionary(grouping: trace, by: \.stage)
        let counts = stages.keys.sorted().map { "\($0)=\(stages[$0]!.count)" }.joined(separator: " ")
        print("[SCDEBUG] PIPELINE counts \(counts) (bounded recent trace)")
        let links = [
            ("ble.rx", "parser.begin"), ("parser.begin", "parser.end"),
            ("parser.end", "main.apply"), ("protocol.move", "canonical.publish"),
            ("coalesce.pending", "coalesce.flush"), ("coalesce.merge", "canonical.publish"),
            ("canonical.publish", "timer.consume"), ("timer.consume", "solve.recognized")
        ]
        for (from, to) in links {
            var origins: [UUID: TimeInterval] = [:]
            for entry in stages[from] ?? [] {
                if let id = entry.id { origins[id] = entry.uptime }
            }
            let intervals = (stages[to] ?? []).compactMap { entry -> Double? in
                guard let id = entry.id, let time = origins[id] else { return nil }
                return max(0, entry.uptime - time) * 1000
            }
            print("[SCDEBUG] PIPELINE \(from)->\(to) matched=\(intervals.count) max_ms=\(number(intervals.max()))")
        }
        for stage in ["ble.rx", "protocol.move", "canonical.publish", "timer.consume"] {
            let values = stages[stage] ?? []
            let gaps = zip(values, values.dropFirst()).map { ($1.uptime - $0.uptime) * 1000 }
            print("[SCDEBUG] GAP stage=\(stage) max_interarrival_ms=\(number(gaps.max())) (includes intentional pauses)")
        }
        for entry in trace.filter({ ($0.stage.hasPrefix("history.") && $0.stage != "history.drain") || $0.stage.hasPrefix("coalesce.") || $0.stage == "continuity.break" }).suffix(32) {
            print("[SCDEBUG] STAGE uptime=\(entry.uptime) \(entry.stage) \(entry.detail)")
        }
    }
}

nonisolated struct SmartCubeTimingDiagnosticSummary {
    let localInterval: Double?
    let deviceInterval: Double?
    let selectedSource: String
    let storedMinusMove: Double?
    let recognitionLatency: Double?

    init(start: SmartCubeMoveEvent, end: SmartCubeMoveEvent?, recognizedAt: Date, storedSeconds: Double) {
        localInterval = end.map { $0.localTimestamp.timeIntervalSince(start.localTimestamp) }
        if let end, start.timestampSource == .deviceClock, end.timestampSource == .deviceClock,
           let first = start.cubeTimestampMilliseconds, let last = end.cubeTimestampMilliseconds,
           let delta = SmartCubeSolveTiming.positiveDeviceDelta(from: first, to: last) {
            deviceInterval = Double(delta) / 1000
        } else {
            deviceInterval = nil
        }
        let reference = deviceInterval ?? localInterval.flatMap { $0 > 0 ? $0 : nil }
        selectedSource = deviceInterval != nil ? "deviceClock" : (reference != nil ? "canonicalLocalTimestamp" : "recognitionWallClockFallback")
        storedMinusMove = reference.map { storedSeconds - $0 }
        recognitionLatency = end.map { recognizedAt.timeIntervalSince($0.localTimestamp) }
    }
}
#endif

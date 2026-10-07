import Foundation

/// Independent, queue-confined producers; consumers join pending work instead of
/// starting another solve behind it. Storage and in-flight work share one bound.
nonisolated final class FTOGenerationPool: @unchecked Sendable {
    private let condition = NSCondition()
    private var reserve: ScrambleReserve
    private var busy: [Bool]
    private var failed: [Bool]
    private let queues: [DispatchQueue]
    private let generate: @Sendable (Int) -> String?

    init(capacity: Int = 4, producerCount: Int = 2, generate: @escaping @Sendable (Int) -> String?) {
        precondition(capacity > 0 && producerCount > 0)
        reserve = ScrambleReserve(capacity: capacity)
        busy = Array(repeating: false, count: producerCount)
        failed = busy
        queues = (0..<producerCount).map { DispatchQueue(label: "CubeFlow.fto-producer.\($0)", qos: .userInitiated) }
        self.generate = generate
    }

    var count: Int {
        condition.lock()
        defer { condition.unlock() }
        return reserve.entries.count
    }

    func prewarm() {
        condition.lock()
        retryFailedProducersForNewDemandLocked()
        scheduleRefillsLocked()
        condition.unlock()
    }

    func take() -> String? {
        condition.lock()
        retryFailedProducersForNewDemandLocked()
        scheduleRefillsLocked()
        while reserve.entries.isEmpty && busy.contains(true) { condition.wait() }
        let result = reserve.take()
        scheduleRefillsLocked()
        condition.unlock()
        return result
    }

    private func retryFailedProducersForNewDemandLocked() {
        // Do not spin on a failed solve; a later explicit request may retry.
        if reserve.entries.isEmpty && !busy.contains(true) {
            failed = Array(repeating: false, count: failed.count)
        }
    }

    private func scheduleRefillsLocked() {
        for index in queues.indices where !busy[index] && !failed[index] {
            guard reserve.entries.count + busy.filter({ $0 }).count < reserve.capacity else { break }
            busy[index] = true
            queues[index].async { [self] in
                let started = ProcessInfo.processInfo.systemUptime
                let value = generate(index)
                condition.lock()
                if let value { reserve.append(value) }
                else { failed[index] = true }
                busy[index] = false
                condition.broadcast()
                scheduleRefillsLocked()
                condition.unlock()
                #if DEBUG
                print(String(format: "[ScramblePerf] FTO producer=%d generation_ms=%.1f", index, (ProcessInfo.processInfo.systemUptime - started) * 1_000))
                #endif
            }
        }
    }
}

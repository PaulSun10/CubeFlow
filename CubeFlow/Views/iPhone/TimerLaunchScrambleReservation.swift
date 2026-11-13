#if os(iOS)
import Foundation

/// A single-use launch reservation for the persisted visible event, not a
/// general cache. A mismatched first demand invalidates it permanently.
@MainActor final class TimerLaunchScrambleReservation {
    static let shared = TimerLaunchScrambleReservation()
    private var context: TimerScrambleGenerationContext?
    private var generation = UUID()
    private var payload: TimerScrambleGenerationPayload?
    private var consumer: (@MainActor (TimerScrambleGenerationPayload) -> Void)?
    private var prepared = false
    private var claimed = false

    func prepare(_ context: TimerScrambleGenerationContext,
                 generate: (TimerScrambleGenerationContext, @escaping @MainActor (TimerScrambleGenerationPayload) -> Void) -> Void) {
        guard !prepared else { return }
        prepared = true; self.context = context
        let id = generation
        generate(context) { [weak self] result in
            guard let self, self.generation == id, self.context == result.context else { return }
            if let consumer = self.consumer {
                self.consumer = nil; self.context = nil
                consumer(result)
            } else if !self.claimed { self.payload = result }
        }
    }

    func consume(for requested: TimerScrambleGenerationContext,
                 completion: @escaping @MainActor (TimerScrambleGenerationPayload) -> Void) -> Bool {
        guard prepared, !claimed else { return false }
        claimed = true
        guard context == requested else {
            generation = UUID(); context = nil; payload = nil; consumer = nil
            return false
        }
        if let payload {
            self.payload = nil; context = nil
            completion(payload)
        } else { consumer = completion }
        return true
    }
}
#endif

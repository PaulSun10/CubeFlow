#if os(iOS)
import Foundation
import Combine

/// One native owner and one replaceable latest-state slot. Independent exact
/// short search never waits behind native work. Cancellation is cooperative;
/// ownership remains until even an uninterruptible injected worker returns.
@MainActor final class SmartCubeGuidanceController: ObservableObject {
    nonisolated struct Request: Equatable, Sendable {
        let identity: SmartCubeRecoveryPlanIdentity
        let sourceFacelets: String
        let targetFacelets: String
        let generation: Int
        let knownPath: [String]?
        var continuationOnly = false
        var keepsEqualPath = false
        var deviceID: UUID? = nil
        var canonicalSequence: UInt64 = 0
    }

    nonisolated struct Publication: Sendable {
        let request: Request
        let decision: SmartCubeReplacementDecision

        @MainActor func progress(identity: SmartCubeRecoveryPlanIdentity, facelets: String,
                      target: String, generation: Int, trusted: Bool, eligible: Bool,
                      deviceID: UUID? = nil) -> SmartCubeScrambleProgress? {
            guard eligible, request.deviceID == deviceID, let replacement = decision.replacement,
                  replacement.canAdopt(identity: identity, facelets: facelets,
                    targetFacelets: target, trusted: trusted, deviated: eligible,
                    currentGeneration: generation) else { return nil }
            return SmartCubeScrambleProgress(replacement: replacement)
        }
    }

    enum Phase { case idle, settling, solving, unavailable }
    typealias Search = @Sendable (Request) async -> SmartCubeReplacementDecision
    typealias Settle = @Sendable () async throws -> Void
    @Published private(set) var phase = Phase.idle
    @Published private(set) var publication: Publication?
    var isUpdating: Bool { phase == .settling || phase == .solving }
    var currentRequest: Request? { latest }
    private let search: Search
    private let settle: Settle
    private let fastSearch: Search?
    private var latest: Request?
    private var ticket: UInt64 = 0
    private var settledTicket: UInt64?
    private var debounceTask: Task<Void, Never>?
    private var worker: Task<Void, Never>?
    private var fastWorker: Task<Void, Never>?

    init(settle: @escaping Settle = { try await Task.sleep(nanoseconds: 120_000_000) },
         search: Search? = nil, fastSearch: Search? = nil) {
        self.settle = settle
        if let search {
            self.search = search; self.fastSearch = fastSearch
        } else {
            self.search = { request in
                await SmartCubeReplacementPlanner.currentStateDecision(identity: request.identity,
                sourceFacelets: request.sourceFacelets, targetFacelets: request.targetFacelets,
                currentGeneration: request.generation, knownPath: request.knownPath,
                shortSearchAlreadyMissed: true)
            }
            self.fastSearch = fastSearch ?? { await SmartCubeReplacementPlanner.shortStateDecision($0) }
        }
    }

    func submit(_ request: Request) {
        if latest == request, isUpdating { return }
        ticket &+= 1
        let currentTicket = ticket
        latest = request
        settledTicket = nil
        publication = nil
        phase = .settling
        debounceTask?.cancel()
        worker?.cancel()
        fastWorker?.cancel(); fastWorker = nil
        trace("scheduled", request)
        if let fastSearch { startFast(request, search: fastSearch, ticket: currentTicket) }
        let settle = settle
        debounceTask = Task { [weak self] in
            do { try await settle() } catch { return }
            guard !Task.isCancelled, let self, ticket == currentTicket else { return }
            settledTicket = currentTicket
            debounceTask = nil
            drain()
        }
    }

    func cancel() {
        ticket &+= 1
        latest = nil
        settledTicket = nil
        debounceTask?.cancel()
        debounceTask = nil
        worker?.cancel()
        fastWorker?.cancel(); fastWorker = nil
        publication = nil
        phase = .idle
    }

    private func drain() {
        guard worker == nil, fastWorker == nil, settledTicket == ticket, let request = latest else { return }
        let currentTicket = ticket, search = search
        phase = .solving
        trace("started", request)
        worker = Task { [weak self] in
            let decision = await search(request)
            guard let self else { return }
            worker = nil
            if !Task.isCancelled, ticket == currentTicket, latest == request {
                latest = nil
                settledTicket = nil
                phase = decision.replacement == nil ? .unavailable : .idle
                trace(decision.replacement == nil ? "unavailable" : "published", request)
                publishIfImproved(decision, request: request)
            } else {
                trace("discarded-cancelled-or-obsolete-ticket", request)
                // The final physical turn may have settled while native code
                // was still running. Drain it here, without another BLE event.
                drain()
            }
        }
    }

    private func startFast(_ request: Request, search: @escaping Search, ticket currentTicket: UInt64) {
        fastWorker = Task { [weak self] in
            let decision = await search(request)
            guard !Task.isCancelled, let self, ticket == currentTicket, latest == request else { return }
            fastWorker = nil
            if decision.replacement != nil {
                latest = nil; settledTicket = nil; phase = .idle
                debounceTask?.cancel(); debounceTask = nil
                worker?.cancel()
                trace("fast-published", request)
                publishIfImproved(decision, request: request)
            } else { drain() }
        }
    }

    private func publishIfImproved(_ decision: SmartCubeReplacementDecision, request: Request) {
        #if DEBUG
        SmartCubeGuidanceTrace.record("candidate-arrived", identity: request.identity,
            source: request.sourceFacelets, target: request.targetFacelets,
            detail: "reason=\(decision.reason.rawValue) count=\(decision.candidateCost ?? -1) publicationDelayMS=\(decision.verifiedAt > 0 ? (ProcessInfo.processInfo.systemUptime - decision.verifiedAt) * 1000 : -1) shown=\(SmartCubeGuidanceTrace.path(request.knownPath)) candidate=\(SmartCubeGuidanceTrace.path(decision.replacement?.tokens))")
        #endif
        if request.keepsEqualPath, let known = decision.verifiedKnownCost,
           let candidate = decision.replacement,
           candidate.tokens.count >= (request.knownPath?.count ?? known) {
            // The verifier simplifies the known route before comparing search
            // results. That shorter route is not on screen until publication.
            trace("continuation-reused", request,
                detail: "known=\(known) shown=\(request.knownPath?.count ?? known) candidate=\(candidate.tokens.count) optimal=\(candidate.isProvenOptimal) origin=\(candidate.origin)")
            return
        }
        publication = Publication(request: request, decision: decision)
    }

    private func trace(_ event: String, _ request: Request, detail: String = "") {
        #if DEBUG
        SmartCubeGuidanceTrace.record(event, identity: request.identity, source: request.sourceFacelets, target: request.targetFacelets,
            detail: "version=\(request.identity.stateVersion) generation=\(request.generation) sequence=\(request.canonicalSequence) device=\(request.deviceID.map { String($0.uuidString.prefix(8)) } ?? "none") \(detail)")
        #endif
    }

    deinit { debounceTask?.cancel(); worker?.cancel(); fastWorker?.cancel() }
}
#endif

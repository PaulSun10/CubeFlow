import Foundation

nonisolated enum CompetitionDetailResource: String, CaseIterable, Sendable {
    case info, regulations, travel, schedule, registration, competitors, live, tickets

    var lifetime: TimeInterval {
        switch self {
        case .live: 15
        case .competitors, .tickets: 60
        default: 6 * 60 * 60
        }
    }
}

nonisolated enum CompetitionSectionLoadingPlan {
    static func initialResources(china: Bool, explicitLive: Bool, knownTickets: Bool = false) -> [CompetitionDetailResource] {
        // China exposes Competitors in both live and published Info navigation; it does
        // not depend on the About response. Tickets still require their explicit flag.
        let info: [CompetitionDetailResource] = china
            ? [.info, .regulations, .travel, .schedule, .registration, .competitors] : [.info, .schedule]
        // A direct Live destination is explicitly requested, even for a published archive.
        return info + (explicitLive ? [.live] : [])
            + (china && knownTickets ? [.tickets] : [])
    }

    static func historicalResources(china: Bool, publicationChecked: Bool, lifecycle: PublishedCompetitionLifecycle,
                                    hasRegistration: Bool, hasCompetitors: Bool) -> [CompetitionDetailResource] {
        // China retains these destinations inside published Info. International publication
        // replaces their primary destinations, so don't download invisible sections.
        guard china || (publicationChecked && lifecycle != .published) else { return [] }
        return (hasRegistration ? [.registration] : []) + (hasCompetitors ? [.competitors] : [])
    }
}

/// The detail destination owns one session, including publication and its gated scrambles.
/// Section stores retain their data, but cannot independently end this loading lifecycle.
nonisolated struct CompetitionLoadingLifecycle {
    enum Work: Hashable, Sendable {
        case detail(CompetitionDetailResource), publication, scrambles, psych(String)
    }
    private(set) var generation = 0
    private(set) var identity = ""
    private(set) var pending: Set<Work> = [.detail(.info)]
    private(set) var isRefresh = false

    var isLoading: Bool { !pending.isEmpty }
    var currentWork: Work? {
        if pending.contains(.detail(.info)) { return .detail(.info) }
        if pending.contains(.publication) { return .publication }
        if pending.contains(.scrambles) { return .scrambles }
        for resource in [CompetitionDetailResource.regulations, .schedule, .travel, .competitors, .registration, .tickets, .live] {
            if pending.contains(.detail(resource)) { return .detail(resource) }
        }
        return pending.compactMap { if case let .psych(key) = $0 { return key }; return nil }
            .sorted().first.map(Work.psych)
    }
    var detailResources: Set<CompetitionDetailResource> {
        Set(pending.compactMap { if case let .detail(resource) = $0 { return resource }; return nil })
    }

    mutating func begin(identity: String, resources: [CompetitionDetailResource], publication: Bool, refresh: Bool) -> Int {
        generation += 1
        self.identity = identity
        isRefresh = refresh
        pending = Set(resources.map(Work.detail))
        if publication { pending.insert(.publication) }
        return generation
    }

    func accepts(_ generation: Int, identity: String) -> Bool {
        self.generation == generation && self.identity == identity
    }

    mutating func schedule(_ work: Work) { pending.insert(work) }
    mutating func finish(_ work: Work) { pending.remove(work) }
    mutating func finishSession() { pending.removeAll() }
}

/// A resource is shared across section selection, not a full-detail variant with different flags.
/// A departing view releases its lease; only the last departing consumer cancels shared work.
actor CompetitionSectionStore {
    static let shared = CompetitionSectionStore()
    private struct Pending {
        let id: UUID
        let task: Task<CompetitionDetailContent, Never>
        var consumers: Set<UUID>
    }
    private var pending: [String: Pending] = [:]
    private var cached: [String: (Date, CompetitionDetailContent)] = [:]

    func content(key: String, lifetime: TimeInterval, refresh: Bool = false,
                 loader: @escaping @Sendable () async -> CompetitionDetailContent) async -> CompetitionDetailContent {
        guard !Task.isCancelled else { return .empty }
        if !refresh, let entry = cached[key], Date().timeIntervalSince(entry.0) < lifetime { return entry.1 }
        let consumer = UUID()
        if pending[key] == nil {
            pending[key] = Pending(id: UUID(), task: Task { await loader() }, consumers: [])
        }
        pending[key]!.consumers.insert(consumer)
        let work = pending[key]!
        return await withTaskCancellationHandler {
            let result = await work.task.value
            let cacheable = await MainActor.run { result != .empty }
            if !Task.isCancelled, pending[key]?.id == work.id {
                pending[key] = nil
                if cacheable {
                    cached[key] = (Date(), result)
                    if cached.count > 80, let oldest = cached.min(by: { $0.value.0 < $1.value.0 }) {
                        cached[oldest.key] = nil
                    }
                }
            }
            return Task.isCancelled ? .empty : result
        } onCancel: {
            Task { await self.release(key: key, workID: work.id, consumer: consumer) }
        }
    }

    private func release(key: String, workID: UUID, consumer: UUID) {
        guard pending[key]?.id == workID else { return }
        pending[key]?.consumers.remove(consumer)
        if pending[key]?.consumers.isEmpty == true {
            pending.removeValue(forKey: key)?.task.cancel()
        }
    }

    func clear() {
        pending.values.forEach { $0.task.cancel() }
        pending.removeAll(); cached.removeAll()
    }
}

extension CompetitionDetailContent {
    func merging(_ other: Self, resource: CompetitionDetailResource) -> Self {
        guard other != .empty else { return self }
        var content = self
        switch resource {
        case .info:
            content.overviewBlocks = other.overviewBlocks
            content.noteBlocks = other.noteBlocks
            content.wcaEvents = other.wcaEvents
            content.localizedName = other.localizedName
            content.championshipTitles = other.championshipTitles
            content.hasRegisterLink = other.hasRegisterLink
            content.hasCompetitorsLink = other.hasCompetitorsLink
            content.wcaCompetitionID = other.wcaCompetitionID
            content.showTickets = other.showTickets
            if content.liveURLOverride == nil { content.liveURLOverride = other.liveURLOverride }
        case .regulations: content.regulationBlocks = other.regulationBlocks
        case .travel:
            content.travelBlocks = other.travelBlocks
            content.travelMapLocations = other.travelMapLocations
        case .schedule:
            content.scheduleDays = other.scheduleDays
            content.scheduleEventSummaries = other.scheduleEventSummaries
            content.scheduleIntroHTML = other.scheduleIntroHTML
            content.scheduleCommentHTML = other.scheduleCommentHTML
            content.scheduleDebugInfo = other.scheduleDebugInfo
        case .registration:
            content.registerBlocks = other.registerBlocks
            content.registrationRequiresSignIn = other.registrationRequiresSignIn
        case .tickets: content.tickets = other.tickets
        case .competitors:
            content.competitorPreviews = other.competitorPreviews
            content.competitorsCount = other.competitorsCount
        case .live:
            content.liveAvailability = other.liveAvailability
            content.liveURLOverride = other.liveURLOverride
            content.liveContent = other.liveContent
            content.wcaLiveContent = other.wcaLiveContent
            content.cubingChinaLiveWebsite = other.cubingChinaLiveWebsite
        }
        return content
    }
}

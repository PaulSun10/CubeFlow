import Foundation
import Combine

/// Presentation evidence over the official dataset. The public profile cache
/// remains the sole owner of downloaded historical PB markers.
@MainActor final class PublishedCompetitionRecordEnrichment: ObservableObject {
    @Published private(set) var data: PublishedCompetitionData?
    @Published private(set) var updateID = 0
    @Published private(set) var showsSavedEvidence = false
    private let profiles: WCAPublicProfileCache
    private var source: PublishedCompetitionData?
    private var sourceID = UUID()
    private var publishID = UUID()
    private var flags: [String: [Int: PublishedRecordFlags]] = [:]
    private var savedPeople: Set<String> = []
    private var visiblePeople: Set<String> = []
    private var visibleCounts: [String: Int] = [:]
    private var pending: [String] = []
    private var attemptedAt: [String: Date] = [:]
    private var forcePeople: Set<String> = []
    private var tasks: [String: (UUID, Task<Void, Never>)] = [:]
    private var hasUnpublishedEvidence = false
    private let merge: @Sendable ([Int: PublishedRecordFlags], PublishedCompetitionData) async -> PublishedCompetitionData

    init(profiles: WCAPublicProfileCache = .shared,
         merge: @escaping @Sendable ([Int: PublishedRecordFlags], PublishedCompetitionData) async -> PublishedCompetitionData = { flags, data in
             await Task.detached(priority: .utility) { PublishedCompetitionPR.applying(flags, to: data) }.value
         }) {
        self.profiles = profiles; self.merge = merge
    }
    func current(for raw: PublishedCompetitionData) -> PublishedCompetitionData {
        source?.competitionID == raw.competitionID && source?.results == raw.results ? data ?? raw : raw
    }
    func configure(_ raw: PublishedCompetitionData) {
        guard source?.competitionID != raw.competitionID || source?.results != raw.results else { return }
        cancel(); sourceID = UUID(); publishID = UUID()
        source = raw; data = raw; flags = [:]; savedPeople = []; attemptedAt = [:]
        hasUnpublishedEvidence = false
        showsSavedEvidence = false
        visiblePeople = visiblePeople.intersection(Set(raw.people.map(\.id)))
        visibleCounts = visibleCounts.filter { visiblePeople.contains($0.key) }
        for id in visiblePeople { enqueue(id) }
    }
    func appeared(_ id: String?, source raw: PublishedCompetitionData) {
        configure(raw)
        guard let id = CompetitionPersonalIdentity.canonical(id), raw.people.contains(where: { $0.id == id }) else { return }
        visiblePeople.insert(id); visibleCounts[id, default: 0] += 1; enqueue(id)
    }
    func requested(_ id: String?, source raw: PublishedCompetitionData) {
        configure(raw)
        guard let id = CompetitionPersonalIdentity.canonical(id), raw.people.contains(where: { $0.id == id }) else { return }
        enqueue(id)
    }
    func disappeared(_ id: String?) {
        guard let id = CompetitionPersonalIdentity.canonical(id) else { return }
        let remaining = max(0, visibleCounts[id, default: 0] - 1)
        if remaining > 0 { visibleCounts[id] = remaining; return }
        visibleCounts[id] = nil; visiblePeople.remove(id); pending.removeAll { $0 == id }
    }
    func refreshVisible(including requestedID: String? = nil) {
        var people = visiblePeople
        if let id = CompetitionPersonalIdentity.canonical(requestedID), source?.people.contains(where: { $0.id == id }) == true {
            people.insert(id)
        }
        for id in people { attemptedAt[id] = nil; forcePeople.insert(id); enqueue(id) }
    }
    private func enqueue(_ id: String) {
        guard tasks[id] == nil, !pending.contains(id),
              attemptedAt[id].map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { return }
        pending.append(id)
        pump()
    }
    private func pump() {
        while tasks.count < 4, !pending.isEmpty {
            let id = pending.removeFirst(), job = UUID(), epoch = sourceID
            attemptedAt[id] = Date()
            let force = forcePeople.remove(id) != nil
            let task = Task { [weak self] in
                guard let self else { return }
                await load(id, epoch: epoch, force: force)
                guard tasks[id]?.0 == job else { return }
                tasks[id] = nil
                if forcePeople.contains(id) { attemptedAt[id] = nil; enqueue(id) }
                pump()
            }
            tasks[id] = (job, task)
        }
    }
    private func load(_ id: String, epoch: UUID, force: Bool) async {
        if let cached = await profiles.cachedPage(id, language: "en"), !Task.isCancelled, sourceID == epoch {
            await install(cached.page, id: id, epoch: epoch)
        }
        do {
            let page = try await profiles.page(id, language: "en", force: force)
            guard !Task.isCancelled, sourceID == epoch else { return }
            savedPeople.remove(id)
            showsSavedEvidence = !savedPeople.isEmpty
            await install(page, id: id, epoch: epoch)
        } catch {
            // Cache age/hits are not failures. Only an actual failed refresh
            // with usable saved evidence warrants the fallback notice.
            guard !Task.isCancelled, sourceID == epoch, !(error is CancellationError) else { return }
            if flags[id]?.values.contains(where: { $0.single || $0.average }) == true {
                savedPeople.insert(id)
                showsSavedEvidence = true
            }
        }
    }
    private func install(_ page: WCAPersonResultsPage, id: String, epoch: UUID) async {
        guard sourceID == epoch, let source,
              CompetitionPersonalIdentity.matches(signedInWCAID: id, competitorWCAID: page.summary.wcaId) else { return }
        let replacement = PublishedCompetitionPR.flags(page: page, data: source)
        if flags[id] != replacement { flags[id] = replacement; hasUnpublishedEvidence = true }
        // A cancelled/covered child can leave collected flags ahead of the last
        // published merge. Identical cached evidence must finish that publication.
        guard hasUnpublishedEvidence else { return }
        let combined = flags.values.reduce(into: [Int: PublishedRecordFlags]()) { $0.merge($1) { _, new in new } }
        let publication = UUID(); publishID = publication
        let enriched = await merge(combined, source)
        guard !Task.isCancelled, sourceID == epoch, publishID == publication else { return }
        hasUnpublishedEvidence = false
        if data?.results != enriched.results { data = enriched; updateID += 1 }
    }
    func cancel() {
        for id in Set(tasks.keys).union(pending) { attemptedAt[id] = nil }
        tasks.values.forEach { $0.1.cancel() }; tasks = [:]; pending = []; forcePeople = []
    }
}

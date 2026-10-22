import SwiftUI

struct CubingChinaUnifiedLiveContent<Actions: View>: View {
    @ObservedObject var session: CubingChinaModernLiveSession
    @ObservedObject var extras: CubingChinaLiveExtrasStore
    @ObservedObject var card: CompetitionResultCardState
    @Binding var roundSelection: String
    let language: String
    let loadCompetitor: (CompetitionWCALiveResultPreview) async -> CompetitionWCALiveCompetitorContent?
    var ownWCAID: String? = nil
    var openCompetitor: ((CubingChinaLiveResult.Competitor) -> Void)? = nil
    @ViewBuilder let actions: () -> Actions
    @State private var destination = "results"
    @State private var sumRankGender = "all"
    #if DEBUG
    @Environment(\.competitionLivePreviewDestination) private var previewDestination
    @State private var didPresentPreview = false
    #endif

    private var eventIDs: [String] { session.rounds.map(\.eventId).reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }
    private var eventID: String { session.rounds.first { $0.key.selectionID == roundSelection }?.eventId ?? session.selectedKey.eventID }
    private var eventBinding: Binding<String> {
        Binding(get: { eventID }, set: { event in
            if let round = session.rounds.filter({ $0.eventId == event }).max(by: { $0.roundNumber < $1.roundNumber }) {
                roundSelection = round.key.selectionID
            }
        })
    }
    private var destinations: [String] {
        ["results"] + (extras.podiums.isEmpty ? [] : ["podiums"])
            + (extras.records.isEmpty ? [] : ["records"]) + (extras.sums.isEmpty ? [] : ["sum_ranks"])
    }
    private var eventTags: [String: String] {
        let roundTags = session.roundRecordTags(in: extras, ownWCAID: ownWCAID)
        return Self.eventRecordTags(rounds: session.rounds, roundTags: roundTags)
    }
    static func eventRecordTags(rounds: [CubingChinaLiveRound], roundTags: [String: String]) -> [String: String] {
        let eventIDs = Set(rounds.map(\.eventId))
        return Dictionary(uniqueKeysWithValues: eventIDs.compactMap { event in
            CubingLiveRecordIndicators.highestDisplay(rounds.filter { $0.eventId == event }
                .map { roundTags[$0.key.selectionID] }).map { (event, $0) }
        })
    }
    private var evidenceKeys: [CubingChinaLiveRoundKey] {
        session.rounds.filter { round in
            if destination == "records" { return extras.records.contains { $0.belongs(to: round) } }
            if destination == "podiums" { return extras.podiums.contains { $0.key == round.key } }
            return false
        }.map(\.key)
    }
    private var evidenceRequestID: String {
        session.advancementEvidenceIdentity + "|" + destination + "|" + evidenceKeys.map(\.selectionID).joined(separator: ",")
    }
    private var personalCandidates: [CubingChinaLiveResult.Competitor] {
        extras.sums.map(\.competitor) + (session.snapshot?.results.compactMap(\.competitor) ?? [])
            + extras.records.compactMap(\.competitor) + extras.podiums.flatMap(\.results).compactMap(\.competitor)
    }
    private var personalRequestID: String {
        let association = CubingChinaPersonalRecords.association(ownWCAID: ownWCAID, candidates: personalCandidates)
        return "\(CompetitionPersonalIdentity.canonical(ownWCAID) ?? "guest")|\(association?.id.rawValue ?? 0)|\(association?.number ?? 0)|" + session.personalRecordRefreshIdentity
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                actions()
                CompetitionResultsNavigation(options: destinations, selection: $destination) {
                    PublishedCompetitionStrings.text("live." + $0, language)
                }.accessibilityIdentifier("competition-live-content-selector")
            }
            if destination == "results" {
                CompetitionResultsSelectorGroup {
                    PublishedEventSelector(eventIDs: eventIDs, selection: eventBinding,
                        effectiveEvent: eventID, language: language, recordTags: eventTags, cubingChinaLive: true)
                } rounds: {
                    PublishedRoundSelector(rounds: session.rounds.filter { $0.eventId == eventID }.map { value in
                        let final = session.rounds.filter { $0.eventId == eventID }.map(\.roundNumber).max()
                        return (value.key.selectionID, value.roundNumber == final ? "f" : String(value.roundNumber))
                    }, selection: $roundSelection, language: language, recordTags: session.roundRecordTags(in: extras, ownWCAID: ownWCAID))
                }
                selectedResults
            } else if destination == "records" {
                ForEach(session.rounds.filter { round in extras.records.contains { $0.belongs(to: round) } }) { round in
                    resultGroup(round: round, values: extras.records.filter { $0.belongs(to: round) }, category: nil)
                }
            } else if destination == "podiums" {
                ForEach(Array(extras.podiums.enumerated()), id: \.offset) { _, podium in
                    if let round = session.rounds.first(where: { $0.key == podium.key }) {
                        resultGroup(round: round, values: podium.results, category: categoryTitle(podium.group))
                    }
                }
            } else if destination == "sum_ranks" {
                CubingChinaSumRankTable(entries: extras.sums, language: language, ownWCAID: ownWCAID,
                    genderSelection: $sumRankGender, openCompetitor: openCompetitor)
            }
            Text(PublishedCompetitionStrings.text("live.provisional", language))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: destinations) { values in if !values.contains(destination) { destination = "results" } }
        .task(id: evidenceRequestID) { await session.loadAdvancementEvidence(for: evidenceKeys) }
        .task(id: personalRequestID) { await session.discoverPersonalRecords(ownWCAID: ownWCAID, candidates: personalCandidates) }
        #if DEBUG
        .onAppear { presentPreview() }
        .onChange(of: destinations) { _ in presentPreview() }
        #endif
    }
    #if DEBUG
    private func presentPreview() {
        guard !didPresentPreview, let previewDestination, destinations.contains(previewDestination) else { return }
        destination = previewDestination; didPresentPreview = true
    }
    #endif

    private var selectedResults: some View {
        VStack(spacing: 0) {
            if let value = session.snapshot, value.round.key == session.selectedKey {
                let current = session.hasCurrentSnapshot && session.resultError == nil
                    && session.rounds.first(where: { $0.id == value.round.id })?.revision == value.round.revision
                CubingChinaIntegratedResultsHeader(snapshot: value, rounds: session.rounds, language: language,
                    current: current, viewers: session.viewers, viewersObservedAt: session.viewersObservedAt)
                Divider()
                if !current {
                    Text(appLocalizedString("explore.cached", languageCode: language))
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
                }
                list(value)
            } else if session.isLoadingResults { ProgressView().padding(24) }
            else { Text(PublishedCompetitionStrings.text("live.results_unavailable", language)).foregroundStyle(.secondary).padding() }
            if session.resultError != nil || session.connectionError != nil {
                Button(PublishedCompetitionStrings.text("retry", language)) { session.retry() }.font(.subheadline).padding(10)
            }
        }
        .modifier(CompetitionResultsSurface())
    }

    private func list(_ snapshot: CubingChinaLiveSnapshot, isCompleteSnapshot: Bool = true) -> some View {
        Group {
            if snapshot.results.isEmpty {
                Text(PublishedCompetitionStrings.text("empty.results", language)).font(.subheadline).foregroundStyle(.secondary).padding()
            } else {
                CompetitionResultExperience(round: CubingChinaLivePresentation.round(snapshot, rounds: session.rounds, language: language,
                    nextParticipants: session.nextParticipants(for: snapshot.round),
                    advancementStates: isCompleteSnapshot ? nil : session.knownAdvancement),
                    languageCode: language, cardState: card, decoratesList: false, showsMyResultsShortcut: false,
                    allowsProviderResultsLoader: true, loadAllResults: loadCompetitor)
            }
        }
    }
    private func resultGroup(round: CubingChinaLiveRound, values: [CubingChinaLiveResult], category: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CubingChinaResultsHeading(round: round, rounds: session.rounds, language: language, category: category).padding(10)
            Divider()
            list(.init(round: round, results: values), isCompleteSnapshot: false)
        }.background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous)).modifier(CompetitionResultsDarkShadow())
    }
    private func categoryTitle(_ group: CubingChinaLivePodium.Group?) -> String? {
        guard let group else { return nil }
        if group.type == "age", let age = group.age {
            return String(format: PublishedCompetitionStrings.text(group.under == true ? "live.age_under" : "live.age_over", language), age)
        }
        return PublishedCompetitionStrings.text("live.category." + group.type, language)
    }

}

struct CubingChinaIntegratedResultsHeader: View {
    let snapshot: CubingChinaLiveSnapshot
    let rounds: [CubingChinaLiveRound]
    let language: String
    let current: Bool
    let viewers: Int
    let viewersObservedAt: Date?
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
            VStack(alignment: .leading, spacing: 6) {
                CubingChinaResultsHeading(round: snapshot.round, rounds: rounds, language: language)
                if current {
                    if dynamicType.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 6) { badges }
                    } else { HStack(spacing: 12) { badges } }
                }
                if let count = CubingChinaLiveHeaderMetadata.freshViewers(viewers, observedAt: viewersObservedAt, now: timeline.date) {
                    Label(String(format: PublishedCompetitionStrings.text("live.viewers", language), count), systemImage: "person.2")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if current, let date = CubingChinaLiveHeaderMetadata.updatedAt(snapshot, now: timeline.date) {
                    HStack(spacing: 4) {
                        Text(PublishedCompetitionStrings.text("live.last_updated", language))
                        Text(date, format: .dateTime.month(.abbreviated).day().hour().minute().locale(appLocale(for: language)))
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }
    }
    @ViewBuilder private var badges: some View {
        if ["open", "live", "finished"].contains(snapshot.round.status) {
            Text(PublishedCompetitionStrings.text("live.status." + snapshot.round.status, language))
                .modifier(CubingChinaHeaderBadge(tint: snapshot.round.status == "finished" ? .green : .blue))
        }
        if let counts = CubingChinaLiveHeaderMetadata.counts(snapshot) {
            Text("\(counts.recorded)/\(counts.expected)")
                .modifier(CubingChinaHeaderBadge(tint: .orange))
                .accessibilityLabel(String(format: PublishedCompetitionStrings.text("live.count", language), counts.recorded, counts.expected))
        }
    }
}

private struct CubingChinaHeaderBadge: ViewModifier {
    let tint: Color
    func body(content: Content) -> some View {
        content.font(.caption.weight(.medium)).foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(tint.opacity(0.10), in: Capsule()).allowsHitTesting(false)
    }
}

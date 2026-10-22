#if DEBUG
import SwiftUI
import Combine

/// Captured data changes no production detail/navigation/presentation composition.
struct CompetitionPublishedDetailAcceptanceSurface: View {
    private let summary: CompetitionSummary
    @StateObject private var store: PublishedCompetitionStore
    init() {
        let id = ProcessInfo.processInfo.environment["CUBEFLOW_ACCEPTANCE_COMPETITION_ID"] ?? "MariettaMondayMiniIV2026"
        let path = ProcessInfo.processInfo.environment["CUBEFLOW_ACCEPTANCE_PUBLISHED_JSON"] ?? ""
        let rows = (try? Data(contentsOf: URL(fileURLWithPath: path)))
            .flatMap { try? PublishedCompetitionService.decodeResults($0, competitionID: id) } ?? []
        let data = PublishedCompetitionData(competitionID: id, results: rows)
        _store = StateObject(wrappedValue: PublishedCompetitionStore(renderingData: data))
        summary = CompetitionSummary(id: id, name: id, shortDisplayName: nil, startDate: .distantPast, endDate: .distantPast,
            registrationOpen: nil, registrationClose: nil, competitorLimit: nil, venue: "Captured venue", venueAddress: "Captured address",
            venueDetails: nil, city: "Marietta", countryISO2: "US", latitude: nil, longitude: nil,
            url: "https://www.worldcubeassociation.org/competitions/\(id)", website: nil, dateRange: "2026",
            eventIDs: data.eventIDs, championshipTypes: nil, localizedRegionLineOverride: nil, localizedAddressLineOverride: nil,
            localizedStatusOverride: nil, localizedRegistrationStartOverride: nil, localizedWaitlistStartOverride: nil)
    }
    var body: some View {
        NavigationLink("Open captured competition") {
            CompetitionDetailView(competition: summary, appLanguage: "en", renderingContent: .empty,
                renderingPublishedStore: store, renderingTab: .results)
        }.navigationTitle("Competitions")
    }
}

/// Synthetic data exercises the real table Button and shared card without network scanning.
struct CompetitionResultsAcceptanceSurface: View {
    @StateObject private var card = CompetitionResultCardState()
    private let published: PublishedCompetitionData? = {
        guard let path = ProcessInfo.processInfo.environment["CUBEFLOW_ACCEPTANCE_PUBLISHED_JSON"],
              let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let id = ProcessInfo.processInfo.environment["CUBEFLOW_ACCEPTANCE_COMPETITION_ID"] ?? "BeijingAutumnRivalry2026"
        guard let rows = try? PublishedCompetitionService.decodeResults(bytes, competitionID: id) else { return nil }
        return PublishedCompetitionData(competitionID: id, results: rows)
    }()
    private let person = CubingChinaLiveResult.Competitor(id: .init(1), number: 1, name: "Acceptance Cuber",
        localName: nil, wcaId: nil, regionIso2: "GB")
    private var results: [CompetitionWCALiveCompetitorResult] {
        [CompetitionWCALiveCompetitorResult(id: "333-final", ranking: 1, isAdvancing: nil, isAdvancingQuestionable: nil,
            attempts: [652, 852, -1], best: 652, average: -1, singleRecordTag: "NR", averageRecordTag: nil,
            roundID: "333-final", roundName: "Final", roundNumber: 1, eventID: "333", eventName: "3x3x3 Cube",
            eventRank: 0, formatID: "a", numberOfAttempts: 5, sortBy: "average"),
         CompetitionWCALiveCompetitorResult(id: "222-final", ranking: 1, isAdvancing: nil, isAdvancingQuestionable: nil,
            attempts: [350], best: 350, average: 0, singleRecordTag: nil, averageRecordTag: nil,
            roundID: "222-final", roundName: "Final", roundNumber: 1, eventID: "222", eventName: "2x2x2 Cube",
            eventRank: 1, formatID: "1", numberOfAttempts: 1, sortBy: "best")]
    }
    private var content: CompetitionWCALiveCompetitorContent {
        .init(id: "ccc-user:1", name: person.name, wcaID: nil, countryISO2: "GB", results: results)
    }
    private var round: CompetitionWCALiveRound {
        .init(id: "333-final", eventID: "333", eventName: "3x3x3 Cube", roundName: "Final", number: 1,
            formatID: "a", numberOfAttempts: 5, sortBy: "average", isFinished: true, advancementType: nil,
            advancementLevel: nil, isActive: false, isOpen: false, results: [])
    }
    var body: some View {
        ScrollView {
            if let published {
                PublishedCompetitionResultsContent(data: published, language: "en", resultCard: card).padding(16)
            } else {
            VStack(spacing: 16) {
                CubingChinaSumRankTable(entries: [.init(competitor: person, sum: 2, count: 2,
                    ranks: ["333": 1, "222": 1], enteredEventIds: ["333", "222"], gender: "male")],
                    language: "en", openCompetitor: { selected in
                        card.presentCompetition(id: "ccc-user:\(selected.id.rawValue)", name: selected.name, content: content)
                    })
                Button("Round-origin All Results") {
                    let preview = CompetitionWCALiveResultPreview(id: "result", ranking: 1, personID: "1",
                        personWCAID: nil, name: person.name, region: "United Kingdom", attempts: [652, 852, -1],
                        best: 652, average: -1, isAdvancing: nil, isAdvancingQuestionable: nil,
                        singleRecordTag: "NR", averageRecordTag: nil)
                    card.present(result: preview, round: round, loader: { _ in content })
                    card.loadAllResults()
                }.accessibilityIdentifier("competition-acceptance-round")
            }.padding(16)
            }
        }.navigationTitle("Results Acceptance")
            .competitionResultsPresentation(state: card, language: "en")
    }
}
#endif

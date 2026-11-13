#if os(iOS)
import SwiftUI
import MapKit

func exploreHomeString(_ key: String, language: String) -> String {
    appLocalizedString("explore.\(key)", languageCode: language, tableName: "ExploreHome")
}

nonisolated struct ExploreCompetitionRecommendation: Identifiable {
    enum Reason: Equatable { case championship, worldRecord, eventProgram(Int) }
    let competition: CompetitionSummary
    let reason: Reason
    let events: Set<String>
    var id: String { competition.id }

    static func ranked(_ competitions: [CompetitionSummary], worldRecordIDs: Set<String>,
                       now: Date, limit: Int = 6) -> [Self] {
        guard limit > 0 else { return [] }
        let candidates: [(Self, Int)] = competitions.compactMap { competition in
            let events = Set(competition.eventIDs.filter { !$0.isEmpty })
            let types = competition.championshipTypes ?? []
            let id = competition.wcaCompetitionID ?? competition.id
            if competition.endDate >= now,
               competition.startDate <= now.addingTimeInterval(120 * 86_400) {
                if types.contains("world") { return (.init(competition: competition, reason: .championship, events: events), 5) }
                if types.contains(where: { $0.hasPrefix("_") || $0 == "greater_china" }) {
                    return (.init(competition: competition, reason: .championship, events: events), 4)
                }
                if types.contains(where: { $0.count == 2 }) {
                    return (.init(competition: competition, reason: .championship, events: events), 3)
                }
                if events.count >= 8 {
                    return (.init(competition: competition, reason: .eventProgram(events.count), events: events), 1)
                }
            } else if competition.endDate < now,
                      competition.endDate >= now.addingTimeInterval(-30 * 86_400),
                      worldRecordIDs.contains(id.lowercased()) {
                return (.init(competition: competition, reason: .worldRecord, events: events), 2)
            }
            return nil
        }
        var remaining = candidates.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            if a.0.events.count != b.0.events.count { return a.0.events.count > b.0.events.count }
            if a.0.competition.startDate != b.0.competition.startDate {
                return a.0.competition.startDate < b.0.competition.startDate
            }
            return a.0.id < b.0.id
        }
        var usedIDs: Set<String> = [], regions: Set<String> = [], events: Set<String> = []
        var results: [Self] = []
        while !remaining.isEmpty, results.count < limit {
            // Keep the strongest pick first; prefer unrepresented locations and
            // event programs for the rest, without reaching beyond this cache.
            let index = results.isEmpty ? 0
                : remaining.firstIndex { !regions.contains($0.0.competition.countryISO2) && !$0.0.events.isSubset(of: events) }
                ?? remaining.firstIndex { !regions.contains($0.0.competition.countryISO2) }
                ?? remaining.firstIndex { !$0.0.events.isSubset(of: events) } ?? 0
            let candidate = remaining.remove(at: index).0
            let id = (candidate.competition.wcaCompetitionID ?? candidate.id).lowercased()
            guard usedIDs.insert(id).inserted else { continue }
            regions.insert(candidate.competition.countryISO2)
            events.formUnion(candidate.events)
            results.append(candidate)
        }
        return results
    }
}

struct ExploreCachedDiscoveries: View {
    @ObservedObject var store: ExploreStore
    let language: String

    var body: some View {
        let records = Set(store.recentRecords.filter { $0.tag.uppercased() == "WR" }
            .map { $0.result.round.competitionEvent.competition.wcaId.lowercased() })
        ExploreDiscoveriesView(language: language,
            recommendations: ExploreCompetitionRecommendation.ranked(store.competitions, worldRecordIDs: records, now: Date()))
    }
}

struct ExploreDiscoveriesView: View {
    let language: String
    let history: ExploreHistory? = .bundled
    var recommendations: [ExploreCompetitionRecommendation] = []
    var body: some View {
        List {
            if !recommendations.isEmpty {
                Section {
                    ForEach(recommendations) { item in
                        NavigationLink {
                            ExploreCompetitionLookupDestination(competitionID: item.competition.wcaCompetitionID ?? item.id,
                                roundID: nil, language: language)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.competition.name).font(.headline)
                                Text(reason(item.reason)).font(.subheadline)
                                Text([item.competition.locationLine, item.competition.dateRange]
                                    .filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                    }
                } header: { ExploreHeading(title: exploreHomeString("noteworthy_competitions", language: language)).textCase(nil) }
            }
            if let history {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                    Text(exploreHomeString("discoveries_intro", language: language))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(String(format: exploreHomeString("history_as_of", language: language), history.exportDate))
                        .font(.footnote).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                places(history.northernmost, title: "northernmost")
                places(history.southernmost, title: "southernmost")
                places(history.earliest, title: "first_competition")
                Section {
                    DisclosureGroup(String(format: exploreHomeString("events_tied", language: language),
                        history.eventRich.first?.events.count ?? 0, history.eventRich.count)) {
                        ForEach(history.eventRich) { place in
                            NavigationLink {
                                ExploreCompetitionLookupDestination(competitionID: place.id, roundID: nil, language: language)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(place.name).font(.headline)
                                    Text(place.start).font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                } header: { ExploreHeading(title: exploreHomeString("most_events", language: language)).textCase(nil) }
                ExploreHistorySource(history: history, language: language)
            } else { Text("explore.unavailable").foregroundStyle(.secondary) }
        }
        .modifier(ExploreListStyle())
        .navigationTitle(Text(exploreHomeString("discover", language: language)))
    }

    private func reason(_ reason: ExploreCompetitionRecommendation.Reason) -> String {
        switch reason {
        case .championship: return exploreHomeString("reason_championship", language: language)
        case .worldRecord: return exploreHomeString("reason_world_record", language: language)
        case .eventProgram(let count):
            return String(format: exploreHomeString("reason_event_count", language: language), count)
        }
    }

    private func places(_ values: [ExploreHistory.Place], title: String) -> some View {
        Section {
            ForEach(values) { place in
                NavigationLink {
                    ExploreCompetitionLookupDestination(competitionID: place.id, roundID: nil, language: language)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        if let latitude = place.latitude, let longitude = place.longitude {
                            ExplorePlaceMap(latitude: latitude, longitude: longitude)
                                .frame(height: 132).clipShape(RoundedRectangle(cornerRadius: 12))
                                .accessibilityHidden(true)
                            Text(latitude.formatted(.number.precision(.fractionLength(2))) + "° " +
                                 longitude.formatted(.number.precision(.fractionLength(2))) + "°")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text(place.name).font(.headline)
                        Text(place.city + " · " + (CompetitionService.localizedRegionName(for: place.country,
                            languageCode: language) ?? place.country)).font(.subheadline).foregroundStyle(.secondary)
                        Text(place.start).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }
            }
        } header: { ExploreHeading(title: exploreHomeString(title, language: language)).textCase(nil) }
    }
}

struct ExplorePlaceMap: View {
    struct Point: Identifiable { let id = 0; let coordinate: CLLocationCoordinate2D }
    let latitude: Double
    let longitude: Double
    var body: some View {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        Map(coordinateRegion: .constant(MKCoordinateRegion(center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 24))),
            interactionModes: [], annotationItems: [Point(coordinate: coordinate)]) {
                MapMarker(coordinate: $0.coordinate)
            }
    }
}

struct ExploreStatsView: View {
    let language: String
    let history: ExploreHistory? = .bundled
    var body: some View {
        List {
            if let history {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(history.completedCount.formatted()).font(.title.weight(.semibold)).monospacedDigit()
                        Text(exploreHomeString("competitions_held", language: language)).font(.headline)
                        Text(String(format: exploreHomeString("countries_reached", language: language), history.countries.count))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(String(format: exploreHomeString("history_as_of", language: language), history.exportDate))
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Section {
                    ForEach(history.years.prefix(10)) { value in countRow(value.id, value.count) }
                    DisclosureGroup(exploreHomeString("earlier_years", language: language)) {
                        ForEach(history.years.dropFirst(10)) { value in countRow(value.id, value.count) }
                    }
                } header: { ExploreHeading(title: exploreHomeString("by_year", language: language)).textCase(nil) }
                Section {
                    ForEach(history.countries.prefix(10)) { value in
                        countRow(CompetitionService.localizedRegionName(for: value.id, languageCode: language) ?? value.id,
                            value.count)
                    }
                } header: { ExploreHeading(title: exploreHomeString("by_country", language: language)).textCase(nil) }
                Section {
                    ForEach(history.events) { value in
                        countRow(CompetitionEventPresentation.localizedFullName(for: value.id, languageCode: language,
                            fallback: value.id), value.count)
                    }
                } header: { ExploreHeading(title: exploreHomeString("by_event", language: language)).textCase(nil) }
                ExploreHistorySource(history: history, language: language)
            } else { Text("explore.unavailable").foregroundStyle(.secondary) }
        }
        .modifier(ExploreListStyle())
        .navigationTitle("explore.stats")
    }
    private func countRow(_ title: String, _ count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 12)
            Text(count.formatted()).monospacedDigit().foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}

private struct ExploreHistorySource: View {
    let history: ExploreHistory
    let language: String
    var body: some View {
        Section {
            Text(String(format: exploreHomeString("history_scope", language: language), history.exportDate))
                .font(.footnote).foregroundStyle(.secondary)
            Text(String(format: exploreHomeString("coordinate_scope", language: language), history.locatedCount, history.completedCount))
                .font(.footnote).foregroundStyle(.secondary)
            Link(exploreHomeString("history_source", language: language), destination: URL(string: history.sourceURL)!)
            Link("WCA", destination: URL(string: "https://www.worldcubeassociation.org/export/results")!)
        }
    }
}
#endif

#if os(iOS)
import SwiftUI
import MapKit

func exploreHomeString(_ key: String, language: String) -> String {
    appLocalizedString("explore.\(key)", languageCode: language, tableName: "ExploreHome")
}

struct ExploreDiscoveriesView: View {
    let language: String
    let history: ExploreHistory? = .bundled
    var body: some View {
        List {
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

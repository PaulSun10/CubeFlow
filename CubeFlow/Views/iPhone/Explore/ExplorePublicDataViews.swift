#if os(iOS)
import SwiftUI
import Combine

@MainActor
private final class ExploreRankingsViewModel: ObservableObject {
    @Published private(set) var rows: [WCAPublicResult] = []
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var statusCode: Int?
    private var currentRequest = UUID()
    private var currentKey = ""

    func load(_ query: WCARankingsQuery, force: Bool = false) async {
        let key = "rankings-v1-\(query.eventID)-\(query.type.rawValue)-\(query.region.id)-\(query.gender.rawValue)-\(query.show.rawValue)"
        if currentKey != key {
            currentKey = key
            rows = []
            fetchedAt = nil
            failed = false
            statusCode = nil
        }
        if !force, let fetchedAt, Date().timeIntervalSince(fetchedAt) < 15 * 60 { return }
        let requestID = UUID()
        currentRequest = requestID
        defer { if currentRequest == requestID { isLoading = false } }
        isLoading = rows.isEmpty
        if rows.isEmpty, let cached = await WCAExplorePublicDataCache.shared.load(WCARankingsResponse.self, key: key) {
            guard currentKey == key, currentRequest == requestID else { return }
            rows = cached.value.rankings
            fetchedAt = cached.fetchedAt
            isLoading = false
        }
        do {
            let response = try await WCAExplorePublicDataService.fetchRankings(query)
            try Task.checkCancellation()
            guard currentKey == key, currentRequest == requestID else { return }
            rows = response.rankings
            fetchedAt = Date()
            failed = false
            statusCode = nil
            if let fetchedAt { await WCAExplorePublicDataCache.shared.save(response, key: key, now: fetchedAt) }
        } catch is CancellationError {
            return
        } catch {
            guard currentKey == key, currentRequest == requestID else { return }
            failed = true
            if case WCAExplorePublicDataError.httpStatus(let code) = error { statusCode = code }
            else { statusCode = nil }
        }
    }
}

@MainActor
private final class ExploreRecordsViewModel: ObservableObject {
    @Published private(set) var records: [String: [WCAPublicResult]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var statusCode: Int?
    private var currentRequest = UUID()
    private var currentKey = ""

    func load(_ query: WCARecordsQuery, force: Bool = false) async {
        let key = "records-v1-\(query.region.id)-\(query.gender.rawValue)-\(query.show.rawValue)"
        if currentKey != key {
            currentKey = key
            records = [:]
            fetchedAt = nil
            failed = false
            statusCode = nil
        }
        if !force, let fetchedAt, Date().timeIntervalSince(fetchedAt) < 15 * 60 { return }
        let requestID = UUID()
        currentRequest = requestID
        defer { if currentRequest == requestID { isLoading = false } }
        isLoading = records.isEmpty
        if records.isEmpty, let cached = await WCAExplorePublicDataCache.shared.load(WCARecordsResponse.self, key: key) {
            guard currentKey == key, currentRequest == requestID else { return }
            records = cached.value.records
            fetchedAt = cached.fetchedAt
            isLoading = false
        }
        do {
            let response = try await WCAExplorePublicDataService.fetchRecords(query)
            try Task.checkCancellation()
            guard currentKey == key, currentRequest == requestID else { return }
            records = response.records
            fetchedAt = Date()
            failed = false
            statusCode = nil
            if let fetchedAt { await WCAExplorePublicDataCache.shared.save(response, key: key, now: fetchedAt) }
        } catch is CancellationError {
            return
        } catch {
            guard currentKey == key, currentRequest == requestID else { return }
            failed = true
            if case WCAExplorePublicDataError.httpStatus(let code) = error { statusCode = code }
            else { statusCode = nil }
        }
    }
}

struct ExploreRankingsView: View {
    let language: String
    @StateObject private var model = ExploreRankingsViewModel()
    @State private var event: CompetitionEventFilter = .threeByThree
    @State private var type: WCAResultType = .single
    @State private var region: CompetitionRegionFilter = .all
    @State private var gender: WCAPublicGender = .all
    @State private var show: WCARankingsShow = .persons
    @State private var countries: [CompetitionRecognizedCountry] = []
    @State private var showsRegionPicker = false

    private var query: WCARankingsQuery {
        WCARankingsQuery(eventID: event.wcaEventID, type: type, region: region, gender: gender, show: show)
    }

    private var loadID: String {
        "\(event.id)|\(type.id)|\(region.id)|\(gender.id)|\(show.id)"
    }

    var body: some View {
        List {
            filters
            status
            if show == .byRegion {
                let groups = WCAExplorePublicDataService.regionalBests(
                    from: model.rows,
                    selectedRegion: region,
                    countries: countries
                )
                ForEach(groups) { group in
                    Section(scopeTitle(group.scope)) {
                        ForEach(Array(group.results.enumerated()), id: \.offset) { _, result in
                            ExplorePublicResultRow(result: result, rank: nil, language: language)
                        }
                    }
                }
            } else {
                Section {
                    ForEach(Array(WCAExplorePublicDataService.rankedRows(model.rows).enumerated()), id: \.offset) { _, ranked in
                        ExplorePublicResultRow(result: ranked.result, rank: ranked.rank, language: language)
                    }
                }
            }
        }
        .modifier(ExploreListStyle())
        .navigationTitle(Text(explorePublicString("rankings", defaultValue: "Rankings", language: language)))
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await model.load(query, force: true) }
        .task(id: loadID) {
            async let loadRows: Void = model.load(query)
            async let loadCountries: Void = loadCountriesIfNeeded()
            _ = await (loadRows, loadCountries)
        }
        .sheet(isPresented: $showsRegionPicker) {
            CompetitionRegionPickerView(selectedRegion: $region, appLanguage: language)
        }
    }

    private var officialURL: URL {
        let source = WCAExplorePublicDataService.rankingsURL(query)!
        var components = URLComponents(url: source, resolvingAgainstBaseURL: false)!
        components.path = components.path.replacingOccurrences(of: "/api/v0", with: "")
        return components.url!
    }

    private var filters: some View {
        Section {
            ExplorePublicMenuRow(title: explorePublicString("event", defaultValue: "Event", language: language),
                                 selection: event.localizedTitle(languageCode: language)) {
                ForEach(CompetitionEventFilter.selectableCases) { option in
                    Button { event = option } label: {
                        ExplorePublicOptionLabel(title: option.localizedTitle(languageCode: language), selected: event == option)
                    }
                }
            }
            Picker(explorePublicString("type", defaultValue: "Type", language: language), selection: $type) {
                ForEach(WCAResultType.allCases) { option in Text(resultTypeTitle(option)).tag(option) }
            }
            .pickerStyle(.segmented)
            DisclosureGroup(exploreHomeString("filters", language: language)) {
            ExplorePublicMenuRow(title: explorePublicString("show", defaultValue: "Show", language: language),
                                 selection: rankingsShowTitle(show)) {
                ForEach(WCARankingsShow.allCases) { option in
                    Button { show = option } label: {
                        ExplorePublicOptionLabel(title: rankingsShowTitle(option), selected: show == option)
                    }
                }
            }
            ExplorePublicMenuRow(title: explorePublicString("gender", defaultValue: "Gender", language: language),
                                 selection: genderTitle(gender)) {
                ForEach(WCAPublicGender.allCases) { option in
                    Button { gender = option } label: {
                        ExplorePublicOptionLabel(title: genderTitle(option), selected: gender == option)
                    }
                }
            }
            Button { showsRegionPicker = true } label: {
                ExplorePublicSelectionRow(
                    title: explorePublicString("region", defaultValue: "Region", language: language),
                    selection: region.localizedTitle(languageCode: language)
                )
            }
            .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var status: some View {
        if model.isLoading {
            Section { ProgressView(explorePublicString("loading", defaultValue: "Loading...", language: language)) }
        } else if model.failed && model.rows.isEmpty {
            ExplorePublicErrorSection(language: language, statusCode: model.statusCode, officialURL: officialURL) { Task { await model.load(query, force: true) } }
        } else if model.failed {
            ExplorePublicSavedDataSection(date: model.fetchedAt, language: language)
            Button(explorePublicString("retry", defaultValue: "Retry", language: language)) {
                Task { await model.load(query, force: true) }
            }
        } else if model.rows.isEmpty {
            Section { Text(explorePublicString("empty", defaultValue: "No results found.", language: language)).foregroundStyle(.secondary) }
        }
    }

    private func scopeTitle(_ scope: WCARegionalBest.Scope) -> String {
        switch scope {
        case .world: return explorePublicString("world", defaultValue: "World", language: language)
        case .continent(let continent): return continent.localizedTitle(languageCode: language)
        case .country(_, let name): return name
        }
    }

    private func loadCountriesIfNeeded() async {
        guard countries.isEmpty else { return }
        countries = (try? await CompetitionService.fetchRecognizedCountries()) ?? []
    }

    private func resultTypeTitle(_ value: WCAResultType) -> String {
        explorePublicString(value.rawValue, defaultValue: value == .single ? "Single" : "Average", language: language)
    }

    private func genderTitle(_ value: WCAPublicGender) -> String {
        explorePublicString("gender_\(value.rawValue.lowercased())", defaultValue: value.rawValue, language: language)
    }

    private func rankingsShowTitle(_ value: WCARankingsShow) -> String {
        let fallback: String
        switch value {
        case .persons: fallback = "100 Persons"
        case .results: fallback = "100 Results"
        case .byRegion: fallback = "By Region"
        }
        return explorePublicString("rankings_\(value.id.replacingOccurrences(of: " ", with: "_"))", defaultValue: fallback, language: language)
    }
}

struct ExploreRecordsView: View {
    let language: String
    @StateObject private var model = ExploreRecordsViewModel()
    @State private var event: CompetitionEventFilter = .all
    @State private var region: CompetitionRegionFilter = .all
    @State private var gender: WCAPublicGender = .all
    @State private var show: WCARecordsShow = .mixed
    @State private var showsRegionPicker = false

    private var query: WCARecordsQuery { WCARecordsQuery(region: region, gender: gender, show: show) }
    private var loadID: String { "\(region.id)|\(gender.id)|\(show.id)" }
    private var sections: [WCARecordSection] {
        WCAExplorePublicDataService.recordSections(
            model.records,
            show: show,
            eventID: event == .all ? nil : event.wcaEventID
        )
    }

    var body: some View {
        List {
            filters
            status
            ForEach(sections) { section in
                Section(sectionTitle(section.kind)) {
                    if show == .slim, case .event = section.kind {
                        ExploreSlimRecordRows(rows: section.rows, language: language)
                    } else {
                        ForEach(Array(section.rows.enumerated()), id: \.offset) { _, result in
                            ExplorePublicResultRow(result: result, rank: nil, language: language, showsType: true)
                        }
                    }
                }
            }
        }
        .modifier(ExploreListStyle())
        .navigationTitle(Text(explorePublicString("records", defaultValue: "Records", language: language)))
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await model.load(query, force: true) }
        .task(id: loadID) { await model.load(query) }
        .sheet(isPresented: $showsRegionPicker) {
            CompetitionRegionPickerView(selectedRegion: $region, appLanguage: language)
        }
    }

    private var officialURL: URL {
        WCAExplorePublicDataService.recordsWebsiteURL(query, eventID: event == .all ? nil : event.wcaEventID)!
    }

    private var filters: some View {
        Section {
            ExplorePublicMenuRow(title: explorePublicString("event", defaultValue: "Event", language: language),
                                 selection: event.localizedTitle(languageCode: language)) {
                ForEach(CompetitionEventFilter.allCases) { option in
                    Button { event = option } label: {
                        ExplorePublicOptionLabel(title: option.localizedTitle(languageCode: language), selected: event == option)
                    }
                }
            }
            DisclosureGroup(exploreHomeString("filters", language: language)) {
            ExplorePublicMenuRow(title: explorePublicString("show", defaultValue: "Show", language: language),
                                 selection: recordsShowTitle(show)) {
                ForEach(WCARecordsShow.allCases) { option in
                    Button { show = option } label: {
                        ExplorePublicOptionLabel(title: recordsShowTitle(option), selected: show == option)
                    }
                }
            }
            ExplorePublicMenuRow(title: explorePublicString("gender", defaultValue: "Gender", language: language),
                                 selection: genderTitle(gender)) {
                ForEach(WCAPublicGender.allCases) { option in
                    Button { gender = option } label: {
                        ExplorePublicOptionLabel(title: genderTitle(option), selected: gender == option)
                    }
                }
            }
            Button { showsRegionPicker = true } label: {
                ExplorePublicSelectionRow(
                    title: explorePublicString("region", defaultValue: "Region", language: language),
                    selection: region.localizedTitle(languageCode: language)
                )
            }
            .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var status: some View {
        if model.isLoading {
            Section { ProgressView(explorePublicString("loading", defaultValue: "Loading...", language: language)) }
        } else if model.failed && model.records.isEmpty {
            ExplorePublicErrorSection(language: language, statusCode: model.statusCode, officialURL: officialURL) { Task { await model.load(query, force: true) } }
        } else if model.failed {
            ExplorePublicSavedDataSection(date: model.fetchedAt, language: language)
            Button(explorePublicString("retry", defaultValue: "Retry", language: language)) {
                Task { await model.load(query, force: true) }
            }
        } else if sections.isEmpty {
            Section { Text(explorePublicString("empty", defaultValue: "No results found.", language: language)).foregroundStyle(.secondary) }
        }
    }

    private func sectionTitle(_ kind: WCARecordSection.Kind) -> String {
        switch kind {
        case .event(let id):
            return CompetitionEventFilter.selectableCases.first(where: { $0.wcaEventID == id })?.localizedTitle(languageCode: language) ?? id
        case .type(let type):
            return explorePublicString(type.rawValue, defaultValue: type == .single ? "Single" : "Average", language: language)
        case .mixedHistory:
            return explorePublicString("mixed_history", defaultValue: "Mixed History", language: language)
        }
    }

    private func genderTitle(_ value: WCAPublicGender) -> String {
        explorePublicString("gender_\(value.rawValue.lowercased())", defaultValue: value.rawValue, language: language)
    }

    private func recordsShowTitle(_ value: WCARecordsShow) -> String {
        let fallback: String
        switch value {
        case .mixed: fallback = "Mixed"
        case .slim: fallback = "Slim"
        case .separate: fallback = "Separate"
        case .history: fallback = "History"
        case .mixedHistory: fallback = "Mixed History"
        }
        return explorePublicString("records_\(value.id.replacingOccurrences(of: " ", with: "_"))", defaultValue: fallback, language: language)
    }
}

private struct ExplorePublicResultRow: View {
    let result: WCAPublicResult
    let rank: Int?
    let language: String
    var showsType = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                WCAProfileView(wcaID: result.personId, displayName: result.personName)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if let rank {
                        Text("\(rank)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 28, alignment: .trailing)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.personName).font(.headline)
                        Text(result.countryId).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(WCAExplorePublicDataService.formatResult(result.value, eventID: result.eventId))
                            .font(.headline.monospacedDigit())
                        if showsType {
                            let tag = result.type == "average" ? result.regionalAverageRecord : result.regionalSingleRecord
                            if let tag, !tag.isEmpty { CompetitionWCARecordTagView(tag: tag, variant: .standard) }
                        }
                        if showsType, let type = result.type {
                            Text(explorePublicString(type, defaultValue: type.capitalized, language: language))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            NavigationLink {
                ExploreCompetitionLookupDestination(competitionID: result.competitionId, roundID: nil, language: language)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                    Text(result.competitionName)
                    Text(result.startDate)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }
}

private struct ExploreSlimRecordRows: View {
    let rows: [WCAPublicResult]
    let language: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(WCAResultType.allCases) { type in
                let matches = rows.filter { $0.type == type.rawValue }
                if !matches.isEmpty {
                    Text(explorePublicString(type.rawValue, defaultValue: type.rawValue.capitalized, language: language))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Array(matches.enumerated()), id: \.offset) { _, result in
                        ExplorePublicResultRow(result: result, rank: nil, language: language)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }
}

struct ExploreCompetitionLookupDestination: View {
    let competitionID: String
    let resultDeepLink: CompetitionWCALiveResultDeepLink?
    let language: String
    @State private var competition: CompetitionSummary?
    @State private var isLoading = true
    @State private var failed = false
    @State private var requestID = 0

    init(competitionID: String, roundID: String?, language: String) {
        self.competitionID = competitionID
        resultDeepLink = roundID.map {
            CompetitionWCALiveResultDeepLink(roundID: $0, personID: nil, personWCAID: nil)
        }
        self.language = language
    }

    init(
        competitionID: String,
        resultDeepLink: CompetitionWCALiveResultDeepLink,
        language: String
    ) {
        self.competitionID = competitionID
        self.resultDeepLink = resultDeepLink
        self.language = language
    }

    var body: some View {
        Group {
            if let competition {
                CompetitionDetailView(
                    competition: competition,
                    appLanguage: language,
                    initialWCALiveRoundID: resultDeepLink?.roundID,
                    initialWCALiveResultDeepLink: resultDeepLink
                )
            } else if isLoading {
                ProgressView(explorePublicString("loading_competition", defaultValue: "Loading competition...", language: language))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Text(explorePublicString("unavailable", defaultValue: "Unable to load this WCA result.", language: language))
                        .multilineTextAlignment(.center)
                    Button(explorePublicString("retry", defaultValue: "Retry", language: language)) { requestID += 1 }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .task(id: requestID) { await load() }
        .accessibilityIdentifier(resultDeepLink.map { "wca-round-\($0.roundID)" } ?? "wca-competition")
    }

    private func load() async {
        isLoading = true
        failed = false
        do {
            competition = try await CompetitionService.fetchCompetitionSummary(id: competitionID, languageCode: language)
        } catch is CancellationError {
            return
        } catch {
            failed = true
        }
        isLoading = false
    }
}

private struct ExplorePublicMenuRow<Content: View>: View {
    let title: String
    let selection: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) {
            ExplorePublicSelectionRow(title: title, selection: selection)
        }
        .buttonStyle(.plain)
    }
}

private struct ExplorePublicSelectionRow: View {
    let title: String
    let selection: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(Color.primary)
            Spacer(minLength: 8)
            Text(selection).foregroundStyle(Color(uiColor: .secondaryLabel)).multilineTextAlignment(.trailing)
            ExploreChevron()
        }
        .contentShape(Rectangle())
    }
}

private struct ExplorePublicOptionLabel: View {
    let title: String
    let selected: Bool

    var body: some View {
        HStack {
            Text(title)
            if selected { Image(systemName: "checkmark") }
        }
    }
}

private struct ExplorePublicErrorSection: View {
    let language: String
    let statusCode: Int?
    let officialURL: URL
    let retry: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(explorePublicString("unavailable", defaultValue: "WCA data is unavailable right now.", language: language))
                    .font(.headline)
                if statusCode == 403 {
                    Text(exploreHomeString("source_refused", language: language)).font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 8)
            Button(explorePublicString("retry", defaultValue: "Retry", language: language), action: retry)
            Link(exploreHomeString("open_wca", language: language), destination: officialURL)
        }
    }
}

private struct ExplorePublicSavedDataSection: View {
    let date: Date?
    let language: String

    var body: some View {
        Section {
            HStack(spacing: 4) {
                Text(explorePublicString("saved_data", defaultValue: "Showing saved data from", language: language))
                if let date { Text(date, style: .date) }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

private func explorePublicString(_ suffix: String, defaultValue: String, language: String) -> String {
    appLocalizedString("explore.public.\(suffix)", languageCode: language,
                       defaultValue: defaultValue, tableName: "ExplorePublicData")
}
#endif

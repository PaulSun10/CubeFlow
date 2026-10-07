#if os(iOS)
import SwiftUI

struct ExploreModuleView: View {
    private enum Route: Hashable { case item(ExploreItem), all }
    let module: ExploreModule
    @ObservedObject var store: ExploreStore
    let language: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var resultSize = 34
    @State private var route: Route?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if module.presentation != .hero {
                HStack(alignment: .firstTextBaseline) {
                    ExploreHeading(title: appLocalizedString(module.titleKey, languageCode: language, tableName: module.titleTable))
                    Spacer(minLength: 8)
                    if module.seeAll != nil {
                        Button { route = .all } label: {
                            ExploreChevron().frame(minWidth: 44, minHeight: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("explore-see-all-\(module.id)")
                        .accessibilityLabel(Text("explore.see_all") + Text(" ") + Text(appLocalizedString(
                            module.titleKey, languageCode: language, tableName: module.titleTable)))
                    }
                }
            }
            switch module.presentation {
            case .hero:
                if let item = module.items.first {
                    itemButton(item) {
                        ExploreSurface {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(appLocalizedString(module.titleKey, languageCode: language, tableName: module.titleTable))
                                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    Spacer()
                                    ExploreChevron()
                                }
                                if let result = item.result {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text(result.value).font(.system(size: resultSize, weight: .bold))
                                            .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                                        CompetitionWCARecordTagView(tag: result.level.rawValue, variant: .standard)
                                    }
                                }
                                if let context = item.recordContext {
                                    Text(context.eventName + " · " + context.resultType).font(.subheadline)
                                    Text(context.personName).font(.headline)
                                    Text(context.countryName).font(.footnote).foregroundStyle(.secondary)
                                    Text(context.competitionName).font(.footnote).foregroundStyle(.secondary)
                                } else {
                                    Text(item.title).font(.headline)
                                    Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            case .carousel:
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(module.items) { item in
                            itemButton(item) {
                                ExploreSurface {
                                    competition(item)
                                        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 0 : 120, alignment: .topLeading)
                                }
                                .frame(width: dynamicTypeSize.isAccessibilitySize ? 310 : 280, alignment: .leading)
                            }
                        }
                    }
                }
            case .compactList:
                ExploreSurface {
                    VStack(spacing: 0) {
                        ForEach(module.items) { item in
                            if item.id != module.items.first?.id { Divider() }
                            itemButton(item) { ExploreRecordRow(item: item) }
                        }
                    }
                }
            case .feature:
                if let item = module.items.first {
                    itemButton(item) {
                        ExploreSurface {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title).font(.headline)
                                Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background {
            NavigationLink(destination: destination, isActive: Binding(
                get: { route != nil }, set: { if !$0 { route = nil } }
            )) { EmptyView() }.hidden()
        }
    }

    private func itemButton<Content: View>(_ item: ExploreItem, @ViewBuilder content: () -> Content) -> some View {
        Button { route = .item(item) } label: { content().foregroundStyle(.primary).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityElement(children: .combine)
    }

    private func competition(_ item: ExploreItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let dates = item.competition {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dates.start, format: .dateTime.month(.abbreviated).day())
                            if !Calendar.current.isDate(dates.start, inSameDayAs: dates.end) {
                                Text("- ") + Text(dates.end, format: .dateTime.month(.abbreviated).day())
                            }
                        }
                    } else {
                        HStack(spacing: 4) {
                            Text(dates.start, format: .dateTime.month(.abbreviated).day())
                            if !Calendar.current.isDate(dates.start, inSameDayAs: dates.end) {
                                Text("-")
                                Text(dates.end, format: .dateTime.month(.abbreviated).day())
                            }
                        }
                    }
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(item.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary)
            if let detail = item.competition {
                Text(String(format: appLocalizedString("explore.event_count", languageCode: language,
                    tableName: "ExploreHome"), detail.eventCount)).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var destination: some View {
        switch route {
        case .item(let item): ExploreItemDestination(item: item, store: store, language: language)
        case .all:
            if module.id == "records.recent" { ExploreRecentRecordsView(store: store, language: language) }
            else if let all = module.seeAll { ExploreBrowseView(destination: all) }
        case nil: EmptyView()
        }
    }
}

struct ExploreRecordRow: View {
    let item: ExploreItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let result = item.result {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(result.value).font(.title3.weight(.semibold)).monospacedDigit()
                    CompetitionWCARecordTagView(tag: result.level.rawValue, variant: .standard)
                    if let rank = result.currentRank { Text("#\(rank)").font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            if let context = item.recordContext {
                Text(context.personName).font(.headline)
                Text(context.eventName + " · " + context.resultType).font(.subheadline).foregroundStyle(.secondary)
                Text(context.competitionName).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(item.title).font(.headline)
                Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

struct ExploreItemDestination: View {
    let item: ExploreItem
    @ObservedObject var store: ExploreStore
    let language: String
    @ViewBuilder var body: some View {
        if case .competition(let id) = item.content, let competition = store.competition(id: id) {
            CompetitionDetailView(competition: competition, appLanguage: language)
        } else if case .recentRecord(_, let competitionID, let roundID, let personID, let personWCAID) = item.content {
            ExploreCompetitionLookupDestination(competitionID: competitionID,
                resultDeepLink: CompetitionWCALiveResultDeepLink(roundID: roundID, personID: personID, personWCAID: personWCAID),
                language: language)
        } else { ExploreBrowseView(destination: item.content.destination) }
    }
}

struct ExploreRecentRecordsView: View {
    @ObservedObject var store: ExploreStore
    let language: String
    @State private var level = "All"
    private var items: [ExploreItem] { store.recentRecordItems.filter { level == "All" || $0.result?.level.rawValue == level } }

    var body: some View {
        List {
            Section {
                Picker(selection: $level) {
                    Text("explore.public.gender_all", tableName: "ExplorePublicData").tag("All")
                    ForEach(["WR", "CR", "NR"], id: \.self) { Text($0).tag($0) }
                } label: { Text("explore.public.records", tableName: "ExplorePublicData") }
                .pickerStyle(.segmented)
                if let date = store.recentRecordsFetchedAt {
                    HStack {
                        Text(exploreHomeString("live_provisional", language: language))
                        Spacer(minLength: 8)
                        Text(date, style: .time)
                    }.font(.footnote).foregroundStyle(.secondary)
                }
            }
            if store.recordsState == .loading { ProgressView() }
            else if store.recordsState == .failed {
                Text("explore.unavailable").foregroundStyle(.secondary)
                Button("explore.retry") { Task { await store.loadRecentRecords(language: language, force: true) } }
            } else if store.recordsState == .failedWithCache {
                Text("explore.saved_updated", tableName: "ExploreHome").font(.footnote).foregroundStyle(.secondary)
                if let date = store.recentRecordsFetchedAt { Text(date, style: .date) }
            }
            Section {
                ForEach(items) { item in
                    NavigationLink { ExploreItemDestination(item: item, store: store, language: language) }
                    label: { ExploreRecordRow(item: item) }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
                if items.isEmpty && store.recordsState != .loading && store.recordsState != .failed {
                    Text("explore.public.empty", tableName: "ExplorePublicData").foregroundStyle(.secondary)
                }
            }
            Section {
                NavigationLink { ExploreRecordsView(language: language) } label: { Text("explore.records") }
                DisclosureGroup(exploreHomeString("about_live", language: language)) {
                    Text(appLocalizedString("explore.live_records_note", languageCode: language, tableName: "ExploreHome"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .modifier(ExploreListStyle())
        .navigationTitle(Text("explore.public.recent_records", tableName: "ExplorePublicData"))
        .refreshable { await store.loadRecentRecords(language: language, force: true) }
        .task { await store.loadRecentRecords(language: language) }
    }
}

#if DEBUG
/// Synthetic visual fixtures. Never included in provider or Home composition inputs.
enum ExplorePreviewFixtures {
    static func module(_ presentation: ExplorePresentation) -> ExploreModule {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let items: [ExploreItem]
        switch presentation {
        case .hero:
            items = [ExploreItem(id: "preview.hero", content: .record(id: "preview"),
                title: "Sample competitor", subtitle: "Preview result · Not a real record", date: nil,
                result: ExploreResultPresentation(value: "12.34", level: .world))]
        case .feature:
            items = [ExploreItem(id: "preview.feature", content: .highlight(id: "preview"),
                title: "Where a community meets", subtitle: "A preview of editorial typography, not a published story.", date: nil)]
        case .carousel:
            items = (0..<3).map { index in
                ExploreItem(id: "preview.competition.\(index)", content: .competition(id: "preview"),
                    title: "Regional Open · Preview", subtitle: "Sample city", date: date,
                    competition: ExploreCompetitionPresentation(start: date, end: date.addingTimeInterval(86400),
                        eventCount: 8, registrationOpen: index == 0))
            }
        case .compactList:
            items = (0..<3).map { index in
                ExploreItem(id: "preview.result.\(index)", content: .record(id: "preview"),
                    title: "Sample competitor", subtitle: "Preview event · Sample only", date: nil,
                    result: ExploreResultPresentation(value: "12.34", level: [.world, .continental, .national][index]))
            }
        }
        return ExploreModule(id: presentation.rawValue, titleKey: "explore.preview",
            presentation: presentation, items: items, seeAll: presentation == .carousel ? .competitions : .highlights)
    }
}

private struct ExploreVocabularyPreview: View {
    @StateObject private var store = ExploreStore()
    var body: some View {
        CompatibleNavigationContainer {
            List {
                ForEach(ExplorePresentation.allCases, id: \.rawValue) { presentation in
                    ExploreModuleView(module: ExplorePreviewFixtures.module(presentation), store: store, language: "en")
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .navigationTitle("tab.explore")
        }
    }
}

#Preview("Explore vocabulary · samples only") { ExploreVocabularyPreview() }
#endif
#endif

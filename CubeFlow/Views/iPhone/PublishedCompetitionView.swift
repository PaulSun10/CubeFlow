import SwiftUI

enum PublishedCompetitionStrings {
    static func text(_ key: String, _ language: String) -> String {
        appLocalizedString(key, languageCode: language, tableName: "CompetitionPublished")
    }
    static func round(_ type: String, language: String) -> String {
        let key: String
        switch type {
        case "f", "c": key = "final"
        case "1", "d": key = "first"
        case "2", "e": key = "second"
        case "3", "g": key = "semi_final"
        case "0", "h": return text("round.qualification", language)
        case "b": return text("round.b_final", language)
        default: return text("round.other", language) + " " + type
        }
        // Cutoff and non-cutoff types share the official round title; format is separate.
        return appLocalizedString("competitions.wca.round.\(key)", languageCode: language)
    }
}

private enum PublishedResultsMode: String, CaseIterable, Identifiable {
    case results, champions, podiums, competitor
    var id: String { rawValue }
}

/// Inline destinations: CompetitionDetailView owns the header, scrolling and navigation.
struct PublishedCompetitionResultsContent: View {
    let sourceData: PublishedCompetitionData
    let language: String
    let recordEvidenceRefreshID: Int
    let loadsRecordEvidence: Bool
    @StateObject private var records: PublishedCompetitionRecordEnrichment
    private var data: PublishedCompetitionData { records.current(for: sourceData) }
    var onFirstResult: () -> Void = {}
    @ObservedObject private var auth = WCAAuthManager.shared
    #if DEBUG
    @Environment(\.competitionLivePreviewIdentity) private var previewIdentity
    #endif
    @State private var mode: PublishedResultsMode = .results
    @State private var selectedEvent = ""
    @State private var selectedRound = ""
    @State private var initialResultUnavailable = false
    @State private var query = ""
    @ObservedObject var resultCard = CompetitionResultCardState()

    init(data: PublishedCompetitionData, language: String,
         initialResult: PublishedCompetitionResultDeepLink? = nil,
         onFirstResult: @escaping () -> Void = {}, resultCard: CompetitionResultCardState? = nil,
         recordEvidenceRefreshID: Int = 0, recordEnrichment: PublishedCompetitionRecordEnrichment? = nil,
         loadsRecordEvidence: Bool = true) {
        self.sourceData = data
        self.language = language
        self.recordEvidenceRefreshID = recordEvidenceRefreshID; self.loadsRecordEvidence = loadsRecordEvidence
        _records = StateObject(wrappedValue: recordEnrichment ?? PublishedCompetitionRecordEnrichment())
        self.onFirstResult = onFirstResult
        self.resultCard = resultCard ?? CompetitionResultCardState()
        // Resolve the official result's actual round, never a guessed Live round ID.
        let row = initialResult?.result(in: data)
        _selectedEvent = State(initialValue: row?.eventID ?? "")
        _selectedRound = State(initialValue: row?.roundKey ?? "")
        _initialResultUnavailable = State(initialValue: initialResult != nil && row == nil)
    }

    private var eventID: String { data.eventIDs.contains(selectedEvent) ? selectedEvent : data.eventIDs.first ?? "" }
    #if DEBUG
    init(data: PublishedCompetitionData, language: String, renderingChampions: Bool) {
        self.init(data: data, language: language, loadsRecordEvidence: false)
        _mode = State(initialValue: renderingChampions ? .champions : .results)
    }
    #endif
    private var rounds: [PublishedCompetitionRound] { data.rounds(for: eventID) }
    private var round: PublishedCompetitionRound? { rounds.first { $0.id == selectedRound } ?? rounds.last }
    private var ownWCAID: String? {
        #if DEBUG
        if let previewIdentity { return previewIdentity }
        #endif
        return auth.isSignedIn ? auth.profile?.wcaId : nil
    }
    private func t(_ key: String) -> String { PublishedCompetitionStrings.text(key, language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CompetitionResultsNavigation(options: PublishedResultsMode.allCases.map(\.rawValue),
                selection: Binding(get: { mode.rawValue }, set: { if let value = PublishedResultsMode(rawValue: $0) { mode = value } }), title: t)
            if records.showsSavedEvidence {
                Text(appLocalizedString("explore.cached", languageCode: language)).font(.caption).foregroundStyle(.secondary)
            }
            switch mode {
            case .results:
                if initialResultUnavailable {
                    Text(appLocalizedString("explore.public.unavailable", languageCode: language,
                        tableName: "ExplorePublicData")).foregroundStyle(.secondary)
                } else {
                    let tags = data.selectorRecordTags(ownWCAID: ownWCAID)
                    CompetitionResultsSelectorGroup {
                        PublishedEventSelector(eventIDs: data.eventIDs, selection: $selectedEvent, effectiveEvent: eventID, language: language,
                            recordTags: tags.events)
                    } rounds: {
                        PublishedRoundSelector(rounds: rounds.map { ($0.id, $0.typeID) }, selection: Binding(
                            get: { round?.id ?? "" }, set: { selectedRound = $0 }), language: language,
                            recordTags: tags.rounds)
                    }
                    if let round { rankedRows(round.results, showsHeader: true) }
                }
            case .champions, .podiums:
                if data.finals.isEmpty { Text(t("no_final")).font(.subheadline).foregroundStyle(.secondary) }
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(data.finals) { final in
                        VStack(alignment: .leading, spacing: 8) {
                            PublishedEventHeading(eventID: final.eventID, language: language)
                            rankedRows(mode == .champions ? final.champions : final.podium, showsHeader: true, eager: true)
                        }
                    }
                }
            case .competitor:
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(t("search"), text: $query)
                        .textInputAutocapitalization(.never).disableAutocorrection(true)
                }
                .padding(10).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                let people = data.people(query: query, currentWCAID: auth.profile?.wcaId)
                LazyVStack(alignment: .leading, spacing: 0) {
                    if people.isEmpty { Text(t("no_matches")).foregroundStyle(.secondary) }
                    ForEach(people) { person in
                        Button { present(person) } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.name).font(.subheadline.weight(person.id == auth.profile?.wcaId ? .semibold : .regular))
                                    Text(person.id).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                if person.id == auth.profile?.wcaId {
                                    Text(t("you")).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                                }
                                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                            }.padding(.vertical, 9).foregroundStyle(.primary)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("published-competitor-\(person.id)")
                        Divider()
                    }
                }
            }
        }
        .onChange(of: eventID) { _ in
            if !rounds.contains(where: { $0.id == selectedRound }) { selectedRound = "" }
        }
        .onAppear { hydrateRecordEvidence() }
        .onChange(of: sourceData.results) { _ in hydrateRecordEvidence() }
        .onChange(of: ownWCAID) { _ in hydrateRecordEvidence() }
        .onChange(of: recordEvidenceRefreshID) { _ in records.refreshVisible(including: ownWCAID) }
        .onChange(of: records.updateID) { _ in
            resultCard.refreshPublishedRecordEvidence(data, language: language)
        }
        .onDisappear { records.cancel() }
    }

    private func hydrateRecordEvidence() {
        records.configure(sourceData)
        if loadsRecordEvidence { records.requested(ownWCAID, source: sourceData) }
    }

    private func rankedRows(_ rows: [PublishedCompetitionResult], showsHeader: Bool = false, eager: Bool = false) -> some View {
        Group {
            if let first = rows.first, let source = data.rounds.first(where: { $0.id == first.roundKey }) {
                let round = PublishedCompetitionRound(id: source.id, eventID: source.eventID, typeID: source.typeID, results: rows)
                CompetitionResultExperience(round: PublishedCompetitionPresentation.round(round, language: language, data: data),
                    languageCode: language, cardState: resultCard, showsHeader: showsHeader, isPublished: true,
                    usesEagerRows: eager,
                    loadAllResults: { result in
                        if loadsRecordEvidence { records.requested(result.personWCAID, source: sourceData) }
                        return PublishedCompetitionPresentation.competitor(result.personWCAID ?? "", data: data, language: language)
                    }, onFirstResult: onFirstResult,
                    onResultVisible: { if loadsRecordEvidence { records.appeared($0.personWCAID, source: sourceData) } },
                    onResultHidden: { records.disappeared($0.personWCAID) })
            }
        }
    }

    private func present(_ person: PublishedCompetitionPerson) {
        if loadsRecordEvidence { records.requested(person.id, source: sourceData) }
        guard let content = PublishedCompetitionPresentation.competitor(person.id, data: data, language: language) else { return }
        resultCard.presentCompetition(id: person.id, name: person.name, isPublished: true, content: content)
    }
}

enum PublishedResultPresentation {
    static func statistics(_ result: PublishedCompetitionResult) -> [String] {
        guard result.showsAverage else { return ["best"] }
        return result.usesAverage ? ["average", "best"] : ["best", "average"]
    }
    static func width(_ statistic: String, result: PublishedCompetitionResult) -> CGFloat {
        result.eventID.hasPrefix("333mb") ? 105 : (statistic == "average" ? 72 : 62)
    }
    static func title(_ statistic: String, result: PublishedCompetitionResult, language: String) -> String {
        PublishedCompetitionStrings.text(statistic == "average" && result.formatID != "a" ? "mean" : statistic, language)
    }
    static func values(_ result: PublishedCompetitionResult) -> [CompetitionResultTableValue] {
        statistics(result).map { statistic in
            let average = statistic == "average"
            return CompetitionResultTableValue(id: statistic,
                text: result.formatted(average ? result.average : result.best, average: average),
                recordTag: average ? result.averageBadge : result.singleBadge, width: width(statistic, result: result))
        }
    }
}

struct PublishedResultColumnHeader: View {
    let result: PublishedCompetitionResult?
    let language: String
    var body: some View {
        if let result {
            CompetitionResultTableHeader(nameTitle: PublishedCompetitionStrings.text("competitor_name", language),
                columns: PublishedResultPresentation.statistics(result).map { statistic in
                    CompetitionResultTableColumn(id: statistic,
                        title: PublishedResultPresentation.title(statistic, result: result, language: language),
                        width: PublishedResultPresentation.width(statistic, result: result))
                })
        }
    }
}

struct PublishedResultRow: View {
    let result: PublishedCompetitionResult
    let language: String
    var showsName = true
    var body: some View {
        CompetitionResultTableRow(rank: String(result.rank), name: showsName ? result.name : "",
            values: PublishedResultPresentation.values(result))
    }
}

struct PublishedEventHeading: View {
    let eventID: String
    let language: String
    var body: some View {
        HStack(spacing: 8) {
            if let glyph = CompetitionEventIconFont.glyph(for: eventID) {
                CompetitionEventGlyph(glyph: glyph,
                    eventName: CompetitionEventPresentation.localizedFullName(for: eventID, languageCode: language), size: 20)
            }
            Text(CompetitionEventPresentation.localizedFullName(for: eventID, languageCode: language))
        }
        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary).textCase(nil)
    }
}

/// Explicit foregrounds also apply to the glyph's own Text, not just its capsule.
enum PublishedEventSelectorStyle {
    static func foreground(selected: Bool) -> Color { selected ? .white : .primary }
    static func inkOffset(_ glyph: String, size: CGFloat) -> CGSize {
        _ = CompetitionEventIconFont.ensureRegistered()
        guard let metrics = CompetitionEventIconFont.glyphMetrics(for: glyph, pointSize: size),
              let font = UIFont(name: CompetitionEventIconFont.fontName, size: size) else { return .zero }
        return CGSize(width: -metrics.centerOffset, height: metrics.bounds.midY - (font.ascender + font.descender) / 2)
    }
}

enum PublishedResultsStyle {
    // Opaque secondary ink avoids the vibrancy attenuation of hierarchical .secondary.
    static let attemptForeground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.76, alpha: 1) : UIColor(white: 0.34, alpha: 1)
    })
}

struct PublishedEventSelector: View {
    let eventIDs: [String]
    @Binding var selection: String
    let effectiveEvent: String
    let language: String
    var recordTags: [String: String] = [:]
    var cubingChinaLive = false
    @ScaledMetric(relativeTo: .body) private var cellSize: CGFloat = 30
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 20
    var body: some View {
        CompetitionProgressiveBlurScrollView {
                HStack(spacing: 0) {
                    ForEach(eventIDs, id: \.self) { event in
                        let selected = effectiveEvent == event
                        Button { selection = event } label: {
                            Group {
                                if cubingChinaLive && event == "smart" {
                                    CompetitionBluetoothSymbol().stroke(PublishedEventSelectorStyle.foreground(selected: selected),
                                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                                        .frame(width: iconSize * 0.6, height: iconSize)
                                } else if let glyph = CompetitionEventIconFont.glyph(for: event) {
                                    CompetitionEventGlyph(glyph: glyph,
                                        eventName: CompetitionEventPresentation.localizedFullName(for: event, languageCode: language),
                                        size: iconSize, color: PublishedEventSelectorStyle.foreground(selected: selected))
                                        .offset(PublishedEventSelectorStyle.inkOffset(glyph, size: iconSize))
                                } else { Text(event).foregroundStyle(PublishedEventSelectorStyle.foreground(selected: selected)) }
                            }
                            .frame(width: cellSize, height: cellSize)
                            .padding(.trailing, recordTags[event] == nil ? 0 : 10)
                            .overlay(alignment: .topTrailing) {
                                if let tag = recordTags[event] {
                                    CompetitionWCARecordTagView(tag: tag, variant: .compact, isOwnPersonalRecord: tag == "PR")
                                        .allowsHitTesting(false)
                                }
                            }
                            .background {
                                if selected {
                                    RoundedRectangle(cornerRadius: 8).fill(Color.blue)
                                        .padding(recordTags[event] == nil ? 0 : -3)
                                }
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(cubingChinaLive ? CubingChinaEventDisplay.name(event, language: language) : CompetitionEventPresentation.localizedFullName(for: event, languageCode: language))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityValue(recordTags[event] ?? "")
                    }
                }
        }
    }
}

struct PublishedRoundSelector: View {
    let rounds: [(id: String, type: String)]
    @Binding var selection: String
    let language: String
    var recordTags: [String: String] = [:]
    var trailingOptions: [String] = []
    var trailingSelection: Binding<String> = .constant("")
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(rounds, id: \.id) { round in
                    Button { selection = round.id } label: {
                        Text(PublishedCompetitionStrings.round(round.type, language: language))
                            .font(.caption.weight(selection == round.id ? .semibold : .regular))
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .foregroundStyle(selection == round.id ? Color.accentColor : .primary)
                            .padding(.trailing, recordTags[round.id] == nil ? 0 : 16)
                            .overlay(alignment: .topTrailing) {
                                if let tag = recordTags[round.id] {
                                    CompetitionWCARecordTagView(tag: tag, variant: .compact, isOwnPersonalRecord: tag == "PR").allowsHitTesting(false)
                                }
                            }
                            .background {
                                if selection == round.id {
                                    RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.opacity(0.12))
                                        .padding(recordTags[round.id] == nil ? 0 : -3)
                                }
                            }
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .accessibilityAddTraits(selection == round.id ? .isSelected : [])
                    .accessibilityValue(recordTags[round.id] ?? "")
                }
                if !trailingOptions.isEmpty {
                    Divider().frame(height: 18)
                    ForEach(trailingOptions, id: \.self) { group in
                        Button { trailingSelection.wrappedValue = group } label: {
                            Text(PublishedCompetitionStrings.text("group", language) + " " + group)
                                .font(.caption.weight(trailingSelection.wrappedValue == group ? .semibold : .regular))
                                .padding(.horizontal, 9).padding(.vertical, 3)
                                .foregroundStyle(trailingSelection.wrappedValue == group ? Color.accentColor : .primary)
                                .background(trailingSelection.wrappedValue == group ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .accessibilityAddTraits(trailingSelection.wrappedValue == group ? .isSelected : [])
                    }
                }
            }
        }
    }
}

struct PublishedScrambleGroupHeading: View {
    let group: String
    let language: String
    var body: some View {
        Text(PublishedCompetitionStrings.text("group", language) + " " + group)
            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("competition-scrambles-group-heading")
    }
}

struct PublishedCompetitionScramblesContent: View {
    let data: PublishedCompetitionData
    let language: String
    @ObservedObject var state: PublishedCompetitionScramblesStore
    var refreshVersion = 0
    var isCoordinated = false
    var isPreparing = false
    var onRetry: (() -> Void)?
    var onFirstScramble: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme
    private var sets: [PublishedScrambleSet] { state.sets }
    private var loading: Bool { state.loading || isPreparing }
    private var failed: Bool { state.failed }
    @State private var event = ""
    @State private var round = ""
    @State private var group = ""
    @State private var selectedScramble: PublishedCompetitionScramble?
    @State private var loadedRefreshVersion: Int?
    init(data: PublishedCompetitionData, language: String, service: PublishedCompetitionService = .shared,
         state: PublishedCompetitionScramblesStore? = nil, refreshVersion: Int = 0,
         isCoordinated: Bool = false, isPreparing: Bool = false, onRetry: (() -> Void)? = nil,
         onFirstScramble: @escaping () -> Void = {}) {
        self.data = data; self.language = language
        self.state = state ?? PublishedCompetitionScramblesStore(service: service)
        self.refreshVersion = refreshVersion; self.onFirstScramble = onFirstScramble
        self.isCoordinated = isCoordinated; self.isPreparing = isPreparing; self.onRetry = onRetry
    }
    private func t(_ key: String) -> String { PublishedCompetitionStrings.text(key, language) }
    var body: some View {
        let selection = PublishedScrambleSelection(sets: sets, eventOrder: data.eventIDs,
            event: event, round: round, group: group)
        VStack(alignment: .leading, spacing: 12) {
            if loading { ProgressView().frame(maxWidth: .infinity) }
            if failed {
                Text(t("scrambles_failed")).font(.subheadline).foregroundStyle(.secondary)
                Button(t("retry")) {
                    if let onRetry { onRetry() }
                    else { Task { await load(refresh: true) } }
                }
            }
            if !loading && !failed && sets.isEmpty { Text(t("scrambles_empty")).foregroundStyle(.secondary) }
            if !sets.isEmpty {
                CompetitionResultsSelectorGroup {
                    PublishedEventSelector(eventIDs: selection.events, selection: $event, effectiveEvent: selection.eventID, language: language)
                } rounds: {
                    PublishedRoundSelector(rounds: selection.roundOptions.map { ($0.id, $0.type) },
                        selection: Binding(get: { selection.roundID }, set: { round = $0; group = "" }), language: language,
                        trailingOptions: selection.groups,
                        trailingSelection: Binding(get: { selection.currentSet?.groupID ?? "" }, set: { group = $0 }))
                }
                if let currentSet = selection.currentSet {
                    PublishedScrambleGroupHeading(group: currentSet.groupID, language: language)
                    ForEach([false, true], id: \.self) { extra in
                        let rows = currentSet.scrambles.filter { $0.isExtra == extra }
                        if !rows.isEmpty {
                            if extra { Text(t("extra")).font(.subheadline.weight(.semibold)).padding(.top, 4) }
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(rows) { scramble in
                                    Button { selectedScramble = scramble } label: {
                                        HStack(alignment: .top, spacing: 10) {
                                            Text(scramble.displayNumber).font(.caption.weight(.semibold).monospacedDigit())
                                                .foregroundStyle(PublishedResultsStyle.attemptForeground).frame(minWidth: 24, alignment: .leading)
                                            Text(scramble.scramble).font(.subheadline.monospaced()).foregroundStyle(.primary)
                                                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }.padding(.vertical, 11).frame(minHeight: 44).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                    .accessibilityIdentifier("competition-scramble-\(scramble.id)")
                                    .onAppear { if scramble.id == currentSet.scrambles.first?.id { onFirstScramble() } }
                                    .contextMenu {
                                        Button {
                                            UIPasteboard.general.string = scramble.scramble
                                        } label: { Label(PublishedCompetitionStrings.text("copy", language), systemImage: "doc.on.doc") }
                                    }
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        }
        .task(id: "\(data.competitionID)|\(refreshVersion)") {
            guard !isCoordinated else { return }
            let refresh = loadedRefreshVersion != nil && loadedRefreshVersion != refreshVersion
            loadedRefreshVersion = refreshVersion
            await load(refresh: refresh)
        }
        .onChange(of: event) { _ in round = ""; group = "" }
        .sheet(item: $selectedScramble) { scramble in
            if let puzzle = scramble.puzzleKey {
                ScrambleDiagramSheet(title: "Scramble", puzzleKey: puzzle, scramble: scramble.scramble,
                    exportAppearance: .solveDetail(colorScheme == .dark ? .dark : .light))
            } else {
                CompatibleNavigationContainer {
                    ScrollView { Text(scramble.scramble).font(.body.monospaced()).textSelection(.enabled).padding() }
                        .navigationTitle(t("scrambles"))
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("done")) { selectedScramble = nil } } }
                }
            }
        }
    }
    private func load(refresh: Bool = false) async {
        await state.load(id: data.competitionID, refresh: refresh)
    }
}

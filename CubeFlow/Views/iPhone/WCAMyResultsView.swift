import SwiftUI
import Combine

@MainActor
final class WCAMyResultsViewModel: ObservableObject {
    @Published private(set) var page: WCAPersonResultsPage?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var cachedResultsLastUpdated: Date?
    @Published var selectedEventCode: String = ""

    private var loadedWCAID: String?
    private var loadedLanguageCode: String?

    func load(wcaId: String, appLanguageCode: String, forceRefresh: Bool = false) async {
        if !forceRefresh, loadedWCAID == wcaId, loadedLanguageCode == appLanguageCode, page != nil {
            return
        }

        isLoading = true
        if page == nil {
            errorMessage = nil
        }

        let cachedSnapshot: WCAResultsService.CachedPersonResultsSnapshot?
        if forceRefresh {
            cachedSnapshot = nil
        } else {
            cachedSnapshot = await WCAResultsService.cachedPersonResults(
                wcaId: wcaId,
                appLanguageCode: appLanguageCode
            )
        }

        if let cachedSnapshot {
            page = cachedSnapshot.page
            cachedResultsLastUpdated = cachedSnapshot.lastUpdated
            loadedWCAID = wcaId
            loadedLanguageCode = appLanguageCode
            if !cachedSnapshot.page.resultsSections.contains(where: { $0.event.code == selectedEventCode }) {
                selectedEventCode = cachedSnapshot.page.resultsSections.first?.event.code ?? ""
            }
            errorMessage = nil
        }

        do {
            let fetchedPage = try await WCAResultsService.fetchPersonResults(
                wcaId: wcaId,
                appLanguageCode: appLanguageCode,
                useCache: false
            )
            page = fetchedPage
            cachedResultsLastUpdated = nil
            loadedWCAID = wcaId
            loadedLanguageCode = appLanguageCode
            if !fetchedPage.resultsSections.contains(where: { $0.event.code == selectedEventCode }) {
                selectedEventCode = fetchedPage.resultsSections.first?.event.code ?? ""
            }
            errorMessage = nil

            let loadedKeyWCAID = wcaId
            let loadedKeyLanguageCode = appLanguageCode
            Task { [weak self] in
                guard let self else { return }
                let enrichedPage = await WCAResultsService.enrichPersonResults(
                    fetchedPage,
                    appLanguageCode: loadedKeyLanguageCode
                )
                await MainActor.run {
                    guard self.loadedWCAID == loadedKeyWCAID,
                          self.loadedLanguageCode == loadedKeyLanguageCode else { return }
                    self.page = enrichedPage
                    if !enrichedPage.resultsSections.contains(where: { $0.event.code == self.selectedEventCode }) {
                        self.selectedEventCode = enrichedPage.resultsSections.first?.event.code ?? ""
                    }
                }
            }
        } catch {
            if cachedSnapshot == nil {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                cachedResultsLastUpdated = nil
            } else {
                errorMessage = nil
            }
        }

        isLoading = false
    }
}

struct WCAMyResultsView: View {
    let profile: WCAUserProfile?

    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @StateObject private var viewModel = WCAMyResultsViewModel()

    private var wcaId: String? {
        profile?.wcaId?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedSection: WCAEventResultsSection? {
        guard let page = viewModel.page else { return nil }
        return page.resultsSections.first(where: { $0.event.code == viewModel.selectedEventCode }) ?? page.resultsSections.first
    }

    private var selectedSectionRecordHighlights: [String: ResultRecordHighlight] {
        guard let selectedSection else { return [:] }
        return recordHighlights(in: selectedSection)
    }

    private var cachedResultsBannerText: String? {
        guard let cachedResultsLastUpdated = viewModel.cachedResultsLastUpdated else { return nil }
        let formattedDate = cachedResultsTimestampFormatter(languageCode: appLanguage).string(from: cachedResultsLastUpdated)
        return String(
            format: appLocalizedString("wca.results.cached_banner_format", languageCode: appLanguage),
            formattedDate
        )
    }

    var body: some View {
        Group {
            if let wcaId, !wcaId.isEmpty {
                content(for: wcaId)
            } else {
                unavailableView(message: appLocalizedString("wca.results_error_missing_wca_id", languageCode: appLanguage))
            }
        }
        .navigationTitle(Text(appLocalizedString("settings.wca_my_results", languageCode: appLanguage)))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(for wcaId: String) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                if let cachedResultsBannerText {
                    cachedResultsBanner(text: cachedResultsBannerText)
                }

                if let page = viewModel.page {
                    summaryCard(page: page)
                    personalRecordsCard(records: page.personalRecords)
                    resultsCard(sections: page.resultsSections)
                } else if viewModel.isLoading {
                    loadingView
                } else {
                    unavailableView(message: viewModel.errorMessage ?? appLocalizedString("wca.results_error_request_failed", languageCode: appLanguage))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 0)
            .padding(.bottom, 20)
        }
        .task(id: wcaId) {
            await viewModel.load(wcaId: wcaId, appLanguageCode: appLanguage)
        }
        .onChange(of: appLanguage) { newValue in
            Task {
                await viewModel.load(wcaId: wcaId, appLanguageCode: newValue, forceRefresh: true)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.page != nil {
                    Button {
                        Task {
                            await viewModel.load(wcaId: wcaId, appLanguageCode: appLanguage, forceRefresh: true)
                        }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }

    private func cachedResultsBanner(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.clock")
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("wca.results_loading")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func unavailableView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let wcaId, !wcaId.isEmpty {
                Button("wca.results_retry") {
                    Task {
                        await viewModel.load(wcaId: wcaId, appLanguageCode: appLanguage, forceRefresh: true)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func summaryCard(page: WCAPersonResultsPage) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                if let avatarURLString = profile?.avatarURL,
                   let avatarURL = URL(string: avatarURLString) {
                    AsyncImage(url: avatarURL) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    .frame(width: 56, height: 56)
                } else {
                    Image(systemName: "person.crop.square")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, height: 56)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile?.displayName ?? "WCA")
                        .font(.system(size: 19, weight: .semibold))
                    Text(page.summary.wcaId)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                summaryCell(
                    titleKey: "wca.results_region",
                    value: localizedSummaryRegion(page.summary.region),
                    leadingSymbol: regionCountryCode(from: page.summary.region).map(flagEmoji(for:))
                )
                summaryCell(
                    titleKey: "wca.results_gender",
                    value: localizedGender(page.summary.gender)
                )
                summaryCell(titleKey: "wca.results_competitions", value: page.summary.competitions)
                summaryCell(titleKey: "wca.results_completed_solves", value: page.summary.completedSolves)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func summaryCell(titleKey: String, value: String, leadingSymbol: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(titleKey))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if let leadingSymbol, !leadingSymbol.isEmpty {
                    Text(leadingSymbol)
                }

                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func personalRecordsCard(records: [WCAPersonalRecord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("wca.results_current_personal_records")
                .font(.system(size: 18, weight: .semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    personalRecordsHeaderRow

                    VStack(spacing: 0) {
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            personalRecordRow(record)

                            if index < records.count - 1 {
                                Divider()
                                    .padding(.leading, 6)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var personalRecordsHeaderRow: some View {
        HStack(spacing: 0) {
            personalRecordHeaderCell("wca.results_event", width: 96, alignment: .leading)
            personalRecordHeaderCell("wca.results_nr", width: 46)
            personalRecordHeaderCell("wca.results_cr", width: 46)
            personalRecordHeaderCell("wca.results_wr", width: 46)
            personalRecordHeaderCell("wca.results_single", width: 80)
            personalRecordHeaderCell("wca.results_average", width: 80)
            personalRecordHeaderCell("wca.results_wr", width: 46)
            personalRecordHeaderCell("wca.results_cr", width: 46)
            personalRecordHeaderCell("wca.results_nr", width: 46)
        }
        .padding(.horizontal, 6)
    }

    private func personalRecordHeaderCell(
        _ titleKey: String,
        width: CGFloat,
        alignment: Alignment = .center
    ) -> some View {
        Text(LocalizedStringKey(titleKey))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
    }

    private func personalRecordRow(_ record: WCAPersonalRecord) -> some View {
        HStack(spacing: 0) {
            Text(localizedEventName(for: record.event))
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 96, alignment: .leading)

            personalRecordValueCell(record.singleNationalRank, width: 46)
            personalRecordValueCell(record.singleContinentRank, width: 46)
            personalRecordValueCell(record.singleWorldRank, width: 46)
            personalRecordValueCell(record.single, width: 80, weight: .bold)
            personalRecordValueCell(record.average, width: 80, weight: .bold)
            personalRecordValueCell(record.averageWorldRank, width: 46)
            personalRecordValueCell(record.averageContinentRank, width: 46)
            personalRecordValueCell(record.averageNationalRank, width: 46)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
    }

    private func personalRecordValueCell(
        _ value: String?,
        width: CGFloat,
        weight: Font.Weight = .medium
    ) -> some View {
        Text(value ?? "—")
            .font(.system(size: 13, weight: weight))
            .monospacedDigit()
            .frame(width: width, alignment: .center)
    }

    private func resultsCard(sections: [WCAEventResultsSection]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("wca.results_results")
                .font(.system(size: 18, weight: .semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sections) { section in
                        Button {
                            viewModel.selectedEventCode = section.event.code
                        } label: {
                            Text(localizedEventPickerLabel(for: section.event))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(viewModel.selectedEventCode == section.event.code ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Group {
                                        if viewModel.selectedEventCode == section.event.code {
                                            Capsule().fill(Color.blue)
                                        } else {
                                            Capsule().fill(.thinMaterial)
                                        }
                                    }
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }

            if let selectedSection {
                VStack(spacing: 10) {
                    ForEach(groupedResults(in: selectedSection)) { group in
                        competitionGroupRow(group)
                    }
                }
            } else {
                Text("wca.results_empty")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func competitionGroupRow(_ group: WCACompetitionGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let countryISO2 = group.countryISO2 {
                    Text(flagEmoji(for: countryISO2))
                }

                Text(group.competitionName)
                    .font(.system(size: 16, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ForEach(Array(group.results.enumerated()), id: \.element.id) { index, result in
                    resultRow(result)

                    if index < group.results.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func resultRow(_ result: WCACompetitionResult) -> some View {
        let highlight = selectedSectionRecordHighlights[result.id] ?? .none

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.roundName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("wca.results_place")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(result.place ?? "—")
                        .font(.system(size: 16, weight: .bold))
                        .monospacedDigit()
                }
            }

            HStack(alignment: .top, spacing: 20) {
                resultMetric(titleKey: "wca.results_single", value: result.single, isRecord: highlight.single)
                resultMetric(titleKey: "wca.results_average", value: result.average, isRecord: highlight.average)
            }
            .padding(.top, -16)

            if !result.solves.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("wca.results_solves")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(formattedSolves(result.solves))
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func resultMetric(titleKey: String, value: String?, isRecord: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(titleKey))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isRecord ? .orange : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedSolves(_ solves: [WCAAttemptResult]) -> String {
        solves
            .map { solve in
                solve.isTrimmed ? "(\(solve.value))" : solve.value
            }
            .joined(separator: ", ")
    }

    private func localizedEventName(for event: WCAEventDescriptor) -> String {
        let key: String
        switch event.code {
        case "333": key = "event.3x3"
        case "222": key = "event.2x2"
        case "444": key = "event.4x4"
        case "555": key = "event.5x5"
        case "666": key = "event.6x6"
        case "777": key = "event.7x7"
        case "333oh": key = "event.3x3oh"
        case "clock": key = "event.clock"
        case "minx": key = "event.megaminx"
        case "pyram": key = "event.pyraminx"
        case "skewb": key = "event.skewb"
        case "sq1": key = "event.square1"
        case "333fm": key = "event.3x3fm"
        case "333bld": key = "event.3x3bld"
        case "444bld": key = "event.4x4bld"
        case "555bld": key = "event.5x5bld"
        case "333mbf", "333mbld": key = "event.3x3mbld"
        default: return event.name
        }

        return appLocalizedString(key, languageCode: appLanguage, defaultValue: event.name)
    }

    private func localizedEventPickerLabel(for event: WCAEventDescriptor) -> String {
        localizedEventName(for: event)
    }

    private func groupedResults(in section: WCAEventResultsSection) -> [WCACompetitionGroup] {
        var groups: [WCACompetitionGroup] = []

        for result in section.results {
            let groupKey = result.competitionPath ?? result.competitionName

            if let lastIndex = groups.indices.last,
               groups[lastIndex].key == groupKey {
                groups[lastIndex].results.append(result)
            } else {
                groups.append(
                    WCACompetitionGroup(
                        key: groupKey,
                        competitionName: result.competitionName,
                        countryISO2: result.countryISO2,
                        results: [result]
                    )
                )
            }
        }

        return groups
    }

    private func recordHighlights(in section: WCAEventResultsSection) -> [String: ResultRecordHighlight] {
        var highlights: [String: ResultRecordHighlight] = [:]
        var bestSingle: Double?
        var bestAverage: Double?

        for result in section.results.reversed() {
            let singleValue = parsedResultValue(result.single)
            let averageValue = parsedResultValue(result.average)

            let isSingleRecord: Bool
            if let singleValue {
                isSingleRecord = bestSingle == nil || singleValue < bestSingle!
                if isSingleRecord {
                    bestSingle = singleValue
                }
            } else {
                isSingleRecord = false
            }

            let isAverageRecord: Bool
            if let averageValue {
                isAverageRecord = bestAverage == nil || averageValue < bestAverage!
                if isAverageRecord {
                    bestAverage = averageValue
                }
            } else {
                isAverageRecord = false
            }

            highlights[result.id] = ResultRecordHighlight(single: isSingleRecord, average: isAverageRecord)
        }

        return highlights
    }

    private func parsedResultValue(_ value: String?) -> Double? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let uppercased = trimmed.uppercased()
        guard uppercased != "DNF", uppercased != "DNS" else { return nil }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        let components = normalized.split(separator: ":")
        if components.count == 1 {
            return Double(components[0])
        }

        var multiplier = 1.0
        var total = 0.0
        for component in components.reversed() {
            guard let part = Double(component) else { return nil }
            total += part * multiplier
            multiplier *= 60
        }
        return total
    }

    private func localizedSummaryRegion(_ rawValue: String) -> String {
        rawValue
    }

    private func localizedGender(_ rawValue: String) -> String {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        let key: String
        switch normalized {
        case "m", "male":
            key = "wca.gender.male"
        case "f", "female":
            key = "wca.gender.female"
        case "o", "other":
            key = "wca.gender.other"
        default:
            return rawValue
        }

        return localizedSummaryString(key: key)
    }

    private func localizedSummaryString(key: String) -> String {
        appLocalizedString(key, languageCode: appLanguage)
    }

    private func regionCountryCode(from region: String) -> String? {
        let trimmed = region.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let override = regionCountryCodeOverrides[trimmed] {
            return override
        }

        let normalizedTarget = normalizedRegionName(trimmed)
        let localeIdentifiers = [
            "en_US",
            "zh-Hans",
            "zh_Hans_CN"
        ]

        for code in Locale.isoRegionCodes {
            guard code.count == 2 else {
                continue
            }

            for localeIdentifier in localeIdentifiers {
                let locale = Locale(identifier: localeIdentifier)
                guard let localized = locale.localizedString(forRegionCode: code) else {
                    continue
                }

                if normalizedRegionName(localized) == normalizedTarget {
                    return code
                }
            }
        }

        return nil
    }

    private func normalizedRegionName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "hong kong sar china", with: "hong kong china")
            .replacingOccurrences(of: "macao sar china", with: "macau china")
            .replacingOccurrences(of: "macao", with: "macau")
            .replacingOccurrences(of: "中國", with: "中国")
            .replacingOccurrences(of: "澳門", with: "澳门")
            .replacingOccurrences(of: "臺", with: "台")
            .replacingOccurrences(of: "[^a-zA-Z0-9\\p{Han}]+", with: "", options: .regularExpression)
            .lowercased()
    }
}

@MainActor
final class WCAMyCompetitionsViewModel: ObservableObject {
    @Published private(set) var page: WCAMyCompetitionsPage?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func load(forceRefresh: Bool = false) async {
        if !forceRefresh, page != nil {
            return
        }

        isLoading = true
        if page == nil {
            errorMessage = nil
        }

        do {
            page = try await WCAMyCompetitionsService.fetchMyCompetitions(
                authManager: WCAAuthManager.shared
            )
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }
}

struct WCAMyCompetitionsView: View {
    let profile: WCAUserProfile?

    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("requestedIPhoneTab") private var requestedIPhoneTab: String = ""
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = WCAMyCompetitionsViewModel()
    @State private var isUpcomingExpanded = true
    @State private var isPastExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                myCompetitionsIntro

                if let page = viewModel.page {
                    myCompetitionsSection(page: page)
                    Divider()
                    bookmarkedCompetitionsSection(page.bookmarkedCompetitions)
                } else if viewModel.isLoading {
                    loadingCard
                } else {
                    errorCard(message: viewModel.errorMessage ?? appLocalizedString("wca.competitions_error_request_failed", languageCode: appLanguage))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 0)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text(appLocalizedString("settings.wca_my_competitions", languageCode: appLanguage)))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.load()
        }
        .modifier(
            WCAMyCompetitionsToolbarModifier(
                isLoading: viewModel.isLoading,
                profile: profile,
                refresh: {
                    Task {
                        await viewModel.load(forceRefresh: true)
                    }
                }
            )
        )
        .refreshable {
            await viewModel.load(forceRefresh: true)
        }
    }

    private var myCompetitionsIntro: some View {
        Text("wca.competitions_intro")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func myCompetitionsSection(page: WCAMyCompetitionsPage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if page.futureCompetitions.isEmpty {
                emptyUpcomingView
            } else {
                DisclosureGroup(isExpanded: $isUpcomingExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        competitionRows(
                            page.futureCompetitions,
                            registrationsByCompetition: page.registrationsByCompetition
                        )
                    }
                    .padding(.top, 10)
                } label: {
                    disclosureLabel("wca.competitions_upcoming")
                }
                .tint(.primary)

                Divider()
            }

            DisclosureGroup(isExpanded: $isPastExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    if page.pastCompetitions.isEmpty {
                        emptyText("wca.competitions_empty_past")
                    } else {
                        competitionRows(
                            page.pastCompetitions,
                            registrationsByCompetition: page.registrationsByCompetition
                        )
                    }
                }
                .padding(.top, 10)
            } label: {
                Text(
                    String(
                        format: appLocalizedString("wca.competitions_past_format", languageCode: appLanguage),
                        page.pastCompetitions.count
                    )
                )
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            }
            .tint(.primary)
        }
    }

    private func bookmarkedCompetitionsSection(_ competitions: [WCAMyCompetitionSummary]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.primary)

                prominentSectionHeader("wca.competitions_bookmarked")
            }

            Text("wca.competitions_bookmarked_intro")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if competitions.isEmpty {
                emptyText("wca.competitions_empty_bookmarked")
                    .padding(.top, 2)
            } else {
                competitionRows(competitions, registrationsByCompetition: [:])
                    .padding(.top, 2)
            }
        }
    }

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
    }

    private func prominentSectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.primary)
    }

    private func disclosureLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
    }

    private func competitionRows(
        _ competitions: [WCAMyCompetitionSummary],
        registrationsByCompetition: [String: String]
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(competitions.enumerated()), id: \.element.id) { index, competition in
                Button {
                    openCompetition(competition)
                } label: {
                    competitionRow(
                        competition,
                        registrationStatus: registrationsByCompetition[competition.id]
                    )
                }
                .buttonStyle(.plain)

                if index < competitions.count - 1 {
                    Divider()
                        .padding(.leading, 2)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func competitionRow(
        _ competition: WCAMyCompetitionSummary,
        registrationStatus: String?
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(competition.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let registrationStatusText = localizedRegistrationStatus(registrationStatus) {
                        Text(registrationStatusText)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(statusColor(for: registrationStatus), in: Capsule())
                    }
                }

                Text(competition.localizedLocation(languageCode: appLanguage))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(competition.localizedDateRange(languageCode: appLanguage))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var emptyUpcomingView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(emptyUpcomingAttributedMessage)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color(red: 60 / 255, green: 110 / 255, blue: 132 / 255))
                .tint(Color(red: 230 / 255, green: 69 / 255, blue: 3 / 255))
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "cubeflow", url.host == "competitions" {
                        requestedIPhoneTab = "competitions"
                        return .handled
                    }
                    openURL(url)
                    return .handled
                })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 17)
        .background(Color(red: 250 / 255, green: 255 / 255, blue: 255 / 255), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(red: 178 / 255, green: 212 / 255, blue: 221 / 255), lineWidth: 1)
        }
    }

    private var emptyUpcomingAttributedMessage: AttributedString {
        let markdown = appLocalizedString("wca.competitions_empty_upcoming_markdown", languageCode: appLanguage)
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("wca.competitions_loading")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func errorCard(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("wca.results_retry") {
                Task {
                    await viewModel.load(forceRefresh: true)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func emptyText(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func openCompetition(_ competition: WCAMyCompetitionSummary) {
        guard let url = competition.officialURL else { return }
        openURL(url)
    }

    private func localizedRegistrationStatus(_ status: String?) -> String? {
        guard let status else { return nil }
        switch status.lowercased() {
        case "accepted":
            return appLocalizedString("wca.competitions_status_accepted", languageCode: appLanguage)
        case "pending":
            return appLocalizedString("wca.competitions_status_pending", languageCode: appLanguage)
        case "waiting_list", "waitlist", "waitlisted":
            return appLocalizedString("wca.competitions_status_waitlisted", languageCode: appLanguage)
        default:
            return nil
        }
    }

    private func statusColor(for status: String?) -> Color {
        switch status?.lowercased() {
        case "accepted":
            return .green
        case "pending":
            return .orange
        case "waiting_list", "waitlist", "waitlisted":
            return .blue
        default:
            return .secondary
        }
    }
}

private struct WCAMyCompetitionsToolbarModifier: ViewModifier {
    let isLoading: Bool
    let profile: WCAUserProfile?
    let refresh: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.modifier(
                WCAMyCompetitionsToolbarWithSpacerModifier(
                    isLoading: isLoading,
                    profile: profile,
                    refresh: refresh
                )
            )
        } else {
            content.modifier(
                WCAMyCompetitionsToolbarDefaultModifier(
                    isLoading: isLoading,
                    profile: profile,
                    refresh: refresh
                )
            )
        }
    }
}

private struct WCAMyCompetitionsToolbarDefaultModifier: ViewModifier {
    let isLoading: Bool
    let profile: WCAUserProfile?
    let refresh: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            wcaCompetitionsRefreshToolbarItem(isLoading: isLoading, refresh: refresh)
            wcaCompetitionsResultsToolbarItem(profile: profile)
        }
    }
}

@available(iOS 26.0, *)
private struct WCAMyCompetitionsToolbarWithSpacerModifier: ViewModifier {
    let isLoading: Bool
    let profile: WCAUserProfile?
    let refresh: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            wcaCompetitionsRefreshToolbarItem(isLoading: isLoading, refresh: refresh)
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            wcaCompetitionsResultsToolbarItem(profile: profile)
        }
    }
}

private func wcaCompetitionsRefreshToolbarItem(
    isLoading: Bool,
    refresh: @escaping () -> Void
) -> ToolbarItem<(), some View> {
    ToolbarItem(placement: .topBarTrailing) {
        Button(action: refresh) {
            if isLoading {
                ProgressView()
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .disabled(isLoading)
    }
}

private func wcaCompetitionsResultsToolbarItem(
    profile: WCAUserProfile?
) -> ToolbarItem<(), some View> {
    ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
            WCAMyResultsView(profile: profile)
        } label: {
            Text("settings.wca_my_results")
        }
    }
}

struct WCAMyCompetitionsPage: Sendable, Codable {
    let futureCompetitions: [WCAMyCompetitionSummary]
    let pastCompetitions: [WCAMyCompetitionSummary]
    let bookmarkedCompetitions: [WCAMyCompetitionSummary]
    let registrationsByCompetition: [String: String]

    enum CodingKeys: String, CodingKey {
        case futureCompetitions = "future_competitions"
        case pastCompetitions = "past_competitions"
        case bookmarkedCompetitions = "bookmarked_competitions"
        case registrationsByCompetition = "registrations_by_competition"
    }
}

struct WCAMyCompetitionSummary: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let website: String?
    let startDate: String?
    let endDate: String?
    let registrationOpen: String?
    let url: String?
    let city: String?
    let countryISO2: String?
    let shortDisplayName: String?
    let registrationStatus: String?

    var displayName: String {
        shortDisplayName?.isEmpty == false ? shortDisplayName! : name
    }

    var officialURL: URL? {
        if let url, !url.isEmpty {
            if url.hasPrefix("http") {
                return URL(string: url)
            }
            return URL(string: "https://www.worldcubeassociation.org\(url.hasPrefix("/") ? "" : "/")\(url)")
        }
        return URL(string: "https://www.worldcubeassociation.org/competitions/\(id)")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case website
        case startDate = "start_date"
        case endDate = "end_date"
        case registrationOpen = "registration_open"
        case url
        case city
        case countryISO2 = "country_iso2"
        case shortDisplayName = "short_display_name"
        case registrationStatus = "registration_status"
    }

    func localizedLocation(languageCode: String) -> String {
        let cityText = city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let countryText = localizedCountryName(languageCode: languageCode)

        if cityText.isEmpty {
            return countryText
        }
        if countryText.isEmpty {
            return cityText
        }
        return "\(cityText), \(countryText)"
    }

    func localizedDateRange(languageCode: String) -> String {
        guard let start = parsedDate(from: startDate) else {
            return startDate ?? ""
        }

        let locale = appLocale(for: languageCode)
        if let end = parsedDate(from: endDate), !Calendar.current.isDate(start, inSameDayAs: end) {
            let formatter = DateIntervalFormatter()
            formatter.locale = locale
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: start, to: end)
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: start)
    }

    private func localizedCountryName(languageCode: String) -> String {
        guard let countryISO2, !countryISO2.isEmpty else { return "" }
        let locale = appLocale(for: languageCode)
        return locale.localizedString(forRegionCode: countryISO2) ?? countryISO2
    }

    private func parsedDate(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

enum WCAMyCompetitionsService {
    static func fetchMyCompetitions(authManager: WCAAuthManager) async throws -> WCAMyCompetitionsPage {
        guard let url = URL(string: "https://www.worldcubeassociation.org/api/v0/competitions/mine") else {
            throw WCAMyCompetitionsFetchError.invalidURL
        }

        var request = try await authManager.authorizedRequest(for: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WCAMyCompetitionsFetchError.requestFailed
        }

        if httpResponse.statusCode == 401 {
            throw WCAMyCompetitionsFetchError.notSignedIn
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw WCAMyCompetitionsFetchError.requestFailed
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(WCAMyCompetitionsPage.self, from: data)
        } catch {
            throw WCAMyCompetitionsFetchError.invalidResponse
        }
    }
}

enum WCAMyCompetitionsFetchError: LocalizedError {
    case invalidURL
    case notSignedIn
    case requestFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return currentAppLocalizedString("wca.competitions_error_request_failed")
        case .notSignedIn:
            return currentAppLocalizedString("wca.competitions_error_sign_in")
        case .requestFailed:
            return currentAppLocalizedString("wca.competitions_error_request_failed")
        case .invalidResponse:
            return currentAppLocalizedString("wca.competitions_error_invalid_response")
        }
    }
}

private struct WCACompetitionGroup: Identifiable {
    let key: String
    let competitionName: String
    let countryISO2: String?
    var results: [WCACompetitionResult]

    var id: String { key }
}

private struct ResultRecordHighlight {
    let single: Bool
    let average: Bool

    static let none = ResultRecordHighlight(single: false, average: false)
}

private func cachedResultsTimestampFormatter(languageCode: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = appLocale(for: languageCode)
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}

private func flagEmoji(for countryCode: String) -> String {
    let uppercased = countryCode.uppercased()
    guard uppercased.count == 2 else { return "" }

    let scalars = uppercased.unicodeScalars.compactMap { scalar -> UnicodeScalar? in
        UnicodeScalar(127397 + scalar.value)
    }

    return String(String.UnicodeScalarView(scalars))
}

private let regionCountryCodeOverrides: [String: String] = [
    "China": "CN",
    "Hong Kong, China": "HK",
    "Macau, China": "MO",
    "Republic of Korea": "KR",
    "Palestine": "PS"
]

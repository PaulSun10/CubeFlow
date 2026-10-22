import SwiftUI

#if os(iOS)
#if DEBUG
private struct CompetitionFilterIsolationKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}
extension EnvironmentValues {
    var competitionFilterIsolation: Set<String> {
        get { self[CompetitionFilterIsolationKey.self] }
        set { self[CompetitionFilterIsolationKey.self] = newValue }
    }
}
#endif
struct CompetitionFiltersMenu: View {
    @Binding var selectedRegion: CompetitionRegionFilter
    @Binding var selectedEvents: Set<CompetitionEventFilter>
    @Binding var selectedYear: CompetitionYearFilter
    @Binding var selectedStatus: CompetitionStatusFilter
    let availablePastYears: [Int]
    @Binding var showsTopCubers: Bool
    let appLanguage: String
    @State private var showsRegionPicker = false
    @State private var showsTopCubersInfo = false
    @State private var areEventIconsReady = CompetitionEventIconFont.isAvailable

    var body: some View {
        Menu {
            Button {
                showsRegionPicker = true
            } label: {
                Text("\(text("competitions.filter.region_country")): \(selectedRegion.localizedTitle(languageCode: appLanguage))")
            }

            Menu(text("competitions.filter.event")) {
                Button {
                    selectedEvents = CompetitionEventFilter.selection(afterToggling: .all, in: selectedEvents)
                } label: {
                    CompetitionFilterOptionLabel(
                        title: CompetitionEventFilter.all.localizedTitle(languageCode: appLanguage),
                        isSelected: selectedEvents == Set(CompetitionEventFilter.selectableCases)
                    )
                }
                Divider()
                ForEach(CompetitionEventFilter.selectableCases) { event in
                    Button {
                        selectedEvents = CompetitionEventFilter.selection(afterToggling: event, in: selectedEvents)
                    } label: {
                        CompetitionFilterOptionLabel(
                            title: event.localizedTitle(languageCode: appLanguage),
                            isSelected: selectedEvents.contains(event),
                            eventID: event.wcaEventID,
                            areEventIconsReady: areEventIconsReady
                        )
                    }
                }
            }
            .compatibleMenuActionDismissBehaviorDisabled()

            Menu(text("competitions.filter.status")) {
                Picker(text("competitions.filter.status"), selection: $selectedStatus) {
                    ForEach(CompetitionStatusFilter.selectableCases) { status in
                        Text(status.localizedTitle(languageCode: appLanguage)).tag(status)
                    }
                }
            }
            if selectedStatus == .past {
                Menu(text("competitions.filter.year")) {
                    Picker(text("competitions.filter.year"), selection: $selectedYear) {
                        Text(CompetitionYearFilter.all.localizedTitle(languageCode: appLanguage))
                            .tag(CompetitionYearFilter.all)
                        ForEach(pastYearOptions, id: \.self) { year in
                            Text(String(year)).tag(CompetitionYearFilter.year(year))
                        }
                    }
                }
            }
            Divider()
            Toggle(text("competitions.filter.show_top_cubers"), isOn: $showsTopCubers)
                .accessibilityIdentifier("competition-filter-top-cubers")
            Button {
                showsTopCubersInfo = true
            } label: {
                Label(text("competitions.filter.show_top_cubers"), systemImage: "info.circle")
            }
            .accessibilityIdentifier("competition-filter-top-cubers-info")
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .accessibilityLabel(text("competitions.filter"))
        .accessibilityIdentifier("competition-filter")
        .sheet(isPresented: $showsRegionPicker) {
            CompetitionRegionPickerView(selectedRegion: $selectedRegion, appLanguage: appLanguage)
        }
        .alert(text("competitions.filter.show_top_cubers"), isPresented: $showsTopCubersInfo) {
            Button(text("common.done"), role: .cancel) { }
        } message: {
            Text(text("competitions.filter.top_cubers_info"))
        }
        .task {
            areEventIconsReady = CompetitionEventIconFont.ensureRegistered()
            await CompetitionService.warmRecognizedCountriesCache()
        }
    }

    private var pastYearOptions: [Int] {
        var years = Set(availablePastYears)
        if case .year(let year) = selectedYear { years.insert(year) }
        return years.sorted(by: >)
    }

    private func text(_ key: String) -> String {
        localizedCompetitionStringInView(key: key, languageCode: appLanguage)
    }
}

extension CompetitionEventFilter {
    // Preserve the original nonempty multi-selection and All semantics.
    static func selection(afterToggling event: Self, in selected: Set<Self>) -> Set<Self> {
        let all = Set(selectableCases)
        if event == .all { return all }
        if selected == all { return [event] }
        var result = selected
        if result.contains(event) { result.remove(event) } else { result.insert(event) }
        return result.isEmpty ? all : result
    }
}

struct CompetitionFiltersPopover: View {
    #if DEBUG
    @Environment(\.competitionFilterIsolation) private var isolation
    #endif
    private var contentAnimation: Animation? {
        #if DEBUG
        if isolation.contains("supplementary-animation") { return nil }
        #endif
        return .easeInOut(duration: 0.22)
    }
    @Binding var selectedRegion: CompetitionRegionFilter
    @Binding var selectedEvents: Set<CompetitionEventFilter>
    @Binding var selectedYear: CompetitionYearFilter
    @Binding var selectedStatus: CompetitionStatusFilter
    let availablePastYears: [Int]
    @Binding var showsTopCubers: Bool
    let appLanguage: String
    @Binding var showsFilterPopover: Bool
    @State private var showsRegionPicker = false
    @State private var showsTopCubersInfo = false
    @State private var areEventIconsReady = CompetitionEventIconFont.isAvailable

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(localizedCompetitionStringInView(key: "competitions.filter", languageCode: appLanguage))
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button {
                    showsFilterPopover = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("competition-filter-close")
            }

            CompetitionFilterButtonRow(
                title: localizedCompetitionStringInView(key: "competitions.filter.region_country", languageCode: appLanguage),
                selectionTitle: selectedRegion.localizedTitle(languageCode: appLanguage)
            ) {
                showsRegionPicker = true
            }

            CompetitionEventMultiSelectSection(
                title: localizedCompetitionStringInView(key: "competitions.filter.event", languageCode: appLanguage),
                selectedEvents: $selectedEvents,
                appLanguage: appLanguage,
                areEventIconsReady: areEventIconsReady
            )

            CompetitionStatusFilterControl(
                title: localizedCompetitionStringInView(key: "competitions.filter.status", languageCode: appLanguage),
                selection: $selectedStatus,
                appLanguage: appLanguage
            )

            if selectedStatus == .past {
                CompetitionFilterMenuRow(
                    title: localizedCompetitionStringInView(key: "competitions.filter.year", languageCode: appLanguage),
                    selectionTitle: selectedYear.localizedTitle(languageCode: appLanguage)
                ) {
                    Button {
                        selectedYear = .all
                    } label: {
                        CompetitionFilterOptionLabel(
                            title: CompetitionYearFilter.all.localizedTitle(languageCode: appLanguage),
                            isSelected: selectedYear == .all
                        )
                    }

                    ForEach(pastYearOptions, id: \.self) { year in
                        Button {
                            selectedYear = .year(year)
                        } label: {
                            CompetitionFilterOptionLabel(
                                title: String(year),
                                isSelected: selectedYear == .year(year)
                            )
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 8) {
                Text(localizedCompetitionStringInView(key: "competitions.filter.show_top_cubers", languageCode: appLanguage))
                    .font(.system(size: 16, weight: .medium))
                Button {
                    showsTopCubersInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(
                    isPresented: $showsTopCubersInfo,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    Text(localizedCompetitionStringInView(key: "competitions.filter.top_cubers_info", languageCode: appLanguage))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .frame(width: 260)
                        .compatiblePopoverCompactAdaptation()
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $showsTopCubers)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(width: 290)
        .animation(contentAnimation, value: selectedStatus)
        .task {
            areEventIconsReady = CompetitionEventIconFont.ensureRegistered()
            await CompetitionService.warmRecognizedCountriesCache()
        }
        .sheet(isPresented: $showsRegionPicker) {
            CompetitionRegionPickerView(
                selectedRegion: $selectedRegion,
                appLanguage: appLanguage
            )
        }
    }

    private var pastYearOptions: [Int] {
        var years = Set(availablePastYears)
        if case .year(let selectedYear) = selectedYear {
            years.insert(selectedYear)
        }
        return years.sorted(by: >)
    }
}

private struct CompetitionStatusFilterControl: View {
    let title: String
    @Binding var selection: CompetitionStatusFilter
    let appLanguage: String
    @Namespace private var selectionIndicator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(CompetitionStatusFilter.selectableCases) { status in
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            selection = status
                        }
                    } label: {
                        Text(status.localizedTitle(languageCode: appLanguage))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selection == status ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background {
                                if selection == status {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(Color.accentColor)
                                        .matchedGeometryEffect(
                                            id: "competition-status-selection",
                                            in: selectionIndicator
                                        )
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == status ? .isSelected : [])
                }
            }
            .padding(3)
            .background(
                Color(uiColor: .secondarySystemFill).opacity(0.56),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
    }
}

struct CompetitionFilterOptionLabel: View {
    let title: String
    let isSelected: Bool
    var eventID: String? = nil
    var areEventIconsReady = true

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                if areEventIconsReady,
                   let eventID,
                   let image = CompetitionEventIconFont.templateImage(
                       for: eventID,
                       title: title,
                       pointSize: 14
                   ) {
                    Image(uiImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.primary)
                        .accessibilityLabel(title)
                }
                Text(title)
            }
            Spacer(minLength: 12)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
            }
        }
    }
}

private struct CompetitionEventMultiSelectSection: View {
    let title: String
    @Binding var selectedEvents: Set<CompetitionEventFilter>
    let appLanguage: String
    let areEventIconsReady: Bool

    private var allSelectableEvents: Set<CompetitionEventFilter> {
        Set(CompetitionEventFilter.selectableCases)
    }

    private var allEventsSelected: Bool {
        selectedEvents == allSelectableEvents
    }

    private var selectionTitle: String {
        if allEventsSelected {
            return CompetitionEventFilter.all.localizedTitle(languageCode: appLanguage)
        }

        if selectedEvents.count == 1, let first = selectedEvents.first {
            return first.localizedTitle(languageCode: appLanguage)
        }

        return String(
            format: localizedCompetitionStringInView(
                key: "competitions.event.selected_count",
                languageCode: appLanguage
            ),
            selectedEvents.count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Menu {
                Button {
                    toggle(.all)
                } label: {
                    CompetitionFilterOptionLabel(
                        title: CompetitionEventFilter.all.localizedTitle(languageCode: appLanguage),
                        isSelected: allEventsSelected
                    )
                }

                Divider()

                ForEach(CompetitionEventFilter.selectableCases) { event in
                    Button {
                        toggle(event)
                    } label: {
                        CompetitionFilterOptionLabel(
                            title: event.localizedTitle(languageCode: appLanguage),
                            isSelected: isSelected(event),
                            eventID: event.wcaEventID,
                            areEventIconsReady: areEventIconsReady
                        )
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectionTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .competitionFilterControlSurface()
            }
            .buttonStyle(.plain)
            .compatibleMenuActionDismissBehaviorDisabled()
        }
    }

    private func isSelected(_ event: CompetitionEventFilter) -> Bool {
        if event == .all {
            return allEventsSelected
        }
        return selectedEvents.contains(event)
    }

    private func toggle(_ event: CompetitionEventFilter) {
        selectedEvents = CompetitionEventFilter.selection(afterToggling: event, in: selectedEvents)
    }
}

private struct CompetitionFilterButtonRow: View {
    let title: String
    let selectionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Button(action: action) {
                HStack(spacing: 8) {
                    Text(selectionTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .competitionFilterControlSurface()
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CompetitionFilterMenuRow<MenuContent: View>: View {
    let title: String
    let selectionTitle: String
    @ViewBuilder let menuContent: () -> MenuContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Menu {
                menuContent()
            } label: {
                HStack(spacing: 8) {
                    Text(selectionTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .competitionFilterControlSurface()
            }
            .buttonStyle(.plain)
        }
    }
}

private extension View {
    func competitionFilterControlSurface() -> some View {
        modifier(CompetitionFilterControlSurface())
    }
}

private struct CompetitionFilterControlSurface: ViewModifier {
    #if DEBUG
    @Environment(\.competitionFilterIsolation) private var isolation
    #endif
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG
        if isolation.contains("visual-layers") { content }
        else { decorated(content) }
        #else
        decorated(content)
        #endif
    }
    private func decorated(_ content: Content) -> some View {
        content.background(
            Color(uiColor: .secondarySystemFill).opacity(0.48),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.24), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct CompetitionRegionPickerView: View {
    private struct CountryOption: Identifiable, Hashable {
        let code: String
        let title: String
        let wcaName: String

        var id: String { code }

        var searchableText: String {
            [title, wcaName, code].joined(separator: " ").lowercased()
        }
    }

    @Binding var selectedRegion: CompetitionRegionFilter
    let appLanguage: String

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var countries: [CountryOption] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredCountries: [CountryOption] {
        guard !normalizedSearchText.isEmpty else {
            return countries
        }

        return countries.filter { country in
            country.searchableText.contains(normalizedSearchText)
        }
    }

    var body: some View {
        CompatibleNavigationContainer {
            List {
                allRegionsSection
                continentSection
                countrySection
            }
            .listStyle(.insetGrouped)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: localizedCompetitionStringInView(
                    key: "competitions.region.search",
                    languageCode: appLanguage
                )
            )
            .navigationTitle(localizedCompetitionStringInView(key: "competitions.filter.region_country", languageCode: appLanguage))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localizedCompetitionStringInView(key: "common.done", languageCode: appLanguage)) {
                        dismiss()
                    }
                }
            }
            .task {
                guard countries.isEmpty else { return }
                isLoading = true
                errorMessage = nil

                do {
                    let recognizedCountries = try await CompetitionService.fetchRecognizedCountries()
                    countries = recognizedCountries.map { country in
                        CountryOption(
                            code: country.code,
                            title: country.localizedTitle(languageCode: appLanguage),
                            wcaName: country.wcaName
                        )
                    }
                } catch {
                    errorMessage = appUserFacingErrorMessage(error, languageCode: appLanguage)
                    countries = []
                }

                isLoading = false
            }
        }
        .compatibleMediumLargeSheet()
    }

    private var allRegionsSection: some View {
        Section {
            regionButton(
                title: CompetitionRegionFilter.all.localizedTitle(languageCode: appLanguage),
                isSelected: selectedRegion == .all
            ) {
                applyRegionSelection(.all)
            }
        }
    }

    private var continentSection: some View {
        Section {
            ForEach(CompetitionContinent.allCases) { continent in
                let option = CompetitionRegionFilter.continent(continent)
                regionButton(
                    title: option.localizedTitle(languageCode: appLanguage),
                    isSelected: selectedRegion == option
                ) {
                    applyRegionSelection(option)
                }
            }
        }
    }

    @ViewBuilder
    private var countrySection: some View {
        Section {
            if isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(localizedCompetitionStringInView(key: "competitions.loading", languageCode: appLanguage))
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredCountries) { country in
                    countryButton(for: country)
                }
            }
        }
    }

    private func countryButton(for country: CountryOption) -> some View {
        let option = CompetitionRegionFilter.country(country.code)

        return Button {
            applyRegionSelection(option)
        } label: {
            HStack(spacing: 12) {
                Text(competitionFlagEmoji(for: country.code))
                CompetitionFilterOptionLabel(
                    title: country.title,
                    isSelected: selectedRegion == option
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func applyRegionSelection(_ region: CompetitionRegionFilter) {
        dismiss()
        DispatchQueue.main.async {
            selectedRegion = region
        }
    }

    private func regionButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            CompetitionFilterOptionLabel(
                title: title,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
    }
}

#endif

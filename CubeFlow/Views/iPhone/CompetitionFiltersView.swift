import SwiftUI

#if os(iOS)
struct CompetitionFiltersPopover: View {
    @Binding var selectedRegion: CompetitionRegionFilter
    @Binding var selectedEvents: Set<CompetitionEventFilter>
    @Binding var selectedYear: CompetitionYearFilter
    @Binding var selectedStatus: CompetitionStatusFilter
    @Binding var showsTopCubers: Bool
    let appLanguage: String
    @Binding var showsFilterPopover: Bool
    @State private var showsRegionPicker = false

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
                appLanguage: appLanguage
            )

            CompetitionFilterMenuRow(
                title: localizedCompetitionStringInView(key: "competitions.filter.year", languageCode: appLanguage),
                selectionTitle: selectedYear.localizedTitle(languageCode: appLanguage)
            ) {
                ForEach(CompetitionYearFilter.allCases) { year in
                    Button {
                        selectedYear = year
                    } label: {
                        CompetitionFilterOptionLabel(
                            title: year.localizedTitle(languageCode: appLanguage),
                            isSelected: selectedYear == year
                        )
                    }
                }
            }

            CompetitionFilterMenuRow(
                title: localizedCompetitionStringInView(key: "competitions.filter.status", languageCode: appLanguage),
                selectionTitle: selectedStatus.localizedTitle(languageCode: appLanguage)
            ) {
                ForEach(CompetitionStatusFilter.selectableCases) { status in
                    Button {
                        selectedStatus = status
                    } label: {
                        CompetitionFilterOptionLabel(
                            title: status.localizedTitle(languageCode: appLanguage),
                            isSelected: selectedStatus == status
                        )
                    }
                }
            }

            Toggle(isOn: $showsTopCubers) {
                Text(localizedCompetitionStringInView(key: "competitions.filter.show_top_cubers", languageCode: appLanguage))
                    .font(.system(size: 16, weight: .medium))
            }
            .toggleStyle(.switch)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(width: 290)
        .task {
            await CompetitionService.warmRecognizedCountriesCache()
        }
        .sheet(isPresented: $showsRegionPicker) {
            CompetitionRegionPickerView(
                selectedRegion: $selectedRegion,
                appLanguage: appLanguage
            )
        }
    }
}

struct CompetitionFilterOptionLabel: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
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
                            isSelected: isSelected(event)
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
        if event == .all {
            selectedEvents = allSelectableEvents
            return
        }

        if allEventsSelected {
            selectedEvents = [event]
            return
        }

        if selectedEvents.contains(event) {
            if selectedEvents.count == 1 {
                selectedEvents = allSelectableEvents
            } else {
                selectedEvents.remove(event)
            }
        } else {
            selectedEvents.insert(event)
        }
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
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CompetitionRegionPickerView: View {
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
                    errorMessage = error.localizedDescription
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

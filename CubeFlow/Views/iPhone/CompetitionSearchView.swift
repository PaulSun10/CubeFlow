import SwiftUI

#if os(iOS)
func localizedCompetitionStringInView(key: String, languageCode: String) -> String {
    appLocalizedString(key, languageCode: languageCode)
}

func competitionFlagEmoji(for countryCode: String) -> String {
    guard countryCode.count == 2 else { return "" }

    let regionalIndicatorBase: UInt32 = 127397
    let scalars = countryCode.uppercased().unicodeScalars.compactMap { scalar in
        UnicodeScalar(regionalIndicatorBase + scalar.value)
    }
    return String(String.UnicodeScalarView(scalars))
}


struct CompetitionSearchView: View {
    let competitions: [CompetitionSummary]
    let appLanguage: String

    @State private var searchText = ""

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredCompetitions: [CompetitionSummary] {
        guard !normalizedSearchText.isEmpty else { return competitions }

        return competitions.filter { competition in
            let haystack = [
                competition.name,
                competition.locationLine,
                competition.venueLine
            ]
            .joined(separator: " ")
            .lowercased()

            return haystack.contains(normalizedSearchText)
        }
    }

    var body: some View {
        List {
            if normalizedSearchText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizedCompetitionStringInView(key: "competitions.search.empty_query_title", languageCode: appLanguage))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(localizedCompetitionStringInView(key: "competitions.search.empty_query_body", languageCode: appLanguage))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else if filteredCompetitions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizedCompetitionStringInView(key: "competitions.search.no_results_title", languageCode: appLanguage))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(localizedCompetitionStringInView(key: "competitions.search.no_results_body", languageCode: appLanguage))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredCompetitions) { competition in
                    NavigationLink {
                        CompetitionDetailView(
                            competition: competition,
                            appLanguage: appLanguage
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text(competitionFlagEmoji(for: competition.countryISO2))
                                            .font(.system(size: 18))
                                        Text(competition.name)
                                            .font(.system(size: 18, weight: .semibold))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Text(competition.locationLine)
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 12)
                            }

                            if !competition.venueLine.isEmpty {
                                Text(competition.venueLine)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
        }
        .listStyle(.plain)
        .compatibleScrollContentBackgroundHidden()
        .navigationTitle(Text(localizedCompetitionStringInView(key: "competitions.search_title", languageCode: appLanguage)))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(localizedCompetitionStringInView(key: "competitions.search_placeholder", languageCode: appLanguage))
        )
    }
}

#endif

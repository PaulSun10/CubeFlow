import Foundation

nonisolated enum CompetitionNameScript {
    static func display(_ name: String, language: String) -> String {
        let transform: String
        if language.hasPrefix("zh-Hant") || language.hasPrefix("zh_TW") { transform = "Hans-Hant" }
        else if language.hasPrefix("zh") { transform = "Hant-Hans" }
        else { return name }
        return name.applyingTransform(StringTransform(transform), reverse: false) ?? name
    }
}

nonisolated enum WCARegionPresentation {
    // WCA lib/static_data/countries.fictive.json (not ISO country codes).
    static let specialRegions = ["XA": "Asia", "XE": "Europe", "XF": "Africa", "XM": "Americas",
        "XN": "North America", "XO": "Oceania", "XS": "South America", "XW": "World"]
    static func name(_ code: String, language: String) -> String {
        let code = code.uppercased()
        if let region = specialRegions[code] {
            return appLocalizedString("wca.region.multiple", languageCode: language)
                + " (" + appLocalizedString("wca.region.\(region)", languageCode: language) + ")"
        }
        return appLocale(for: language).localizedString(forRegionCode: code) ?? code
    }
}

nonisolated enum WCAOfficialParticipation {
    static func competitionIDs(page: WCAPersonResultsPage, wcaID: String) -> Set<String> {
        guard WCAPublicProfileCache.canonicalID(page.summary.wcaId) == WCAPublicProfileCache.canonicalID(wcaID),
              WCAPublicProfileCache.canonicalID(wcaID) != nil else { return [] }
        return Set(page.resultsSections.flatMap(\.results).compactMap { result in
            guard let path = result.competitionPath, let url = URL(string: path),
                  url.host == nil || ["www.worldcubeassociation.org", "worldcubeassociation.org"].contains(url.host?.lowercased() ?? "") else { return nil }
            let parts = url.path.split(separator: "/")
            guard parts.count >= 2, parts[0] == "competitions" else { return nil }
            return String(parts[1])
        })
    }
}

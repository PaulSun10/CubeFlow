import Foundation

struct AppCacheReport: Sendable, Hashable {
    let competitionListBytes: Int64
    let competitionLocalizedNamesBytes: Int64
    let competitionTopCubersBytes: Int64
    let recognizedCountriesBytes: Int64
    let wcaResultsBytes: Int64

    static let empty = AppCacheReport(
        competitionListBytes: 0,
        competitionLocalizedNamesBytes: 0,
        competitionTopCubersBytes: 0,
        recognizedCountriesBytes: 0,
        wcaResultsBytes: 0
    )

    var competitionSupportBytes: Int64 {
        competitionLocalizedNamesBytes + recognizedCountriesBytes
    }

    var totalBytes: Int64 {
        competitionListBytes + competitionSupportBytes + competitionTopCubersBytes + wcaResultsBytes
    }
}

enum AppCacheManager {
    nonisolated private static var cacheDirectory: URL {
        let baseDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseDirectory.appendingPathComponent("CubeFlow", isDirectory: true)
    }

    nonisolated private static func cacheFileURL(_ filename: String) -> URL {
        cacheDirectory.appendingPathComponent(filename)
    }

    nonisolated static func currentReport() -> AppCacheReport {
        AppCacheReport(
            competitionListBytes: fileSize(for: cacheFileURL("competition-query-cache-v2.json")),
            competitionLocalizedNamesBytes: fileSize(for: cacheFileURL("competition-localized-names-v6.json")),
            competitionTopCubersBytes: fileSize(for: cacheFileURL("competition-top-cubers-cache-v1.json")),
            recognizedCountriesBytes: fileSize(for: cacheFileURL("competition-recognized-countries.json")),
            wcaResultsBytes: fileSize(for: cacheFileURL("wca-person-results-cache-v1.json"))
        )
    }

    static func clearCompetitionListCache() async {
        await CompetitionService.clearCompetitionListCache()
        URLCache.shared.removeAllCachedResponses()
    }

    static func clearCompetitionSupportCache() async {
        await CompetitionService.clearCompetitionSupportCache()
        URLCache.shared.removeAllCachedResponses()
    }

    static func clearCompetitionDetailCache() async {
        await CompetitionService.clearCompetitionDetailCache()
    }

    static func clearCompetitionTopCubersCache() async {
        await CompetitionService.clearCompetitionTopCubersCache()
    }

    static func clearWCAResultsCache() async {
        await WCAResultsService.clearPersonResultsCache()
        URLCache.shared.removeAllCachedResponses()
    }

    static func clearAllCaches() async {
        await CompetitionService.clearAllCompetitionCaches()
        await WCAResultsService.clearAllCaches()
        URLCache.shared.removeAllCachedResponses()
    }

    nonisolated static func formattedSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    nonisolated private static func fileSize(for url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }
}

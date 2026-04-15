import Foundation

enum SolveMetrics {
    nonisolated static func formatTime(_ seconds: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", seconds)
    }

    nonisolated static func formatAverage(_ seconds: Double?) -> String {
        guard let seconds else { return currentAppLocalizedString("common.not_available") }
        if seconds.isNaN { return currentAppLocalizedString("common.dnf") }
        return String(format: "%.2f", seconds)
    }

    @MainActor
    static func adjustedTime(for solve: Solve) -> Double? {
        switch solve.result {
        case .solved:
            return solve.time
        case .plusTwo:
            return solve.time + 2
        case .dnf:
            return nil
        }
    }

    nonisolated static func adjustedTime(for solve: SessionSolveSample) -> Double? {
        switch SolveResult(rawValue: solve.resultRaw) ?? .solved {
        case .solved:
            return solve.time
        case .plusTwo:
            return solve.time + 2
        case .dnf:
            return nil
        }
    }

    @MainActor
    static func displayTime(for solve: Solve, decimals: Int = 3) -> String {
        switch solve.result {
        case .solved:
            return formatTime(solve.time, decimals: decimals)
        case .plusTwo:
            return "\(formatTime(solve.time + 2, decimals: decimals))+"
        case .dnf:
            return currentAppLocalizedString("common.dnf")
        }
    }

    nonisolated static func displayTime(for solve: SessionSolveSample, decimals: Int = 3) -> String {
        switch SolveResult(rawValue: solve.resultRaw) ?? .solved {
        case .solved:
            return formatTime(solve.time, decimals: decimals)
        case .plusTwo:
            return "\(formatTime(solve.time + 2, decimals: decimals))+"
        case .dnf:
            return currentAppLocalizedString("common.dnf")
        }
    }

    nonisolated static func displayDate(_ date: Date, languageCode: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLocale(for: languageCode)
        formatter.dateFormat = appLocalizedString("common.date_format", languageCode: languageCode)
        return formatter.string(from: date)
    }

    @MainActor
    static func trimmedAverage(from solves: [Solve], count: Int) -> Double? {
        guard solves.count >= count else { return nil }
        return averageValue(from: Array(solves.prefix(count)), trimmingCount: 1)
    }

    @MainActor
    static func averageValue(from solves: [Solve], trimmingCount: Int) -> Double? {
        averageValue(
            adjustedTimes: solves.map { adjustedTime(for: $0) },
            trimmingCount: trimmingCount
        )
    }

    nonisolated static func averageValue(from solves: [SessionSolveSample], trimmingCount: Int) -> Double? {
        averageValue(
            adjustedTimes: solves.map { adjustedTime(for: $0) },
            trimmingCount: trimmingCount
        )
    }

    @MainActor
    static func percentageTrimmedAverage(from solves: [Solve], percentage: Double) -> Double? {
        let trimmingCount = Int(Double(solves.count) * percentage)
        return averageValue(from: solves, trimmingCount: trimmingCount)
    }

    nonisolated static func percentageTrimmedAverage(from solves: [SessionSolveSample], percentage: Double) -> Double? {
        let trimmingCount = Int(Double(solves.count) * percentage)
        return averageValue(from: solves, trimmingCount: trimmingCount)
    }

    @MainActor
    static func sessionMean(from solves: [Solve]) -> Double? {
        let validTimes = solves.compactMap { adjustedTime(for: $0) }
        guard !validTimes.isEmpty else { return nil }
        let total = validTimes.reduce(0, +)
        return total / Double(validTimes.count)
    }

    nonisolated private static func averageValue(adjustedTimes: [Double?], trimmingCount: Int) -> Double? {
        guard !adjustedTimes.isEmpty else { return nil }
        guard trimmingCount >= 0, trimmingCount * 2 < adjustedTimes.count else { return nil }

        let ranked = adjustedTimes
            .map { adjusted -> (Double, Bool) in
                if let adjusted {
                    return (adjusted, false)
                }
                return (Double.greatestFiniteMagnitude, true)
            }
            .sorted { $0.0 < $1.0 }

        let trimmed = ranked.dropFirst(trimmingCount).dropLast(trimmingCount)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains(where: \.1) {
            return Double.nan
        }

        let total = trimmed.reduce(0) { $0 + $1.0 }
        return total / Double(trimmed.count)
    }
}

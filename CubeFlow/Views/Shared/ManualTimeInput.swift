import Foundation

enum ManualInputInterface: String, CaseIterable {
    case keyboard, keypad
    var key: String { "manual.interface.\(rawValue)" }
}

enum ManualTimeInterpretation: String, CaseIterable {
    case fixed, smart
    var key: String { "manual.interpretation.\(rawValue)" }
}

enum ManualTimePrecision: Int, CaseIterable {
    case hundredths = 2, milliseconds = 3
    var key: String { "manual.precision.\(rawValue)" }
}

enum ManualTimeFormat: String, CaseIterable {
    case seconds = "X", seconds2 = "X.XX", seconds3 = "X.XXX"
    case minutes = "X:XX", minutes2 = "X:XX.XX", minutes3 = "X:XX.XXX"
    case hours = "X:XX:XX", hours2 = "X:XX:XX.XX", hours3 = "X:XX:XX.XXX"

    static let defaultFormat = ManualTimeFormat.hours3

    var decimals: Int { rawValue.split(separator: ".").dropFirst().first?.count ?? 0 }
    var fields: Int { rawValue.split(separator: ":").count }
}

struct ManualTimeCandidate: Equatable, Identifiable {
    let seconds: Double
    let decimals: Int
    var id: Int { decimals }
    // Inputs are exact decimal ticks, not measured durations. Avoid truncating
    // one tick when binary floating-point multiplication lands one ULP low.
    var display: String { SolveMetrics.formatTime(seconds.nextUp, decimals: decimals) }
}

/// Pure, bounded parsing. The leading X is variable-width (at most nine digits);
/// lower minute/second fields are base 60, never normalized through overflow.
enum ManualTimeParser {
    static func candidates(_ raw: String, mode: ManualTimeInterpretation, format: ManualTimeFormat) -> [ManualTimeCandidate] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 18,
              text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ":") }) else { return [] }
        if text.contains(".") || text.contains(":") {
            return explicit(text).map { [$0] } ?? []
        }
        if mode == .fixed {
            // The default clock format retains the familiar short hundredths entry.
            let shortClock = format == .hours3 && text.count <= 3
            return grouped(text, fields: shortClock ? 1 : format.fields,
                           decimals: shortClock ? 2 : format.decimals).map { [$0] } ?? []
        }
        if text.count <= 3 { return grouped(text, fields: 1, decimals: 2).map { [$0] } ?? [] }
        return [2, 3].compactMap { decimals in
            let wholeCount = max(0, text.count - decimals)
            return grouped(text, fields: wholeCount > 4 ? 3 : wholeCount > 2 ? 2 : 1, decimals: decimals)
        }
    }

    static func preferred(_ candidates: [ManualTimeCandidate], reference: Double?, defaultPrecision: ManualTimePrecision,
                          override: Int?) -> ManualTimeCandidate? {
        if let override, let selected = candidates.first(where: { $0.id == override }) { return selected }
        guard candidates.count > 1 else { return candidates.first }
        let fallback = candidates.first(where: { $0.decimals == defaultPrecision.rawValue }) ?? candidates[0]
        guard let reference, reference.isFinite, reference > 0 else { return fallback }
        let ranked = candidates.sorted { abs(log(max($0.seconds, 0.0001) / reference)) < abs(log(max($1.seconds, 0.0001) / reference)) }
        // If relative-distance scores differ by less than 15%, prefer the
        // user's configured precision instead of an unstable near-tie.
        let first = abs(log(max(ranked[0].seconds, 0.0001) / reference))
        let second = abs(log(max(ranked[1].seconds, 0.0001) / reference))
        return second - first <= log(1.15) ? fallback : ranked[0]
    }

    static func reference(current: [SessionSolveSample], historical: [SessionSolveSample], event: String) -> Double? {
        func median(_ samples: [SessionSolveSample]) -> Double? {
            var recent: [SessionSolveSample] = []
            for sample in samples where sample.eventRawValue == event {
                guard sample.time.isFinite, sample.time > 0, SolveResult(rawValue: sample.resultRaw) != nil,
                      let value = sample.adjustedTime, value.isFinite, value > 0 else { continue }
                let position = recent.firstIndex { $0.date < sample.date } ?? recent.count
                if position < 20 { recent.insert(sample, at: position); if recent.count > 20 { recent.removeLast() } }
            }
            let values = recent.compactMap(\.adjustedTime).sorted()
            guard !values.isEmpty else { return nil }
            let middle = values.count / 2
            return values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
        }
        return median(current) ?? median(historical)
    }

    private static func explicit(_ text: String) -> ManualTimeCandidate? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), let last = parts.last else { return nil }
        let secondParts = last.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(secondParts.count), !secondParts[0].isEmpty || secondParts.count == 2,
              secondParts[0].count <= 9,
              let seconds = secondParts[0].isEmpty ? 0 : Double(secondParts[0]) else { return nil }
        let decimals = secondParts.count == 2 ? secondParts[1].count : 0
        guard secondParts.count == 1 || (1...9).contains(decimals) else { return nil }
        let fraction = secondParts.count == 2 ? (Double(secondParts[1]) ?? -1) / pow(10, Double(decimals)) : 0
        guard fraction >= 0, parts.count == 1 || seconds < 60 else { return nil }
        var value = seconds + fraction
        for (index, part) in parts.dropLast().enumerated() {
            guard !part.isEmpty, part.count <= (index == 0 ? 9 : 2),
                  part.allSatisfy(\.isNumber), let number = Double(part), index == 0 || number < 60 else { return nil }
            value += number * pow(60, Double(parts.count - index - 1))
        }
        return ManualTimeCandidate(seconds: value, decimals: decimals)
    }

    private static func grouped(_ text: String, fields: Int, decimals: Int) -> ManualTimeCandidate? {
        var digits = text
        let fractionDigits = min(decimals, digits.count)
        let fraction = decimals == 0 ? 0 : (Double(digits.suffix(fractionDigits)) ?? 0) / pow(10, Double(decimals))
        if fractionDigits > 0 { digits.removeLast(fractionDigits) }
        var total = fraction
        for field in 0..<fields {
            let width = field == fields - 1 ? digits.count : min(2, digits.count)
            guard width <= (field == fields - 1 ? 9 : 2) else { return nil }
            let number = width == 0 ? 0 : Double(digits.suffix(width)) ?? -1
            guard number >= 0, field == fields - 1 || number < 60 else { return nil }
            total += number * pow(60, Double(field))
            if width > 0 { digits.removeLast(width) }
        }
        return ManualTimeCandidate(seconds: total, decimals: decimals)
    }
}

struct ManualTimeDraft {
    var raw = ""
    var override: Int?
    private(set) var savedRequestID: UUID?

    mutating func edit(_ text: String) {
        raw = text
        if text.isEmpty { override = nil }
    }
    mutating func consume(requestID: UUID) -> Bool {
        guard savedRequestID != requestID else { return false }
        savedRequestID = requestID
        raw = ""; override = nil
        return true
    }
}

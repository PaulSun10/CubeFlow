import SwiftUI

struct AlgExactProbability: Decodable, Hashable {
    let numerator: Int
    let denominator: Int

    var value: Double? {
        guard denominator > 0, numerator >= 0, numerator <= denominator else { return nil }
        return Double(numerator) / Double(denominator)
    }

    var reduced: (Int, Int)? {
        guard value != nil else { return nil }
        var a = numerator, b = denominator
        while b != 0 { (a, b) = (b, a % b) }
        return (numerator / a, denominator / a)
    }
}

enum AlgProbabilityPresentation {
    static func text(exact: AlgExactProbability?, approximate: Double?, locale: Locale = .current) -> String? {
        guard let value = exact?.value ?? approximate, value.isFinite, (0...1).contains(value) else { return nil }
        let percent = NumberFormatter()
        percent.locale = locale
        percent.numberStyle = .percent
        percent.maximumSignificantDigits = 3
        percent.minimumSignificantDigits = 1
        guard let percentage = percent.string(from: NSNumber(value: value)) else { return nil }
        guard let (a, b) = exact?.reduced else { return "\u{2248}" + percentage }
        let integer = NumberFormatter()
        integer.locale = locale
        integer.numberStyle = .decimal
        integer.maximumFractionDigits = 0
        return "\(integer.string(from: NSNumber(value: a)) ?? String(a))/\(integer.string(from: NSNumber(value: b)) ?? String(b)) \u{00B7} \(percentage)"
    }
}

struct AlgProbabilityLabel: View {
    let algCase: AlgCase
    @AppStorage("appLanguage") private var languageCode = "en"

    var body: some View {
        if let text = AlgProbabilityPresentation.text(exact: algCase.probabilityExact,
            approximate: algCase.probability, locale: Locale(identifier: languageCode)) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 126, alignment: .trailing)
                .accessibilityLabel(Text("algs.probability") + Text(": " + text))
        }
    }
}

import SwiftUI

enum SolveTimeAccuracy: String, CaseIterable, Identifiable, Sendable {
    case hundredths
    case thousandths

    var id: String { rawValue }

    var decimals: Int {
        switch self {
        case .hundredths: 2
        case .thousandths: 3
        }
    }

    static func resolved(from rawValue: String) -> SolveTimeAccuracy {
        SolveTimeAccuracy(rawValue: rawValue) ?? .thousandths
    }
}

private struct SolveTimeAccuracyEnvironmentKey: EnvironmentKey {
    static let defaultValue = SolveTimeAccuracy.thousandths
}

extension EnvironmentValues {
    var solveTimeAccuracy: SolveTimeAccuracy {
        get { self[SolveTimeAccuracyEnvironmentKey.self] }
        set { self[SolveTimeAccuracyEnvironmentKey.self] = newValue }
    }
}

import Foundation

nonisolated enum DiagramStrokeStyle: String, CaseIterable, Identifiable, Sendable {
    case thin
    // Keep the old stored value for the accepted 1.6x appearance.
    case medium = "thick"
    case thick = "heavy"
    var id: String { rawValue }
    var scale: Double {
        switch self { case .thin: 1; case .medium: 1.6; case .thick: 2.6 }
    }
    var localizationKey: String {
        switch self {
        case .thin: "settings.diagram_stroke_thin"
        case .medium: "settings.diagram_stroke_medium"
        case .thick: "settings.diagram_stroke_thick"
        }
    }
}

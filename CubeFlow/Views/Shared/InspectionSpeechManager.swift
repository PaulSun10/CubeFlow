import Foundation
import SwiftUI

@MainActor
final class InspectionSpeechManager {
    static let shared = InspectionSpeechManager()

    private init() {}

    func speakCheckpoint(_ checkpoint: InspectionSpeechCheckpoint, languageCode: String, voiceMode: String) {
        // Placeholder for future custom audio playback. Intentionally a no-op
        // until mp3 inspection prompts are added.
        _ = checkpoint
        _ = languageCode
        _ = voiceMode
    }
}

enum InspectionSpeechCheckpoint: Hashable {
    case eight
    case twelve
    case plusTwo
    case dnf

    func spokenText(languageCode: String) -> String {
        switch self {
        case .eight:
            return appLocalizedString("inspection.speech.eight_seconds", languageCode: languageCode)
        case .twelve:
            return appLocalizedString("inspection.speech.twelve_seconds", languageCode: languageCode)
        case .plusTwo:
            return appLocalizedString("inspection.speech.plus_two", languageCode: languageCode)
        case .dnf:
            return appLocalizedString("inspection.speech.dnf", languageCode: languageCode)
        }
    }
}

enum InspectionAlertVoiceMode: String, CaseIterable, Identifiable {
    case off
    case male
    case female
    case mixed

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .off: "settings.inspection_alert_off"
        case .male: "settings.inspection_alert_male"
        case .female: "settings.inspection_alert_female"
        case .mixed: "settings.inspection_alert_mixed"
        }
    }
}

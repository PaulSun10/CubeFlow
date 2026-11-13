#if os(iOS)
import XCTest
import SwiftUI
@testable import CubeFlow

@MainActor final class TimerScramblePositionTests: XCTestCase {
    func testAbsentPreferenceUsesQuarterTravelWithoutWritingADefault() throws {
        let name = "TimerScramblePositionTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let position = AppStorage(wrappedValue: TimerCustomizationDefaults.scrambleVerticalPosition,
            "timerScrambleVerticalPosition", store: defaults)
        XCTAssertEqual(position.wrappedValue, 0.25)
        XCTAssertNil(defaults.object(forKey: "timerScrambleVerticalPosition"))
        XCTAssertEqual(TimerArrangementLayout.scrambleTop(availableHeight: 300,
            contentHeight: 100, normalizedPosition: position.wrappedValue), 50)
    }

    func testExplicitPreferencesSurviveAndRemovingPreferenceRestoresDefault() throws {
        let name = "TimerScramblePositionTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        for stored in [0.0, 0.25, 0.63, 1.0] {
            defaults.set(stored, forKey: "timerScrambleVerticalPosition")
            let position = AppStorage(wrappedValue: TimerCustomizationDefaults.scrambleVerticalPosition,
                "timerScrambleVerticalPosition", store: defaults)
            XCTAssertEqual(position.wrappedValue, stored)
            XCTAssertEqual(Double(TimerArrangementLayout.normalizedScramblePosition(position.wrappedValue)) * 100,
                stored * 100, accuracy: 0.001)
        }
        defaults.removeObject(forKey: "timerScrambleVerticalPosition")
        let reset = AppStorage(wrappedValue: TimerCustomizationDefaults.scrambleVerticalPosition,
            "timerScrambleVerticalPosition", store: defaults)
        XCTAssertEqual(reset.wrappedValue, 0.25)
    }

    func testSettingsAndTimerUseTheSameDefaultWithoutPreferenceRegistrationOrMigration() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for name in ["SettingsTabView", "TimerTabView"] {
            let source = try String(contentsOf: root.appendingPathComponent("CubeFlow/Views/iPhone/\(name).swift"), encoding: .utf8)
            XCTAssertTrue(source.contains("@AppStorage(\"timerScrambleVerticalPosition\") private var timerScrambleVerticalPosition: Double = TimerCustomizationDefaults.scrambleVerticalPosition"))
        }
    }
}
#endif

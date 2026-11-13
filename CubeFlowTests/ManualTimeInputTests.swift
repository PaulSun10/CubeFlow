import XCTest
@testable import CubeFlow

@MainActor final class ManualTimeInputTests: XCTestCase {
    private func value(_ raw: String, _ format: ManualTimeFormat) -> Double? {
        ManualTimeParser.candidates(raw, mode: .fixed, format: format).first?.seconds
    }
    func testAllNineFixedFormatsAndShortZeroPaddedInput() throws {
        let examples: [(ManualTimeFormat, String, Double)] = [
            (.seconds, "921", 921), (.seconds2, "921", 9.21), (.seconds3, "921", 0.921),
            (.minutes, "123", 83), (.minutes2, "12345", 83.45), (.minutes3, "123456", 83.456),
            (.hours, "12345", 5025), (.hours2, "1234567", 5025.67), (.hours3, "12345678", 5025.678)]
        XCTAssertEqual(examples.count, ManualTimeFormat.allCases.count)
        for (format, raw, expected) in examples {
            XCTAssertEqual(try XCTUnwrap(value(raw, format)), expected, accuracy: 0.000001, format.rawValue)
            XCTAssertEqual(value("000" + raw, format), value(raw, format))
            XCTAssertEqual(try XCTUnwrap(value("1", format)), 1 / pow(10, Double(format == .hours3 ? 2 : format.decimals)), accuracy: 0.000001)
        }
    }
    func testDefaultClockFormatShortInputsAndStoredChoiceIsolation() throws {
        XCTAssertEqual(ManualTimeFormat.defaultFormat, .hours3)
        for (raw, expected) in [("921", 9.21), ("6789", 6.789), ("110013", 70.013), ("123456789", 45296.789)] {
            XCTAssertEqual(try XCTUnwrap(value(raw, .defaultFormat)), expected, accuracy: 0.000001)
        }
        XCTAssertEqual(value("921", .seconds), 921, "Explicitly selected compatibility format is unchanged")
        XCTAssertEqual(value("921", .seconds3), 0.921)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(ManualTimeFormat.seconds.rawValue, forKey: "manualTimeFormat")
        XCTAssertEqual(ManualTimeFormat(rawValue: defaults.string(forKey: "manualTimeFormat") ?? ManualTimeFormat.defaultFormat.rawValue), .seconds)
    }
    func testFixedBoundariesRejectOverflowInsteadOfChangingFormat() {
        XCTAssertEqual(value("159", .minutes), 119)
        XCTAssertNil(value("160", .minutes)); XCTAssertNil(value("126000", .hours))
        XCTAssertNil(value("6000", .minutes2)); XCTAssertNil(value("1000000000", .seconds))
        XCTAssertEqual(value("0", .hours3), 0)
        for format in ManualTimeFormat.allCases { XCTAssertNil(value("", format)) }
    }
    func testExplicitSeparatorsOverrideBothModesWithoutTruncating() throws {
        for mode in ManualTimeInterpretation.allCases {
            for format in ManualTimeFormat.allCases {
                XCTAssertEqual(try XCTUnwrap(ManualTimeParser.candidates("1:10.013", mode: mode, format: format).first?.seconds), 70.013, accuracy: 0.000001)
                XCTAssertEqual(ManualTimeParser.candidates("9.21", mode: mode, format: format).first?.seconds, 9.21)
            }
        }
        for raw in ["1.001", "1.009", "9.210", "1:01.001", "1:10.013"] {
            let result = try XCTUnwrap(ManualTimeParser.candidates(raw, mode: .smart, format: .seconds).first)
            XCTAssertEqual(result.display, raw)
        }
        XCTAssertEqual(value(".5", .seconds), 0.5)
        XCTAssertEqual(value("1:.5", .seconds), 60.5)
        XCTAssertEqual(value("1.2345", .seconds), 1.2345, "Explicit seconds retain legacy precision")
        for raw in [".", "1:", ":2", "1::2", "1:60", "1:60:00", "1.2.3", "1:2:3:4", "-1", "nan", "inf", "1e3", "1.1234567890", " 1 2 "] {
            XCTAssertTrue(ManualTimeParser.candidates(raw, mode: .smart, format: .seconds).isEmpty, raw)
        }
    }
    func testSmartShortInputsAndMinuteHourCandidates() throws {
        for (raw, expected) in [("1", 0.01), ("92", 0.92), ("921", 9.21)] {
            let candidates = ManualTimeParser.candidates(raw, mode: .smart, format: .hours3)
            XCTAssertEqual(candidates.count, 1); XCTAssertEqual(candidates[0].seconds, expected)
        }
        XCTAssertEqual(ManualTimeParser.candidates("3512", mode: .smart, format: .seconds).map(\.seconds), [35.12, 3.512])
        XCTAssertEqual(ManualTimeParser.candidates("9210", mode: .smart, format: .seconds).map(\.seconds), [92.10, 9.210])
        let long = ManualTimeParser.candidates("110013", mode: .smart, format: .seconds)
        XCTAssertEqual(long.map(\.seconds), [660.13, 70.013])
        XCTAssertEqual(try XCTUnwrap(ManualTimeParser.candidates("123456789", mode: .smart, format: .seconds).first?.seconds), 45296.789, accuracy: 0.000001)
    }
    func testSmartRanksByRelevantHistoryAndDeterministicFallback() {
        func pick(_ raw: String, _ reference: Double?, _ precision: ManualTimePrecision = .hundredths) -> Double? {
            ManualTimeParser.preferred(ManualTimeParser.candidates(raw, mode: .smart, format: .seconds), reference: reference, defaultPrecision: precision, override: nil)?.seconds
        }
        XCTAssertEqual(pick("9982", 9), 9.982); XCTAssertEqual(pick("3982", 40), 39.82)
        XCTAssertEqual(pick("3512", nil), 35.12); XCTAssertEqual(pick("3512", nil, .milliseconds), 3.512)
        XCTAssertEqual(pick("3512", sqrt(35.12 * 3.512), .milliseconds), 3.512)
    }
    func testReferenceSessionEventIsolationPlusTwoDNFAndLatestTwenty() {
        func sample(_ value: Double, event: String = "3x3", result: String = "solved", date: Double = 1) -> SessionSolveSample {
            .init(id: UUID(), date: Date(timeIntervalSince1970: date), time: value, resultRaw: result, scramble: "", comment: "", eventRawValue: event)
        }
        let current = [sample(7, result: "plusTwo"), sample(1, result: "dnf"), sample(100, event: "2x2")]
        let history = [sample(40)]
        XCTAssertEqual(ManualTimeParser.reference(current: current, historical: history, event: "3x3"), 9)
        XCTAssertEqual(ManualTimeParser.reference(current: current, historical: history, event: "4x4"), nil)
        XCTAssertEqual(ManualTimeParser.reference(current: [], historical: history, event: "3x3"), 40)
        let many = (0..<50).map { sample(Double($0), date: Double($0)) }
        XCTAssertEqual(ManualTimeParser.reference(current: many, historical: [], event: "3x3"), 39.5)
    }
    func testManualOverrideSurvivesEditsAndAuthoritativeValueIsConsumedOnlyOnce() {
        var draft = ManualTimeDraft(); draft.edit("3512"); draft.override = 3
        draft.edit("9210")
        let candidates = ManualTimeParser.candidates(draft.raw, mode: .smart, format: .seconds)
        XCTAssertEqual(ManualTimeParser.preferred(candidates, reference: 90, defaultPrecision: .hundredths, override: draft.override)?.seconds, 9.21)
        draft.edit("921"); XCTAssertEqual(draft.override, 3)
        draft.edit("9210"); XCTAssertEqual(draft.override, 3)
        let id = UUID(); XCTAssertTrue(draft.consume(requestID: id)); XCTAssertFalse(draft.consume(requestID: id))
        XCTAssertEqual(draft.raw, ""); XCTAssertNil(draft.override)
        XCTAssertTrue(draft.consume(requestID: UUID()))
    }
}

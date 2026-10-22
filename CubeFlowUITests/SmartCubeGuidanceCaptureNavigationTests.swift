import XCTest

final class GuidanceCaptureSettingsAcceptanceTests: XCTestCase {
    @MainActor func testDevelopmentCaptureRetainsStoppedRecordingAcrossSettingsAndTimerTabs() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "settings", "-appLanguage", "en"]
        app.launch(); defer { app.terminate() }
        app.tabBars.buttons["Settings"].tap()
        let debug = app.switches["debug-mode"]
        for _ in 0..<16 {
            if debug.exists && debug.isHittable { break }
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(debug.isHittable, app.debugDescription)
        if debug.value as? String == "1" { debug.coordinate(withNormalizedOffset: .init(dx: 0.92, dy: 0.5)).tap() }
        let link = app.buttons["guidance-capture-navigation"]
        XCTAssertTrue(link.isHittable, app.debugDescription)
        link.tap()
        let record = app.switches["guidance-capture-record"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        func toggleRecording() {
            // Form exposes the whole labelled row as a Switch. Tap the actual
            // trailing native switch, not the centre of the label's AX frame.
            print("[GuidanceToggle] frame=\(record.frame) value=\(String(describing: record.value))")
            record.coordinate(withNormalizedOffset: .init(dx: 1, dy: 0.5))
                .withOffset(.init(dx: -26, dy: 0)).tap()
        }
        if record.value as? String == "1" { toggleRecording() }
        app.buttons["Clear Guidance Capture"].tap()
        let copy = app.buttons["smart-cube-copy-guidance-diagnostics"]
        XCTAssertFalse(copy.isEnabled)
        toggleRecording()
        XCTAssertTrue(record.waitForExistence(timeout: 2))
        XCTAssertEqual(record.value as? String, "1", app.debugDescription)
        app.tabBars.buttons["Timer"].tap()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertEqual(record.value as? String, "1")
        toggleRecording()
        XCTAssertEqual(record.value as? String, "0")
        XCTAssertTrue(copy.isEnabled)
        copy.tap()
        XCTAssertEqual(copy.value as? String, "Copied")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Real Settings Development Guidance Capture"; attachment.lifetime = .keepAlways; add(attachment)
    }
}

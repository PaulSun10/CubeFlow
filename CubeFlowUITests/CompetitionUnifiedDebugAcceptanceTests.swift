import XCTest

final class CompetitionUnifiedDebugAcceptanceTests: XCTestCase {
    @MainActor private func development(_ app: XCUIApplication) {
        app.tabBars.buttons["Settings"].tap()
        let toggle = app.switches["debug-mode"]
        for _ in 0..<16 {
            if toggle.exists && toggle.isHittable { break }
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(toggle.isHittable, app.debugDescription)
        if toggle.value as? String != "1" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
    }
    @MainActor func testInAppFilterStartStopAcrossSettingsTabsAndMasterHidesTools() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en", "--competition-filter-acceptance"]
        app.launch(); defer { app.terminate() }
        development(app)
        app.buttons["Filter Capture"].tap()
        let start = app.buttons["Start Capture"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        if app.buttons["Stop Capture"].exists { app.buttons["Stop Capture"].tap() }
        app.buttons["Clear Captures"].tap()
        start.tap()
        XCTAssertEqual(app.staticTexts["debug-capture-status"].label, "Recording")
        app.tabBars.buttons["Explore"].tap()
        let filter = app.buttons["competition-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<2 {
            filter.tap()
            let close = app.buttons["competition-filter-close"]
            XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
            close.tap()
        }
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Stop Capture"].waitForExistence(timeout: 5))
        app.buttons["Stop Capture"].tap()
        XCTAssertEqual(app.staticTexts["debug-capture-status"].label, "Stopped")
        let share = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Share ")).firstMatch
        XCTAssertTrue(share.exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "in-app-filter-capture"; shot.lifetime = .keepAlways; add(shot)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let toggle = app.switches["debug-mode"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertFalse(app.buttons["Filter Capture"].exists)
        XCTAssertFalse(app.buttons["Separator Capture"].exists)
        XCTAssertFalse(app.buttons["Scroll Capture"].exists)
    }
    @MainActor func testSeparatorVisibleCardCaptureReviewSelectionAndNativeShare() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en", "--competition-results-acceptance"]
        app.launchEnvironment["CUBEFLOW_ACCEPTANCE_PUBLISHED_JSON"] = root.appendingPathComponent("build/competition-reliability-oct14/beijing-333-results.json").path
        app.launch(); defer { app.terminate() }
        development(app)
        app.buttons["Separator Capture"].tap()
        if app.buttons["Stop Capture"].exists { app.buttons["Stop Capture"].tap() }
        app.buttons["Clear Captures"].tap()
        app.buttons["Start Capture"].tap()
        app.tabBars.buttons["Explore"].tap()
        let mode = app.buttons["By Competitor"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10)); mode.tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Yiheng\n")
        let person = app.buttons["published-competitor-2019WANY36"]
        XCTAssertTrue(person.waitForExistence(timeout: 5)); person.tap()
        let capture = app.buttons["separator-capture-visible"]
        XCTAssertTrue(capture.waitForExistence(timeout: 5)); capture.tap()
        let share = app.buttons["separator-review-share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5), app.debugDescription)
        let line = app.buttons["First round → Second round"]
        XCTAssertTrue(line.exists); line.tap()
        XCTAssertTrue(app.buttons["Clear Selection"].isEnabled)
        app.buttons["Undo"].tap()
        XCTAssertFalse(app.buttons["Clear Selection"].isEnabled)
        line.tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "separator-review-selected-real-round"; shot.lifetime = .keepAlways; add(shot)
        share.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5), app.debugDescription)
    }
}

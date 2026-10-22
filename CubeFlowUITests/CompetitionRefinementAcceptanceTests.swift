import XCTest

final class CompetitionRefinementAcceptanceTests: XCTestCase {
    @MainActor func testFilterOpensRepeatedlyAndRestoresPresentAfterRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en", "--competition-filter-acceptance"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Competitions"].waitForExistence(timeout: 15))
        let filter = app.buttons["competition-filter"]
        XCTAssertTrue(filter.exists)
        for status in ["Recent", "Past", "Present", "Present"] {
            filter.tap()
            XCTAssertTrue(app.buttons[status].waitForExistence(timeout: 5), app.debugDescription)
            app.buttons[status].tap()
            XCTAssertEqual(app.staticTexts["Year"].exists, status == "Past")
            XCTAssertTrue(app.buttons[status].isSelected, "The selected status must actually change")
            app.buttons["competition-filter-close"].tap()
        }
        app.terminate()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en", "--competition-filter-acceptance"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Competitions"].waitForExistence(timeout: 15))
        app.buttons["competition-filter"].tap()
        XCTAssertTrue(app.buttons["Present"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Present"].isSelected, "The last selection survives relaunch without a status override")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "competition-filter-present-restored"; shot.lifetime = .keepAlways; add(shot)
        app.terminate()
    }
}

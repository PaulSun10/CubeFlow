import XCTest

#if targetEnvironment(simulator)
final class AlgToolbarIdentityTests: XCTestCase {
    @MainActor func testSingletonGroupAndCaseUseTheSameLearnAction() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "algs", "-appLanguage", "en",
            "-algBrowseViewModeStore", "list", "-algBrowseOrganizationStore", "subset"]
        app.launch()
        defer { app.terminate() }

        let navigation = app.navigationBars.firstMatch
        let puzzle = navigation.buttons.matching(NSPredicate(format: "label CONTAINS %@", "3x3")).firstMatch
        XCTAssertTrue(puzzle.waitForExistence(timeout: 10))
        puzzle.tap()
        app.buttons["Megaminx"].firstMatch.tap()
        let set = app.staticTexts["Megaminx PLL"].firstMatch
        XCTAssertTrue(set.waitForExistence(timeout: 5))
        set.tap()

        let group = app.staticTexts["2 2x2s"].firstMatch
        for _ in 0..<5 where !group.isHittable { app.swipeUp() }
        XCTAssertTrue(group.isHittable)
        group.tap()
        let unlearned = app.staticTexts["1 Cases · Not Started"].firstMatch
        let learned = app.staticTexts["1 Cases · Learned"].firstMatch
        let groupReady = NSPredicate { _, _ in unlearned.exists || learned.exists }
        let groupExpectation = expectation(for: groupReady, evaluatedWith: app)
        wait(for: [groupExpectation], timeout: 5)
        let info = navigation.buttons["info"].firstMatch
        XCTAssertTrue(info.isHittable, navigation.debugDescription)
        info.tap()
        let infoBar = app.navigationBars["About Megaminx PLL"]
        XCTAssertTrue(infoBar.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Overview"].exists)
        infoBar.buttons.firstMatch.tap()

        let learn = navigation.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graduationcap")).firstMatch
        let startedLearned = learned.exists
        XCTAssertTrue(startedLearned || unlearned.exists, app.debugDescription)
        XCTAssertTrue(learn.isHittable, navigation.debugDescription)
        learn.tap()
        XCTAssertTrue((startedLearned ? unlearned : learned).waitForExistence(timeout: 5))

        app.staticTexts["W"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Algorithms"].waitForExistence(timeout: 5))
        XCTAssertFalse(info.exists)
        XCTAssertTrue(learn.isHittable, navigation.debugDescription)
        learn.tap()
        navigation.buttons.firstMatch.tap()
        XCTAssertTrue((startedLearned ? learned : unlearned).waitForExistence(timeout: 5))
    }
}
#endif

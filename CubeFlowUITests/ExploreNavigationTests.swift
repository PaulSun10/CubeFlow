import XCTest

final class ExploreNavigationTests: XCTestCase {
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + " accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }

    @MainActor private func open(_ destination: String, in app: XCUIApplication) {
        let button = app.descendants(matching: .any)["explore-browse-\(destination)"].firstMatch
        for _ in 0..<10 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    @MainActor func testHomeAndBrowseNavigationWithRealData() {
        verifyHomeAndBrowse(language: "en")
    }

    @MainActor func testChineseHomeAndBrowseNavigationWithRealData() {
        verifyHomeAndBrowse(language: "zh-Hans")
    }

    @MainActor func testHomeCompositionAtCurrentTextSizeInBothLanguages() {
        continueAfterFailure = false
        for language in ["en", "zh-Hans"] {
            let app = XCUIApplication()
            app.launchArguments = ["-requestedIPhoneTab", "explore", "-appLanguage", language]
            app.launch()
            XCTAssertTrue(app.navigationBars[language == "en" ? "Explore" : "探索"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts[language == "en" ? "World Record" : "世界纪录"].waitForExistence(timeout: 25))
            capture(app, "Final Home top \(language)")
            let upcoming = app.staticTexts[language == "en" ? "Coming Up" : "即将举行"].firstMatch
            // List virtualizes off-screen modules; scroll before testing their presence.
            for _ in 0..<8 where !upcoming.isHittable { app.swipeUp() }
            if upcoming.isHittable {
                capture(app, "Final Upcoming \(language)")
            }
            let last = app.descendants(matching: .any)["explore-browse-highlights"].firstMatch
            for _ in 0..<12 where !last.isHittable { app.swipeUp() }
            XCTAssertTrue(last.isHittable)
            capture(app, "Final Home bottom \(language)")
            app.terminate()
        }
    }

    @MainActor private func verifyHomeAndBrowse(language: String) {
        continueAfterFailure = false
        let chinese = language == "zh-Hans"
        let homeTitle = chinese ? "探索" : "Explore"
        let recordTitle = chinese ? "世界纪录" : "World Record"
        let recentTitle = chinese ? "近期纪录" : "Recent Records"
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "explore", "-appLanguage", language]
        app.launch()
        XCTAssertTrue(app.navigationBars[homeTitle].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts[recordTitle].waitForExistence(timeout: 25) ||
                      app.staticTexts[recentTitle].exists)
        capture(app, "Explore Home real data")
        app.swipeUp()
        capture(app, "Explore Home middle composition")
        let upcoming = app.staticTexts[chinese ? "即将举行" : "Coming Up"].firstMatch
        for _ in 0..<8 where upcoming.exists && !upcoming.isHittable { app.swipeUp() }
        if upcoming.isHittable { capture(app, "Explore Upcoming composition") }
        let browse = app.descendants(matching: .any)["explore-browse-rankings"].firstMatch
        for _ in 0..<6 where !browse.isHittable { app.swipeUp() }
        capture(app, "Explore Home bottom composition")
        for _ in 0..<12 where !app.staticTexts[recordTitle].isHittable { app.swipeDown() }
        let recent = app.buttons["explore-see-all-records.recent"]
        if recent.waitForExistence(timeout: 5) {
            for _ in 0..<4 where !recent.isHittable { app.swipeUp() }
            recent.tap()
            XCTAssertTrue(app.navigationBars[recentTitle].waitForExistence(timeout: 5))
            capture(app, "Recent Records full native feed")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        open("rankings", in: app)
        XCTAssertTrue(app.navigationBars[chinese ? "排名" : "Rankings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[chinese ? "项目" : "Event"].exists)
        _ = app.buttons[chinese ? "在 WCA 查看" : "View on WCA"].waitForExistence(timeout: 25)
        capture(app, "Rankings source error and retained filters")
        captureErrorContentIfNeeded(app, language: language, name: "Rankings scrolled error")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        open("records", in: app)
        XCTAssertTrue(app.navigationBars[chinese ? "纪录" : "Records"].waitForExistence(timeout: 5))
        _ = app.buttons[chinese ? "在 WCA 查看" : "View on WCA"].waitForExistence(timeout: 25)
        capture(app, "Records source error")
        captureErrorContentIfNeeded(app, language: language, name: "Records scrolled error")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        open("stats", in: app)
        XCTAssertTrue(app.navigationBars[chinese ? "统计" : "Stats"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[chinese ? "已举行的 WCA 比赛" : "WCA competitions held"].exists)
        XCTAssertFalse(app.staticTexts["Coming in a future Explore update."].exists)
        capture(app, "Stats real dated WCA export")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        open("highlights", in: app)
        XCTAssertTrue(app.navigationBars[chinese ? "发现" : "Discover"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Svalbard 2025"].waitForExistence(timeout: 5))
        capture(app, "Geographic discovery north and south")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        open("competitions", in: app)
        XCTAssertTrue(app.navigationBars[chinese ? "比赛" : "Competitions"].waitForExistence(timeout: 10))
        _ = app.staticTexts[chinese ? "正在加载比赛…" : "Loading competitions..."].waitForNonExistence(timeout: 15)
        capture(app, "Preserved competition browser")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars[homeTitle].waitForExistence(timeout: 5))
    }

    @MainActor private func captureErrorContentIfNeeded(_ app: XCUIApplication, language: String, name: String) {
        let link = app.buttons[language == "zh-Hans" ? "在 WCA 查看" : "View on WCA"]
        if link.exists && !link.isHittable {
            for _ in 0..<5 where !link.isHittable { app.swipeUp() }
            capture(app, name)
        }
    }

    @MainActor func testLegacyCompetitionTabRequestOpensChildBrowser() {
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.navigationBars["Competitions"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Competitions"].exists)
    }
}

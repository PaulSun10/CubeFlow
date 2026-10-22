import XCTest

final class CompetitionPerformanceTests: XCTestCase {
    @MainActor func testFinalThreeCompetitionLoadingReview() {
        continueAfterFailure = false
        for (country, query) in [("CN", "Guangzhou Grand Open"), ("CN", "Beijing Autumn Rivalry"), ("CA", "Toronto Weeknights I")] {
            let app = XCUIApplication()
            app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en",
                "-competition_filter_region", "country-\(country)", "-competition_filter_status", "past",
                "-competition_filter_year", "2026", "-competition_show_top_cubers", "NO",
                "-competitionForceFreshFirstDetail", "YES"]
            app.launch()
            let search = app.buttons["Search competitions"].firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 45))
            search.tap()
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(query)
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", query)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 20), app.debugDescription)
            for opening in ["fresh", "reopen"] {
                let started = ProcessInfo.processInfo.systemUptime
                row.tap()
                let document = app.otherElements["competition-rich-document"].firstMatch
                XCTAssertTrue(document.waitForExistence(timeout: 60), app.debugDescription)
                let useful = ProcessInfo.processInfo.systemUptime
                let refresh = app.buttons["competition-refresh"].firstMatch
                let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Not Loading"), object: refresh)
                XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 45), .completed)
                let finished = ProcessInfo.processInfo.systemUptime
                print("[CompetitionFinalReview] \(query) \(opening) useful=\((useful - started) * 1000)ms whole=\((finished - started) * 1000)ms tail=\((finished - useful) * 1000)ms")
                snapshot("review-\(country)-\(query)-\(opening)", app: app)
                app.navigationBars.buttons.firstMatch.tap()
                XCTAssertTrue(row.waitForExistence(timeout: 5))
            }
            app.terminate()
        }
    }

    @MainActor func testGuangzhouTapToUsefulInfo() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en",
            "-competition_filter_region", "country-CN", "-competition_filter_status", "past",
            "-competition_filter_year", "2026", "-competition_show_top_cubers", "NO",
            "-competitionForceFreshFirstDetail", "YES"]
        app.launch()
        let search = app.buttons["Search competitions"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 45))
        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Guangzhou Grand Open")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Guangzhou Grand Open")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), app.debugDescription)
        for opening in ["initial", "reopen"] {
            let started = ProcessInfo.processInfo.systemUptime
            row.tap()
            let document = app.otherElements["competition-rich-document"].firstMatch
            XCTAssertTrue(document.waitForExistence(timeout: 60), app.debugDescription)
            print("[CompetitionNavigationUI] Guangzhou \(opening) tap-to-document=\((ProcessInfo.processInfo.systemUptime - started) * 1000)ms")
            let infoPresented = ProcessInfo.processInfo.systemUptime
            if opening == "initial" {
                let refresh = app.buttons["competition-refresh"].firstMatch
                let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Not Loading"), object: refresh)
                XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 35), .completed)
                let finished = ProcessInfo.processInfo.systemUptime
                print("[CompetitionNavigationUI] Guangzhou whole-session=\((finished - started) * 1000)ms after-Info=\((finished - infoPresented) * 1000)ms")
            }
            // Screenshot/AX export work must not inflate the whole-session measurement.
            snapshot("guangzhou-\(opening)-info", app: app)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "guangzhou-\(opening)-tree"; tree.lifetime = .keepAlways; add(tree)
            if opening == "initial" {
                for (tab, prefix) in [("Results", "competition-result-published-"), ("Scrambles", "competition-scramble-")] {
                    let selectionStart = ProcessInfo.processInfo.systemUptime
                    app.buttons[tab].firstMatch.tap()
                    let firstRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
                    XCTAssertTrue(firstRow.waitForExistence(timeout: 8), app.debugDescription)
                    print("[CompetitionNavigationUI] Guangzhou prepared \(tab)=\((ProcessInfo.processInfo.systemUptime - selectionStart) * 1000)ms")
                    snapshot("guangzhou-prepared-\(tab)", app: app)
                }
                app.buttons["Info"].firstMatch.tap()
            }
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(row.waitForExistence(timeout: 5))
        }
        app.terminate()
    }

    @MainActor func testExploreBrowseAndAdjacentSectionChevron() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "explore", "-appLanguage", "en"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 15))
        let browse = app.buttons["explore-browse-competitions"].firstMatch
        for _ in 0..<8 where !browse.isHittable { app.swipeUp() }
        XCTAssertTrue(browse.isHittable)
        XCTAssertLessThanOrEqual(browse.images.count, 1, "The decorative chevron may be hidden from accessibility")
        if browse.images.firstMatch.exists {
            XCTAssertGreaterThan(browse.images.firstMatch.frame.midX, browse.frame.midX)
        }
        XCTAssertGreaterThanOrEqual(browse.frame.height, 66)
        let lastBrowse = app.buttons["explore-browse-highlights"].firstMatch
        for _ in 0..<4 where !lastBrowse.isHittable { app.swipeUp() }
        XCTAssertTrue(lastBrowse.isHittable)
        XCTAssertLessThanOrEqual(lastBrowse.images.count, 1)
        if lastBrowse.images.firstMatch.exists {
            XCTAssertGreaterThan(lastBrowse.images.firstMatch.frame.midX, lastBrowse.frame.midX)
        }
        snapshot("explore-browse-page-background", app: app)
        let records = app.buttons["explore-see-all-records.recent"].firstMatch
        for _ in 0..<8 where !records.isHittable { app.swipeDown() }
        XCTAssertTrue(records.waitForExistence(timeout: 5))
        XCTAssertLessThan(records.frame.maxX, app.frame.width * 0.75, "The heading control ends after its adjacent chevron, not at the trailing edge")
        let peru = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Peru Nationals 2026")).firstMatch
        if peru.exists {
            XCTAssertFalse(peru.label.contains("Events: 17"))
            XCTAssertTrue(peru.label.contains("Clock"), "Coming Up exposes localized event names, not private-use glyph characters")
        }
        snapshot("explore-adjacent-records-chevron", app: app)
        app.terminate()
    }

    @MainActor private func snapshot(_ name: String, app: XCUIApplication) {
        // Allow the existing crossfade to finish; this is outside measured navigation intervals.
        Thread.sleep(forTimeInterval: 0.4)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testRealBrowserTapToUsefulInfo() {
        continueAfterFailure = false
        for (country, query) in [("CN", "Beijing Autumn Rivalry"), ("CA", "Toronto Weeknights I")] {
            let app = XCUIApplication()
            app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en",
                "-competition_filter_region", "country-\(country)", "-competition_filter_status", "past",
                "-competition_filter_year", "2026", "-competition_show_top_cubers", "NO"]
            app.launch()
            XCTAssertTrue(app.navigationBars["Competitions"].waitForExistence(timeout: 20))
            let search = app.buttons["Search competitions"].firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 40))
            search.tap()
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(query)
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", query)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 15), app.debugDescription)
            let started = ProcessInfo.processInfo.systemUptime
            row.tap()
            let document = app.otherElements["competition-rich-document"].firstMatch
            XCTAssertTrue(document.waitForExistence(timeout: 35), app.debugDescription)
            print("[CompetitionNavigationUI] \(query) tap-to-document=\((ProcessInfo.processInfo.systemUptime - started) * 1000)ms")
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "real-info-\(country)"; attachment.lifetime = .keepAlways; add(attachment)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "real-info-\(country)-tree"; tree.lifetime = .keepAlways; add(tree)
            let largeTitle = app.staticTexts["competition-large-title"].firstMatch
            XCTAssertTrue(largeTitle.exists)
            let info = app.buttons["Info"].firstMatch
            XCTAssertGreaterThan(largeTitle.frame.minY, info.frame.maxY, "The body Large Title must be below primary navigation")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            let warmStarted = ProcessInfo.processInfo.systemUptime
            row.tap()
            XCTAssertTrue(document.waitForExistence(timeout: 10))
            print("[CompetitionNavigationUI] \(query) warm-tap-to-document=\((ProcessInfo.processInfo.systemUptime - warmStarted) * 1000)ms")
            if country == "CA" {
                app.buttons["Events"].firstMatch.tap()
                snapshot("real-wca-info-events", app: app)
                app.buttons["Schedule"].firstMatch.tap()
                snapshot("real-wca-info-schedule", app: app)
                app.buttons["General Info"].firstMatch.tap()
                app.swipeUp()
                snapshot("real-wca-inline-title", app: app)
                for _ in 0..<3 where !app.buttons["Scrambles"].firstMatch.isHittable { app.swipeDown() }
                let scramblesStarted = ProcessInfo.processInfo.systemUptime
                app.buttons["Scrambles"].firstMatch.tap()
                let scramble = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "competition-scramble-")).firstMatch
                XCTAssertTrue(scramble.waitForExistence(timeout: 15), app.debugDescription)
                print("[CompetitionNavigationUI] Scrambles selection-to-row=\((ProcessInfo.processInfo.systemUptime - scramblesStarted) * 1000)ms")
                snapshot("real-published-scrambles", app: app)
                let results = app.buttons["Results"].firstMatch
                XCTAssertTrue(results.waitForExistence(timeout: 15))
                let selectionStarted = ProcessInfo.processInfo.systemUptime
                results.tap()
                let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "competition-result-published-")).firstMatch
                XCTAssertTrue(result.waitForExistence(timeout: 15), app.debugDescription)
                print("[CompetitionNavigationUI] Results selection-to-row=\((ProcessInfo.processInfo.systemUptime - selectionStarted) * 1000)ms")
                let listShot = XCTAttachment(screenshot: app.screenshot())
                listShot.name = "real-published-results"; listShot.lifetime = .keepAlways; add(listShot)
                result.tap()
                let allResults = app.buttons["All results"].firstMatch
                XCTAssertTrue(allResults.waitForExistence(timeout: 5), app.debugDescription)
                let cardShot = XCTAttachment(screenshot: app.screenshot())
                cardShot.name = "real-published-card"; cardShot.lifetime = .keepAlways; add(cardShot)
                allResults.tap()
                let profile = app.buttons["WCA Profile"].firstMatch
                XCTAssertTrue(profile.waitForExistence(timeout: 5), app.debugDescription)
                let allShot = XCTAttachment(screenshot: app.screenshot())
                allShot.name = "real-published-all-results"; allShot.lifetime = .keepAlways; add(allShot)
                profile.tap()
                XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5))
                let profileShot = XCTAttachment(screenshot: app.screenshot())
                profileShot.name = "real-wca-profile"; profileShot.lifetime = .keepAlways; add(profileShot)
            }
            app.terminate()
        }
    }
}

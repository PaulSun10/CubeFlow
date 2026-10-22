import XCTest

final class CompetitionScrollRetentionAcceptanceTests: XCTestCase {
    @MainActor func testNativeSwitchSettingsRoundTripRetainsSwipeAndEnablesShare() throws {
        continueAfterFailure = false
        print("[ScrollRetentionUI] native-switch round-trip revision 3")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("build/competition-physical-acceptance-oct13/list-summaries.json"))) as? [[String: Any]])
        let formatter = ISO8601DateFormatter()
        for index in rows.indices {
            let date = formatter.string(from: Date().addingTimeInterval(-Double(index + 3) * 86400))
            rows[index]["startDate"] = date; rows[index]["endDate"] = date
        }
        let fixture = root.appendingPathComponent("build/competition-capture-retention-oct16/ui-past-fixture.json")
        try JSONSerialization.data(withJSONObject: rows).write(to: fixture)
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en",
            "-competitionCardStyle", "list", "-competition_show_top_cubers", "NO",
            "-competition_filter_status", "past", "-competition_filter_year", "all",
            "-competition_filter_region", "all", "--competition-physical-browser"]
        // No owner-timing flag or command-line recording preference: the actual
        // Settings switch must enable capture after the collection already exists.
        app.launchEnvironment["CUBEFLOW_PHYSICAL_SUMMARIES"] = fixture.path
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.collectionViews["competition-long-list"].waitForExistence(timeout: 15))
        func diagnostics() {
            let settings = app.tabBars.buttons["Settings"]
            if !settings.isHittable {
                // Scrolling can natively minimize the tab bar to Explore alone.
                app.tabBars.buttons["Explore"].tap()
            }
            XCTAssertTrue(settings.waitForExistence(timeout: 3)); settings.tap()
            let toggle = app.switches["competition-scroll-recording"]
            if toggle.waitForExistence(timeout: 1) { return }
            let entry = app.buttons["Competition Scroll Diagnostics"]
            for _ in 0..<14 {
                if entry.exists && entry.isHittable { break }
                app.swipeUp(velocity: .fast)
            }
            XCTAssertTrue(entry.isHittable, app.debugDescription); entry.tap()
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        }
        diagnostics()
        let toggle = app.switches["competition-scroll-recording"]
        func switchRecording() {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        if toggle.value as? String == "1" { switchRecording() }
        app.buttons["competition-scroll-clear"].tap()
        XCTAssertFalse(app.buttons["competition-scroll-share"].isEnabled)
        switchRecording()
        XCTAssertEqual(toggle.value as? String, "1", "Tap the native switch, not its label")
        app.tabBars.buttons["Explore"].tap()
        let list = app.collectionViews["competition-long-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5)); list.swipeUp(velocity: .slow)
        diagnostics()
        if toggle.value as? String == "1" { switchRecording() }
        XCTAssertEqual(toggle.value as? String, "0")
        let share = app.buttons["competition-scroll-share"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate:
            NSPredicate(format: "enabled == YES"), object: share)], timeout: 4), .completed)
        XCTAssertTrue(share.isEnabled)
        let count = app.staticTexts["competition-scroll-capture-count"]
        XCTAssertFalse(count.label.contains("Captures: 0"), count.label)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "retained-scroll-and-enabled-share"
        image.lifetime = .keepAlways; add(image)
    }
}

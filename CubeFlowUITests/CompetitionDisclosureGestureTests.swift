import XCTest

final class CompetitionDisclosureGestureTests: XCTestCase {
    @MainActor func testRealDisclosureTapsDoNotMoveTheViewport() throws {
        try repeatedTaps(extraArguments: [])
    }
    @MainActor func testGlassDisclosureTapsDoNotMoveTheViewport() throws {
        try repeatedTaps(extraArguments: ["--competition-disclosure-glass"])
    }
    @MainActor private func repeatedTaps(extraArguments: [String]) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en", "--competition-disclosure-acceptance"] + extraArguments
        app.launch()
        defer { app.terminate() }
        let marker = app.staticTexts["competition-viewport-marker"]
        let disclosure = app.buttons.matching(NSPredicate(format:
            "identifier == %@ AND label BEGINSWITH %@", "competition-top-cubers-expand", "Show ")).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        let collapsedLabel = disclosure.label
        let origin = marker.frame.minY
        for _ in 0..<6 {
            for expected in ["Show Less", collapsedLabel] {
                XCTAssertTrue(disclosure.isHittable, "No test-induced auto-scroll to disclosure is allowed")
                disclosure.tap()
                let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", expected), object: disclosure)
                XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 3), .completed)
                try verifyReadOnlyTrace(app, permitsClamping: false)
                XCTAssertEqual(marker.frame.minY, origin, accuracy: 1, "Actual tap and self-sizing must leave viewport stationary")
            }
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "actual-disclosure-viewport"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testExpansionNearBottomDoesNotAutoScrollToShowLess() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en",
            "--competition-disclosure-acceptance", "--competition-disclosure-edge"]
        app.launch(); defer { app.terminate() }
        let button = disclosure(app)
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        XCTAssertTrue(button.isHittable, "The initial disclosure must be visible without scrolling")
        let marker = app.staticTexts["competition-viewport-marker"], origin = marker.frame.minY
        button.tap()
        try verifyReadOnlyTrace(app, permitsClamping: false)
        XCTAssertEqual(marker.frame.minY, origin, accuracy: 1)
    }

    @MainActor func testCollapseAfterScrollingToExpandedEndOnlyClampsToNativeBoundary() throws {
        try scrolledCollapse(extraArguments: [])
    }

    @MainActor func testGlassCollapseAfterScrollingToExpandedEndOnlyClampsToNativeBoundary() throws {
        try scrolledCollapse(extraArguments: ["--competition-disclosure-glass"])
    }

    @MainActor func testScrolledCollapseWithContentBelowDoesNotMoveViewport() throws {
        try scrolledCollapse(extraArguments: ["--competition-disclosure-long-tail"], permitsClamping: false)
    }

    @MainActor func testGlassScrolledCollapseWithContentBelowDoesNotMoveViewport() throws {
        try scrolledCollapse(extraArguments: ["--competition-disclosure-long-tail", "--competition-disclosure-glass"], permitsClamping: false)
    }

    @MainActor private func scrolledCollapse(extraArguments: [String], permitsClamping: Bool = true) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en",
            "--competition-disclosure-acceptance", "--competition-disclosure-boundary"] + extraArguments
        app.launch(); defer { app.terminate() }
        let button = disclosure(app)
        XCTAssertTrue(button.waitForExistence(timeout: 15)); XCTAssertTrue(button.isHittable)
        button.tap(); try verifyReadOnlyTrace(app, permitsClamping: false)
        let list = app.collectionViews["competition-disclosure-list"]
        for _ in 0..<6 where !button.isHittable { list.swipeUp() }
        XCTAssertTrue(button.isHittable, "Only explicit user-style scroll gestures may reveal Show Less")
        button.tap(); try verifyReadOnlyTrace(app, permitsClamping: permitsClamping, requiresScrolled: true)
    }

    @MainActor private func disclosure(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@",
            "competition-top-cubers-expand", "Show ")).firstMatch
    }

    @MainActor private func verifyReadOnlyTrace(_ app: XCUIApplication, permitsClamping: Bool, requiresScrolled: Bool = false) throws {
        let list = app.collectionViews["competition-disclosure-list"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH %@", "{"), object: list)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed)
        let text = try XCTUnwrap(list.value as? String)
        let evidence = XCTAttachment(string: text); evidence.name = "read-only-disclosure-offset-trace"; evidence.lifetime = .keepAlways; add(evidence)
        print("[DisclosureTrace] \(text)")
        let trace = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        func number(_ key: String) throws -> Double { try XCTUnwrap(trace[key] as? Double) }
        let start = try number("start"), end = try number("end")
        let lower = try number("minimum"), upper = try number("maximum")
        if requiresScrolled {
            XCTAssertGreaterThan(start, lower + 50, "Collapse must begin after scrolling through expanded entries")
        }
        XCTAssertEqual(end, min(max(start, lower), upper), accuracy: 1, "Only the closest legal native boundary may change the offset")
        XCTAssertLessThanOrEqual(try number("unexpected"), 1, "Unexpected model-offset movement during disclosure")
        XCTAssertLessThanOrEqual(try number("presentationDrift"), 1, "Unexpected animated viewport movement when clamping is not needed")
        XCTAssertLessThanOrEqual(try number("cellOriginDrift"), 1, "The card must expand downward, not shift its leading origin")
        XCTAssertLessThanOrEqual(try number("viewportOriginDrift"), 1, "The surrounding navigation must not move the viewport")
        if !permitsClamping { XCTAssertEqual(end, start, accuracy: 1) }
    }
}

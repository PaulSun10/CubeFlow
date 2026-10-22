import XCTest

final class CompetitionLongScrollAcceptanceTests: XCTestCase {
    @MainActor func testCapturedLongListRepeatedSwipesCold() throws { try exercise(glass: false, warm: false) }
    @MainActor func testCapturedLongGlassRepeatedSwipesWarm() throws { try exercise(glass: true, warm: true) }

    @MainActor private func exercise(glass: Bool, warm: Bool) throws {
        continueAfterFailure = false
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let listFile = root.appendingPathComponent("build/competition-physical-acceptance-oct13/list-summaries.json")
        guard FileManager.default.fileExists(atPath: listFile.path) else { throw XCTSkip("Requires captured public list") }
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en",
            "-competitionCardStyle", glass ? "glass" : "list", "-competition_show_top_cubers", "YES",
            "--competition-long-list-acceptance"] + (warm ? ["--competition-long-warm"] : [])
        app.launchEnvironment["CUBEFLOW_LONG_LIST_JSON"] = listFile.path
        app.launchEnvironment["CUBEFLOW_LONG_WCIF_JSON"] = root.appendingPathComponent("build/competition-physical-regressions/beijing-wcif.json").path
        app.launch(); defer { app.terminate() }
        let list = app.collectionViews["competition-long-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 15), app.debugDescription)
        if !warm {
            list.swipeUp(velocity: .slow)
            let text = try XCTUnwrap(list.value as? String)
            let trace = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            XCTAssertEqual(trace["loadReleasedDuringGesture"] as? Bool, true, "Cold response must arrive during a real gesture")
            let attachment = XCTAttachment(string: text); attachment.name = "cold-load-during-first-drag"; attachment.lifetime = .keepAlways; add(attachment)
            list.swipeDown(velocity: .slow)
        }
        let disclosure = app.buttons["competition-top-cubers-expand"].firstMatch
        for _ in 0..<3 {
            if disclosure.exists, disclosure.frame.midY < 700, disclosure.frame.midY > 210 { break }
            list.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(disclosure.isHittable, "Captured Beijing disclosure must be reached using explicit swipes")
        let collapsedLabel = disclosure.label
        disclosure.tap()
        try verifyDisclosure(list)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "real-browser-after-disclosure"; image.lifetime = .keepAlways; add(image)
        XCTAssertTrue(disclosure.label.contains("Show Less"), "label=\(disclosure.label)\n\(app.debugDescription)")
        for upward in [true, false] {
            for index in 0..<12 {
                if upward { list.swipeUp() } else { list.swipeDown() }
                let text = try XCTUnwrap(list.value as? String)
                let trace = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
                let samples = try XCTUnwrap(trace["samples"] as? [[Double]])
                XCTAssertGreaterThan(samples.count, 2, "Need the complete drag/deceleration trace")
                let first = try XCTUnwrap(samples.first), last = try XCTUnwrap(samples.last)
                let progress = upward ? last[1] - first[1] : first[1] - last[1]
                print("[LongScroll] glass=\(glass) up=\(upward) gesture=\(index) start=\(first[1]) end=\(last[1]) progress=\(progress) samples=\(samples.count)")
                let attachment = XCTAttachment(string: text); attachment.name = "long-scroll-\(glass)-\(upward)-\(index)"; attachment.lifetime = .keepAlways; add(attachment)
                if index > 0 {
                    let room = upward ? first[3] - first[1] : first[1] - first[2]
                    if room > 200 { XCTAssertGreaterThan(progress, 80, "Each real swipe must escape the prior position") }
                    for (before, after) in zip(samples, samples.dropFirst()) {
                        // Ignore only true boundary bounce/clamping, not legal-position restoration.
                        guard before[1] >= before[2], before[1] <= before[3],
                              before[1] >= after[2], before[1] <= after[3],
                              after[1] >= after[2], after[1] <= after[3] else { continue }
                        let reverse = upward ? before[1] - after[1] : after[1] - before[1]
                        XCTAssertLessThanOrEqual(reverse, 8, "Unexpected snapback within a legally reachable viewport")
                    }
                }
            }
        }
        for _ in 0..<6 {
            if disclosure.exists, disclosure.frame.midY < 700, disclosure.frame.midY > 210 { break }
            if disclosure.exists, disclosure.frame.midY < 210 { list.swipeDown(velocity: .slow) }
            else { list.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(disclosure.label.contains("Show Less"), "Cell recycling must not silently collapse the expanded row")
        disclosure.tap()
        try verifyDisclosure(list)
        XCTAssertEqual(disclosure.label, collapsedLabel, "Return to the same measured three-row prefix")
    }
    @MainActor private func verifyDisclosure(_ list: XCUIElement) throws {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in list.label.contains("unexpected") }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        let trace = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(list.label.utf8)) as? [String: Any])
        print("[ProductionDisclosure] \(list.label)")
        let image = XCTAttachment(string: list.label); image.name = "real-browser-disclosure-transition"; image.lifetime = .keepAlways; add(image)
        for key in ["unexpected", "presentationDrift", "viewportOriginDrift", "cellOriginDrift", "titleOriginDrift", "titleRelativeDrift"] {
            XCTAssertLessThanOrEqual(try XCTUnwrap(trace[key] as? Double), 1, key)
        }
    }
}

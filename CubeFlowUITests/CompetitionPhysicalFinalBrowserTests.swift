import XCTest

final class CompetitionPhysicalFinalBrowserTests: XCTestCase {
    @MainActor func testMakatiWarmList() throws { try exercise(glass: false, cold: false) }
    @MainActor func testMakatiWarmGlass() throws { try exercise(glass: true, cold: false) }
    @MainActor func testMakatiVenueAndExistingRowsList() throws { try exercise(glass: false, cold: false, elements: true) }
    @MainActor func testMakatiVenueAndExistingRowsGlass() throws { try exercise(glass: true, cold: false, elements: true) }
    @MainActor func testGlassCardActions() {
        do { try exercise(glass: true, cold: false, routeOnly: true) }
        catch { XCTFail(String(describing: error)) }
    }
    @MainActor func testMultipleColdArrivalsList() throws { try exercise(glass: false, cold: true) }
    @MainActor func testMultipleColdArrivalsGlass() throws { try exercise(glass: true, cold: true) }
    @MainActor func testInteriorColdArrivalsList() throws { try exercise(glass: false, cold: true, interior: true) }
    @MainActor func testInteriorColdArrivalsGlass() throws { try exercise(glass: true, cold: true, interior: true) }
    @MainActor func testWarmInitialGestureControlList() throws { try exercise(glass: false, cold: false, gestureOnly: true) }
    @MainActor func testWarmInitialGestureControlGlass() throws { try exercise(glass: true, cold: false, gestureOnly: true) }

    @MainActor private func exercise(glass: Bool, cold: Bool, interior: Bool = false, gestureOnly: Bool = false, elements: Bool = false, routeOnly: Bool = false) throws {
        continueAfterFailure = false
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("build/competition-final-ui-oct14")
        let run = UUID().uuidString
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en",
            "-competitionCardStyle", glass ? "glass" : "list", "-competition_show_top_cubers", "YES",
            "-competition_filter_status", "recent", "-competition_filter_region", "all",
            "-competition_filter_year", "all", "--competition-physical-browser"]
            + (cold ? [] : ["--competition-physical-warm"])
            + (interior || gestureOnly ? ["--competition-physical-interior"] : [])
        app.launchEnvironment["CUBEFLOW_PHYSICAL_SUMMARIES"] = folder.appendingPathComponent("browser-summaries.json").path
        app.launchEnvironment["CUBEFLOW_MAKATI_WCIF"] = folder.appendingPathComponent("makati-wcif.json").path
        app.launchEnvironment["CUBEFLOW_TOKAI_WCIF"] = folder.appendingPathComponent("tokai-wcif.json").path
        app.launchEnvironment["CUBEFLOW_BEIJING_WCIF"] = root.appendingPathComponent("build/competition-physical-regressions/beijing-wcif.json").path
        app.launch(); defer { app.terminate() }
        let list = app.collectionViews["competition-long-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 15), app.debugDescription)
        if cold || gestureOnly {
            // Assert the first gesture containing publication, not only later swipes.
            list.swipeUp(velocity: .slow)
            if interior { list.swipeUp(velocity: .slow) }
            let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "\"idleRecordingComplete\":true"), object: list)
            XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 3), .completed)
            let text = try XCTUnwrap(list.value as? String)
            try text.write(to: folder.appendingPathComponent("cold-gesture-\(glass ? "glass" : "list").json"), atomically: true, encoding: .utf8)
            try text.write(to: folder.appendingPathComponent("gesture-\(gestureOnly ? "warm-control" : (interior ? "cold-interior" : "cold-initial"))-\(glass ? "glass" : "list")-\(run).json"), atomically: true, encoding: .utf8)
            let attachment = XCTAttachment(string: text); attachment.name = "normal-browser-cold-first-drag"; attachment.lifetime = .keepAlways; add(attachment)
            let trace = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            XCTAssertEqual(trace["loadReleasedDuringGesture"] as? Bool, cold)
            let samples = try XCTUnwrap(trace["samples"] as? [[Double]])
            XCTAssertGreaterThan(samples.count, 3)
            var visualPairs = 0
            for (before, after) in zip(samples, samples.dropFirst()) {
                guard before[1] >= before[2], before[1] <= before[3], after[1] >= after[2], after[1] <= after[3] else { continue }
                guard before.count >= 9, after.count >= 9, before[5] == after[5] else { continue }
                visualPairs += 1
                // Large-title collapse can rebase model offsets with no onscreen movement.
                XCTAssertLessThanOrEqual(after[8] - before[8], 1, "Visible backward movement during the actual gesture")
            }
            XCTAssertGreaterThan(visualPairs, 3, "Verify real cell presentation, not only response overlap")
            return
        }
        let makati = app.cells.containing(NSPredicate(format: "label == %@", "Makati Speedcubing Open IX 2026")).firstMatch
        let button = makati.buttons["competition-top-cubers-expand"]
        for _ in 0..<6 where !button.isHittable { list.swipeUp(velocity: .slow) }
        XCTAssertTrue(button.isHittable, app.debugDescription)
        let collapsedLabel = button.label
        if routeOnly {
            button.tap()
            XCTAssertTrue(list.isHittable, "Disclosure must not activate the surrounding native row Button")
            XCTAssertEqual(button.label, "Show Less")
            button.tap()
            XCTAssertTrue(list.isHittable)
            XCTAssertEqual(button.label, collapsedLabel)
            let title = makati.staticTexts["Makati Speedcubing Open IX 2026"]
            title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let back = app.navigationBars.buttons["BackButton"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            XCTAssertFalse(list.isHittable)
            back.tap()
            XCTAssertTrue(list.waitForExistence(timeout: 5))
            XCTAssertEqual(button.label, collapsedLabel)
            print("[OriginalGlassRoute] independent expand/collapse and native navigation/return passed")
            return
        }
        for index in 0..<4 {
            button.tap()
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in list.label.contains("titleOriginDrift") }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 4), .completed)
            let text = list.label
            try text.write(to: folder.appendingPathComponent("warm-\(glass ? "glass" : "list")-\(index).json"), atomically: true, encoding: .utf8)
            try text.write(to: folder.appendingPathComponent("warm-\(glass ? "glass" : "list")-\(run)-\(index).json"), atomically: true, encoding: .utf8)
            let trace = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            if elements {
                let samples = try XCTUnwrap(trace["elementSamples"] as? [String: [[Double]]])
                for key in ["MakatiSpeedcubingOpenIX2026|venue", "MakatiSpeedcubingOpenIX2026|top-heading"] {
                    XCTAssertGreaterThan(try XCTUnwrap(samples[key]).count, 3, key)
                }
                let existingCubers = samples.filter { $0.key.contains("|cuber:") && $0.value.count > 3 && $0.value.first![0] < samples.values.compactMap(\.first).map { $0[0] }.min()! + 0.03 }
                XCTAssertGreaterThanOrEqual(existingCubers.count, 3)
                for (key, points) in samples where !key.hasSuffix("|disclosure") && (!key.contains("|cuber:") || existingCubers[key] != nil) {
                    let origin = try XCTUnwrap(points.first)[2]
                    let drift = points.map { abs($0[2] - origin) }.max() ?? 0
                    print("[ExistingCardElement] \(key) drift=\(drift)")
                    XCTAssertLessThanOrEqual(drift, 1, key)
                }
                XCTAssertGreaterThan(try XCTUnwrap(samples["MakatiSpeedcubingOpenIX2026|disclosure"]).count, 3)
            }
            for key in ["unexpected", "presentationDrift", "titleOriginDrift", "titleRelativeDrift"] {
                XCTAssertLessThanOrEqual(try XCTUnwrap(trace[key] as? Double), 1, key)
            }
            let attachment = XCTAttachment(string: text); attachment.name = "makati-normal-browser-disclosure"; attachment.lifetime = .keepAlways; add(attachment)
        }
        let appearance = XCTAttachment(screenshot: app.screenshot()); appearance.name = "stable-card-\(glass ? "glass" : "list")"
        appearance.lifetime = .keepAlways; add(appearance)
        if glass {
            let title = makati.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Makati Speedcubing Open IX 2026")).firstMatch
            title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let back = app.navigationBars.buttons["BackButton"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            XCTAssertFalse(list.isHittable, "The real card surface must navigate, not only animate")
            back.tap()
            XCTAssertTrue(list.waitForExistence(timeout: 5))
            XCTAssertEqual(button.label, collapsedLabel, "Returning must preserve disclosure state")
        }
    }
}

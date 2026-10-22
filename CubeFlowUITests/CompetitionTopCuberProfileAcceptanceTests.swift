import XCTest

final class CompetitionTopCuberProfileAcceptanceTests: XCTestCase {
    @MainActor func testListChipOpensExistingFullPageProfileAndReturnsToExpandedCard() throws { try exercise(glass: false) }
    @MainActor func testGlassChipOpensExistingFullPageProfileAndReturnsToExpandedCard() throws { try exercise(glass: true) }

    @MainActor func testActualDevelopmentTogglePersistsAcrossRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "settings", "-appLanguage", "en"]
        app.launch(); defer { app.terminate() }
        func toggle() -> XCUIElement {
            let item = app.switches["debug-mode"]
            for _ in 0..<16 {
                if item.exists && item.isHittable { break }
                app.swipeUp(velocity: .fast)
            }
            XCTAssertTrue(item.isHittable, app.debugDescription)
            return item
        }
        let original = toggle().value as? String
        XCTAssertTrue(original == "0" || original == "1")
        if original == "0" { toggle().coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
        XCTAssertEqual(toggle().value as? String, "1")
        app.terminate(); app.launch()
        XCTAssertEqual(toggle().value as? String, "1")
        if original == "0" { toggle().coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
        XCTAssertEqual(toggle().value as? String, original)
    }

    @MainActor private func exercise(glass: Bool) throws {
        continueAfterFailure = false
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("build/competition-final-ui-oct14")
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en",
            "-competitionCardStyle", glass ? "glass" : "list", "-competition_show_top_cubers", "YES",
            "-competition_filter_status", "recent", "-competition_filter_region", "all", "-competition_filter_year", "all",
            "--competition-physical-browser", "--competition-physical-warm"]
        app.launchEnvironment["CUBEFLOW_PHYSICAL_SUMMARIES"] = folder.appendingPathComponent("browser-summaries.json").path
        app.launchEnvironment["CUBEFLOW_MAKATI_WCIF"] = folder.appendingPathComponent("makati-wcif.json").path
        app.launchEnvironment["CUBEFLOW_TOKAI_WCIF"] = folder.appendingPathComponent("tokai-wcif.json").path
        app.launchEnvironment["CUBEFLOW_BEIJING_WCIF"] = root.appendingPathComponent("build/competition-physical-regressions/beijing-wcif.json").path
        app.launch(); defer { app.terminate() }
        let list = app.collectionViews["competition-long-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        let card = app.cells.containing(NSPredicate(format: "label == %@", "Makati Speedcubing Open IX 2026")).firstMatch
        let disclosure = card.buttons["competition-top-cubers-expand"]
        for _ in 0..<6 where !disclosure.isHittable { list.swipeUp(velocity: .slow) }
        XCTAssertTrue(disclosure.isHittable, app.debugDescription)
        disclosure.tap()
        XCTAssertEqual(disclosure.label, "Show Less")
        let chip = card.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "competition-top-cuber-profile-")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), app.debugDescription)
        let id = String(chip.identifier.dropFirst("competition-top-cuber-profile-".count))
        XCTAssertEqual(id.count, 10)
        XCTAssertLessThan(chip.frame.width, card.frame.width)
        let original = chip.frame
        for x in [0.3, 0.92, 0.02] {
            chip.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).tap()
            let destination = app.descendants(matching: .any).matching(identifier: "competition-top-cuber-wca-profile-" + id).firstMatch
            XCTAssertTrue(destination.waitForExistence(timeout: 8), app.debugDescription)
            XCTAssertFalse(list.isHittable)
            XCTAssertEqual(app.sheets.count, 0)
            XCTAssertEqual(app.popovers.count, 0)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(list.waitForExistence(timeout: 5))
            XCTAssertTrue(list.isHittable, "Return must not reveal an accidentally opened competition detail")
            XCTAssertEqual(disclosure.label, "Show Less")
            XCTAssertEqual(chip.frame.minY, original.minY, accuracy: 1)
            XCTAssertEqual(chip.frame.size, original.size)
        }
        let start = chip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -180)))
        XCTAssertTrue(list.isHittable, "Dragging over a chip must remain native scrolling, not open Profile")
        XCTAssertLessThan(chip.frame.minY, original.minY - 20)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "profile-return-\(glass ? "glass" : "list")"; image.lifetime = .keepAlways; add(image)
    }
}

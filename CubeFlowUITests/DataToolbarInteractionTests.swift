import XCTest

#if targetEnvironment(simulator)
final class DataToolbarInteractionTests: XCTestCase {
    @MainActor func testNativeToolbarSelectionAndDirectDeleteAtFourDigits() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "data", "-appLanguage", "en",
            "-selectedSessionID", "", "-dataSolveResultFilter", "all", "-dataSolveSortOption", "newest"]
        app.launchEnvironment["CUBEFLOW_DATA_TOOLBAR_UI_TEST"] = "1"
        app.launchEnvironment["CUBEFLOW_DATA_SELECTION_TRACE"] = "1"
        app.launch()
        defer { app.terminate() }
        func button(_ id: String) -> XCUIElement { app.buttons.matching(identifier: id).firstMatch }
        func waitFor(_ message: String, _ condition: @escaping () -> Bool) {
            let ready = expectation(for: NSPredicate { _, _ in condition() }, evaluatedWith: app)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, message)
        }
        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let select = button("data-selection-open"), close = button("data-selection-close")
        let all = button("data-selection-all"), move = button("data-selection-move")
        let delete = button("data-selection-delete"), search = button("data-bottom-search")
        let row = app.buttons.matching(identifier: "data-solve-row").firstMatch
        // A hosted ToolbarItem can be drawn at a valid frame even when
        // XCTest's hittability heuristic for its descendants is false.
        // Send a real screen tap and assert the action's outcome below.
        func tapToolbar(_ button: XCUIElement) {
            XCTAssertTrue(button.exists && button.isEnabled)
            let frame = button.frame
            XCTAssertFalse(frame.isEmpty)
            XCTAssertTrue(app.frame.contains(CGPoint(x: frame.midX, y: frame.midY)))
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: frame.midY - app.frame.minY)).tap()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        capture("data-native-search")
        XCTAssertTrue(select.isHittable)
        let selectFrame = select.frame
        select.tap()
        waitFor("The primary disabled Delete must be present in the selection bar") {
            close.isHittable && !select.exists && delete.exists && !delete.isEnabled && all.exists && !search.exists
        }
        print("[DataSelectionButtonFrames] select=\(selectFrame) close=\(close.frame)")
        XCTAssertFalse(move.exists)
        capture("data-zero-disabled-delete")
        XCTAssertTrue(row.isHittable)
        row.tap()
        waitFor("Manual 0 to 1 must surface Move and enable Delete") { move.exists && delete.exists && delete.isEnabled }
        let one = move.label
        let wideDeleteWidth = delete.frame.width
        capture("data-one-enabled-delete")
        row.tap()
        waitFor("Manual 1 to 0 must remove Move and disable Delete") { !move.exists && delete.exists && !delete.isEnabled }
        tapToolbar(all)
        waitFor("Bulk selection must expose all three direct controls") { move.exists && move.label != one && delete.exists }
        capture("data-four-digit-direct-actions")
        XCTAssertTrue(move.label.replacingOccurrences(of: ",", with: "").contains("1021"))
        XCTAssertLessThan(all.frame.maxX, move.frame.minX + 1)
        XCTAssertLessThan(move.frame.maxX, delete.frame.minX + 1)
        // UIKit can report the icon's accessible frame inside the larger
        // prominent Glass surface. Validate the actual tap below.
        XCTAssertTrue(app.frame.contains(delete.frame))
        XCTAssertLessThanOrEqual(delete.frame.width, wideDeleteWidth + 1)
        print("[DataToolbarFrames] oneDelete=\(wideDeleteWidth) all=\(all.frame) move=\(move.frame) delete=\(delete.frame)")
        tapToolbar(delete)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        tapToolbar(move)
        XCTAssertTrue(app.staticTexts["Toolbar destination"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()
        tapToolbar(all)
        waitFor("Deselect All must restore the disabled action") { !move.exists && delete.exists && !delete.isEnabled }
        close.tap()
        waitFor("Exit must restore native Search and remove selection actions") {
            search.isHittable && select.isHittable && !close.exists && !delete.exists
        }
        search.tap()
        let searchBar = app.navigationBars["Search Solves"]
        XCTAssertTrue(searchBar.waitForExistence(timeout: 5))
        XCTAssertFalse(select.isHittable, "The selection button belongs to Data, not the pushed Search screen")
        searchBar.buttons.firstMatch.tap()
        waitFor("Returning from Search restores the Data accessory and selection item") {
            search.isHittable && select.isHittable && !close.exists
        }
    }

    @MainActor func testRTLToolbarKeepsDeleteOnTheTrailingSide() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "data", "-appLanguage", "ar",
            "-selectedSessionID", "", "-dataSolveResultFilter", "all", "-dataSolveSortOption", "newest"]
        app.launchEnvironment["CUBEFLOW_DATA_TOOLBAR_UI_TEST"] = "1"
        app.launch()
        defer { app.terminate() }
        let select = app.buttons["data-selection-open"].firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        select.tap()
        let all = app.buttons["data-selection-all"].firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        all.tap()
        let move = app.buttons["data-selection-move"].firstMatch
        let delete = app.buttons["data-selection-delete"].firstMatch
        XCTAssertTrue(move.waitForExistence(timeout: 5))
        XCTAssertTrue(all.exists && move.exists && delete.exists && delete.isEnabled)
        XCTAssertGreaterThan(all.frame.minX + 1, move.frame.maxX)
        XCTAssertGreaterThan(move.frame.minX + 1, delete.frame.maxX)
        XCTAssertGreaterThanOrEqual(delete.frame.width, 44)
        XCTAssertFalse(delete.label.isEmpty)
        delete.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor func testNativeTopSelectionRetainsGraphAndFilter() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "data", "-appLanguage", "en",
            "-selectedSessionID", "", "-dataSolveResultFilter", "all", "-dataSolveSortOption", "newest"]
        app.launchEnvironment["CUBEFLOW_DATA_TOOLBAR_UI_TEST"] = "1"
        app.launch()
        defer { app.terminate() }
        let data = app.navigationBars["Data"]
        let open = data.buttons["data-selection-open"], close = data.buttons["data-selection-close"]
        let graph = data.buttons["Time Trend"], filter = data.buttons["Filter"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        XCTAssertTrue(graph.isHittable && filter.isHittable)
        let normal = open.frame
        for _ in 0..<3 {
            open.tap()
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            XCTAssertFalse(open.exists)
            XCTAssertTrue(graph.isHittable && filter.isHittable)
            XCTAssertGreaterThan(normal.width, close.frame.width)
            XCTAssertEqual(normal.midY, close.frame.midY, accuracy: 1)
            close.tap()
            XCTAssertTrue(open.waitForExistence(timeout: 5))
            XCTAssertFalse(close.exists)
        }
        filter.tap()
        XCTAssertTrue(app.buttons["Time Range"].waitForExistence(timeout: 5))
        // Open an existing Filter action and return without changing filters.
        app.buttons["Time Range"].tap()
        let range = app.navigationBars["Time Range"]
        XCTAssertTrue(range.buttons["Done"].waitForExistence(timeout: 5))
        range.buttons["Done"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        graph.tap()
        XCTAssertTrue(app.navigationBars["Time Trend"].waitForExistence(timeout: 5))
    }

    @MainActor func testSessionsEditDoneRenameAndDelete() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "data", "-appLanguage", "en", "-selectedSessionID", ""]
        app.launchEnvironment["CUBEFLOW_DATA_TOOLBAR_UI_TEST"] = "1"
        app.launch()
        defer { app.terminate() }
        let sessions = app.navigationBars["Data"].buttons["Session"]
        XCTAssertTrue(sessions.waitForExistence(timeout: 10))
        sessions.tap()
        let bar = app.navigationBars["Session"]
        let edit = bar.buttons["Edit"], done = bar.buttons["Done"], rename = bar.buttons["Rename"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertFalse(rename.isEnabled)
        let delete = app.buttons["sessions-edit-delete"]
        let selectAll = app.buttons["Select All"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertFalse(delete.isEnabled)
        let deleteSlot = delete.frame
        XCTAssertLessThan(selectAll.frame.midX, deleteSlot.midX)
        selectAll.tap()
        XCTAssertTrue(delete.isEnabled)
        XCTAssertEqual(delete.frame.midX, deleteSlot.midX, accuracy: 1)
        delete.tap()
        let bulk = app.alerts["Delete Sessions?"]
        XCTAssertTrue(bulk.waitForExistence(timeout: 5))
        bulk.buttons["Cancel"].tap()
        let deselectAll = app.buttons["Deselect All"]
        XCTAssertTrue(deselectAll.waitForExistence(timeout: 5))
        deselectAll.tap()
        XCTAssertFalse(delete.isEnabled)
        let destination = app.staticTexts["Toolbar destination"].firstMatch
        destination.tap()
        XCTAssertTrue(rename.isEnabled)
        XCTAssertTrue(delete.isEnabled)
        let source = app.staticTexts["Toolbar source"].firstMatch
        source.tap()
        XCTAssertFalse(rename.isEnabled)
        XCTAssertTrue(delete.isEnabled)
        source.tap()
        XCTAssertTrue(rename.isEnabled)
        XCTAssertTrue(delete.isEnabled)
        destination.tap()
        XCTAssertFalse(rename.isEnabled)
        XCTAssertFalse(delete.isEnabled)
        destination.tap()
        XCTAssertTrue(rename.isEnabled)
        XCTAssertTrue(delete.isEnabled)
        let enabledAppearance = XCTAttachment(screenshot: app.screenshot())
        enabledAppearance.name = "sessions-edit-enabled"
        enabledAppearance.lifetime = .keepAlways
        add(enabledAppearance)
        rename.tap()
        let alert = app.alerts["Rename"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Toolbar destination".count) + "Renamed session")
        alert.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Renamed session"].waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        app.staticTexts["Renamed session"].tap()
        delete.tap()
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Renamed session"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Toolbar source"].exists)
        if done.exists { done.tap() }
        bar.buttons["Close"].tap()
        XCTAssertTrue(sessions.waitForExistence(timeout: 5))
    }

    @MainActor func testSessionsBottomToolbarPreservesArabicEditingAndDeleteSlot() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "data", "-appLanguage", "ar", "-selectedSessionID", "",
            "-AppleTextDirection", "YES"]
        app.launchEnvironment["CUBEFLOW_DATA_TOOLBAR_UI_TEST"] = "1"
        app.launch()
        defer { app.terminate() }
        let previousAppearance = XCUIDevice.shared.appearance
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = previousAppearance }
        let sessions = app.navigationBars.firstMatch.buttons["جلسة"]
        XCTAssertTrue(sessions.waitForExistence(timeout: 10))
        sessions.tap()
        let bar = app.navigationBars["جلسة"]
        let edit = bar.buttons["تعديل"], done = bar.buttons["تم"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let all = app.buttons["تحديد الكل"], delete = app.buttons["sessions-edit-delete"]
        let rename = bar.buttons["إعادة تسمية"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertFalse(delete.isEnabled)
        let slot = delete.frame
        XCTAssertLessThan(all.frame.maxX, slot.minX)
        let row = app.staticTexts["Toolbar destination"].firstMatch
        row.tap()
        XCTAssertTrue(rename.isEnabled)
        XCTAssertTrue(delete.isEnabled)
        row.tap()
        XCTAssertFalse(rename.isEnabled)
        XCTAssertFalse(delete.isEnabled)
        all.tap()
        XCTAssertFalse(rename.isEnabled)
        XCTAssertTrue(delete.isEnabled)
        XCTAssertEqual(delete.frame.midX, slot.midX, accuracy: 1)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "sessions-edit-enabled-rtl"
        capture.lifetime = .keepAlways
        add(capture)
        done.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertFalse(delete.exists)
    }
}
#endif

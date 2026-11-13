import XCTest

final class TimerTouchReliabilityTests: XCTestCase {
    @MainActor func testInspectionExitInCardsAndClassicDoesNotStartOrRecordASolve() {
        continueAfterFailure = false
        for (arrangement, hidden, language) in [
            ("cards", true, "ar"),
            ("cards", false, "de"),
            ("classic", true, "en"),
            ("classic", false, "en")
        ] {
            let app = XCUIApplication()
            app.launchEnvironment["CUBEFLOW_DATA_TOOLBAR_UI_TEST"] = "1"
            app.launchArguments = ["-requestedIPhoneTab", "timer", "-appLanguage", language,
                "-selectedSessionID", "", "-enteringTimesWith", "timer",
                "-timerArrangement", arrangement, "-scrambleDisplayMode", "scroll",
                "-wcaInspectionEnabled", "YES", "-hideElementsWhenSolving", hidden ? "YES" : "NO"]
            app.launch()
            let time = app.staticTexts["timer-time-display"].firstMatch
            let exit = app.buttons["timer-inspection-exit"].firstMatch
            let scramble = app.descendants(matching: .any)["timer-scramble-control"].firstMatch
            let event = app.buttons["timer-event-menu"].firstMatch
            XCTAssertTrue(time.waitForExistence(timeout: 15))
            XCTAssertTrue(scramble.waitForExistence(timeout: 15))
            let originalScramble = scramble.label
            let originalEvent = event.label
            let idleTime = time.label
            let idleTimerY = time.frame.midY
            XCTAssertFalse(exit.exists)
            for attempt in 0..<2 {
                time.tap()
                XCTAssertTrue(exit.waitForExistence(timeout: 3))
                XCTAssertTrue(exit.isHittable)
                XCTAssertEqual(time.frame.midY, idleTimerY, accuracy: 1)
                if hidden {
                    XCTAssertLessThan(exit.frame.midX, app.frame.midX)
                    XCTAssertGreaterThan(exit.frame.minY, time.frame.maxY)
                    XCTAssertLessThan(exit.frame.maxY, app.frame.maxY)
                    XCTAssertEqual(exit.frame.width, 48, accuracy: 1)
                    XCTAssertEqual(exit.frame.height, 48, accuracy: 1)
                    XCTAssertGreaterThanOrEqual(app.frame.maxY - exit.frame.maxY, 7.5)
                    XCTAssertEqual(exit.frame.midX - app.frame.minX, app.frame.maxY - exit.frame.midY, accuracy: 1)
                    XCTAssertFalse(event.exists)
                } else {
                    XCTAssertEqual(exit.frame.midX, time.frame.midX, accuracy: 2)
                    XCTAssertGreaterThanOrEqual(exit.frame.minY, time.frame.maxY)
                    XCTAssertTrue(event.exists)
                }
                if arrangement == "classic" && !hidden && attempt == 0 {
                    let expired = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "DNF"), object: time)
                    XCTAssertEqual(XCTWaiter.wait(for: [expired], timeout: 19), .completed)
                }
                if attempt == 0 { exit.tap() } else { exit.press(forDuration: 0.15) }
                XCTAssertFalse(exit.exists)
                XCTAssertEqual(time.label, idleTime)
                XCTAssertTrue(scramble.waitForExistence(timeout: 3))
                XCTAssertEqual(scramble.label, originalScramble)
                XCTAssertEqual(event.label, originalEvent)
                XCTAssertFalse(app.alerts.firstMatch.exists)
            }
            app.terminate()
        }
    }

    @MainActor func testDynamicUpperBlankSpaceAndHeaderControls() {
        continueAfterFailure = false
        for mode in ["shrinkFont", "scroll"] {
            for arrangement in ["classic", "split", "cards"] {
                let app = XCUIApplication()
                app.launchArguments = ["-requestedIPhoneTab", "timer", "-appLanguage", "en",
                    "-enteringTimesWith", "timer", "-timerArrangement", arrangement,
                    "-scrambleDisplayMode", mode, "-wcaInspectionEnabled", "NO", "-hideElementsWhenSolving", "NO",
                    "-timerTouchDiagnostics", "YES"]
                app.launch()
                let time = app.staticTexts["timer-time-display"].firstMatch
                let event = app.buttons["timer-event-menu"].firstMatch
                let input = app.buttons["timer-input-menu"].firstMatch
                let scramble = app.descendants(matching: .any)["timer-scramble-control"].firstMatch
                XCTAssertTrue(time.waitForExistence(timeout: 15))
                XCTAssertTrue(scramble.waitForExistence(timeout: 15))
                XCTAssertTrue(event.exists && input.exists)
                let gapX = (input.frame.maxX + event.frame.minX) / 2
                XCTAssertGreaterThan(event.frame.minX, input.frame.maxX)
                let points = [
                    CGPoint(x: time.frame.midX, y: (scramble.frame.maxY + time.frame.minY) / 2),
                    CGPoint(x: gapX, y: event.frame.midY)
                ]
                for point in points {
                    let coordinate = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y))
                    let before = time.label
                    coordinate.press(forDuration: 0.08)
                    Thread.sleep(forTimeInterval: 0.3)
                    XCTAssertNotEqual(time.label, before, "Dynamic blank space must start timing: \(arrangement)/\(mode)/\(point)")
                    coordinate.tap()
                    let cancel = app.buttons["Cancel"].firstMatch
                    XCTAssertTrue(cancel.waitForExistence(timeout: 3))
                    cancel.tap()
                }
                let beforeControl = time.label
                event.tap()
                XCTAssertEqual(time.label, beforeControl, "Opening event controls must not start the timer")
                app.tap()
                scramble.tap()
                let done = app.buttons["Close"].firstMatch
                XCTAssertTrue(done.waitForExistence(timeout: 3), "Scramble interaction must retain its detail sheet")
                done.tap()
                XCTAssertEqual(time.label, beforeControl)
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "timer-dynamic-\(arrangement)-\(mode)"; attachment.lifetime = .keepAlways; add(attachment)
                app.terminate()
            }
        }
    }

    @MainActor func testDigitsAndBlankTouchesAfterIdleAcrossArrangements() {
        continueAfterFailure = false
        for arrangement in ["classic", "split", "cards"] {
            let app = XCUIApplication()
            app.launchArguments = ["-requestedIPhoneTab", "timer", "-appLanguage", "en",
                "-enteringTimesWith", "timer", "-timerArrangement", arrangement,
                "-scrambleDisplayMode", "shrinkFont", "-wcaInspectionEnabled", "NO", "-hideElementsWhenSolving", "NO",
                "-timerTouchDiagnostics", "YES"]
            app.launch()
            let time = app.staticTexts["timer-time-display"].firstMatch
            XCTAssertTrue(time.waitForExistence(timeout: 10))
            for location in ["digits", "blank-side", "blank-below", "blank-card", "quick-blank", "quick-blank"] {
                if location == "blank-below" { Thread.sleep(forTimeInterval: 3) }
                let frame = time.frame
                let point: CGPoint
                switch location {
                case "blank-side": point = CGPoint(x: 18, y: frame.midY)
                case "blank-below": point = CGPoint(x: frame.midX, y: frame.maxY + 24)
                case "blank-card": point = CGPoint(x: 35, y: app.frame.maxY - 160)
                case "quick-blank": point = CGPoint(x: 18, y: frame.midY)
                default: point = CGPoint(x: frame.midX, y: frame.midY)
                }
                let before = time.label
                let coordinate = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y))
                if location == "quick-blank" { coordinate.tap() } else { coordinate.press(forDuration: 0.08) }
                Thread.sleep(forTimeInterval: 0.35)
                let after = time.label
                print("[TimerTouchUI] \(arrangement) \(location) \(point) before=\(before) after=\(after)")
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "timer-\(arrangement)-\(location)"; attachment.lifetime = .keepAlways; add(attachment)
                XCTAssertNotEqual(before, after, "Touch must reach Timer, including the blank surface")
                coordinate.tap()
                let cancel = app.buttons["Cancel"].firstMatch
                XCTAssertTrue(cancel.waitForExistence(timeout: 3), "Stop must reach the result confirmation")
                cancel.tap()
            }
            app.terminate()
        }
    }
}

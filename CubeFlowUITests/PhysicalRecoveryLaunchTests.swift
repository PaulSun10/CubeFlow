import XCTest

#if targetEnvironment(simulator)
final class PhysicalRecoveryLaunchTests: XCTestCase {
    @MainActor func testColdLaunchShowsRestoredTimerControlsWithTracingEnabled() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "timer", "-appLanguage", "en",
            "-scrambleDisplayMode", "scroll"]
        app.launchEnvironment["CUBEFLOW_EXPERIENCE_TRACE"] = "1"
        defer { app.terminate() }
        for sample in 0..<3 {
            app.terminate()
            let start = ProcessInfo.processInfo.systemUptime
            app.launch()
            let input = app.buttons["timer-input-menu"].firstMatch
            let event = app.buttons["timer-event-menu"].firstMatch
            let scramble = app.staticTexts.matching(identifier: "timer-scramble-control")
            XCTAssertTrue(input.waitForExistence(timeout: 10))
            // Native TNoodle is unavailable in this target. Measure the real
            // restored UI, not hardware scramble generation or BLE readiness.
            let ready = expectation(for: NSPredicate { _, _ in
                let text = scramble.allElementsBoundByIndex.map(\.label).joined(separator: " ")
                return input.isHittable && event.exists && !text.isEmpty && text != "…"
            }, evaluatedWith: app)
            wait(for: [ready], timeout: 10)
            print("[PhysicalRecoveryLaunch] sample=\(sample) launch_to_timer_controls_ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000)")
        }
    }

    @MainActor func testWarmForegroundKeepsTimerControlsReady() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "timer", "-appLanguage", "en"]
        app.launch()
        defer { app.terminate() }
        let input = app.buttons["timer-input-menu"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        for sample in 0..<3 {
            XCUIDevice.shared.press(.home)
            let start = ProcessInfo.processInfo.systemUptime
            app.activate()
            let ready = expectation(for: NSPredicate { _, _ in input.isHittable }, evaluatedWith: app)
            wait(for: [ready], timeout: 10)
            print("[PerfAudit] warm_foreground sample=\(sample) ms=\((ProcessInfo.processInfo.systemUptime - start) * 1_000)")
        }
    }
}
#endif

import XCTest

final class CompetitionOrdinaryScrollTests: XCTestCase {
    @MainActor func testWarmListOrdinaryScrollOwners() throws { try record(glass: false, warm: true) }
    @MainActor func testWarmGlassOrdinaryScrollOwners() throws { try record(glass: true, warm: true) }
    @MainActor func testColdListOrdinaryScrollOwners() throws { try record(glass: false, warm: false) }
    @MainActor func testColdGlassOrdinaryScrollOwners() throws { try record(glass: true, warm: false) }

    @MainActor private func record(glass: Bool, warm: Bool) throws {
        continueAfterFailure = false
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let output = root.appendingPathComponent("build/competition-scroll-filter-oct16")
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en",
            "-competitionCardStyle", glass ? "glass" : "list", "-competition_show_top_cubers", "YES",
            "-competition_filter_status", "past", "-competition_filter_year", "all", "-competition_filter_region", "all",
            "--competition-physical-browser", "--competition-scroll-owner-timing"]
            + (warm ? ["--competition-physical-warm"] : [])
        // Keep captured text/venue sizes, but make the entire fixture Past. Both
        // the source seam and the active Browser intentionally apply that filter.
        let source = root.appendingPathComponent("build/competition-physical-acceptance-oct13/list-summaries.json")
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: source)) as? [[String: Any]])
        let beijing = try XCTUnwrap(rows.firstIndex { $0["id"] as? String == "BeijingAutumnRivalry2026" })
        rows.insert(rows.remove(at: beijing), at: 0)
        let formatter = ISO8601DateFormatter()
        for index in rows.indices {
            let date = Date().addingTimeInterval(-Double(index + 3) * 86400)
            rows[index]["startDate"] = formatter.string(from: date)
            rows[index]["endDate"] = formatter.string(from: date)
        }
        let fixture = output.appendingPathComponent("ordinary-synthetic-past-dates.json")
        try JSONSerialization.data(withJSONObject: rows).write(to: fixture)
        print("[OrdinaryCoverage] fixture=\(fixture.path) rows=\(rows.count)")
        app.launchEnvironment["CUBEFLOW_PHYSICAL_SUMMARIES"] = fixture.path
        app.launchEnvironment["CUBEFLOW_BEIJING_WCIF"] = root.appendingPathComponent("build/competition-physical-regressions/beijing-wcif.json").path
        app.launchEnvironment["CUBEFLOW_MAKATI_WCIF"] = root.appendingPathComponent("build/competition-final-ui-oct14/makati-wcif.json").path
        app.launchEnvironment["CUBEFLOW_TOKAI_WCIF"] = root.appendingPathComponent("build/competition-final-ui-oct14/tokai-wcif.json").path
        app.launch(); defer { app.terminate() }
        let list = app.collectionViews["competition-long-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 15), app.debugDescription)
        var seen = Set<String>()
        for index in 0..<4 {
            if index == 3 { list.swipeDown(velocity: .fast) }
            else { list.swipeUp(velocity: index == 0 ? .slow : .fast) }
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "\"idleRecordingComplete\":true"), object: list)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 4), .completed)
            let text = try XCTUnwrap(list.value as? String)
            let trace = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            let samples = try XCTUnwrap(trace["owners"] as? [[String: Any]])
            XCTAssertGreaterThan(samples.count, 5)
            let first = try XCTUnwrap(samples.first)
            let size = try XCTUnwrap(first["contentSize"] as? [Double])
            let viewport = try XCTUnwrap(first["viewport"] as? [Double])
            print("[OrdinaryCoverage] gesture=\(index) height=\(size[1]) viewport=\(viewport[3])")
            XCTAssertGreaterThan(size[1], viewport[3] * 3, "Do not mistake short-content boundary bounce for a long-list failure")
            for sample in samples {
                for cell in (sample["cells"] as? [[String: Any]]) ?? [] {
                    if let id = cell["id"] as? String { seen.insert(id) }
                }
            }
            XCTAssertTrue(samples.contains { $0["dragging"] as? Bool == true })
            XCTAssertTrue(samples.contains { $0["dragging"] as? Bool == false && $0["decelerating"] as? Bool == false })
            XCTAssertTrue(samples.contains { sample in
                (sample["cells"] as? [[String: Any]])?.contains {
                    !(($0["elements"] as? [[String: Any]]) ?? []).isEmpty
                } == true
            }, "Capture hosted content, not just collection offsets")
            let name = "ordinary-\(warm ? "warm" : "cold")-\(glass ? "glass" : "list")-\(index)"
            try text.write(to: output.appendingPathComponent(name + ".json"), atomically: true, encoding: .utf8)
            let attachment = XCTAttachment(string: text); attachment.name = name
            attachment.lifetime = .keepAlways; add(attachment)
            var idlePullback = 0.0
            for (previous, current) in zip(samples, samples.dropFirst()) {
                guard current["dragging"] as? Bool == false, current["decelerating"] as? Bool == false,
                      let oldOffset = previous["offset"] as? [Double], let newOffset = current["offset"] as? [Double],
                      abs(oldOffset[1] - newOffset[1]) < 0.01,
                      let minimum = current["minimumOffset"] as? Double,
                      let maximum = current["maximumOffset"] as? Double,
                      newOffset[1] > minimum + 1, newOffset[1] < maximum - 1,
                      let oldCells = previous["cells"] as? [[String: Any]],
                      let newCells = current["cells"] as? [[String: Any]] else { continue }
                for cell in newCells {
                    guard let id = cell["id"] as? String,
                          let old = oldCells.first(where: { $0["id"] as? String == id }),
                          let oldFrame = old["cellModel"] as? [Double],
                          let newFrame = cell["cellModel"] as? [Double] else { continue }
                    idlePullback = max(idlePullback, oldFrame[1] - newFrame[1])
                }
            }
            print("[OrdinaryCoverage] \(name) idleCellPullback=\(idlePullback)")
            XCTAssertLessThanOrEqual(idlePullback, 1, "Empty Top Cubers publication must not pull stable visible cells upward at idle")
        }
        XCTAssertGreaterThanOrEqual(seen.count, 8, "Exercise virtualization across mixed cells, not one bouncing card")
    }
}

import XCTest
import UIKit

final class CompetitionResultsNavigationAcceptanceTests: XCTestCase {
    @MainActor func testActualPublishedDetailBackgroundBackWithCard() throws {
        continueAfterFailure = false
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en", "--competition-real-detail-acceptance"]
        app.launchEnvironment["CUBEFLOW_ACCEPTANCE_COMPETITION_ID"] = "MariettaMondayMiniIV2026"
        app.launchEnvironment["CUBEFLOW_ACCEPTANCE_PUBLISHED_JSON"] = root.appendingPathComponent("build/competition-reliability-oct14/marietta-results.json").path
        app.launch(); defer { app.terminate() }
        let entry = app.buttons["Open captured competition"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15)); entry.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "competition-result-published-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription); row.tap()
        XCTAssertTrue(app.buttons["competition-result-close"].waitForExistence(timeout: 5))
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "actual-detail-background-back-before"; image.lifetime = .keepAlways; add(image)
        let back = app.buttons["competition-detail-back"]
        XCTAssertTrue(back.isHittable, app.debugDescription)
        back.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["competition-result-close"].exists)
    }
    @MainActor func testFilterRecoversAcrossBackgroundForegroundWithoutRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en"]
        app.launch(); defer { app.terminate() }
        let filter = app.buttons["competition-filter"]
        let close = app.buttons["competition-filter-close"]
        XCTAssertTrue(filter.waitForExistence(timeout: 15))
        for _ in 0..<4 {
            filter.tap()
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            XCUIDevice.shared.press(.home)
            let background = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.state == .runningBackground || app.state == .runningBackgroundSuspended
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [background], timeout: 5), .completed)
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
            if close.exists { close.tap() }
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"), object: close)
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
            XCTAssertTrue(filter.waitForExistence(timeout: 5))
            filter.tap()
            XCTAssertTrue(close.waitForExistence(timeout: 5), "Scene restoration must not leave Filter locked")
            XCTAssertEqual(app.buttons.matching(identifier: "competition-filter-close").count, 1)
            close.tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == NO"), object: close)], timeout: 5), .completed)
        }
    }
    @MainActor func testWangRoundSeparatorsInNativeCompositor() throws {
        continueAfterFailure = false
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("build/competition-reliability-oct14/beijing-333-results.json")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Requires complete captured public 3x3 results") }
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en",
            "--competition-results-acceptance", "--competition-render-uninstrumented"]
        app.launchEnvironment["CUBEFLOW_ACCEPTANCE_PUBLISHED_JSON"] = file.path
        app.launch(); defer { app.terminate() }
        let mode = app.buttons["By Competitor"]
        XCTAssertTrue(mode.waitForExistence(timeout: 15)); mode.tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Yiheng\n")
        let person = app.buttons["published-competitor-2019WANY36"]
        XCTAssertTrue(person.waitForExistence(timeout: 5)); person.tap()
        XCTAssertTrue(app.buttons["competition-result-close"].waitForExistence(timeout: 5))
        let card = app.otherElements["competition-result-card"]
        let names = ["First round", "Second round", "Semi Final", "Final"]
        let frames = try names.map { name -> CGRect in
            let row = card.staticTexts[name].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), name)
            return row.frame
        }
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot); attachment.name = "wang-native-compositor-uninstrumented"
        attachment.lifetime = .keepAlways; add(attachment)
        try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/cubeflow-wang-native-compositor.png"))
        let cg = try XCTUnwrap(screenshot.image.cgImage)
        let scale = CGFloat(cg.width) / app.frame.width
        var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        func luminance(_ x: Int, _ y: Int) -> Double {
            let i = (y * cg.width + x) * 4
            return Double(Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) / 3
        }
        let x = Int(card.frame.midX * scale)
        for (previous, current) in zip(frames, frames.dropFirst()) {
            let y = Int((previous.midY + current.midY) / 2 * scale)
            XCTAssertTrue(x >= 0 && x < cg.width && y > 8 && y < cg.height - 8)
            guard x >= 0, x < cg.width, y > 8, y < cg.height - 8 else { continue }
            let background = (luminance(x, y - 8) + luminance(x, y + 8)) / 2
            let contrast = (y - 3...y + 3).map { abs(luminance(x, $0) - background) }.max() ?? 0
            print("[NativeRule] y=\(CGFloat(y) / scale) contrast=\(contrast) previous=\(previous) next=\(current)")
            XCTAssertGreaterThan(contrast, 1, "The on-screen compositor must paint every boundary")
        }
    }
    @MainActor func testDetailBackDismissesCardAndReturnsToParent() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en", "--competition-results-detail-acceptance"]
        app.launch(); defer { app.terminate() }
        let entry = app.buttons["Open Results"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15)); entry.tap()
        let row = app.buttons["competition-sum-ranks-row-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.buttons["competition-result-close"].waitForExistence(timeout: 5))
        let back = app.buttons["competition-detail-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(back.isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "native-detail-back-with-card"
        shot.lifetime = .keepAlways; add(shot)
        back.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["competition-result-close"].exists)
        XCTAssertFalse(row.exists)
        entry.tap(); XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap(); XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap(); XCTAssertTrue(entry.waitForExistence(timeout: 5))
    }

    @MainActor func testNamedOfficialDatasetsOpenRepeatedCompetitorCards() throws {
        continueAfterFailure = false
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let datasets = [("MariettaMondayMiniIV2026", "marietta-results.json"), ("MNQuietChampionship2026", "minnesota-results.json")]
        for (id, filename) in datasets {
            let file = root.appendingPathComponent("build/competition-reliability-oct14/" + filename)
            guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Requires captured public named-competition results") }
            let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
            let person = try XCTUnwrap(rows.first { ($0["wca_id"] as? String)?.isEmpty == false })
            let personID = try XCTUnwrap(person["wca_id"] as? String)
            let app = XCUIApplication()
            app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en", "--competition-results-acceptance"]
            app.launchEnvironment["CUBEFLOW_ACCEPTANCE_PUBLISHED_JSON"] = file.path
            app.launchEnvironment["CUBEFLOW_ACCEPTANCE_COMPETITION_ID"] = id
            app.launch(); defer { app.terminate() }
            let mode = app.buttons["By Competitor"]
            XCTAssertTrue(mode.waitForExistence(timeout: 15)); mode.tap()
            let search = app.textFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(personID + "\n")
            let row = app.buttons["published-competitor-" + personID]
            for _ in 0..<4 {
                XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
                let close = app.buttons["competition-result-close"]
                XCTAssertTrue(close.waitForExistence(timeout: 5), id)
                let card = app.otherElements["competition-result-card"]
                XCTAssertTrue(card.exists)
                XCTAssertFalse(app.buttons["competition-all-results-back"].exists)
                let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "official-card-" + id
                shot.lifetime = .keepAlways; add(shot)
                close.tap()
            }
            app.terminate()
        }
    }
    @MainActor func testOfficialByCompetitorUsesCompleteDownloadedProductionResults() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/competition-physical-regressions/beijing-results.json")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Requires the captured full public response") }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en", "--competition-results-acceptance"]
        app.launchEnvironment["CUBEFLOW_ACCEPTANCE_PUBLISHED_JSON"] = file.path
        app.launch(); defer { app.terminate() }
        let mode = app.buttons["By Competitor"]
        XCTAssertTrue(mode.waitForExistence(timeout: 15), app.debugDescription)
        mode.tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Tymon\n")
        let person = app.buttons["published-competitor-2016KOLA02"]
        XCTAssertTrue(person.waitForExistence(timeout: 5)); person.tap()
        XCTAssertTrue(app.buttons["competition-result-close"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["competition-all-results-back"].exists)
        let card = app.otherElements["competition-result-card"]
        XCTAssertTrue(card.exists)
        let flag = card.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "\u{1F1F5}\u{1F1F1}")).firstMatch
        XCTAssertTrue(flag.waitForExistence(timeout: 5), "Country from the same selected competitor must be visible")
        for title in ["2x2x2 Cube", "3x3x3 Cube", "4x4x4 Cube", "5x5x5 Cube", "6x6x6 Cube", "7x7x7 Cube"] {
            XCTAssertTrue(card.staticTexts[title].exists, title)
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "official-beijing-all-results"
        shot.lifetime = .keepAlways; add(shot)
        app.buttons["competition-wca-profile"].tap()
        let profileBar = app.navigationBars["Tymon Kolasiński"]
        XCTAssertTrue(profileBar.waitForExistence(timeout: 10), "The existing Profile link must retain native navigation\n\(app.debugDescription)")
        let back = profileBar.buttons["BackButton"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: back)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        back.tap()
        XCTAssertTrue(app.buttons["competition-result-close"].waitForExistence(timeout: 5))
    }

    @MainActor func testOfficialByCompetitorShowsRecordBadgesAndIndependentSolveAccess() throws {
        continueAfterFailure = false
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/competition-physical-regressions/beijing-results.json")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Requires captured official results") }
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en", "--competition-results-acceptance"]
        app.launchEnvironment["CUBEFLOW_ACCEPTANCE_PUBLISHED_JSON"] = file.path
        app.launch(); defer { app.terminate() }
        let mode = app.buttons["By Competitor"]
        XCTAssertTrue(mode.waitForExistence(timeout: 15)); mode.tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Tymon\n")
        let person = app.buttons["published-competitor-2016KOLA02"]
        XCTAssertTrue(person.waitForExistence(timeout: 5)); person.tap()
        let card = app.otherElements["competition-result-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.staticTexts["NR"].firstMatch.exists, "The official By Competitor path must retain verified record metadata")
        let tables = card.scrollViews.matching(identifier: "competition-all-results-table")
        XCTAssertGreaterThanOrEqual(tables.count, 2)
        let first = tables.element(boundBy: 0), second = tables.element(boundBy: 1)
        XCTAssertEqual(first.staticTexts.matching(identifier: "Results").count, 1)
        let firstRound = first.staticTexts["First round"].firstMatch
        let secondBest = second.staticTexts["Best"].firstMatch
        XCTAssertTrue(firstRound.exists); XCTAssertTrue(secondBest.exists)
        let initialX = firstRound.frame.minX, otherX = secondBest.frame.minX
        first.swipeLeft()
        XCTAssertLessThan(firstRound.frame.minX, initialX - 20)
        XCTAssertEqual(secondBest.frame.minX, otherX, accuracy: 1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "official-by-competitor-horizontal-solves"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["competition-result-close"].tap()
        XCTAssertTrue(person.waitForExistence(timeout: 5))
    }

    @MainActor func testSumRowOpensCompleteDirectCardAndRoundEntryRetainsBack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en", "--competition-results-acceptance"]
        app.launch(); defer { app.terminate() }
        let row = app.buttons["competition-sum-ranks-row-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 15)); XCTAssertTrue(row.isHittable)
        let timerFrame = app.tabBars.buttons["Timer"].frame
        XCTAssertTrue(row.label.contains("United Kingdom"), row.label)
        row.tap()
        let close = app.buttons["competition-result-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5)); XCTAssertTrue(close.isHittable)
        XCTAssertFalse(app.buttons["competition-all-results-back"].exists)
        XCTAssertTrue(app.staticTexts["3x3x3 Cube"].exists)
        XCTAssertTrue(app.staticTexts["2x2x2 Cube"].exists, "All events, not an arbitrary round")
        let tables = app.scrollViews.matching(identifier: "competition-all-results-table")
        XCTAssertEqual(tables.count, 2, app.debugDescription)
        for table in tables.allElementsBoundByIndex {
            XCTAssertEqual(table.frame.width, min(app.frame.width - 32, 430) - 44, accuracy: 1)
        }
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "scene-wide-all-results-card"; image.lifetime = .keepAlways; add(image)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: timerFrame.midX, dy: timerFrame.midY)).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Explore"].isSelected, "A backdrop tap must not activate the underlying Timer tab")
        row.tap(); XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap(); XCTAssertTrue(row.waitForExistence(timeout: 5))
        app.buttons["competition-acceptance-round"].tap()
        let back = app.buttons["competition-all-results-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5)); XCTAssertTrue(close.exists)
        back.tap(); XCTAssertFalse(back.exists); XCTAssertTrue(close.exists)
        close.tap(); XCTAssertTrue(row.isHittable)
    }

    @MainActor func testFilterUsesOriginalPopoverControlsAndRepeatedReopening() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-requestedIPhoneTab", "competitions", "-appLanguage", "en", "--competition-filter-acceptance", "--competition-filter-timing"]
        app.launch(); defer { app.terminate() }
        let filter = app.buttons["competition-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 15))
        filter.tap()
        XCTAssertTrue(app.buttons["competition-filter-close"].waitForExistence(timeout: 5))
        app.buttons["All Countries/Regions"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["competition-filter-close"].waitForExistence(timeout: 5))
        app.buttons["Present"].tap()
        XCTAssertTrue(app.staticTexts["Event"].exists)
        XCTAssertFalse(app.staticTexts["Year"].exists)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "restored-native-filter-popover"
        image.lifetime = .keepAlways; add(image)
        XCTAssertTrue(app.buttons["Recent"].exists)
        XCTAssertTrue(app.buttons["Past"].exists)
        app.buttons["Past"].tap()
        XCTAssertTrue(app.staticTexts["Year"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Present"].tap()
        XCTAssertFalse(app.staticTexts["Year"].exists)
        for _ in 0..<3 {
            app.buttons["competition-filter-close"].tap()
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: filter)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
            filter.tap()
            XCTAssertTrue(app.buttons["competition-filter-close"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Present"].isSelected)
        }
        app.buttons["competition-filter-close"].tap()
        filter.tap()
        XCTAssertTrue(app.buttons["competition-filter-close"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 20, dy: 500)).tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"), object: app.buttons["competition-filter-close"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        filter.tap()
        XCTAssertTrue(app.buttons["competition-filter-close"].waitForExistence(timeout: 5), "Outside dismissal must release presentation ownership")
        app.buttons["competition-filter-close"].tap()
        let toolbar = XCTAttachment(screenshot: app.screenshot()); toolbar.name = "restored-shared-map-filter-toolbar"
        toolbar.lifetime = .keepAlways; add(toolbar)
    }
}

import XCTest
import SwiftUI
@testable import CubeFlow

@MainActor final class CompetitionAllResultsTableTests: XCTestCase {
    private func result(_ id: String = "333", round: Int = 1, attempts: [Int] = [912, 876, 798, 934, 921],
                        format: String = "a", count: Int = 5) -> CompetitionWCALiveCompetitorResult {
        .init(id: "\(id)-\(round)", ranking: 1, isAdvancing: round < 5, isAdvancingQuestionable: false,
            attempts: attempts, best: attempts.first ?? 0, average: count > 1 ? 928 : 0,
            singleRecordTag: round == 1 ? "NR" : nil, averageRecordTag: round == 1 && count > 1 ? "PR" : nil,
            roundID: String(round), roundName: "Round \(round)", roundNumber: round, eventID: id,
            eventName: CompetitionEventPresentation.officialName(for: id), eventRank: ["333", "666", "333bf"].firstIndex(of: id),
            formatID: format, numberOfAttempts: count, sortBy: count > 1 ? "average" : "best")
    }
    private func views(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(views) }
    private func settle(_ window: UIWindow) async throws {
        for _ in 0..<20 { window.layoutIfNeeded(); try await Task.sleep(nanoseconds: 30_000_000) }
    }
    private func mount<V: View>(_ root: V) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 960)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        return window
    }
    func testActualSolvesAndOneHeaderReuseCanonicalFormatter() {
        let five = result(), three = result("666", attempts: [6234, -1, -2], format: "m", count: 3)
        let one = result("333bf", attempts: [10456, 0, 0, 0, 0], format: "1", count: 1)
        XCTAssertEqual(CompetitionAllResultsDisplay.attempts(five), ["9.12", "8.76", "7.98", "9.34", "9.21"])
        XCTAssertEqual(CompetitionAllResultsDisplay.attempts(three), ["1:02.34", "DNF", "DNS"])
        XCTAssertEqual(CompetitionAllResultsDisplay.attempts(one), ["1:44.56"])
        XCTAssertEqual(CompetitionAllResultsDisplay.attempts(result(attempts: [0, 912, 0, -1, 0])), ["", "9.12", "", "DNF"])
        XCTAssertEqual(CompetitionAllResultsDisplay.attempts(result(attempts: [0, 0, 0])), [])
        // The provider stores +2-inclusive centiseconds, not a separate penalty flag.
        XCTAssertEqual(CompetitionAllResultsDisplay.attempts(result(attempts: [912 + 200])), ["11.12"])
        for (value, count) in [(five, 5), (three, 3), (one, 1)] {
            let plan = CompetitionAllResultsSolves(results: [value], language: "en")
            XCTAssertEqual(plan.widths.count, count)
            XCTAssertEqual(plan.headers, ["Results"] + Array(repeating: "", count: count - 1))
            let shift = CompetitionAllResultsSolves.originAdjustment(value: CompetitionAllResultsDisplay.attempts(value)[0], header: plan.headers[0])
            XCTAssertEqual(plan.width, plan.widths.reduce(0, +) + CGFloat(count) * 12 + max(0, shift))
        }
        let moves = result("333fm", attempts: [25, 26, 27], format: "m", count: 3)
        XCTAssertEqual(CompetitionAllResultsDisplay.attempts(moves), ["25", "26", "27"])
    }

    nonisolated private func formatOffActor(_ values: [CompetitionWCALiveCompetitorResult]) -> [[String]] {
        values.map(CompetitionAllResultsDisplay.attempts)
    }

    func testFormattingFunctionReferenceIsAvailableWithoutAnActorHop() {
        XCTAssertEqual(formatOffActor([result()]), [["9.12", "8.76", "7.98", "9.34", "9.21"]])
    }

    func testMountedSolveTailAddsFourPointsToAcceptedInterValueGap() async throws {
        for attempts in [[912, 876, 798, 934, 921], [6234, -1, -2, 10456, 360123]] {
            let value = result(attempts: attempts)
            let texts = CompetitionAllResultsDisplay.attempts(value)
            let plan = CompetitionAllResultsSolves(results: [value], language: "en")
            CompetitionResultSeparatorDiagnostics.rows = [:]
            let window = try mount(CompetitionAllResultsSolveCells(plan: plan, values: texts, traceID: "gap")
                .fixedSize().frame(height: 36).environment(\.colorScheme, .light))
            defer { window.isHidden = true; window.rootViewController = nil }
            try await settle(window)
            for index in 1..<texts.count {
                let previous = try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows["gap-\(index - 1)"])
                let current = try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows["gap-\(index)"])
                let ink = (texts[index] as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 14)]).width
                let actualGap = current.maxX - CompetitionAllResultsSolves.horizontalPadding - ink
                    - (previous.maxX - CompetitionAllResultsSolves.horizontalPadding)
                let acceptedGap = ceil(ink) + 8 - ink
                XCTAssertEqual(actualGap, acceptedGap + 4, accuracy: 0.01)
                XCTAssertLessThan(plan.widths[index], max(62, ceil(ink)) + 0.01)
                XCTAssertEqual(current.minX, previous.maxX, accuracy: 0.01)
            }
            XCTAssertEqual(plan.headers, ["Results", "", "", "", ""])
        }
    }

    func testAllThreeEventTablesKeepLeadingSummaryAndIndependentNativeHorizontalOwners() async throws {
        var results: [CompetitionWCALiveCompetitorResult] = []
        for round in 1...5 {
            results += [result(round: round), result("666", round: round, attempts: [6234, -1, -2], format: "m", count: 3),
                        result("333bf", round: round, attempts: [10456], format: "1", count: 1)]
        }
        let content = CompetitionWCALiveCompetitorContent(id: "person", name: "Horizontal solve access",
            wcaID: nil, countryISO2: "US", results: results)
        let state = CompetitionResultCardState()
        state.presentCompetition(id: content.id, name: content.name, content: content)
        CompetitionResultSeparatorDiagnostics.rows = [:]
        let window = try mount(CompetitionResultExperience(round: state.selection!.round, languageCode: "en", cardState: state, mode: .card))
        defer { window.isHidden = true; window.rootViewController = nil; state.close() }
        try await settle(window)
        let anchors = views(window).compactMap { $0 as? CompetitionHorizontalTableBoundaryAnchor }
        let owners = anchors.compactMap(\.scrollView).filter { $0.window != nil }
        XCTAssertEqual(owners.count, 3)
        XCTAssertEqual(Set(owners.map(ObjectIdentifier.init)).count, 3)
        let allScrolls = views(window).compactMap { $0 as? UIScrollView }
        let vertical = try XCTUnwrap(allScrolls.first { candidate in
            !owners.contains(where: { $0 === candidate }) && owners.allSatisfy { $0.isDescendant(of: candidate) }
        })
        XCTAssertTrue(vertical.bounces, "The outer card keeps native vertical scrolling")
        XCTAssertGreaterThan(vertical.contentSize.height, vertical.bounds.height)
        let verticalOffset = vertical.contentOffset
        for owner in owners {
            XCTAssertFalse(owner.bounces)
            XCTAssertFalse(owner.alwaysBounceHorizontal)
            XCTAssertEqual(owner.contentOffset.x, -owner.adjustedContentInset.left, accuracy: 0.01)
            XCTAssertEqual(owner.bounds.width, 314, accuracy: 1)
            XCTAssertGreaterThan(owner.contentSize.width, owner.bounds.width)
        }
        let initial = owners.map(\.contentOffset)
        let first = try XCTUnwrap(owners.first)
        let end = CGRect(x: first.contentSize.width - 1, y: 0, width: 1, height: 1)
        first.scrollRectToVisible(end, animated: false)
        try await settle(window)
        XCTAssertEqual(first.contentOffset.x, first.contentSize.width - first.bounds.width + first.adjustedContentInset.right, accuracy: 1)
        for index in 1..<owners.count { XCTAssertEqual(owners[index].contentOffset, initial[index]) }
        XCTAssertEqual(vertical.contentOffset, verticalOffset)
        first.scrollRectToVisible(CGRect(x: 0, y: 0, width: 1, height: 1), animated: false)
        try await settle(window)
        XCTAssertEqual(first.contentOffset.x, -first.adjustedContentInset.left, accuracy: 0.01)
        for id in ["333", "666", "333bf"] {
            let row = try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows["\(id)-1"])
            let header = try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows["\(id)-solve-header-0"])
            let solve = try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows["\(id)-1-solve-0"])
            XCTAssertEqual(row.height, 36, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(row.width, 314)
            XCTAssertEqual(header.minX, row.maxX, accuracy: 0.01, "Solves start strictly after the original summary block")
            XCTAssertEqual(solve.minX, header.minX, accuracy: 0.01)
            let firstValue = try XCTUnwrap(results.first { $0.eventID == id })
            let plan = CompetitionAllResultsSolves(results: [firstValue], language: "en")
            XCTAssertEqual(solve.width, plan.cellWidth(0, values: CompetitionAllResultsDisplay.attempts(firstValue)) + 12, accuracy: 0.01)
        }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let shot = XCTAttachment(image: image); shot.name = "all-results-independent-summary-tables"; shot.lifetime = .keepAlways; add(shot)
    }

    func testOfficialByCompetitorAndRoundAdaptersPreserveEveryVerifiedRecordTag() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("build/competition-physical-regressions/beijing-results.json")
        let rows = try PublishedCompetitionService.decodeResults(Data(contentsOf: file), competitionID: "BeijingAutumnRivalry2026")
        let data = PublishedCompetitionData(competitionID: "BeijingAutumnRivalry2026", results: rows)
        let records = rows.filter { $0.singleBadge != nil || $0.averageBadge != nil }
        XCTAssertFalse(records.isEmpty)
        for record in records {
            let all = try XCTUnwrap(PublishedCompetitionPresentation.competitor(record.wcaID, data: data, language: "en"))
            let direct = try XCTUnwrap(all.results.first { $0.id == "published-\(record.id)" })
            let round = try XCTUnwrap(data.rounds.first { $0.id == record.roundKey })
            let preview = try XCTUnwrap(PublishedCompetitionPresentation.round(round, language: "en", data: data).results.first { $0.id == direct.id })
            XCTAssertEqual(direct.singleRecordTag, preview.singleRecordTag)
            XCTAssertEqual(direct.averageRecordTag, preview.averageRecordTag)
            XCTAssertEqual(direct.singleRecordTag, record.singleBadge)
            XCTAssertEqual(direct.averageRecordTag, record.averageBadge)
            let rendered = PublishedResultPresentation.values(record)
            XCTAssertEqual(rendered.first { $0.id == "best" }?.recordTag, direct.singleRecordTag)
            if record.showsAverage { XCTAssertEqual(rendered.first { $0.id == "average" }?.recordTag, direct.averageRecordTag) }
        }
    }

    func testNativeBoundaryConfigurationRestoresOnlyItsOwnOwnerOnDetach() {
        let vertical = UIScrollView(), horizontal = UIScrollView()
        vertical.bounces = true; horizontal.bounces = true; horizontal.alwaysBounceHorizontal = true
        vertical.addSubview(horizontal)
        let anchor = CompetitionHorizontalTableBoundaryAnchor()
        horizontal.addSubview(anchor); anchor.attach()
        XCTAssertTrue(anchor.scrollView === horizontal)
        XCTAssertFalse(horizontal.bounces)
        XCTAssertFalse(horizontal.alwaysBounceHorizontal)
        XCTAssertTrue(vertical.bounces)
        anchor.detach()
        XCTAssertTrue(horizontal.bounces)
        XCTAssertTrue(horizontal.alwaysBounceHorizontal)
        XCTAssertTrue(vertical.bounces)
    }

    func testMountedFirstSolveInkAlignsWithStationaryHeaderInEveryLanguage() async throws {
        for language in ["en", "zh-Hans", "zh-Hant"] {
            for attempts in [[852, 913, 876, 941, 893], [-1, -2, 360123, 812, 750]] {
                let value = result(attempts: attempts)
                let texts = CompetitionAllResultsDisplay.attempts(value)
                let plan = CompetitionAllResultsSolves(results: [value], language: language)
                CompetitionResultSeparatorDiagnostics.rows = [:]
                let root = VStack(spacing: 20) {
                    CompetitionAllResultsSolveCells(plan: plan, traceID: "ink-header")
                    CompetitionAllResultsSolveCells(plan: plan, values: texts, traceID: "ink-values")
                }.fixedSize().environment(\.colorScheme, .light)
                let window = try mount(root)
                window.rootViewController?.view.backgroundColor = .white
                defer { window.isHidden = true; window.rootViewController = nil }
                try await settle(window)
                let header = try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows["ink-header-0"])
                let row = try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows["ink-values-0"])
                let format = UIGraphicsImageRendererFormat(); format.scale = 3; format.opaque = true
                let snapshot = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let image = try XCTUnwrap(snapshot.cgImage)
                let bytes = try XCTUnwrap(image.dataProvider?.data) as Data
                func leftInk(_ rect: CGRect) -> CGFloat? {
                    var left: Int?
                    for y in max(0, Int(rect.minY * 3))..<min(image.height, Int(rect.maxY * 3)) {
                        for x in max(0, Int(rect.minX * 3))..<min(image.width, Int(rect.maxX * 3)) {
                            let offset = y * image.bytesPerRow + x * 4
                            if bytes[offset] < 100 && bytes[offset + 1] < 100 && bytes[offset + 2] < 100 { left = min(left ?? x, x) }
                        }
                    }
                    return left.map { CGFloat($0) / 3 }
                }
                XCTAssertEqual(try XCTUnwrap(leftInk(header)), try XCTUnwrap(leftInk(row)), accuracy: 1 / 3 + 0.01, "\(language), \(texts)")
                XCTAssertEqual(header.width, plan.widths[0] + 12, accuracy: 0.01)
                for index in 1..<texts.count {
                    let previous = try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows["ink-values-\(index - 1)"])
                    let current = try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows["ink-values-\(index)"])
                    XCTAssertEqual(current.minX, previous.maxX, accuracy: 0.01)
                    XCTAssertEqual(current.width, plan.widths[index] + 12, accuracy: 0.01)
                }
                let shot = XCTAttachment(image: snapshot); shot.name = "solve-ink-\(language)-\(texts[0])"; shot.lifetime = .keepAlways; add(shot)
            }
        }
    }

}

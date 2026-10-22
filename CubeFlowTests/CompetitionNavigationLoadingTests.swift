import XCTest
import SwiftUI
import Combine
@testable import CubeFlow

@MainActor private final class DisclosureProbe: ObservableObject {
    @Published var expanded = false
}
@MainActor private final class BrowserActivityProbe: ObservableObject {
    @Published var active = true
}
private struct BrowserPublicationFixture: View {
    private let scope = CompetitionBrowserPublicationAcceptance.scope
    @ObservedObject var activity: BrowserActivityProbe
    let onSnapshot: (CompetitionBrowserPublicationSnapshot) -> Void
    var body: some View {
        CompetitionBrowserView(isActive: activity.active)
            .environment(\.competitionBrowserPublicationEnabled, true)
            .environment(\.competitionBrowserPublicationScope, scope)
            .onPreferenceChange(CompetitionBrowserPublicationKey.self) { if let value = $0 { onSnapshot(value) } }
    }
}
private struct HostedDisclosureFixture: View {
    @ObservedObject var probe: DisclosureProbe
    let values: [CompetitionTopCuberPreview]
    var body: some View {
        CompetitionExpandableTopCubers(previews: values, language: "en", expansion: $probe.expanded) { item in
            Text(item.name).font(.system(size: 13)).padding(8)
        }.padding(16)
    }
}
@MainActor private final class HostingRows: NSObject, UICollectionViewDataSource {
    let probe = DisclosureProbe()
    let values = (0..<24).map { CompetitionTopCuberPreview(id: String($0), name: "Competitor \($0)", badges: []) }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 3 }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "row", for: indexPath) as! CompetitionHostingCollectionViewCell
        if indexPath.item == 1 { cell.setRootView(AnyView(HostedDisclosureFixture(probe: probe, values: values))) }
        else { cell.setRootView(AnyView(Color.clear.frame(height: indexPath.item == 0 ? 240 : 1800))) }
        return cell
    }
}

@MainActor final class CompetitionNavigationLoadingTests: XCTestCase {
    func testListPublicationRejectsChangedInactiveAndCancelledQueryRequests() async {
        XCTAssertTrue(competitionListRequestIsCurrent(expected: "present", current: "present", isActive: true))
        XCTAssertFalse(competitionListRequestIsCurrent(expected: "present", current: "recent", isActive: true))
        XCTAssertFalse(competitionListRequestIsCurrent(expected: "present", current: "present", isActive: false))
        var release: CheckedContinuation<Void, Never>?
        let task = Task { @MainActor in
            await withCheckedContinuation { release = $0 }
            // Present -> Recent -> Present is an ABA: signature equality alone
            // cannot authorize publication by the cancelled original task.
            return competitionListRequestIsCurrent(expected: "present", current: "present", isActive: true)
        }
        for _ in 0..<100 where release == nil { await Task.yield() }
        XCTAssertNotNil(release)
        task.cancel()
        release?.resume()
        let accepts = await task.value
        XCTAssertFalse(accepts)
    }
    func testActualBrowserRejectsSuspendedCacheAcrossPresentRecentPresent() async throws {
        for _ in 0..<12 { try await exerciseActualBrowserSuspendedCacheABA() }
    }
    func testActualBrowserRejectsSuspendedPageAndErrorAcrossPresentRecentPresent() async throws {
        for fails in [false, true] {
            for _ in 0..<4 { try await exerciseActualBrowserSuspendedCacheABA(suspendsPage: true, fails: fails) }
        }
    }
    func testActualBrowserReactivationDoesNotWaitForCancelledCacheResponse() async throws {
        for _ in 0..<4 { try await exerciseActualBrowserSuspendedCacheABA(reactivates: true) }
    }
    private func exerciseActualBrowserSuspendedCacheABA(suspendsPage: Bool = false, fails: Bool = false,
                                                       reactivates: Bool = false) async throws {
        let defaults = UserDefaults.standard
        CompetitionBrowserPublicationAcceptance.scope = UUID()
        let keys = ["appLanguage", "competition_filter_status", "competition_filter_region",
            "competition_filter_year", "competition_filter_events", "competition_show_top_cubers"]
        let previous = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        var gate: CheckedContinuation<CompetitionCacheSnapshot?, Never>?
        var pageGate: CheckedContinuation<Result<CompetitionPageResult, Error>, Never>?
        var presentReads = 0
        var snapshots: [CompetitionBrowserPublicationSnapshot] = []
        var publications: [CompetitionBrowserPublicationSnapshot] = []
        CompetitionBrowserPublicationAcceptance.published = { publications.append($0) }
        var displayedIDs: [String] = []
        var displayedHistory: [[String]] = []
        CompetitionBrowserPublicationAcceptance.displayed = {
            displayedIDs = $0; displayedHistory.append($0)
        }
        let activity = BrowserActivityProbe()
        func fixture(_ id: String, days: TimeInterval) -> CompetitionSummary {
            let date = Calendar.current.startOfDay(for: Date()).addingTimeInterval(days * 86400)
            return CompetitionSummary(id: id, name: id, shortDisplayName: nil, startDate: date, endDate: date,
                registrationOpen: nil, registrationClose: nil, competitorLimit: nil, venue: "", venueAddress: "",
                venueDetails: nil, city: "Fixture", countryISO2: "US", latitude: nil, longitude: nil,
                url: "https://www.worldcubeassociation.org/competitions/\(id)", website: nil,
                dateRange: "Fixture", eventIDs: ["333"], championshipTypes: nil,
                localizedRegionLineOverride: nil, localizedAddressLineOverride: nil, localizedStatusOverride: nil,
                localizedRegistrationStartOverride: nil, localizedWaitlistStartOverride: nil)
        }
        let old = fixture("race-present-old", days: 2)
        let fresh = fixture("race-present-fresh", days: 2)
        let recent = fixture("race-recent", days: -2)
        CompetitionBrowserPublicationAcceptance.cache = { query in
            if suspendsPage { return nil }
            if query.status == .present {
                presentReads += 1
                if presentReads == 1 { return await withCheckedContinuation { gate = $0 } }
            }
            return CompetitionCacheSnapshot(competitions: [query.status == .recent ? recent : fresh],
                totalCount: 1, lastUpdated: Date())
        }
        CompetitionBrowserPublicationAcceptance.page = { query, _ in
            if suspendsPage, query.status == .present {
                presentReads += 1
                if presentReads == 1 {
                    let result = await withCheckedContinuation { pageGate = $0 }
                    return try result.get()
                }
            }
            let rows = [query.status == .recent ? recent : fresh]
            return CompetitionPageResult(competitions: rows, receivedCount: 1, nextPage: nil, totalCount: 1)
        }
        defer {
            gate?.resume(returning: nil)
            pageGate?.resume(returning: .failure(CancellationError()))
            CompetitionBrowserPublicationAcceptance.cache = nil
            CompetitionBrowserPublicationAcceptance.page = nil
            CompetitionBrowserPublicationAcceptance.displayed = nil
            CompetitionBrowserPublicationAcceptance.published = nil
            CompetitionBrowserPublicationAcceptance.scope = nil
            for key in keys {
                if let value = previous[key] ?? nil { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set("en-XCTest-\(UUID().uuidString)", forKey: "appLanguage")
        defaults.set("present", forKey: "competition_filter_status")
        defaults.set(CompetitionRegionFilter.all.id, forKey: "competition_filter_region")
        defaults.set(CompetitionYearFilter.all.id, forKey: "competition_filter_year")
        defaults.set(CompetitionEventFilter.threeByThree.rawValue, forKey: "competition_filter_events")
        defaults.set(false, forKey: "competition_show_top_cubers")
        try await render(CompatibleNavigationContainer {
            BrowserPublicationFixture(activity: activity, onSnapshot: { snapshots.append($0) })
        }, width: 390, dark: false, name: "actual-query-publication") { _ in
            for _ in 0..<100 where gate == nil && pageGate == nil { try await Task.sleep(nanoseconds: 20_000_000) }
            XCTAssertTrue(gate != nil || pageGate != nil, "The actual Browser must suspend its first response")
            if reactivates {
                activity.active = false
                for _ in 0..<100 where snapshots.last?.isActive != false { try await Task.sleep(nanoseconds: 20_000_000) }
                XCTAssertEqual(snapshots.last?.isActive, false)
                activity.active = true
            } else {
                defaults.set("recent", forKey: "competition_filter_status")
                for _ in 0..<100 where displayedIDs != [recent.id] {
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
                XCTAssertEqual(displayedIDs, [recent.id], "Observe the actual native diffable display, not a coalesced preference")
                defaults.set("present", forKey: "competition_filter_status")
            }
            for _ in 0..<100 where displayedIDs != [fresh.id] {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertEqual(displayedIDs, [fresh.id])
            let beforeRelease = snapshots.count
            let publishedBeforeRelease = publications.count
            let displayedBeforeRelease = displayedHistory.count
            gate?.resume(returning: CompetitionCacheSnapshot(competitions: [old], totalCount: 1, lastUpdated: Date()))
            gate = nil
            pageGate?.resume(returning: fails ? .failure(URLError(.badServerResponse))
                : .success(CompetitionPageResult(competitions: [old], receivedCount: 1, nextPage: nil, totalCount: 1)))
            pageGate = nil
            try await Task.sleep(nanoseconds: 400_000_000)
            // Preferences can be coalesced/dropped across UIKit-hosted updates.
            // Observe these same invariants at the actual production commit,
            // independently from the native diffable display assertions below.
            XCTAssertEqual(publications.last?.ids, [fresh.id])
            XCTAssertEqual(publications.last?.sourceIDs, [fresh.id])
            XCTAssertEqual(publications.last?.preparedIDs, [fresh.id])
            XCTAssertEqual(displayedIDs, [fresh.id])
            XCTAssertFalse(displayedHistory.dropFirst(displayedBeforeRelease).contains { $0.contains(old.id) })
            XCTAssertFalse(snapshots.dropFirst(beforeRelease).contains { $0.ids.contains(old.id) })
            XCTAssertFalse(snapshots.dropFirst(beforeRelease).contains { $0.sourceIDs.contains(old.id) })
            XCTAssertFalse(publications.dropFirst(publishedBeforeRelease).contains {
                $0.ids.contains(old.id) || $0.sourceIDs.contains(old.id) || $0.preparedIDs.contains(old.id)
            })
            XCTAssertFalse(publications.last?.phase.hasPrefix("failed") ?? true)
            print("[ActualPublicationABA] ignoredForeignDisplays=\(CompetitionBrowserPublicationAcceptance.ignoredForeignDisplays) \(snapshots)")
        }
    }
    func testCachedTopCubersPublishesBeforeAnyNetworkRequest() async {
        let values = [CompetitionTopCuberPreview(id: "person", name: "Cached person", badges: [])]
        let model = CompetitionTopCubersLoader()
        var fetched = false
        await model.load(cache: { values }, fetch: { fetched = true; return [] }, identity: "fixture")
        XCTAssertEqual(model.state, .loaded(values)); XCTAssertFalse(fetched)
        let warm = CompetitionTopCubersLoader(initial: .loaded(values))
        await warm.load(cache: { XCTFail("Warm state must render without waiting for cache lookup"); return nil },
            fetch: { XCTFail("Warm state must not refetch"); return nil }, identity: "fixture")
        XCTAssertEqual(warm.state, .loaded(values))
    }
    func testColdTopCubersStartsFetchWithoutUnrelatedLoadingGate() async {
        let model = CompetitionTopCubersLoader()
        var started = false
        await model.load(cache: { nil }, fetch: {
            started = true; XCTAssertEqual(model.state, .loading)
            return [CompetitionTopCuberPreview(id: "person", name: "Network person", badges: [])]
        }, identity: "fixture")
        XCTAssertTrue(started)
        if case .loaded = model.state {} else { XCTFail("Result must be published directly to hosted row") }
    }
    func testTopCubersFetchContinuesDuringGestureButGeometryPublishesAtIdle() async {
        let interaction = CompetitionListInteraction()
        interaction.setActive(true)
        let values = [CompetitionTopCuberPreview(id: "person", name: "Network person", badges: [])]
        let model = CompetitionTopCubersLoader()
        var requests = 0
        await model.load(cache: { nil }, fetch: { requests += 1; return values },
            identity: "fixture", interaction: interaction)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(model.state, .loading, "Network completion must not resize a cell during a gesture")
        await model.load(cache: { XCTFail("Pending content must not refetch"); return nil },
            fetch: { XCTFail("Pending content must not refetch"); return [] }, identity: "fixture", interaction: interaction)
        interaction.setActive(false)
        model.publishPending()
        XCTAssertEqual(model.state, .loaded(values))
        model.publishPending()
        XCTAssertEqual(model.state, .loaded(values))
    }
    func testDirectAllResultsEntryUsesNoSpecificRoundAndCancelsOnDismiss() async throws {
        let snapshot = try JSONDecoder().decode(CubingChinaLiveSnapshot.self, from: CubingChinaModernLiveFixtures.beijing)
        let content = try XCTUnwrap(CubingChinaLivePresentation.competitor([snapshot.results[0]], rounds: [snapshot.round], language: "en"))
        let card = CompetitionResultCardState()
        card.presentCompetition(id: content.id, name: content.name, content: content)
        XCTAssertEqual(card.selection?.entry, .competition)
        XCTAssertEqual(card.selection?.round.eventID, "")
        XCTAssertEqual(card.selectedCompetitorContent, content)
        card.close(); XCTAssertNil(card.selection); XCTAssertNil(card.selectedCompetitorContent)
        card.presentCompetition(id: content.id, name: content.name) {
            try? await Task.sleep(nanoseconds: 100_000_000); return content
        }
        card.close(); try await Task.sleep(nanoseconds: 130_000_000)
        XCTAssertNil(card.selection); XCTAssertNil(card.selectedCompetitorContent)
        card.present(result: CubingChinaLivePresentation.preview(snapshot.results[0], language: "en"),
            round: CubingChinaLivePresentation.round(snapshot, rounds: [snapshot.round], language: "en"), loader: nil)
        XCTAssertEqual(card.selection?.entry, .round)
        card.close()
    }
    func testSumRankLeadingColumnsFitCompactContentWidth() {
        for width in [CGFloat(288), 343, 398, 736] {
            let columns = CompetitionSumRankColumns(width: width, scale: 1)
            XCTAssertLessThanOrEqual(columns.leadingWidth, width + 0.01)
            XCTAssertGreaterThanOrEqual(columns.region, 104)
            XCTAssertGreaterThanOrEqual(columns.name, 84)
            XCTAssertGreaterThanOrEqual(columns.position, 36)
            XCTAssertTrue(columns.countOrigin >= width - 0.01 || columns.countOrigin + columns.count <= width + 0.01,
                "Count must be completely hidden or completely visible, never a clipped fragment")
            if width <= 398 { XCTAssertEqual(columns.countOrigin, width, accuracy: 0.01) }
        }
    }
    func testAllResultsUsesOneGeometryIncludingMissingAverageAndLongScores() {
        let columns = CompetitionAllResultsColumns(roundNames: ["Final", "Combined First Round"],
            averageTexts: ["DNF", "8.04"], bestTexts: ["6.52", "27/30 54:10", "DNF"], hasAverage: true)
        XCTAssertEqual(columns.statistics, [.average, .best])
        XCTAssertGreaterThan(columns.round, 44)
        XCTAssertGreaterThan(columns.widths[.best] ?? 0, 62)
        XCTAssertGreaterThan(columns.minimumWidth, 320)
        // Every section consumes the same plan even when a row has no average.
        let expected = 46 + 8 + columns.round + columns.statistics.reduce(CGFloat(0)) {
            $0 + columns.widths[$1]! + columns.reserves[$1]! + CompetitionAllResultsLayout.leading
        }
        XCTAssertEqual(columns.minimumWidth, expected)
        let bestOnly = CompetitionAllResultsColumns(roundNames: ["Final"], averageTexts: [], bestTexts: ["DNF"], hasAverage: false)
        XCTAssertEqual(bestOnly.statistics, [.best])
    }
    func testAllResultsFormatsDNFAndPenaltyInclusiveTotalsAndMeanMoves() {
        func result(event: String, best: Int, average: Int) -> CompetitionWCALiveCompetitorResult {
            .init(id: "value", ranking: 1, isAdvancing: nil, isAdvancingQuestionable: nil,
                attempts: [best, -1], best: best, average: average, singleRecordTag: nil, averageRecordTag: nil,
                roundID: "final", roundName: "Final", roundNumber: 1, eventID: event, eventName: event,
                eventRank: nil, formatID: "m", numberOfAttempts: 3, sortBy: "average")
        }
        // Provider scores already include a +2; presentation must not add it again.
        let time = result(event: "333", best: 652 + 200, average: -1)
        XCTAssertEqual(CompetitionAllResultsDisplay.value(.best, result: time), "8.52")
        XCTAssertEqual(CompetitionAllResultsDisplay.value(.average, result: time), "DNF")
        XCTAssertEqual(CompetitionAllResultsDisplay.value(.average, result: result(event: "333", best: 652, average: 0)), "")
        let moves = result(event: "333fm", best: 25, average: 2533)
        XCTAssertEqual(CompetitionAllResultsDisplay.value(.best, result: moves), "25")
        XCTAssertEqual(CompetitionAllResultsDisplay.value(.average, result: moves), "25.33")
        XCTAssertEqual(CompetitionAllResultsDisplay.value(.average, result: result(event: "333fm", best: 9, average: 999)), "9.99")
    }
    func testOverflowTableProductionCardPreservesViewportCornerMask() async throws {
        let value = CompetitionWCALiveCompetitorResult(id: "wide-score", ranking: 1,
            isAdvancing: nil, isAdvancingQuestionable: nil, attempts: [970_354_050], best: 970_354_050, average: 0,
            singleRecordTag: "WR", averageRecordTag: nil, roundID: "wide-final",
            roundName: "Combined Preliminary Qualification Round", roundNumber: 1, eventID: "333mbf",
            eventName: "3x3x3 Multi-Blind", eventRank: nil, formatID: "1", numberOfAttempts: 1, sortBy: "best")
        let content = CompetitionWCALiveCompetitorContent(id: "wide-person", name: "Overflow fixture",
            wcaID: nil, countryISO2: "US", results: [value])
        let card = CompetitionResultCardState()
        card.presentCompetition(id: content.id, name: content.name, content: content)
        try await render(CompetitionResultExperience(round: card.selection!.round,
            languageCode: "en", cardState: card, mode: .card), width: 390, dark: false,
            name: "overflow-viewport-corners") { window in
                let scroll = try XCTUnwrap(self.views(window).compactMap { $0 as? UIScrollView }
                    .first { $0.contentSize.width > $0.bounds.width + 20 })
                XCTAssertEqual(scroll.bounds.width, 314, accuracy: 1, "390pt scene minus 32pt card margins and two 22pt table insets")
                for trailing in [false, true] {
                    if trailing { scroll.setContentOffset(CGPoint(x: scroll.contentSize.width - scroll.bounds.width, y: 0), animated: false) }
                    window.layoutIfNeeded()
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "overflow-viewport-corners-\(trailing)"
                    attachment.lifetime = .keepAlways
                    self.add(attachment)
                }
            }
        card.close()
    }
    func testPublishedWangFourRoundSeparatorCapture() async throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/competition-physical-regressions/beijing-results.json")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Requires captured complete public results") }
        let rows = try PublishedCompetitionService.decodeResults(Data(contentsOf: file), competitionID: "BeijingAutumnRivalry2026")
        let data = PublishedCompetitionData(competitionID: "BeijingAutumnRivalry2026", results: rows)
        let complete = try XCTUnwrap(PublishedCompetitionPresentation.competitor("2019WANY36", data: data, language: "en"))
        let rounds = complete.results.filter { $0.eventID == "333" }
        XCTAssertEqual(rounds.count, 4)
        XCTAssertEqual(Set(rounds.map(\.id)).count, 4)
        for count in [2, 3, 4] {
        let selectedRounds = Array(rounds.prefix(count))
        let content = CompetitionWCALiveCompetitorContent(id: complete.id, name: complete.name,
            wcaID: complete.wcaID, countryISO2: complete.countryISO2, results: selectedRounds)
        for dark in [false, true] {
          for phase in [CGFloat(0), CGFloat(1) / 6, CGFloat(1) / 3] {
            CompetitionResultSeparatorDiagnostics.rows = [:]
            let card = CompetitionResultCardState()
            card.presentCompetition(id: content.id, name: content.name, content: content)
            try await render(CompetitionResultExperience(round: card.selection!.round,
                languageCode: "en", cardState: card, mode: .card).offset(y: phase), width: 390, dark: dark,
                name: "wang-round-surface-\(count)-\(dark)-\(phase)") { window in
                    let pixel = 1 / window.traitCollection.displayScale
                    var boundaries: [String: CGRect] = [:]
                    for index in 1..<selectedRounds.count {
                        let previous = try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows[selectedRounds[index - 1].id])
                        let current = try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows[selectedRounds[index].id])
                        let frame = CGRect(x: current.minX, y: previous.maxY,
                            width: current.width, height: current.minY - previous.maxY)
                        boundaries[selectedRounds[index].id] = frame
                        XCTAssertGreaterThanOrEqual(frame.height, pixel - 0.001, "Every intended boundary must retain a pixel-sized gap")
                    }
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    let cg = try XCTUnwrap(image.cgImage)
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
                    for result in selectedRounds.dropFirst() {
                        let frame = try XCTUnwrap(boundaries[result.id])
                        let x = Int(frame.midX * image.scale), y = Int(frame.midY * image.scale)
                        XCTAssertTrue(x >= 0 && x < cg.width && y > 6 && y < cg.height - 6)
                        guard x >= 0, x < cg.width, y > 6, y < cg.height - 6 else { continue }
                        let background = (luminance(x, y - 6) + luminance(x, y + 6)) / 2
                        let contrast = (y - 2...y + 2).map { abs(luminance(x, $0) - background) }.max() ?? 0
                        print("[PaintedSeparator] rows=\(count) phase=\(phase) dark=\(dark) id=\(result.id) frame=\(frame) pixelY=\(frame.midY * image.scale) contrast=\(contrast)")
                        XCTAssertGreaterThan(contrast, 1, "A layout frame alone is insufficient: every boundary must paint a visible pixel")
                    }
                    let attachment = XCTAttachment(image: image); attachment.name = "wang-round-separators-\(count)-\(dark)-\(phase)"
                    attachment.lifetime = .keepAlways; self.add(attachment)
                }
            card.close()
          }
        }
        }
    }
    func testAllResultsUsesExistingCornerBadgesForSingleAndAverageWithoutChangingRows() async throws {
        let tags = ["WR", "CR", "NR", "PR"]
        let colors: [[Double]] = [[244, 67, 54], [255, 235, 59], [0, 230, 118], [238, 238, 238]]
        let values = tags.enumerated().map { index, tag in
            CompetitionWCALiveCompetitorResult(id: "badge-\(index)", ranking: index + 1,
                isAdvancing: index < 3, isAdvancingQuestionable: false, attempts: [852, 900, 1000, 1100, 1200],
                best: 852, average: 1000, singleRecordTag: tag, averageRecordTag: tags[3 - index],
                roundID: String(index), roundName: "Round \(index + 1)", roundNumber: index + 1,
                eventID: "333", eventName: "3x3x3 Cube", eventRank: 0, formatID: "a", numberOfAttempts: 5, sortBy: "average")
        }
        let content = CompetitionWCALiveCompetitorContent(id: "badge-person", name: "Explicit record metadata",
            wcaID: nil, countryISO2: nil, results: values)
        CompetitionResultSeparatorDiagnostics.rows = [:]
        let card = CompetitionResultCardState()
        card.presentCompetition(id: content.id, name: content.name, content: content)
        defer { card.close() }
        try await render(CompetitionResultExperience(round: card.selection!.round,
            languageCode: "en", cardState: card, mode: .card), width: 390, dark: false, name: "all-results-record-corners") { window in
            let bitmap = try self.finalUIBitmap(window)
            for (index, result) in values.enumerated() {
                let frame = try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows[result.id])
                XCTAssertEqual(frame.height, 36, accuracy: 0.001)
                for average in [false, true] {
                    // Existing shared badge offset (23,-6) and column reserves.
                    // Verify pixels at the expected corner, not just a tag in a model.
                    let trailing = frame.maxX - (average ? 74 : 2)
                    let region = CGRect(x: trailing - 23, y: frame.minY, width: 21, height: 19)
                    let color = colors[average ? 3 - index : index]
                    var matches = 0
                    for y in Int(region.minY * bitmap.scale)..<Int(region.maxY * bitmap.scale) {
                        for x in Int(region.minX * bitmap.scale)..<Int(region.maxX * bitmap.scale) {
                            let pixel = bitmap.rgb(x, y)
                            if zip(pixel, color).allSatisfy({ abs($0 - $1) < 1.1 }) { matches += 1 }
                        }
                    }
                    XCTAssertGreaterThan(matches, 10, "\(average ? result.averageRecordTag! : result.singleRecordTag!) missing from its corresponding value corner")
                }
            }
        }
    }
    func testPhysicalOHSeparatorsHaveConsistentPixelAppearance() async throws {
        try await verifyPhysicalOHSeparators(horizontal: false)
    }
    func testInternalRoundSeparatorProfilesAtFractionalOrigins() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let bytes = try Data(contentsOf: root.appendingPathComponent("build/competition-physical-regressions/beijing-results.json"))
        let data = PublishedCompetitionData(competitionID: "BeijingAutumnRivalry2026",
            results: try PublishedCompetitionService.decodeResults(bytes, competitionID: "BeijingAutumnRivalry2026"))
        let person = try XCTUnwrap(PublishedCompetitionPresentation.competitor("2019WANY36", data: data, language: "en"))
        let rounds = person.results.filter { $0.eventID == "333" }
        XCTAssertEqual(rounds.count, 4)
        let content = CompetitionWCALiveCompetitorContent(id: person.id, name: person.name,
            wcaID: person.wcaID, countryISO2: person.countryISO2, results: rounds)
        for dark in [false, true] {
            for step in 0..<8 {
                let phase = CGFloat(step) / 12
                let card = CompetitionResultCardState()
                card.presentCompetition(id: content.id, name: content.name, content: content)
                CompetitionResultSeparatorDiagnostics.rows = [:]
                try await render(CompetitionResultExperience(round: card.selection!.round,
                    languageCode: "en", cardState: card, mode: .card).offset(y: phase),
                    width: 390, dark: dark, name: "internal-rule-profile-\(dark)-\(step)") { window in
                    let bitmap = try self.finalUIBitmap(window)
                    let frames = try rounds.map { try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows[$0.id]) }
                    var peaks: [Double] = [], areas: [Double] = []
                    for index in 1..<frames.count {
                        let previous = frames[index - 1], current = frames[index]
                        let center = (previous.maxY + current.minY) / 2 * bitmap.scale
                        let x = Int(current.midX * bitmap.scale), y = Int(center)
                        let base = (bitmap.tone(x, y - 6) + bitmap.tone(x, y + 6)) / 2
                        let profile = (-3...3).map { abs(bitmap.tone(x, y + $0) - base) }
                        peaks.append(profile.max() ?? 0); areas.append(profile.reduce(0, +))
                        print("[InternalRuleProfile] dark=\(dark) phase=\(phase) round=\(index) pixelY=\(center) gap=\(current.minY - previous.maxY) profile=\(profile)")
                    }
                    XCTAssertLessThanOrEqual((peaks.max() ?? 0) - (peaks.min() ?? 0), 1,
                        "Internal round lines must have the same peak shade")
                    XCTAssertLessThanOrEqual((areas.max() ?? 0) - (areas.min() ?? 0), 1,
                        "Equal darkest pixels alone must not hide unequal painted coverage")
                    let first = try XCTUnwrap(frames.first)
                    let x = Int(first.midX * bitmap.scale)
                    let y = Int(first.minY * bitmap.scale - 0.5)
                    let base = (bitmap.tone(x, y - 6) + bitmap.tone(x, y + 6)) / 2
                    let header = (-3...3).map { abs(bitmap.tone(x, y + $0) - base) }
                    print("[AdjacentHeaderProfile] dark=\(dark) phase=\(phase) profile=\(header)")
                    XCTAssertEqual(header.max() ?? 0, peaks.first ?? 0, accuracy: 1)
                    XCTAssertEqual(header.reduce(0, +), areas.first ?? 0, accuracy: 1)
                }
                card.close()
            }
        }
    }
    func testPhysicalOHSeparatorsRemainConsistentAfterHorizontalScroll() async throws {
        try await verifyPhysicalOHSeparators(horizontal: true)
    }
    private func verifyPhysicalOHSeparators(horizontal: Bool) async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let rows = try PublishedCompetitionService.decodeResults(Data(contentsOf: root.appendingPathComponent(
            "build/competition-physical-regressions/beijing-results.json")), competitionID: "BeijingAutumnRivalry2026")
        let data = PublishedCompetitionData(competitionID: "BeijingAutumnRivalry2026", results: rows)
        for id in ["2016KOLA02", "2019WANY36"] {
            let complete = try XCTUnwrap(PublishedCompetitionPresentation.competitor(id, data: data, language: "en"))
            // Current official WCA data has Wang's two OH rounds but no Tymon
            // OH entries. His verified four 3x3 rounds exercise the same renderer.
            let event = id == "2019WANY36" ? "333oh" : "333"
            let rounds = complete.results.filter { $0.eventID == event }
            XCTAssertGreaterThanOrEqual(rounds.count, 2)
            for count in Set([2, rounds.count]).sorted() { for dark in [false, true] {
                let selected = Array(rounds.prefix(count))
                let content = CompetitionWCALiveCompetitorContent(id: complete.id, name: complete.name,
                    wcaID: complete.wcaID, countryISO2: complete.countryISO2, results: selected)
                let card = CompetitionResultCardState()
                card.presentCompetition(id: id, name: content.name, content: content)
                CompetitionResultSeparatorDiagnostics.rows = [:]
                try await render(CompetitionResultExperience(round: card.selection!.round, languageCode: "en", cardState: card,
                    mode: .card), width: horizontal ? 320 : 390, dark: dark, name: "oh-consistency-\(id)-\(count)-\(dark)-\(horizontal)") { window in
                    if horizontal {
                        let scroll = try XCTUnwrap(self.views(window).compactMap { $0 as? UIScrollView }.first {
                            $0.contentSize.width > $0.bounds.width + 1
                        })
                        let maximum = scroll.contentSize.width - scroll.bounds.width
                        scroll.setContentOffset(CGPoint(x: maximum, y: scroll.contentOffset.y), animated: false)
                        scroll.layoutIfNeeded()
                        try await Task.sleep(nanoseconds: 30_000_000)
                        XCTAssertEqual(scroll.contentOffset.x, maximum, accuracy: 1)
                    }
                    let bitmap = try self.finalUIBitmap(window)
                    let frames = try selected.map { try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows[$0.id]) }
                    let pixel = 1 / bitmap.scale
                    var intensities: [Double] = []
                    for index in frames.indices {
                        let frame = frames[index]
                        let y = index == 0 ? frame.minY - pixel / 2 : (frames[index - 1].maxY + frame.minY) / 2
                        let xPixel = Int(frame.midX * bitmap.scale), yPixel = Int(y * bitmap.scale)
                        let base = (bitmap.tone(xPixel, yPixel - 6) + bitmap.tone(xPixel, yPixel + 6)) / 2
                        let intensity = (yPixel - 2...yPixel + 2).map { abs(bitmap.tone(xPixel, $0) - base) }.max() ?? 0
                        XCTAssertGreaterThan(intensity, 1, "Every header/round boundary must remain visible")
                        intensities.append(intensity)
                    }
                    print("[OHBoundaryPixels] id=\(id) rows=\(count) dark=\(dark) intensities=\(intensities)")
                    XCTAssertLessThanOrEqual((intensities.max() ?? 0) - (intensities.min() ?? 0), 1,
                        "One adaptive treatment must not alternate between strong native and faint drawn rules")
                }
                card.close()
            } }
        }
    }
    func testChampionsPositionFillsLastInteriorPixel() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for (id, file) in [("MariettaMondayMiniIV2026", "marietta-results.json"), ("MNQuietChampionship2026", "minnesota-results.json"),
                           ("BeijingAutumnRivalry2026", "../competition-final-ui-oct14/beijing-current-results.json")] {
            let rows = try PublishedCompetitionService.decodeResults(Data(contentsOf: root.appendingPathComponent(
                "build/competition-reliability-oct14/\(file)")), competitionID: id)
            let data = PublishedCompetitionData(competitionID: id, results: rows)
            let champion = try XCTUnwrap(data.finals.first?.champions.first)
            for dark in [false, true] {
                CompetitionResultSeparatorDiagnostics.rows = [:]
                let content = PublishedCompetitionResultsContent(data: data, language: "en", renderingChampions: true).padding(16)
                try await render(ScrollView { content }, width: 390, dark: dark, name: "champion-fill-\(id)-\(dark)") { window in
                    let frame = try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows["list-published-\(champion.id)"])
                    let button = try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows["button-published-\(champion.id)"])
                    let table = try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows["table-published-\(champion.roundKey)"])
                    print("[ChampionBounds] row=\(frame) button=\(button) table=\(table)")
                    XCTAssertEqual(frame.maxY, button.maxY, accuracy: 0.001)
                    XCTAssertEqual(frame.maxY, table.maxY, accuracy: 0.001)
                    XCTAssertEqual(frame.height, 34, accuracy: 0.001)
                    let bitmap = try self.finalUIBitmap(window)
                    XCTAssertGreaterThanOrEqual(frame.minY, 0)
                    XCTAssertLessThan(frame.maxY * bitmap.scale, CGFloat(bitmap.height))
                    let x = Int((frame.minX + 12) * bitmap.scale)
                    let middle = bitmap.rgb(x, Int(frame.midY * bitmap.scale))
                    let endPixel = Int(floor(frame.maxY * bitmap.scale + 0.0001))
                    let bottom = bitmap.rgb(x, endPixel - 1)
                    XCTAssertEqual(middle[1], 230, accuracy: 1, "Sample the actual champion green, not an offscreen/background pixel")
                    print("[ChampionFill] id=\(id) dark=\(dark) frame=\(frame) edge=\(frame.maxY * bitmap.scale) middle=\(middle) bottom=\(bottom) edgePixels=\((endPixel - 3...endPixel + 1).map { bitmap.rgb(x, $0) })")
                    for channel in 0..<3 { XCTAssertEqual(bottom[channel], middle[channel], accuracy: 1) }
                }
            }
        }
    }
    private struct FinalUIBitmap {
        let bytes: [UInt8]
        let width: Int
        let height: Int
        let scale: CGFloat
        func rgb(_ x: Int, _ y: Int) -> [Double] {
            guard x >= 0, x < width, y >= 0, y < height else { return [-1, -1, -1] }
            let offset = (y * width + x) * 4
            return (0..<3).map { Double(bytes[offset + $0]) }
        }
        func tone(_ x: Int, _ y: Int) -> Double { rgb(x, y).reduce(0, +) / 3 }
    }
    func testInternalResultsNavigationKeepsNativeModalAndDimmer() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let rows = try PublishedCompetitionService.decodeResults(Data(contentsOf: root.appendingPathComponent(
            "build/competition-reliability-oct14/marietta-results.json")), competitionID: "MariettaMondayMiniIV2026")
        let data = PublishedCompetitionData(competitionID: "MariettaMondayMiniIV2026", results: rows)
        let round = PublishedCompetitionPresentation.round(try XCTUnwrap(data.rounds.first), language: "en", data: data)
        let result = try XCTUnwrap(round.results.first)
        let content = try XCTUnwrap(PublishedCompetitionPresentation.competitor(try XCTUnwrap(result.personWCAID), data: data, language: "en"))
        do {
            let state = CompetitionResultCardState()
            let surface = CompetitionResultExperience(round: round, languageCode: "en", cardState: state,
                isPublished: true).competitionResultsPresentation(state: state, language: "en", round: round)
            try await render(surface, width: 390, dark: false, name: "native-internal-navigation") { window in
                let host = try XCTUnwrap(window.rootViewController)
                state.present(result: result, round: round, isPublished: true, loader: { _ in content })
                for _ in 0..<200 where host.presentedViewController == nil || host.presentedViewController?.isBeingPresented == true {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                let modal = try XCTUnwrap(host.presentedViewController)
                let selection = state.selection?.result.id
                state.loadAllResults()
                var forwardFrames: Set<Int> = []
                for _ in 0..<20 {
                    forwardFrames.insert(self.renderedFingerprint(window))
                    try await Task.sleep(nanoseconds: 16_000_000)
                }
                XCTAssertGreaterThan(forwardFrames.count, 3, "Forward transition must render intermediate frames, not merely declare an animation")
                for _ in 0..<200 where state.selectedCompetitorContent == nil || state.allResultsHeight == 0 {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                XCTAssertNotNil(state.selectedCompetitorContent)
                XCTAssertGreaterThan(state.allResultsHeight, 0)
                XCTAssertTrue(host.presentedViewController === modal)
                XCTAssertEqual(state.selection?.result.id, selection)
                XCTAssertFalse(modal.isBeingPresented || modal.isBeingDismissed)
                XCTAssertEqual(modal.view.alpha, 1)
                XCTAssertTrue(CATransform3DIsIdentity(modal.view.layer.transform))
                withAnimation(.easeOut(duration: 0.16)) {
                    state.selectedCompetitorContent = nil
                    state.allResultsHeight = 0
                }
                var backwardFrames: Set<Int> = []
                for _ in 0..<20 {
                    backwardFrames.insert(self.renderedFingerprint(window))
                    try await Task.sleep(nanoseconds: 16_000_000)
                }
                XCTAssertGreaterThan(backwardFrames.count, 3, "Back transition must render intermediate frames")
                try await Task.sleep(nanoseconds: 200_000_000)
                XCTAssertTrue(host.presentedViewController === modal)
                XCTAssertEqual(state.selection?.result.id, selection)
                XCTAssertGreaterThan(state.resultSummaryHeight, 0)
                XCTAssertEqual(modal.view.alpha, 1)
                XCTAssertTrue(CATransform3DIsIdentity(modal.view.layer.transform))
                state.close()
                for _ in 0..<200 where host.presentedViewController != nil {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                XCTAssertNil(host.presentedViewController)
            }
        }
    }
    private func renderedFingerprint(_ window: UIWindow) -> Int {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        return image.pngData()?.hashValue ?? 0
    }
    func testRoundOriginKeepsSummaryWhileAllResultsLoads() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let rows = try PublishedCompetitionService.decodeResults(Data(contentsOf: root.appendingPathComponent(
            "build/competition-reliability-oct14/marietta-results.json")), competitionID: "MariettaMondayMiniIV2026")
        let data = PublishedCompetitionData(competitionID: "MariettaMondayMiniIV2026", results: rows)
        let round = PublishedCompetitionPresentation.round(try XCTUnwrap(data.rounds.first), language: "en", data: data)
        let result = try XCTUnwrap(round.results.first)
        let content = try XCTUnwrap(PublishedCompetitionPresentation.competitor(try XCTUnwrap(result.personWCAID), data: data, language: "en"))
        var gate: CheckedContinuation<CompetitionWCALiveCompetitorContent?, Never>?
        let state = CompetitionResultCardState()
        state.present(result: result, round: round, isPublished: true, loader: { _ in await withCheckedContinuation { gate = $0 } })
        defer { gate?.resume(returning: nil); state.close() }
        func span(_ bitmap: FinalUIBitmap) -> ClosedRange<Int>? {
            let ys = (0..<bitmap.height).filter { bitmap.tone(Int(20 * bitmap.scale), $0) > 200 }
            guard let first = ys.first, let last = ys.last else { return nil }; return first...last
        }
        try await render(CompetitionResultExperience(round: round, languageCode: "en", cardState: state, mode: .card,
            isPublished: true), width: 390, dark: false, name: "round-loading-before") { window in
            let before = try XCTUnwrap(span(try self.finalUIBitmap(window)))
            XCTAssertGreaterThan(before.count, 100)
            state.loadAllResults()
            for _ in 0..<100 where gate == nil { try await Task.sleep(nanoseconds: 10_000_000) }
            XCTAssertNotNil(gate)
            try await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertTrue(state.isLoadingCompetitorContent)
            window.rootViewController?.view.setNeedsLayout()
            window.rootViewController?.view.layoutIfNeeded()
            let loadingImage = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try loadingImage.pngData()?.write(to: URL(fileURLWithPath: "/tmp/cubeflow-navigation-loading/screenshots/round-loading-pending.png"))
            let loading = try XCTUnwrap(span(try self.finalUIBitmap(window)))
            print("[RoundLoadingGeometry] before=\(before) loading=\(loading)")
            XCTAssertEqual(before.lowerBound, loading.lowerBound, accuracy: 1)
            XCTAssertEqual(before.upperBound, loading.upperBound, accuracy: 1)
            gate?.resume(returning: content); gate = nil
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertEqual(state.selectedCompetitorContent, content)
            XCTAssertEqual(state.selection?.result.id, result.id)
        }
    }
    private func finalUIBitmap(_ window: UIWindow) throws -> FinalUIBitmap {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        return FinalUIBitmap(bytes: bytes, width: cg.width, height: cg.height, scale: image.scale)
    }
    func testDirectCardAndCompactSumRanksMounted() async throws {
        let snapshot = try JSONDecoder().decode(CubingChinaLiveSnapshot.self, from: CubingChinaModernLiveFixtures.beijing)
        let original = try XCTUnwrap(CubingChinaLivePresentation.competitor([snapshot.results[0]], rounds: [snapshot.round], language: "en"))
        let bestOnly = CompetitionWCALiveCompetitorResult(id: "multi", ranking: 1, isAdvancing: nil,
            isAdvancingQuestionable: nil, attempts: [970_354_050], best: 970_354_050, average: 0,
            singleRecordTag: "WR", averageRecordTag: nil, roundID: "multi-final", roundName: "Final", roundNumber: 1,
            eventID: "333mbf", eventName: "3x3x3 Multi-Blind", eventRank: nil, formatID: "1", numberOfAttempts: 1, sortBy: "best")
        let content = CompetitionWCALiveCompetitorContent(id: original.id,
            name: "A Very Long Competitor Name That Must Not Overlap Dismiss", wcaID: original.wcaID,
            countryISO2: original.countryISO2, results: original.results + [bestOnly])
        let entries = try JSONDecoder().decode(CubingChinaLiveData<[CubingChinaLiveSumRank]>.self, from: CubingChinaUnifiedFixtures.sums).data
        for width in [CGFloat(320), 768] {
            for dark in [false, true] {
                let card = CompetitionResultCardState()
                card.presentCompetition(id: content.id, name: content.name, content: content)
                try await render(CompetitionResultExperience(round: card.selection!.round,
                    languageCode: "en", cardState: card, mode: .card),
                    width: width, dark: dark, name: "direct-card-\(Int(width))-\(dark)")
                card.close()
                try await render(ScrollView {
                    CubingChinaSumRankTable(entries: entries, language: "en", openCompetitor: { person in
                        card.presentCompetition(id: String(person.id.rawValue), name: person.name, content: content)
                    }).padding(16)
                }, width: width, dark: dark, name: "compact-sums-\(Int(width))-\(dark)")
            }
        }
    }
    func testRepeatedDisclosureContinuouslyInListAndGlass() async throws {
        try await exerciseRepeatedDisclosure(animation: .easeInOut(duration: 0.32))
    }
    func testTopOriginDisclosureKeepsGlyphAndNativeHeightStable() async throws {
        try await exerciseRepeatedDisclosure(animation: .easeInOut(duration: 0.32))
        try await testDisclosureVisibleGlyphMotion()
    }
    func testDisclosureNativeSizingWithoutSwiftUIAnimation() async throws {
        CompetitionDisclosureViewportProbe.shared.capturesGeometryWrites = true
        defer { CompetitionDisclosureViewportProbe.shared.capturesGeometryWrites = false }
        try await exerciseRepeatedDisclosure(animation: nil)
    }
    private func exerciseRepeatedDisclosure(animation: Animation?) async throws {
        for glass in [false, true] {
                let state = CompetitionDisclosureAcceptanceState()
                try await render(CompatibleNavigationContainer {
                    CompetitionDisclosureAcceptanceSurface(state: state, controlled: true, boundary: false, glass: glass)
                        .navigationTitle("Competitions").navigationBarTitleDisplayMode(.large)
                }, width: 320, dark: glass, name: "continuous-disclosure-\(glass)") { window in
                    let collection = try XCTUnwrap(self.views(window).compactMap { $0 as? UICollectionView }
                        .first { $0.accessibilityIdentifier == "competition-disclosure-list" })
                    let original = collection.contentOffset.y
                    let row = IndexPath(item: 1, section: 0)
                    let collapsedHeight = try XCTUnwrap(collection.cellForItem(at: row)).frame.height
                    for _ in 0..<3 {
                        CompetitionDisclosureViewportProbe.shared.begin()
                        withAnimation(animation) { state.expanded = true }
                        try await Task.sleep(nanoseconds: 700_000_000)
                        try await self.checkTrace(collection, clamping: false)
                        XCTAssertEqual(collection.contentOffset.y, original, accuracy: 1)
                        XCTAssertGreaterThan(try XCTUnwrap(collection.cellForItem(at: row)).frame.height, collapsedHeight + 1)
                        CompetitionDisclosureViewportProbe.shared.begin()
                        withAnimation(animation) { state.expanded = false }
                        try await Task.sleep(nanoseconds: 700_000_000)
                        try await self.checkTrace(collection, clamping: false)
                        XCTAssertEqual(try XCTUnwrap(collection.cellForItem(at: row)).frame.height, collapsedHeight, accuracy: 1)
                    }
                }
        }
    }
    func testDisclosureVisibleGlyphMotion() async throws {
        for glass in [false, true] {
            let state = CompetitionDisclosureAcceptanceState()
            try await render(CompatibleNavigationContainer {
                CompetitionDisclosureAcceptanceSurface(state: state, controlled: true, glass: glass)
                    .navigationTitle("Competitions")
            }, width: 390, dark: false, name: "disclosure-ink-baseline-\(glass)") { window in
                let collection = try XCTUnwrap(self.views(window).compactMap { $0 as? UICollectionView }
                    .first { $0.accessibilityIdentifier == "competition-disclosure-list" })
                let cell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 1, section: 0)))
                let rect = cell.convert(cell.bounds, to: window)
                let region = CGRect(x: rect.minX + 16, y: rect.minY + 8, width: 180, height: 130)
                func capture(_ label: String) throws -> CGFloat {
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    let directory = URL(fileURLWithPath: "/tmp/cubeflow-navigation-loading/screenshots")
                    try image.pngData()?.write(to: directory.appendingPathComponent("disclosure-ink-\(glass)-\(label).png"))
                    let cg = try XCTUnwrap(image.cgImage)
                    var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
                    try pixels.withUnsafeMutableBytes { buffer in
                        let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height,
                            bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                    }
                    let lowerX = max(0, Int(region.minX * image.scale))
                    let upperX = min(cg.width, Int(region.maxX * image.scale))
                    let lowerY = max(0, Int(region.minY * image.scale))
                    let upperY = min(cg.height, Int(region.maxY * image.scale))
                    for y in lowerY..<upperY {
                        var ink = 0
                        for x in lowerX..<upperX {
                            let i = (y * cg.width + x) * 4
                            if Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2]) < 192 { ink += 1 }
                        }
                        if ink >= 3 { return CGFloat(y) / image.scale }
                    }
                    return try XCTUnwrap(nil as CGFloat?, "No visible title ink in the measured region")
                }
                let baseline = try capture("baseline")
                try await Task.sleep(nanoseconds: 100_000_000)
                let startOffset = collection.contentOffset.y
                CompetitionDisclosureViewportProbe.shared.begin()
                withAnimation(.easeInOut(duration: 0.32)) { state.expanded = true }
                try await Task.sleep(nanoseconds: 160_000_000)
                let intermediate = try capture("midpoint")
                try await Task.sleep(nanoseconds: 1_000_000_000)
                let settled = try capture("settled")
                let positions = [baseline, intermediate, settled]
                let drift = positions.map { abs($0 - baseline) }.max() ?? 0
                print("[DisclosureInk] glass=\(glass) origins=\(positions) drift=\(drift) trace=\(collection.accessibilityValue ?? "missing")")
                XCTAssertEqual(collection.contentOffset.y, startOffset, accuracy: 1)
                XCTAssertLessThanOrEqual(drift, 1, "Actual visible title ink must remain stationary")
            }
        }
    }
    private func views(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(views) }
    private func checkTrace(_ collection: UICollectionView, clamping: Bool) async throws {
        for _ in 0..<100 where !(collection.accessibilityValue ?? "").hasPrefix("{") {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let text = try XCTUnwrap(collection.accessibilityValue)
        let trace = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        func number(_ key: String) throws -> Double { try XCTUnwrap(trace[key] as? Double) }
        let start = try number("start"), end = try number("end")
        let expected = min(max(start, try number("minimum")), try number("maximum"))
        XCTAssertEqual(end, expected, accuracy: 1)
        XCTAssertLessThanOrEqual(try number("unexpected"), 1, text)
        XCTAssertLessThanOrEqual(try number("presentationDrift"), 1, text)
        XCTAssertLessThanOrEqual(try number("cellOriginDrift"), 1, text)
        XCTAssertGreaterThan(try number("presentationSamples"), 0, "The test must observe actual presentation frames")
        let titleFrames = try XCTUnwrap(trace["titleLayoutSamples"] as? [[Double]])
        XCTAssertGreaterThan(titleFrames.count, 0, "Measure the actual title, not only the collection viewport")
        if let first = titleFrames.first, let last = titleFrames.last, abs(first[5] - last[5]) > 10 {
            let lower = min(first[5], last[5]), upper = max(first[5], last[5])
            XCTAssertTrue(titleFrames.contains { $0[5] > lower + 1 && $0[5] < upper - 1 },
                "The card height must interpolate, not jump while only rows fade")
        }
        XCTAssertLessThanOrEqual(try number("titleOriginDrift"), 1, text)
        XCTAssertLessThanOrEqual(try number("titleRelativeDrift"), 1, text)
        if !clamping { XCTAssertEqual(end, start, accuracy: 1) }
        let evidence = XCTAttachment(string: text); evidence.name = "continuous-disclosure-trace"; evidence.lifetime = .keepAlways; add(evidence)
    }
    private func render<V: View>(_ view: V, width: CGFloat, dark: Bool, name: String,
                                check: (UIWindow) async throws -> Void = { _ in }) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: width, height: 960)
        let host = UIHostingController(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        window.overrideUserInterfaceStyle = dark ? .dark : .light; window.windowLevel = .alert + 1
        window.rootViewController = host; window.makeKeyAndVisible()
        defer {
            host.beginAppearanceTransition(false, animated: false); host.endAppearanceTransition()
            window.isHidden = true; window.rootViewController = nil
        }
        try await Task.sleep(nanoseconds: 550_000_000); host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let directory = URL(fileURLWithPath: "/tmp/cubeflow-navigation-loading/screenshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try image.pngData()?.write(to: directory.appendingPathComponent(name + ".png"))
        XCTAssertGreaterThan(image.size.width, 0)
        try await check(window)
    }
    func testDisclosureViewportInActualHostingCollectionCells() async throws {
        for width in [CGFloat(320), 768] {
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(76))
            let item = NSCollectionLayoutItem(layoutSize: size)
            let section = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [item]))
            let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout(section: section))
            collection.register(CompetitionHostingCollectionViewCell.self, forCellWithReuseIdentifier: "row")
            let rows = HostingRows(); collection.dataSource = rows
            let controller = UIViewController(); controller.view = collection
            controller.navigationItem.title = "Competitions"; controller.navigationItem.largeTitleDisplayMode = .always
            controller.setContentScrollView(collection)
            let nav = UINavigationController(rootViewController: controller); nav.navigationBar.prefersLargeTitles = true
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: width, height: 850)
            window.windowLevel = .alert + 1; window.rootViewController = nav; window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            try await Task.sleep(nanoseconds: 500_000_000); collection.layoutIfNeeded()
            collection.setContentOffset(CGPoint(x: 0, y: 100), animated: false)
            try await Task.sleep(nanoseconds: 400_000_000)
            let origin = collection.contentOffset.y
            for _ in 0..<6 {
                for expanded in [true, false] {
                    withAnimation(.easeInOut(duration: 0.32)) { rows.probe.expanded = expanded }
                    try await Task.sleep(nanoseconds: 420_000_000)
                    XCTAssertEqual(collection.contentOffset.y, origin, accuracy: 1,
                        "Actual hosting-cell self-sizing must not move viewport: expanded=\(expanded), width=\(width)")
                }
            }
        }
    }
}

extension CompetitionNavigationLoadingTests {
    func testActualBrowserIndependentRefreshABAHasAnEpochGuardAndNegativeControl() async throws {
        for checksEpoch in [false, true] {
            let defaults = UserDefaults.standard
            CompetitionBrowserPublicationAcceptance.scope = UUID()
            let keys = ["appLanguage", "competition_filter_status", "competition_filter_region", "competition_filter_year", "competition_filter_events", "competition_show_top_cubers"]
            let previous = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
            var suspended: CheckedContinuation<CompetitionPageResult, Never>?
            var reads = 0
            var ids: [String] = []
            let now = Date()
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let day = CompetitionDateWindow(now: now)!
            func fixture(_ id: String, offset: Int) -> CompetitionSummary {
                let date = calendar.date(byAdding: .day, value: offset, to: day.today)!
                return CompetitionSummary(id: id, name: id, shortDisplayName: nil, startDate: date, endDate: date,
                    registrationOpen: nil, registrationClose: nil, competitorLimit: nil, venue: "", venueAddress: "", venueDetails: nil,
                    city: "Fixture", countryISO2: "US", latitude: nil, longitude: nil, url: "https://www.worldcubeassociation.org/competitions/\(id)",
                    website: nil, dateRange: "Fixture", eventIDs: ["333"], championshipTypes: nil,
                    localizedRegionLineOverride: nil, localizedAddressLineOverride: nil, localizedStatusOverride: nil,
                    localizedRegistrationStartOverride: nil, localizedWaitlistStartOverride: nil)
            }
            let initial = fixture("initial-A", offset: 2), fresh = fixture("new-A", offset: 2)
            let obsolete = fixture("obsolete-refresh-A", offset: 2), recent = fixture("recent-B", offset: -2)
            var returnsFresh = false
            CompetitionBrowserPublicationAcceptance.now = { now }
            CompetitionBrowserPublicationAcceptance.checksRequestEpoch = checksEpoch
            CompetitionBrowserPublicationAcceptance.displayed = { ids = $0 }
            CompetitionBrowserPublicationAcceptance.cache = { query in
                .init(competitions: [query.status == .recent ? recent : returnsFresh ? fresh : initial], totalCount: 1, lastUpdated: now)
            }
            CompetitionBrowserPublicationAcceptance.page = { _ , _ in
                reads += 1
                return await withCheckedContinuation { suspended = $0 }
            }
            defer {
                suspended?.resume(returning: .init(competitions: [], receivedCount: 0, nextPage: nil, totalCount: 0))
                CompetitionBrowserPublicationAcceptance.cache = nil; CompetitionBrowserPublicationAcceptance.page = nil
                CompetitionBrowserPublicationAcceptance.displayed = nil; CompetitionBrowserPublicationAcceptance.now = nil
                CompetitionBrowserPublicationAcceptance.checksRequestEpoch = true
                CompetitionBrowserPublicationAcceptance.scope = nil
                for key in keys { if let value = previous[key] ?? nil { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
            }
            defaults.set("en-epoch-\(UUID().uuidString)", forKey: "appLanguage")
            defaults.set("present", forKey: "competition_filter_status")
            defaults.set(CompetitionRegionFilter.all.id, forKey: "competition_filter_region")
            defaults.set(CompetitionYearFilter.all.id, forKey: "competition_filter_year")
            defaults.set(CompetitionEventFilter.threeByThree.rawValue, forKey: "competition_filter_events")
            defaults.set(false, forKey: "competition_show_top_cubers")
            try await render(CompatibleNavigationContainer { BrowserPublicationFixture(activity: BrowserActivityProbe(), onSnapshot: { _ in }) },
                width: 390, dark: false, name: "independent-refresh-epoch-\(checksEpoch)") { _ in
                for _ in 0..<150 where ids != [initial.id] { try await Task.sleep(nanoseconds: 10_000_000) }
                XCTAssertEqual(ids, [initial.id])
                // The load's defer releases ownership before the real refresh path starts.
                for _ in 0..<10 { await Task.yield() }
                CompetitionBrowserPublicationAcceptance.refreshRequests.send(())
                for _ in 0..<150 where suspended == nil { try await Task.sleep(nanoseconds: 10_000_000) }
                XCTAssertNotNil(suspended)
                defaults.set("recent", forKey: "competition_filter_status")
                for _ in 0..<150 where ids != [recent.id] { try await Task.sleep(nanoseconds: 10_000_000) }
                XCTAssertEqual(ids, [recent.id])
                returnsFresh = true; defaults.set("present", forKey: "competition_filter_status")
                for _ in 0..<150 where ids != [fresh.id] { try await Task.sleep(nanoseconds: 10_000_000) }
                XCTAssertEqual(ids, [fresh.id])
                suspended?.resume(returning: .init(competitions: [obsolete], receivedCount: 1, nextPage: nil, totalCount: 1)); suspended = nil
                for _ in 0..<80 {
                    if !checksEpoch, ids == [obsolete.id] { break }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                XCTAssertEqual(ids, checksEpoch ? [fresh.id] : [obsolete.id], "Negative control reproduces the independent old refresh; current epoch must reject it")
                XCTAssertEqual(reads, 1)
            }
        }
    }
}

extension CompetitionNavigationLoadingTests {
    func testMountedPresentWindowAdvancesOnSystemTimeChangeAndForegroundWithoutFilterToggle() async throws {
        let defaults = UserDefaults.standard
        CompetitionBrowserPublicationAcceptance.scope = UUID()
        let keys = ["appLanguage", "competition_filter_status", "competition_filter_region", "competition_filter_year", "competition_filter_events", "competition_show_top_cubers"]
        let previous = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        let iso = ISO8601DateFormatter()
        var now = iso.date(from: "2026-10-21T12:00:00Z")!
        var requested: [String] = [], displayed: [String] = []
        CompetitionBrowserPublicationAcceptance.now = { now }
        CompetitionBrowserPublicationAcceptance.displayed = { displayed = $0 }
        CompetitionBrowserPublicationAcceptance.cache = { query in
            let day = query.dateWindow!
            let name = day.isoDay(day.today)
            requested.append(name)
            let value = CompetitionSummary(id: name, name: name, shortDisplayName: nil, startDate: day.today, endDate: day.today,
                registrationOpen: nil, registrationClose: nil, competitorLimit: nil, venue: "", venueAddress: "", venueDetails: nil,
                city: "Fixture", countryISO2: "US", latitude: nil, longitude: nil,
                url: "https://www.worldcubeassociation.org/competitions/\(name)", website: nil, dateRange: name,
                eventIDs: ["333"], championshipTypes: nil, localizedRegionLineOverride: nil, localizedAddressLineOverride: nil,
                localizedStatusOverride: nil, localizedRegistrationStartOverride: nil, localizedWaitlistStartOverride: nil)
            return .init(competitions: [value], totalCount: 1, lastUpdated: Date())
        }
        CompetitionBrowserPublicationAcceptance.page = { _, _ in
            XCTFail("Complete current-day cache must not trigger an unnecessary network refresh")
            return .init(competitions: [], receivedCount: 0, nextPage: nil, totalCount: 0)
        }
        defer {
            CompetitionBrowserPublicationAcceptance.cache = nil; CompetitionBrowserPublicationAcceptance.page = nil
            CompetitionBrowserPublicationAcceptance.now = nil; CompetitionBrowserPublicationAcceptance.displayed = nil
            CompetitionBrowserPublicationAcceptance.scope = nil
            for key in keys { if let value = previous[key] ?? nil { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
        }
        defaults.set("en-day-window-\(UUID().uuidString)", forKey: "appLanguage")
        defaults.set("present", forKey: "competition_filter_status")
        defaults.set(CompetitionRegionFilter.all.id, forKey: "competition_filter_region")
        defaults.set(CompetitionYearFilter.all.id, forKey: "competition_filter_year")
        defaults.set(CompetitionEventFilter.threeByThree.rawValue, forKey: "competition_filter_events")
        defaults.set(false, forKey: "competition_show_top_cubers")
        try await render(CompatibleNavigationContainer {
            BrowserPublicationFixture(activity: BrowserActivityProbe(), onSnapshot: { _ in })
        }, width: 390, dark: false, name: "civil-day-refresh") { _ in
            XCTAssertEqual(displayed, ["2026-10-21"])
            for (next, notification) in [("2026-10-22", UIApplication.significantTimeChangeNotification),
                                          ("2026-10-23", UIApplication.willEnterForegroundNotification)] {
                now = iso.date(from: next + "T12:00:00Z")!
                NotificationCenter.default.post(name: notification, object: nil)
                for _ in 0..<150 where displayed != [next] { try await Task.sleep(nanoseconds: 10_000_000) }
                XCTAssertEqual(displayed, [next])
                XCTAssertEqual(defaults.string(forKey: "competition_filter_status"), "present")
            }
            XCTAssertEqual(requested, ["2026-10-21", "2026-10-22", "2026-10-23"])
        }
    }
}

import SwiftUI
import XCTest
@testable import CubeFlow

@MainActor
final class CompetitionRecordsRefinementTests: XCTestCase {
    func testPublishedLiveIsVisibleOnlyForAnAvailableProvider() {
        for china in [true, false] {
            XCTAssertEqual(CompetitionDetailNavigationPolicy.tabs(lifecycle: .published, cubingChina: china,
                showLive: true, language: "en"), [.info, .results, .scrambles, .live])
            XCTAssertEqual(CompetitionDetailNavigationPolicy.tabs(lifecycle: .published, cubingChina: china,
                showLive: false, language: "en"), [.info, .results, .scrambles])
            XCTAssertEqual(CompetitionDetailNavigationPolicy.selection(lifecycle: .published, cubingChina: china,
                showLive: false, explicitLive: true, primary: .live, section: .info).primary, .results)
        }
        var content = CompetitionDetailContent.empty
        content.liveURLOverride = URL(string: "https://live.worldcubeassociation.org/competitions/123")
        content.liveAvailability = .ended
        XCTAssertFalse(CompetitionDetailNavigationPolicy.showsLive(content: content, cubingChina: false),
            "An end date or a URL alone cannot establish an available results source")
        XCTAssertFalse(CompetitionDetailNavigationPolicy.showsLive(content: content, cubingChina: true))
        XCTAssertFalse(CompetitionDetailNavigationPolicy.usesCubingChinaLive(cubingChina: false,
            explicitWCALive: true, hasContent: true))
        XCTAssertNotNil(UIImage(systemName: "shuffle"))
    }

    func testCrossProviderRoundTargetNeedsVerifiedMetadataAndOneMatch() throws {
        let options = [option("333", "1"), option("333", "f"), option("777", "1"), option("777", "f")]
        var target = CompetitionWCALiveResultDeepLink(roundID: "opaque-wca-id", personID: "p", personWCAID: nil,
            eventID: "777", roundNumber: 1, finalRoundNumber: 2)
        XCTAssertEqual(target.cubingChinaRound(in: options)?.id, "777|1")
        target.roundNumber = 2
        XCTAssertEqual(target.cubingChinaRound(in: options)?.id, "777|f")
        XCTAssertNil(target.cubingChinaRound(in: options + [option("777", "c")]))
        target.finalRoundNumber = nil
        XCTAssertNil(target.cubingChinaRound(in: options))
        target.eventID = "missing"
        XCTAssertNil(target.cubingChinaRound(in: options))
    }

    func testCurrentChinaArchiveRequiresVerifiedIdentityAndRoundTarget() throws {
        let slug = "Fixture-2026"
        let table: [Any] = [["competition:\(slug)": 1, "live-records:\(slug)": 5],
            ["alias": 2, "live": 3, "wcaCompetitionId": 4], slug, true, "Fixture2026",
            [6, 9], ["eventId": 7, "roundNumber": 8], "777", 1,
            ["eventId": 7, "roundNumber": 10], 2]
        func html(_ values: [Any]) throws -> String {
            "<script id=\"__NUXT_DATA__\" type=\"application/json\">\(String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self))</script>"
        }
        let source = try html(table)
        let archive = try XCTUnwrap(CubingChinaLiveWebsite.parse(html: source, slug: slug,
            expectedWCAID: "Fixture2026"))
        XCTAssertEqual(archive.url.absoluteString, "https://cubing.com/competition/Fixture-2026/live")
        XCTAssertEqual(archive.rounds.map(\.number), [1, 2])
        XCTAssertNil(CubingChinaLiveWebsite.parse(html: source, slug: slug, expectedWCAID: "Wrong2026"))
        XCTAssertNil(CubingChinaLiveWebsite.parse(html: source, slug: "Other-2026", expectedWCAID: nil))
        var notLive = table; notLive[3] = false
        XCTAssertNil(CubingChinaLiveWebsite.parse(html: try html(notLive), slug: slug, expectedWCAID: nil))
        var empty = table; empty[5] = [Int]()
        XCTAssertNil(CubingChinaLiveWebsite.parse(html: try html(empty), slug: slug, expectedWCAID: nil))
        var target = CompetitionWCALiveResultDeepLink(roundID: "opaque-wca-id", personID: nil,
            personWCAID: nil, eventID: "777", roundNumber: 2)
        XCTAssertEqual(archive.targetURL(for: target)?.absoluteString,
            "https://cubing.com/competition/Fixture-2026/live?eventId=777&roundNumber=2")
        target.roundNumber = 3
        XCTAssertNil(archive.targetURL(for: target))
        target.roundNumber = nil
        XCTAssertNil(archive.targetURL(for: target))
        XCTAssertEqual(archive.targetURL(for: nil), archive.url)

        var update = CompetitionDetailContent.empty
        update.cubingChinaLiveWebsite = archive
        update.liveURLOverride = archive.url; update.liveAvailability = .available
        let merged = CompetitionDetailContent.empty.merging(update, resource: .live)
        XCTAssertEqual(merged.cubingChinaLiveWebsite, archive)
        XCTAssertEqual(merged.replacingCompetitors(from: .empty).cubingChinaLiveWebsite, archive)
        XCTAssertTrue(CompetitionDetailNavigationPolicy.showsLive(content: merged, cubingChina: true))
        XCTAssertFalse(CompetitionDetailNavigationPolicy.showsLive(content: merged, cubingChina: false))
        XCTAssertEqual(try JSONDecoder().decode(CompetitionDetailContent.self,
            from: JSONEncoder().encode(merged)).cubingChinaLiveWebsite, archive)
    }

    func testGlobalLiveRoundMetadataSurvivesCandidateAndLegacyCacheDecode() throws {
        let bytes = Data(#"{"id":"r","tag":"AsR","type":"single","attemptResult":8000,"result":{"id":"x","person":{"id":"p","name":"Fixture","country":{"iso2":"CN","name":"China"}},"round":{"id":"opaque","number":1,"competitionEvent":{"event":{"id":"777","name":"7x7"},"competition":{"id":"c","wcaId":"Fixture2026","name":"Fixture"},"rounds":[{"id":"opaque","number":1},{"id":"final","number":2}]}}}}"#.utf8)
        let record = try JSONDecoder().decode(WCARecentRecord.self, from: bytes)
        let item = try XCTUnwrap(WCAExplorePublicDataService.recentRecordsCandidate([record], language: "en")
            .first(where: { $0.id == "records.recent" })?.items.first)
        XCTAssertEqual(item.result?.level, .continental)
        XCTAssertEqual(item.liveResultDeepLink?.eventID, "777")
        XCTAssertEqual(item.liveResultDeepLink?.roundNumber, 1)
        XCTAssertEqual(item.liveResultDeepLink?.finalRoundNumber, 2)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var result = object["result"] as! [String: Any]
        var round = result["round"] as! [String: Any]
        round.removeValue(forKey: "number")
        result["round"] = round; object["result"] = result
        XCTAssertNil(try JSONDecoder().decode(WCARecentRecord.self,
            from: JSONSerialization.data(withJSONObject: object)).result.round.number)
    }

    func testMeasuredFourRowViewportAndInnerScrollingLightDark() throws {
        for scheme in [ColorScheme.light, .dark] {
            for count in [2, 4, 8] {
                let items = records(count)
                let reference = UIHostingController(rootView: VStack(spacing: 0) {
                    ForEach(Array(items.prefix(4))) { item in
                        if item.id != items.first?.id { Divider() }
                        ExploreRecordRow(item: item)
                    }
                })
                let expected = reference.sizeThatFits(in: CGSize(width: 362, height: 2000)).height
                let host = UIHostingController(rootView: ExploreRecentRecordsViewport(items: items) { item in
                    Button {} label: { ExploreRecordRow(item: item) }.buttonStyle(.plain)
                }.environment(\.colorScheme, scheme).ignoresSafeArea()
                    .background(Color(uiColor: .systemBackground)))
                host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
                XCTAssertEqual(host.sizeThatFits(in: CGSize(width: 362, height: 2000)).height, expected, accuracy: 0.5)
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
                let window = UIWindow(windowScene: scene)
                window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
                window.frame = CGRect(x: 0, y: 0, width: 362, height: expected)
                window.rootViewController = host; window.isHidden = false
                host.view.frame = window.bounds; host.view.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                let scroll = try XCTUnwrap(scrollViews(in: host.view).first)
                XCTAssertEqual(scroll.bounds.height, expected, accuracy: 0.5)
                if #available(iOS 26.0, *) {
                    XCTAssertTrue(scroll.topEdgeEffect.isHidden)
                    XCTAssertEqual(scroll.bottomEdgeEffect.style, .soft)
                    XCTAssertFalse(scroll.bottomEdgeEffect.isHidden)
                }
                if count > 4 {
                    XCTAssertGreaterThan(scroll.contentSize.height, expected)
                    let before = scroll.contentOffset.y
                    scroll.setContentOffset(CGPoint(x: 0, y: min(120, scroll.contentSize.height - expected)), animated: false)
                    XCTAssertGreaterThan(scroll.contentOffset.y, before)
                    scroll.setContentOffset(.zero, animated: false)
                } else {
                    XCTAssertEqual(scroll.contentSize.height, expected, accuracy: 1)
                }
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "records-viewport-\(count)-\(scheme)"; attachment.lifetime = .keepAlways; add(attachment)
                try saveSnapshot(image, name: attachment.name ?? "records")
                window.isHidden = true
            }
        }
    }

    func testSelectorBadgeCoordinatesAndLayoutAreUnchangedBySelection() throws {
        for scheme in [ColorScheme.light, .dark] {
            var sizes: [CGSize] = []
            var badgeBounds: [CGRect] = []
            for legacy in [true, false] {
                let view = VStack(alignment: .leading, spacing: 12) {
                    if legacy {
                        legacySelectors
                    } else {
                        PublishedEventSelector(eventIDs: ["333", "777"], selection: .constant("333"),
                            effectiveEvent: "333", language: "en", recordTags: ["333": "CR"])
                        PublishedRoundSelector(rounds: [("one", "1"), ("final", "f")],
                            selection: .constant("one"), language: "en", recordTags: ["one": "CR"])
                    }
                }.padding(16).environment(\.colorScheme, scheme).ignoresSafeArea()
                    .background(Color(uiColor: .systemBackground))
                let host = UIHostingController(rootView: view)
                host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
                let size = host.sizeThatFits(in: CGSize(width: 362, height: 500))
                sizes.append(size)
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
                let window = UIWindow(windowScene: scene)
                window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
                window.frame = CGRect(origin: .zero, size: size)
                window.rootViewController = host; window.isHidden = false
                host.view.frame = window.bounds; host.view.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
                }
                badgeBounds.append(try yellowBounds(image))
                let attachment = XCTAttachment(image: image)
                attachment.name = "selector-bounds-legacy-\(legacy)-\(scheme)"; attachment.lifetime = .keepAlways; add(attachment)
                try saveSnapshot(image, name: attachment.name ?? "selectors")
                window.isHidden = true
            }
            XCTAssertEqual(sizes[0], sizes[1])
            XCTAssertEqual(badgeBounds[0], badgeBounds[1], "Both existing opaque CR badges keep their pixel coordinates")
        }
    }

    private func saveSnapshot(_ image: UIImage, name: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("[RecordsSnapshot] \(url.path)")
    }

    @ViewBuilder private var legacySelectors: some View {
        CompetitionProgressiveBlurScrollView {
            HStack(spacing: 6) {
                ForEach(["333", "777"], id: \.self) { event in
                    let glyph = CompetitionEventIconFont.glyph(for: event)!
                    CompetitionEventGlyph(glyph: glyph, eventName: event, size: 22,
                        color: PublishedEventSelectorStyle.foreground(selected: event == "333"))
                        .offset(PublishedEventSelectorStyle.inkOffset(glyph, size: 22))
                        .frame(width: 36, height: 36)
                        .background(event == "333" ? Color.blue : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.trailing, event == "333" ? 10 : 0)
                        .overlay(alignment: .topTrailing) {
                            if event == "333" { CompetitionWCARecordTagView(tag: "CR", variant: .compact) }
                        }
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(["1", "f"], id: \.self) { round in
                    Text(PublishedCompetitionStrings.round(round, language: "en"))
                        .font(.caption.weight(round == "1" ? .semibold : .regular))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .foregroundStyle(round == "1" ? Color.accentColor : .primary)
                        .background(round == "1" ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                        .padding(.trailing, round == "1" ? 16 : 0)
                        .overlay(alignment: .topTrailing) {
                            if round == "1" { CompetitionWCARecordTagView(tag: "CR", variant: .compact) }
                        }
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private func yellowBounds(_ image: UIImage) throws -> CGRect {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                if bytes[index] > 245 && bytes[index + 1] > 225 && bytes[index + 1] < 245 && bytes[index + 2] < 70 {
                    minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
        }
        XCTAssertGreaterThanOrEqual(maxX, minX)
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func option(_ event: String, _ round: String) -> CompetitionLiveRoundOption {
        .init(id: "\(event)|\(round)", eventID: event, roundID: round, eventName: event, roundName: round,
            statusText: nil, recordedCount: 1, totalCount: 1, formatID: "a")
    }

    private func records(_ count: Int) -> [ExploreItem] {
        (0..<count).map { index in
            ExploreItem(id: "row-\(index)", content: .record(id: "\(index)"),
                title: "7x7x7 Cube average of 1:35.93", subtitle: "Competitor \(index + 1) from Sample country",
                date: nil, result: ExploreResultPresentation(value: "1:35.93", level: .world))
        }
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }
}

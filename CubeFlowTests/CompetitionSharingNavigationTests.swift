import XCTest
import SwiftUI
import WebKit
import CoreText
@testable import CubeFlow

@MainActor final class CompetitionSharingNavigationTests: XCTestCase {
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<250 { if condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTFail("Production presentation did not settle")
    }

    func testNavigationUsesActualStateAndImmediatelyInvalidatesOnTrustOrTargetChange() async throws {
        let model = GuidanceStateTestHarness(), device = UUID(), attempt = UUID()
        let source = CubeSurface.solved(size: 3)
        model.setScramble("R U")
        model.update(facelets: source, trusted: true, deviceID: device, attemptID: attempt, sequence: 1)
        try await wait { model.route != nil }
        let first = try XCTUnwrap(model.route)
        XCTAssertEqual(try first.tokens.reduce(source) { try XCTUnwrap(SmartCubeBluetoothManager.facelets($0, applying: $1)) }, model.target)
        XCTAssertTrue(first.isProvenOptimal)
        model.update(facelets: source, trusted: false, deviceID: device, attemptID: attempt, sequence: 2)
        XCTAssertNil(model.route); XCTAssertNil(model.guidance.currentRequest)
        model.setScramble("F")
        model.update(facelets: source, trusted: true, deviceID: device, attemptID: UUID(), sequence: 3)
        try await wait { model.route != nil }
        XCTAssertEqual(model.route?.tokens, ["F"])
        model.update(facelets: model.target, trusted: true, deviceID: device, attemptID: attempt, sequence: 4)
        XCTAssertTrue(model.reached); XCTAssertNil(model.route)
        model.setScramble("invalid input"); XCTAssertNil(model.target); XCTAssertFalse(model.reached)
        model.cancel()
    }

    private func row(format: String = "a", attempts: [Int] = [900, 1000, -1, -2, 1200], average: Int = 1100,
                     event: String = "333") -> CompetitionShareRow {
        .make(.init(id: "fixture", ranking: 1, isAdvancing: nil, isAdvancingQuestionable: nil,
            attempts: attempts, best: attempts.first ?? 0, average: average, singleRecordTag: "NR", averageRecordTag: "WR",
            roundID: "final", roundName: "Final", roundNumber: 1, eventID: event, eventName: event,
            eventRank: 0, formatID: format, numberOfAttempts: attempts.count, sortBy: "average"), language: "en")
    }

    func testSharingKeepsFormattingAndSeparateVerifiedAggregateBadges() {
        let five = row()
        XCTAssertEqual(five.attempts, ["9.00", "10.00", "DNF", "DNS", "12.00"])
        XCTAssertEqual(five.averageBadge, "WR"); XCTAssertEqual(five.singleBadge, "NR")
        XCTAssertEqual(CompetitionHighlightMetric.choices(for: five).count, 7)
        XCTAssertEqual(CompetitionHighlightMetric.attempt(2).label(five, language: "en"), "Third Solve")
        XCTAssertNil(CompetitionHighlightMetric.attempt(0).badge(five), "An aggregate single record does not identify a solve")
        XCTAssertNil(CompetitionHighlightMetric.attempt(7).value(five))
        let mean = row(format: "m", attempts: [2100, 2200, 2300])
        XCTAssertTrue(mean.isMean); XCTAssertEqual(mean.attempts.count, 3)
        let single = row(format: "1", attempts: [2600], average: 0)
        XCTAssertEqual(CompetitionHighlightMetric.choices(for: single), [.single, .attempt(0)])
        XCTAssertEqual(row(format: "m", attempts: [25], event: "333fm").attempts, ["25"])
        let missing = row(attempts: [900, 0, 1100])
        XCTAssertEqual(missing.attempts, ["9.00", "11.00"])
        XCTAssertEqual(CompetitionHighlightMetric.attempt(1).label(missing, language: "en"), "Third Solve")
    }

    func testReportAndHighlightRenderWithoutExternalArtworkOrNetwork() throws {
        let context = CompetitionSharingContext(name: "Fixture Championship 2026", details: "Test venue")
        for mode in [CompetitionShareRequest.Mode.report, .highlight] {
            let request = CompetitionShareRequest(mode: mode, context: context, name: "Test Competitor", rows: [row()])
            let image = try XCTUnwrap(CompetitionShareRenderer.render(request, metric: .average, artwork: nil, language: "en"))
            XCTAssertEqual(image.size.width, 840); XCTAssertGreaterThan(image.size.height, 250)
            XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 5000)
            let cg = try XCTUnwrap(image.cgImage)
            var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let bitmap = try XCTUnwrap(CGContext(data: &pixels, width: cg.width, height: cg.height, bitsPerComponent: 8,
                bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            bitmap.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            let red = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 180 && pixels[$0 + 1] < 140 && pixels[$0 + 2] < 140 }.count
            XCTAssertGreaterThan(red, 100, "Verified WR badge must be present in the actual exported pixels")
            let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("build/performance-battle-sharing-nov03")
            try image.pngData()?.write(to: directory.appendingPathComponent(mode == .report ? "report.png" : "highlight.png"))
        }
    }

    func testChineseScriptConversionDoesNotTranslateEnglishOrInventTitles() {
        XCTAssertEqual(CompetitionNameScript.display("广州比赛", language: "zh-Hant"), "廣州比賽")
        XCTAssertEqual(CompetitionNameScript.display("廣州比賽", language: "zh-Hans"), "广州比赛")
        XCTAssertEqual(CompetitionNameScript.display("Official Name", language: "en"), "Official Name")
    }

    func testHistogramIntegralUpperBoundaryCountsEachSolveExactlyOnce() {
        for times in [[10.0], [10.0, 12.0], [10.0, 10.5, 11.0, 11.5, 12.0]] {
            let samples = times.map { SessionSolveSample(id: UUID(), date: Date(), time: $0, resultRaw: "solved", scramble: "", comment: "", eventRawValue: "3x3") }
            let trend = SessionSolveTrend(solves: samples)
            XCTAssertEqual(trend.bins.reduce(0) { $0 + $1.count }, times.count)
            XCTAssertTrue(trend.bins.allSatisfy { $0.count >= 0 })
        }
    }

    func testLargeTrendPreservesPointsAndHistogram() {
        let samples = (0..<20_000).reversed().map { index in
            SessionSolveSample(id: UUID(), date: Date(timeIntervalSince1970: Double(index / 3)),
                time: 4 + Double((index * 47) % 1577) / 100,
                resultRaw: index.isMultiple(of: 7) ? "dnf" : index.isMultiple(of: 9) ? "plusTwo" : "solved",
                scramble: "R U R' U' F2", comment: "Trend fixture", eventRawValue: index.isMultiple(of: 9) ? "2x2" : "3x3")
        }
        func reference(_ solves: [SessionSolveSample]) -> ([SessionSolveTrend.Point], [SessionSolveTrend.Bin]) {
            let points = solves.sorted { $0.date < $1.date }.compactMap { solve -> SessionSolveTrend.Point? in
                guard let time = SolveMetrics.adjustedTime(for: solve), time.isFinite, time >= 0 else { return nil }
                return .init(id: solve.id, date: solve.date, time: time)
            }
            let values = points.map(\.time).filter { $0.isFinite && $0 >= 0 }
            guard let lo = values.min(), let hi = values.max() else { return ([], []) }
            let ordered = values.sorted()
            let q1 = ordered[(ordered.count - 1) / 4], q3 = ordered[(ordered.count - 1) * 3 / 4]
            let minimum = solves.contains { PuzzleEvent.fromSolveEvent($0.eventRawValue) == .square1 } ? 1.0 : 0.25
            let preferred = [0.25, 0.5, 1.0, 2, 5, 10, 15, 30, 60]
            let suggested = min(2 * (q3 - q1) / pow(Double(values.count), 1.0 / 3), max(minimum, (hi - lo) / 8))
            var width = preferred.first { $0 >= max(minimum, suggested) } ?? max(60, ceil(suggested / 60) * 60)
            var counts: [Double: Int] = [:], lower = 0.0
            repeat {
                lower = floor(lo / width) * width
                counts.removeAll(keepingCapacity: true)
                let final = max(0, ceil((hi - lower) / width) - 1)
                for value in values { counts[min(final, max(0, floor((value - lower) / width))), default: 0] += 1 }
                if counts.count <= 80 { break }
                width = preferred.first { $0 > width } ?? width * 2
            } while width.isFinite
            return (points, counts.keys.sorted().map {
                .init(lower: lower + $0 * width, upper: lower + ($0 + 1) * width, count: counts[$0]!)
            })
        }
        var baseline: [Double] = [], optimized: [Double] = []
        for _ in 0..<5 {
            var start = ProcessInfo.processInfo.systemUptime
            let old = reference(samples)
            baseline.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            start = ProcessInfo.processInfo.systemUptime
            let new = SessionSolveTrend(solves: samples)
            optimized.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            XCTAssertEqual(new.points, old.0)
            XCTAssertEqual(new.bins, old.1)
        }
        let sq1 = samples + [.init(id: UUID(), date: .distantPast, time: 0, resultRaw: "dnf", scramble: "",
            comment: "", eventRawValue: "square-1")]
        XCTAssertEqual(SessionSolveTrend(solves: sq1).bins, reference(sq1).1)
        print("[SessionSolveTrend] rows=\(samples.count) before_ms=\(baseline) after_ms=\(optimized)")
    }

    func testMountedOrganizerDocumentFitsImagesAndTablesAndRejectsAuthorScripts() async throws {
        let base = OrganizerWebDocument.sourceURL(slug: "fixture", section: "cubing-v2-travel")
        XCTAssertEqual(base.host, "cubing.com")
        XCTAssertEqual(base.path, "/competition/fixture/travel")
        XCTAssertEqual(URL(string: "photo.png", relativeTo: base)?.absoluteURL.path, "/competition/fixture/photo.png")
        XCTAssertEqual(URL(string: "/uploads/photo.png", relativeTo: base)?.absoluteURL.host, "cubing.com")
        let html = "<script>window.authorScriptExecuted=true</script><p>Organizer</p><table style='width:1200px'><tr><td>Wide content</td></tr></table><p>Travel information</p>"
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 320, height: 700)
        window.rootViewController = UIHostingController(rootView: CompetitionOrganizerHTMLView(html: html, baseURL: URL(string: "https://cubing.com")))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func web(_ view: UIView) -> WKWebView? { (view as? WKWebView) ?? view.subviews.lazy.compactMap { web($0) }.first }
        try await wait { window.layoutIfNeeded(); return web(window)?.bounds.height ?? 0 > 40 }
        let view = try XCTUnwrap(web(window))
        let result = try await view.evaluateJavaScript("[typeof window.authorScriptExecuted,document.querySelectorAll('.cf-table').length,document.documentElement.scrollWidth,window.innerWidth]") as? [Any]
        XCTAssertEqual(result?[0] as? String, "undefined"); XCTAssertEqual(result?[1] as? Int, 1)
        XCTAssertEqual(result?[2] as? Int, result?[3] as? Int)
        XCTAssertFalse(view.scrollView.isScrollEnabled)
        XCTAssertFalse(view.configuration.websiteDataStore.isPersistent)
    }

    func testOrganizerLongMixedTextAndTrailingHeadingFitAtAccessibilitySize() async throws {
        let longLink = "https://www.worldcubeassociation.org/competitions/" + String(repeating: "JiangmenOpen2026", count: 10)
        let paragraph = String(repeating: "Organizer 2026 \u{6C5F}\u{9580} competition, registration 20:30. ", count: 28)
        let html = """
        <h2>Organizer information</h2><h3>Official links</h3>
        <p style="height:18px;overflow:hidden">\(paragraph)</p>
        <p><a href="\(longLink)">\(longLink)</a></p>
        <section data-cc-block="card"><div class="cc-card__header"><h3>Registration</h3></div>
        <div class="cc-card__body" style="height:16px;overflow:hidden">
        <ul><li><strong>Registration <em>opens</em></strong></li><li>20:30<br>UTC+8</li></ul></div></section>
        <p></p><h2 id="last">Important dates</h2>
        """
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 320, height: 700)
        func content(_ dark: Bool) -> some View {
            ScrollView { CompetitionOrganizerHTMLView(html: html, baseURL: URL(string: "https://cubing.com")) }
                .environment(\.dynamicTypeSize, dark ? .accessibility3 : .accessibility2)
                .environment(\.colorScheme, dark ? .dark : .light)
        }
        let host = UIHostingController(rootView: content(false))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func web(_ view: UIView) -> WKWebView? { (view as? WKWebView) ?? view.subviews.lazy.compactMap { web($0) }.first }
        try await wait { window.layoutIfNeeded(); return web(window)?.bounds.height ?? 0 > 300 }
        let view = try XCTUnwrap(web(window))
        let result = try await view.evaluateJavaScript("""
            [document.querySelector('#last').getBoundingClientRect().bottom,
             document.querySelector('p').getBoundingClientRect().height,
             document.documentElement.scrollWidth,window.innerWidth,
             document.querySelector('a').getAttribute('href'),
             document.querySelectorAll('li strong em').length]
            """) as? [Any]
        XCTAssertLessThanOrEqual(try XCTUnwrap(result?[0] as? Double), view.bounds.height + 1)
        XCTAssertGreaterThan(try XCTUnwrap(result?[1] as? Double), 100)
        XCTAssertEqual(result?[2] as? Int, result?[3] as? Int)
        XCTAssertEqual(result?[4] as? String, longLink)
        XCTAssertEqual(result?[5] as? Int, 1)
        let nonce = try await view.evaluateJavaScript("document.documentElement.dataset.cfNonce") as? String
        XCTAssertNotNil(nonce)
        let initialFont = try await view.evaluateJavaScript("parseFloat(getComputedStyle(document.body).fontSize)") as? Double
        host.rootView = content(true)
        var dark = ""
        for _ in 0..<100 {
            dark = try await view.evaluateJavaScript("document.documentElement.dataset.cfDark") as? String ?? ""
            if dark == "true" { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(dark, "true")
        XCTAssertTrue(web(window) === view)
        let newNonce = try await view.evaluateJavaScript("document.documentElement.dataset.cfNonce") as? String
        let newFont = try await view.evaluateJavaScript("parseFloat(getComputedStyle(document.body).fontSize)") as? Double
        XCTAssertEqual(newNonce, nonce, "Appearance and text scale must not reload the document")
        XCTAssertGreaterThan(try XCTUnwrap(newFont), try XCTUnwrap(initialFont))
        let oldHeight = view.bounds.height
        _ = try await view.evaluateJavaScript("""
            const img = new Image();
            img.width = 100;
            img.src = "data:image/svg+xml;base64,\(Data("<svg xmlns='http://www.w3.org/2000/svg' width='100' height='650'></svg>".utf8).base64EncodedString())";
            document.querySelector('#cf-content').insertBefore(img,document.querySelector('#last'));
            true
            """)
        try await wait { view.bounds.height > oldHeight + 450 }
        let trailing = try await view.evaluateJavaScript("document.querySelector('#last').getBoundingClientRect().bottom") as? Double
        XCTAssertLessThanOrEqual(try XCTUnwrap(trailing), view.bounds.height + 1)
    }

    func testMountedJiangmenOrganizerSnapshotsFitAtNarrowWidth() async throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let input = repo.appendingPathComponent("build/native-recovery-nov09")
        let artifacts = repo.appendingPathComponent("build/native-compositing-nov09")
        guard FileManager.default.fileExists(atPath: input.appendingPathComponent("jiangmen-about.html").path) else {
            throw XCTSkip("Optional captured public Jiangmen HTML is not present")
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='480' height='240'></svg>"
        let image = "data:image/svg+xml;base64," + Data(svg.utf8).base64EncodedString()
        for (name, section) in [("about", CubingChinaDetailSection.about), ("rules", .regulations), ("travel", .travel)] {
            let raw = try String(contentsOf: input.appendingPathComponent("jiangmen-\(name).html"), encoding: .utf8)
            let blocks = CubingChinaDetailAdapter.blocks(html: raw, section: section, language: "zh-Hans").blocks
            let organizer = try XCTUnwrap(blocks.first { OrganizerWebDocument.sectionKey(for: $0.id) != nil })
            // Keep the real DOM and inline styles; replace network images so
            // coverage does not depend on a CDN or its image sizes.
            let html = try XCTUnwrap(organizer.html).replacingOccurrences(
                of: #"https://i\.cubing\.com/[^"'\s<>]+"#, with: image, options: .regularExpression)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 700)
            window.rootViewController = UIHostingController(rootView:
                ScrollView { CompetitionOrganizerHTMLView(html: html,
                    baseURL: OrganizerWebDocument.sourceURL(slug: "Jiangmen-Open-2026", section: organizer.id)) }
                .frame(width: 320)
                .environment(\.dynamicTypeSize, .accessibility2))
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            func web(_ view: UIView) -> WKWebView? { (view as? WKWebView) ?? view.subviews.lazy.compactMap { web($0) }.first }
            try await wait { window.layoutIfNeeded(); return web(window)?.bounds.height ?? 0 > 300 }
            let view = try XCTUnwrap(web(window))
            let measurement = """
                (() => {
                  const content=document.getElementById('cf-content'), range=document.createRange();
                  range.selectNodeContents(content);
                  return [range.getBoundingClientRect().bottom,document.documentElement.scrollWidth,
                    window.innerWidth,content.querySelectorAll('a').length,content.querySelectorAll('.cf-table').length]
                })()
                """
            var result: [Any]?
            for _ in 0..<200 {
                result = try await view.evaluateJavaScript(measurement) as? [Any]
                if let bottom = result?[0] as? Double, bottom <= view.bounds.height + 1,
                   abs(view.bounds.width - 292) <= 1 { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            let lastText = try XCTUnwrap(result?[0] as? Double)
            XCTAssertLessThanOrEqual(lastText, view.bounds.height + 1, name)
            XCTAssertEqual(view.bounds.width, 292, accuracy: 1, name)
            XCTAssertEqual(result?[1] as? Int, result?[2] as? Int, name)
            if section == .travel { XCTAssertGreaterThan(try XCTUnwrap(result?[4] as? Int), 0) }
            let frame = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
            try frame.pngData()?.write(to: artifacts.appendingPathComponent("jiangmen-\(name)-mounted.png"))
            print("[JiangmenMounted] section=\(name) text_bottom=\(lastText) viewport=\(view.bounds.size)")
        }
    }

    func testMountedJiangmenCertificationUsesNativeUnclippedText() async throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixture = repo.appendingPathComponent("build/native-recovery-nov09/jiangmen-rules.html")
        let chinese = "\u{4E16}\u{754C}\u{9B54}\u{65B9}\u{534F}\u{4F1A}\u{8BA4}\u{8BC1}\u{6BD4}\u{8D5B}"
        let english = "WCA-certified competition"
        let fallback = "<section><h3>\(chinese)</h3><p>WCA <a href='https://www.worldcubeassociation.org/regulations/'>Rules</a></p></section><section><h2>Organizer</h2><div class='prose'><p>Organizer information</p></div></section>"
        let raw = (try? String(contentsOf: fixture, encoding: .utf8)) ?? fallback
        let block = try XCTUnwrap(CubingChinaDetailAdapter.blocks(html: raw, section: .regulations, language: "zh-Hans")
            .blocks.first { $0.title == chinese })
        XCTAssertNil(OrganizerWebDocument.sectionKey(for: block.id))
        let html = try XCTUnwrap(block.html)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        for (index, sample) in [chinese, english, "\(chinese) WCA"].enumerated() {
            let width = CGFloat(index == 0 ? 292 : 350)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: width, height: 740)
            window.overrideUserInterfaceStyle = index == 1 ? .light : .dark
            window.rootViewController = UIHostingController(rootView:
                ScrollView {
                    CompetitionRichHTMLContent(html: html.replacingOccurrences(of: chinese, with: sample),
                        languageCode: index == 1 ? "en" : "zh-Hans", baseURL: URL(string: "https://cubing.com"),
                        leadingTitle: sample)
                }
                .environment(\.dynamicTypeSize, index == 0 ? .large : .accessibility2))
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            func matchingText() -> UITextView? {
                descendants(window).compactMap { $0 as? UITextView }.first {
                    $0.text?.contains(sample) == true && $0.bounds.height > 0
                }
            }
            try await wait { window.layoutIfNeeded(); return matchingText() != nil }
            let view = try XCTUnwrap(matchingText())
            let manager = view.layoutManager
            manager.ensureLayout(for: view.textContainer)
            let chars = (view.text! as NSString).range(of: sample)
            let glyphs = manager.glyphRange(forCharacterRange: chars, actualCharacterRange: nil)
            var locations: [String] = []
            manager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, lineGlyphs, _ in
                let run = NSIntersectionRange(glyphs, lineGlyphs)
                guard run.length > 0 else { return }
                let range = manager.characterRange(forGlyphRange: run, actualGlyphRange: nil)
                let line = CTLineCreateWithAttributedString(view.attributedText.attributedSubstring(from: range))
                let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                let baseline = rect.minY + manager.location(forGlyphAt: run.location).y + view.textContainerInset.top - view.contentOffset.y
                let top = baseline - ink.maxY, bottom = baseline - ink.minY
                locations.append("ink=\(top)...\(bottom) line=\(rect.minY)...\(rect.maxY) baseline=\(baseline)")
                XCTAssertGreaterThanOrEqual(top, -0.5, sample)
                XCTAssertLessThanOrEqual(bottom, view.bounds.height + 0.5, sample)
            }
            XCTAssertFalse(locations.isEmpty)
            XCTAssertFalse(descendants(window).contains { $0 is WKWebView })
            print("[JiangmenCertification] sample=\(index) width=\(view.bounds.width) height=\(view.bounds.height) \(locations.joined(separator: " "))")
            let artifacts = repo.appendingPathComponent("build/native-toolbar-nov09")
            try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
            let frame = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try frame.pngData()?.write(to: artifacts.appendingPathComponent("certification-\(index).png"))
        }
    }
}

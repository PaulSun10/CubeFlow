import XCTest
import SwiftUI
import ImageIO
@testable import CubeFlow

@MainActor final class CompetitionPagedExportTests: XCTestCase {
    private func request(_ count: Int) -> CompetitionShareRequest {
        .init(mode: .report, context: .init(name: "Complete Report", details: "Venue and dates"), name: "Fixture", identity: "2020TEST01",
            rows: (0..<count).map {
                .init(id: "same-id", eventID: "event-\($0 % 4)", eventName: "Event \($0 % 4)", round: "RoundToken-\($0)",
                    rank: String($0 + 1), average: "10.00", single: "9.00", attempts: ["9.00", "DNF", "DNS", "10.00+", "10.25"],
                    averageBadge: $0 == count - 1 ? "WR" : "PR", singleBadge: "NR", isMean: false)
            })
    }
    private func source(_ request: CompetitionShareRequest) -> CompetitionExportSource {
        .init(request: request, artwork: nil, badges: CompetitionShareRenderer.badgeImages(["WR", "CR", "NR", "PR"]),
              headers: ["Round", "Average", "Mean", "Best", "Results"], metricLabel: "Average", metricValue: "10.00", metricBadge: nil)
    }
    func testReportPlanPreservesAllRowsAttemptsAndMetadataAndRejectsExtremeSize() throws {
        let request = request(512), started = ProcessInfo.processInfo.systemUptime
        let plan = try CompetitionReportLayout.plan(source(request))
        let text = plan.commands.compactMap { command -> String? in
            if case .text(let text, _, _, _, _, _) = command { return text }; return nil
        }
        XCTAssertEqual(text.filter { $0.contains("RoundToken-") }.count, 512, "Duplicate provider IDs must not drop rows")
        for row in request.rows { XCTAssertTrue(text.contains("#\(row.rank)  \(row.round)"), row.round) }
        for metadata in ["Complete Report", "Venue and dates", "Fixture", "2020TEST01", "DNF", "DNS", "10.00+"] {
            XCTAssertTrue(text.contains { $0.contains(metadata) })
        }
        XCTAssertFalse(text.contains("CubeFlow"))
        XCTAssertThrowsError(try CompetitionReportLayout.plan(source(self.request(4000)))) {
            XCTAssertTrue($0 is CompetitionReportImageError)
        }
        let dimensions = try CompetitionReportImageLimits.dimensions(plan.size)
        XCTAssertGreaterThanOrEqual(dimensions.width, 840)
        XCTAssertLessThanOrEqual(dimensions.width * dimensions.height, 48_000_000)
        print("[NativeUIReport] layout512_ms=\((ProcessInfo.processInfo.systemUptime - started) * 1000)")
    }

    func testLongMetadataAndAttemptsWrapWithinSingleLayout() throws {
        let value = Array(repeating: "Long metadata \u{9577}\u{6587}\u{5B57} ", count: 600).joined()
        let request = CompetitionShareRequest(mode: .report, context: .init(name: value, details: value), name: value,
            rows: [.init(id: "one", eventID: "333", eventName: value, round: value, rank: "1", average: "10.00", single: "9.00",
                attempts: Array(repeating: "10.00+", count: 600), averageBadge: "WR", singleBadge: "NR", isMean: false)])
        let plan = try CompetitionReportLayout.plan(source(request))
        let commands = plan.commands
        for command in commands {
            XCTAssertGreaterThanOrEqual(command.rect.minY, 0)
            XCTAssertLessThanOrEqual(command.rect.maxY, plan.size.height)
            XCTAssertLessThanOrEqual(command.rect.maxX, plan.size.width)
        }
        let attempts = commands.compactMap { command -> String? in
            if case .text(let text, _, _, _, _, _) = command { return text }; return nil
        }.joined(separator: " ")
        XCTAssertEqual(attempts.components(separatedBy: "10.00+").count - 1, 600)
    }

    func testProductionExportsOneReadableImageAndLeaseRetainsFile() async throws {
        let start = ProcessInfo.processInfo.systemUptime
        var before = rusage()
        getrusage(RUSAGE_SELF, &before)
        var document: CompetitionShareDocument? = try await CompetitionShareRenderer.exportDocument(request(512), metric: .average, artwork: nil, language: "en")
        var after = rusage()
        getrusage(RUSAGE_SELF, &after)
        let directory = try XCTUnwrap(document?.directory), files = try XCTUnwrap(document?.pages)
        XCTAssertEqual(files.count, 1, "Preview strips must never become share items")
        let file = try XCTUnwrap(files.first)
        XCTAssertEqual(file.rowIndices, Array(0..<512))
        XCTAssertLessThanOrEqual(file.pixelWidth * file.pixelHeight, 48_000_000)
        XCTAssertGreaterThanOrEqual(file.pixelWidth, 840)
        let tiles = try XCTUnwrap(document?.previewTiles)
        XCTAssertEqual(tiles.reduce(0) { $0 + $1.pixelHeight }, file.pixelHeight)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(file.url as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight as String] as? Int, file.pixelHeight)
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth as String] as? Int, file.pixelWidth)
        let maximum = await CompetitionDocumentExporter.shared.maximumReportStripBitmapBytes
        let main = await CompetitionDocumentExporter.shared.renderedOnMain
        XCTAssertLessThan(maximum, 3_000_000); XCTAssertFalse(main)
        let bytes = try file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        print("[NativeUIReport] rows=512 image=\(file.pixelWidth)x\(file.pixelHeight) png_bytes=\(bytes) elapsed_ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000) bitmap_bytes=\(maximum) rss_before=\(before.ru_maxrss) rss_after=\(after.ru_maxrss)")
        let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 4096
        ] as CFDictionary)
        XCTAssertNotNil(decoded, "Check the actual long PNG decoder, not only IHDR metadata")
        var share: SystemShareSheet? = SystemShareSheet(items: files.map(\.url), retainedResource: document)
        var owner: SystemShareSheet.Coordinator? = share?.makeCoordinator()
        share = nil; document = nil
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path), "Native share retains its file lease")
        XCTAssertNotNil(owner?.retainedResource)
        owner = nil
        for _ in 0..<300 where FileManager.default.fileExists(atPath: directory.path) { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testActualPNGDecodesAndUsesAdjacentStandardBadges() async throws {
        let sample = request(9)
        let source = self.source(sample)
        let plan = try CompetitionReportLayout.plan(source)
        let values = plan.commands.enumerated().filter { _, command in
            if case .text("10.00", _, _, _, _, _) = command { return true }; return false
        }
        XCTAssertEqual(values.count, sample.rows.count)
        for (index, value) in values {
            guard case .image(let badge, let rect) = plan.commands[index + 1] else { return XCTFail("Missing adjacent badge") }
            XCTAssertGreaterThan(rect.minX, value.rect.minX)
            XCTAssertLessThan(rect.minX - value.rect.minX, 100)
            XCTAssertEqual(rect.minY - value.rect.minY, 1, accuracy: 0.01)
            XCTAssertTrue([source.badges["WR"]?.size, source.badges["PR"]?.size].contains(badge.size))
        }
        let document = try await CompetitionShareRenderer.exportDocument(sample, metric: .average, artwork: nil, language: "en")
        let url = try XCTUnwrap(document.pages.first?.url)
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        XCTAssertEqual(image.height, document.pages.first?.pixelHeight)
        let artifacts = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/native-ui-nov05")
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        try Data(contentsOf: url).write(to: artifacts.appendingPathComponent("report-sample.png"))
    }

    func testHighlightPNGHasCompactIdentityBadgeAndAllAttemptsWithoutTopRule() async throws {
        let report = request(1)
        let highlight = CompetitionShareRequest(mode: .highlight, context: report.context, name: report.name,
            identity: report.identity, rows: report.rows)
        let source = CompetitionExportSource(request: highlight, artwork: nil,
            badges: CompetitionShareRenderer.badgeImages(["WR", "NR"], compact: true, isOwn: true, pixelScale: 4),
            headers: ["Round", "Average", "Mean", "Best", "Results"], metricLabel: "Average", metricValue: "10.00", metricBadge: "WR",
            showsHighlightAttempts: true)
        let plan = try CompetitionHighlightLayout.plan(source)
        XCTAssertLessThan(plan.size.height, 620)
        XCTAssertEqual(plan.size.width, 620)
        let text = plan.commands.compactMap { command -> String? in
            if case .text(let value, _, _, _, _, _) = command { return value }; return nil
        }.joined(separator: " ")
        XCTAssertFalse(text.contains("CubeFlow"))
        for expected in ["Fixture", "2020TEST01", "RoundToken-0", "#1", "10.00", "DNF", "DNS", "10.00+"] {
            XCTAssertTrue(text.contains(expected), expected)
        }
        guard case .fill(let background, let color) = plan.commands.first else { return XCTFail("Missing background") }
        XCTAssertEqual(background.size, plan.size)
        XCTAssertGreaterThan(color.cgColor.components?.first ?? 0, 0.9)
        XCTAssertFalse(plan.commands.dropFirst().contains { $0.rect.minY == 0 })
        XCTAssertEqual(plan.commands.filter { if case .image = $0 { return true }; return false }.count, 1)
        let value = try XCTUnwrap(plan.commands.first {
            if case .text("10.00", _, 72, _, _, _) = $0 { return true }; return false
        }?.rect)
        let badge = try XCTUnwrap(plan.commands.first { if case .image = $0 { return true }; return false }?.rect)
        let numberFont = UIFont.monospacedDigitSystemFont(ofSize: 72, weight: .bold)
        let numberInkTop = value.minY + numberFont.ascender - numberFont.capHeight
        XCTAssertEqual(badge.minY, numberInkTop, accuracy: 1)
        XCTAssertLessThan(badge.midY, numberInkTop + numberFont.capHeight / 2)
        XCTAssertEqual(badge.height, try XCTUnwrap(source.badges["WR"]).size.height * 2)
        XCTAssertLessThanOrEqual(badge.maxX, plan.size.width - 36)
        var single = source
        single.showsHighlightAttempts = false
        let singlePlan = try CompetitionHighlightLayout.plan(single)
        XCTAssertFalse(singlePlan.commands.contains { if case .text(let value, _, _, _, _, _) = $0 { return value.contains("DNS") }; return false })
        XCTAssertLessThan(singlePlan.size.height, plan.size.height)
        let document = try await CompetitionShareRenderer.exportDocument(highlight, metric: .average, artwork: nil, language: "en")
        XCTAssertEqual(document.pages.count, 1)
        let url = try XCTUnwrap(document.pages.first?.url)
        XCTAssertNotNil(UIImage(contentsOfFile: url.path)?.cgImage)
        let artifacts = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/native-recovery-nov09")
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        try Data(contentsOf: url).write(to: artifacts.appendingPathComponent("highlight.png"))
    }

    func testLongTimedReportKeepsMeasuredAttemptsInlineAndExportsPNG() async throws {
        let events = [("333", "3x3x3"), ("444", "4x4x4"), ("555", "5x5x5"), ("666", "6x6x6"), ("777", "7x7x7"), ("minx", "Megaminx")]
        let request = CompetitionShareRequest(mode: .report,
            context: .init(name: "Jiangmen Open", details: "江门，广东 · 中国"), name: "Fixture",
            rows: events.map { id, name in
                .init(id: id, eventID: id, eventName: name, round: "Final", rank: "3",
                      average: "2:13.70", single: "2:09.05",
                      attempts: ["2:09.05", "2:12.24", "2:14.79", "2:16.10+", "DNF"],
                      averageBadge: nil, singleBadge: "PR", isMean: false)
            })
        let plan = try CompetitionReportLayout.plan(source(request))
        let rows = plan.commands.compactMap { command -> (String, CGRect)? in
            if case .text(let text, let rect, _, _, _, _) = command { return (text, rect) }
            return nil
        }
        let rules = plan.commands.compactMap { command -> CGRect? in
            if case .fill(let rect, _) = command, rect.height == 1 { return rect }
            return nil
        }
        XCTAssertEqual(rules.count, events.count)
        for (event, rule) in zip(events, rules) {
            let heading = try XCTUnwrap(rows.first { $0.0 == event.1 }?.1)
            XCTAssertEqual(rule.minX, heading.minX)
            XCTAssertEqual(rule.maxX, heading.maxX)
            XCTAssertEqual(heading.minY - rule.minY, 10)
        }
        let attempts = rows.filter { $0.0.contains("2:16.10+") }
        XCTAssertEqual(attempts.count, events.count)
        XCTAssertTrue(attempts.allSatisfy { $0.0.contains("2:09.05") && $0.0.contains("DNF") })
        let firstLabels = rows.filter { $0.0 == "Average" }
        XCTAssertEqual(firstLabels.count, events.count)
        for (event, label) in zip(events, firstLabels) {
            let heading = try XCTUnwrap(rows.first { $0.0 == event.1 }?.1)
            XCTAssertEqual(label.1.minY - heading.maxY, 5, accuracy: 0.01)
        }
        for (index, attempt) in attempts.enumerated() {
            XCTAssertTrue(rows.contains { $0.0 == "2:13.70" && $0.1.midY == attempt.1.midY && $0.1.maxX < attempt.1.minX })
            if index + 1 < rules.count {
                // The text command includes three points of line leading.
                XCTAssertEqual(rules[index + 1].minY - attempt.1.maxY, 5, accuracy: 0.01)
            }
        }
        let document = try await CompetitionShareRenderer.exportDocument(request, metric: .average, artwork: nil, language: "en")
        let page = try XCTUnwrap(document.pages.first)
        XCTAssertEqual(document.pages.count, 1)
        XCTAssertNotNil(UIImage(contentsOfFile: page.url.path)?.cgImage)
        try saveArtifact(page.url, "report-long-times.png")
    }

    func testHighlightVariantsExportInBothAppearances() async throws {
        for tag in [nil, "PR", "NR", "CR", "WR"] as [String?] {
            let row = CompetitionShareRow(id: "long", eventID: "minx", eventName: "Megaminx", round: "Final",
                rank: "11", average: "2:04.30", single: "1:59.24", attempts: ["1:59.24", "2:03.56", "2:07.14+", "DNF", "2:02.11"],
                averageBadge: tag, singleBadge: nil, isMean: false)
            let request = CompetitionShareRequest(mode: .highlight,
                context: .init(name: "International Spring Championship and Jiangmen Open 2026", details: "江门，广东 · 中国"),
                name: "A Long Competitor Name for Wrapping and Mixed Script 陈思源", identity: "2020TEST01", rows: [row])
            for dark in [false, true] {
                let document = try await CompetitionShareRenderer.exportDocument(request, metric: .average,
                    artwork: nil, language: dark ? "zh-Hans" : "en", highlightDark: dark)
                let page = try XCTUnwrap(document.pages.first)
                XCTAssertEqual(document.pages.count, 1)
                XCTAssertEqual(UIImage(contentsOfFile: page.url.path)?.cgImage?.width, page.pixelWidth)
                try saveArtifact(page.url, "highlight-\(tag ?? "ordinary")-\(dark ? "dark" : "light").png")
            }
            if tag == nil {
                let document = try await CompetitionShareRenderer.exportDocument(request, metric: .single,
                    artwork: nil, language: "en")
                try saveArtifact(try XCTUnwrap(document.pages.first).url, "highlight-single-light.png")
            }
        }
    }

    func testReportRetainsBannerAndCompleteBilingualContent() async throws {
        let sample = request(12)
        let artwork = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 180)).image { context in
            UIColor(red: 0.10, green: 0.22, blue: 0.35, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 180))
            ("Jiangmen Open 2026" as NSString).draw(at: CGPoint(x: 35, y: 56),
                withAttributes: [.font: UIFont.systemFont(ofSize: 50, weight: .semibold), .foregroundColor: UIColor.white])
        }
        let request = CompetitionShareRequest(mode: .report,
            context: .init(name: "江门公开赛 Jiangmen Open", details: "江门，广东 · 中国",
                           artwork: .init(kind: .banner, url: URL(fileURLWithPath: "/fixture-banner.png"))),
            name: "Chen Siyuan 陈思源 — Mixed Script Competitor", identity: "2020TEST01", rows: sample.rows)
        let fixture = source(request)
        let plan = try CompetitionReportLayout.plan(.init(request: request, artwork: artwork, badges: fixture.badges,
            headers: fixture.headers, metricLabel: fixture.metricLabel, metricValue: fixture.metricValue, metricBadge: fixture.metricBadge))
        XCTAssertTrue(plan.commands.contains { command in
            if case .image(let image, let rect) = command { return image === artwork && rect.width > 600 }
            return false
        })
        let document = try await CompetitionShareRenderer.exportDocument(request, metric: .average, artwork: artwork, language: "zh-Hans")
        XCTAssertEqual(document.pages.count, 1)
        let page = try XCTUnwrap(document.pages.first)
        XCTAssertEqual(UIImage(contentsOfFile: page.url.path)?.cgImage?.height, page.pixelHeight)
        try saveArtifact(page.url, "report-bilingual-banner.png")
    }

    private func saveArtifact(_ url: URL, _ name: String) throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/native-recovery-nov09")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(contentsOf: url).write(to: directory.appendingPathComponent(name))
    }

    func testSharingLocationUsesVerifiedCityProvinceAndDeduplicatesMunicipalities() {
        let jiangmen: [String: Any] = ["regionIso2": "CN", "cityName": "江门", "provinceName": "广东"]
        let metadata = ["locations": [jiangmen]]
        XCTAssertEqual(CubingChinaDetailAdapter.sharingLocation(in: metadata, language: "zh-Hans"), "江门，广东 · 中国")
        XCTAssertEqual(CubingChinaDetailAdapter.sharingLocation(in: metadata, language: "zh-Hant"), "江門，廣東 · 中國")
        XCTAssertNil(CubingChinaDetailAdapter.sharingLocation(in: metadata, language: "en"))
        let beijing = ["regionIso2": "CN", "cityName": "北京", "provinceName": "北京"]
        XCTAssertEqual(CubingChinaDetailAdapter.sharingLocation(in: ["locations": [beijing]], language: "zh-Hans"), "北京 · 中国")
        XCTAssertNil(CubingChinaDetailAdapter.sharingLocation(in: ["locations": [jiangmen, beijing]], language: "zh-Hans"))
    }

    func testSingleRoundAndTypicalMultiEventReportsExportAtFullResolution() async throws {
        let artifacts = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/native-ui-nov05")
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        for count in [1, 68] {
            let started = ProcessInfo.processInfo.systemUptime
            let document = try await CompetitionShareRenderer.exportDocument(request(count), metric: .average, artwork: nil, language: "en")
            let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
            XCTAssertEqual(document.pages.count, 1)
            let file = try XCTUnwrap(document.pages.first)
            XCTAssertEqual(file.rowIndices, Array(0..<count))
            XCTAssertEqual(file.pixelWidth, 1680)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(file.url as CFURL, nil))
            XCTAssertNotNil(CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2048
            ] as CFDictionary))
            let bytes = try Data(contentsOf: file.url)
            if count == 1 { try bytes.write(to: artifacts.appendingPathComponent("report-single-round.png")) }
            print("[NativeUIReport] rows=\(count) image=\(file.pixelWidth)x\(file.pixelHeight) png_bytes=\(bytes.count) elapsed_ms=\(elapsed)")
        }
    }

    func testTraditionalChineseReportImageIncludesCompetitionAndThreeNamedStages() async throws {
        let rows = ["初賽", "複賽", "決賽"].enumerated().map { index, name in
            CompetitionShareRow(id: "round-\(index)", eventID: "333", eventName: "三階魔方", round: name,
                rank: String(index + 1), average: "7.26", single: "6.53", attempts: ["6.53", "7.03", "DNF", "7.69+", "7.05"],
                averageBadge: "PR", singleBadge: "CR", isMean: false)
        }
        let request = CompetitionShareRequest(mode: .report,
            context: .init(name: "2026 北京金秋魔方賽", details: "中國北京  ·  2026.10.24"),
            name: "示例選手", identity: "2026TEST01", rows: rows)
        let document = try await CompetitionShareRenderer.exportDocument(request, metric: .average, artwork: nil, language: "zh-Hant")
        XCTAssertEqual(document.pages.count, 1)
        let file = try XCTUnwrap(document.pages.first)
        XCTAssertEqual(file.rowIndices, [0, 1, 2])
        XCTAssertNotNil(UIImage(contentsOfFile: file.url.path)?.cgImage)
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/native-ui-nov05")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(contentsOf: file.url).write(to: directory.appendingPathComponent("report-zh-Hant.png"))
    }

    func testCancelledExportNeverPublishesPartialDocumentAndConcurrentExportsStayIndependent() async throws {
        let cancelled = Task { try await CompetitionShareRenderer.exportDocument(request(3000), metric: .average, artwork: nil, language: "en") }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled export published") } catch is CancellationError {} catch { XCTFail("\(error)") }
        let a = Task { try await CompetitionShareRenderer.exportDocument(request(2), metric: .average, artwork: nil, language: "en") }
        let b = Task { try await CompetitionShareRenderer.exportDocument(request(3), metric: .single, artwork: nil, language: "zh-Hant") }
        let first = try await a.value, second = try await b.value
        XCTAssertNotEqual(first.directory, second.directory)
        XCTAssertEqual(Set(first.pages.flatMap(\.rowIndices)), [0, 1])
        XCTAssertEqual(Set(second.pages.flatMap(\.rowIndices)), [0, 1, 2])
    }

    func testCancellationAfterWritingFirstPageRemovesPartialFiles() async throws {
        let probe = WrittenPageCancellation()
        await CompetitionDocumentExporter.shared.debugObserveWrittenPage { directory in probe.cancel(directory) }
        let task = Task { try await CompetitionShareRenderer.exportDocument(request(512), metric: .average, artwork: nil, language: "en") }
        probe.install(task)
        do { _ = try await task.value; XCTFail("Partial export published") }
        catch is CancellationError {} catch { XCTFail("\(error)") }
        await CompetitionDocumentExporter.shared.debugObserveWrittenPage(nil)
        let directory = try XCTUnwrap(probe.directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}

nonisolated private final class WrittenPageCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<CompetitionShareDocument, Error>?
    private var value: URL?
    var directory: URL? { lock.lock(); defer { lock.unlock() }; return value }
    func install(_ task: Task<CompetitionShareDocument, Error>) { lock.lock(); self.task = task; lock.unlock() }
    func cancel(_ directory: URL) { lock.lock(); value = directory; let task = task; lock.unlock(); task?.cancel() }
}

import XCTest
import SwiftUI
@testable import CubeFlow

@MainActor final class ExploreRegionPackingTests: XCTestCase {
    private let events = ExploreCompetitionEventStrip.officialEvents
    private let counts = [1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17]

    func testActualGlyphPartitionsKeepEveryEventInOrderAndFillFirstRowBeforeWrapping() {
        XCTAssertTrue(CompetitionEventIconFont.ensureRegistered())
        for category in [UIContentSizeCategory.extraSmall, .small, .medium, .large, .extraLarge,
                         .extraExtraLarge, .extraExtraExtraLarge, .accessibilityMedium, .accessibilityLarge,
                         .accessibilityExtraLarge, .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge] {
            let traits = UITraitCollection(preferredContentSizeCategory: category)
            let icon = UIFontMetrics(forTextStyle: .footnote).scaledValue(for: 18, compatibleWith: traits)
            let font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            for count in counts {
                let widths = events.prefix(count).map { ExploreCompetitionEventStrip.width($0, iconSize: icon, labelFont: font, language: "en") }
                let available: CGFloat = category.isAccessibilityCategory ? 278 : 248
                let rows = ExploreEventPacking.rows(widths: widths, available: available)
                XCTAssertEqual(rows.flatMap { Array($0.indices) }, Array(0..<count))
                for row in rows {
                    let used = row.indices.map { widths[$0] }.reduce(0, +) + CGFloat(row.indices.count - 1) * row.spacing
                    XCTAssertLessThanOrEqual(used, available + 0.001)
                    XCTAssertGreaterThanOrEqual(row.spacing, ExploreEventPacking.minimumSpacing)
                    XCTAssertLessThanOrEqual(row.spacing, ExploreEventPacking.maximumSpacing)
                    if row.indices.upperBound < count {
                        let next = widths[row.indices.upperBound]
                        XCTAssertGreaterThan(row.indices.map { widths[$0] }.reduce(0, +) + next
                            + CGFloat(row.indices.count) * ExploreEventPacking.minimumSpacing, available)
                    }
                }
                if !category.isAccessibilityCategory { XCTAssertLessThanOrEqual(rows.count, 2) }
                print("[RegionRows] type=\(category.rawValue) icon=\(icon) width=\(available) count=\(count) rows=\(rows.map { $0.indices.count }) gaps=\(rows.map(\.spacing))")
            }
        }
        // Unequal ink widths, not event-count rules, determine the split.
        let uneven = ExploreEventPacking.rows(widths: [60, 60, 10, 10, 10, 10], available: 140)
        XCTAssertEqual(uneven.first?.indices, 0..<3)
        XCTAssertTrue(ExploreEventPacking.rows(widths: [], available: 248).isEmpty)
    }

    func testAdaptiveSquareCellsScaleDownContinuouslyThenWrapAtMeasuredCapacity() {
        XCTAssertTrue(CompetitionEventIconFont.ensureRegistered())
        for available in [CGFloat(248), 278] {
            var previous = CGFloat.infinity
            var sizes: [Int: CGFloat] = [:]
            for count in counts {
                let layout = ExploreCompetitionEventStrip.layout(eventIDs: Array(events.prefix(count)), minimumIcon: 18,
                    labelFont: .systemFont(ofSize: 13), language: "en", available: available)
                XCTAssertGreaterThanOrEqual(layout.iconSize, 18)
                XCTAssertLessThanOrEqual(layout.iconSize, 36)
                XCTAssertLessThanOrEqual(layout.iconSize, previous + 0.001)
                previous = layout.iconSize; sizes[count] = layout.iconSize
                XCTAssertEqual(layout.rows.flatMap { Array($0.indices) }, Array(0..<count))
                XCTAssertGreaterThanOrEqual(layout.cellSide, layout.iconSize + 6 - 0.001)
                for row in layout.rows {
                    XCTAssertLessThanOrEqual(CGFloat(row.indices.count) * layout.cellSide
                        + CGFloat(row.indices.count - 1) * row.spacing, available + 0.001)
                    if row.indices.upperBound < count {
                        XCTAssertGreaterThan(CGFloat(row.indices.count + 1) * layout.cellSide
                            + CGFloat(row.indices.count) * ExploreEventPacking.minimumSpacing, available)
                    }
                }
                print("[AdaptiveRegion] width=\(available) count=\(count) font=\(layout.iconSize) cell=\(layout.cellSide) rows=\(layout.rows.map { $0.indices.count }) gaps=\(layout.rows.map(\.spacing)) height=\(layout.reservedHeight)")
            }
            XCTAssertGreaterThan(sizes[5]!, sizes[8]!)
            XCTAssertGreaterThan(sizes[1]!, 30)
        }
    }

    private func mount<V: View>(_ content: V, width: CGFloat) throws -> (UIWindow, UIHostingController<V>) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 1800)
        let host = UIHostingController(rootView: content)
        window.rootViewController = host; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        return (window, host)
    }
    private func settle(_ window: UIWindow) async throws {
        for _ in 0..<5 { window.layoutIfNeeded(); try await Task.sleep(nanoseconds: 15_000_000) }
    }
    private func snapshot(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let item = XCTAttachment(image: image); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    func testMountedGlyphBoundsAndReservedHeightAcrossCountsTextSizesAndWidths() async throws {
        for (size, available) in [(DynamicTypeSize.large, CGFloat(248)), (.xxxLarge, 248), (.accessibility3, 278), (.accessibility5, 278)] {
            var heights: [CGFloat] = []
            for count in counts {
                var frames: [String: CGRect] = [:]
                let content = ExploreCompetitionEventStrip(eventIDs: Array(events.prefix(count)), language: "en", availableWidth: available)
                    .environment(\.dynamicTypeSize, size)
                    .environment(\.exploreRegionalMeasurement, { frames.merge($0, uniquingKeysWith: { _, new in new }) })
                    .fixedSize().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                let (window, host) = try mount(content, width: available)
                defer { window.isHidden = true; window.rootViewController = nil }
                try await settle(window)
                XCTAssertEqual(frames.count, count)
                let ordered = events.prefix(count).compactMap { frames["event-" + $0] }
                let firstRow = ordered.filter { abs($0.minY - (ordered.first?.minY ?? 0)) < 0.1 }
                for (index, frame) in ordered.enumerated() {
                    XCTAssertGreaterThanOrEqual(frame.minX, -0.01)
                    XCTAssertLessThanOrEqual(frame.maxX, available + 0.01)
                    XCTAssertGreaterThan(frame.width, 0)
                    let column = ordered.prefix(index).filter { abs($0.minY - frame.minY) < 0.1 }.count
                    XCTAssertEqual(frame.midX, firstRow[column].midX, accuracy: 0.01,
                        "Every actual row must retain the first row's column pitch")
                    if index > 0 {
                        let previous = ordered[index - 1]
                        if abs(previous.minY - frame.minY) < 0.1 { XCTAssertGreaterThanOrEqual(frame.minX, previous.maxX + 0.9) }
                        else { XCTAssertGreaterThanOrEqual(frame.minY, previous.maxY) }
                    }
                }
                let ideal = UIHostingController(rootView: ExploreCompetitionEventStrip(eventIDs: Array(events.prefix(count)), language: "en", availableWidth: available).environment(\.dynamicTypeSize, size))
                heights.append(ideal.sizeThatFits(in: CGSize(width: available, height: 1800)).height)
                XCTAssertNotNil(host.view)
                if count == 17 { snapshot(window, name: "region-events-17-\(size)") }
            }
            for height in heights { XCTAssertEqual(height, heights[0], accuracy: 0.1) }
        }
    }
    private func items() -> [ExploreItem] {
        let date = Date(timeIntervalSince1970: 1_791_504_000)
        return counts.enumerated().map { index, count in
            ExploreItem(id: "region-\(count)", content: .competition(id: "fixture-\(count)"),
                title: index == 1 ? "A Longer Regional Championship Competition 2026" : "Regional Open 2026",
                subtitle: index == 2 ? "A longer location name, Hong Kong" : "Hong Kong", date: date,
                competition: ExploreCompetitionPresentation(start: date, end: date.addingTimeInterval(index % 2 == 0 ? 86400 : 0), eventCount: count,
                    registrationOpen: false, eventIDs: Array(events.prefix(count))))
        }
    }
    func testMountedRegionalGlyphInkIsCenteredWithoutChangingAcceptedCellPacking() async throws {
        for available in [CGFloat(248), 278] {
            var frames: [String: CGRect] = [:]
            let strip = ExploreCompetitionEventStrip(eventIDs: events, language: "en", availableWidth: available)
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .large)
                .environment(\.exploreRegionalMeasurement, { frames.merge($0, uniquingKeysWith: { _, new in new }) })
                .fixedSize().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color.white)
            let (window, _) = try mount(strip, width: available)
            defer { window.isHidden = true; window.rootViewController = nil }
            try await settle(window)
            let format = UIGraphicsImageRendererFormat(); format.scale = 3; format.opaque = true
            let rendered = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let image = try XCTUnwrap(rendered.cgImage)
            let columns = image.width, rows = image.height
            var pixels = [UInt8](repeating: 255, count: columns * rows * 4)
            try pixels.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: columns, height: rows,
                    bitsPerComponent: 8, bytesPerRow: columns * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            }
            for event in events {
                let frame = try XCTUnwrap(frames["event-" + event])
                let firstY = try XCTUnwrap(frames["event-" + events[0]]).minY
                let firstRow = events.compactMap { frames["event-" + $0] }.filter { abs($0.minY - firstY) < 0.1 }
                let earlier = events.prefix(while: { $0 != event }).compactMap { frames["event-" + $0] }
                let column = earlier.filter { abs($0.minY - frame.minY) < 0.1 }.count
                XCTAssertEqual(frame.midX, firstRow[column].midX, accuracy: 0.01, event)
                var left = columns, right = -1
                for y in max(0, Int(frame.minY * 3))..<min(rows, Int(ceil(frame.maxY * 3))) {
                    for x in max(0, Int(frame.minX * 3))..<min(columns, Int(ceil(frame.maxX * 3))) {
                        let index = (y * columns + x) * 4
                        if pixels[index] < 100 && pixels[index + 1] < 100 && pixels[index + 2] < 100 {
                            left = min(left, x); right = max(right, x)
                        }
                    }
                }
                XCTAssertGreaterThanOrEqual(right, left, "No actual ink for \(event)")
                XCTAssertEqual(CGFloat(left + right + 1) / 6, frame.midX, accuracy: 0.7, event)
            }
            let item = XCTAttachment(image: rendered); item.name = "regional-ink-centers-\(available)"
            item.lifetime = .keepAlways; add(item)
        }
    }
    func testMountedProductionRegionalFamilyHasUniformRealCardHeightAtEachScreenWidth() async throws {
        let items = items()
        let module = ExploreModule(id: "region", titleKey: "explore.in_region", presentation: .carousel, items: items, seeAll: .competitions, titleTable: "ExploreHome")
        for width in [CGFloat(320), 393, 440] {
            for size in [DynamicTypeSize.large, .xxxLarge, .accessibility3, .accessibility5] {
                var frames: [String: CGRect] = [:]
                let content = ExploreModuleView(module: module, store: ExploreStore(), language: "en")
                    .environment(\.dynamicTypeSize, size)
                    .environment(\.colorScheme, width == 440 ? .dark : .light)
                    .environment(\.exploreRegionalMeasurement, { frames.merge($0, uniquingKeysWith: { _, new in new }) })
                    .frame(maxHeight: .infinity, alignment: .top).background(ExploreStyle.page)
                let (window, _) = try mount(content, width: width)
                defer { window.isHidden = true; window.rootViewController = nil }
                try await settle(window)
                let cards = items.compactMap { frames["card-" + $0.id] }
                XCTAssertEqual(cards.count, counts.count)
                for card in cards {
                    XCTAssertEqual(card.width, size.isAccessibilitySize ? 310 : 280, accuracy: 0.1)
                    XCTAssertEqual(card.height, cards[0].height, accuracy: 0.1)
                    XCTAssertLessThan(card.height, 1700, "Must be natural content, not the viewport height")
                }
                let areas = items.compactMap { frames["event-area-" + $0.id] }
                XCTAssertEqual(areas.count, counts.count)
                for area in areas {
                    XCTAssertEqual(area.minY, areas[0].minY, accuracy: 0.1)
                    XCTAssertEqual(area.height, areas[0].height, accuracy: 0.1)
                }
                print("[RegionFamily] screen=\(width) type=\(size) heights=\(cards.map(\.height))")
                if width == 393 || (width == 440 && size == .large) {
                    snapshot(window, name: "region-family-\(size)-\(width == 440 ? "dark" : "light")")
                }
            }
        }
    }
    func testMountedAdaptiveGalleryInBothThemes() async throws {
        for dark in [false, true] {
            let content = VStack(alignment: .leading, spacing: 12) {
                ForEach([1, 3, 5, 7, 9, 13, 17], id: \.self) { count in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(count) events").font(.caption).foregroundStyle(.secondary)
                        ExploreCompetitionEventStrip(eventIDs: Array(self.events.prefix(count)), language: "en")
                    }.padding(16).background(ExploreStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                }
            }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(ExploreStyle.page).environment(\.colorScheme, dark ? .dark : .light)
            let (window, _) = try mount(content, width: 320)
            defer { window.isHidden = true; window.rootViewController = nil }
            try await settle(window)
            snapshot(window, name: "adaptive-region-gallery-\(dark ? "dark" : "light")")
        }
    }
    func testRecreatedAndChangedWidthOrContentUseCurrentMetricsWithoutStaleMeasurements() {
        let reused = UIHostingController(rootView: ExploreCompetitionEventStrip(eventIDs: ["333"], language: "zh-Hans"))
        for width in [CGFloat(180), 248, 278, 330] {
            for count in [1, 17, 5, 14] {
                let content = ExploreCompetitionEventStrip(eventIDs: Array(events.prefix(count)), language: "zh-Hans", availableWidth: width)
                reused.rootView = content
                let host = UIHostingController(rootView: content)
                let fit = host.sizeThatFits(in: CGSize(width: width, height: 1800))
                let updated = reused.sizeThatFits(in: CGSize(width: width, height: 1800))
                XCTAssertEqual(updated.height, fit.height, accuracy: 0.1)
                XCTAssertEqual(fit.width, width, accuracy: 0.1)
                XCTAssertGreaterThan(fit.height, 0)
                let labels = events.prefix(count).map { CompetitionEventPresentation.localizedFullName(for: $0, languageCode: "zh-Hans") }
                XCTAssertEqual(labels.count, count)
                XCTAssertTrue(items().allSatisfy { if case .competition = $0.content { return true }; return false })
            }
        }
    }
}

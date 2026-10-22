import XCTest
import SwiftUI
@testable import CubeFlow

private struct ChipFrames: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
@MainActor private final class ChipGeometry {
    var frames: [Int: CGRect] = [:]
    var anchors: [Int: UIView] = [:]
}
private struct BadgePixelAnchor: UIViewRepresentable {
    let mounted: (UIView) -> Void
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        mounted(view)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {}
}
private extension View {
    func packingProbe(_ index: Int) -> some View {
        background { GeometryReader { proxy in
            Color.clear.preference(key: ChipFrames.self, value: [index: proxy.frame(in: .named("packing"))])
        } }
    }
}

@available(iOS 16.0, *)
@MainActor final class CompetitionTopCuberPackingTests: XCTestCase {
    private func mount<V: View>(_ content: V, width: CGFloat) throws -> (UIWindow, UIHostingController<V>) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 1600)
        let host = UIHostingController(rootView: content)
        window.rootViewController = host; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        return (window, host)
    }
    private func settle() async throws { try await Task.sleep(nanoseconds: 100_000_000) }
    private func assertOrderedMaximal(_ frames: [CGRect], width: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        for (index, frame) in frames.enumerated() {
            XCTAssertGreaterThanOrEqual(frame.minX, -0.01, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, width + 0.01, file: file, line: line)
            guard index > 0 else { continue }
            let previous = frames[index - 1]
            if abs(previous.minY - frame.minY) < 0.01 {
                XCTAssertEqual(frame.minX, previous.maxX + 8, accuracy: 0.01, file: file, line: line)
            } else {
                XCTAssertGreaterThan(frame.minY, previous.minY, file: file, line: line)
                XCTAssertEqual(frame.minX, 0, accuracy: 0.01, file: file, line: line)
                XCTAssertGreaterThan(previous.maxX + 8 + frame.width, width, "Next consecutive chip must genuinely not fit", file: file, line: line)
            }
        }
    }

    func testExactFitFractionalBoundaryAndNoRankSkipping() async throws {
        for width in [CGFloat(180.375), 180.25, 196] {
            let state = ChipGeometry()
            let sizes: [CGFloat] = width == 196 ? [140, 120, 40, 35] : [100.125, 72.25, 30.5, 20]
            let root = CompetitionWrappingLayout {
                ForEach(sizes.indices, id: \.self) { index in
                    Color.gray.frame(width: sizes[index], height: 30).packingProbe(index)
                }
            }.coordinateSpace(name: "packing").frame(width: width)
                .onPreferenceChange(ChipFrames.self) { state.frames = $0 }
            let (window, _) = try mount(root, width: width)
            defer { window.isHidden = true; window.rootViewController = nil }
            try await settle()
            let frames = try sizes.indices.map { try XCTUnwrap(state.frames[$0]) }
            assertOrderedMaximal(frames, width: width)
            if width == 180.375 { XCTAssertEqual(frames[0].minY, frames[1].minY) }
            else { XCTAssertGreaterThan(frames[1].minY, frames[0].minY) }
            if width == 196 {
                XCTAssertEqual(frames[1].minY, frames[2].minY)
                XCTAssertGreaterThan(frames[2].minY, frames[0].minY, "Never backfill NR ahead of CR")
            }
        }
    }

    func testRealChipsPackConsecutivelyAtRenderedIntrinsicWidthsAcrossEnvironments() async throws {
        let entries: [CompetitionTopCuberPreview] = ["Max Park", "Wesley", "\u{738b}\u{827a}\u{8861}", "Long competitor name with wrapping", "NR E"].enumerated().map {
            .init(id: String($0.offset), name: $0.element,
                  badges: [.init(id: "333", eventID: "333", tier: $0.offset < 2 ? .wr : $0.offset < 4 ? .cr : .nr)])
        }
        for width in [CGFloat(280), 320, 390, 768] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                for language in ["en", "zh-Hans"] {
                    let state = ChipGeometry()
                    let root = CompetitionWrappingLayout {
                        ForEach(entries.indices, id: \.self) { index in
                            CompetitionTopCuberChip(preview: entries[index], language: language, iconsReady: true).packingProbe(index)
                        }
                    }.coordinateSpace(name: "packing").frame(width: width)
                        .dynamicTypeSize(size).onPreferenceChange(ChipFrames.self) { state.frames = $0 }
                    let (window, _) = try mount(root, width: width)
                    defer { window.isHidden = true; window.rootViewController = nil }
                    try await settle()
                    let frames = try entries.indices.map { try XCTUnwrap(state.frames[$0]) }
                    assertOrderedMaximal(frames, width: width)
                    for index in entries.indices {
                        let host = UIHostingController(rootView: CompetitionTopCuberChip(preview: entries[index], language: language, iconsReady: true).dynamicTypeSize(size))
                        let measured = host.sizeThatFits(in: CGSize(width: width, height: 10000))
                        // UIKit's hosting fit rounds up while Layout retains
                        // fractional points. Allow only that physical-pixel edge.
                        let pixel = 1 / window.traitCollection.displayScale + 0.001
                        XCTAssertEqual(frames[index].width, measured.width, accuracy: pixel)
                        XCTAssertEqual(frames[index].height, measured.height, accuracy: pixel)
                    }
                    print("[TopChipPacking] width=\(width) size=\(size) lang=\(language) frames=\(frames)")
                }
            }
        }
    }

    func testRecordBadgesAreSquareInAllTiersAndFallbacks() throws {
        for size in [DynamicTypeSize.large, .accessibility3] {
            for tier in [CompetitionTopCuberTier.wr, .cr, .nr] {
                for icons in [false, true] {
                    let host = UIHostingController(rootView: CompetitionTopCuberRecordBadge(
                        badge: .init(id: "sq1", eventID: "sq1", tier: tier), language: "zh-Hans", iconsReady: icons).dynamicTypeSize(size))
                    let actual = host.sizeThatFits(in: CGSize(width: 300, height: 300))
                    XCTAssertEqual(actual.width, actual.height, accuracy: 0.01)
                    XCTAssertGreaterThan(actual.width, 0)
                    if size == .large { XCTAssertEqual(actual.width, 25, accuracy: 0.01) }
                }
            }
        }
    }

    func testEveryOfficialEventOutlineIsCenteredWithoutChangingItsScale() throws {
        XCTAssertTrue(CompetitionEventIconFont.ensureRegistered())
        for event in ["222", "333", "444", "555", "666", "777", "333bf", "333fm", "333oh",
                      "clock", "minx", "pyram", "skewb", "sq1", "444bf", "555bf", "333mbf"] {
            let glyph = try XCTUnwrap(CompetitionEventIconFont.glyph(for: event))
            for scale in [CGFloat(1), 2] {
                let rect = CGRect(x: 0, y: 0, width: 25 * scale, height: 25 * scale)
                let path = CompetitionTopCuberEventInk(glyph: glyph,
                    fontName: CompetitionEventIconFont.fontName, pointSize: 13 * scale).path(in: rect)
                let metrics = try XCTUnwrap(CompetitionEventIconFont.glyphMetrics(for: glyph, pointSize: 13 * scale))
                XCTAssertFalse(path.isEmpty)
                XCTAssertEqual(path.boundingRect.midX, rect.midX, accuracy: 0.001, event)
                XCTAssertEqual(path.boundingRect.midY, rect.midY, accuracy: 0.001, event)
                XCTAssertEqual(path.boundingRect.width, metrics.bounds.width, accuracy: 0.01, event)
                XCTAssertEqual(path.boundingRect.height, metrics.bounds.height, accuracy: 0.01, event)
            }
        }
    }

    func testNativeGlassBadgesKeepTierColoredInkInBothAppearancesAndSchemes() async throws {
        for scheme in [ColorScheme.light, .dark] {
            for glass in [false, true] {
                let state = ChipGeometry()
                let badges = HStack(spacing: 30) {
                    ForEach(0..<3) { index in
                        CompetitionTopCuberRecordBadge(badge: .init(id: "333", eventID: "333",
                            tier: [CompetitionTopCuberTier.wr, .cr, .nr][index]), language: "en", iconsReady: true)
                            .background { BadgePixelAnchor { state.anchors[index] = $0 } }
                    }
                }.padding(20)
                let root = Group {
                    if #available(iOS 26.0, *), glass {
                        badges.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
                    } else { badges.background(Color(uiColor: .secondarySystemGroupedBackground)) }
                }.foregroundStyle(.white)
                    .frame(width: 390, height: 1600)
                    .background(Color(uiColor: .systemGroupedBackground))
                    .environment(\.colorScheme, scheme).preferredColorScheme(scheme)
                let (window, _) = try mount(root, width: 390)
                defer { window.isHidden = true; window.rootViewController = nil }
                try await settle()
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image {
                    _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let bitmap = try XCTUnwrap(image.cgImage)
                var pixels = [UInt8](repeating: 0, count: bitmap.width * bitmap.height * 4)
                try pixels.withUnsafeMutableBytes { buffer in
                    let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: bitmap.width, height: bitmap.height,
                        bitsPerComponent: 8, bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                    context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
                }
                for index in 0..<3 {
                    let anchor = try XCTUnwrap(state.anchors[index])
                    let frame = anchor.convert(anchor.bounds, to: window).insetBy(dx: 5, dy: 5)
                    var colored = 0
                    for y in Int(frame.minY * image.scale)..<Int(frame.maxY * image.scale) {
                        for x in Int(frame.minX * image.scale)..<Int(frame.maxX * image.scale) {
                            let offset = (y * bitmap.width + x) * 4
                            let r = Int(pixels[offset]), g = Int(pixels[offset + 1]), b = Int(pixels[offset + 2])
                            if index == 0 ? (r > 190 && g < 115 && b < 115)
                                : index == 1 ? (r > 215 && g > 85 && g < 195 && b < 80)
                                : (r > 215 && g > 170 && b < 80) { colored += 1 }
                        }
                    }
                    XCTAssertGreaterThan(colored, 5, "tier=\(index) scheme=\(scheme) glass=\(glass)")
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "tier-ink-\(scheme)-glass-\(glass)"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }

    func testProductionChipLightAndDarkAppearance() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let entries: [CompetitionTopCuberPreview] = ["Max Park", "Yiheng Wang", "Tymon Kolasi\u{144}ski"].enumerated().map {
                .init(id: String($0.offset), name: $0.element, badges: [.init(id: "333", eventID: "333", tier: [.wr, .cr, .nr][$0.offset])])
            }
            let root = VStack(alignment: .leading, spacing: 12) {
                Text("Top Cubers").font(.subheadline.weight(.semibold))
                CompetitionWrappingLayout {
                    ForEach(entries) { CompetitionTopCuberChip(preview: $0, language: "en", iconsReady: true) }
                }.competitionSizeDebug("section available", color: .blue)
            }.padding(16).frame(width: 390).background(Color(uiColor: .systemBackground)).environment(\.colorScheme, scheme)
            let (window, host) = try mount(root, width: 390)
            defer { window.isHidden = true; window.rootViewController = nil }
            try await settle()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "top-cubers-chips-\(scheme)"; attachment.lifetime = .keepAlways; add(attachment)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("top-cubers-polish", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try image.pngData()?.write(to: folder.appendingPathComponent("\(scheme).png"))
            _ = host
        }
    }
}

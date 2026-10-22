import XCTest
import SwiftUI
@testable import CubeFlow

@MainActor final class CompetitionSeparatorEvidenceTests: XCTestCase {
    func testProductionTopBoundariesUseOneRasterRowAcrossFractionalLayoutOrigins() async throws {
        CompetitionResultSeparatorDiagnostics.measureRows = true
        CompetitionResultSeparatorDiagnostics.rows = [:]
        let phases: [CGFloat] = [0, 1.0/6, 1.0/3, 0.5, 2.0/3, 5.0/6]
        let root = ZStack(alignment: .topLeading) {
            Color.white
            ForEach(phases.indices, id: \.self) { index in
                CompetitionResultRoundRow(showsBoundary: true) { Color.white.frame(width: 300, height: 36) }
                    .competitionResultRowProbe("phase-\(index)")
                    .padding(.top, 100 + CGFloat(index) * 70 + phases[index])
            }
        }.ignoresSafeArea().environment(\.displayScale, 3).environment(\.colorScheme, .light)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIHostingController(rootView: root); window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<15 { window.layoutIfNeeded(); try await Task.sleep(nanoseconds: 30_000_000) }
        let format = UIGraphicsImageRendererFormat(); format.scale = 3; format.preferredRange = .standard; format.opaque = true
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let cg = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(cg.bitsPerPixel, 32)
        let bytes = try XCTUnwrap(cg.dataProvider?.data) as Data
        var referenceColor: [UInt8]?
        for index in phases.indices {
            let frame = try XCTUnwrap(CompetitionResultSeparatorDiagnostics.rows["phase-\(index)"])
            let first = Int(floor(frame.minY * 3))
            let x = Int((frame.minX + 200) * 3)
            let colored = ((first - 2)...(first + 4)).filter { y in
                let offset = y * cg.bytesPerRow + x * 4
                return bytes[offset] < 253 || bytes[offset + 1] < 253 || bytes[offset + 2] < 253
            }
            print("[SeparatorRaster] phase=\(phases[index]) origin=\(frame.minY) pixels=\(colored)")
            XCTAssertEqual(colored.count, 1, "phase \(phases[index]); actual pixel rows \(colored)")
            if let y = colored.first {
                let start = y * cg.bytesPerRow + x * 4
                let color = Array(bytes[start..<(start + 3)])
                if let referenceColor { XCTAssertEqual(color, referenceColor, "Do not trade differing coverage for differing opacity") }
                else { referenceColor = color }
            }
            XCTAssertEqual(frame.height, 36 + 1.0/3, accuracy: 0.001)
        }
        let attachment = XCTAttachment(image: image); attachment.name = "production-separator-fractional-origins"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testHeaderPaintAndBoundaryFootprintRemainUnchanged() {
        for scale: CGFloat in [2, 3] {
            for origin: CGFloat in [183.83333333333331, 402.49999999999994, 584.8333333333333] {
                let height: CGFloat = 29
                let previous = ((origin + height - 1 / scale) * scale).rounded() / scale - origin
                XCTAssertEqual(CompetitionRoundBoundaryPaint.localY(origin: origin, height: height, scale: scale, bottom: true), previous, accuracy: 1e-12)
                XCTAssertEqual(CompetitionRoundBoundaryPaint.localY(origin: origin, height: 36 + 1 / scale, scale: scale, bottom: false), 0)
            }
        }
    }
    func testPhysicalCaptureSelectedGroupsAreNotMisreadAsPreferredReferenceStyle() {
        // Actual selected IDs from CD9B962C; these are the unwanted thick lines.
        let selected = ["333:published-333|954898:published-333|954899", "333:published-333|954899:published-333|954900",
            "333:published-333|954900:published-333|954901", "222:published-222|954903:published-222|954904"]
        let thinReferences = ["222:published-222|954902:published-222|954903", "444:published-444|954905:published-444|954906"]
        var selection = CompetitionSeparatorSelection()
        for id in selected { selection.toggle(id) }
        XCTAssertEqual(selection.ids.filter { $0.hasPrefix("333:") }.count, 3)
        XCTAssertEqual(selection.ids.filter { $0.hasPrefix("222:") }.count, 1)
        XCTAssertFalse(thinReferences.contains { selection.ids.contains($0) })
        // Both selected and unselected lines have phase .5 in the capture.
        // Their differing clipped local placement, not this phase alone, matters.
        let selectedNativeY = [746.5, 855.5, 964.5, 1512.5]
        let unselectedNativeY = [1402.5, 1949.5, 2059.5]
        for y in selectedNativeY + unselectedNativeY { XCTAssertEqual(y - floor(y), 0.5) }
        selection.toggle(selected[0]); XCTAssertFalse(selection.ids.contains(selected[0]))
        selection.undo(); XCTAssertTrue(selection.ids.contains(selected[0]))
    }

}

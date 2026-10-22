import XCTest
import SwiftUI
@testable import CubeFlow

@MainActor final class CompetitionRecordBadgeRenderingTests: XCTestCase {
    private func pixels<V: View>(_ view: V, dark: Bool = false) async throws -> [UInt8] {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 180, height: 80)
        window.rootViewController = UIHostingController(rootView: view.frame(width: 180, height: 80)
            .background(dark ? Color.black : .white).environment(\.colorScheme, dark ? .dark : .light))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<3 { window.layoutIfNeeded(); try await Task.sleep(nanoseconds: 20_000_000) }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: cg.width, height: cg.height,
            bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return bytes
    }
    private func count(_ bytes: [UInt8], _ predicate: (Int, Int, Int) -> Bool) -> Int {
        stride(from: 0, to: bytes.count, by: 4).filter {
            predicate(Int(bytes[$0]), Int(bytes[$0+1]), Int(bytes[$0+2]))
        }.count
    }
    func testRealResultValueUsesBlueOnlyForVerifiedOwnPRInBothThemes() async throws {
        for dark in [false, true] {
            let own = try await pixels(CompetitionResultTableStatisticValue(text: "10.00", recordTag: "PR",
                width: 72, emphasized: true, isOwnRecord: true), dark: dark)
            let other = try await pixels(CompetitionResultTableStatisticValue(text: "10.00", recordTag: "PR",
                width: 72, emphasized: true), dark: dark)
            let ordinary = try await pixels(CompetitionResultTableStatisticValue(text: "10.00", recordTag: nil,
                width: 72, emphasized: true, isOwnRecord: true), dark: dark)
            let blue: (Int, Int, Int) -> Bool = { r, g, b in b > 150 && g > 60 && b > g + 35 && b > r + 70 }
            XCTAssertGreaterThan(count(own, blue), 25)
            XCTAssertEqual(count(other, blue), 0)
            XCTAssertEqual(count(ordinary, blue), 0)
        }
    }
    func testRegionalBadgeColorsUnchangedForOwnVersusOther() async throws {
        for tag in ["WR", "CR", "NR"] {
            let own = try await pixels(CompetitionWCARecordTagView(tag: tag, isOwnPersonalRecord: true))
            let other = try await pixels(CompetitionWCARecordTagView(tag: tag))
            XCTAssertEqual(own, other, "Ownership must never recolor \(tag)")
            if tag == "NR" { XCTAssertGreaterThan(count(own, { r, g, b in g > 180 && r < 60 && b < 160 }), 25) }
        }
    }
}

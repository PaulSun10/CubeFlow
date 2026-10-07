#if os(iOS)
import UIKit

/// Canonical sticker identities, not baked-in RGB pixels. Rasterized once per palette/pose.
enum AlgLastLayerDiagram {
    static func image(stickers: [String: String], colors: [String], quarterTurns: Int = 0) -> UIImage? {
        guard colors.count == 6, ["us", "ub", "uf", "ul", "ur"].allSatisfy({ stickers[$0]?.count == 9 }) else { return nil }
        let palette = Dictionary(uniqueKeysWithValues: zip(Array("yogwrb"), colors.map { UIColor(scrambleHex: $0) }))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 224, height: 224), format: format).image { renderer in
            let ctx = renderer.cgContext
            ctx.translateBy(x: 112, y: 112)
            ctx.rotate(by: CGFloat(quarterTurns % 4) * .pi / 2)
            ctx.translateBy(x: -112, y: -112)
            func cell(_ color: Character, _ rect: CGRect) {
                let fill = palette[color] ?? UIColor.systemGray3
                ctx.setFillColor(fill.cgColor)
                ctx.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 4).cgPath)
                ctx.fillPath()
            }
            for (i, color) in Array(stickers["us"]!).enumerated() {
                cell(color, CGRect(x: 28 + i % 3 * 56, y: 28 + i / 3 * 56, width: 52, height: 52))
            }
            for (face, side) in [("ub", 0), ("ur", 1), ("uf", 2), ("ul", 3)] {
                for (i, color) in Array(stickers[face]!.prefix(3)).enumerated() {
                    let rect: CGRect
                    switch side {
                    case 0: rect = CGRect(x: 28 + (2-i)*56, y: 8, width: 52, height: 16)
                    case 1: rect = CGRect(x: 200, y: 28+i*56, width: 16, height: 52)
                    case 2: rect = CGRect(x: 28+i*56, y: 200, width: 52, height: 16)
                    default: rect = CGRect(x: 8, y: 28+(2-i)*56, width: 16, height: 52)
                    }
                    cell(color, rect)
                }
            }
        }
    }
}
#endif

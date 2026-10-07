#if os(iOS)
import UIKit

/// Complete upper/lower views share one padded intrinsic canvas, in every Alg presentation.
enum SquareOneCaseDiagram {
    static let canvasSize = CGSize(width: 224, height: 456)

    static func image(setup: String, colors: [String] = ScrambleColorConfiguration.default.squareOne, quarterTurns: Int = 0) -> UIImage? {
        var state = SquareOneState()
        guard state.apply(setup) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        guard colors.count == 6 else { return nil }
        let palette = colors.map { UIColor(scrambleHex: $0) }
        let sideColors = [palette[1], palette[5], palette[4], palette[2]]
        // Each piece's original adjacent side stickers, independent of its current position.
        let edges = [0, 1, 2, 3, 3, 2, 1, 0]
        let corners = [[0,1],[1,2],[2,3],[3,0],[0,3],[3,2],[2,1],[1,0]]
        let reach = 1 + sqrt(3.0) / 2
        // A corner can rotate beyond the square silhouette during cube-shape cases.
        let drawingScale = (canvasSize.width / 2 - 8) / (sqrt(2) * reach)
        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { renderer in
            let ctx = renderer.cgContext
            for (layer, sectors) in [state.top, state.bottom].enumerated() {
                ctx.saveGState()
                ctx.translateBy(x: 112, y: layer == 0 ? 112 : 344)
                ctx.rotate(by: CGFloat(quarterTurns % 4) * .pi / 2)
                ctx.scaleBy(x: drawingScale, y: drawingScale)
                var index = 0
                while index < 12 {
                    let piece = sectors[index]
                    if sectors[(index + 11) % 12] == piece {
                        index += 1
                        continue
                    }
                    let corner = piece % 2 == 1
                    let angle = -Double(layer == 0 ? (corner ? index - 1 : index) : (corner ? index - 6 : index - 5)) * .pi / 6
                    ctx.saveGState()
                    ctx.rotate(by: angle)
                    let boundary: [CGPoint] = corner
                        ? [.zero, CGPoint(x: -0.5, y: -reach), CGPoint(x: -reach, y: -reach), CGPoint(x: -reach, y: -0.5)]
                        : [.zero, CGPoint(x: -0.5, y: -reach), CGPoint(x: 0.5, y: -reach)]
                    func polygon(_ points: [CGPoint], color: UIColor) {
                        ctx.beginPath(); ctx.addLines(between: points); ctx.closePath()
                        ctx.setFillColor(color.cgColor); ctx.fillPath()
                        ctx.beginPath(); ctx.addLines(between: points); ctx.closePath()
                        ctx.setStrokeColor(UIColor.black.cgColor); ctx.setLineWidth(1.5 / drawingScale); ctx.strokePath()
                    }
                    if corner {
                        polygon([boundary[0], boundary[1], boundary[2]], color: sideColors[corners[piece / 2][0]])
                        polygon([boundary[0], boundary[2], boundary[3]], color: sideColors[corners[piece / 2][1]])
                    } else {
                        polygon(boundary, color: sideColors[edges[piece / 2]])
                    }
                    polygon(boundary.map { CGPoint(x: $0.x * 0.68, y: $0.y * 0.68) }, color: piece < 8 ? palette[0] : palette[3])
                    ctx.restoreGState()
                    index += corner ? 2 : 1
                }
                ctx.restoreGState()
            }
        }
    }
}
#endif

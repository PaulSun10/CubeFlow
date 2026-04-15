import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct AlgSetPayload: Decodable {
    let cases: [AlgCase]
}

struct AlgCase: Decodable {
    let imageKey: String
    let stickers: Stickers?
}

struct Stickers: Decodable {
    let us: String
    let ub: String
    let uf: String
    let ul: String
    let ur: String
}

enum Palette {
    static func color(for sticker: Character) -> NSColor {
        switch sticker.lowercased() {
        case "r": return NSColor(hex: 0xD00000)
        case "o": return NSColor(hex: 0xEE8800)
        case "b": return NSColor(hex: 0x2040D0)
        case "g": return NSColor(hex: 0x11AA00)
        case "w": return NSColor(hex: 0xFFFFFF)
        case "y": return NSColor(hex: 0xFFFF00)
        case "l": return NSColor(hex: 0x888888)
        case "d": return NSColor(hex: 0x555555)
        case "x": return NSColor(hex: 0x999999)
        case "k": return NSColor(hex: 0x111111)
        case "c": return NSColor(hex: 0x0099FF)
        case "p": return NSColor(hex: 0xFF99CC)
        case "m": return NSColor(hex: 0xFF0099)
        default: return NSColor(hex: 0x888888)
        }
    }

    static let background = NSColor.black
}

extension NSColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xff) / 255
        let green = CGFloat((hex >> 8) & 0xff) / 255
        let blue = CGFloat(hex & 0xff) / 255
        self.init(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}

func writePNG(context: CGContext, url: URL) throws {
    guard let image = context.makeImage() else {
        throw NSError(domain: "PLLImageGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to make CGImage"])
    }

    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "PLLImageGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination"])
    }

    CGImageDestinationAddImage(destination, image, nil)
    if !CGImageDestinationFinalize(destination) {
        throw NSError(domain: "PLLImageGenerator", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PNG"])
    }
}

func drawSticker(
    context: CGContext,
    rect: CGRect,
    color: NSColor,
    topLeft: CGFloat,
    topRight: CGFloat,
    bottomLeft: CGFloat,
    bottomRight: CGFloat
) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
    path.addQuadCurve(
        to: CGPoint(x: rect.maxX, y: rect.minY + topRight),
        control: CGPoint(x: rect.maxX, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
    path.addQuadCurve(
        to: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY),
        control: CGPoint(x: rect.maxX, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
    path.addQuadCurve(
        to: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft),
        control: CGPoint(x: rect.minX, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
    path.addQuadCurve(
        to: CGPoint(x: rect.minX + topLeft, y: rect.minY),
        control: CGPoint(x: rect.minX, y: rect.minY)
    )
    path.closeSubpath()

    context.addPath(path)
    context.setFillColor(color.cgColor)
    context.fillPath()
}

func drawJCube(stickers: Stickers, into context: CGContext, width: CGFloat, height: CGFloat, rank: Int = 3) {
    let margin = width / 9
    let rawStickerSize = (height - margin * 2) / CGFloat(rank)
    let gap = rawStickerSize / 10
    let stickerSize = rawStickerSize - gap
    let corner = stickerSize / 4

    context.setFillColor(Palette.background.cgColor)
    context.fill(CGRect(x: margin, y: margin, width: width - margin * 2, height: height - margin * 2))

    let charsUS = Array(stickers.us)
    for row in 0..<rank {
        for col in 0..<rank {
            let idx = col + row * rank
            guard idx < charsUS.count else { continue }

            var tl = corner
            var tr = corner
            var bl = corner
            var br = corner

            if row == 0 {
                tl = 0
                bl = 0
                if col == 0 && rank != 2 { br = 1 }
            }
            if col == 0 {
                tl = 0
                tr = 0
                if row == rank - 1 && rank != 2 { bl = 1 }
            }
            if row == rank - 1 {
                tr = 0
                br = 0
                if rank != 2 { tr = col == rank - 1 ? 1 : tr }
            }
            if col == rank - 1 {
                bl = 0
                br = 0
                if row == rank - 1 && rank != 2 { tl = 1 }
            }

            let rect = CGRect(
                x: margin + CGFloat(col) * (stickerSize + gap) + gap / 2,
                y: margin + CGFloat(row) * (stickerSize + gap) + gap / 2,
                width: stickerSize / 2 + corner,
                height: stickerSize / 2 + corner
            ).insetBy(dx: -stickerSize / 4, dy: -stickerSize / 4)

            drawSticker(
                context: context,
                rect: rect,
                color: Palette.color(for: charsUS[idx]),
                topLeft: tl,
                topRight: tr,
                bottomLeft: bl,
                bottomRight: br
            )
        }
    }

    let topStripChars = Array(stickers.ub)
    let bottomStripChars = Array(stickers.uf)
    let leftStripChars = Array(stickers.ul)
    let rightStripChars = Array(stickers.ur)

    for i in 0..<rank {
        let topChar = topStripChars[max(0, rank - 1 - i)]
        let bottomChar = bottomStripChars[min(bottomStripChars.count - 1, i)]
        let leftChar = leftStripChars[min(leftStripChars.count - 1, i)]
        let rightChar = rightStripChars[max(0, rank - 1 - i)]

        let topRect = CGRect(
            x: margin + CGFloat(i) * (stickerSize + gap) + gap / 2,
            y: gap / 2,
            width: stickerSize,
            height: margin - gap
        )
        let bottomRect = CGRect(
            x: margin + CGFloat(i) * (stickerSize + gap) + gap / 2,
            y: margin + CGFloat(rank) * (stickerSize + gap) + gap / 2,
            width: stickerSize,
            height: margin - gap
        )
        let leftRect = CGRect(
            x: gap / 2,
            y: margin + CGFloat(i) * (stickerSize + gap) + gap / 2,
            width: margin - gap,
            height: stickerSize
        )
        let rightRect = CGRect(
            x: margin + CGFloat(rank) * (stickerSize + gap) + gap / 2,
            y: margin + CGFloat(i) * (stickerSize + gap) + gap / 2,
            width: margin - gap,
            height: stickerSize
        )

        drawSticker(context: context, rect: topRect, color: Palette.color(for: topChar), topLeft: 1, topRight: 1, bottomLeft: 1, bottomRight: 1)
        drawSticker(context: context, rect: bottomRect, color: Palette.color(for: bottomChar), topLeft: 1, topRight: 1, bottomLeft: 1, bottomRight: 1)
        drawSticker(context: context, rect: leftRect, color: Palette.color(for: leftChar), topLeft: 1, topRight: 1, bottomLeft: 1, bottomRight: 1)
        drawSticker(context: context, rect: rightRect, color: Palette.color(for: rightChar), topLeft: 1, topRight: 1, bottomLeft: 1, bottomRight: 1)
    }
}

func generateImage(for algCase: AlgCase, outputDirectory: URL) throws {
    guard let stickers = algCase.stickers else { return }

    let width = 75
    let height = 75

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "PLLImageGenerator", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create graphics context"])
    }

    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    context.clear(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

    drawJCube(stickers: stickers, into: context, width: CGFloat(width), height: CGFloat(height))

    let outputURL = outputDirectory.appendingPathComponent("\(algCase.imageKey).png")
    try writePNG(context: context, url: outputURL)
}

let arguments = CommandLine.arguments
let jsonPath = arguments.count > 1 ? arguments[1] : "/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Resources/Algs/pll.json"
let outputPath = arguments.count > 2 ? arguments[2] : "/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Resources/Algs/PLLImages"

let jsonURL = URL(fileURLWithPath: jsonPath)
let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)

let payload = try JSONDecoder().decode(AlgSetPayload.self, from: Data(contentsOf: jsonURL))
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for algCase in payload.cases {
    try generateImage(for: algCase, outputDirectory: outputDirectory)
}

print("Generated \(payload.cases.count) PLL images in \(outputDirectory.path)")

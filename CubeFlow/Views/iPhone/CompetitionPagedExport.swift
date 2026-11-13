#if os(iOS)
import UIKit
import ImageIO
import CoreText

nonisolated struct CompetitionExportPage: Identifiable, Sendable {
    let id: Int
    let url: URL
    let pixelWidth: Int
    let pixelHeight: Int
    let size: CGSize
    let rowIndices: [Int]
}

/// File URLs, not retained full-resolution bitmaps. Share/Photos own this lease
/// for the entire operation, even when the preview is replaced or dismissed.
nonisolated final class CompetitionShareDocument: @unchecked Sendable, Identifiable {
    let id = UUID()
    let directory: URL
    let pages: [CompetitionExportPage]
    let previewTiles: [CompetitionExportPage]
    init(directory: URL, pages: [CompetitionExportPage], previewTiles: [CompetitionExportPage] = []) {
        self.directory = directory; self.pages = pages; self.previewTiles = previewTiles
    }
    deinit {
        let directory = directory
        DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: directory) }
    }
}

nonisolated struct CompetitionExportSource: @unchecked Sendable {
    let request: CompetitionShareRequest
    let artwork: UIImage?
    let badges: [String: UIImage]
    let headers: [String]
    let metricLabel: String
    let metricValue: String
    let metricBadge: String?
    var reportTitle = "Competition Report"
    var highlightDark = false
    var showsHighlightAttempts = false
}

nonisolated extension CompetitionShareDrawCommand {
    var rect: CGRect {
        switch self { case .text(_, let rect, _, _, _, _), .image(_, let rect), .fill(let rect, _): rect }
    }
    func translated(y: CGFloat) -> Self {
        let shifted = rect.offsetBy(dx: 0, dy: y)
        switch self {
        case let .text(value, _, size, weight, color, right): return .text(value, shifted, size, weight, color, right)
        case let .image(image, _): return .image(image, shifted)
        case let .fill(_, color): return .fill(shifted, color)
        }
    }
    var canSplit: Bool { if case .fill = self { return true }; return false }
}

/// One compact result, independent of the full report's tabular layout.
nonisolated enum CompetitionHighlightLayout {
    static func plan(_ source: CompetitionExportSource) throws -> PreparedCompetitionShare {
        guard source.request.mode == .highlight, let row = source.request.rows.first else {
            throw ContentImageActionError.unavailable
        }
        let width: CGFloat = 620, inner: CGFloat = 36, usable: CGFloat = 548
        let dark = source.highlightDark
        let ink = dark ? UIColor(white: 0.95, alpha: 1) : UIColor(red: 0.09, green: 0.14, blue: 0.21, alpha: 1)
        let secondary = UIColor(white: dark ? 0.73 : 0.36, alpha: 1)
        let canvas = dark ? UIColor(red: 0.06, green: 0.08, blue: 0.11, alpha: 1) : UIColor(white: 0.98, alpha: 1)
        let accent = dark ? UIColor(red: 0.50, green: 0.74, blue: 0.99, alpha: 1)
            : UIColor(red: 0.12, green: 0.31, blue: 0.58, alpha: 1)
        var commands: [CompetitionShareDrawCommand] = []
        var y: CGFloat = 30
        func text(_ value: String, size: CGFloat, weight: UIFont.Weight = .regular,
                  color: UIColor? = nil, tag: String? = nil) {
            let badge = tag.flatMap { source.badges[$0] }
            let badgeScale: CGFloat = 2
            let available = usable - (badge.map { $0.size.width * badgeScale + 12 } ?? 0)
            let original = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            let measured = (value as NSString).size(withAttributes: [.font: original]).width
            let fittedSize = badge != nil && measured > available ? max(38, floor(size * available / measured)) : size
            let font = fittedSize == size ? original : UIFont.monospacedDigitSystemFont(ofSize: fittedSize, weight: weight)
            let pitch = ceil(font.lineHeight) + 2
            let string = value as NSString
            let typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(string: value, attributes: [.font: font]))
            var start = 0
            while start < string.length {
                let count = min(string.length - start, max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(available))))
                let line = string.substring(with: NSRange(location: start, length: count))
                commands.append(.text(line, CGRect(x: inner, y: y, width: available, height: pitch), fittedSize, weight,
                                      color ?? ink, false))
                if start + count == string.length, let badge {
                    let advance = ceil((line as NSString).size(withAttributes: [.font: font]).width)
                    commands.append(.image(badge, CGRect(x: inner + min(advance, available) + 12,
                        y: y + max(1, font.ascender - font.capHeight),
                        width: badge.size.width * badgeScale, height: badge.size.height * badgeScale)))
                }
                y += pitch
                start += count
            }
        }

        text(row.eventName, size: 27, weight: .semibold)
        y += 5
        text(source.metricLabel, size: 18, weight: .semibold, color: accent)
        y += 2
        text(source.metricValue, size: 72, weight: .bold, tag: source.metricBadge)
        y += 9
        let rank = row.rank == "-" ? "" : "  \u{00B7}  #\(row.rank)"
        text(row.round + rank, size: 17, color: secondary)
        y += 16
        commands.append(.fill(CGRect(x: inner, y: y, width: usable, height: 1), accent.withAlphaComponent(0.32)))
        y += 16
        text(source.request.name, size: 24, weight: .semibold)
        if let id = source.request.identity { text(id, size: 14, color: secondary) }
        if let competition = source.request.context.name, !competition.isEmpty {
            y += 8
            text(competition, size: 17, weight: .medium)
        }
        if let location = source.request.context.details, !location.isEmpty {
            text(location, size: 15, color: secondary)
        }
        if source.showsHighlightAttempts, !row.attempts.isEmpty {
            y += 17
            text(source.headers[4], size: 14, weight: .semibold, color: accent)
            y += 4
            text(row.attempts.joined(separator: "  \u{00B7}  "), size: 17, weight: .medium, color: secondary)
        }
        let size = CGSize(width: width, height: ceil(y + 28))
        guard size.height.isFinite, size.height <= 3_500 else { throw ContentImageActionError.unavailable }
        commands.insert(.fill(CGRect(origin: .zero, size: size), canvas), at: 0)
        return PreparedCompetitionShare(size: size, commands: commands)
    }
}

actor CompetitionDocumentExporter {
    static let shared = CompetitionDocumentExporter()
    #if DEBUG
    private(set) var maximumReportStripBitmapBytes = 0
    private(set) var renderedOnMain = false
    private var pageWritten: (@Sendable (URL) -> Void)?
    func debugObserveWrittenPage(_ action: (@Sendable (URL) -> Void)?) { pageWritten = action }
    #endif
    func export(_ source: CompetitionExportSource) throws -> CompetitionShareDocument {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CubeFlow-Report-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: directory) } }
        if source.request.mode == .report {
            let document = try exportReport(source, directory: directory)
            succeeded = true
            return document
        }
        try Task.checkCancellation()
        let plan = try CompetitionHighlightLayout.plan(source)
        let url = directory.appendingPathComponent("CubeFlow-Highlight.png")
        let page = try autoreleasepool {
            guard let image = plan.draw(), let cg = image.cgImage,
                  let bytes = image.pngData() else { throw ContentImageActionError.unavailable }
            try Task.checkCancellation()
            try bytes.write(to: url, options: .atomic)
            #if DEBUG
            renderedOnMain = renderedOnMain || Thread.isMainThread
            #endif
            return CompetitionExportPage(id: 0, url: url, pixelWidth: cg.width, pixelHeight: cg.height,
                size: image.size, rowIndices: [0])
        }
        #if DEBUG
        pageWritten?(directory)
        #endif
        try Task.checkCancellation()
        succeeded = true
        return CompetitionShareDocument(directory: directory, pages: [page])
    }

    private func exportReport(_ source: CompetitionExportSource, directory: URL) throws -> CompetitionShareDocument {
        try Task.checkCancellation()
        let plan = try CompetitionReportLayout.plan(source)
        let dimensions = try CompetitionReportImageLimits.dimensions(plan.size)
        let (width, height, scale) = dimensions
        let url = directory.appendingPathComponent("CubeFlow-Competition-Report.png")
        let encoder = try CompetitionPNGStream(url: url, width: width, height: height)
        let ordered = plan.commands.indices.sorted { plan.commands[$0].rect.minY < plan.commands[$1].rect.minY }
        var next = 0, active: [Int] = [], tiles: [CompetitionExportPage] = []
        let rowBytes = width * 4
        for origin in stride(from: 0, to: height, by: CompetitionReportImageLimits.stripHeight) {
            try Task.checkCancellation()
            let rows = min(CompetitionReportImageLimits.stripHeight, height - origin)
            let top = CGFloat(origin) / scale, bottom = CGFloat(origin + rows) / scale
            active.removeAll { plan.commands[$0].rect.maxY <= top }
            while next < ordered.count, plan.commands[ordered[next]].rect.minY < bottom {
                let index = ordered[next]
                if plan.commands[index].rect.maxY > top { active.append(index) }
                next += 1
            }
            try autoreleasepool {
                guard let bitmap = CGContext(data: nil, width: width, height: rows, bitsPerComponent: 8,
                    bytesPerRow: rowBytes, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                    let pixels = bitmap.data else { throw ContentImageActionError.unavailable }
                bitmap.setFillColor(UIColor.white.cgColor)
                bitmap.fill(CGRect(x: 0, y: 0, width: width, height: rows))
                bitmap.translateBy(x: 0, y: CGFloat(rows))
                bitmap.scaleBy(x: scale, y: -scale)
                bitmap.translateBy(x: 0, y: -top)
                UIGraphicsPushContext(bitmap)
                PreparedCompetitionShare.paint(active.sorted().map { plan.commands[$0] }, in: bitmap)
                UIGraphicsPopContext()

                let stride = rowBytes + 1
                var lines = Data(count: stride * rows)
                lines.withUnsafeMutableBytes { bytes in
                    guard let destination = bytes.baseAddress else { return }
                    for row in 0..<rows {
                        memcpy(destination + row * stride + 1, pixels + row * rowBytes, rowBytes)
                    }
                }
                try encoder.append(&lines)
                #if DEBUG
                maximumReportStripBitmapBytes = max(maximumReportStripBitmapBytes, rowBytes * rows)
                renderedOnMain = renderedOnMain || Thread.isMainThread
                #endif
                // Preview tiles are not share items. They keep very tall images
                // readable without decoding the full PNG or shrinking to a tiny thumbnail.
                if height > 4096 {
                    guard let image = bitmap.makeImage(), let data = UIImage(cgImage: image).pngData() else {
                        throw ContentImageActionError.unavailable
                    }
                    let preview = directory.appendingPathComponent("preview-\(tiles.count).png")
                    try data.write(to: preview)
                    tiles.append(.init(id: tiles.count, url: preview, pixelWidth: width, pixelHeight: rows,
                        size: CGSize(width: CGFloat(width) / scale, height: CGFloat(rows) / scale), rowIndices: []))
                }
            }
            #if DEBUG
            pageWritten?(directory)
            #endif
        }
        try encoder.finish()
        try Task.checkCancellation()
        let image = CompetitionExportPage(id: 0, url: url, pixelWidth: width, pixelHeight: height,
            size: CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale), rowIndices: Array(source.request.rows.indices))
        return CompetitionShareDocument(directory: directory, pages: [image], previewTiles: tiles)
    }
}

actor CompetitionPageThumbnailLoader {
    static let shared = CompetitionPageThumbnailLoader()
    func thumbnail(_ url: URL) -> UIImage? {
        autoreleasepool {
            guard !Task.isCancelled, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0,
                    [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2048,
                     kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
            return UIImage(cgImage: image)
        }
    }

    func banner(_ url: URL) async -> UIImage? {
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 12)
        guard let (file, response) = try? await URLSession.shared.download(for: request) else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        guard !Task.isCancelled, let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16 * 1024 * 1024,
              let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0,
                [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1680,
                 kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
#endif

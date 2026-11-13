#if os(iOS)
import UIKit
import CoreText
import zlib

/// A readability and interoperability policy, not a claim that every Photos
/// library or share extension accepts the PNG format's theoretical dimensions.
nonisolated enum CompetitionReportImageLimits {
    static let maximumHeight = 65_535
    static let maximumPixels = 48_000_000
    static let stripHeight = 384

    static func dimensions(_ size: CGSize) throws -> (width: Int, height: Int, scale: CGFloat) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              size.height <= CGFloat(maximumHeight), size.width * size.height <= CGFloat(maximumPixels)
        else { throw CompetitionReportImageError.tooLong }
        // Quantize down so rounding the final dimensions cannot add a row over the cap.
        let ideal = min(2, CGFloat(maximumHeight) / size.height,
                        sqrt(CGFloat(maximumPixels - 100_000) / (size.width * size.height)))
        let scale = max(1, floor(ideal * 64) / 64)
        let width = Int(ceil(size.width * scale)), height = Int(ceil(size.height * scale))
        guard height <= maximumHeight, width * height <= maximumPixels else { throw CompetitionReportImageError.tooLong }
        return (width, height, scale)
    }
}

nonisolated enum CompetitionReportImageError: LocalizedError {
    case tooLong
    var errorDescription: String? {
        currentAppLocalizedString("share.report_too_long")
    }
}

nonisolated enum CompetitionReportLayout {
    static let width: CGFloat = 840
    static func plan(_ source: CompetitionExportSource) throws -> PreparedCompetitionShare {
        guard !source.request.rows.isEmpty else { throw ContentImageActionError.unavailable }
        let inner: CGFloat = 44, usable: CGFloat = 752
        let ink = UIColor(red: 0.08, green: 0.13, blue: 0.20, alpha: 1)
        let secondary = UIColor(red: 0.29, green: 0.34, blue: 0.40, alpha: 1)
        let sectionRule = UIColor(red: 0.77, green: 0.83, blue: 0.88, alpha: 1)
        let rule = UIColor(red: 0.86, green: 0.89, blue: 0.92, alpha: 1)
        var commands: [CompetitionShareDrawCommand] = []
        var fonts: [FontKey: UIFont] = [:]
        let rowPadding: CGFloat = 8
        let lineLeading: CGFloat = 3
        func font(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let key = FontKey(size: size, weight: weight.rawValue)
            if let cached = fonts[key] { return cached }
            let value = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            fonts[key] = value
            return value
        }
        @discardableResult func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat,
                  size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor? = nil,
                  badge: UIImage? = nil) -> CGFloat {
            let face = font(size, weight)
            let pitch = ceil(face.lineHeight) + lineLeading
            let attributed = NSAttributedString(string: value, attributes: [.font: face])
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            let source = value as NSString
            let available = max(16, width - (badge.map { $0.size.width + 8 } ?? 0))
            var start = 0, top = y
            while start < source.length {
                let count = min(source.length - start, max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(available))))
                let range = NSRange(location: start, length: count)
                let line = source.substring(with: range)
                commands.append(.text(line, CGRect(x: x, y: top, width: available, height: pitch), size, weight, color ?? ink, false))
                if start + count == source.length, let badge {
                    let measured = ceil((line as NSString).size(withAttributes: [.font: face]).width)
                    commands.append(.image(badge, CGRect(x: x + min(measured, available) + 5,
                        y: top + 1, width: badge.size.width, height: badge.size.height)))
                }
                start += count
                top += pitch
            }
            return top - y
        }
        func sectionBoundary(at y: CGFloat) {
            commands.append(.fill(CGRect(x: inner, y: y, width: usable, height: 1), sectionRule))
        }
        func measured(_ value: String, size: CGFloat, weight: UIFont.Weight = .regular) -> CGFloat {
            ceil((value as NSString).size(withAttributes: [.font: font(size, weight)]).width) + 2
        }
        var y: CGFloat = 24
        if let artwork = source.artwork, artwork.size.width > 0, artwork.size.height > 0 {
            let logo = source.request.context.artwork?.kind == .logo
            let scale = min((logo ? 112 : usable) / artwork.size.width, (logo ? 88 : 220) / artwork.size.height)
            commands.append(.image(artwork, CGRect(x: inner, y: y + 16, width: artwork.size.width * scale,
                height: artwork.size.height * scale)))
            y += artwork.size.height * scale + 24
        } else {
            y += 16
        }
        y += text(source.reportTitle, x: inner, y: y, width: usable, size: 14, weight: .semibold, color: secondary) + 4
        if let name = source.request.context.name, !name.isEmpty {
            y += text(name, x: inner, y: y, width: usable, size: 34, weight: .bold) + 6
        }
        if let details = source.request.context.details, !details.isEmpty {
            y += text(details, x: inner, y: y, width: usable, size: 15, color: secondary) + 4
        }
        y += 8
        y += text(source.request.name, x: inner, y: y, width: usable, size: 23, weight: .semibold)
        if let identity = source.request.identity {
            y += text(identity, x: inner, y: y + 2, width: usable, size: 15, color: secondary) + 2
        }
        y += 16

        var groups: [String: [CompetitionShareRow]] = [:], order: [String] = []
        for row in source.request.rows {
            if groups[row.eventID] == nil { order.append(row.eventID) }
            groups[row.eventID, default: []].append(row)
        }
        for event in order {
            try Task.checkCancellation()
            guard let rows = groups[event], let first = rows.first else { continue }
            sectionBoundary(at: y)
            y += 10 + text(first.eventName, x: inner, y: y + 10, width: usable, size: 23, weight: .semibold) - lineLeading
            for (rowIndex, row) in rows.enumerated() {
                try Task.checkCancellation()
                let top = y + rowPadding
                let rank = row.rank == "-" ? row.round : "#\(row.rank)  \(row.round)"
                var attempts = row.attempts.joined(separator: "\u{2003}")
                let statistics = [(row.isMean ? source.headers[2] : source.headers[1], row.average, row.averageBadge),
                                  (source.headers[3], row.single, row.singleBadge)].compactMap { label, value, tag in
                    value.map { (label, $0, tag.flatMap { source.badges[$0] }) }
                }
                let rankWidth = max(72, measured(rank, size: 18, weight: .semibold))
                let widths = statistics.map { label, value, badge in
                    max(measured(label, size: 13, weight: .medium),
                        measured(value, size: 21, weight: .semibold) + (badge.map { $0.size.width + 8 } ?? 0))
                }
                var gap: CGFloat = 22
                let summaryWidth = rankWidth + widths.reduce(0, +)
                func measuredAttempts() -> CGFloat {
                    max(measured(source.headers[4], size: 13, weight: .medium), measured(attempts, size: 21))
                }
                var attemptWidth = measuredAttempts()
                if summaryWidth + CGFloat(widths.count + 1) * gap + attemptWidth > usable {
                    gap = 12
                    attempts = row.attempts.joined(separator: "\u{2002}")
                    attemptWidth = measuredAttempts()
                }
                let inline = !attempts.isEmpty && summaryWidth + CGFloat(widths.count + 1) * gap + attemptWidth <= usable
                var end = top + text(rank, x: inner, y: top + 10, width: inline ? rankWidth : 220, size: 18, weight: .semibold) + 10
                var x = inner + (inline ? rankWidth + gap : 240)
                for (index, entry) in statistics.enumerated() {
                    let (label, value, badge) = entry
                    let width = inline ? widths[index] : 240
                    let labelHeight = text(label, x: x, y: top, width: width, size: 13, weight: .medium, color: secondary)
                    let valueHeight = text(value, x: x, y: top + labelHeight, width: width, size: 21, weight: .semibold, badge: badge)
                    end = max(end, top + labelHeight + valueHeight)
                    x += width + (inline ? gap : 14)
                }
                if inline {
                    let labelHeight = text(source.headers[4], x: x, y: top, width: attemptWidth, size: 13, weight: .medium, color: secondary)
                    let valueHeight = text(attempts, x: x, y: top + labelHeight, width: attemptWidth, size: 21)
                    end = max(end, top + labelHeight + valueHeight)
                } else if !row.attempts.isEmpty {
                    let attemptTop = end + 5
                    let labelWidth: CGFloat = 112
                    let label = text(source.headers[4], x: inner, y: attemptTop + 4, width: labelWidth, size: 13, color: secondary)
                    let values = text(attempts, x: inner + labelWidth,
                        y: attemptTop, width: usable - labelWidth, size: 21)
                    end = attemptTop + max(label + 4, values)
                }
                y = end - lineLeading + rowPadding
                guard y * width <= CGFloat(CompetitionReportImageLimits.maximumPixels),
                      y <= CGFloat(CompetitionReportImageLimits.maximumHeight) else { throw CompetitionReportImageError.tooLong }
                if rowIndex < rows.count - 1 {
                    commands.append(.fill(CGRect(x: inner, y: y, width: usable, height: 0.5), rule))
                    y += 0.5
                }
            }
        }
        return PreparedCompetitionShare(size: CGSize(width: width, height: ceil(y + 6)), commands: commands)
    }
    private struct FontKey: Hashable { let size: CGFloat; let weight: CGFloat }
}

/// Standard PNG: one zlib stream split across IDAT chunks. Only one strip,
/// scanline staging buffer and a small compression output buffer are resident.
nonisolated final class CompetitionPNGStream {
    private let file: FileHandle
    private let stream: UnsafeMutablePointer<z_stream>
    private var output = Data(count: 64 * 1024)

    init(url: URL, width: Int, height: Int) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw ContentImageActionError.unavailable }
        file = try FileHandle(forWritingTo: url)
        let pointer = UnsafeMutablePointer<z_stream>.allocate(capacity: 1)
        pointer.initialize(to: z_stream())
        guard deflateInit_(pointer, Z_BEST_SPEED, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            pointer.deinitialize(count: 1); pointer.deallocate()
            throw ContentImageActionError.unavailable
        }
        stream = pointer
        try file.write(contentsOf: Data([137, 80, 78, 71, 13, 10, 26, 10]))
        var header = Self.bytes(UInt32(width))
        header.append(Self.bytes(UInt32(height)))
        header.append(contentsOf: [8, 6, 0, 0, 0]) // RGBA, noninterlaced
        try chunk("IHDR", header)
    }

    deinit {
        deflateEnd(stream)
        stream.deinitialize(count: 1); stream.deallocate()
        try? file.close()
    }

    func append(_ scanlines: inout Data) throws {
        try scanlines.withUnsafeMutableBytes { input in
            stream.pointee.next_in = input.bindMemory(to: UInt8.self).baseAddress
            stream.pointee.avail_in = UInt32(input.count)
            while stream.pointee.avail_in != 0 { _ = try compress(Z_NO_FLUSH) }
            stream.pointee.next_in = nil
        }
    }

    func finish() throws {
        while try compress(Z_FINISH) != Z_STREAM_END { }
        try chunk("IEND", Data())
        try file.close()
    }

    private func compress(_ mode: Int32) throws -> Int32 {
        try Task.checkCancellation()
        let capacity = output.count
        let result = output.withUnsafeMutableBytes { bytes in
            stream.pointee.next_out = bytes.bindMemory(to: UInt8.self).baseAddress
            stream.pointee.avail_out = UInt32(capacity)
            return deflate(stream, mode)
        }
        guard result == Z_OK || result == Z_STREAM_END else { throw ContentImageActionError.unavailable }
        let count = capacity - Int(stream.pointee.avail_out)
        if count > 0 { try chunk("IDAT", output.prefix(count)) }
        return result
    }

    private func chunk(_ type: String, _ data: Data) throws {
        let code = Data(type.utf8)
        let seed = code.withUnsafeBytes { crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, UInt32($0.count)) }
        let checksum = data.withUnsafeBytes { crc32(seed, $0.bindMemory(to: UInt8.self).baseAddress, UInt32($0.count)) }
        try file.write(contentsOf: Self.bytes(UInt32(data.count)))
        try file.write(contentsOf: code)
        try file.write(contentsOf: data)
        try file.write(contentsOf: Self.bytes(UInt32(truncatingIfNeeded: checksum)))
    }

    private static func bytes(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}
#endif

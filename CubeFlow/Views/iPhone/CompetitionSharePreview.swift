#if os(iOS)
import SwiftUI
import UIKit

private struct CompetitionSharingKey: EnvironmentKey { static let defaultValue: CompetitionSharingContext? = nil }
extension EnvironmentValues {
    var competitionSharing: CompetitionSharingContext? {
        get { self[CompetitionSharingKey.self] }
        set { self[CompetitionSharingKey.self] = newValue }
    }
}

struct CompetitionSharePreview: View {
    let request: CompetitionShareRequest
    let language: String
    @State private var document: CompetitionShareDocument?
    @State private var artwork: UIImage?
    @State private var attemptedArtwork = false
    @State private var metric: CompetitionHighlightMetric
    @State private var isExporting = true
    @State private var shared: CompetitionShareDocument?
    @State private var isSaving = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(request: CompetitionShareRequest, language: String) {
        self.request = request; self.language = language
        _metric = State(initialValue: request.rows.first.flatMap { CompetitionHighlightMetric.choices(for: $0).first } ?? .single)
    }

    var body: some View {
        CompatibleNavigationContainer {
            ScrollView {
                LazyVStack(spacing: 18) {
                    if request.mode == .highlight, let row = request.rows.first {
                        Picker("share.result", selection: Binding(get: { metric }, set: { metric = $0; isExporting = true })) {
                            ForEach(CompetitionHighlightMetric.choices(for: row), id: \.self) { choice in
                                Text(choice.label(row, language: language)).tag(choice)
                            }
                        }.pickerStyle(.menu)
                    }
                    if let document {
                        LazyVStack(spacing: 0) {
                            ForEach(document.previewTiles.isEmpty ? document.pages : document.previewTiles) { page in
                                CompetitionExportPagePreview(page: page)
                            }
                        }
                    }
                    else if isExporting { ProgressView().frame(minHeight: 200) }
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    HStack(spacing: 12) {
                        Button("share.save_image") {
                            guard let document, !isSaving else { return }
                            isSaving = true
                            Task {
                                defer { isSaving = false }
                                do { try await ContentImageActions.save(files: document.pages.map(\.url)); message = appLocalizedString("share.saved", languageCode: language) }
                                catch { message = error.localizedDescription }
                                withExtendedLifetime(document) {}
                            }
                        }
                        Button { if let document { shared = document } } label: {
                            Label("share.share", systemImage: "square.and.arrow.up")
                        }
                    }.compatibleProminentButtonFromIOS16(tint: .blue).disabled(document == nil || isExporting || isSaving)
                }.padding(20).frame(maxWidth: 820).frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(Text(LocalizedStringKey(request.mode == .report ? "share.report" : "share.highlight"))).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.done") { dismiss() } } }
        }
        .sheet(item: $shared) { lease in SystemShareSheet(items: lease.pages.map(\.url), retainedResource: lease) }
        .task(id: ExportIdentity(request: request.id, metric: metric, dark: request.mode == .highlight && colorScheme == .dark)) {
            isExporting = true
            let selectedMetric = metric
            if request.mode == .report, !attemptedArtwork, let url = request.context.artwork?.url {
                let loaded = await CompetitionPageThumbnailLoader.shared.banner(url)
                guard !Task.isCancelled, metric == selectedMetric else { return }
                artwork = loaded; attemptedArtwork = true
            }
            do {
                let result = try await CompetitionShareRenderer.exportDocument(request, metric: selectedMetric, artwork: artwork, language: language, highlightDark: colorScheme == .dark)
                guard !Task.isCancelled, metric == selectedMetric else { return }
                document = result; isExporting = false; message = nil
            } catch {
                guard !Task.isCancelled, metric == selectedMetric else { return }
                isExporting = false; message = error.localizedDescription
            }
        }
    }
    private struct ExportIdentity: Hashable { let request: UUID; let metric: CompetitionHighlightMetric; let dark: Bool }
}

private struct CompetitionExportPagePreview: View {
    let page: CompetitionExportPage
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable() }
            else { Color.clear.overlay(ProgressView()) }
        }
        .aspectRatio(page.size.width / page.size.height, contentMode: .fit)
        .accessibilityLabel(Text("share.preview"))
        .task(id: page.url) {
            let loaded = await CompetitionPageThumbnailLoader.shared.thumbnail(page.url)
            if !Task.isCancelled { image = loaded }
        }
        .onDisappear { image = nil }
    }
}

struct CompetitionShareButton: View {
    let request: CompetitionShareRequest
    let language: String
    var compact = false
    var loadFullRequest: (@MainActor () async -> CompetitionShareRequest?)? = nil
    @State private var snapshot: CompetitionShareRequest?
    @State private var requesting = false
    @State private var failed = false
    var body: some View {
        Group {
        if compact {
            CompetitionResultCardCloseButton(label: appLocalizedString(request.mode == .report ? "share.report" : "share.highlight", languageCode: language),
                action: open, systemImage: "square.and.arrow.up")
                .accessibilityIdentifier(request.mode == .report ? "competition-share-report" : "competition-share-highlight")
        } else {
        Button(action: open) {
            Label(LocalizedStringKey(request.mode == .report ? "share.report" : "share.highlight"), systemImage: "square.and.arrow.up")
                .font(.subheadline).frame(minHeight: 44)
        }
        .buttonStyle(.plain).foregroundStyle(Color.accentColor)
        }
        }
        .disabled(requesting)
        .task(id: requesting) {
            guard requesting, let loadFullRequest else { return }
            let loaded = await loadFullRequest()
            guard !Task.isCancelled else { return }
            requesting = false
            if let loaded { snapshot = loaded } else { failed = true }
        }
        .alert(ContentImageActionError.unavailable.localizedDescription, isPresented: $failed) {
            Button("common.done", role: .cancel) {}
        }
        .sheet(item: $snapshot) { CompetitionSharePreview(request: $0, language: language) }
    }
    private func open() {
        if loadFullRequest == nil { snapshot = request }
        else { requesting = true }
    }
}

@MainActor enum CompetitionShareRenderer {
    static func exportDocument(_ request: CompetitionShareRequest, metric: CompetitionHighlightMetric,
                               artwork: UIImage?, language: String, highlightDark: Bool = false) async throws -> CompetitionShareDocument {
        try Task.checkCancellation()
        let row = request.rows.first
        let metricBadge = row.flatMap { metric.badge($0) }
        let tags = request.mode == .highlight ? Set([metricBadge].compactMap { $0 })
            : Set(request.rows.flatMap { [$0.averageBadge, $0.singleBadge].compactMap { $0 } })
        let own = request.mode == .report && CompetitionPersonalIdentity.matches(
            signedInWCAID: WCAAuthManager.shared.profile?.wcaId, competitorWCAID: request.identity)
        var source = CompetitionExportSource(request: request, artwork: artwork,
            badges: badgeImages(tags, compact: true, isOwn: own || request.mode == .highlight,
                pixelScale: request.mode == .highlight ? 4 : 2),
            headers: ["round", "average", "mean", "single", "results"].map { key in
                key == "single" ? appLocalizedString("wca.results_single", languageCode: language) : PublishedCompetitionStrings.text(key, language)
            }, metricLabel: row.map { metric.label($0, language: language) } ?? "",
            metricValue: row.flatMap { metric.value($0) } ?? "-", metricBadge: metricBadge)
        source.reportTitle = appLocalizedString("share.report", languageCode: language)
        source.highlightDark = highlightDark
        source.showsHighlightAttempts = metric == .average
        return try await CompetitionDocumentExporter.shared.export(source)
    }
    static func badgeImages(_ tags: Set<String>, compact: Bool = false, isOwn: Bool = false, pixelScale: CGFloat = 2) -> [String: UIImage] {
        var result: [String: UIImage] = [:]
        for raw in tags {
            guard let tag = CubingLiveRecordIndicators.highestDisplay([raw]), result[tag] == nil else { continue }
            let content = CompetitionWCARecordTagView(tag: tag, variant: compact ? .compact : .standard, isOwnPersonalRecord: isOwn).environment(\.colorScheme, .light)
            let host = UIHostingController(rootView: content)
            let size = host.sizeThatFits(in: CGSize(width: 80, height: 40))
            result[tag] = try? ImageExportRenderUtility.render(content, width: ceil(size.width), isOpaque: false,
                fallbackBackground: .clear, pixelScale: pixelScale)
        }
        return result
    }
    #if DEBUG
    private(set) static var debugPreparationMilliseconds: Double = 0
    static func debugWorkerMetrics() async -> (maximum: Int, main: Bool) { await CompetitionImageRenderQueue.shared.metrics() }
    #endif

    #if DEBUG
    static func export(_ request: CompetitionShareRequest, metric: CompetitionHighlightMetric,
                       artwork: UIImage?, language: String) async -> UIImage? {
        guard !Task.isCancelled, let plan = prepare(request, metric: metric, artwork: artwork, language: language) else { return nil }
        return await CompetitionImageRenderQueue.shared.render(plan)?.image
    }

    // Synchronous entry is retained only for deterministic pixel fixtures and before/after benchmarks.
    static func render(_ request: CompetitionShareRequest, metric: CompetitionHighlightMetric,
                       artwork: UIImage?, language: String) -> UIImage? {
        prepare(request, metric: metric, artwork: artwork, language: language)?.draw()
    }
    private static func prepare(_ request: CompetitionShareRequest, metric: CompetitionHighlightMetric,
                       artwork: UIImage?, language: String) -> PreparedCompetitionShare? {
        #if DEBUG
        let started = ProcessInfo.processInfo.systemUptime
        defer { debugPreparationMilliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1000 }
        #endif
        guard !request.rows.isEmpty, request.rows.count <= 256 else { return nil }
        let width: CGFloat = 840, margin: CGFloat = 28
        let title = request.context.name ?? "CubeFlow"
        let hasLogo = artwork != nil && request.context.artwork?.kind == .logo
        let infoX = margin + (hasLogo ? 126 : 0)
        let titleFont = UIFont.systemFont(ofSize: 25, weight: .semibold)
        let titleHeight = ceil((title as NSString).boundingRect(with: CGSize(width: width - margin - infoX, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: titleFont], context: nil).height)
        let artworkHeight: CGFloat = artwork == nil ? 0 : request.context.artwork?.kind == .logo ? 110 : 220
        let infoHeight = titleHeight + 10 + (request.context.details == nil ? 0 : 26)
        let header = 24 + (hasLogo ? 0 : artworkHeight) + max(hasLogo ? 110 : 0, infoHeight) + 40
            + (request.identity == nil ? 0 : 26) + 12
        let eventIDs = request.rows.reduce(into: [String]()) { if !$0.contains($1.eventID) { $0.append($1.eventID) } }
        let bodyHeight: CGFloat = request.mode == .highlight ? 260 : CGFloat(eventIDs.count * 70 + request.rows.count * 48)
        let size = CGSize(width: width, height: header + bodyHeight + 40)
        guard size.height.isFinite, size.height <= 30_000 else { return nil }
        var commands: [CompetitionShareDrawCommand] = []
        var badgeImages: [String: UIImage] = [:]
        func text(_ value: String, _ rect: CGRect, size: CGFloat = 17, weight: UIFont.Weight = .regular, color: UIColor = .black, right: Bool = false) {
            commands.append(.text(value, rect, size, weight, color, right))
        }
        func badge(_ tag: String?, x: CGFloat, y: CGFloat) {
            guard let tag = tag.flatMap(PublishedCompetitionResult.recordBadge) else { return }
            if badgeImages[tag] == nil {
                let content = CompetitionWCARecordTagView(tag: tag, variant: .standard).environment(\.colorScheme, .light)
                let host = UIHostingController(rootView: content)
                let size = host.sizeThatFits(in: CGSize(width: 80, height: 40)); host.view.bounds = CGRect(origin: .zero, size: size)
                badgeImages[tag] = try? ImageExportRenderUtility.render(content, width: ceil(size.width), isOpaque: false, fallbackBackground: .clear)
            }
            if let image = badgeImages[tag] { commands.append(.image(image, CGRect(origin: CGPoint(x: x, y: y), size: image.size))) }
        }
        do {
            commands.append(.fill(CGRect(origin: .zero, size: size), .white))
            commands.append(.fill(CGRect(x: 0, y: 0, width: width, height: 5), UIColor.systemBlue.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))))
            var y: CGFloat = 24
            if let artwork {
                let bounds = CGRect(x: margin, y: y, width: hasLogo ? 110 : width - 2 * margin, height: artworkHeight - 12)
                let scale = min(bounds.width / artwork.size.width, bounds.height / artwork.size.height)
                commands.append(.image(artwork, CGRect(x: bounds.midX - artwork.size.width * scale / 2, y: bounds.midY - artwork.size.height * scale / 2,
                    width: artwork.size.width * scale, height: artwork.size.height * scale)))
                if !hasLogo { y += artworkHeight }
            }
            text(title, CGRect(x: infoX, y: y, width: width - margin - infoX, height: titleHeight + 8), size: 25, weight: .semibold)
            if let details = request.context.details { text(details, CGRect(x: infoX, y: y + titleHeight + 10, width: width - margin - infoX, height: 24), size: 14, color: .darkGray) }
            y += max(hasLogo ? 110 : 0, infoHeight)
            text(request.name, CGRect(x: margin, y: y, width: width - 2 * margin, height: 38), size: 27, weight: .bold); y += 40
            if let identity = request.identity { text(identity, CGRect(x: margin, y: y, width: width - 2 * margin, height: 24), size: 14, color: .darkGray); y += 26 }
            y = max(y + 12, header)
            if request.mode == .highlight, let row = request.rows.first {
                text(row.eventName + " · " + row.round, CGRect(x: margin, y: y, width: width - 2 * margin, height: 44), size: 23, weight: .semibold)
                text(metric.label(row, language: language), CGRect(x: margin, y: y + 54, width: 600, height: 28), size: 18, color: .darkGray)
                text(metric.value(row) ?? "-", CGRect(x: margin, y: y + 90, width: 670, height: 100), size: 72, weight: .semibold)
                badge(metric.badge(row), x: width - margin - 54, y: y + 92)
                text("#" + row.rank, CGRect(x: margin, y: y + 208, width: 300, height: 28), size: 20, weight: .medium)
            } else {
                for event in eventIDs {
                    let rows = request.rows.filter { $0.eventID == event }
                    text(rows.first?.eventName ?? event, CGRect(x: margin, y: y, width: width - 2 * margin, height: 30), size: 21, weight: .semibold); y += 34
                    commands.append(.fill(CGRect(x: margin, y: y, width: width - 2 * margin, height: 30), UIColor(white: 0.95, alpha: 1)))
                    for (label, x, w) in [("#", margin, 36.0), (PublishedCompetitionStrings.text("round", language), 70.0, 135.0),
                        (PublishedCompetitionStrings.text(rows.first?.isMean == true ? "mean" : "average", language), 210.0, 110.0),
                        (appLocalizedString("wca.results_single", languageCode: language), 340.0, 110.0),
                        (PublishedCompetitionStrings.text("results", language), 470.0, 330.0)] {
                        text(label, CGRect(x: x, y: y + 6, width: w, height: 24), size: 13, weight: .semibold, color: .darkGray)
                    }
                    y += 30
                    for row in rows {
                        text(row.rank, CGRect(x: margin, y: y + 14, width: 36, height: 28), size: 16)
                        text(row.round, CGRect(x: 70, y: y + 8, width: 130, height: 40), size: 15)
                        text(row.average ?? "-", CGRect(x: 210, y: y + 14, width: 108, height: 28), size: 18, weight: .semibold)
                        badge(row.averageBadge, x: 296, y: y + 1)
                        text(row.single ?? "-", CGRect(x: 340, y: y + 14, width: 108, height: 28), size: 18, weight: .semibold)
                        badge(row.singleBadge, x: 426, y: y + 1)
                        text(row.attempts.joined(separator: "  "), CGRect(x: 470, y: y + 12, width: 340, height: 36), size: 13)
                        commands.append(.fill(CGRect(x: margin, y: y + 47, width: width - 2 * margin, height: 0.5), UIColor(white: 0.88, alpha: 1))); y += 48
                    }
                    y += 6
                }
            }
            text("CubeFlow", CGRect(x: margin, y: size.height - 26, width: width - 2 * margin, height: 22), size: 12, weight: .medium, color: .gray, right: true)
        }
        return PreparedCompetitionShare(size: size, commands: commands)
    }
    #endif
}

// Immutable image/color snapshots only. UIKit views and ImageRenderer remain
// on MainActor; the worker owns its bitmap and Core Graphics context exclusively.
nonisolated enum CompetitionShareDrawCommand: @unchecked Sendable {
    case text(String, CGRect, CGFloat, UIFont.Weight, UIColor, Bool)
    case image(UIImage, CGRect)
    case fill(CGRect, UIColor)
}

nonisolated struct PreparedCompetitionShare: @unchecked Sendable {
    let size: CGSize
    let commands: [CompetitionShareDrawCommand]
    func draw() -> UIImage? {
        guard !Task.isCancelled else { return nil }
        return autoreleasepool {
            let format = UIGraphicsImageRendererFormat()
            // Bound a single report to approximately 48 MB of 8-bit pixels,
            // preserving logical column widths and ordinary reports' 2x scale.
            format.scale = min(2, sqrt(12_000_000 / (size.width * size.height)))
            format.preferredRange = .standard; format.opaque = true
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                Self.paint(commands, in: context.cgContext)
            }
            return Task.isCancelled ? nil : image
        }
    }

    static func paint(_ commands: [CompetitionShareDrawCommand], in context: CGContext) {
        let rightAligned = NSMutableParagraphStyle(); rightAligned.alignment = .right
        let leftAligned = NSMutableParagraphStyle(); leftAligned.alignment = .left
        var fonts: [DrawingFont: UIFont] = [:]
        for command in commands {
            if Task.isCancelled { return }
            switch command {
            case let .text(value, rect, size, weight, color, right):
                let key = DrawingFont(size: size, weight: weight.rawValue)
                let font = fonts[key] ?? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                fonts[key] = font
                (value as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color,
                    .paragraphStyle: right ? rightAligned : leftAligned])
            case let .image(image, rect): image.draw(in: rect)
            case let .fill(rect, color): context.setFillColor(color.cgColor); context.fill(rect)
            }
        }
    }
    private struct DrawingFont: Hashable { let size: CGFloat; let weight: CGFloat }
}

nonisolated private struct CompetitionExportedImage: @unchecked Sendable { let image: UIImage }

private actor CompetitionImageRenderQueue {
    static let shared = CompetitionImageRenderQueue()
    #if DEBUG
    private var inFlight = 0
    private var maximum = 0
    private var renderedOnMain = false
    func metrics() -> (maximum: Int, main: Bool) { (maximum, renderedOnMain) }
    #endif
    func render(_ plan: PreparedCompetitionShare) -> CompetitionExportedImage? {
        guard !Task.isCancelled else { return nil }
        #if DEBUG
        inFlight += 1; maximum = max(maximum, inFlight)
        renderedOnMain = renderedOnMain || Thread.isMainThread
        defer { inFlight -= 1 }
        #endif
        return plan.draw().map { CompetitionExportedImage(image: $0) }
    }
}
#endif

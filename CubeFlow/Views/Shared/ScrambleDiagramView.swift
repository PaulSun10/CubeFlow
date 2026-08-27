#if os(iOS)
import SwiftUI
import WebKit

struct ScrambleDiagramView: View {
    let puzzleKey: String
    let scramble: String
    let isInteractive: Bool
    let exportAppearance: ScrambleExportAppearance

    @AppStorage("scrambleDiagramColorSchemeData") private var colorSchemeData: Data?

    init(
        puzzleKey: String,
        scramble: String,
        isInteractive: Bool = true,
        exportAppearance: ScrambleExportAppearance = .solveDetail(.light)
    ) {
        self.puzzleKey = puzzleKey
        self.scramble = scramble
        self.isInteractive = isInteractive
        self.exportAppearance = exportAppearance
    }

    @ViewBuilder
    var body: some View {
        let colorScheme = ScrambleColorConfiguration.decode(from: colorSchemeData)
            .schemeString(for: puzzleKey)
        let diagram = ScrambleDiagramWebView(
            puzzleKey: puzzleKey,
            scramble: scramble,
            colorScheme: colorScheme
        )
        .background(Color.clear)

        if isInteractive {
            ZStack {
                diagram
                    .allowsHitTesting(false)

                Color.clear
                    .contentShape(Rectangle())
            }
            .modifier(
                ScrambleDiagramActionsModifier(
                    puzzleKey: puzzleKey,
                    scramble: scramble,
                    colorScheme: colorScheme,
                    exportAppearance: exportAppearance
                )
            )
        } else {
            diagram
        }
    }

    static func diagramAspectRatio(for puzzleKey: String) -> CGFloat {
        switch puzzleKey {
        case "clk":
            return 375 / 180
        case "megaminx":
            return 392 / 196
        case "pyraminx":
            return 315 / 253.31243060694828
        case "skewb":
            return 326.26914536239786 / 283.280
        case "squareone":
            return 495 / 283.5
        default:
            return 39 / 29
        }
    }
}

struct ScrambleDiagramSheet: View {
    let title: LocalizedStringKey
    let puzzleKey: String
    let scramble: String
    let exportAppearance: ScrambleExportAppearance

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        navigationContent
    }

    @ViewBuilder
    private var navigationContent: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                content.compatibleSoftScrollEdgeEffect()
            }
        } else {
            NavigationView {
                content
            }
            .navigationViewStyle(.stack)
        }
    }

    private var content: some View {
        ScrambleDiagramViewer(
            puzzleKey: puzzleKey,
            scramble: scramble,
            exportAppearance: exportAppearance
        )
    }

}

enum ScrambleExportKind: Equatable {
    case diagramOnly
    case withScramble
}

struct TimerScrambleExportConfiguration {
    let backgroundAppearance: AppearanceConfiguration
    let backgroundImage: UIImage?
    let textAppearance: AppearanceConfiguration
    let fontDesign: TimerFontDesignOption
    let fontStyle: TimerFontStyleOption
    let fontSize: Double
    let colorScheme: ColorScheme
}

@MainActor
enum TimerScrambleExportLayout {
    static let minimumNotationFontSize: CGFloat = 22
    static let maximumNotationFontSize: CGFloat = 52
    static let maximumNotationLines = 3

    static func notationFontSize(
        for scramble: String,
        configuration: TimerScrambleExportConfiguration,
        availableWidth: CGFloat = 640
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 4
        paragraph.lineBreakMode = .byWordWrapping

        for candidate in stride(
            from: maximumNotationFontSize,
            through: minimumNotationFontSize,
            by: -1
        ) {
            let font = configuration.fontDesign.uiFont(
                size: candidate,
                style: configuration.fontStyle
            )
            let text = NSAttributedString(string: scramble, attributes: [
                .font: font,
                .paragraphStyle: paragraph
            ])
            let measured = text.boundingRect(
                with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            let maximumHeight = ceil(font.lineHeight * CGFloat(maximumNotationLines) + 8)
            if ceil(measured.height) <= maximumHeight {
                return candidate
            }
        }
        return minimumNotationFontSize
    }
}

enum ScrambleExportAppearance {
    case timer(TimerScrambleExportConfiguration)
    case solveDetail(SolveShareBackground)
}

enum SolveShareContentKind: String, CaseIterable, Identifiable {
    case solveCard
    case diagramOnly
    case diagramAndScramble

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solveCard: return "Solve Card"
        case .diagramOnly: return "Diagram Only"
        case .diagramAndScramble: return "Diagram + Scramble"
        }
    }
}

enum SolveShareBackground: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .light: return Color(red: 0.965, green: 0.965, blue: 0.975)
        case .dark: return Color(red: 0.075, green: 0.08, blue: 0.095)
        }
    }

    var primaryTextColor: Color { self == .dark ? .white : .black }
    var isOpaque: Bool { true }
}

private struct ScrambleDiagramActionsModifier: ViewModifier {
    let puzzleKey: String
    let scramble: String
    let colorScheme: String
    let exportAppearance: ScrambleExportAppearance

    @State private var showingViewer = false
    @State private var showingShareChoice = false
    @State private var sharedImage: ScrambleSharedImage?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .onTapGesture { showingViewer = true }
            .contextMenu {
                Button {
                    perform(.diagramOnly) { ContentImageActions.copy($0) }
                } label: {
                    Label("Copy Image", systemImage: "doc.on.doc")
                }

                Button {
                    save(.diagramOnly)
                } label: {
                    Label("Save Image", systemImage: "square.and.arrow.down")
                }

                Button {
                    perform(.withScramble) { ContentImageActions.copy($0) }
                } label: {
                    Label("Copy with Scramble", systemImage: "doc.on.doc.fill")
                }

                Button {
                    save(.withScramble)
                } label: {
                    Label("Save with Scramble", systemImage: "square.and.arrow.down.fill")
                }

                Button {
                    showingShareChoice = true
                } label: {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
            }
            .zoomViewerPresentation(isPresented: $showingViewer) {
                CompatibleNavigationContainer {
                    ScrambleDiagramViewer(
                        puzzleKey: puzzleKey,
                        scramble: scramble,
                        exportAppearance: exportAppearance
                    )
                }
            }
            .confirmationDialog("Share", isPresented: $showingShareChoice) {
                Button("Diagram Only") { share(.diagramOnly) }
                Button("Diagram + Scramble") { share(.withScramble) }
                Button("Cancel", role: .cancel) { }
            }
            .sheet(item: $sharedImage) { item in
                SystemShareSheet(items: [item.image])
            }
            .alert(
                "Unable to Export Diagram",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func save(_ kind: ScrambleExportKind) {
        perform(kind) { image in
            do {
                try await ContentImageActions.save(image)
                ScreenTransientFeedback.showSuccess("Saved to Photos")
            } catch {
                errorMessage = readableMessage(for: error)
            }
        }
    }

    private func share(_ kind: ScrambleExportKind) {
        perform(kind) { image in
            sharedImage = ScrambleSharedImage(image: image)
        }
    }

    private func perform(
        _ kind: ScrambleExportKind,
        operation: @escaping @MainActor (UIImage) async -> Void
    ) {
        Task {
            do {
                let image = try await ScrambleExportRenderer.render(
                    puzzleKey: puzzleKey,
                    scramble: scramble,
                    colorScheme: colorScheme,
                    kind: kind,
                    appearance: exportAppearance
                )
                await operation(image)
            } catch {
                errorMessage = readableMessage(for: error)
            }
        }
    }

    private func readableMessage(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription,
           !localized.isEmpty {
            return localized
        }
        return error.localizedDescription.isEmpty
            ? "The scramble diagram could not be exported."
            : error.localizedDescription
    }
}

private struct ScrambleSharedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ScrambleDiagramViewer: View {
    let puzzleKey: String
    let scramble: String
    let exportAppearance: ScrambleExportAppearance

    @Environment(\.dismiss) private var dismiss
    @AppStorage("scrambleDiagramColorSchemeData") private var colorSchemeData: Data?
    @AppStorage("scrambleTextFontDesign") private var fontDesignRawValue = TimerFontDesignOption.default.rawValue
    @AppStorage("scrambleTextFontWeight") private var fontStyleRawValue = TimerFontWeightOption.medium.rawValue
    @AppStorage("scrambleTextFontSize") private var fontSize = 20.0

    @State private var image: UIImage?
    @State private var sharedImage: ScrambleSharedImage?
    @State private var showingShareChoice = false
    @State private var errorMessage: String?

    private var colorScheme: String {
        ScrambleColorConfiguration.decode(from: colorSchemeData).schemeString(for: puzzleKey)
    }

    private var fontDesign: TimerFontDesignOption {
        TimerFontDesignOption.resolvedAvailableOption(rawValue: fontDesignRawValue)
    }

    private var fontStyle: TimerFontStyleOption {
        fontDesign.resolvedStyle(rawValue: fontStyleRawValue, preferredLegacyWeight: .medium)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    Group {
                        if let image {
                            ZoomableContentImage(image: image)
                        } else if let errorMessage {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.system(size: 28, weight: .semibold))
                                Text("Unable to Render Diagram")
                                    .font(.headline)
                                Text(errorMessage)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.center)
                            }
                            .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 220)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(
                        ScrambleDiagramView.diagramAspectRatio(for: puzzleKey),
                        contentMode: .fit
                    )

                    Text(scramble)
                        .font(fontDesign.font(size: min(max(fontSize, 14), 32), style: fontStyle))
                        .compatibleFontWidth(fontDesign)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .selectableContent()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(minHeight: proxy.size.height, alignment: .center)
            }
        }
        .compatibleSoftScrollEdgeEffect()
        .navigationTitle("Scramble")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingShareChoice = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(image == nil)
                .accessibilityLabel("Share")
            }
        }
        .confirmationDialog("Share", isPresented: $showingShareChoice) {
            Button("Diagram Only") { share(.diagramOnly) }
            Button("Diagram + Scramble") { share(.withScramble) }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(item: $sharedImage) { item in
            SystemShareSheet(items: [item.image])
        }
        .task(id: "\(puzzleKey)|\(scramble)|\(colorScheme)") {
            do {
                image = try await ScrambleExportRenderer.render(
                    puzzleKey: puzzleKey,
                    scramble: scramble,
                    colorScheme: colorScheme,
                    kind: .diagramOnly,
                    appearance: exportAppearance
                )
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func share(_ kind: ScrambleExportKind) {
        Task {
            do {
                let rendered = try await ScrambleExportRenderer.render(
                    puzzleKey: puzzleKey,
                    scramble: scramble,
                    colorScheme: colorScheme,
                    kind: kind,
                    appearance: exportAppearance
                )
                sharedImage = ScrambleSharedImage(image: rendered)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

@MainActor
enum ScrambleExportRenderer {
    static func render(
        puzzleKey: String,
        scramble: String,
        colorScheme: String,
        kind: ScrambleExportKind,
        appearance: ScrambleExportAppearance
    ) async throws -> UIImage {
        let diagram = try await ScrambleDiagramImageRenderer.render(
            puzzleKey: puzzleKey,
            scramble: scramble,
            colorScheme: colorScheme
        )
        switch appearance {
        case .timer(let configuration):
            return try TimerScrambleCompositeRenderer.render(
                diagram: diagram,
                scramble: kind == .withScramble ? scramble : nil,
                configuration: configuration
            )
        case .solveDetail(let background):
            guard kind == .withScramble else {
                return try renderSolveDiagram(diagram, background: background)
            }
            return try ScrambleCompositeImageRenderer.render(
                diagram: diagram,
                scramble: scramble,
                font: .systemFont(ofSize: 22, weight: .medium),
                background: background
            )
        }
    }

    private static func renderSolveDiagram(
        _ diagram: UIImage,
        background: SolveShareBackground
    ) throws -> UIImage {
        let content = SolveDiagramExportView(diagram: diagram, background: background)
            .frame(width: 720)
        return try ImageExportRenderUtility.render(
            content,
            width: 720,
            isOpaque: true,
            fallbackBackground: background.uiColor
        )
    }
}

@MainActor
enum TimerScrambleCompositeRenderer {
    static func render(
        diagram: UIImage,
        scramble: String?,
        configuration: TimerScrambleExportConfiguration
    ) throws -> UIImage {
        let content = TimerScrambleExportView(
            diagram: diagram,
            scramble: scramble,
            configuration: configuration
        )
        .frame(width: 720)
        .environment(\.colorScheme, configuration.colorScheme)
        return try ImageExportRenderUtility.render(
            content,
            width: 720,
            isOpaque: true,
            fallbackBackground: configuration.colorScheme == .dark ? .black : .white
        )
    }
}

private struct TimerScrambleExportView: View {
    let diagram: UIImage
    let scramble: String?
    let configuration: TimerScrambleExportConfiguration

    private let contentWidth: CGFloat = 640
    private let maximumDiagramHeight: CGFloat = 540

    var body: some View {
        VStack(spacing: scramble == nil ? 0 : 28) {
            Image(uiImage: diagram)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(
                    width: fittedDiagramSize.width,
                    height: fittedDiagramSize.height
                )

            if let scramble, !scramble.isEmpty {
                notation(scramble)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: contentWidth)
            }
        }
        .padding(40)
        .frame(width: 720)
        .background { exportBackground }
        .clipped()
    }

    @ViewBuilder
    private func notation(_ scramble: String) -> some View {
        let fontSize = TimerScrambleExportLayout.notationFontSize(
            for: scramble,
            configuration: configuration,
            availableWidth: contentWidth
        )
        let text = Text(scramble)
            .font(
                configuration.fontDesign.font(
                    size: fontSize,
                    style: configuration.fontStyle
                )
            )
            .compatibleFontWidth(configuration.fontDesign)

        switch configuration.textAppearance.style {
        case .system, .photo:
            text.foregroundStyle(.primary)
        case .color:
            text.foregroundStyle(
                configuration.textAppearance.color(for: configuration.colorScheme)
            )
        case .gradient:
            let gradient = configuration.textAppearance.gradient(for: configuration.colorScheme)
            text.foregroundStyle(
                LinearGradient(
                    gradient: Gradient(stops: gradient.resolvedStops),
                    startPoint: gradientStartPoint(angle: gradient.angle),
                    endPoint: gradientEndPoint(angle: gradient.angle)
                )
            )
        }
    }

    @ViewBuilder
    private var exportBackground: some View {
        ZStack {
            configuration.colorScheme == .dark ? Color.black : Color.white

            switch configuration.backgroundAppearance.style {
            case .system:
                Color.clear
            case .color:
                configuration.backgroundAppearance.color(for: configuration.colorScheme)
            case .gradient:
                let gradient = configuration.backgroundAppearance.gradient(for: configuration.colorScheme)
                LinearGradient(
                    gradient: Gradient(stops: gradient.resolvedStops),
                    startPoint: gradientStartPoint(angle: gradient.angle),
                    endPoint: gradientEndPoint(angle: gradient.angle)
                )
            case .photo:
                if let image = configuration.backgroundImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
        }
    }

    private var fittedDiagramSize: CGSize {
        guard diagram.size.width > 0, diagram.size.height > 0 else {
            return CGSize(width: contentWidth, height: maximumDiagramHeight)
        }
        let scale = min(
            contentWidth / diagram.size.width,
            maximumDiagramHeight / diagram.size.height
        )
        return CGSize(width: diagram.size.width * scale, height: diagram.size.height * scale)
    }

    private func gradientStartPoint(angle: Double) -> UnitPoint {
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 - cos(radians) * 0.5, y: 0.5 - sin(radians) * 0.5)
    }

    private func gradientEndPoint(angle: Double) -> UnitPoint {
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 + cos(radians) * 0.5, y: 0.5 + sin(radians) * 0.5)
    }
}

@MainActor
enum SolveShareRenderer {
    static func render(
        sample: SessionSolveSample,
        position: Int?,
        puzzleKey: String?,
        comment: String,
        decimals: Int,
        contentKind: SolveShareContentKind = .solveCard,
        background: SolveShareBackground = .light
    ) async throws -> UIImage {
        let diagram: UIImage?
        if let puzzleKey, !sample.scramble.isEmpty {
            let colorSchemeData = UserDefaults.standard.data(forKey: "scrambleDiagramColorSchemeData")
            let colorScheme = ScrambleColorConfiguration.decode(from: colorSchemeData)
                .schemeString(for: puzzleKey)
            diagram = try await ScrambleDiagramImageRenderer.render(
                puzzleKey: puzzleKey,
                scramble: sample.scramble,
                colorScheme: colorScheme
            )
        } else {
            diagram = nil
        }

        let eventName = PuzzleEvent(rawValue: sample.eventRawValue)
            .map { currentAppLocalizedString($0.localizationKey) }

        switch contentKind {
        case .solveCard:
            let content = SolveShareCardView(
                solveNumber: position,
                time: SolveMetrics.displayTime(for: sample, decimals: decimals),
                penalty: penaltyText(for: sample),
                eventName: eventName,
                comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
                diagram: diagram,
                scramble: sample.scramble,
                background: background
            )
            .frame(width: 720)
            return try ImageExportRenderUtility.render(
                content,
                width: 720,
                isOpaque: background.isOpaque,
                fallbackBackground: background.uiColor
            )

        case .diagramOnly:
            guard let diagram else { throw ContentImageActionError.unavailable }
            let content = SolveDiagramExportView(diagram: diagram, background: background)
                .frame(width: 720)
            return try ImageExportRenderUtility.render(
                content,
                width: 720,
                isOpaque: true,
                fallbackBackground: background.uiColor
            )

        case .diagramAndScramble:
            guard let diagram else { throw ContentImageActionError.unavailable }
            return try ScrambleCompositeImageRenderer.render(
                diagram: diagram,
                scramble: sample.scramble,
                font: .systemFont(ofSize: 22, weight: .medium),
                background: background
            )
        }
    }

    private static func penaltyText(for sample: SessionSolveSample) -> String? {
        switch SolveResult(rawValue: sample.resultRaw) ?? .solved {
        case .solved:
            return nil
        case .plusTwo:
            return "+2 penalty"
        case .dnf:
            return "DNF"
        }
    }
}

private struct SolveShareCardView: View {
    let solveNumber: Int?
    let time: String
    let penalty: String?
    let eventName: String?
    let comment: String
    let diagram: UIImage?
    let scramble: String
    let background: SolveShareBackground

    private var primary: Color { background.primaryTextColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .firstTextBaseline) {
                if let solveNumber {
                    Text("#\(solveNumber)")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(primary.opacity(0.48))
                }

                Spacer(minLength: 18)

                if let eventName, !eventName.isEmpty {
                    Text(eventName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(primary.opacity(0.55))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(time)
                    .font(.system(size: 76, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(primary)

                if let penalty {
                    Text(penalty)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(primary.opacity(0.52))
                }
            }

            if !comment.isEmpty {
                Text(comment)
                    .font(.system(size: 23, weight: .regular))
                    .foregroundStyle(primary.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let diagram {
                Image(uiImage: diagram)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 470)
            }

            if !scramble.isEmpty {
                Text(scramble)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(primary.opacity(0.82))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(48)
        .background(background.color)
    }
}

@MainActor
enum ScrambleCompositeImageRenderer {
    static func render(
        diagram: UIImage,
        scramble: String,
        font: UIFont,
        background: SolveShareBackground
    ) throws -> UIImage {
        let canvasWidth: CGFloat = 720
        let contentWidth: CGFloat = 640
        let maximumDiagramHeight: CGFloat = 540
        let outerPadding: CGFloat = 40
        let contentSpacing: CGFloat = 28

        let diagramSize = aspectFitSize(
            diagram.size,
            inside: CGSize(width: contentWidth, height: maximumDiagramHeight)
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 4
        paragraph.lineBreakMode = .byWordWrapping
        let notationColor: UIColor = background == .dark ? .white : .black
        let notation = NSAttributedString(string: scramble, attributes: [
            .font: font,
            .foregroundColor: notationColor.withAlphaComponent(1),
            .paragraphStyle: paragraph
        ])
        let measuredText = notation.boundingRect(
            with: CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let textHeight = max(ceil(measuredText.height), ceil(font.lineHeight))
        let canvasHeight = outerPadding + diagramSize.height + contentSpacing
            + textHeight + outerPadding
        let canvasSize = CGSize(width: canvasWidth, height: ceil(canvasHeight))

        let format = UIGraphicsImageRendererFormat()
        format.opaque = background.isOpaque
        format.scale = 2
        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
            if background.isOpaque {
                background.uiColor.setFill()
                context.fill(CGRect(origin: .zero, size: canvasSize))
            } else {
                context.cgContext.clear(CGRect(origin: .zero, size: canvasSize))
            }

            let diagramRect = CGRect(
                x: (canvasWidth - diagramSize.width) / 2,
                y: outerPadding,
                width: diagramSize.width,
                height: diagramSize.height
            )
            diagram.draw(in: diagramRect)

            let textRect = CGRect(
                x: outerPadding,
                y: diagramRect.maxY + contentSpacing,
                width: contentWidth,
                height: textHeight
            )
            notation.draw(
                with: textRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }
    }

    private static func aspectFitSize(_ source: CGSize, inside bounds: CGSize) -> CGSize {
        guard source.width > 0, source.height > 0 else { return bounds }
        let scale = min(bounds.width / source.width, bounds.height / source.height)
        return CGSize(width: source.width * scale, height: source.height * scale)
    }
}

private struct SolveDiagramExportView: View {
    let diagram: UIImage
    let background: SolveShareBackground

    var body: some View {
        Image(uiImage: diagram)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(maxWidth: 648, maxHeight: 540)
            .padding(36)
            .background(background.color)
    }
}

@MainActor
private enum ImageExportRenderUtility {
    static func render<Content: View>(
        _ content: Content,
        width: CGFloat,
        isOpaque: Bool,
        fallbackBackground: UIColor
    ) throws -> UIImage {
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = fallbackBackground
        let measured = controller.sizeThatFits(
            in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
        let size = CGSize(width: width, height: max(1, ceil(measured.height)))
        controller.view.bounds = CGRect(origin: .zero, size: size)
        controller.view.layoutIfNeeded()

        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
            renderer.scale = 2
            renderer.isOpaque = isOpaque
            guard let image = renderer.uiImage else { throw ContentImageActionError.unavailable }
            return image
        }

        let format = UIGraphicsImageRendererFormat()
        format.opaque = isOpaque
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}

private extension SolveShareBackground {
    var uiColor: UIColor {
        switch self {
        case .light: return UIColor(red: 0.965, green: 0.965, blue: 0.975, alpha: 1)
        case .dark: return UIColor(red: 0.075, green: 0.08, blue: 0.095, alpha: 1)
        }
    }
}

@MainActor
private final class ScrambleDiagramImageRenderer: NSObject, WKNavigationDelegate {
    private static var activeRenderers: [UUID: ScrambleDiagramImageRenderer] = [:]

    private let id = UUID()
    private let webView: WKWebView
    private var continuation: CheckedContinuation<UIImage, Error>?

    private override init() {
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 720, height: 540), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
    }

    static func render(puzzleKey: String, scramble: String, colorScheme: String) async throws -> UIImage {
        let renderer = ScrambleDiagramImageRenderer()
        activeRenderers[renderer.id] = renderer
        return try await withCheckedThrowingContinuation { continuation in
            renderer.continuation = continuation
            renderer.webView.loadHTMLString(
                ScrambleDiagramWebView.html(
                    puzzleKey: puzzleKey,
                    scramble: scramble,
                    colorScheme: colorScheme
                ),
                baseURL: Bundle.main.resourceURL
            )
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.getElementById('diagram').src") { [weak self] value, error in
            guard let self else { return }
            if let error {
                finish(.failure(error))
                return
            }
            guard let dataURL = value as? String,
                  let comma = dataURL.firstIndex(of: ","),
                  let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
                  let image = UIImage(data: data) else {
                finish(.failure(ContentImageActionError.unavailable))
                return
            }
            finish(.success(image))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<UIImage, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        Self.activeRenderers[id] = nil
        continuation.resume(with: result)
    }
}

private struct ScrambleDiagramWebView: UIViewRepresentable {
    let puzzleKey: String
    let scramble: String
    let colorScheme: String

    final class Coordinator {
        var lastPuzzleKey: String?
        var lastScramble: String?
        var lastColorScheme: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        loadIfNeeded(webView, coordinator: context.coordinator, force: true)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        loadIfNeeded(webView, coordinator: context.coordinator, force: false)
    }

    private func loadIfNeeded(_ webView: WKWebView, coordinator: Coordinator, force: Bool) {
        guard force
            || coordinator.lastPuzzleKey != puzzleKey
            || coordinator.lastScramble != scramble
            || coordinator.lastColorScheme != colorScheme else {
            return
        }
        coordinator.lastPuzzleKey = puzzleKey
        coordinator.lastScramble = scramble
        coordinator.lastColorScheme = colorScheme
        webView.loadHTMLString(Self.html(puzzleKey: puzzleKey, scramble: scramble, colorScheme: colorScheme), baseURL: Bundle.main.resourceURL)
    }

    fileprivate static func html(puzzleKey: String, scramble: String, colorScheme: String) -> String {
        let sourceMap: [String: String] = [
            "main": loadJavaScript(relativePath: "main.js"),
            "mathlib": loadJavaScript(relativePath: "mathlib.js"),
            "cubes/nnn": loadJavaScript(relativePath: "cubes/nnn.js"),
            "cubes/clk": loadJavaScript(relativePath: "cubes/clk.js"),
            "cubes/megaminx": loadJavaScript(relativePath: "cubes/megaminx.js"),
            "cubes/pyraminx": loadJavaScript(relativePath: "cubes/pyraminx.js"),
            "cubes/skewb": loadJavaScript(relativePath: "cubes/skewb.js"),
            "cubes/squareone": loadJavaScript(relativePath: "cubes/squareone.js"),
        ]

        let sourceEntries = sourceMap.map { key, value in
            "\(javaScriptLiteral(key)): \(javaScriptLiteral(value))"
        }
        .sorted()
        .joined(separator: ",\n")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
          <style>
            :root { color-scheme: light dark; }
            html, body {
              margin: 0;
              padding: 0;
              width: 100%;
              height: 100%;
              background: transparent;
              overflow: hidden;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            }
            body {
              display: flex;
              align-items: center;
              justify-content: center;
              min-height: 0;
            }
            #wrap {
              width: 100%;
              height: 100%;
              display: flex;
              align-items: center;
              justify-content: center;
              padding: 0;
              box-sizing: border-box;
            }
            #diagram {
              width: auto;
              height: auto;
              max-width: 100%;
              max-height: 100%;
              object-fit: contain;
              display: none;
            }
            #message {
              color: rgba(60, 60, 67, 0.7);
              font-size: 15px;
              text-align: center;
              padding: 16px;
            }
          </style>
        </head>
        <body>
          <div id="wrap">
            <img id="diagram" alt="Scramble diagram" />
            <div id="message">Rendering scramble…</div>
          </div>
          <script>
            const sourceMap = {
            \(sourceEntries)
            };

            const factories = {};
            const cache = {};

            const canvasShim = {
              createCanvas: function(width, height) {
                const scale = Math.min(Math.max(window.devicePixelRatio || 1, 1), 3);
                const canvas = document.createElement("canvas");
                canvas.width = Math.ceil(width * scale);
                canvas.height = Math.ceil(height * scale);
                canvas.style.width = width + "px";
                canvas.style.height = height + "px";
                const originalGetContext = canvas.getContext.bind(canvas);
                canvas.getContext = function(type, ...args) {
                  const context = originalGetContext(type, ...args);
                  if (type === "2d" && context && !context.__cubeFlowScaled) {
                    context.scale(scale, scale);
                    context.__cubeFlowScaled = true;
                  }
                  return context;
                };
                canvas.toBuffer = () => canvas.toDataURL("image/png");
                return canvas;
              }
            };

            function normalize(parts) {
              const output = [];
              for (const part of parts) {
                if (!part || part === ".") continue;
                if (part === "..") output.pop();
                else output.push(part);
              }
              return output.join("/");
            }

            function stripExtension(path) {
              return path.endsWith(".js") ? path.slice(0, -3) : path;
            }

            function resolve(from, request) {
              if (request === "canvas") return "canvas";
              if (!request.startsWith(".")) return stripExtension(request);
              const base = from.split("/");
              base.pop();
              return stripExtension(normalize(base.concat(request.split("/"))));
            }

            function defineModule(name, source) {
              factories[name] = new Function("require", "module", "exports", source);
            }

            function requireModule(name) {
              if (name === "canvas") return canvasShim;
              if (cache[name]) return cache[name].exports;
              const factory = factories[name];
              if (!factory) throw new Error("Missing module: " + name);
              const module = { exports: {} };
              cache[name] = module;
              const localRequire = (request) => requireModule(resolve(name, request));
              factory(localRequire, module, module.exports);
              return module.exports;
            }

            Object.entries(sourceMap).forEach(([name, source]) => defineModule(name, source));

            function render() {
              const image = document.getElementById("diagram");
              const message = document.getElementById("message");
              try {
                const scrambleImage = requireModule("main");
                const result = scrambleImage.genImage(\(javaScriptLiteral(puzzleKey)), \(javaScriptLiteral(scramble)), \(javaScriptLiteral(colorScheme)));
                const dataURL = typeof result === "string"
                  ? result
                  : (result && typeof result.toDataURL === "function" ? result.toDataURL("image/png") : "");
                if (!dataURL) throw new Error("Empty render result");
                image.src = dataURL;
                image.style.display = "block";
                message.style.display = "none";
              } catch (error) {
                console.error(error);
                message.textContent = "Unable to render scramble: " + String((error && (error.stack || error.message)) || error);
                image.style.display = "none";
              }
            }

            render();
          </script>
        </body>
        </html>
        """
    }

    private static func loadJavaScript(relativePath: String) -> String {
        for candidate in resourceCandidates(relativePath: relativePath) {
            if let url = candidate, let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }
        return ""
    }

    private static func resourceCandidates(relativePath: String) -> [URL?] {
        let relative = relativePath.split(separator: "/").map(String.init)
        let fileName = relative.last
        let base = Bundle.main.resourceURL
        let drawScramble = base?.appendingPathComponent("DrawScramble", isDirectory: true)
        let resourcesDrawScramble = base?.appendingPathComponent("Resources/DrawScramble", isDirectory: true)

        func append(_ root: URL?) -> URL? {
            relative.reduce(root) { partial, component in
                partial?.appendingPathComponent(component, isDirectory: false)
            }
        }

        return [
            append(drawScramble),
            append(resourcesDrawScramble),
            drawScramble.flatMap { root in fileName.map { root.appendingPathComponent($0, isDirectory: false) } },
            resourcesDrawScramble.flatMap { root in fileName.map { root.appendingPathComponent($0, isDirectory: false) } },
            append(base)
        ] + [base.flatMap { root in fileName.map { root.appendingPathComponent($0, isDirectory: false) } }]
    }

    private static func javaScriptLiteral(_ string: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [string])
        let encoded = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(encoded.dropFirst().dropLast())
    }
}
#endif

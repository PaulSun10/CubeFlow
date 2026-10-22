import SwiftUI

struct CompetitionResultCardTitleStyle: ViewModifier {
    static let fontSize: CGFloat = 24
    static let contentInset: CGFloat = 22
    static let closeInset: CGFloat = 38
    func body(content: Content) -> some View {
        content.font(.system(size: Self.fontSize, weight: .bold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, Self.closeInset)
    }
}

nonisolated enum CompetitionRoundBoundaryPaint {
    static func localY(origin: CGFloat, height: CGFloat, scale: CGFloat, bottom: Bool) -> CGFloat {
        // A top boundary is painted on the Canvas's own raster origin. Global
        // layout coordinates can differ from its pixel-rounded surface origin.
        guard bottom else { return 0 }
        let edge = height - 1 / scale
        return ((origin + edge) * scale).rounded() / scale - origin
    }
}

/// Draw the hairline on the complete row surface, retaining its original pixel-sized gap.
struct CompetitionResultRoundRow<Content: View>: View {
    let showsBoundary: Bool
    var boundaryAtBottom = false
    @ViewBuilder let content: () -> Content
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        VStack(spacing: 0) {
            if showsBoundary, !boundaryAtBottom { Color.clear.frame(height: 1 / displayScale) }
            content()
            if showsBoundary, boundaryAtBottom { Color.clear.frame(height: 1 / displayScale) }
        }
        .overlay {
            if showsBoundary {
                GeometryReader { geometry in
                    Canvas { context, size in
                        let origin = geometry.frame(in: .global).minY
                        let y = CompetitionRoundBoundaryPaint.localY(origin: origin, height: size.height,
                            scale: displayScale, bottom: boundaryAtBottom)
                        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1 / displayScale)),
                            with: .color(Color(uiColor: .opaqueSeparator)))
                    }
                    #if DEBUG
                    .modifier(CompetitionSeparatorInstrumentation(origin: geometry.frame(in: .global).minY,
                        scale: displayScale, bottom: boundaryAtBottom))
                    #endif
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

#if DEBUG
@MainActor enum CompetitionResultSeparatorDiagnostics {
    static var measureRows = NSClassFromString("XCTestCase") != nil
        && !ProcessInfo.processInfo.arguments.contains("--competition-render-uninstrumented")
    static var rows: [String: CGRect] = [:]
}
#endif
extension View {
    @ViewBuilder func competitionResultRowProbe(_ id: String) -> some View {
        #if DEBUG
        if CompetitionResultSeparatorDiagnostics.measureRows {
        background {
            GeometryReader { proxy in
                Color.clear.onAppear { CompetitionResultSeparatorDiagnostics.rows[id] = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { CompetitionResultSeparatorDiagnostics.rows[id] = $0 }
            }
        }
        } else { self }
        #else
        self
        #endif
    }
}

/// Both sources embed the original selectors; only their common container is new.
struct CompetitionResultsSelectorGroup<Events: View, Rounds: View>: View {
    @ViewBuilder let events: () -> Events
    @ViewBuilder let rounds: () -> Rounds
    var body: some View {
        VStack(spacing: 2) {
            events()
            Divider().padding(.horizontal, 4).opacity(0.55)
            rounds()
        }
        .padding(.horizontal, 10).padding(.vertical, 2)
        .modifier(CompetitionResultsSurface())
    }
}

struct CompetitionResultsDarkShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        // A near-black shadow disappears against dark surfaces; this faint ambient lift is visible.
        content.shadow(color: scheme == .dark ? .white.opacity(0.065) : .clear, radius: 4, y: 2)
    }
}

struct CompetitionResultsSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.modifier(CompetitionResultListDecoration(enabled: true, darkShadow: true))
    }
}

struct CompetitionResultsNavigation: View {
    let options: [String]
    @Binding var selection: String
    let title: (String) -> String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(options, id: \.self) { option in
                    Button { selection = option } label: {
                        Text(title(option)).font(.subheadline.weight(selection == option ? .semibold : .regular))
                            .foregroundStyle(selection == option ? Color.accentColor : .primary)
                            .padding(.vertical, 8).frame(minHeight: 44)
                            .overlay(alignment: .bottom) {
                                if selection == option { Capsule().fill(Color.accentColor).frame(height: 2) }
                            }
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(selection == option ? .isSelected : [])
                        .accessibilityIdentifier("competition-results-destination-" + option)
                }
            }
        }
    }
}

struct CompetitionResultListDecoration: ViewModifier {
    let enabled: Bool
    let darkShadow: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                .modifier(CompetitionResultsOptionalDarkShadow(enabled: darkShadow))
        } else { content }
    }
}

private struct CompetitionResultsOptionalDarkShadow: ViewModifier {
    let enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.modifier(CompetitionResultsDarkShadow()) } else { content }
    }
}

struct CompetitionChampionshipSymbol: View {
    var body: some View {
        Image(systemName: "trophy.fill").font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.orange)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
    }
}

/// All Results keeps its 36-point rows. Rare long scores scroll instead of clipping badges/text.
enum CompetitionAllResultsLayout {
    static let leading: CGFloat = 4
    static let badgeReserve: CGFloat = 25
    static func scoreWidth(texts: [String], base: CGFloat, emphasized: Bool) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 14, weight: emphasized ? .semibold : .regular)
        return max(base, texts.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }.max() ?? base)
    }
    static func minimumWidth(scoreWidths: [CGFloat]) -> CGFloat {
        46 + 8 + 44 + scoreWidths.reduce(0) { $0 + $1 + leading + badgeReserve }
    }
    static func trailingReserve(nextWidth: CGFloat?, nextInkWidth: CGFloat?) -> CGFloat {
        guard let nextWidth, let nextInkWidth else { return badgeReserve }
        return max(6, badgeReserve - leading - max(0, nextWidth - nextInkWidth))
    }
    static func minimumWidth(scoreWidths: [CGFloat], reserves: [CGFloat]) -> CGFloat {
        46 + 8 + 44 + scoreWidths.reduce(0, +) + reserves.reduce(0, +) + CGFloat(scoreWidths.count) * leading
    }
}

/// One plan for the entire competitor card, including best-only event sections.
struct CompetitionAllResultsColumns {
    let statistics: [CompetitionWCALiveResultStatistic]
    let round: CGFloat
    let widths: [CompetitionWCALiveResultStatistic: CGFloat]
    let reserves: [CompetitionWCALiveResultStatistic: CGFloat]
    init(roundNames: [String], averageTexts: [String], bestTexts: [String], hasAverage: Bool) {
        statistics = hasAverage ? [.average, .best] : [.best]
        round = max(44, roundNames.map {
            ceil(($0 as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 14)]).width)
        }.max() ?? 44)
        let best = CompetitionAllResultsLayout.scoreWidth(texts: bestTexts, base: 62, emphasized: true)
        let average = CompetitionAllResultsLayout.scoreWidth(texts: averageTexts, base: 72, emphasized: true)
        widths = [.average: average, .best: best]
        reserves = [.best: CompetitionAllResultsLayout.badgeReserve,
            .average: CompetitionAllResultsLayout.trailingReserve(nextWidth: best,
                nextInkWidth: CompetitionAllResultsLayout.scoreWidth(texts: bestTexts, base: 0, emphasized: true))]
    }
    var minimumWidth: CGFloat {
        46 + 8 + round + statistics.reduce(0) {
            $0 + (widths[$1] ?? 0) + (reserves[$1] ?? 0) + CompetitionAllResultsLayout.leading
        }
    }
}

nonisolated enum CompetitionAllResultsDisplay {
    static func value(_ statistic: CompetitionWCALiveResultStatistic, result: CompetitionWCALiveCompetitorResult) -> String {
        switch statistic {
        case .average:
            WCAResultFormatter.string(from: result.average, eventID: result.eventID, resultType: "average")
        case .best:
            WCAResultFormatter.string(from: result.best, eventID: result.eventID, resultType: "single")
        }
    }

    static func attempts(_ result: CompetitionWCALiveCompetitorResult) -> [String] {
        guard let last = result.attempts.lastIndex(where: { $0 != 0 }) else { return [] }
        return result.attempts[...last].map {
            WCAResultFormatter.string(from: $0, eventID: result.eventID, resultType: "single")
        }
    }
}

/// Additional columns never participate in the leading summary's width plan.
struct CompetitionAllResultsSolves {
    let widths: [CGFloat]
    let headers: [String]
    private let trailingReserve: CGFloat
    static let horizontalPadding: CGFloat = 6
    init(results: [CompetitionWCALiveCompetitorResult], language: String) {
        let values = results.map(CompetitionAllResultsDisplay.attempts)
        let count = values.map(\.count).max() ?? 0
        let title = PublishedCompetitionStrings.text("results", language)
        headers = (0..<count).map { $0 == 0 ? title : "" }
        widths = (0..<count).map { index in
            let texts = values.compactMap { $0.indices.contains(index) ? $0[index] : nil }
            let valueWidth = CompetitionAllResultsLayout.scoreWidth(texts: texts, base: 0, emphasized: false)
            let headerWidth = index == 0 ? ceil((title as NSString).size(withAttributes:
                [.font: UIFont.systemFont(ofSize: 14, weight: .medium)]).width) : 0
            return max(valueWidth, headerWidth)
        }
        trailingReserve = values.compactMap(\.first).map { Self.originAdjustment(value: $0, header: title) }.max().map { max(0, $0) } ?? 0
    }
    // Change only unused leading space in the first value cell. Later solves
    // move together; the header, inter-cell padding and summary stay fixed.
    func cellWidth(_ index: Int, values: [String]?) -> CGFloat {
        guard index == 0, let first = values?.first, !first.isEmpty else { return widths[index] }
        return widths[index] + Self.originAdjustment(value: first, header: headers[0])
    }
    static func originAdjustment(value: String, header: String) -> CGFloat {
        func metrics(_ text: String, weight: UIFont.Weight) -> (advance: CGFloat, ink: CGFloat) {
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14, weight: weight)]
            return ((text as NSString).size(withAttributes: attributes).width,
                CompetitionEventIconFont.textInkBounds(NSAttributedString(string: text, attributes: attributes)).minX)
        }
        let value = metrics(value, weight: .regular), header = metrics(header, weight: .medium)
        return value.advance - value.ink - header.advance + header.ink
    }
    var width: CGFloat { widths.reduce(0, +) + CGFloat(widths.count) * Self.horizontalPadding * 2 + trailingReserve }
}

struct CompetitionAllResultsSolveCells: View {
    let plan: CompetitionAllResultsSolves
    var values: [String]? = nil
    var traceID: String = ""
    var body: some View {
        HStack(spacing: 0) {
            ForEach(plan.widths.indices, id: \.self) { index in
                Group {
                    if let values {
                        CompetitionResultTableStatisticValue(text: values.indices.contains(index) ? values[index] : "",
                            recordTag: nil, width: plan.cellWidth(index, values: values), emphasized: false)
                    } else {
                        CompetitionResultTableHeaderCell(text: plan.headers[index], width: plan.widths[index], alignment: .trailing)
                    }
                }.padding(.horizontal, CompetitionAllResultsSolves.horizontalPadding)
                    .competitionResultRowProbe("\(traceID)-\(index)")
            }
        }.frame(width: plan.width, alignment: .leading)
    }
}

struct CompetitionAdaptiveResultsTable<Content: View>: View {
    let minimumWidth: CGFloat
    let viewportWidth: CGFloat?
    let additionalWidth: CGFloat
    @ViewBuilder let content: (CGFloat) -> Content
    @State private var availableWidth: CGFloat = 0
    init(minimumWidth: CGFloat, viewportWidth: CGFloat? = nil, additionalWidth: CGFloat = 0,
         @ViewBuilder content: @escaping (CGFloat) -> Content) {
        self.minimumWidth = minimumWidth; self.viewportWidth = viewportWidth
        self.additionalWidth = additionalWidth; self.content = content
    }
    init(minimumWidth: CGFloat, viewportWidth: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(minimumWidth: minimumWidth, viewportWidth: viewportWidth) { _ in content() }
    }
    var body: some View {
        let summaryWidth = max(viewportWidth ?? availableWidth, minimumWidth)
        ScrollView(.horizontal, showsIndicators: true) {
            content(summaryWidth).frame(width: summaryWidth + additionalWidth, alignment: .leading)
                .background { CompetitionHorizontalTableBoundary().frame(width: 0, height: 0) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .frame(width: viewportWidth)
        .accessibilityIdentifier("competition-all-results-table")
        .background { GeometryReader { proxy in
            Color.clear
                .onAppear { updateAvailableWidth(proxy.size.width) }
                .onChange(of: proxy.size.width) { updateAvailableWidth($0) }
        } }
    }
    private func updateAvailableWidth(_ width: CGFloat) {
        guard viewportWidth == nil, width > 0, availableWidth != width else { return }
        availableWidth = width
    }
}

/// Configure only the horizontal owner containing this content. No appearance
/// proxy, gesture interception, offset writes, or ancestor vertical-scroll changes.
private struct CompetitionHorizontalTableBoundary: UIViewRepresentable {
    func makeUIView(context: Context) -> CompetitionHorizontalTableBoundaryAnchor { .init() }
    func updateUIView(_ view: CompetitionHorizontalTableBoundaryAnchor, context: Context) { view.attach() }
    static func dismantleUIView(_ view: CompetitionHorizontalTableBoundaryAnchor, coordinator: Void) { view.detach() }
}

final class CompetitionHorizontalTableBoundaryAnchor: UIView {
    private(set) weak var scrollView: UIScrollView?
    private var previous: (bounces: Bool, alwaysHorizontal: Bool)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false; accessibilityElementsHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { detach() } else { attach() } }
    override func didMoveToSuperview() { super.didMoveToSuperview(); if window != nil { attach() } }
    func attach() {
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView {
                if scrollView !== scroll {
                    detach()
                    scrollView = scroll; previous = (scroll.bounces, scroll.alwaysBounceHorizontal)
                }
                if scroll.bounces { scroll.bounces = false }
                if scroll.alwaysBounceHorizontal { scroll.alwaysBounceHorizontal = false }
                return
            }
            ancestor = view.superview
        }
    }
    func detach() {
        if let scrollView, let previous {
            scrollView.bounces = previous.bounces; scrollView.alwaysBounceHorizontal = previous.alwaysHorizontal
        }
        scrollView = nil; previous = nil
    }
}

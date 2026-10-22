#if os(iOS)
import SwiftUI

nonisolated enum ExploreEventPacking {
    static let spacing: CGFloat = 6
    static let minimumSpacing: CGFloat = 4
    static let maximumSpacing: CGFloat = 12
    struct Row { let indices: Range<Int>; let spacing: CGFloat }

    /// Fill each row before starting the next; never rebalance a full first row.
    static func rows(widths: [CGFloat], available: CGFloat, preferredSpacing: CGFloat = spacing) -> [Row] {
        guard !widths.isEmpty, available.isFinite, available > 0 else { return [] }
        let preferred = min(maximumSpacing, max(minimumSpacing, preferredSpacing))
        var result: [Row] = [], start = 0
        while start < widths.count {
            var end = start + 1, ink = widths[start]
            while end < widths.count, ink + widths[end] + CGFloat(end - start) * minimumSpacing <= available + 0.001 {
                ink += widths[end]; end += 1
            }
            let gaps = end - start - 1
            let gap = gaps == 0 ? preferred : min(preferred, max(minimumSpacing, (available - ink) / CGFloat(gaps)))
            result.append(Row(indices: start..<end, spacing: gap)); start = end
        }
        return result
    }
}

struct ExploreCompetitionEventStrip: View {
    let eventIDs: [String]
    let language: String
    var availableWidth: CGFloat = 248
    static let officialEvents = ["333", "222", "444", "555", "666", "777", "333bf", "333fm", "333oh", "clock", "minx", "pyram", "skewb", "sq1", "444bf", "555bf", "333mbf"]
    @ScaledMetric(relativeTo: .footnote) private var iconSize = 18
    @ScaledMetric(relativeTo: .footnote) private var labelSize = 13

    private var events: [String] { eventIDs.reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }
    private var labelFont: UIFont { .monospacedDigitSystemFont(ofSize: labelSize, weight: .medium) }
    struct Layout {
        let iconSize: CGFloat
        let cellSide: CGFloat
        let rows: [ExploreEventPacking.Row]
        let reservedHeight: CGFloat
    }
    static func layout(eventIDs: [String], minimumIcon: CGFloat, labelFont: UIFont, language: String, available: CGFloat) -> Layout {
        let minimum = max(18, minimumIcon)
        // Include font advance/overhang as well as the shared glyph's vertical padding.
        let family = officialEvents + eventIDs.filter { !officialEvents.contains($0) }
        let widthFactor = family.filter { CompetitionEventIconFont.glyph(for: $0) != nil }.map {
            width($0, iconSize: minimum, labelFont: labelFont, language: language) / minimum
        }.max() ?? 1
        func side(_ font: CGFloat) -> CGFloat { ceil(max(font + 6, font * widthFactor)) }
        let minimumSide = side(minimum)
        let familyRows = max(2, ExploreEventPacking.rows(widths: Array(repeating: minimumSide, count: officialEvents.count), available: available).count)
        let height = CGFloat(familyRows) * minimumSide + CGFloat(familyRows - 1) * ExploreEventPacking.spacing
        let maximumSide = min(height, side(minimum * 2))
        func comfortableGap(_ cell: CGFloat) -> CGFloat {
            min(ExploreEventPacking.maximumSpacing, max(ExploreEventPacking.minimumSpacing, cell / 4))
        }
        let count = eventIDs.count
        var chosenSide = minimumSide
        if count > 0, CGFloat(count) * minimumSide + CGFloat(count - 1) * ExploreEventPacking.minimumSpacing <= available {
            // Largest coherent square cells with comfortable proportional spacing.
            var lower = minimumSide, upper = min(maximumSide, available)
            for _ in 0..<16 {
                let middle = (lower + upper) / 2
                if CGFloat(count) * middle + CGFloat(count - 1) * comfortableGap(middle) <= available { lower = middle }
                else { upper = middle }
            }
            chosenSide = floor(lower * 2) / 2
        }
        let font = min(chosenSide - 6, chosenSide / widthFactor)
        let widths = eventIDs.map { event in
            CompetitionEventIconFont.glyph(for: event) != nil ? chosenSide
                : min(available, width(event, iconSize: font, labelFont: labelFont, language: language))
        }
        let packed = ExploreEventPacking.rows(widths: widths, available: available, preferredSpacing: comfortableGap(chosenSide))
        // Fixed square glyph cells form columns, not separately spaced rows.
        // A short final row must keep the first row's compressed column pitch.
        let glyphGrid = eventIDs.allSatisfy { CompetitionEventIconFont.glyph(for: $0) != nil }
        let rows = glyphGrid ? packed.map {
            ExploreEventPacking.Row(indices: $0.indices, spacing: packed.first?.spacing ?? $0.spacing)
        } : packed
        return Layout(iconSize: max(minimum, font), cellSide: chosenSide, rows: rows,
            reservedHeight: max(height, CGFloat(rows.count) * chosenSide + CGFloat(max(0, rows.count - 1)) * ExploreEventPacking.spacing))
    }
    static func width(_ event: String, iconSize: CGFloat, labelFont: UIFont, language: String) -> CGFloat {
        if let glyph = CompetitionEventIconFont.glyph(for: event),
           let metrics = CompetitionEventIconFont.glyphMetrics(for: glyph, pointSize: iconSize) {
            let overhang = max(0, -metrics.bounds.minX, metrics.bounds.maxX - metrics.advance)
            return ceil(metrics.advance + 2 * overhang)
        }
        let title = CompetitionEventPresentation.localizedFullName(for: event, languageCode: language)
        return ceil((title as NSString).size(withAttributes: [.font: labelFont]).width)
    }
    static func inkCenterOffset(glyph: String, size: CGFloat) -> CGFloat {
        -(CompetitionEventIconFont.glyphMetrics(for: glyph, pointSize: size)?.centerOffset ?? 0)
    }
    private func title(_ event: String) -> String {
        CompetitionEventPresentation.localizedFullName(for: event, languageCode: language)
    }
    var body: some View {
        let _ = CompetitionEventIconFont.ensureRegistered()
        let values = events
        let layout = Self.layout(eventIDs: values, minimumIcon: iconSize, labelFont: labelFont, language: language, available: availableWidth)
        let rows = layout.rows
        VStack(alignment: .leading, spacing: ExploreEventPacking.spacing) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: rows[row].spacing) {
                    ForEach(Array(rows[row].indices), id: \.self) { index in
                        let event = values[index]
                        Group {
                            if let glyph = CompetitionEventIconFont.glyph(for: event) {
                                CompetitionEventGlyph(glyph: glyph, eventName: title(event), size: layout.iconSize)
                                    .environment(\.dynamicTypeSize, .large)
                                    .offset(x: Self.inkCenterOffset(glyph: glyph, size: layout.iconSize))
                            } else {
                                Text(title(event)).font(.system(size: labelSize, weight: .medium).monospacedDigit())
                            }
                        }.frame(width: CompetitionEventIconFont.glyph(for: event) != nil ? layout.cellSide
                            : min(availableWidth, Self.width(event, iconSize: layout.iconSize, labelFont: labelFont, language: language)), height: layout.cellSide)
                            .accessibilityIdentifier("explore-region-event-\(event)")
                            .modifier(ExploreRegionalMeasurement(id: "event-\(event)"))
                    }
                }
                .frame(height: layout.cellSide, alignment: .leading)
            }
        }

        .frame(width: availableWidth, height: layout.reservedHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(events.map(title).joined(separator: ", "))
    }
}

/// Mounted test observation only. No production measurement state or feedback.
struct ExploreRegionalMeasurement: ViewModifier {
    let id: String
    #if DEBUG
    @Environment(\.exploreRegionalMeasurement) private var observe
    func body(content: Content) -> some View {
        content.background {
            if observe != nil {
                GeometryReader { proxy in
                    Color.clear.preference(key: ExploreRegionalFrames.self, value: [id: proxy.frame(in: .global)])
                }
                .onPreferenceChange(ExploreRegionalFrames.self) { observe?($0) }
            }
        }
    }
    #else
    func body(content: Content) -> some View { content }
    #endif
}

#if DEBUG
private struct ExploreRegionalObserverKey: EnvironmentKey {
    static let defaultValue: (([String: CGRect]) -> Void)? = nil
}
nonisolated private struct ExploreRegionalFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
extension EnvironmentValues {
    var exploreRegionalMeasurement: (([String: CGRect]) -> Void)? {
        get { self[ExploreRegionalObserverKey.self] }
        set { self[ExploreRegionalObserverKey.self] = newValue }
    }
}
#endif
#endif

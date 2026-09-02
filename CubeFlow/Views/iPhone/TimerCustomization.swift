import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if os(iOS)
private struct TimerPreviewTopControlsHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TimerPreviewScrambleHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

enum TimerArrangement: String, CaseIterable, Identifiable {
    case classic
    case split
    case cards

    var id: String { rawValue }

    var localizedKey: String {
        switch self {
        case .classic: "settings.timer_arrangement_classic"
        case .split: "settings.timer_arrangement_split"
        case .cards: "settings.timer_arrangement_cards"
        }
    }

    var defaultTitle: String {
        switch self {
        case .classic: "Classic"
        case .split: "Split"
        case .cards: "Cards"
        }
    }

    var allowsIndependentDiagramPlacement: Bool {
        self == .classic
    }

    static func resolved(storedRawValue: String) -> TimerArrangement {
        switch storedRawValue {
        case "splitStatisticsLeading", "splitDiagramLeading":
            return .split
        default:
            return TimerArrangement(rawValue: storedRawValue) ?? .classic
        }
    }

    func resolvedDiagramPlacement(
        from stored: DrawScramblePlacement,
        splitOrder: TimerSplitOrder
    ) -> DrawScramblePlacement? {
        switch self {
        case .classic:
            return stored.isFloating ? stored : nil
        case .split:
            return splitOrder == .statisticsLeading ? .bottomRight : .bottomLeft
        case .cards:
            return nil
        }
    }
}

struct TimerArrangementMigrationResult: Equatable {
    let arrangement: TimerArrangement
    let minimalMode: Bool
    let completed: Bool
}

enum TimerArrangementMigration {
    static func resolve(
        storedArrangement: String,
        minimalMode: Bool,
        completed: Bool
    ) -> TimerArrangementMigrationResult {
        guard !completed else {
            return TimerArrangementMigrationResult(
                arrangement: TimerArrangement.resolved(storedRawValue: storedArrangement),
                minimalMode: minimalMode,
                completed: true
            )
        }
        return TimerArrangementMigrationResult(
            arrangement: storedArrangement == "minimal"
                ? .classic
                : TimerArrangement.resolved(storedRawValue: storedArrangement),
            minimalMode: storedArrangement == "minimal" ? true : minimalMode,
            completed: true
        )
    }
}

struct TimerEffectivePresentation: Equatable {
    let arrangement: TimerArrangement
    let minimalMode: Bool

    var showsStatistics: Bool { !minimalMode }
    var showsScrambleDiagram: Bool { !minimalMode }

    func resolvedDiagramPlacement(
        from stored: DrawScramblePlacement,
        splitOrder: TimerSplitOrder
    ) -> DrawScramblePlacement? {
        guard showsScrambleDiagram else { return nil }
        return arrangement.resolvedDiagramPlacement(from: stored, splitOrder: splitOrder)
    }
}

enum TimerSplitOrder: String, CaseIterable, Identifiable {
    case statisticsLeading
    case diagramLeading

    var id: String { rawValue }

    var localizedKey: String {
        switch self {
        case .statisticsLeading: "settings.timer_split_order_statistics_leading"
        case .diagramLeading: "settings.timer_split_order_diagram_leading"
        }
    }

    var defaultTitle: String {
        switch self {
        case .statisticsLeading: "Statistics First"
        case .diagramLeading: "Diagram First"
        }
    }

    static func resolved(storedRawValue: String, legacyArrangementRawValue: String) -> TimerSplitOrder {
        if legacyArrangementRawValue == "splitDiagramLeading" { return .diagramLeading }
        if legacyArrangementRawValue == "splitStatisticsLeading" { return .statisticsLeading }
        if let stored = TimerSplitOrder(rawValue: storedRawValue) {
            return stored
        }
        return .statisticsLeading
    }
}

enum TimerStatisticMetric: String, CaseIterable, Identifiable, Hashable {
    case mean
    case best
    case mo3
    case ao5
    case ao12
    case ao50
    case ao100
    case solveCount

    var id: String { rawValue }

    var localizedKey: String {
        switch self {
        case .mean: "settings.timer_stat_mean"
        case .best: "settings.timer_stat_best"
        case .mo3: "data.mo3"
        case .ao5: "data.ao5"
        case .ao12: "data.ao12"
        case .ao50: "data.ao50"
        case .ao100: "data.ao100"
        case .solveCount: "settings.timer_stat_solve_count"
        }
    }

    var defaultTitle: String {
        switch self {
        case .mean: "Mean"
        case .best: "Best"
        case .mo3: "Mo3"
        case .ao5: "Ao5"
        case .ao12: "Ao12"
        case .ao50: "Ao50"
        case .ao100: "Ao100"
        case .solveCount: "Solve Count"
        }
    }

    static func resolvedSelection(
        storedValue: String,
        legacyDisplayOption: AverageDisplayOption
    ) -> [TimerStatisticMetric] {
        if storedValue == "none" { return [] }
        let stored = storedValue
            .split(separator: ",")
            .compactMap { TimerStatisticMetric(rawValue: String($0)) }
        if !storedValue.isEmpty {
            let selected = Set(stored)
            return allCases.filter(selected.contains)
        }

        switch legacyDisplayOption {
        case .none: return []
        case .ao5: return [.ao5]
        case .ao12: return [.ao12]
        case .ao5AndAo12: return [.ao5, .ao12]
        }
    }

    static func storedValue(for metrics: [TimerStatisticMetric]) -> String {
        let selected = Set(metrics)
        let stored = allCases.filter(selected.contains).map(\.rawValue).joined(separator: ",")
        return stored.isEmpty ? "none" : stored
    }
}

enum TimerCustomizationDefaults {
    static let drawScrambleSize: Double = 275
    static let drawScrambleSizeRange: ClosedRange<Double> = 96...500

    static func resolvedDrawScrambleSize(_ storedValue: Double) -> Double {
        guard storedValue.isFinite else { return drawScrambleSize }
        return min(max(storedValue, drawScrambleSizeRange.lowerBound), drawScrambleSizeRange.upperBound)
    }
}

enum TimerStatisticSelection {
    static let classicMaximumCount = 2
    static let cardsMaximumCount = 4
    static let defaultCardsSelection: [TimerStatisticMetric] = [.mean, .ao5, .ao12, .ao100]

    static func resolved(
        arrangement: TimerArrangement,
        sharedStoredValue: String,
        classicStoredValue: String,
        cardsStoredValue: String = "",
        legacyDisplayOption: AverageDisplayOption
    ) -> [TimerStatisticMetric] {
        let shared = TimerStatisticMetric.resolvedSelection(
            storedValue: sharedStoredValue,
            legacyDisplayOption: legacyDisplayOption
        )
        switch arrangement {
        case .classic:
            let classic = classicStoredValue.isEmpty
                ? shared
                : TimerStatisticMetric.resolvedSelection(
                    storedValue: classicStoredValue,
                    legacyDisplayOption: legacyDisplayOption
                )
            return Array(classic.prefix(classicMaximumCount))
        case .split:
            return shared
        case .cards:
            let cards = cardsStoredValue.isEmpty
                ? defaultCardsSelection
                : TimerStatisticMetric.resolvedSelection(
                    storedValue: cardsStoredValue,
                    legacyDisplayOption: legacyDisplayOption
                )
            return Array(cards.prefix(cardsMaximumCount))
        }
    }

    static func migratedCardsStoredValue(
        cardsStoredValue: String,
        legacyDisplayOption: AverageDisplayOption
    ) -> String {
        let selection = cardsStoredValue.isEmpty
            ? defaultCardsSelection
            : TimerStatisticMetric.resolvedSelection(
                storedValue: cardsStoredValue,
                legacyDisplayOption: legacyDisplayOption
            )
        return TimerStatisticMetric.storedValue(for: Array(selection.prefix(cardsMaximumCount)))
    }

    static func migratedClassicStoredValue(
        sharedStoredValue: String,
        classicStoredValue: String,
        legacyDisplayOption: AverageDisplayOption
    ) -> String {
        let selection = resolved(
            arrangement: .classic,
            sharedStoredValue: sharedStoredValue,
            classicStoredValue: classicStoredValue,
            legacyDisplayOption: legacyDisplayOption
        )
        return TimerStatisticMetric.storedValue(for: selection)
    }

    static func updating(
        _ selection: [TimerStatisticMetric],
        metric: TimerStatisticMetric,
        isSelected: Bool,
        arrangement: TimerArrangement
    ) -> [TimerStatisticMetric] {
        var selected = Set(selection)
        if isSelected {
            let maximumCount = maximumCount(for: arrangement)
            if let maximumCount,
               !selected.contains(metric),
               selected.count >= maximumCount {
                return Array(TimerStatisticMetric.allCases.filter(selected.contains).prefix(maximumCount))
            }
            selected.insert(metric)
        } else {
            selected.remove(metric)
        }

        let ordered = TimerStatisticMetric.allCases.filter(selected.contains)
        guard let maximumCount = maximumCount(for: arrangement) else { return ordered }
        return Array(ordered.prefix(maximumCount))
    }

    static func maximumCount(for arrangement: TimerArrangement) -> Int? {
        switch arrangement {
        case .classic: classicMaximumCount
        case .cards: cardsMaximumCount
        case .split: nil
        }
    }
}

enum TimerCardsTwoStatisticArrangement: String, CaseIterable, Identifiable {
    case vertical
    case horizontal
    var id: String { rawValue }
}

enum TimerCardsThreeStatisticArrangement: String, CaseIterable, Identifiable {
    case topEmphasis
    case bottomEmphasis
    var id: String { rawValue }
}

enum TimerCardsStatisticsLayout: String, Codable, Equatable {
    case full
    case vertical
    case horizontal
    case topEmphasis
    case bottomEmphasis
    case grid

    static func resolved(
        count: Int,
        two: TimerCardsTwoStatisticArrangement,
        three: TimerCardsThreeStatisticArrangement
    ) -> TimerCardsStatisticsLayout {
        switch count {
        case 2: two == .vertical ? .vertical : .horizontal
        case 3: three == .topEmphasis ? .topEmphasis : .bottomEmphasis
        case 4...: .grid
        default: .full
        }
    }

    var slotLocalizationKeys: [String] {
        switch self {
        case .full: []
        case .vertical: ["settings.timer_slot_top", "settings.timer_slot_bottom"]
        case .horizontal: ["settings.timer_slot_left", "settings.timer_slot_right"]
        case .topEmphasis: ["settings.timer_slot_top", "settings.timer_slot_bottom_left", "settings.timer_slot_bottom_right"]
        case .bottomEmphasis: ["settings.timer_slot_top_left", "settings.timer_slot_top_right", "settings.timer_slot_bottom"]
        case .grid: ["settings.timer_slot_top_left", "settings.timer_slot_top_right", "settings.timer_slot_bottom_left", "settings.timer_slot_bottom_right"]
        }
    }
}

struct TimerCardsPositionStore: Codable, Equatable {
    var assignments: [String: [String]] = [:]

    static func decode(_ storedValue: String) -> TimerCardsPositionStore {
        guard let data = storedValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(TimerCardsPositionStore.self, from: data) else {
            return TimerCardsPositionStore()
        }
        return decoded
    }

    func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    func resolvedMetrics(
        for layout: TimerCardsStatisticsLayout,
        selectedMetrics: [TimerStatisticMetric]
    ) -> [TimerStatisticMetric] {
        let selected = Set(selectedMetrics)
        var resolved: [TimerStatisticMetric] = []
        for rawValue in assignments[layout.rawValue] ?? [] {
            guard let metric = TimerStatisticMetric(rawValue: rawValue),
                  selected.contains(metric),
                  !resolved.contains(metric) else { continue }
            resolved.append(metric)
        }
        resolved.append(contentsOf: TimerStatisticMetric.allCases.filter {
            selected.contains($0) && !resolved.contains($0)
        })
        return Array(resolved.prefix(selectedMetrics.count))
    }

    func assigning(
        metric: TimerStatisticMetric,
        to slot: Int,
        layout: TimerCardsStatisticsLayout,
        selectedMetrics: [TimerStatisticMetric]
    ) -> TimerCardsPositionStore {
        var copy = self
        var resolved = resolvedMetrics(for: layout, selectedMetrics: selectedMetrics)
        guard resolved.indices.contains(slot), let source = resolved.firstIndex(of: metric) else { return copy }
        resolved.swapAt(source, slot)
        copy.assignments[layout.rawValue] = resolved.map(\.rawValue)
        return copy
    }

    func normalizing(
        layout: TimerCardsStatisticsLayout,
        selectedMetrics: [TimerStatisticMetric]
    ) -> TimerCardsPositionStore {
        var copy = self
        copy.assignments[layout.rawValue] = resolvedMetrics(
            for: layout,
            selectedMetrics: selectedMetrics
        ).map(\.rawValue)
        return copy
    }
}

struct TimerCardsStatisticsConfiguration: Equatable {
    let selectedMetrics: [TimerStatisticMetric]
    let layout: TimerCardsStatisticsLayout
    let positionedMetrics: [TimerStatisticMetric]

    static func resolve(
        selectedMetrics: [TimerStatisticMetric],
        twoArrangement: TimerCardsTwoStatisticArrangement,
        threeArrangement: TimerCardsThreeStatisticArrangement,
        positionStore: TimerCardsPositionStore
    ) -> TimerCardsStatisticsConfiguration {
        let selection = Array(selectedMetrics.prefix(TimerStatisticSelection.cardsMaximumCount))
        let layout = TimerCardsStatisticsLayout.resolved(
            count: selection.count,
            two: twoArrangement,
            three: threeArrangement
        )
        return TimerCardsStatisticsConfiguration(
            selectedMetrics: selection,
            layout: layout,
            positionedMetrics: positionStore.resolvedMetrics(for: layout, selectedMetrics: selection)
        )
    }
}

struct TimerStatisticDisplayItem: Identifiable, Hashable {
    let metric: TimerStatisticMetric
    let title: String
    let value: String
    let isAvailable: Bool

    init(
        metric: TimerStatisticMetric,
        title: String,
        value: String,
        isAvailable: Bool = true
    ) {
        self.metric = metric
        self.title = title
        self.value = value
        self.isAvailable = isAvailable
    }

    var id: TimerStatisticMetric { metric }
}

struct TimerEventMenu: View {
    @Binding var selection: PuzzleEvent
    let isEnabled: Bool

    var body: some View {
        Menu {
            ForEach(PuzzleEvent.regularCases, id: \.self) { event in
                if event == .fourByFour {
                    Menu("timer.menu.4x4") {
                        ForEach(PuzzleEvent.fourByFourCases, id: \.self) { nestedEvent in
                            eventButton(nestedEvent)
                        }
                    }
                } else if event != .fourByFourFast {
                    eventButton(event)
                }
            }

            Menu("timer.menu.bld") {
                ForEach(PuzzleEvent.blindfoldedCases, id: \.self) { event in
                    eventButton(event)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(selection.localizationKey))
                    .font(.system(size: 17, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.capsule)
            .clipShape(.capsule)
            .compatibleGlassFromIOS16(in: Capsule())
        }
        .tint(.primary)
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func eventButton(_ event: PuzzleEvent) -> some View {
        Button(LocalizedStringKey(event == .fourByFour ? "event.4x4_standard" : event.localizationKey)) {
            selection = event
        }
    }
}

@MainActor
private struct TimerPreviewViewportMetrics {
    let size: CGSize
    let topSafeAreaHeight: CGFloat
    let bottomTabBarReserveHeight: CGFloat

    var timerContentFrame: CGRect {
        let contentHeight = max(0, size.height - topSafeAreaHeight - bottomTabBarReserveHeight)
        return CGRect(x: 0, y: topSafeAreaHeight, width: size.width, height: contentHeight)
    }

    static var current: TimerPreviewViewportMetrics {
        #if canImport(UIKit)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
        let rawSize = window?.bounds.size ?? CGSize(width: 393, height: 852)
        let size = TimerArrangementLayout.sanitizedSize(rawSize, fallback: CGSize(width: 393, height: 852))
        let safeInsets = window?.safeAreaInsets ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let tabBarHeight = tabBarHeight(in: window?.rootViewController)
        return TimerPreviewViewportMetrics(
            size: size,
            topSafeAreaHeight: TimerArrangementLayout.nonnegativeFinite(safeInsets.top),
            bottomTabBarReserveHeight: TimerArrangementLayout.nonnegativeFinite(
                tabBarHeight > 0 ? tabBarHeight : 49 + safeInsets.bottom
            )
        )
        #else
        return TimerPreviewViewportMetrics(
            size: CGSize(width: 393, height: 852),
            topSafeAreaHeight: 59,
            bottomTabBarReserveHeight: 83
        )
        #endif
    }

    #if canImport(UIKit)
    private static func tabBarHeight(in viewController: UIViewController?) -> CGFloat {
        guard let viewController else { return 0 }
        if let tabBarController = viewController as? UITabBarController {
            return tabBarController.tabBar.bounds.height
        }
        for child in viewController.children {
            let height = tabBarHeight(in: child)
            if height > 0 { return height }
        }
        if let presented = viewController.presentedViewController {
            return tabBarHeight(in: presented)
        }
        return 0
    }
    #endif
}

enum TimerArrangementLayout {
    static let componentSpacing: CGFloat = 12
    static let outerInset: CGFloat = 16
    static let bottomInset: CGFloat = 16
    static let cardContentInset: CGFloat = 10
    static let timerContentHorizontalInset: CGFloat = 24
    static let topControlsTopInset: CGFloat = 8
    static let topControlsMinimumHeight: CGFloat = 48
    static let scrambleAccessorySpacing: CGFloat = 10
    static let scrambleAccessoryButtonSpacing: CGFloat = 6
    static let scrambleContentMinimumHeight: CGFloat = 44
    static let defaultTimerVerticalOffset: CGFloat = 18

    struct Geometry: Equatable {
        let containerSize: CGSize
        let timerCenter: CGPoint
        let classicStatisticsFrame: CGRect
        let splitLeadingFrame: CGRect
        let splitTrailingFrame: CGRect
        let leadingCardFrame: CGRect
        let trailingCardFrame: CGRect
        let independentDiagramWidth: CGFloat

        func independentDiagramFrame(
            placement: DrawScramblePlacement,
            aspectRatio: CGFloat
        ) -> CGRect {
            let ratio = TimerArrangementLayout.positiveFinite(aspectRatio, fallback: 1)
            let width = independentDiagramWidth
            let height = TimerArrangementLayout.nonnegativeFinite(width / ratio)
            let y = max(0, containerSize.height - TimerArrangementLayout.bottomInset - height)
            let x: CGFloat
            switch placement {
            case .bottomLeft:
                x = min(TimerArrangementLayout.outerInset, containerSize.width)
            case .bottomCenter:
                x = max(0, (containerSize.width - width) / 2)
            default:
                x = max(0, containerSize.width - TimerArrangementLayout.outerInset - width)
            }
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }

    static func nonnegativeFinite(_ value: CGFloat, fallback: CGFloat = 0) -> CGFloat {
        guard value.isFinite else { return max(0, fallback.isFinite ? fallback : 0) }
        return max(0, value)
    }

    static func positiveFinite(_ value: CGFloat, fallback: CGFloat = 1) -> CGFloat {
        let resolvedFallback = fallback.isFinite && fallback > 0 ? fallback : 1
        guard value.isFinite, value > 0 else { return resolvedFallback }
        return value
    }

    static func sanitizedSize(_ size: CGSize, fallback: CGSize = .zero) -> CGSize {
        CGSize(
            width: nonnegativeFinite(size.width, fallback: fallback.width),
            height: nonnegativeFinite(size.height, fallback: fallback.height)
        )
    }

    static func timerReservedHeight(fontSize: CGFloat) -> CGFloat {
        max(positiveFinite(fontSize, fallback: 64) * 1.45, 110)
    }

    static func classicStatisticsOffset(
        timerFontSize: CGFloat,
        statisticsFontSize: CGFloat
    ) -> CGFloat {
        positiveFinite(timerFontSize, fallback: 64) * 0.62
            + positiveFinite(statisticsFontSize, fallback: 20) * 0.55
            + 10
    }

    static func statisticsColumnHeight(
        itemCount: Int,
        fontSize: CGFloat,
        lineSpacing: CGFloat = 6
    ) -> CGFloat {
        let count = CGFloat(max(0, itemCount))
        let spacing = max(0, count - 1) * nonnegativeFinite(lineSpacing)
        return nonnegativeFinite(max(30, count * positiveFinite(fontSize, fallback: 20) * 1.2 + spacing))
    }

    static func contentWidth(
        containerWidth: CGFloat,
        horizontalInsets: CGFloat,
        maximum: CGFloat? = nil
    ) -> CGFloat {
        let width = nonnegativeFinite(containerWidth)
        let insets = nonnegativeFinite(horizontalInsets)
        let available = max(0, width - insets)
        guard let maximum else { return available }
        return min(available, nonnegativeFinite(maximum))
    }

    static func geometry(
        containerSize: CGSize,
        timerVerticalOffset: CGFloat,
        classicStatisticsHeight: CGFloat,
        classicStatisticsOffset: CGFloat,
        diagramPreferredWidth: CGFloat,
        diagramAspectRatio: CGFloat
    ) -> Geometry {
        let size = sanitizedSize(containerSize)
        let timerY = min(
            size.height,
            max(0, size.height / 2 + (timerVerticalOffset.isFinite ? timerVerticalOffset : 0))
        )
        let timerCenter = CGPoint(x: size.width / 2, y: timerY)
        let availableContentWidth = contentWidth(
            containerWidth: size.width,
            horizontalInsets: outerInset * 2
        )
        let sideWidth = max(0, (availableContentWidth - componentSpacing) / 2)
        let ratio = positiveFinite(diagramAspectRatio, fallback: 1)
        let preferredDiagramWidth = nonnegativeFinite(diagramPreferredWidth)
        let splitDiagramWidth = min(sideWidth, preferredDiagramWidth)
        let splitDiagramHeight = splitDiagramWidth / ratio
        let statisticsHeight = nonnegativeFinite(classicStatisticsHeight)
        let splitHeight = min(
            max(0, size.height - bottomInset),
            max(statisticsHeight, splitDiagramHeight)
        )
        let splitY = max(0, size.height - bottomInset - splitHeight)
        let leadingX = min(outerInset, size.width)
        let trailingX = min(size.width, leadingX + sideWidth + componentSpacing)
        let splitLeadingFrame = CGRect(x: leadingX, y: splitY, width: sideWidth, height: splitHeight)
        let splitTrailingFrame = CGRect(x: trailingX, y: splitY, width: sideWidth, height: splitHeight)

        let preferredCardHeight = min(136, max(116, size.height * 0.195))
        let cardHeight = min(preferredCardHeight, max(0, size.height - bottomInset * 2))
        let cardY = max(0, size.height - bottomInset - cardHeight)
        let leadingCardFrame = CGRect(x: leadingX, y: cardY, width: sideWidth, height: cardHeight)
        let trailingCardFrame = CGRect(x: trailingX, y: cardY, width: sideWidth, height: cardHeight)

        let classicWidth = contentWidth(
            containerWidth: size.width,
            horizontalInsets: 48,
            maximum: 360
        )
        let classicHeight = min(statisticsHeight, max(0, size.height - timerY))
        let classicCenterY = timerY + nonnegativeFinite(classicStatisticsOffset)
        let classicY = min(
            max(0, size.height - classicHeight),
            max(0, classicCenterY - classicHeight / 2)
        )
        let classicStatisticsFrame = CGRect(
            x: max(0, (size.width - classicWidth) / 2),
            y: classicY,
            width: classicWidth,
            height: classicHeight
        )

        return Geometry(
            containerSize: size,
            timerCenter: timerCenter,
            classicStatisticsFrame: classicStatisticsFrame,
            splitLeadingFrame: splitLeadingFrame,
            splitTrailingFrame: splitTrailingFrame,
            leadingCardFrame: leadingCardFrame,
            trailingCardFrame: trailingCardFrame,
            independentDiagramWidth: min(preferredDiagramWidth, availableContentWidth)
        )
    }

    static func normalizedScramblePosition(_ value: Double) -> CGFloat {
        CGFloat(max(0, min(1, value.isFinite ? value : 0)))
    }

    static func scrambleTop(
        availableHeight: CGFloat,
        contentHeight: CGFloat,
        normalizedPosition: Double
    ) -> CGFloat {
        let travel = max(0, nonnegativeFinite(availableHeight) - nonnegativeFinite(contentHeight))
        return travel * normalizedScramblePosition(normalizedPosition)
    }

    static func scrambleAvailableHeight(
        containerHeight: CGFloat,
        timerVerticalOffset: CGFloat,
        timerReservedHeight: CGFloat,
        topControlsHeight: CGFloat
    ) -> CGFloat {
        nonnegativeFinite(
            max(
                72,
                nonnegativeFinite(containerHeight) / 2
                    + (timerVerticalOffset.isFinite ? timerVerticalOffset : 0)
                    - nonnegativeFinite(timerReservedHeight) / 2
                    - nonnegativeFinite(topControlsHeight)
            ),
            fallback: 72
        )
    }

    static func centeredGroupTop(containerHeight: CGFloat, groupHeight: CGFloat) -> CGFloat {
        max(0, (nonnegativeFinite(containerHeight) - nonnegativeFinite(groupHeight)) / 2)
    }

    static func collisionAvoidingGroupTop(
        containerHeight: CGFloat,
        groupHeight: CGFloat,
        obstructionMinY: CGFloat?,
        minimumSpacing: CGFloat
    ) -> CGFloat {
        let safeGroupHeight = nonnegativeFinite(groupHeight)
        let preferred = centeredGroupTop(containerHeight: containerHeight, groupHeight: safeGroupHeight)
        guard let obstructionMinY, obstructionMinY.isFinite, safeGroupHeight > 0 else { return preferred }
        return max(0, min(preferred, obstructionMinY - nonnegativeFinite(minimumSpacing) - safeGroupHeight))
    }

    static func automaticStatisticsFontSize(
        availableWidth: CGFloat,
        itemCount: Int,
        preferredSize: CGFloat
    ) -> CGFloat {
        let safePreferredSize = positiveFinite(preferredSize, fallback: 18)
        guard itemCount > 0 else { return min(safePreferredSize, 18) }
        let widthPerItem = max(1, nonnegativeFinite(availableWidth) / CGFloat(min(itemCount, 4)))
        let widthScale = min(1, widthPerItem / 104)
        let countScale: CGFloat = itemCount > 4 ? 0.82 : 1
        return max(11, min(safePreferredSize, 18) * widthScale * countScale)
    }

    static func cardDiagramWidth(
        in frame: CGRect,
        aspectRatio: CGFloat
    ) -> CGFloat {
        let inset = nonnegativeFinite(cardContentInset)
        let availableWidth = max(0, nonnegativeFinite(frame.width) - inset * 2)
        let availableHeight = max(0, nonnegativeFinite(frame.height) - inset * 2)
        return min(
            availableWidth,
            availableHeight * positiveFinite(aspectRatio)
        )
    }
}

struct TimerCardStatisticsView: View {
    let items: [TimerStatisticDisplayItem]
    let layout: TimerCardsStatisticsLayout
    let appearance: AppearanceConfiguration
    let fontDesign: TimerFontDesignOption
    let fontStyle: TimerFontStyleOption
    let preferredFontSize: Double

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let safeWidth = TimerArrangementLayout.nonnegativeFinite(proxy.size.width)
            let safeHeight = TimerArrangementLayout.nonnegativeFinite(proxy.size.height)
            let preferredValueSize = max(
                22,
                TimerArrangementLayout.positiveFinite(CGFloat(preferredFontSize), fallback: 18) * 1.2
            )
            let valueSize = max(16, min(preferredValueSize, safeWidth * 0.18, safeHeight * 0.24))
            let labelSize = max(10, min(valueSize * 0.48, 13))

            statisticsLayout(labelSize: labelSize, valueSize: valueSize)
        }
    }

    @ViewBuilder
    private func statisticsLayout(labelSize: CGFloat, valueSize: CGFloat) -> some View {
        switch layout {
        case .full:
            statisticsCell(items.first, labelSize: labelSize, valueSize: valueSize)
        case .vertical:
            VStack(spacing: 0) {
                statisticsCell(item(at: 0), labelSize: labelSize, valueSize: valueSize)
                statisticsDivider
                statisticsCell(item(at: 1), labelSize: labelSize, valueSize: valueSize)
            }
        case .horizontal:
            statisticsRow(Array(items.prefix(2)), labelSize: labelSize, valueSize: valueSize)
        case .topEmphasis:
            VStack(spacing: 0) {
                statisticsCell(item(at: 0), labelSize: labelSize, valueSize: valueSize)
                statisticsDivider
                statisticsRow(Array(items.dropFirst().prefix(2)), labelSize: labelSize, valueSize: valueSize)
            }
        case .bottomEmphasis:
            VStack(spacing: 0) {
                statisticsRow(Array(items.prefix(2)), labelSize: labelSize, valueSize: valueSize)
                statisticsDivider
                statisticsCell(item(at: 2), labelSize: labelSize, valueSize: valueSize)
            }
        case .grid:
            VStack(spacing: 0) {
                statisticsRow(Array(items.prefix(2)), labelSize: labelSize, valueSize: valueSize)
                statisticsDivider
                statisticsRow(Array(items.dropFirst(2).prefix(2)), labelSize: labelSize, valueSize: valueSize)
            }
        }
    }

    private var statisticsDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.24))
            .frame(height: 1)
    }

    private func item(at index: Int) -> TimerStatisticDisplayItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    private func statisticsRow(
        _ rowItems: [TimerStatisticDisplayItem],
        labelSize: CGFloat,
        valueSize: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(rowItems) { item in
                statisticsCell(item, labelSize: labelSize, valueSize: valueSize)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func statisticsCell(
        _ item: TimerStatisticDisplayItem?,
        labelSize: CGFloat,
        valueSize: CGFloat
    ) -> some View {
        VStack(spacing: 3) {
            if let item {
                Text(item.title)
                    .font(fontDesign.font(size: labelSize, style: fontStyle))
                    .compatibleFontWidth(fontDesign)
                    .opacity(0.72)
                Text(item.isAvailable && !item.value.isEmpty ? item.value : "—")
                    .font(fontDesign.font(size: valueSize, style: fontStyle))
                    .compatibleFontWidth(fontDesign)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
        }
        .foregroundStyle(textStyle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var textStyle: AnyShapeStyle {
        guard appearance.style != .system else { return AnyShapeStyle(Color.primary) }
        return timerAppearanceShapeStyle(for: appearance, colorScheme: colorScheme)
    }
}

struct TimerStatisticsView: View {
    enum Layout: Equatable {
        case vertical
        case verticalCentered
        case horizontal
        case card
    }

    let items: [TimerStatisticDisplayItem]
    let layout: Layout
    let appearance: AppearanceConfiguration
    let fontDesign: TimerFontDesignOption
    let fontStyle: TimerFontStyleOption
    let fontSize: Double
    let usesAutomaticSize: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if usesAutomaticSize {
            GeometryReader { proxy in
                statisticsContent(
                    size: TimerArrangementLayout.automaticStatisticsFontSize(
                        availableWidth: proxy.size.width,
                        itemCount: items.count,
                        preferredSize: fontSize
                    )
                )
            }
            .frame(minHeight: minimumHeight)
        } else {
            statisticsContent(
                size: TimerArrangementLayout.positiveFinite(CGFloat(fontSize), fallback: 18)
            )
            .frame(minHeight: minimumHeight, alignment: contentAlignment)
        }
    }

    @ViewBuilder
    private func statisticsContent(size: CGFloat) -> some View {
        Group {
            switch layout {
            case .vertical:
                VStack(alignment: .leading, spacing: 5) {
                    metricRows(size: size)
                }
            case .verticalCentered:
                VStack(alignment: .center, spacing: 6) {
                    metricRows(size: size)
                }
            case .horizontal:
                HStack(spacing: 12) {
                    metricRows(size: size)
                }
            case .card:
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 72), spacing: 8)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    metricRows(size: size)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: contentAlignment)
    }

    @ViewBuilder
    private func metricRows(size: CGFloat) -> some View {
        ForEach(items) { item in
            Text("\(item.title): \(item.value)")
                .font(fontDesign.font(size: size, style: fontStyle))
                .compatibleFontWidth(fontDesign)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(textStyle)
        }
    }

    private var minimumHeight: CGFloat {
        let safeFontSize = TimerArrangementLayout.positiveFinite(CGFloat(fontSize), fallback: 18)
        return switch layout {
        case .vertical, .verticalCentered: max(1, CGFloat(items.count)) * safeFontSize * 1.15
        case .horizontal: safeFontSize * 1.35
        case .card: max(44, ceil(CGFloat(items.count) / 2) * 24)
        }
    }

    private var contentAlignment: Alignment {
        switch layout {
        case .vertical, .card: .topLeading
        case .verticalCentered, .horizontal: .center
        }
    }

    private var textStyle: AnyShapeStyle {
        guard appearance.style != .system else { return AnyShapeStyle(Color.secondary) }
        return timerAppearanceShapeStyle(for: appearance, colorScheme: colorScheme)
    }
}

struct TimerCustomizationPreview: View {
    let arrangement: TimerArrangement
    let minimalMode: Bool
    let splitOrder: TimerSplitOrder
    let scramblePosition: Double
    let backgroundAppearance: AppearanceConfiguration
    let backgroundImageData: Data?
    let timerAppearance: AppearanceConfiguration
    let scrambleAppearance: AppearanceConfiguration
    let statisticsAppearance: AppearanceConfiguration
    let timerFontDesign: TimerFontDesignOption
    let timerFontStyle: TimerFontStyleOption
    let timerFontSize: Double
    let scrambleFontDesign: TimerFontDesignOption
    let scrambleFontStyle: TimerFontStyleOption
    let scrambleFontSize: Double
    let statisticsFontDesign: TimerFontDesignOption
    let statisticsFontStyle: TimerFontStyleOption
    let statisticsFontSize: Double
    let numeralPreferences: NumeralPreferencesSnapshot
    let statistics: [TimerStatisticDisplayItem]
    let cardsStatisticsConfiguration: TimerCardsStatisticsConfiguration
    let diagramPlacement: DrawScramblePlacement
    let diagramSize: Double
    let showsNextScrambleButton: Bool
    let streakCount: Int
    let isTodaySolved: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var previewEvent: PuzzleEvent = .threeByThree
    @State private var previewScramble = "R U2 F' L2 D B2 R2 U' F2 D2 L' B U R'"
    @State private var previewTopControlsHeight: CGFloat = 0
    @State private var previewScrambleContentHeight: CGFloat = 0

    private var effectivePresentation: TimerEffectivePresentation {
        TimerEffectivePresentation(arrangement: arrangement, minimalMode: minimalMode)
    }

    var body: some View {
        let viewport = TimerPreviewViewportMetrics.current
        GeometryReader { proxy in
            let availableWidth = TimerArrangementLayout.nonnegativeFinite(proxy.size.width)
            let scale = min(1, availableWidth / viewport.size.width)

            previewCanvas(viewport: viewport)
                .frame(width: viewport.size.width, height: viewport.size.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(
                    width: TimerArrangementLayout.nonnegativeFinite(viewport.size.width * scale),
                    height: TimerArrangementLayout.nonnegativeFinite(viewport.size.height * scale),
                    alignment: .topLeading
                )
        }
        .aspectRatio(
            viewport.size.width / viewport.size.height,
            contentMode: .fit
        )
        .layoutPriority(1)
    }

    private func previewCanvas(viewport: TimerPreviewViewportMetrics) -> some View {
        let size = viewport.size
        let contentFrame = viewport.timerContentFrame

        return ZStack(alignment: .topLeading) {
            previewBackground

            previewTimerContent(size: contentFrame.size)
                .frame(width: contentFrame.width, height: contentFrame.height)
                .position(x: contentFrame.midX, y: contentFrame.midY)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color(.separator).opacity(0.22), lineWidth: 0.5)
        }
    }

    private func previewTimerContent(size: CGSize) -> some View {
        let safeStatisticsFontSize = TimerArrangementLayout.positiveFinite(CGFloat(statisticsFontSize), fallback: 20)
        let safeTimerFontSize = TimerArrangementLayout.positiveFinite(CGFloat(timerFontSize), fallback: 64)
        let statisticsHeight = TimerArrangementLayout.statisticsColumnHeight(
            itemCount: statistics.count,
            fontSize: min(safeStatisticsFontSize, 56)
        )
        let previewPuzzleKey = previewEvent.scrambleDiagramPuzzleKey
        let diagramAspectRatio = TimerArrangementLayout.positiveFinite(
            previewPuzzleKey.map { ScrambleDiagramView.diagramAspectRatio(for: $0) } ?? 1
        )
        let geometry = TimerArrangementLayout.geometry(
            containerSize: size,
            timerVerticalOffset: TimerArrangementLayout.defaultTimerVerticalOffset,
            classicStatisticsHeight: statisticsHeight,
            classicStatisticsOffset: TimerArrangementLayout.classicStatisticsOffset(
                timerFontSize: safeTimerFontSize,
                statisticsFontSize: safeStatisticsFontSize
            ),
            diagramPreferredWidth: CGFloat(diagramSize),
            diagramAspectRatio: diagramAspectRatio
        )
        let timerReservedHeight = TimerArrangementLayout.timerReservedHeight(fontSize: safeTimerFontSize)
        let measuredTopControlsHeight = max(
            TimerArrangementLayout.topControlsMinimumHeight,
            TimerArrangementLayout.nonnegativeFinite(previewTopControlsHeight)
        )
        let scrambleAvailableHeight = TimerArrangementLayout.scrambleAvailableHeight(
            containerHeight: size.height,
            timerVerticalOffset: TimerArrangementLayout.defaultTimerVerticalOffset,
            timerReservedHeight: timerReservedHeight,
            topControlsHeight: measuredTopControlsHeight
        )

        return ZStack {
            VStack(spacing: 0) {
                previewTopControls
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TimerPreviewTopControlsHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                        }
                    }

                previewPositionedScrambleArea(
                    availableHeight: scrambleAvailableHeight,
                    puzzleKey: previewPuzzleKey
                )

                Spacer(minLength: 0)
            }
            .padding(.horizontal, TimerArrangementLayout.timerContentHorizontalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            styledText(
                NumeralPresentation.presentNumericText(
                    "12.34",
                    scope: .timer,
                    preferences: numeralPreferences
                ),
                appearance: timerAppearance,
                design: timerFontDesign,
                style: timerFontStyle,
                size: Double(safeTimerFontSize)
            )
            .monospacedDigit()
            .position(geometry.timerCenter)

            arrangementBottomContent(geometry: geometry, diagramAspectRatio: diagramAspectRatio)
        }
        .onPreferenceChange(TimerPreviewTopControlsHeightPreferenceKey.self) { height in
            previewTopControlsHeight = TimerArrangementLayout.nonnegativeFinite(height)
        }
        .onPreferenceChange(TimerPreviewScrambleHeightPreferenceKey.self) { height in
            previewScrambleContentHeight = min(
                TimerArrangementLayout.nonnegativeFinite(height),
                scrambleAvailableHeight
            )
        }
    }

    private func previewPositionedScrambleArea(
        availableHeight: CGFloat,
        puzzleKey: String?
    ) -> some View {
        let safeAvailableHeight = TimerArrangementLayout.nonnegativeFinite(availableHeight, fallback: 72)
        let safeScrambleFontSize = TimerArrangementLayout.positiveFinite(CGFloat(scrambleFontSize), fallback: 20)
        let measuredContentHeight = max(
            TimerArrangementLayout.nonnegativeFinite(previewScrambleContentHeight),
            TimerArrangementLayout.scrambleContentMinimumHeight
        )
        let top = TimerArrangementLayout.scrambleTop(
            availableHeight: safeAvailableHeight,
            contentHeight: measuredContentHeight,
            normalizedPosition: scramblePosition
        )

        return ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: TimerArrangementLayout.scrambleAccessorySpacing) {
                ScrollView(.vertical, showsIndicators: false) {
                    styledText(
                        previewScramble,
                        appearance: scrambleAppearance,
                        design: scrambleFontDesign,
                        style: scrambleFontStyle,
                        size: Double(min(safeScrambleFontSize, 45))
                    )
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .minimumScaleFactor(0.45)
                    .allowsTightening(true)
                    .padding(.vertical, 1)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TimerPreviewScrambleHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                        }
                    }
                }
                .frame(maxHeight: safeAvailableHeight, alignment: .top)

                VStack(spacing: TimerArrangementLayout.scrambleAccessoryButtonSpacing) {
                    if puzzleKey != nil,
                       effectivePresentation.showsScrambleDiagram,
                       arrangement.allowsIndependentDiagramPlacement,
                       diagramPlacement == .inline {
                        previewCircularButton(systemName: "eye")
                    }
                    if showsNextScrambleButton {
                        previewCircularButton(systemName: "arrow.clockwise")
                    }
                }
            }
            .padding(.top, top)
        }
        .frame(height: safeAvailableHeight, alignment: .top)
    }

    private var previewTopControls: some View {
        ZStack {
            HStack(spacing: 8) {
                previewModeButton
                Spacer()
                previewStreakButton
            }

            TimerEventMenu(selection: $previewEvent, isEnabled: true)
        }
        .padding(.top, TimerArrangementLayout.topControlsTopInset)
        .onChange(of: previewEvent) { event in
            previewScramble = previewScramble(for: event)
            previewScrambleContentHeight = 0
        }
    }

    private var previewModeButton: some View {
        Button(action: {}) {
            HStack(spacing: 6) {
                Image(systemName: LocalBattleMode.solo.iconName)
                    .font(.system(size: 15, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .compatibleGlassFromIOS16(in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var previewStreakButton: some View {
        Button(action: {}) {
            HStack(spacing: 6) {
                Image(isTodaySolved ? "streak_fire_red" : "streak_fire_gray")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .opacity(isTodaySolved ? 1 : 0.7)
                if streakCount > 0 {
                    Text("\(streakCount)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .compatibleGlassFromIOS16(in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func previewCircularButton(systemName: String) -> some View {
        Button(action: {}) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 36)
                .compatibleGlassFromIOS16(in: Circle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func arrangementBottomContent(
        geometry: TimerArrangementLayout.Geometry,
        diagramAspectRatio: CGFloat
    ) -> some View {
        if effectivePresentation.showsStatistics || effectivePresentation.showsScrambleDiagram {
            switch arrangement {
            case .classic:
                if effectivePresentation.showsStatistics {
                    previewStatistics(layout: .verticalCentered, automatic: false)
                        .frame(
                            width: geometry.classicStatisticsFrame.width,
                            height: geometry.classicStatisticsFrame.height
                        )
                        .position(
                            x: geometry.classicStatisticsFrame.midX,
                            y: geometry.classicStatisticsFrame.midY
                        )
                }
                if effectivePresentation.showsScrambleDiagram {
                    independentPreviewDiagram(geometry: geometry, aspectRatio: diagramAspectRatio)
                }

            case .split:
                splitPreview(geometry: geometry, diagramAspectRatio: diagramAspectRatio)

            case .cards:
                if effectivePresentation.showsStatistics {
                    previewCard {
                        TimerCardStatisticsView(
                            items: cardPreviewStatistics,
                            layout: cardsStatisticsConfiguration.layout,
                            appearance: statisticsAppearance,
                            fontDesign: statisticsFontDesign,
                            fontStyle: statisticsFontStyle,
                            preferredFontSize: statisticsFontSize
                        )
                        .padding(TimerArrangementLayout.cardContentInset)
                    }
                    .frame(width: geometry.leadingCardFrame.width, height: geometry.leadingCardFrame.height)
                    .position(x: geometry.leadingCardFrame.midX, y: geometry.leadingCardFrame.midY)
                }

                if effectivePresentation.showsScrambleDiagram {
                    previewCard {
                    let diagramWidth = TimerArrangementLayout.cardDiagramWidth(
                        in: geometry.trailingCardFrame,
                        aspectRatio: diagramAspectRatio
                    )
                    previewDiagram(width: min(diagramWidth, CGFloat(diagramSize)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: geometry.trailingCardFrame.width, height: geometry.trailingCardFrame.height)
                    .position(x: geometry.trailingCardFrame.midX, y: geometry.trailingCardFrame.midY)
                }
            }
        }
    }

    private func splitPreview(
        geometry: TimerArrangementLayout.Geometry,
        diagramAspectRatio: CGFloat
    ) -> some View {
        let statisticsFrame = splitOrder == .statisticsLeading
            ? geometry.splitLeadingFrame
            : geometry.splitTrailingFrame
        let diagramFrame = splitOrder == .statisticsLeading
            ? geometry.splitTrailingFrame
            : geometry.splitLeadingFrame
        let safeAspectRatio = TimerArrangementLayout.positiveFinite(diagramAspectRatio)
        let diagramWidth = min(
            TimerArrangementLayout.nonnegativeFinite(CGFloat(diagramSize)),
            diagramFrame.width,
            diagramFrame.height * safeAspectRatio
        )

        return ZStack {
            if effectivePresentation.showsStatistics {
                previewStatistics(layout: .vertical, automatic: false)
                    .frame(width: statisticsFrame.width, height: statisticsFrame.height, alignment: .bottomLeading)
                    .position(x: statisticsFrame.midX, y: statisticsFrame.midY)
            }

            if effectivePresentation.showsScrambleDiagram {
                previewDiagram(width: diagramWidth)
                    .position(
                        x: diagramFrame.midX,
                        y: diagramFrame.maxY - (diagramWidth / safeAspectRatio) / 2
                    )
            }
        }
    }

    @ViewBuilder
    private func independentPreviewDiagram(
        geometry: TimerArrangementLayout.Geometry,
        aspectRatio: CGFloat
    ) -> some View {
        if diagramPlacement.isFloating {
            let frame = geometry.independentDiagramFrame(placement: diagramPlacement, aspectRatio: aspectRatio)
            previewDiagram(width: frame.width)
                .position(x: frame.midX, y: frame.midY)
        }
    }

    @ViewBuilder
    private func previewDiagram(width: CGFloat) -> some View {
        if let puzzleKey = previewEvent.scrambleDiagramPuzzleKey {
            let aspectRatio = TimerArrangementLayout.positiveFinite(
                ScrambleDiagramView.diagramAspectRatio(for: puzzleKey)
            )
            let safeWidth = TimerArrangementLayout.nonnegativeFinite(width)
            Button(action: {}) {
                ScrambleDiagramView(
                    puzzleKey: puzzleKey,
                    scramble: previewScramble,
                    isInteractive: false
                )
                    .frame(width: safeWidth, height: safeWidth / aspectRatio)
            }
            .buttonStyle(.plain)
        }
    }

    private func previewScramble(for event: PuzzleEvent) -> String {
        TNoodleScrambler.scramble(for: event.previewTNoodleRegistry)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? event.previewFallbackScramble
    }

    private func previewStatistics(
        layout: TimerStatisticsView.Layout,
        automatic: Bool
    ) -> some View {
        TimerStatisticsView(
            items: statistics,
            layout: layout,
            appearance: statisticsAppearance,
            fontDesign: statisticsFontDesign,
            fontStyle: statisticsFontStyle,
            fontSize: statisticsFontSize,
            usesAutomaticSize: automatic
        )
    }

    private var cardPreviewStatistics: [TimerStatisticDisplayItem] {
        let values: [TimerStatisticMetric: String] = [
            .best: "8.91",
            .mo3: "9.86",
            .ao5: "10.24",
            .ao12: "10.71",
            .ao50: "10.93",
            .ao100: "11.18",
            .mean: "10.68",
            .solveCount: "128"
        ]
        return cardsStatisticsConfiguration.positionedMetrics.map { metric in
            TimerStatisticDisplayItem(
                metric: metric,
                title: statistics.first(where: { $0.metric == metric })?.title ?? metric.defaultTitle,
                value: values[metric].map {
                    NumeralPresentation.presentNumericText(
                        $0,
                        scope: .statistics,
                        preferences: numeralPreferences
                    )
                } ?? "—"
            )
        }
    }

    private func previewCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .compatibleGlassFromIOS16(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var previewBackground: some View {
#if canImport(UIKit)
        if backgroundAppearance.style == .photo,
           let backgroundImageData,
           let image = UIImage(data: backgroundImageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            previewBackgroundStyle
        }
#else
        previewBackgroundStyle
#endif
    }

    @ViewBuilder
    private var previewBackgroundStyle: some View {
        switch backgroundAppearance.style {
        case .system, .photo:
            Color(.secondarySystemGroupedBackground)
        case .color:
            backgroundAppearance.color(for: colorScheme)
        case .gradient:
            let gradient = backgroundAppearance.gradient(for: colorScheme)
            LinearGradient(
                gradient: Gradient(stops: gradient.resolvedStops),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func styledText(
        _ value: String,
        appearance: AppearanceConfiguration,
        design: TimerFontDesignOption,
        style: TimerFontStyleOption,
        size: Double
    ) -> some View {
        Text(value)
            .font(design.font(size: size, style: style))
            .compatibleFontWidth(design)
            .foregroundStyle(timerAppearanceShapeStyle(for: appearance, colorScheme: colorScheme))
    }
}

private extension PuzzleEvent {
    var previewTNoodleRegistry: TNoodlePuzzleRegistry {
        switch self {
        case .twoByTwo: .two
        case .threeByThree, .threeByThreeOH, .threeByThreeMBLD: .three
        case .fourByFour, .fourByFourFast: .four
        case .fiveByFive: .five
        case .sixBySix: .six
        case .sevenBySeven: .seven
        case .megaminx: .mega
        case .pyraminx: .pyra
        case .square1: .sq1
        case .clock: .clock
        case .skewb: .skewb
        case .threeByThreeFM: .threeFM
        case .threeByThreeBLD: .threeNI
        case .fourByFourBLD: .fourNI
        case .fiveByFiveBLD: .fiveNI
        }
    }

    var previewFallbackScramble: String {
        switch self {
        case .twoByTwo:
            "R U R' F2 U' R U2"
        case .threeByThree, .threeByThreeOH, .threeByThreeFM, .threeByThreeBLD, .threeByThreeMBLD:
            "R U2 F' L2 D B2 R2 U' F2 D2 L' B U R'"
        case .fourByFour, .fourByFourFast, .fourByFourBLD:
            "Rw U2 Rw' F2 U R2 U' Fw Rw2 D'"
        case .fiveByFive, .fiveByFiveBLD:
            "Rw U2 Rw' F2 Uw R2 Uw' Fw Rw2 D'"
        case .sixBySix:
            "3Rw U2 Rw' F2 Uw R2 3Uw' Fw Rw2 D'"
        case .sevenBySeven:
            "3Rw U2 Rw' F2 3Uw R2 Uw' Fw Rw2 D'"
        case .megaminx:
            "R++ D-- R++ D++ R-- D-- R++ D-- R-- D++ U'"
        case .pyraminx:
            "R U R' L' U B' L U' r'"
        case .square1:
            "(1,0) / (0,3) / (-1,-3) / (3,0) /"
        case .clock:
            "UR1+ DR2+ DL3- UL4+ U1+ R2- D3+ L4- ALL1+ y2 U1+ R2+ D1- L2- ALL3+"
        case .skewb:
            "R U R' L U' B R' B'"
        }
    }
}

func timerAppearanceShapeStyle(
    for configuration: AppearanceConfiguration,
    colorScheme: ColorScheme
) -> AnyShapeStyle {
    switch configuration.style {
    case .system, .photo:
        return AnyShapeStyle(Color.primary)
    case .color:
        return AnyShapeStyle(configuration.color(for: colorScheme))
    case .gradient:
        let gradient = configuration.gradient(for: colorScheme)
        return AnyShapeStyle(
            LinearGradient(
                gradient: Gradient(stops: gradient.resolvedStops),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}
#endif

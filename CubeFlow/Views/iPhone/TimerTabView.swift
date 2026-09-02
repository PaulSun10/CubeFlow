import SwiftUI
import CoreData
#if os(iOS)
import AudioToolbox
import UIKit
#endif

#if os(iOS)
private let solvesDidChangeNotification = Notification.Name("CubeFlowSolvesDidChange")

private struct ScrambleDisplayHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ManualTimeInputHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ManualTimeEntryHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct FloatingScrambleFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private struct TimerTopControlsHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private enum TimerLayoutCoordinateSpace {
    static let name = "TimerTabView.Layout"
}

struct TimerTabView: View {
    #if DEBUG
    private let marketingPreviewConfiguration: MarketingTimerPreviewConfiguration?
    #endif
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.solveTimeAccuracy) private var solveTimeAccuracy
    @ObservedObject private var ganTimer = GANTimerBluetoothManager.shared
    @ObservedObject private var smartCube = SmartCubeBluetoothManager.shared
    @StateObject private var nearbyBattleManager = NearbyBattleManager()
    @FocusState private var isTypingFieldFocused: Bool

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Session.createdAt, ascending: true)],
        animation: .default
    )
    private var sessions: FetchedResults<Session>
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Solve.date, ascending: false)],
        animation: .default
    )
    private var solves: FetchedResults<Solve>

    @AppStorage("selectedSessionID") private var selectedSessionID: String = ""
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("timerBackgroundAppearanceData") private var timerBackgroundAppearanceData: Data?
    @AppStorage("timerTextAppearanceData") private var timerTextAppearanceData: Data?
    @AppStorage("scrambleTextAppearanceData") private var scrambleTextAppearanceData: Data?
    @AppStorage("averageTextAppearanceData") private var averageTextAppearanceData: Data?
    @AppStorage("timerTextFontSize") private var timerTextFontSize: Double = 64
    @AppStorage("scrambleTextFontSize") private var scrambleTextFontSize: Double = 20
    @AppStorage("averageTextFontSize") private var averageTextFontSize: Double = 20
    @AppStorage("timerTextFontDesign") private var timerTextFontDesign: String = TimerFontDesignOption.default.rawValue
    @AppStorage("scrambleTextFontDesign") private var scrambleTextFontDesign: String = TimerFontDesignOption.default.rawValue
    @AppStorage("averageTextFontDesign") private var averageTextFontDesign: String = TimerFontDesignOption.default.rawValue
    @AppStorage("timerTextFontWeight") private var timerTextFontWeight: String = TimerFontWeightOption.semibold.rawValue
    @AppStorage("scrambleTextFontWeight") private var scrambleTextFontWeight: String = TimerFontWeightOption.medium.rawValue
    @AppStorage("averageTextFontWeight") private var averageTextFontWeight: String = TimerFontWeightOption.medium.rawValue
    @AppStorage("wcaInspectionEnabled") private var wcaInspectionEnabled: Bool = false
    @AppStorage("ganInspectionStartsOnPress") private var ganInspectionStartsOnPress: Bool = false
    @AppStorage("ganShowResultPopup") private var ganShowResultPopup: Bool = true
    @AppStorage("ganResultInputMode") private var ganResultInputMode: String = GANResultInputMode.manual.rawValue
    @AppStorage("inspectionAlertVoiceMode") private var inspectionAlertVoiceMode: String = InspectionAlertVoiceMode.off.rawValue
    @AppStorage("averageDisplayOption") private var averageDisplayOption: String = AverageDisplayOption.ao5AndAo12.rawValue
    @AppStorage("timerUpdatingMode") private var timerUpdatingMode: String = "on"
    @AppStorage("enteringTimesWith") private var enteringTimesWith: String = "timer"
    @AppStorage("hideElementsWhenSolving") private var hideElementsWhenSolving: Bool = false
    @AppStorage("scrambleDisplayMode") private var scrambleDisplayMode: String = ScrambleDisplayMode.shrinkFont.rawValue
    @AppStorage("timerBackgroundImageData") private var timerBackgroundImageData: Data?
    @AppStorage("drawScramblePlacement") private var drawScramblePlacement: String = DrawScramblePlacement.inline.rawValue
    @AppStorage("drawScrambleFloatingSize") private var drawScrambleFloatingSize: Double = TimerCustomizationDefaults.drawScrambleSize
    @AppStorage("timerArrangement") private var timerArrangement: String = TimerArrangement.classic.rawValue
    @AppStorage("timerMinimalMode") private var timerMinimalMode: Bool = false
    @AppStorage("timerMinimalArrangementMigrationCompleted") private var timerMinimalArrangementMigrationCompleted: Bool = false
    @AppStorage("timerSplitOrder") private var timerSplitOrder: String = TimerSplitOrder.statisticsLeading.rawValue
    @AppStorage("timerScrambleVerticalPosition") private var timerScrambleVerticalPosition: Double = 0
    @AppStorage("timerStatisticsSelection") private var timerStatisticsSelection: String = ""
    @AppStorage("timerClassicStatisticsSelection") private var timerClassicStatisticsSelection: String = ""
    @AppStorage("timerCardsStatisticsSelection") private var timerCardsStatisticsSelection: String = ""
    @AppStorage("timerCardsTwoStatisticsArrangement") private var timerCardsTwoStatisticsArrangement: String = TimerCardsTwoStatisticArrangement.vertical.rawValue
    @AppStorage("timerCardsThreeStatisticsArrangement") private var timerCardsThreeStatisticsArrangement: String = TimerCardsThreeStatisticArrangement.topEmphasis.rawValue
    @AppStorage("timerCardsStatisticsPositions") private var timerCardsStatisticsPositions: String = ""
    @AppStorage("showNextScrambleButton") private var showNextScrambleButton: Bool = true
    @AppStorage("appNumeralSystem") private var appNumeralSystem = NumeralSystem.systemDefault.rawValue
    @AppStorage("timerNumeralSystem") private var timerNumeralSystem = NumeralPreferenceKeys.inheritedRawValue
    @AppStorage("statisticsNumeralSystem") private var statisticsNumeralSystem = NumeralPreferenceKeys.inheritedRawValue
    @AppStorage("appNumeralChineseFinancial") private var appNumeralChineseFinancial = false
    @AppStorage("timerNumeralChineseFinancial") private var timerNumeralChineseFinancial = false
    @AppStorage("statisticsNumeralChineseFinancial") private var statisticsNumeralChineseFinancial = false
    @AppStorage("appNumeralChineseNumberFormat") private var appNumeralChineseNumberFormat = ChineseNumeralNumberFormat.digits.rawValue
    @AppStorage("timerNumeralChineseNumberFormat") private var timerNumeralChineseNumberFormat = ChineseNumeralNumberFormat.digits.rawValue
    @AppStorage("statisticsNumeralChineseNumberFormat") private var statisticsNumeralChineseNumberFormat = ChineseNumeralNumberFormat.digits.rawValue
    @AppStorage("appNumeralChineseDecimalStyle") private var appNumeralChineseDecimalStyle = ChineseNumeralDecimalStyle.period.rawValue
    @AppStorage("timerNumeralChineseDecimalStyle") private var timerNumeralChineseDecimalStyle = ChineseNumeralDecimalStyle.period.rawValue
    @AppStorage("statisticsNumeralChineseDecimalStyle") private var statisticsNumeralChineseDecimalStyle = ChineseNumeralDecimalStyle.period.rawValue
    @AppStorage("smartCubeFixedView") private var smartCubeFixedViewRawValue = SmartCubeFixedView.urf.rawValue
    @AppStorage("smartCubeReadySound") private var smartCubeReadySound = true

    @State private var selectedEvent: PuzzleEvent = .threeByThree
    @State private var elapsedSeconds: Double = 0
    @State private var isRunning = false
    @State private var timerStartDate: Date?
    @State private var displayTimer: Timer?

    @State private var isPressingToArm = false
    @State private var isReadyToStart = false
    @State private var isInspecting = false
    @State private var inspectionStartDate: Date?
    @State private var inspectionElapsed: Double = 0
    @State private var ganDisplayRefreshDate: Date = .now
    @State private var timerBackgroundAppearance = AppearanceConfiguration.defaultBackground
    @State private var timerTextAppearance = AppearanceConfiguration.defaultTimerText
    @State private var scrambleTextAppearance = AppearanceConfiguration.defaultScrambleText
    @State private var averageTextAppearance = AppearanceConfiguration.defaultAverageText
    @State private var decodedTimerBackgroundImage: UIImage?
    @State private var announcedInspectionCheckpoints: Set<InspectionSpeechCheckpoint> = []
    @State private var currentSolveInspectionPenalty: SolveResult?
    @State private var pendingInspectionPenalty: SolveResult?
    @State private var pendingSolveTime: Double?
    @State private var showingResultPopup = false
    @State private var ganPendingResultSelection: SolveResult = .solved
    @State private var ganResultPressCount: Int = 0
    @State private var ganResultCommitToken = UUID()
    @State private var ganResultCommitProgress: Double = 0
    @State private var currentScramble: String = ""
    @State private var typedTimeInput: String = ""
    @State private var isGenerating2x2 = false
    @State private var scrambleRequestToken = UUID()
    @State private var mblindScrambles: [String] = []
    @State private var mblindScrambleCount: Int = 3
    @State private var showingMblindSheet = false
    @State private var showingMblindCountPicker = false
    @State private var showingScrambleDiagram = false
    @State private var mblindCountSelection: Int = 3
    @State private var sessionStatisticsSnapshot = SessionStatisticsSnapshot.empty
    @State private var solvedDayCountsSnapshot: [Date: Int] = [:]
    @State private var streakCountSnapshot: Int = 0
    @State private var longestStreakSnapshot: Int = 0
    @State private var isTodaySolvedSnapshot: Bool = false
    @State private var keepOverlayTimerVisible = false
    @State private var localBattleMode: LocalBattleMode = .solo
    @State private var localBattleFirstEvent: PuzzleEvent = .threeByThree
    @State private var localBattleSecondEvent: PuzzleEvent = .threeByThree
    @State private var localBattleScrambleCache: [PuzzleEvent: String] = [:]
    @State private var localBattleFirstElapsed: Double = 0
    @State private var localBattleSecondElapsed: Double = 0
    @State private var localBattleFirstStartDate: Date?
    @State private var localBattleSecondStartDate: Date?
    @State private var isLocalBattleFirstRunning = false
    @State private var isLocalBattleSecondRunning = false
    @State private var isLocalBattleFirstPressing = false
    @State private var isLocalBattleSecondPressing = false
    @State private var localBattleDisplayTimer: Timer?
    @State private var localBattleFirstScore = 0
    @State private var localBattleSecondScore = 0
    @State private var localBattleFirstHandicapSeconds = 0
    @State private var localBattleSecondHandicapSeconds = 0
    @State private var localBattleFirstRoundTime: Double?
    @State private var localBattleSecondRoundTime: Double?
    @State private var localBattleFirstDisplayTime: Double?
    @State private var localBattleSecondDisplayTime: Double?
    @State private var didScoreCurrentLocalBattleRound = false
    @State private var scrambleDisplayMeasuredHeight: CGFloat = 0
    @State private var manualTimeInputHeight: CGFloat = 0
    @State private var manualTimeEntryHeight: CGFloat = 0
    @State private var floatingScrambleFrame: CGRect?
    @State private var timerTopControlsHeight: CGFloat = 0
    @State private var smartCubeTargetFacelets: String?
    @State private var smartCubeIsReady = false
    @State private var smartCubeSolveStartMoveIndex = 0

    private let hiddenTimerVerticalOffset = TimerArrangementLayout.defaultTimerVerticalOffset
    private let manualTimeEntrySpacing: CGFloat = 12
    private let ganResultChoices: [SolveResult] = [.solved, .plusTwo, .dnf]
    private let ganResultAutoCommitDelay: TimeInterval = 1.5

    #if DEBUG
    init(marketingPreviewConfiguration: MarketingTimerPreviewConfiguration? = nil) {
        self.marketingPreviewConfiguration = marketingPreviewConfiguration
        _selectedEvent = State(initialValue: marketingPreviewConfiguration?.event ?? .threeByThree)
        _elapsedSeconds = State(initialValue: marketingPreviewConfiguration?.elapsedSeconds ?? 0)
        _currentScramble = State(initialValue: marketingPreviewConfiguration?.scramble ?? "")
    }
    #endif

    private var timerReservedFrameHeight: CGFloat {
        TimerArrangementLayout.timerReservedHeight(
            fontSize: CGFloat(timerTextFontSize)
        )
    }

    private var averageOverlayVerticalOffset: CGFloat {
        TimerArrangementLayout.classicStatisticsOffset(
            timerFontSize: CGFloat(timerTextFontSize),
            statisticsFontSize: CGFloat(resolvedAverageTextFontSize)
        )
    }

    private var resolvedScrambleTextFontSize: Double {
        guard scrambleTextFontSize.isFinite, scrambleTextFontSize > 0 else { return 20 }
        return min(scrambleTextFontSize, 45)
    }

    private var resolvedAverageTextFontSize: Double {
        guard averageTextFontSize.isFinite, averageTextFontSize > 0 else { return 20 }
        return min(averageTextFontSize, 56)
    }

    private var resolvedScrambleDisplayMode: ScrambleDisplayMode {
        ScrambleDisplayMode(rawValue: scrambleDisplayMode) ?? .shrinkFont
    }

    private var timerGestureTopReserveHeight: CGFloat {
        let headerHeight: CGFloat = 146
        guard resolvedScrambleDisplayMode == .scroll else { return headerHeight }
        return headerHeight + scrambleDisplayMeasuredHeight + 12
    }

    private var selectedSession: Session? {
        sessions.first(where: { $0.id.uuidString == selectedSessionID }) ?? sessions.first
    }

    private var selectedSessionEvent: PuzzleEvent {
        guard
            let rawValue = selectedSession?.selectedEventRawValue,
            let event = PuzzleEvent(rawValue: rawValue)
        else {
            return .threeByThree
        }
        return event
    }

    private var mblindScrambleSheet: some View {
        CompatibleNavigationContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(indexedMblindScrambles, id: \.index) { item in
                        Text("\(item.index + 1). \(item.scramble)")
                            .font(.system(size: 16, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(24)
            }
            .navigationTitle(appLocalizedString("timer.mblind.sheet_title", languageCode: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") {
                        showingMblindSheet = false
                    }
                }
            }
        }
        .compatibleLargeSheet()
    }

    private var mblindCountPickerSheet: some View {
        CompatibleNavigationContainer {
            VStack(spacing: 16) {
                Picker("", selection: $mblindCountSelection) {
                    ForEach(1...50, id: \.self) { count in
                        Text(mblindCountLabel(count))
                            .tag(count)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .navigationTitle(appLocalizedString("timer.mblind.count_title", languageCode: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") {
                        mblindScrambleCount = mblindCountSelection
                        showingMblindCountPicker = false
                        generateNewScramble()
                    }
                }
            }
        }
        .compatibleMediumSheet()
    }

    private var mblindCountFormat: String {
        appLocalizedString("timer.mblind.count_format", languageCode: appLanguage)
    }

    private func mblindCountLabel(_ count: Int) -> String {
        String(format: mblindCountFormat, count)
    }

    private var scrambleDisplayLabel: some View {
        configuredText(
            Text(scrambleDisplayText),
            size: resolvedScrambleTextFontSize,
            design: resolvedScrambleTextFontDesign,
            style: resolvedScrambleTextFontStyle
        )
        .id(scrambleDisplayText)
        .foregroundStyle(scrambleTextStyle)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
        .minimumScaleFactor(resolvedScrambleDisplayMode == .shrinkFont ? 0.45 : 1)
        .allowsTightening(resolvedScrambleDisplayMode == .shrinkFont)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var resolvedGANResultInputMode: GANResultInputMode {
        GANResultInputMode(rawValue: ganResultInputMode) ?? .manual
    }

    private var showingStandardResultAlert: Binding<Bool> {
        Binding(
            get: { showingResultPopup && !(enteringTimesWith == "gan" && ganShowResultPopup && resolvedGANResultInputMode == .cycle) },
            set: { newValue in
                if !newValue {
                    showingResultPopup = false
                }
            }
        )
    }

    private var showsGANResultPopup: Bool {
        showingResultPopup
            && enteringTimesWith == "gan"
            && ganShowResultPopup
            && resolvedGANResultInputMode == .cycle
    }

    private var ganResultPopup: some View {
        TimerGANResultPopup(
            pendingSolveTime: pendingSolveTime,
            inputMode: resolvedGANResultInputMode,
            choices: ganResultChoices,
            selectedResult: ganPendingResultSelection,
            commitProgress: ganResultCommitProgress,
            autoCommitDelay: ganResultAutoCommitDelay,
            onSave: savePendingSolve,
            onCancel: discardPendingSolve
        )
    }

    private func circularGlassIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .compatibleGlassFromIOS16(in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var timerTextStyle: AnyShapeStyle {
        if enteringTimesWith == "smartCube", !isRunning, smartCubeIsReady {
            return AnyShapeStyle(Color.green)
        }
        if enteringTimesWith == "gan" && !isRunning {
            if ganTimer.connectionState == .ready {
                return AnyShapeStyle(Color.green)
            }
            if ganTimer.isHandsOn {
                return AnyShapeStyle(Color.red)
            }
        }

        if (isPressingToArm || isReadyToStart) && !isRunning {
            return AnyShapeStyle(Color.green)
        }
        return shapeStyle(for: timerTextAppearance)
    }

    private var scrambleTextStyle: AnyShapeStyle {
        shapeStyle(for: scrambleTextAppearance)
    }

    private var averageTextStyle: AnyShapeStyle {
        if averageTextAppearance.style == .system {
            return AnyShapeStyle(.secondary)
        }
        return shapeStyle(for: averageTextAppearance)
    }

    private var resolvedAverageDisplayOption: AverageDisplayOption {
        AverageDisplayOption(rawValue: averageDisplayOption) ?? .ao5AndAo12
    }

    private var resolvedTimerArrangement: TimerArrangement {
        TimerArrangement.resolved(storedRawValue: timerArrangement)
    }

    private var resolvedTimerSplitOrder: TimerSplitOrder {
        TimerSplitOrder.resolved(
            storedRawValue: timerSplitOrder,
            legacyArrangementRawValue: timerArrangement
        )
    }

    private var effectiveTimerPresentation: TimerEffectivePresentation {
        TimerEffectivePresentation(arrangement: resolvedTimerArrangement, minimalMode: timerMinimalMode)
    }

    private var resolvedDrawScrambleFloatingSize: Double {
        TimerCustomizationDefaults.resolvedDrawScrambleSize(drawScrambleFloatingSize)
    }

    private func migrateTimerArrangementPreferencesIfNeeded() {
        let legacyArrangement = timerArrangement
        let migration = TimerArrangementMigration.resolve(
            storedArrangement: legacyArrangement,
            minimalMode: timerMinimalMode,
            completed: timerMinimalArrangementMigrationCompleted
        )
        let migratedArrangement = migration.arrangement
        let migratedOrder = TimerSplitOrder.resolved(
            storedRawValue: timerSplitOrder,
            legacyArrangementRawValue: legacyArrangement
        )
        if timerArrangement != migratedArrangement.rawValue {
            timerArrangement = migratedArrangement.rawValue
        }
        if timerSplitOrder != migratedOrder.rawValue {
            timerSplitOrder = migratedOrder.rawValue
        }
        if timerMinimalMode != migration.minimalMode {
            timerMinimalMode = migration.minimalMode
        }
        if timerMinimalArrangementMigrationCompleted != migration.completed {
            timerMinimalArrangementMigrationCompleted = migration.completed
        }
        let normalizedPosition = Double(
            TimerArrangementLayout.normalizedScramblePosition(timerScrambleVerticalPosition)
        )
        if timerScrambleVerticalPosition != normalizedPosition {
            timerScrambleVerticalPosition = normalizedPosition
        }
        let normalizedDiagramSize = TimerCustomizationDefaults.resolvedDrawScrambleSize(drawScrambleFloatingSize)
        if drawScrambleFloatingSize != normalizedDiagramSize {
            drawScrambleFloatingSize = normalizedDiagramSize
        }
        let migratedClassicStatistics = TimerStatisticSelection.migratedClassicStoredValue(
            sharedStoredValue: timerStatisticsSelection,
            classicStoredValue: timerClassicStatisticsSelection,
            legacyDisplayOption: resolvedAverageDisplayOption
        )
        if timerClassicStatisticsSelection != migratedClassicStatistics {
            timerClassicStatisticsSelection = migratedClassicStatistics
        }
        let migratedCardsStatistics = TimerStatisticSelection.migratedCardsStoredValue(
            cardsStoredValue: timerCardsStatisticsSelection,
            legacyDisplayOption: resolvedAverageDisplayOption
        )
        if timerCardsStatisticsSelection != migratedCardsStatistics {
            timerCardsStatisticsSelection = migratedCardsStatistics
        }
    }

    private var selectedTimerStatistics: [TimerStatisticMetric] {
        TimerStatisticSelection.resolved(
            arrangement: resolvedTimerArrangement,
            sharedStoredValue: timerStatisticsSelection,
            classicStoredValue: timerClassicStatisticsSelection,
            cardsStoredValue: timerCardsStatisticsSelection,
            legacyDisplayOption: resolvedAverageDisplayOption
        )
    }

    private var resolvedCardsStatisticsConfiguration: TimerCardsStatisticsConfiguration {
        TimerCardsStatisticsConfiguration.resolve(
            selectedMetrics: TimerStatisticSelection.resolved(
                arrangement: .cards,
                sharedStoredValue: timerStatisticsSelection,
                classicStoredValue: timerClassicStatisticsSelection,
                cardsStoredValue: timerCardsStatisticsSelection,
                legacyDisplayOption: resolvedAverageDisplayOption
            ),
            twoArrangement: TimerCardsTwoStatisticArrangement(rawValue: timerCardsTwoStatisticsArrangement) ?? .vertical,
            threeArrangement: TimerCardsThreeStatisticArrangement(rawValue: timerCardsThreeStatisticsArrangement) ?? .topEmphasis,
            positionStore: TimerCardsPositionStore.decode(timerCardsStatisticsPositions)
        )
    }

    private var resolvedArrangementDiagramPlacement: DrawScramblePlacement? {
        effectiveTimerPresentation.resolvedDiagramPlacement(
            from: resolvedDrawScramblePlacement,
            splitOrder: resolvedTimerSplitOrder
        )
    }

    private var showsArrangedDiagram: Bool {
        guard canShowScrambleDiagram, effectiveTimerPresentation.showsScrambleDiagram else { return false }
        switch resolvedTimerArrangement {
        case .classic:
            return resolvedArrangementDiagramPlacement != nil
        case .split, .cards:
            return true
        }
    }

    private var timerText: String {
        _ = ganDisplayRefreshDate
        if enteringTimesWith == "typing" && !isRunning && !isInspecting {
            return ""
        }
        if isInspecting {
            return inspectionDisplayText
        }
        if enteringTimesWith == "gan" {
            return formatDisplayedTime(ganTimer.liveSeconds)
        }
        if isRunning {
            return runningDisplayText
        }
        return formatDisplayedTime(elapsedSeconds)
    }

    private var scrambleDisplayText: String {
        if selectedEvent == .threeByThreeMBLD {
            if mblindScrambles.isEmpty {
                return currentScramble
            }
            if mblindScrambles.count > 3 {
                return String(
                    format: appLocalizedString("timer.mblind.view_all_format", languageCode: appLanguage),
                    mblindScrambles.count
                )
            }
            return mblindScrambles
                .enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n\n")
        }
        return currentScramble
    }

    private var scrambleToSave: String {
        if selectedEvent == .threeByThreeMBLD, !mblindScrambles.isEmpty {
            return mblindScrambles
                .enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
        }
        return currentScramble
    }

    private var solvedDayCounts: [Date: Int] {
        solvedDayCountsSnapshot
    }

    private var solvedDays: Set<Date> {
        Set(solvedDayCounts.keys)
    }

    private var indexedMblindScrambles: [(index: Int, scramble: String)] {
        Array(mblindScrambles.enumerated()).map { (index: $0.offset, scramble: $0.element) }
    }

    private var isTodaySolved: Bool {
        isTodaySolvedSnapshot
    }

    private var streakCount: Int {
        streakCountSnapshot
    }

    private var longestStreak: Int {
        longestStreakSnapshot
    }

    private var timerDecimals: Int {
        solveTimeAccuracy.decimals
    }

    private var numeralPreferencesSnapshot: NumeralPreferencesSnapshot {
        _ = (
            appNumeralSystem,
            timerNumeralSystem,
            statisticsNumeralSystem,
            appNumeralChineseFinancial,
            timerNumeralChineseFinancial,
            statisticsNumeralChineseFinancial,
            appNumeralChineseNumberFormat,
            timerNumeralChineseNumberFormat,
            statisticsNumeralChineseNumberFormat,
            appNumeralChineseDecimalStyle,
            timerNumeralChineseDecimalStyle,
            statisticsNumeralChineseDecimalStyle
        )
        return .load()
    }

    private var resolvedTimerTextFontDesign: TimerFontDesignOption {
        TimerFontDesignOption.resolvedAvailableOption(rawValue: timerTextFontDesign)
    }

    private var resolvedScrambleTextFontDesign: TimerFontDesignOption {
        TimerFontDesignOption.resolvedAvailableOption(rawValue: scrambleTextFontDesign)
    }

    private var resolvedAverageTextFontDesign: TimerFontDesignOption {
        TimerFontDesignOption.resolvedAvailableOption(rawValue: averageTextFontDesign)
    }

    private var resolvedTimerTextFontStyle: TimerFontStyleOption {
        resolvedTimerTextFontDesign.resolvedStyle(
            rawValue: timerTextFontWeight,
            preferredLegacyWeight: .semibold
        )
    }

    private var resolvedScrambleTextFontStyle: TimerFontStyleOption {
        resolvedScrambleTextFontDesign.resolvedStyle(
            rawValue: scrambleTextFontWeight,
            preferredLegacyWeight: .medium
        )
    }

    private var resolvedAverageTextFontStyle: TimerFontStyleOption {
        resolvedAverageTextFontDesign.resolvedStyle(
            rawValue: averageTextFontWeight,
            preferredLegacyWeight: .medium
        )
    }

    private func configuredFont(
        size: Double,
        design: TimerFontDesignOption,
        style: TimerFontStyleOption
    ) -> Font {
        design.font(size: size, style: style)
    }

    @ViewBuilder
    private func configuredText(
        _ text: Text,
        size: Double,
        design: TimerFontDesignOption,
        style: TimerFontStyleOption
    ) -> some View {
        text
            .font(configuredFont(size: size, design: design, style: style))
            .compatibleFontWidth(design)
    }

    private var timerTickInterval: TimeInterval {
        solveTimeAccuracy == .hundredths ? 0.01 : 0.001
    }

    private var shouldHideNonTimerContent: Bool {
        hideElementsWhenSolving && (isRunning || isInspecting)
    }

    private var showsOverlayTimer: Bool {
        shouldHideNonTimerContent || keepOverlayTimerVisible
    }

    private var shouldHideTabBar: Bool {
        shouldHideNonTimerContent || localBattleMode != .solo
    }

    private var runningDisplayText: String {
        switch timerUpdatingMode {
        case "off", "inspectionOnly":
            return appLocalizedString("timer.solving", languageCode: appLanguage)
        case "seconds":
            return NumeralPresentation.formatInteger(
                Int(elapsedSeconds.rounded(.down)),
                scope: .timer,
                preferences: numeralPreferencesSnapshot
            )
        default:
            return formatDisplayedTime(elapsedSeconds)
        }
    }

    private var inspectionDisplayText: String {
        switch timerUpdatingMode {
        case "off":
            return appLocalizedString("timer.inspect", languageCode: appLanguage)
        default:
            if inspectionElapsed >= 17 {
                return appLocalizedString("common.dnf", languageCode: appLanguage)
            }
            if inspectionElapsed > 15 {
                return appLocalizedString("inspection.speech.plus_two", languageCode: appLanguage)
            }
            let remaining = max(0, 15 - inspectionElapsed)
            return NumeralPresentation.formatInteger(
                Int(ceil(remaining)),
                scope: .timer,
                preferences: numeralPreferencesSnapshot
            )
        }
    }

    private var soloTimerContent: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                if !shouldHideNonTimerContent {
                    timerTopControls
                        .background {
                            GeometryReader { controlsProxy in
                                Color.clear.preference(
                                    key: TimerTopControlsHeightPreferenceKey.self,
                                    value: controlsProxy.size.height
                                )
                            }
                        }

                    let availableHeight = TimerArrangementLayout.scrambleAvailableHeight(
                        containerHeight: proxy.size.height,
                        timerVerticalOffset: hiddenTimerVerticalOffset,
                        timerReservedHeight: timerReservedFrameHeight,
                        topControlsHeight: timerTopControlsHeight
                    )
                    positionedScrambleArea(availableHeight: availableHeight)

                    if enteringTimesWith == "smartCube" {
                        smartCubeTimerPanel
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, TimerArrangementLayout.timerContentHorizontalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onPreferenceChange(TimerTopControlsHeightPreferenceKey.self) { height in
            timerTopControlsHeight = height
        }
    }

    private var timerTopControls: some View {
        ZStack {
            HStack {
                localBattleModeMenu
                    .zIndex(10)

                Spacer()

                StreakButton(
                    isTodaySolved: isTodaySolved,
                    streakCount: streakCount,
                    longestStreak: longestStreak,
                    solvedDayCounts: solvedDayCounts,
                    fireRedImageName: "streak_fire_red",
                    fireGrayImageName: "streak_fire_gray"
                )
            }

            eventMenu
        }
        .padding(.top, TimerArrangementLayout.topControlsTopInset)
    }

    private func positionedScrambleArea(availableHeight: CGFloat) -> some View {
        let safeAvailableHeight = TimerArrangementLayout.nonnegativeFinite(availableHeight, fallback: 72)
        let measuredContentHeight = max(
            TimerArrangementLayout.nonnegativeFinite(scrambleDisplayMeasuredHeight),
            TimerArrangementLayout.scrambleContentMinimumHeight
        )
        let top = TimerArrangementLayout.scrambleTop(
            availableHeight: safeAvailableHeight,
            contentHeight: measuredContentHeight,
            normalizedPosition: timerScrambleVerticalPosition
        )

        return ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: TimerArrangementLayout.scrambleAccessorySpacing) {
                scrambleDisplayContainer(maxHeight: safeAvailableHeight)
                    .animation(.snappy(duration: 0.22, extraBounce: 0), value: scrambleDisplayText)

                VStack(spacing: TimerArrangementLayout.scrambleAccessoryButtonSpacing) {
                    if canShowScrambleDiagram,
                       effectiveTimerPresentation.showsScrambleDiagram,
                       resolvedTimerArrangement.allowsIndependentDiagramPlacement,
                       resolvedDrawScramblePlacement == .inline {
                        circularGlassIconButton(systemName: "eye") {
                            showingScrambleDiagram = true
                        }
                    }

                    if showNextScrambleButton {
                        circularGlassIconButton(systemName: "arrow.clockwise") {
                            generateNewScramble()
                        }
                    }

                    if selectedEvent == .threeByThreeMBLD {
                        circularGlassIconButton(systemName: "gearshape") {
                            mblindCountSelection = mblindScrambleCount
                            showingMblindCountPicker = true
                        }
                    }
                }
            }
            .padding(.top, top)
        }
        .frame(height: safeAvailableHeight, alignment: .top)
    }

    private var smartCubeTimerPanel: some View {
        VStack(spacing: 4) {
            SmartCube3DView(
                facelets: smartCube.facelets,
                stateRevision: smartCube.cubeStateRevision,
                fixedView: SmartCubeFixedView(rawValue: smartCubeFixedViewRawValue) ?? .urf
            )
            .frame(height: 180)
            .frame(maxWidth: .infinity)

            Label(smartCubeStatusText, systemImage: smartCubeStatusSymbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(smartCubeIsReady ? .green : .secondary)
        }
        .padding(.top, 2)
    }

    private var smartCubeStatusText: LocalizedStringKey {
        if !smartCube.isConnected { return "smart_cube.timer.disconnected" }
        if isRunning { return "smart_cube.timer.solving" }
        if smartCubeIsReady { return "smart_cube.timer.ready" }
        return "smart_cube.timer.scramble"
    }

    private var smartCubeStatusSymbol: String {
        if !smartCube.isConnected { return "antenna.radiowaves.left.and.right.slash" }
        if isRunning { return "timer" }
        if smartCubeIsReady { return "checkmark.circle.fill" }
        return "arrow.triangle.2.circlepath"
    }

    @ViewBuilder
    private func scrambleDisplayContainer(maxHeight: CGFloat) -> some View {
        let safeMaxHeight = TimerArrangementLayout.nonnegativeFinite(maxHeight)
        ScrollView(.vertical, showsIndicators: resolvedScrambleDisplayMode == .scroll) {
            Group {
                scrambleDisplayButton
            }
            .padding(.vertical, 1)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: ScrambleDisplayHeightPreferenceKey.self, value: proxy.size.height)
                }
            }
        }
        .frame(maxHeight: safeMaxHeight, alignment: .top)
        .onPreferenceChange(ScrambleDisplayHeightPreferenceKey.self) { height in
            scrambleDisplayMeasuredHeight = min(
                TimerArrangementLayout.nonnegativeFinite(height),
                safeMaxHeight
            )
        }
    }

    @ViewBuilder
    private var scrambleDisplayButton: some View {
        if selectedEvent == .threeByThreeMBLD, mblindScrambles.count > 3 {
            Button {
                showingMblindSheet = true
            } label: {
                scrambleDisplayLabel
            }
            .buttonStyle(.plain)
        } else {
            scrambleDisplayLabel
        }
    }

    private var localBattleModeMenu: some View {
        LocalBattleModeMenu(mode: localBattleMode, onSelectMode: setLocalBattleMode)
    }

    private var localBattleContent: some View {
        Group {
            if localBattleMode == .nearby {
                NearbyBattleView(
                    manager: nearbyBattleManager,
                    selectedEvent: selectedEvent,
                    timerTextStyle: timerTextStyle,
                    scrambleTextStyle: scrambleTextStyle,
                    formatDisplayedTime: formatDisplayedTime,
                    generateScramble: { preferredScramble(for: selectedEvent) },
                    onExit: { setLocalBattleMode(.solo) }
                )
            } else {
                LocalBattleContent(
                    mode: localBattleMode,
                    firstEvent: localBattleFirstEvent,
                    secondEvent: localBattleSecondEvent,
                    firstScramble: localBattleScramble(for: .first),
                    secondScramble: localBattleScramble(for: .second),
                    firstElapsed: localBattleElapsed(for: .first),
                    secondElapsed: localBattleElapsed(for: .second),
                    isFirstRunning: isLocalBattleFirstRunning,
                    isSecondRunning: isLocalBattleSecondRunning,
                    isFirstPressing: isLocalBattleFirstPressing,
                    isSecondPressing: isLocalBattleSecondPressing,
                    firstScore: localBattleFirstScore,
                    secondScore: localBattleSecondScore,
                    firstHandicapSeconds: localBattleFirstHandicapSeconds,
                    secondHandicapSeconds: localBattleSecondHandicapSeconds,
                    firstFinishedTime: localBattleFirstDisplayTime,
                    secondFinishedTime: localBattleSecondDisplayTime,
                    timerTextStyle: timerTextStyle,
                    scrambleTextStyle: scrambleTextStyle,
                    formatDisplayedTime: formatDisplayedTime,
                    onExit: { setLocalBattleMode(.solo) },
                    onSelectEvent: setLocalBattleEvent,
                    onSelectHandicap: setLocalBattleHandicap,
                    onPressPlayer: pressLocalBattleTimer,
                    onReleasePlayer: releaseLocalBattleTimer
                )
            }
        }
    }

    var body: some View {
        CompatibleNavigationContainer {
            ZStack {
                timerBackgroundView
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard enteringTimesWith == "typing", isTypingFieldFocused else { return }
                        isTypingFieldFocused = false
                    }

                if localBattleMode == .solo {
                    soloTimerContent
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                } else {
                    localBattleContent
                }

                if localBattleMode == .solo {
                    if enteringTimesWith == "typing" {
                        GeometryReader { proxy in
                            let containerSize = TimerArrangementLayout.sanitizedSize(proxy.size)
                            let contentWidth = TimerArrangementLayout.contentWidth(
                                containerWidth: containerSize.width,
                                horizontalInsets: 48,
                                maximum: 420
                            )
                            manualTimeEntryContent
                                .frame(width: contentWidth)
                                .position(
                                    x: containerSize.width / 2,
                                    y: manualTimeEntryTop(in: proxy) + manualTimeEntryHeight / 2
                                )
                        }
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                    } else {
                        timerArrangementCenterLayer
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                    }
                }

                if localBattleMode == .solo && enteringTimesWith == "timer" {
                    GeometryReader { _ in
                        VStack(spacing: 0) {
                            // Controls and scramble content remain outside the timer hit region.
                            Color.clear
                                .frame(height: timerGestureTopReserveHeight)
                                .allowsHitTesting(false)

                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                                .gesture(startTimerGesture)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }

                if localBattleMode == .solo && !shouldHideNonTimerContent {
                    timerArrangementBottomLayer
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                }

                if localBattleMode == .solo && showsGANResultPopup {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    ganResultPopup
                        .padding(.horizontal, 24)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .coordinateSpace(name: TimerLayoutCoordinateSpace.name)
            .onPreferenceChange(FloatingScrambleFramePreferenceKey.self) { frame in
                floatingScrambleFrame = frame
            }
            .animation(.easeInOut(duration: 0.18), value: showsGANResultPopup)
            .onAppear {
                migrateTimerArrangementPreferencesIfNeeded()
                normalizeUnavailableFontSelections()
                updateTimerAppearances()
                updateTimerBackgroundImage()
            }
            .compatibleNavigationBarHidden()
        }
        .compatibleTabBarVisibility(hidden: shouldHideTabBar)
    .task {
        ensureSessionExists()
        var restoredEvent = synchronizeSelectedSession(idRawValue: selectedSessionID)
        if enteringTimesWith == "smartCube" {
            selectedEvent = .threeByThree
            restoredEvent = .threeByThree
        }
        if enteringTimesWith == "smartCube" {
            refreshSolveSnapshots(for: restoredEvent)
        }
        refreshStreakSnapshots()
        if currentScramble.isEmpty {
            generateNewScramble()
        }
        if enteringTimesWith == "gan" {
            ganTimer.prepareIfNeeded()
        } else if enteringTimesWith == "smartCube" {
            smartCube.prepareIfNeeded()
            prepareSmartCubeScrambleTarget()
        }
    }

        .onChange(of: timerBackgroundAppearanceData) { _ in
            updateTimerBackgroundAppearance()
            updateTimerBackgroundImage()
        }
        .onChange(of: timerTextAppearanceData) { _ in
            updateTimerTextAppearance()
        }
        .onChange(of: scrambleTextAppearanceData) { _ in
            updateScrambleTextAppearance()
        }
        .onChange(of: averageTextAppearanceData) { _ in
            updateAverageTextAppearance()
        }
        .onChange(of: timerBackgroundImageData) { _ in
            updateTimerBackgroundImage()
        }
        .onDisappear {
            invalidateTimer()
            invalidateLocalBattleTimer()
            nearbyBattleManager.stop()
        }
        .onChange(of: enteringTimesWith) { newValue in
            if newValue == "gan" {
                ganTimer.prepareIfNeeded()
            } else if newValue == "smartCube" {
                selectedEvent = .threeByThree
                smartCube.prepareIfNeeded()
                prepareSmartCubeScrambleTarget()
            } else {
                resetSmartCubeTimerState()
            }
        }
        .onChange(of: currentScramble) { _ in
            guard enteringTimesWith == "smartCube" else { return }
            prepareSmartCubeScrambleTarget()
        }
        .onChange(of: smartCube.facelets) { facelets in
            guard enteringTimesWith == "smartCube", let facelets else { return }
            handleSmartCubeFacelets(facelets)
        }
        .onChange(of: smartCube.latestMove) { move in
            guard enteringTimesWith == "smartCube", let move else { return }
            handleSmartCubeMove(move)
        }
        .onChange(of: ganTimer.connectionState) { newValue in
            handleGANTimerStateChange(newValue)
        }
        .onChange(of: ganTimer.completedSolve) { solve in
            guard enteringTimesWith == "gan", let solve else { return }
            handleGANCompletedSolve(seconds: solve.seconds)
        }
        .onChange(of: ganTimer.clearButtonEventID) { eventID in
            guard enteringTimesWith == "gan", eventID != nil else { return }
            handleGANResultSelectionButtonPress()
        }
        .onChange(of: ganTimer.inspectionToggleEventID) { eventID in
            guard enteringTimesWith == "gan", ganInspectionStartsOnPress, eventID != nil else { return }
            handleGANInspectionToggle()
        }
        .onChange(of: selectedEvent) { newEvent in
            floatingScrambleFrame = nil
            if enteringTimesWith == "smartCube", selectedEvent != .threeByThree {
                selectedEvent = .threeByThree
                return
            }
            persistSelectedEventToSession()
            refreshSolveSnapshots(for: newEvent)
            generateNewScramble()
            resetLocalBattleScrambles()
        }
        .onChange(of: timerArrangement) { _ in
            floatingScrambleFrame = nil
        }
        .onChange(of: timerSplitOrder) { _ in
            floatingScrambleFrame = nil
        }
        .onChange(of: drawScramblePlacement) { _ in
            floatingScrambleFrame = nil
        }
        .onChange(of: selectedSessionID) { newSessionID in
            _ = synchronizeSelectedSession(idRawValue: newSessionID)
        }
        .onChange(of: sessions.count) { _ in
            _ = synchronizeSelectedSession(idRawValue: selectedSessionID)
        }
        .onChange(of: solves.count) { _ in
            refreshSolveSnapshots()
            refreshStreakSnapshots()
        }
        .onReceive(NotificationCenter.default.publisher(for: solvesDidChangeNotification)) { _ in
            refreshSolveSnapshots()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CubeFlowSessionsWillDelete"))) { _ in
            sessionStatisticsSnapshot = .empty
        }
        .onChange(of: shouldHideNonTimerContent) { newValue in
            if newValue {
                keepOverlayTimerVisible = true
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    guard !shouldHideNonTimerContent else { return }
                    keepOverlayTimerVisible = false
                }
            }
        }
        .alert("timer.solve_result.title", isPresented: showingStandardResultAlert) {
            Button("common.solved") {
                savePendingSolve(as: .solved)
            }
            Button("+2") {
                savePendingSolve(as: .plusTwo)
            }
            Button("common.dnf") {
                savePendingSolve(as: .dnf)
            }
            Button("common.cancel", role: .cancel) {
                discardPendingSolve()
            }
        } message: {
            Text(SolveMetrics.formatTime(
                pendingSolveTime ?? 0,
                decimals: timerDecimals,
                numeralScope: .timer,
                numeralPreferences: numeralPreferencesSnapshot
            ))
        }
        .sheet(isPresented: $showingMblindSheet) {
            mblindScrambleSheet
        }
        .sheet(isPresented: $showingMblindCountPicker) {
            mblindCountPickerSheet
        }
        .fullScreenCover(isPresented: $showingScrambleDiagram) {
            if let scrambleDiagramPuzzleKey {
                ScrambleDiagramSheet(
                    title: "timer.scramble_diagram",
                    puzzleKey: scrambleDiagramPuzzleKey,
                    scramble: currentScramble,
                    exportAppearance: timerScrambleExportAppearance
                )
            }
        }
        .background(
            SpacebarKeyCommandHandler(
                onSpaceDown: {
                    guard localBattleMode == .solo else { return }
                    armForStartIfNeeded()
                },
                onSpaceUp: {
                    guard localBattleMode == .solo else { return }
                    if isRunning {
                        stopTimerAndSave()
                    } else {
                        releaseToStartIfReady()
                    }
                },
                onSpaceTap: {
                    guard localBattleMode == .solo else { return }
                    handleSpacebarTrigger()
                }
            )
            .frame(width: 0, height: 0)
        )
    }

    private func normalizeUnavailableFontSelections() {
        if resolvedTimerTextFontDesign.rawValue != timerTextFontDesign {
            timerTextFontDesign = resolvedTimerTextFontDesign.rawValue
        }
        if resolvedScrambleTextFontDesign.rawValue != scrambleTextFontDesign {
            scrambleTextFontDesign = resolvedScrambleTextFontDesign.rawValue
        }
        if resolvedAverageTextFontDesign.rawValue != averageTextFontDesign {
            averageTextFontDesign = resolvedAverageTextFontDesign.rawValue
        }
        let timerStyle = resolvedTimerTextFontStyle.id
        let scrambleStyle = resolvedScrambleTextFontStyle.id
        let averageStyle = resolvedAverageTextFontStyle.id
        if timerStyle != timerTextFontWeight { timerTextFontWeight = timerStyle }
        if scrambleStyle != scrambleTextFontWeight { scrambleTextFontWeight = scrambleStyle }
        if averageStyle != averageTextFontWeight { averageTextFontWeight = averageStyle }
    }

// Event selection
    private var eventMenu: some View {
        TimerEventMenu(
            selection: $selectedEvent,
            isEnabled: enteringTimesWith != "smartCube" && !isMarketingPreviewTimer
        )
    }

    private var startTimerGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                armForStartIfNeeded()
            }
            .onEnded { _ in
                if isRunning {
                    stopTimerAndSave()
                } else {
                    releaseToStartIfReady()
                }
            }
    }

    private func armForStartIfNeeded() {
        guard enteringTimesWith == "timer" else { return }
        guard !isRunning, !isPressingToArm else { return }

        isPressingToArm = true
        isReadyToStart = true
        triggerReadyHaptic()
    }

    private func releaseToStartIfReady() {
        guard enteringTimesWith == "timer" else { return }
        guard !isRunning else { return }

        if isReadyToStart {
            if isInspecting {
                startTimer()
            } else if wcaInspectionEnabled {
                startInspection()
            } else {
                startTimer()
            }
        }

        isPressingToArm = false
        isReadyToStart = false
    }

    private func startInspection() {
        guard !isRunning, !isInspecting else { return }

        inspectionElapsed = 0
        inspectionStartDate = .now
        isInspecting = true
        announcedInspectionCheckpoints.removeAll()
        currentSolveInspectionPenalty = nil
        startDisplayTimer()
    }

    private func startTimer() {
        guard !isRunning else { return }

        if isInspecting {
            currentSolveInspectionPenalty = inspectionPenalty(for: inspectionElapsed)
            isInspecting = false
            inspectionStartDate = nil
            inspectionElapsed = 0
        }

        elapsedSeconds = 0
        timerStartDate = .now
        isRunning = true

        startDisplayTimer()
    }

    private func stopTimerAndSave() {
        guard isRunning else { return }

        invalidateTimer()
        isRunning = false
        isPressingToArm = false
        isReadyToStart = false

        guard elapsedSeconds > 0 else { return }
        pendingSolveTime = elapsedSeconds
        pendingInspectionPenalty = currentSolveInspectionPenalty
        showingResultPopup = true
    }

    private func prepareSmartCubeScrambleTarget() {
        smartCubeTargetFacelets = SmartCubeBluetoothManager.facelets(afterApplying: currentScramble)
        smartCubeIsReady = smartCube.facelets == smartCubeTargetFacelets
        smartCubeSolveStartMoveIndex = smartCube.moveHistory.count
    }

    private func handleSmartCubeFacelets(_ facelets: String) {
        if isRunning {
            guard facelets == SmartCubeBluetoothManager.solvedFacelets else { return }
            finishSmartCubeSolve()
            return
        }

        guard let smartCubeTargetFacelets else {
            smartCubeIsReady = false
            return
        }
        let wasReady = smartCubeIsReady
        smartCubeIsReady = facelets == smartCubeTargetFacelets
        if smartCubeIsReady, !wasReady {
            smartCubeSolveStartMoveIndex = smartCube.moveHistory.count
            if smartCubeReadySound {
                AudioServicesPlaySystemSound(1104)
            }
        }
    }

    private func handleSmartCubeMove(_ move: SmartCubeMoveEvent) {
        guard smartCubeIsReady, !isRunning, !showingResultPopup else { return }
        smartCubeIsReady = false
        smartCubeSolveStartMoveIndex = max(smartCube.moveHistory.count - 1, 0)
        elapsedSeconds = 0
        timerStartDate = move.localTimestamp
        isRunning = true
        startDisplayTimer()
    }

    private func finishSmartCubeSolve() {
        guard isRunning, let timerStartDate else { return }
        let finishDate = smartCube.latestMove?.localTimestamp ?? .now
        let duration = finishDate.timeIntervalSince(timerStartDate)
        invalidateTimer()
        isRunning = false
        guard duration > 0 else { return }
        elapsedSeconds = duration
        pendingSolveTime = duration
        pendingInspectionPenalty = nil
        currentSolveInspectionPenalty = nil
        showingResultPopup = true
    }

    private func resetSmartCubeTimerState() {
        smartCubeTargetFacelets = nil
        smartCubeIsReady = false
        smartCubeSolveStartMoveIndex = 0
    }

    private func handleGANTimerStateChange(_ state: GANTimerConnectionState) {
        guard enteringTimesWith == "gan" else { return }

        switch state {
        case .handsOn:
            if !isRunning && !isInspecting {
                isPressingToArm = true
                isReadyToStart = false
            }
        case .ready:
            if !isRunning && !isInspecting && !isReadyToStart {
                triggerReadyHaptic()
            }
            if !isRunning && !isInspecting {
                isPressingToArm = true
                isReadyToStart = true
            }
        case .running:
            if isInspecting {
                currentSolveInspectionPenalty = inspectionPenalty(for: inspectionElapsed)
                isInspecting = false
                inspectionStartDate = nil
                inspectionElapsed = 0
            }
            isPressingToArm = false
            isReadyToStart = false
            isRunning = true
            startDisplayTimer()
        case .connected, .finished, .disconnected, .bluetoothUnavailable, .unauthorized, .scanning, .connecting, .failed:
            if !showingResultPopup {
                isRunning = false
            }
            if !isInspecting {
                isPressingToArm = false
                isReadyToStart = false
            }
            if !isRunning && !isInspecting {
                invalidateTimer()
            }
        }
    }

    private func handleGANCompletedSolve(seconds: Double) {
        invalidateTimer()
        isRunning = false
        isPressingToArm = false
        isReadyToStart = false

        guard seconds > 0 else { return }
        pendingSolveTime = seconds
        pendingInspectionPenalty = nil
        currentSolveInspectionPenalty = nil
        ganPendingResultSelection = .solved
        ganResultPressCount = 0
        ganResultCommitToken = UUID()
        ganResultCommitProgress = 0
        showingResultPopup = ganShowResultPopup

        if ganShowResultPopup && resolvedGANResultInputMode == .cycle {
            scheduleGANResultCommit(after: ganResultAutoCommitDelay)
        }
    }

    private func handleGANInspectionToggle() {
        guard !isRunning, !showingResultPopup else { return }

        if isInspecting {
            isInspecting = false
            inspectionStartDate = nil
            inspectionElapsed = 0
            announcedInspectionCheckpoints = []
            currentSolveInspectionPenalty = nil
        } else {
            startInspection()
        }
    }

    private func handleGANResultSelectionButtonPress() {
        guard enteringTimesWith == "gan", pendingSolveTime != nil, !isRunning else { return }

        let currentIndex = ganResultChoices.firstIndex(of: ganPendingResultSelection) ?? 0
        let nextIndex = (currentIndex + 1) % ganResultChoices.count
        ganPendingResultSelection = ganResultChoices[nextIndex]
        ganResultPressCount += 1

        scheduleGANResultCommit(after: ganResultAutoCommitDelay)
    }

    private func scheduleGANResultCommit(after delay: TimeInterval) {
        let token = UUID()
        ganResultCommitToken = token
        ganResultCommitProgress = 0

        DispatchQueue.main.async {
            withAnimation(.linear(duration: delay)) {
                ganResultCommitProgress = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard ganResultCommitToken == token, pendingSolveTime != nil else { return }
            savePendingSolve(as: ganPendingResultSelection)
        }
    }

    private func savePendingSolve(as result: SolveResult) {
        guard let selectedSession, let pendingSolveTime, pendingSolveTime > 0 else {
            discardPendingSolve()
            return
        }

        let finalResult: SolveResult
        switch pendingInspectionPenalty {
        case .dnf:
            finalResult = .dnf
        case .plusTwo:
            finalResult = result == .dnf ? .dnf : .plusTwo
        default:
            finalResult = result
        }

        _ = Solve(
            time: pendingSolveTime,
            date: .now,
            scramble: scrambleToSave,
            event: selectedEvent.rawValue,
            result: finalResult,
            session: selectedSession,
            context: modelContext
        )
        persistSolveChangesAndRefresh()
        generateNewScramble()
        discardPendingSolve()
    }

    private func discardPendingSolve() {
        ganResultCommitToken = UUID()
        ganResultPressCount = 0
        ganPendingResultSelection = .solved
        ganResultCommitProgress = 0
        pendingSolveTime = nil
        pendingInspectionPenalty = nil
        currentSolveInspectionPenalty = nil
        showingResultPopup = false
    }

    private func invalidateTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
        timerStartDate = nil
        inspectionStartDate = nil
    }

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: timerTickInterval, repeats: true) { _ in
            if let inspectionStartDate, isInspecting {
                inspectionElapsed = Date().timeIntervalSince(inspectionStartDate)
                announceInspectionCheckpointsIfNeeded()
            }
            if enteringTimesWith == "gan", isRunning {
                ganDisplayRefreshDate = .now
            }
            if let timerStartDate, isRunning {
                elapsedSeconds = Date().timeIntervalSince(timerStartDate)
            }
            if !isRunning && !isInspecting {
                displayTimer?.invalidate()
                displayTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func setLocalBattleMode(_ mode: LocalBattleMode) {
        guard localBattleMode != mode else { return }

        updateOrientation(for: mode)

        if localBattleMode == .nearby, mode != .nearby {
            nearbyBattleManager.stop()
        }

        if mode == .solo {
            resetLocalBattleTimers()
            resetLocalBattleScores()
        } else {
            if localBattleMode == .solo {
                isTypingFieldFocused = false
                isPressingToArm = false
                isReadyToStart = false
            }
            resetLocalBattleTimers()
            resetLocalBattleScores()
            if mode == .nearby {
                nearbyBattleManager.stop()
            } else {
                resetLocalBattleEvents()
                resetLocalBattleScrambles()
            }
        }

        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
            localBattleMode = mode
        }
    }

    private func updateOrientation(for mode: LocalBattleMode) {
        switch mode {
        case .headToHead:
            AppOrientationManager.set(.portrait, preferredOrientation: .portrait)
        case .sideBySide:
            AppOrientationManager.set(.landscape, preferredOrientation: .landscapeRight)
        case .solo, .nearby:
            AppOrientationManager.reset()
        }
    }

    private func resetLocalBattleScrambles() {
        localBattleScrambleCache.removeAll()
        _ = localBattleScramble(for: .first)
        _ = localBattleScramble(for: .second)
    }

    private func resetLocalBattleEvents() {
        localBattleFirstEvent = selectedEvent
        localBattleSecondEvent = selectedEvent
    }

    private func localBattleScramble(for player: LocalBattlePlayer) -> String {
        localBattleScramble(for: localBattleEvent(for: player))
    }

    private func localBattleScramble(for event: PuzzleEvent) -> String {
        if let scramble = localBattleScrambleCache[event] {
            return scramble
        }

        let scramble = preferredScramble(for: event)
        localBattleScrambleCache[event] = scramble
        return scramble
    }

    private func localBattleEvent(for player: LocalBattlePlayer) -> PuzzleEvent {
        switch player {
        case .first:
            return localBattleFirstEvent
        case .second:
            return localBattleSecondEvent
        }
    }

    private func setLocalBattleEvent(for player: LocalBattlePlayer, event: PuzzleEvent) {
        guard !localBattleIsRunning(player),
              !localBattleIsPressing(player)
        else { return }

        if didScoreCurrentLocalBattleRound {
            localBattleScrambleCache.removeAll()
        }

        switch player {
        case .first:
            localBattleFirstEvent = event
        case .second:
            localBattleSecondEvent = event
        }
        _ = localBattleScramble(for: event)
    }

    private func setLocalBattleHandicap(for player: LocalBattlePlayer, seconds: Int) {
        guard !localBattleIsRunning(player),
              !localBattleIsPressing(player)
        else { return }

        let clampedSeconds = min(max(seconds, 0), 10)
        switch player {
        case .first:
            localBattleFirstHandicapSeconds = clampedSeconds
        case .second:
            localBattleSecondHandicapSeconds = clampedSeconds
        }
    }

    private func localBattleElapsed(for player: LocalBattlePlayer) -> Double {
        switch player {
        case .first:
            return localBattleFirstElapsed
        case .second:
            return localBattleSecondElapsed
        }
    }

    private func localBattleIsRunning(_ player: LocalBattlePlayer) -> Bool {
        switch player {
        case .first:
            return isLocalBattleFirstRunning
        case .second:
            return isLocalBattleSecondRunning
        }
    }

    private func localBattleIsPressing(_ player: LocalBattlePlayer) -> Bool {
        switch player {
        case .first:
            return isLocalBattleFirstPressing
        case .second:
            return isLocalBattleSecondPressing
        }
    }

    private func setLocalBattlePressing(_ isPressing: Bool, for player: LocalBattlePlayer) {
        switch player {
        case .first:
            isLocalBattleFirstPressing = isPressing
        case .second:
            isLocalBattleSecondPressing = isPressing
        }
    }

    private func localBattleRoundTime(for player: LocalBattlePlayer) -> Double? {
        switch player {
        case .first:
            return localBattleFirstRoundTime
        case .second:
            return localBattleSecondRoundTime
        }
    }

    private func localBattleHandicapSeconds(for player: LocalBattlePlayer) -> Int {
        switch player {
        case .first:
            return localBattleFirstHandicapSeconds
        case .second:
            return localBattleSecondHandicapSeconds
        }
    }

    private func localBattleOpponent(of player: LocalBattlePlayer) -> LocalBattlePlayer {
        switch player {
        case .first:
            return .second
        case .second:
            return .first
        }
    }

    private func toggleLocalBattleTimer(for player: LocalBattlePlayer) {
        if localBattleIsRunning(player) {
            stopLocalBattleTimer(for: player)
        } else {
            startLocalBattleTimer(for: player)
        }
    }

    private func pressLocalBattleTimer(for player: LocalBattlePlayer) {
        prepareNextLocalBattleRoundIfNeeded()
        guard !localBattleIsRunning(player), localBattleRoundTime(for: player) == nil else { return }
        setLocalBattlePressing(true, for: player)
        triggerReadyHaptic()
    }

    private func releaseLocalBattleTimer(for player: LocalBattlePlayer) {
        if localBattleIsRunning(player) {
            stopLocalBattleTimer(for: player)
            return
        }

        guard localBattleIsPressing(player), localBattleRoundTime(for: player) == nil else { return }
        let opponentPlayer = localBattleOpponent(of: player)
        let opponentCanStart = localBattleIsPressing(opponentPlayer)
            || localBattleIsRunning(opponentPlayer)
            || localBattleRoundTime(for: opponentPlayer) != nil

        setLocalBattlePressing(false, for: player)
        guard opponentCanStart else { return }
        startLocalBattleTimer(for: player)
    }

    private func startLocalBattleTimer(for player: LocalBattlePlayer) {
        prepareNextLocalBattleRoundIfNeeded()
        localBattleFirstDisplayTime = nil
        localBattleSecondDisplayTime = nil

        switch player {
        case .first:
            localBattleFirstElapsed = 0
            localBattleFirstStartDate = .now
            isLocalBattleFirstRunning = true
            localBattleFirstRoundTime = nil
        case .second:
            localBattleSecondElapsed = 0
            localBattleSecondStartDate = .now
            isLocalBattleSecondRunning = true
            localBattleSecondRoundTime = nil
        }
        startLocalBattleDisplayTimerIfNeeded()
    }

    private func stopLocalBattleTimer(for player: LocalBattlePlayer) {
        switch player {
        case .first:
            if let localBattleFirstStartDate {
                localBattleFirstElapsed = Date().timeIntervalSince(localBattleFirstStartDate)
            }
            localBattleFirstRoundTime = localBattleFirstElapsed
            localBattleFirstDisplayTime = localBattleFirstElapsed
            localBattleFirstStartDate = nil
            isLocalBattleFirstRunning = false
            isLocalBattleFirstPressing = false
        case .second:
            if let localBattleSecondStartDate {
                localBattleSecondElapsed = Date().timeIntervalSince(localBattleSecondStartDate)
            }
            localBattleSecondRoundTime = localBattleSecondElapsed
            localBattleSecondDisplayTime = localBattleSecondElapsed
            localBattleSecondStartDate = nil
            isLocalBattleSecondRunning = false
            isLocalBattleSecondPressing = false
        }

        scoreLocalBattleRoundIfReady()

        if !isLocalBattleFirstRunning && !isLocalBattleSecondRunning {
            invalidateLocalBattleTimer()
        }
    }

    private func resetLocalBattleTimers() {
        localBattleFirstElapsed = 0
        localBattleSecondElapsed = 0
        localBattleFirstStartDate = nil
        localBattleSecondStartDate = nil
        isLocalBattleFirstRunning = false
        isLocalBattleSecondRunning = false
        isLocalBattleFirstPressing = false
        isLocalBattleSecondPressing = false
        localBattleFirstRoundTime = nil
        localBattleSecondRoundTime = nil
        localBattleFirstDisplayTime = nil
        localBattleSecondDisplayTime = nil
        didScoreCurrentLocalBattleRound = false
        invalidateLocalBattleTimer()
    }

    private func resetLocalBattleScores() {
        localBattleFirstScore = 0
        localBattleSecondScore = 0
    }

    private func prepareNextLocalBattleRoundIfNeeded() {
        guard didScoreCurrentLocalBattleRound else { return }
        localBattleFirstRoundTime = nil
        localBattleSecondRoundTime = nil
        isLocalBattleFirstPressing = false
        isLocalBattleSecondPressing = false
        resetLocalBattleScrambles()
        didScoreCurrentLocalBattleRound = false
    }

    private func scoreLocalBattleRoundIfReady() {
        guard !didScoreCurrentLocalBattleRound,
              let firstTime = localBattleFirstRoundTime,
              let secondTime = localBattleSecondRoundTime
        else { return }

        let adjustedFirstTime = max(0, firstTime - Double(localBattleHandicapSeconds(for: .second)))
        let adjustedSecondTime = max(0, secondTime - Double(localBattleHandicapSeconds(for: .first)))

        if adjustedFirstTime < adjustedSecondTime {
            localBattleFirstScore += 1
        } else if adjustedSecondTime < adjustedFirstTime {
            localBattleSecondScore += 1
        }
        didScoreCurrentLocalBattleRound = true
    }

    private func startLocalBattleDisplayTimerIfNeeded() {
        guard localBattleDisplayTimer == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: timerTickInterval, repeats: true) { _ in
            if let localBattleFirstStartDate, isLocalBattleFirstRunning {
                localBattleFirstElapsed = Date().timeIntervalSince(localBattleFirstStartDate)
            }
            if let localBattleSecondStartDate, isLocalBattleSecondRunning {
                localBattleSecondElapsed = Date().timeIntervalSince(localBattleSecondStartDate)
            }
            if !isLocalBattleFirstRunning && !isLocalBattleSecondRunning {
                localBattleDisplayTimer?.invalidate()
                localBattleDisplayTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        localBattleDisplayTimer = timer
    }

    private func invalidateLocalBattleTimer() {
        localBattleDisplayTimer?.invalidate()
        localBattleDisplayTimer = nil
    }

    private func inspectionPenalty(for elapsed: Double) -> SolveResult? {
        if elapsed >= 17 {
            return .dnf
        }
        if elapsed > 15 {
            return .plusTwo
        }
        return nil
    }

    private var statisticsDisplayItems: [TimerStatisticDisplayItem] {
        selectedTimerStatistics.map(statisticDisplayItem(for:))
    }

    private var cardStatisticsDisplayItems: [TimerStatisticDisplayItem] {
        resolvedCardsStatisticsConfiguration.positionedMetrics.map(statisticDisplayItem(for:))
    }

    private var averageDisplayView: some View {
        statisticsDisplayView(layout: .vertical, automaticSize: false)
    }

    private func statisticsDisplayView(
        layout: TimerStatisticsView.Layout,
        automaticSize: Bool
    ) -> some View {
        TimerStatisticsView(
            items: statisticsDisplayItems,
            layout: layout,
            appearance: averageTextAppearance,
            fontDesign: resolvedAverageTextFontDesign,
            fontStyle: resolvedAverageTextFontStyle,
            fontSize: resolvedAverageTextFontSize,
            usesAutomaticSize: automaticSize
        )
    }

    private func statisticDisplayItem(for metric: TimerStatisticMetric) -> TimerStatisticDisplayItem {
        let presentation: (value: String, isAvailable: Bool)
        switch metric {
        case .mean:
            presentation = formattedAveragePresentation(sessionStatisticsSnapshot.mean)
        case .best:
            presentation = formattedAveragePresentation(sessionStatisticsSnapshot.best)
        case .mo3:
            presentation = formattedAveragePresentation(sessionStatisticsSnapshot.currentAverage(for: .mo3))
        case .ao5:
            presentation = formattedAveragePresentation(sessionStatisticsSnapshot.currentAverage(for: .ao5))
        case .ao12:
            presentation = formattedAveragePresentation(sessionStatisticsSnapshot.currentAverage(for: .ao12))
        case .ao50:
            presentation = formattedAveragePresentation(sessionStatisticsSnapshot.currentAverage(for: .ao50))
        case .ao100:
            presentation = formattedAveragePresentation(sessionStatisticsSnapshot.currentAverage(for: .ao100))
        case .solveCount:
            presentation = (
                NumeralPresentation.formatInteger(
                    sessionStatisticsSnapshot.solveCount,
                    scope: .statistics,
                    preferences: numeralPreferencesSnapshot
                ),
                true
            )
        }

        return TimerStatisticDisplayItem(
            metric: metric,
            title: appLocalizedString(
                metric.localizedKey,
                languageCode: appLanguage,
                defaultValue: metric.defaultTitle
            ),
            value: presentation.value,
            isAvailable: presentation.isAvailable
        )
    }

    private func formattedAveragePresentation(_ value: Double?) -> (value: String, isAvailable: Bool) {
        (
            SolveMetrics.formatAverage(
                value,
                decimals: timerDecimals,
                numeralScope: .statistics,
                numeralPreferences: numeralPreferencesSnapshot
            ),
            value != nil
        )
    }

    private func formatDisplayedTime(_ seconds: Double) -> String {
        SolveMetrics.formatTime(
            seconds,
            decimals: timerDecimals,
            numeralScope: .timer,
            numeralPreferences: numeralPreferencesSnapshot
        )
    }

    private func announceInspectionCheckpointsIfNeeded() {
        guard isInspecting else { return }
        guard inspectionAlertVoiceMode != InspectionAlertVoiceMode.off.rawValue else { return }

        if inspectionElapsed >= 8, !announcedInspectionCheckpoints.contains(.eight) {
            announcedInspectionCheckpoints.insert(.eight)
            InspectionSpeechManager.shared.speakCheckpoint(.eight, languageCode: appLanguage, voiceMode: inspectionAlertVoiceMode)
        }

        if inspectionElapsed >= 12, !announcedInspectionCheckpoints.contains(.twelve) {
            announcedInspectionCheckpoints.insert(.twelve)
            InspectionSpeechManager.shared.speakCheckpoint(.twelve, languageCode: appLanguage, voiceMode: inspectionAlertVoiceMode)
        }

        if inspectionElapsed > 15, !announcedInspectionCheckpoints.contains(.plusTwo) {
            announcedInspectionCheckpoints.insert(.plusTwo)
            InspectionSpeechManager.shared.speakCheckpoint(.plusTwo, languageCode: appLanguage, voiceMode: inspectionAlertVoiceMode)
        }

        if inspectionElapsed >= 17, !announcedInspectionCheckpoints.contains(.dnf) {
            announcedInspectionCheckpoints.insert(.dnf)
            InspectionSpeechManager.shared.speakCheckpoint(.dnf, languageCode: appLanguage, voiceMode: inspectionAlertVoiceMode)
        }
    }

    private func parseTypedTime(_ input: String) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":").map(String.init)
            guard parts.count <= 3 else { return nil }
            let secondsPart = Double(parts.last ?? "") ?? -1
            guard secondsPart >= 0 else { return nil }

            if parts.count == 2, let minutes = Double(parts[0]) {
                return minutes * 60 + secondsPart
            }
            if parts.count == 3,
               let hours = Double(parts[0]),
               let minutes = Double(parts[1]) {
                return hours * 3600 + minutes * 60 + secondsPart
            }
            return nil
        }

        return Double(trimmed)
    }

    @ViewBuilder
    private var timerDisplayView: some View {
        if enteringTimesWith == "typing" {
            manualTimeInputField
        } else {
            configuredText(
                Text(timerText),
                size: timerTextFontSize,
                design: resolvedTimerTextFontDesign,
                style: resolvedTimerTextFontStyle
            )
                .monospacedDigit()
                .foregroundStyle(timerTextStyle)
                .contentShape(Rectangle())
        }
    }

    private var timerArrangementCenterLayer: some View {
        GeometryReader { proxy in
            let geometry = timerArrangementGeometry(for: proxy.size)

            timerDisplayView
                .position(geometry.timerCenter)

            if !shouldHideNonTimerContent,
               resolvedTimerArrangement == .classic,
               effectiveTimerPresentation.showsStatistics,
               !statisticsDisplayItems.isEmpty {
                statisticsDisplayView(layout: .verticalCentered, automaticSize: false)
                    .frame(
                        width: geometry.classicStatisticsFrame.width,
                        height: geometry.classicStatisticsFrame.height
                    )
                    .position(
                        x: geometry.classicStatisticsFrame.midX,
                        y: geometry.classicStatisticsFrame.midY
                    )
            }
        }
    }

    @ViewBuilder
    private var timerArrangementBottomLayer: some View {
        GeometryReader { proxy in
            let geometry = timerArrangementGeometry(for: proxy.size)
            switch resolvedTimerArrangement {
            case .classic:
                if let placement = resolvedArrangementDiagramPlacement,
                   canShowScrambleDiagram,
                   effectiveTimerPresentation.showsScrambleDiagram {
                    independentDiagramLayer(placement: placement, geometry: geometry)
                }

            case .split:
                splitBottomLayer(geometry: geometry)

            case .cards:
                cardsBottomLayer(geometry: geometry)
            }
        }
        .transition(.opacity)
    }

    private func independentDiagramLayer(
        placement: DrawScramblePlacement,
        geometry: TimerArrangementLayout.Geometry
    ) -> some View {
        let frame = geometry.independentDiagramFrame(
            placement: placement,
            aspectRatio: resolvedScrambleDiagramAspectRatio
        )
        return floatingScrambleDiagram(width: frame.width)
            .position(x: frame.midX, y: frame.midY)
    }

    private func splitBottomLayer(geometry: TimerArrangementLayout.Geometry) -> some View {
        let statisticsFrame = resolvedTimerSplitOrder == .statisticsLeading
            ? geometry.splitLeadingFrame
            : geometry.splitTrailingFrame
        let diagramFrame = resolvedTimerSplitOrder == .statisticsLeading
            ? geometry.splitTrailingFrame
            : geometry.splitLeadingFrame
        let diagramWidth = min(
            TimerArrangementLayout.nonnegativeFinite(CGFloat(resolvedDrawScrambleFloatingSize)),
            diagramFrame.width,
            diagramFrame.height * resolvedScrambleDiagramAspectRatio
        )

        return ZStack {
            if effectiveTimerPresentation.showsStatistics {
                splitStatistics(width: statisticsFrame.width, height: statisticsFrame.height)
                    .position(x: statisticsFrame.midX, y: statisticsFrame.midY)
            }

            if effectiveTimerPresentation.showsScrambleDiagram {
                arrangedDiagram(width: diagramWidth)
                    .position(
                        x: diagramFrame.midX,
                        y: diagramFrame.maxY - (diagramWidth / resolvedScrambleDiagramAspectRatio) / 2
                    )
            }
        }
    }

    private func cardsBottomLayer(geometry: TimerArrangementLayout.Geometry) -> some View {
        let statisticsFrame = geometry.leadingCardFrame
        let diagramFrame = geometry.trailingCardFrame
        let diagramWidth = TimerArrangementLayout.cardDiagramWidth(
            in: diagramFrame,
            aspectRatio: resolvedScrambleDiagramAspectRatio
        )

        return ZStack {
            if effectiveTimerPresentation.showsStatistics {
                TimerCardStatisticsView(
                    items: cardStatisticsDisplayItems,
                    layout: resolvedCardsStatisticsConfiguration.layout,
                    appearance: averageTextAppearance,
                    fontDesign: resolvedAverageTextFontDesign,
                    fontStyle: resolvedAverageTextFontStyle,
                    preferredFontSize: resolvedAverageTextFontSize
                )
                .padding(TimerArrangementLayout.cardContentInset)
                .frame(width: statisticsFrame.width, height: statisticsFrame.height)
                .compatibleGlassFromIOS16(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .position(x: statisticsFrame.midX, y: statisticsFrame.midY)
            }

            if effectiveTimerPresentation.showsScrambleDiagram {
                arrangedDiagram(width: min(diagramWidth, CGFloat(resolvedDrawScrambleFloatingSize)))
                    .frame(width: diagramFrame.width, height: diagramFrame.height)
                    .compatibleGlassFromIOS16(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .position(x: diagramFrame.midX, y: diagramFrame.midY)
            }
        }
    }

    @ViewBuilder
    private func splitStatistics(width: CGFloat, height: CGFloat) -> some View {
        if effectiveTimerPresentation.showsStatistics, !statisticsDisplayItems.isEmpty {
            statisticsDisplayView(layout: .vertical, automaticSize: false)
                .frame(width: width, height: height, alignment: .bottomLeading)
        }
    }

    @ViewBuilder
    private func arrangedDiagram(width: CGFloat) -> some View {
        if canShowScrambleDiagram {
            floatingScrambleDiagram(width: width)
        }
    }

    private var statisticsColumnHeight: CGFloat {
        TimerArrangementLayout.statisticsColumnHeight(
            itemCount: statisticsDisplayItems.count,
            fontSize: CGFloat(resolvedAverageTextFontSize)
        )
    }

    private var resolvedScrambleDiagramAspectRatio: CGFloat {
        guard let scrambleDiagramPuzzleKey else { return 1 }
        return TimerArrangementLayout.positiveFinite(
            ScrambleDiagramView.diagramAspectRatio(for: scrambleDiagramPuzzleKey)
        )
    }

    private func timerArrangementGeometry(for size: CGSize) -> TimerArrangementLayout.Geometry {
        TimerArrangementLayout.geometry(
            containerSize: size,
            timerVerticalOffset: hiddenTimerVerticalOffset,
            classicStatisticsHeight: statisticsColumnHeight,
            classicStatisticsOffset: averageOverlayVerticalOffset,
            diagramPreferredWidth: CGFloat(resolvedDrawScrambleFloatingSize),
            diagramAspectRatio: resolvedScrambleDiagramAspectRatio
        )
    }

    private var manualTimeEntryContent: some View {
        VStack(spacing: manualTimeEntrySpacing) {
            manualTimeInputField

            Button("timer.typing_save") {
                saveTypedTime()
            }
            .compatibleProminentButtonFromIOS16(tint: .blue)
            .disabled(parseTypedTime(typedTimeInput) == nil)

            if !shouldHideNonTimerContent,
               effectiveTimerPresentation.showsStatistics,
               !statisticsDisplayItems.isEmpty {
                averageDisplayView
                    .allowsHitTesting(false)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ManualTimeEntryHeightPreferenceKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(ManualTimeEntryHeightPreferenceKey.self) { height in
            manualTimeEntryHeight = height
        }
    }

    private var manualTimeInputField: some View {
        TextField(LocalizedStringKey("timer.typing_placeholder"), text: $typedTimeInput)
            .font(.system(size: 40, weight: .semibold))
            .multilineTextAlignment(.center)
            .keyboardType(.decimalPad)
            .focused($isTypingFieldFocused)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: ManualTimeInputHeightPreferenceKey.self, value: proxy.size.height)
                }
            }
            .onPreferenceChange(ManualTimeInputHeightPreferenceKey.self) { height in
                manualTimeInputHeight = height
            }
    }

    private func manualTimeEntryTop(in proxy: GeometryProxy) -> CGFloat {
        let localOriginY = proxy.frame(in: .named(TimerLayoutCoordinateSpace.name)).minY
        let obstructionMinY: CGFloat? = if showsArrangedDiagram, let floatingScrambleFrame {
            floatingScrambleFrame.minY - localOriginY
        } else {
            nil
        }
        return TimerArrangementLayout.collisionAvoidingGroupTop(
            containerHeight: proxy.size.height,
            groupHeight: manualTimeEntryHeight,
            obstructionMinY: obstructionMinY,
            minimumSpacing: manualTimeEntrySpacing
        )
    }

    private func saveTypedTime() {
        guard let parsed = parseTypedTime(typedTimeInput),
              let selectedSession,
              parsed > 0 else { return }

        _ = Solve(
            time: parsed,
            date: .now,
            scramble: scrambleToSave,
            event: selectedEvent.rawValue,
            result: .solved,
            session: selectedSession,
            context: modelContext
        )
        persistSolveChangesAndRefresh()
        typedTimeInput = ""
        isTypingFieldFocused = false
        generateNewScramble()
    }

    private func persistSolveChangesAndRefresh() {
        try? modelContext.save()
        refreshSolveSnapshots()
        refreshStreakSnapshots()
        NotificationCenter.default.post(name: solvesDidChangeNotification, object: nil)
    }

    private func ensureSessionExists() {
        if sessions.isEmpty {
            let newSession = Session(name: "Session", context: modelContext)
            selectedSessionID = newSession.id.uuidString
            return
        }

        if selectedSession == nil, let firstSession = sessions.first {
            selectedSessionID = firstSession.id.uuidString
        }
    }

    @discardableResult
    private func restoreSelectedEventFromSession() -> PuzzleEvent {
        let restoredEvent = selectedSessionEvent
        if selectedEvent != restoredEvent {
            selectedEvent = restoredEvent
        }
        return restoredEvent
    }

    @discardableResult
    private func synchronizeSelectedSession(idRawValue: String) -> PuzzleEvent {
        guard
            let sessionID = UUID(uuidString: idRawValue),
            let session = sessions.first(where: { $0.id == sessionID })
                ?? (try? modelContext.fetchSession(with: sessionID))
        else {
            let fallbackEvent = restoreSelectedEventFromSession()
            refreshSolveSnapshots(for: fallbackEvent)
            return fallbackEvent
        }

        let sessionEvent = PuzzleEvent(rawValue: session.selectedEventRawValue) ?? .threeByThree
        if selectedEvent != sessionEvent {
            selectedEvent = sessionEvent
        }
        refreshSolveSnapshots(for: sessionEvent, session: session)
        return sessionEvent
    }

    private func persistSelectedEventToSession() {
        guard let selectedSession else { return }
        let rawValue = selectedEvent.rawValue
        guard selectedSession.selectedEventRawValue != rawValue else { return }
        selectedSession.selectedEventRawValue = rawValue
        try? modelContext.save()
    }

    private func refreshSolveSnapshots(
        for _: PuzzleEvent? = nil,
        session explicitSession: Session? = nil
    ) {
        guard let resolvedSession = explicitSession ?? selectedSession else {
            sessionStatisticsSnapshot = .empty
            return
        }

        let sessionSolves = (try? modelContext.fetchSolves(forSessionID: resolvedSession.id))
            ?? solves.filter { $0.session?.id == resolvedSession.id }
        let samples = sessionSolves.map { solve in
            SessionSolveSample(
                id: solve.id,
                date: solve.date,
                time: solve.time,
                resultRaw: solve.resultRaw,
                scramble: solve.scramble,
                comment: solve.comment,
                eventRawValue: solve.event
            )
        }
        sessionStatisticsSnapshot = DataTabComputation.buildSessionStatisticsSnapshot(from: samples)
    }

    private func refreshStreakSnapshots() {
        let calendar = Calendar.current
        let dayCounts = solves.reduce(into: [Date: Int]()) { result, solve in
            let day = calendar.startOfDay(for: solve.date)
            result[day, default: 0] += 1
        }
        solvedDayCountsSnapshot = dayCounts

        let days = Set(dayCounts.keys)
        let today = calendar.startOfDay(for: Date())
        isTodaySolvedSnapshot = (dayCounts[today] ?? 0) > 0

        var streak = 0
        let startDay = days.contains(today)
            ? today
            : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var day = startDay
        while days.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        streakCountSnapshot = streak

        let sortedDays = days.sorted()
        var longest = 0
        var current = 0
        var previousDay: Date?
        for day in sortedDays {
            if let previousDay,
               let nextDay = calendar.date(byAdding: .day, value: 1, to: previousDay),
               calendar.isDate(day, inSameDayAs: nextDay) {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
            previousDay = day
        }
        longestStreakSnapshot = longest
    }

    private func generateNewScramble() {
        #if DEBUG
        if let marketingPreviewConfiguration {
            currentScramble = marketingPreviewConfiguration.scramble
            return
        }
        #endif

        if selectedEvent == .twoByTwo {
            if isGenerating2x2 { return }
            isGenerating2x2 = true
            currentScramble = "…"
            let requestToken = UUID()
            scrambleRequestToken = requestToken
            DispatchQueue.global(qos: .userInitiated).async {
                let scramble = preferredScramble(for: .twoByTwo)
                DispatchQueue.main.async {
                    guard scrambleRequestToken == requestToken else {
                        isGenerating2x2 = false
                        return
                    }
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                        currentScramble = scramble
                    }
                    isGenerating2x2 = false
                }
            }
        } else if selectedEvent == .fourByFour || selectedEvent == .fourByFourFast || selectedEvent == .fourByFourBLD {
            currentScramble = "…"
            let requestToken = UUID()
            scrambleRequestToken = requestToken
            DispatchQueue.global(qos: .userInitiated).async {
                let scramble = preferredScramble(for: selectedEvent)
                DispatchQueue.main.async {
                    guard scrambleRequestToken == requestToken else { return }
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                        currentScramble = scramble
                    }
                }
            }
        } else if selectedEvent == .fiveByFive || selectedEvent == .fiveByFiveBLD {
            currentScramble = "…"
            let requestToken = UUID()
            scrambleRequestToken = requestToken
            DispatchQueue.global(qos: .userInitiated).async {
                let scramble = preferredScramble(for: selectedEvent)
                DispatchQueue.main.async {
                    guard scrambleRequestToken == requestToken else { return }
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                        currentScramble = scramble
                    }
                }
            }
        } else if selectedEvent == .sixBySix {
            currentScramble = "…"
            let requestToken = UUID()
            scrambleRequestToken = requestToken
            DispatchQueue.global(qos: .userInitiated).async {
                let scramble = preferredScramble(for: .sixBySix)
                DispatchQueue.main.async {
                    guard scrambleRequestToken == requestToken else { return }
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                        currentScramble = scramble
                    }
                }
            }
        } else if selectedEvent == .sevenBySeven {
            currentScramble = "…"
            let requestToken = UUID()
            scrambleRequestToken = requestToken
            DispatchQueue.global(qos: .userInitiated).async {
                let scramble = preferredScramble(for: .sevenBySeven)
                DispatchQueue.main.async {
                    guard scrambleRequestToken == requestToken else { return }
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                        currentScramble = scramble
                    }
                }
            }
        } else if selectedEvent == .megaminx {
            currentScramble = "…"
            let requestToken = UUID()
            scrambleRequestToken = requestToken
            DispatchQueue.global(qos: .userInitiated).async {
                let scramble = preferredScramble(for: .megaminx)
                DispatchQueue.main.async {
                    guard scrambleRequestToken == requestToken else { return }
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                        currentScramble = scramble
                    }
                }
            }
        } else if selectedEvent == .pyraminx {
            currentScramble = "…"
            let requestToken = UUID()
            scrambleRequestToken = requestToken
            DispatchQueue.global(qos: .userInitiated).async {
                let scramble = preferredScramble(for: .pyraminx)
                DispatchQueue.main.async {
                    guard scrambleRequestToken == requestToken else { return }
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                        currentScramble = scramble
                    }
                }
            }
        } else if selectedEvent == .clock {
            currentScramble = "…"
            let requestToken = UUID()
            scrambleRequestToken = requestToken
            DispatchQueue.global(qos: .userInitiated).async {
                let scramble = preferredScramble(for: .clock)
                DispatchQueue.main.async {
                    guard scrambleRequestToken == requestToken else { return }
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                        currentScramble = scramble
                    }
                }
            }
        } else if selectedEvent == .skewb {
            currentScramble = "…"
            let requestToken = UUID()
            scrambleRequestToken = requestToken
            DispatchQueue.global(qos: .userInitiated).async {
                let scramble = preferredScramble(for: .skewb)
                DispatchQueue.main.async {
                    guard scrambleRequestToken == requestToken else { return }
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                        currentScramble = scramble
                    }
                }
            }
        } else if selectedEvent == .square1 {
            currentScramble = "…"
            let requestToken = UUID()
            scrambleRequestToken = requestToken
            DispatchQueue.global(qos: .userInitiated).async {
                let scramble = preferredScramble(for: .square1)
                DispatchQueue.main.async {
                    guard scrambleRequestToken == requestToken else { return }
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                        currentScramble = scramble
                    }
                }
            }
        } else if selectedEvent == .threeByThreeMBLD {
            currentScramble = "…"
            mblindScrambles = []
            let requestToken = UUID()
            scrambleRequestToken = requestToken
            let count = max(1, mblindScrambleCount)
            DispatchQueue.global(qos: .userInitiated).async {
                var scrambles: [String] = []
                scrambles.reserveCapacity(count)
                for _ in 0..<count {
                    scrambles.append(preferredScramble(for: .threeByThreeMBLD))
                }
                DispatchQueue.main.async {
                    guard scrambleRequestToken == requestToken else { return }
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                        mblindScrambles = scrambles
                        currentScramble = scrambles.first ?? ""
                    }
                }
            }
        } else {
            currentScramble = "…"
            let requestToken = UUID()
            scrambleRequestToken = requestToken
            DispatchQueue.global(qos: .userInitiated).async {
                let scramble = preferredScramble(for: selectedEvent)
                DispatchQueue.main.async {
                    guard scrambleRequestToken == requestToken else { return }
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                        currentScramble = scramble
                    }
                }
            }
        }
    }

    private var isMarketingPreviewTimer: Bool {
        #if DEBUG
        marketingPreviewConfiguration != nil
        #else
        false
        #endif
    }

    private func preferredScramble(for event: PuzzleEvent) -> String {
        if event == .fourByFourFast {
            return fastFourByFourScramble()
        }

        let registry = tnoodleRegistry(for: event)
        if let scramble = TNoodleScrambler.scramble(for: registry),
           !scramble.isEmpty {
            return scramble
        }

        if let diagnostic = TNoodleScrambler.diagnostic(for: registry) {
            return "\(appLocalizedString("timer.scramble_unavailable", languageCode: appLanguage))\n\(diagnostic)"
        }

        return appLocalizedString("timer.scramble_unavailable", languageCode: appLanguage)
    }

    private func fastFourByFourScramble() -> String {
        let moves: [(notation: String, axis: Int)] = [
            ("R", 0), ("L", 0), ("Rw", 0), ("Lw", 0),
            ("U", 1), ("D", 1), ("Uw", 1), ("Dw", 1),
            ("F", 2), ("B", 2), ("Fw", 2), ("Bw", 2)
        ]
        let suffixes = ["", "'", "2"]
        var generator = SystemRandomNumberGenerator()
        var scramble: [String] = []
        var previousAxis: Int?

        while scramble.count < 40 {
            guard let move = moves.randomElement(using: &generator) else { break }
            guard move.axis != previousAxis else { continue }
            let suffix = suffixes.randomElement(using: &generator) ?? ""
            scramble.append(move.notation + suffix)
            previousAxis = move.axis
        }

        return scramble.joined(separator: " ")
    }

    private func tnoodleRegistry(for event: PuzzleEvent) -> TNoodlePuzzleRegistry {
        switch event {
        case .twoByTwo:
            return .two
        case .threeByThree, .threeByThreeOH, .threeByThreeMBLD:
            return .three
        case .fourByFour, .fourByFourFast:
            return .four
        case .fiveByFive:
            return .five
        case .sixBySix:
            return .six
        case .sevenBySeven:
            return .seven
        case .megaminx:
            return .mega
        case .pyraminx:
            return .pyra
        case .square1:
            return .sq1
        case .clock:
            return .clock
        case .skewb:
            return .skewb
        case .threeByThreeFM:
            return .threeFM
        case .threeByThreeBLD:
            return .threeNI
        case .fourByFourBLD:
            return .fourNI
        case .fiveByFiveBLD:
            return .fiveNI
        }
    }

    private var timerBackgroundView: some View {
        switch timerBackgroundAppearance.style {
        case .system:
            return AnyView(Color.clear)
        case .color:
            return AnyView(timerBackgroundAppearance.color(for: colorScheme))
        case .gradient:
            let gradient = timerBackgroundAppearance.gradient(for: colorScheme)
            return AnyView(
                LinearGradient(
                    gradient: Gradient(stops: gradient.resolvedStops),
                    startPoint: gradientStartPoint(angle: gradient.angle),
                    endPoint: gradientEndPoint(angle: gradient.angle)
                )
            )
        case .photo:
            #if os(iOS)
            if let image = decodedTimerBackgroundImage {
                return AnyView(
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                )
            }
            #endif
            return AnyView(Color.clear)
        }
    }

    private func updateTimerAppearances() {
        updateTimerBackgroundAppearance()
        updateTimerTextAppearance()
        updateScrambleTextAppearance()
        updateAverageTextAppearance()
    }

    private func updateTimerBackgroundAppearance() {
        let decoded = AppearanceConfiguration.decode(from: timerBackgroundAppearanceData, fallback: .defaultBackground)
        if timerBackgroundAppearance != decoded {
            timerBackgroundAppearance = decoded
        }
    }

    private func updateTimerTextAppearance() {
        let decoded = AppearanceConfiguration.decode(from: timerTextAppearanceData, fallback: .defaultTimerText)
        if timerTextAppearance != decoded {
            timerTextAppearance = decoded
        }
    }

    private func updateScrambleTextAppearance() {
        let decoded = AppearanceConfiguration.decode(from: scrambleTextAppearanceData, fallback: .defaultScrambleText)
        if scrambleTextAppearance != decoded {
            scrambleTextAppearance = decoded
        }
    }

    private func updateAverageTextAppearance() {
        let decoded = AppearanceConfiguration.decode(from: averageTextAppearanceData, fallback: .defaultAverageText)
        if averageTextAppearance != decoded {
            averageTextAppearance = decoded
        }
    }

    private func updateTimerBackgroundImage() {
        guard timerBackgroundAppearance.style == .photo,
              let data = timerBackgroundImageData else {
            decodedTimerBackgroundImage = nil
            return
        }

        decodedTimerBackgroundImage = UIImage(data: data)
    }

    private func gradientStartPoint(angle: Double) -> UnitPoint {
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 - cos(radians) * 0.5, y: 0.5 - sin(radians) * 0.5)
    }

    private func gradientEndPoint(angle: Double) -> UnitPoint {
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 + cos(radians) * 0.5, y: 0.5 + sin(radians) * 0.5)
    }

    private func shapeStyle(for configuration: AppearanceConfiguration) -> AnyShapeStyle {
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
                    startPoint: gradientStartPoint(angle: gradient.angle),
                    endPoint: gradientEndPoint(angle: gradient.angle)
                )
            )
        }
    }

    private func triggerReadyHaptic() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
        #endif
    }

    private var scrambleDiagramPuzzleKey: String? {
        selectedEvent.scrambleDiagramPuzzleKey
    }

    private var resolvedDrawScramblePlacement: DrawScramblePlacement {
        DrawScramblePlacement(rawValue: drawScramblePlacement) ?? .inline
    }

    private var canShowScrambleDiagram: Bool {
        guard scrambleDiagramPuzzleKey != nil else { return false }
        guard !currentScramble.isEmpty, currentScramble != "…" else { return false }
        let unavailablePrefix = appLocalizedString("timer.scramble_unavailable", languageCode: appLanguage)
        return !currentScramble.hasPrefix(unavailablePrefix)
    }

    private var drawScrambleButton: some View {
        Button {
            showingScrambleDiagram = true
        } label: {
            Image(systemName: "eye")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .compatibleGlassFromIOS16(in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func floatingScrambleDiagram(width: CGFloat) -> some View {
        let safeWidth = TimerArrangementLayout.nonnegativeFinite(width)
        return Group {
            if let scrambleDiagramPuzzleKey {
                let aspectRatio = TimerArrangementLayout.positiveFinite(
                    ScrambleDiagramView.diagramAspectRatio(for: scrambleDiagramPuzzleKey)
                )
                let height = TimerArrangementLayout.nonnegativeFinite(safeWidth / aspectRatio)
                ScrambleDiagramView(
                    puzzleKey: scrambleDiagramPuzzleKey,
                    scramble: currentScramble,
                    exportAppearance: timerScrambleExportAppearance
                )
                    .frame(width: safeWidth, height: height)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: FloatingScrambleFramePreferenceKey.self,
                                value: proxy.frame(in: .named(TimerLayoutCoordinateSpace.name))
                            )
                        }
                    }
            }
        }
    }

    private var timerScrambleExportAppearance: ScrambleExportAppearance {
        .timer(
            TimerScrambleExportConfiguration(
                backgroundAppearance: timerBackgroundAppearance,
                backgroundImage: decodedTimerBackgroundImage,
                textAppearance: scrambleTextAppearance,
                fontDesign: resolvedScrambleTextFontDesign,
                fontStyle: resolvedScrambleTextFontStyle,
                fontSize: resolvedScrambleTextFontSize,
                colorScheme: colorScheme
            )
        )
    }

    private func handleSpacebarTrigger() {
        guard enteringTimesWith == "timer" else { return }
        if isRunning {
            stopTimerAndSave()
        } else if isInspecting {
            startTimer()
        } else if wcaInspectionEnabled {
            startInspection()
        } else {
            startTimer()
        }
    }
}

#endif

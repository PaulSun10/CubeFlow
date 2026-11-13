import SwiftUI
import CoreData
#if os(iOS)
import Combine
import UIKit
@available(iOS 26.0, *)
private struct TimerInspectionNativeExitButton: UIViewRepresentable {
    let title: String
    let label: String
    let tint: UIColor
    let action: () -> Void
    @Environment(\.layoutDirection) private var layoutDirection

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "timer-inspection-exit"
        button.addAction(UIAction { [weak coordinator = context.coordinator] _ in
            coordinator?.action?()
        }, for: .touchUpInside)
        updateUIView(button, context: context)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
        let direction: UISemanticContentAttribute = layoutDirection == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        if button.semanticContentAttribute != direction { button.semanticContentAttribute = direction }
        if button.tintColor != tint { button.tintColor = tint }
        if button.accessibilityLabel != label { button.accessibilityLabel = label }
        if button.configuration?.title != title {
            var configuration = SessionNativeActionStyle.configuration(tint: tint)
            configuration.title = title
            configuration.cornerStyle = .capsule
            configuration.buttonSize = .small
            configuration.contentInsets = .init(top: 5, leading: 10, bottom: 5, trailing: 10)
            configuration.titleLineBreakMode = .byWordWrapping
            button.configuration = configuration
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        let intrinsic = uiView.intrinsicContentSize
        guard let width = proposal.width, width < intrinsic.width else { return intrinsic }
        return CGSize(width: width, height: uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height)
    }

    final class Coordinator {
        var action: (() -> Void)?
    }
}

#endif

#if os(iOS)
private let solvesDidChangeNotification = Notification.Name("CubeFlowSolvesDidChange")

private struct ScrambleDisplayHeightPreferenceKey: PreferenceKey {
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

private struct TimerRenderedFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

struct TimerExclusionAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct TimerScrambleAreaBottomPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum TimerLayoutCoordinateSpace {
    static let name = "TimerTabView.Layout"
}

private struct PendingWeiPoCombinedStop {
    let id: UUID
    let seconds: Double
    let stoppedAt: Date
}

struct TimerTabView: View {
    let isActive: Bool
    #if DEBUG
    private let marketingPreviewConfiguration: Binding<MarketingTimerPreviewConfiguration>?
    @Environment(\.smartCubeTimerGuidanceProbe) private var guidanceProbe
    @Environment(\.smartCubeCardEntryProbe) private var cardEntryProbe
    @Environment(\.localBattleTestProbe) private var battleProbe
    #endif
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.solveTimeAccuracy) private var solveTimeAccuracy
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    #if DEBUG
    @Environment(\.manualTimeEntryProbe) private var manualProbe
    @Environment(\.appPerformanceProbe) private var performanceProbe
    #endif
    @ScaledMetric(relativeTo: .subheadline) private var minimumSmartCubeStatisticSize: CGFloat = 16
    @ObservedObject private var ganTimer = GANTimerBluetoothManager.shared
    @ObservedObject private var smartCube = SmartCubeBluetoothManager.shared
    @StateObject private var nearbyBattleManager = NearbyBattleManager()
    @FocusState private var isTypingFieldFocused: Bool
    @GestureState private var timerTouchIsActive = false

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
    @AppStorage("manualInputInterface") private var manualInputInterface = ManualInputInterface.keyboard.rawValue
    @AppStorage("manualTimeInterpretation") private var manualInterpretation = ManualTimeInterpretation.fixed.rawValue
    @AppStorage("manualTimeFormat") private var manualFormat = ManualTimeFormat.defaultFormat.rawValue
    @AppStorage("manualSmartDefault") private var manualDefault = ManualTimePrecision.hundredths.rawValue
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
    @AppStorage("hideElementsWhenSolving") private var hideElementsWhenSolving: Bool = true
    @AppStorage("scrambleDisplayMode") private var scrambleDisplayMode: String = ScrambleDisplayMode.shrinkFont.rawValue
    @AppStorage("timerBackgroundImageData") private var timerBackgroundImageData: Data?
    @AppStorage("drawScramblePlacement") private var drawScramblePlacement: String = DrawScramblePlacement.inline.rawValue
    @AppStorage("drawScrambleFloatingSize") private var drawScrambleFloatingSize: Double = TimerCustomizationDefaults.drawScrambleSize
    @AppStorage("timerArrangement") private var timerArrangement: String = TimerArrangement.cards.rawValue
    @AppStorage("timerMinimalMode") private var timerMinimalMode: Bool = false
    @AppStorage("timerMinimalArrangementMigrationCompleted") private var timerMinimalArrangementMigrationCompleted: Bool = false
    @AppStorage("timerSplitOrder") private var timerSplitOrder: String = TimerSplitOrder.statisticsLeading.rawValue
    @AppStorage("timerScrambleVerticalPosition") private var timerScrambleVerticalPosition: Double = TimerCustomizationDefaults.scrambleVerticalPosition
    @AppStorage("timerStatisticsSelection") private var timerStatisticsSelection: String = ""
    @AppStorage("timerClassicStatisticsSelection") private var timerClassicStatisticsSelection: String = ""
    @AppStorage("timerCardsStatisticsSelection") private var timerCardsStatisticsSelection: String = ""
    @AppStorage("timerCardsTwoStatisticsArrangement") private var timerCardsTwoStatisticsArrangement: String = TimerCardsTwoStatisticArrangement.vertical.rawValue
    @AppStorage("timerCardsThreeStatisticsArrangement") private var timerCardsThreeStatisticsArrangement: String = TimerCardsThreeStatisticArrangement.topEmphasis.rawValue
    @AppStorage("timerCardsStatisticsPositions") private var timerCardsStatisticsPositions: String = ""
    @AppStorage("showNextScrambleButton") private var showNextScrambleButton: Bool = true
    @AppStorage("appNumeralSystem") private var appNumeralSystem = NumeralSystem.westernArabic.rawValue
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
    @AppStorage("smartCubeShowVirtualCube") private var smartCubeShowVirtualCube = true
    @AppStorage("smartCubeTimerPosition") private var smartCubeTimerPositionRawValue = SmartCubeTimerPosition.right.rawValue
    @AppStorage("smartCubeTimerLayout") private var smartCubeTimerLayoutRawValue = SmartCubeTimerLayout.centered.rawValue
    @AppStorage("smartCubeCurrentMovePresentation") private var smartCubeCurrentMovePresentationRawValue = SmartCubeCurrentMovePresentation.highlight.rawValue
    @AppStorage("smartCubeHighlightColorMode") private var smartCubeHighlightColorModeRawValue = SmartCubeHighlightColorMode.automatic.rawValue
    @AppStorage("smartCubeHighlightTextMode") private var smartCubeHighlightTextModeRawValue = SmartCubeHighlightColorMode.automatic.rawValue
    @AppStorage("smartCubeHighlightColorData") private var smartCubeHighlightColorData: Data?
    @AppStorage("smartCubeHighlightTextColorData") private var smartCubeHighlightTextColorData: Data?
    @AppStorage("smartCubeCompletedMovesBehavior") private var smartCubeCompletedMovesBehaviorRawValue = SmartCubeCompletedMovesBehavior.collapse.rawValue
    @AppStorage("smartCubeScrambleTransition") private var smartCubeScrambleTransitionRawValue = SmartCubeScrambleTransition.instant.rawValue
    @AppStorage("smartCubeRecoveryDisplay") private var smartCubeRecoveryDisplayRawValue = SmartCubeRecoveryDisplay.inline.rawValue
    @AppStorage("smartCubeHighlightAnimation") private var smartCubeHighlightAnimationRawValue = SmartCubeHighlightAnimation.instant.rawValue

    @State private var selectedEvent: PuzzleEvent = .threeByThree
    @State private var restoredSmartCubeEvent: PuzzleEvent?
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
    @State private var displayedScrambleContext: TimerScrambleGenerationContext?
    @State private var solveSnapshotsNeedRefresh = false
    @State private var scrambleNeedsReplacement = false
    @State private var currentCardsDiagram: ScrambleDiagramSnapshot?
    @State private var manualDraft = ManualTimeDraft()
    @State private var manualReference: Double?
    @State private var scrambleRequestToken = UUID()
    @State private var scramblePrefetchSlot = TimerScramblePrefetchSlot()
    @State private var scramblePrefetchConsumptionToken: UUID?
    @State private var scramblePrefetchConsumptionRequestedAt: TimeInterval?
    @State private var mblindScrambles: [String] = []
    @State private var mblindScrambleCount: Int = 3
    @State private var showingMblindSheet = false
    @State private var showingMblindCountPicker = false
    @State private var mblindCountSelection: Int = 3
    @State private var showingSmartCubeDevicePicker = false
    @State private var smartCubeReadinessTracker = SmartCubeReadinessAnnouncementTracker()
    @State private var timerPBState = TimerPersonalBestState.empty
    @State private var celebrationID: UUID?
    @State private var celebrationGate = TimerPBCelebrationGate()
    @State private var currentResultPB = TimerCurrentResultPBState()
    @State private var sessionStatisticsSnapshot = SessionStatisticsSnapshot.empty
    @State private var solvedDayCountsSnapshot: [Date: Int] = [:]
    @State private var streakCountSnapshot: Int = 0
    @State private var longestStreakSnapshot: Int = 0
    @State private var isTodaySolvedSnapshot: Bool = false
    @State private var keepOverlayTimerVisible = false
    @State private var localBattleMode: LocalBattleMode = .solo
    @State private var localBattleFirstEvent: PuzzleEvent = .threeByThree
    @State private var localBattleSecondEvent: PuzzleEvent = .threeByThree
    @State private var localBattleScrambles = LocalBattleScrambleState()
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
    @State private var localBattleHandicap = LocalBattleHandicap()
    @State private var localBattleFirstRoundTime: Double?
    @State private var localBattleSecondRoundTime: Double?
    @State private var localBattleFirstDisplayTime: Double?
    @State private var localBattleSecondDisplayTime: Double?
    @State private var didScoreCurrentLocalBattleRound = false
    @State private var scrambleDisplayMeasuredHeight: CGFloat = 0
    @State private var showingScrambleDetail = false
    @State private var manualTimeEntryHeight: CGFloat = 0
    @ScaledMetric(relativeTo: .largeTitle) private var manualDisplayHeight: CGFloat = 64
    @State private var pbObstacles: [CGRect] = []
    @State private var pbBannerHeight: CGFloat = 0
    @State private var floatingScrambleFrame: CGRect?
    @State private var timerTopControlsHeight: CGFloat = 0
    @State private var timerRenderedFrame: CGRect?
    @State private var timerScrambleAreaBottom: CGFloat = 0
    @State private var smartCubeScrambleProgress: SmartCubeScrambleProgress?
    @State private var smartCubeScrambleEpoch = SmartCubeScrambleEpoch()
    @State private var smartCubeRecoveryState = SmartCubeRecoveryPresentationState.inactive
    @StateObject private var smartCubeGuidance = SmartCubeGuidanceController()
    @State private var smartCubeGuidanceInForeground = UIApplication.shared.applicationState != .background
    @StateObject private var localBattleDevices = LocalBattleDevices()
    @State private var showingSmartCubeManagement = false
    @State private var managedSmartCubeID: UUID?
    @State private var smartCubeHighlightedTokenIndex: Int?
    @State private var smartCubeSolveLifecycle = SmartCubeSolveLifecycle()
    @State private var smartCubeSolveStartMove: SmartCubeMoveEvent?
    @State private var smartCubeIsReady = false
    @State private var smartCubeTimingWasActive = false
    @State private var reconstructionCapture = SmartCubeReconstructionCapture()
    @State private var combinedSolveLifecycle = CombinedSolveLifecycle()
    @State private var pendingWeiPoCombinedStop: PendingWeiPoCombinedStop?
    @State private var pendingSolveInputSource: SolveInputSource?
    @State private var pendingSolveReconstruction: SolveReconstruction?
    @State private var pendingSolveScramble: String?
    @State private var activeSolveAssignment: TimerSolveAssignment?

    private let hiddenTimerVerticalOffset = TimerArrangementLayout.defaultTimerVerticalOffset
    private let manualTimeEntrySpacing: CGFloat = 12
    private let manualKeypadGap: CGFloat = 8
    private let ganResultChoices: [SolveResult] = [.solved, .plusTwo, .dnf]
    private let ganResultAutoCommitDelay: TimeInterval = 1.5

    #if DEBUG
    init(isActive: Bool = true, marketingPreviewConfiguration: Binding<MarketingTimerPreviewConfiguration>? = nil,
         guidanceController: SmartCubeGuidanceController? = nil) {
        self.isActive = isActive
        self.marketingPreviewConfiguration = marketingPreviewConfiguration
        let previewConfiguration = marketingPreviewConfiguration?.wrappedValue
        _selectedEvent = State(initialValue: previewConfiguration?.event ?? .threeByThree)
        _elapsedSeconds = State(initialValue: previewConfiguration?.elapsedSeconds ?? 0)
        _currentScramble = State(initialValue: previewConfiguration?.scramble ?? "")
        if let guidanceController { _smartCubeGuidance = StateObject(wrappedValue: guidanceController) }
    }
    #else
    init(isActive: Bool = true) {
        self.isActive = isActive
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

    private var selectedSession: Session? {
        sessions.first(where: { $0.id.uuidString == selectedSessionID }) ?? sessions.first
    }

    private var selectedTimingMethod: SessionTimingMethod {
        SessionTimingMethod(rawValue: enteringTimesWith) ?? .timer
    }

    private var usesSmartCubeInput: Bool { selectedTimingMethod.usesSmartCube }
    private var usesGANTimerInput: Bool { selectedTimingMethod.usesGANTimer }
    private var usesCombinedInput: Bool { selectedTimingMethod == .smartCubeAndGAN }
    private var usesWeiPo2NativeVisual: Bool {
        smartCube.connectedProtocol == .moyu && smartCube.puzzleSize == 2
    }

    private var combinedReadiness: CombinedSolveReadiness {
        let observation = smartCube.observationReadiness
        return CombinedSolveReadiness(
            smartCubeConnected: smartCube.isConnected,
            smartCubeObservationReady: observation.isReady
                && smartCubeReadinessTracker.permitsReadiness(observation),
            scrambleVerified: smartCubeScrambleProgress?.isComplete == true,
            smartCubeReady: smartCubeIsReady
                && (!usesWeiPo2NativeVisual || smartCube.weiPo2PendingSnapshotCount == 0),
            smartTimerConnected: ganTimer.isConnected,
            smartTimerReady: ganTimer.isHardwareReadyForStart
        )
    }

    private var smartCubeInputIsReady: Bool {
        usesCombinedInput ? combinedReadiness.isReady : smartCubeIsReady
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

    private var effectiveTimerEvent: PuzzleEvent {
        SmartCubeTimerEventPolicy.effectiveEvent(
            normalEvent: selectedEvent,
            isSmartCubeTiming: usesSmartCubeInput,
            smartCubePuzzleSize: smartCube.isConnected ? smartCube.puzzleSize : (selectedEvent == .twoByTwo ? 2 : 3)
        )
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
        Group {
            if smartCubeConnectionIsLoading {
                Color.clear
                    .frame(height: TimerArrangementLayout.scrambleContentMinimumHeight)
                    .accessibilityHidden(true)
            } else if usesSmartCubeInput, let smartCubeScrambleProgress {
                SmartCubeScrambleProgressView(
                    scramble: currentScramble,
                    tokens: smartCubeScrambleProgress.tokens,
                    completedTokenIndices: smartCubeScrambleProgress.completedTokenIndices,
                    highlightedTokenIndex: resolvedSmartCubeCurrentMovePresentation == .highlight
                        ? smartCubeHighlightedTokenIndex
                        : nil,
                    recoveryPlan: smartCubeRecoveryState.plan ?? smartCubeRecoveryState.fallbackPlan,
                    recoveryDisplay: resolvedSmartCubeRecoveryDisplay,
                    highlightAnimation: resolvedSmartCubeHighlightAnimation,
                    behavior: resolvedSmartCubeCompletedMovesBehavior,
                    transition: resolvedSmartCubeScrambleTransition,
                    fontDesign: resolvedScrambleTextFontDesign,
                    fontStyle: resolvedScrambleTextFontStyle,
                    fontSize: resolvedScrambleTextFontSize,
                    foregroundStyle: scrambleTextStyle,
                    highlightBackgroundStyle: smartCubeCurrentMoveHighlightBackgroundStyle,
                    highlightForegroundStyle: smartCubeCurrentMoveHighlightForegroundStyle,
                    showsLiveProgress: smartCube.isReadyForMoveObservation && !isRunning && !isInspecting,
                    showsStateOnlyProgress: smartCubeScrambleProgress.puzzleSize == 2,
                    isStateOnlyOffPath: smartCubeScrambleProgress.puzzleSize == 2 && smartCubeScrambleProgress.isDeviated,
                    isUpdatingGuidance: smartCubeGuidance.isUpdating && !isRunning && !isInspecting,
                    isGuidanceUnavailable: smartCubeGuidance.phase == .unavailable && !isRunning && !isInspecting,
                    showsInspectionCompletion: canRestartSmartCubeInspection,
                    diagnosticContext: smartCubeGuidanceDiagnosticContext
                )
            } else {
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
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var resolvedGANResultInputMode: GANResultInputMode {
        GANResultInputMode(rawValue: ganResultInputMode) ?? .manual
    }

    private var showingStandardResultAlert: Binding<Bool> {
        Binding(
            get: { showingResultPopup && !(usesGANTimerInput && ganShowResultPopup && resolvedGANResultInputMode == .cycle) },
            set: { newValue in
                if !newValue {
                    showingResultPopup = false
                }
            }
        )
    }

    private var showsGANResultPopup: Bool {
        showingResultPopup
            && usesGANTimerInput
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
        if usesCombinedInput, !isRunning {
            if combinedReadiness.isReady { return AnyShapeStyle(Color.green) }
            if ganTimer.isHandsOn, ganTimer.isConnected, smartCube.isConnected {
                return AnyShapeStyle(Color.red)
            }
            return shapeStyle(for: timerTextAppearance)
        }
        if usesSmartCubeInput, !isRunning, smartCubeIsReady {
            return AnyShapeStyle(Color.green)
        }
        if usesSmartCubeInput, !usesCombinedInput, isInspecting,
           !hideElementsWhenSolving, currentSolveInspectionPenalty != nil {
            return AnyShapeStyle(Color.red)
        }
        if usesGANTimerInput && !isRunning && (!usesCombinedInput || smartCubeIsReady) {
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
        let stored = TimerArrangement.resolved(storedRawValue: timerArrangement)
        return usesInlineManualKeypad && stored == .classic ? .split : stored
    }

    private var usesInlineManualKeypad: Bool {
        enteringTimesWith == "typing" && manualInputInterface == ManualInputInterface.keypad.rawValue
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

    private var resolvedSmartCubeCompletedMovesBehavior: SmartCubeCompletedMovesBehavior {
        SmartCubeCompletedMovesBehavior(rawValue: smartCubeCompletedMovesBehaviorRawValue) ?? .collapse
    }

    private var resolvedSmartCubeCurrentMovePresentation: SmartCubeCurrentMovePresentation {
        SmartCubeCurrentMovePresentation(rawValue: smartCubeCurrentMovePresentationRawValue) ?? .highlight
    }

    private var resolvedSmartCubeHighlightColorMode: SmartCubeHighlightColorMode {
        SmartCubeHighlightColorMode(rawValue: smartCubeHighlightColorModeRawValue) ?? .automatic
    }

    private var resolvedSmartCubeHighlightTextMode: SmartCubeHighlightColorMode {
        SmartCubeHighlightColorMode(rawValue: smartCubeHighlightTextModeRawValue) ?? .automatic
    }

    private var smartCubeCurrentMoveHighlightBackgroundStyle: AnyShapeStyle {
        if resolvedSmartCubeHighlightColorMode == .custom {
            return AnyShapeStyle(smartCubeCustomHighlightBackground.color)
        }
        return scrambleTextStyle
    }

    private var smartCubeCurrentMoveHighlightForegroundStyle: AnyShapeStyle {
        if resolvedSmartCubeHighlightTextMode == .custom {
            return AnyShapeStyle(smartCubeCustomHighlightText.color)
        }
        return AnyShapeStyle(
            SmartCubeHighlightToneResolver
                .contrastingTone(for: smartCubeEffectiveHighlightRepresentativeColor)
                .color
        )
    }

    private var smartCubeCustomHighlightBackground: StoredColorData {
        StoredColorData.decode(
            from: smartCubeHighlightColorData,
            fallback: SmartCubeHighlightColorDefaults.background
        )
    }

    private var smartCubeCustomHighlightText: StoredColorData {
        StoredColorData.decode(
            from: smartCubeHighlightTextColorData,
            fallback: SmartCubeHighlightColorDefaults.text
        )
    }

    private var smartCubeEffectiveHighlightRepresentativeColor: StoredColorData {
        if resolvedSmartCubeHighlightColorMode == .custom {
            return smartCubeCustomHighlightBackground
        }

        switch scrambleTextAppearance.style {
        case .system, .photo:
            return colorScheme == .dark
                ? StoredColorData(r: 1, g: 1, b: 1)
                : StoredColorData(r: 0, g: 0, b: 0)
        case .color:
            return colorScheme == .dark
                ? scrambleTextAppearance.darkColor.sanitized()
                : scrambleTextAppearance.lightColor.sanitized()
        case .gradient:
            let stops = scrambleTextAppearance.gradient(for: colorScheme).sanitized().stops
            guard !stops.isEmpty else {
                return colorScheme == .dark
                    ? StoredColorData(r: 1, g: 1, b: 1)
                    : StoredColorData(r: 0, g: 0, b: 0)
            }
            let count = Double(stops.count)
            return StoredColorData(
                r: stops.reduce(0) { $0 + $1.r } / count,
                g: stops.reduce(0) { $0 + $1.g } / count,
                b: stops.reduce(0) { $0 + $1.b } / count
            )
        }
    }

    private var resolvedSmartCubeScrambleTransition: SmartCubeScrambleTransition {
        SmartCubeScrambleTransition.resolved(
            storedRawValue: smartCubeScrambleTransitionRawValue,
            behavior: resolvedSmartCubeCompletedMovesBehavior
        )
    }

    private var resolvedSmartCubeRecoveryDisplay: SmartCubeRecoveryDisplay {
        SmartCubeRecoveryDisplay.resolved(smartCubeRecoveryDisplayRawValue)
    }

    private var resolvedSmartCubeHighlightAnimation: SmartCubeHighlightAnimation {
        SmartCubeHighlightAnimation(rawValue: smartCubeHighlightAnimationRawValue) ?? .animated
    }

    private var resolvedSmartCubeTimerPosition: SmartCubeTimerPosition {
        SmartCubeTimerPosition(rawValue: smartCubeTimerPositionRawValue) ?? .right
    }

    private var resolvedSmartCubeTimerLayout: SmartCubeTimerLayout {
        SmartCubeTimerLayout(rawValue: smartCubeTimerLayoutRawValue) ?? .centered
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
        #if DEBUG
        if let previewConfiguration = marketingPreviewConfiguration?.wrappedValue,
           !isRunning,
           !isInspecting {
            return formatDisplayedTime(max(0, previewConfiguration.elapsedSeconds))
        }
        #endif
        if enteringTimesWith == "typing" && !isRunning && !isInspecting {
            return ""
        }
        if isInspecting {
            return inspectionDisplayText
        }
        if usesGANTimerInput {
            return formatDisplayedTime(ganTimer.liveSeconds)
        }
        if isRunning {
            return runningDisplayText
        }
        return formatDisplayedTime(elapsedSeconds)
    }

    private var scrambleDisplayText: String {
        if effectiveTimerEvent == .threeByThreeMBLD {
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
        if effectiveTimerEvent == .threeByThreeMBLD, !mblindScrambles.isEmpty {
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
            return formatDisplayedTime(elapsedSeconds, decimals: 0)
        default:
            return formatDisplayedTime(elapsedSeconds)
        }
    }

    private var inspectionDisplayText: String {
        switch InspectionPenaltyPolicy.penalty(for: inspectionElapsed) {
        case .dnf: return appLocalizedString("common.dnf", languageCode: appLanguage)
        case .plusTwo: return appLocalizedString("inspection.speech.plus_two", languageCode: appLanguage)
        default: break
        }
        if usesSmartCubeInput && !usesCombinedInput {
            return NumeralPresentation.formatInteger(
                Int(floor(inspectionElapsed)), scope: .timer, preferences: numeralPreferencesSnapshot
            )
        }
        if timerUpdatingMode == "off" {
            return appLocalizedString("timer.inspect", languageCode: appLanguage)
        }
        return NumeralPresentation.formatInteger(
            Int(ceil(max(0, 15 - inspectionElapsed))), scope: .timer, preferences: numeralPreferencesSnapshot
        )
    }

    private func soloTimerContent(exclusionTop: CGFloat? = nil, shrinkTimerTop: CGFloat? = nil) -> some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                if !shouldHideNonTimerContent {
                    VStack(spacing: 8) {
                        timerTopControls
                    }
                    .background {
                        GeometryReader { controlsProxy in
                            Color.clear.preference(
                                key: TimerTopControlsHeightPreferenceKey.self,
                                value: controlsProxy.size.height
                            )
                        }
                    }

                    let estimatedHeight = TimerArrangementLayout.scrambleAvailableHeight(
                        containerHeight: proxy.size.height,
                        timerVerticalOffset: hiddenTimerVerticalOffset,
                        timerReservedHeight: timerReservedFrameHeight,
                        topControlsHeight: timerTopControlsHeight
                    )
                    let availableHeight = !usesSmartCubeInput ? (exclusionTop ?? timerRenderedFrame?.minY).map { top in
                        TimerArrangementLayout.measuredScrambleAvailableHeight(
                            timerTop: top,
                            scrambleTop: proxy.frame(in: .named(TimerLayoutCoordinateSpace.name)).minY + timerTopControlsHeight
                        )
                    } ?? estimatedHeight : estimatedHeight
                    positionedScrambleArea(availableHeight: availableHeight, shrinkTimerTop: shrinkTimerTop)

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
                    .timerHeaderInteractiveRegion()
                    .zIndex(10)

                timerInputModeMenu
                    .timerHeaderInteractiveRegion()
                    .accessibilityIdentifier("timer-input-menu")
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
                .timerHeaderInteractiveRegion()
            }

            eventMenu
                .timerHeaderInteractiveRegion()
                .accessibilityIdentifier("timer-event-menu")
        }
        .padding(.top, TimerArrangementLayout.topControlsTopInset)
    }

    private var timerInputModeMenu: some View {
        Menu {
            ForEach(SessionTimingMethod.allCases) { mode in
                Button {
                    enteringTimesWith = mode.rawValue
                } label: {
                    if mode == selectedTimingMethod {
                        Label(timingMethodLocalizedKey(mode), systemImage: "checkmark")
                    } else {
                        Text(timingMethodLocalizedKey(mode))
                    }
                }
            }
        } label: {
            Image(systemName: "stopwatch")
                .font(.system(size: 14, weight: .semibold))
                .padding(10)
                .compatibleGlassFromIOS16(in: Circle())
        }
        .accessibilityLabel(timingMethodLocalizedKey(selectedTimingMethod))
    }

    private func timingMethodLocalizedKey(_ mode: SessionTimingMethod) -> LocalizedStringKey {
        switch mode {
        case .timer: "settings.entering_times_timer"
        case .typing: "settings.entering_times_typing"
        case .gan: "settings.entering_times_gan"
        case .smartCube: "settings.entering_times_smart_cube"
        case .smartCubeAndGAN: "settings.entering_times_smart_cube_and_gan"
        }
    }

    @ViewBuilder
    private func positionedScrambleArea(availableHeight: CGFloat, shrinkTimerTop: CGFloat? = nil) -> some View {
        if resolvedScrambleDisplayMode == .scroll && !usesSmartCubeInput {
            TimerScrambleScrollViewport(
                availableHeight: availableHeight,
                timerTop: usesInlineManualKeypad ? nil : timerRenderedFrame?.minY,
                coordinateSpace: TimerLayoutCoordinateSpace.name
            ) { height in
                positionedScrambleContent(availableHeight: height)
            }
        } else if resolvedScrambleDisplayMode == .shrinkFont && !usesSmartCubeInput {
            TimerScrambleShrinkViewport(
                availableHeight: availableHeight,
                timerTop: usesInlineManualKeypad ? nil : shrinkTimerTop ?? timerRenderedFrame?.minY,
                coordinateSpace: TimerLayoutCoordinateSpace.name
            ) { height in
                positionedScrambleContent(availableHeight: height)
            }
        } else {
            positionedScrambleContent(availableHeight: availableHeight)
        }
    }

    private func positionedScrambleContent(availableHeight: CGFloat) -> some View {
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
                scrambleDisplayContainer(maxHeight: TimerArrangementLayout.scrollViewportHeight(
                    availableHeight: safeAvailableHeight, topOffset: top
                ))
                    .animation(.snappy(duration: 0.22, extraBounce: 0), value: scrambleDisplayText)

                VStack(spacing: TimerArrangementLayout.scrambleAccessoryButtonSpacing) {
                    if showNextScrambleButton {
                        TimerScrambleRefreshButton {
                            generateNewScramble()
                        }
                        .timerHeaderInteractiveRegion()
                        .accessibilityIdentifier("timer-next-scramble")
                        .disabled(isRunning || pendingSolveTime != nil)
                    }

                    if effectiveTimerEvent == .threeByThreeMBLD {
                        circularGlassIconButton(systemName: "gearshape") {
                            mblindCountSelection = mblindScrambleCount
                            showingMblindCountPicker = true
                        }
                        .timerHeaderInteractiveRegion()
                    }
                }
            }
            .padding(.top, top)
            .background {
                GeometryReader { areaProxy in
                    Color.clear.preference(
                        key: TimerScrambleAreaBottomPreferenceKey.self,
                        value: areaProxy.frame(in: .named(TimerLayoutCoordinateSpace.name)).maxY
                    )
                }
            }
        }
        .frame(height: safeAvailableHeight, alignment: .top)
        #if DEBUG
        .background {
            if manualProbe != nil { GeometryReader { proxy in Color.clear.preference(key: ManualEntryFrameKey.self,
                value: ["scramble": proxy.frame(in: .global)]) } }
        }
        #endif
    }

    private var smartCubeConnectionIsLoading: Bool {
        usesSmartCubeInput
            && SmartCubeTimerConnectionPresentation.resolve(
                readiness: smartCube.observationReadiness,
                isAttemptApproved: smartCubeReadinessTracker.permitsReadiness(
                    smartCube.observationReadiness
                ),
                connectionState: smartCube.connectionState
            ) == .loading
    }

    private var showsSmartCubeReadyStatus: Bool {
        guard !isRunning, !isInspecting else { return false }
        if usesCombinedInput { return combinedReadiness.isReady }
        let observation = smartCube.observationReadiness
        return smartCubeIsReady && smartCubeScrambleProgress?.isComplete == true
            && observation.isReady && smartCubeReadinessTracker.permitsReadiness(observation)
    }

    private var hasVerifiedSmartCubeInspectionTarget: Bool {
        let readiness = smartCube.observationReadiness
        return readiness.isReady && smartCubeReadinessTracker.permitsReadiness(readiness)
            && displayedScrambleMatchesSelection && !scrambleNeedsReplacement
            && smartCubeScrambleProgress?.puzzleSize == smartCube.puzzleSize
            && smartCubeScrambleProgress?.isVerifiedComplete(at: smartCube.facelets) == true
    }

    private var canRestartSmartCubeInspection: Bool {
        guard isActive, localBattleMode == .solo, usesSmartCubeInput, !usesCombinedInput, wcaInspectionEnabled,
              !isRunning, !isInspecting, !showingResultPopup, !showingSmartCubeManagement else { return false }
        return smartCubeScrambleEpoch.canRestartInspection(
            attemptID: smartCube.connectionAttemptID,
            targetVerified: hasVerifiedSmartCubeInspectionTarget,
            lifecycle: smartCubeSolveLifecycle
        )
    }

    private func restartSmartCubeInspection() {
        guard canRestartSmartCubeInspection else { return }
        // Recheck after consuming any moves delivered before this tap.
        consumePendingSmartCubeUpdates()
        guard canRestartSmartCubeInspection,
              smartCubeScrambleEpoch.restartInspection(
                attemptID: smartCube.connectionAttemptID,
                targetVerified: hasVerifiedSmartCubeInspectionTarget,
                latestMoveID: smartCube.latestMove?.id,
                lifecycle: &smartCubeSolveLifecycle
              ) == .beginInspection else { return }
        startInspection()
    }

    @ViewBuilder
    private func scrambleDisplayContainer(maxHeight: CGFloat) -> some View {
        let safeMaxHeight = TimerArrangementLayout.nonnegativeFinite(maxHeight)
        Group {
            if resolvedScrambleDisplayMode == .shrinkFont && !usesSmartCubeInput {
                if effectiveTimerEvent == .threeByThreeMBLD, mblindScrambles.count > 3 {
                    Button { showingMblindSheet = true } label: { fittingScrambleText }
                        .buttonStyle(.plain)
                } else {
                    fittingScrambleText
                }
            } else {
                ScrollView(.vertical, showsIndicators: resolvedScrambleDisplayMode == .scroll) {
                    scrambleDisplayButton
                        .timerHeaderInteractiveRegion()
                        .accessibilityIdentifier("timer-scramble-control")
                        .padding(.vertical, 1)
                        .background {
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: ScrambleDisplayHeightPreferenceKey.self, value: proxy.size.height)
                            }
                        }
                }
            }
        }
        .frame(height: safeMaxHeight, alignment: .top)
        .clipped()
        .onPreferenceChange(ScrambleDisplayHeightPreferenceKey.self) { height in
            scrambleDisplayMeasuredHeight = min(
                TimerArrangementLayout.nonnegativeFinite(height),
                safeMaxHeight
            )
        }
    }

    private var fittingScrambleText: some View {
        TimerFittingScrambleText(
            text: scrambleDisplayText, maximumFontSize: resolvedScrambleTextFontSize,
            design: resolvedScrambleTextFontDesign, style: resolvedScrambleTextFontStyle
        ) { size in
            Text(scrambleDisplayText)
                // Render the measured face exactly; custom fonts must not scale twice.
                .font(Font(resolvedScrambleTextFontDesign.uiFont(size: CGFloat(size), style: resolvedScrambleTextFontStyle)))
                .foregroundStyle(scrambleTextStyle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                #if DEBUG
                .background {
                    if manualProbe != nil { GeometryReader { text in Color.clear.preference(key: ManualEntryFrameKey.self,
                        value: ["scramble-text": text.frame(in: .global)]) } }
                }
                #endif
                .contentShape(Rectangle())
                .onTapGesture { showingScrambleDetail = true }
                .timerHeaderInteractiveRegion()
                .accessibilityIdentifier("timer-scramble-control")
        }
    }

    @ViewBuilder
    private var scrambleDisplayButton: some View {
        if effectiveTimerEvent == .threeByThreeMBLD, mblindScrambles.count > 3 {
            Button {
                showingMblindSheet = true
            } label: {
                scrambleDisplayLabel
            }
            .buttonStyle(.plain)
        } else {
            scrambleDisplayLabel
                .contentShape(Rectangle())
                .onTapGesture {
                    if !usesSmartCubeInput { showingScrambleDetail = true }
                }
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
                    firstHandicapSeconds: localBattleHandicap.seconds(for: .first),
                    secondHandicapSeconds: localBattleHandicap.seconds(for: .second),
                    firstFinishedTime: localBattleFirstDisplayTime,
                    secondFinishedTime: localBattleSecondDisplayTime,
                    timerTextStyle: timerTextStyle,
                    scrambleTextStyle: scrambleTextStyle,
                    formatDisplayedTime: formatDisplayedTime,
                    canSelectEvent: { !localBattleIsRunning($0) && !localBattleIsPressing($0) },
                    onExit: { setLocalBattleMode(.solo) },
                    onSelectEvent: setLocalBattleEvent,
                    onSelectHandicap: setLocalBattleHandicap,
                    onPressPlayer: pressLocalBattleTimer,
                    onReleasePlayer: releaseLocalBattleTimer,
                    onCancelPlayer: { setLocalBattlePressing(false, for: $0) },
                    devices: localBattleDevices,
                    onConfigure: { player, configuration in
                        localBattleDevices.setConfiguration(configuration, for: player)
                        if configuration.input == .smartTimer { ganTimer.prepareIfNeeded() }
                    },
                    onManual: submitLocalBattleManual,
                    isRoundComplete: didScoreCurrentLocalBattleRound,
                    canEditHandicap: canEditLocalBattleHandicap
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

                if localBattleMode == .solo && canRestartSmartCubeInspection {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: restartSmartCubeInspection)
                        .accessibilityHidden(true)
                }

                if localBattleMode == .solo {
                    if usesInlineManualKeypad {
                        manualKeypadLayer
                            .ignoresSafeArea(.keyboard, edges: .bottom)
                    } else if enteringTimesWith != "timer" || usesSmartCubeInput {
                        soloTimerContent()
                            .ignoresSafeArea(.keyboard, edges: .bottom)
                    }
                } else {
                    localBattleContent
                }

                if localBattleMode == .solo {
                    if enteringTimesWith == "typing" && !usesInlineManualKeypad {
                        GeometryReader { proxy in
                            let containerSize = TimerArrangementLayout.sanitizedSize(proxy.size)
                            let contentWidth = TimerArrangementLayout.contentWidth(
                                containerWidth: containerSize.width,
                                horizontalInsets: 48,
                                maximum: 420
                            )
                                manualTimeEntryContent()
                                    .frame(width: contentWidth)
                                    .position(x: containerSize.width / 2,
                                              y: manualTimeEntryTop(in: proxy) + manualTimeEntryHeight / 2)
                        }
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                    } else if !usesInlineManualKeypad {
                        timerArrangementCenterLayer
                        .allowsHitTesting(usesSmartCubeInput)
                        .ignoresSafeArea()
                    }
                }

                if localBattleMode == .solo && enteringTimesWith == "timer" {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(startTimerGesture)
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
            .overlayPreferenceValue(TimerExclusionAnchorPreferenceKey.self) { anchor in
                if localBattleMode == .solo && enteringTimesWith == "timer" && !usesSmartCubeInput {
                    GeometryReader { root in
                        if let anchor {
                            let top = root[anchor].minY
                            TimerScrambleExclusionLayer(timerTop: top, usesDynamicHitRegions: enteringTimesWith == "timer") {
                                soloTimerContent(exclusionTop: top,
                                    shrinkTimerTop: root.frame(in: .named(TimerLayoutCoordinateSpace.name)).minY + top)
                            }
                        }
                    }
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                }
            }
            .overlay(alignment: .center) {
                if let resultID = currentResultPB.solveID {
                    GeometryReader { proxy in
                        let bounds = proxy.frame(in: .named(TimerLayoutCoordinateSpace.name))
                        let center = timerRenderedFrame.flatMap { timer in
                            TimerPBPlacement.center(container: bounds, timer: timer,
                                upperBottom: timerScrambleAreaBottom, obstacles: pbObstacles,
                                bannerHeight: pbBannerHeight, aboveTimer: resolvedTimerArrangement == .classic)
                        }
                        TimerPBCelebration().id(resultID)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(GeometryReader { banner in
                                Color.clear.preference(key: TimerPBBannerHeightKey.self, value: banner.size.height)
                            })
                            .position(x: (center?.x ?? bounds.midX) - bounds.minX,
                                      y: (center?.y ?? bounds.midY) - bounds.minY)
                            .opacity(center == nil ? 0 : 1)
                            .accessibilityHidden(center == nil)
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                if let celebrationID {
                    TimerPBConfetti {
                        guard self.celebrationID == celebrationID else { return }
                        self.celebrationID = nil
                    }.id(celebrationID)
                        .ignoresSafeArea().allowsHitTesting(false)
                }
            }
            .overlayPreferenceValue(TimerExclusionAnchorPreferenceKey.self, inspectionExitLayer)
            .coordinateSpace(name: TimerLayoutCoordinateSpace.name)
            #if DEBUG
            .onPreferenceChange(ManualEntryFrameKey.self) { manualProbe?.frames = $0 }
            #endif
            .background {
                CompetitionNativePresentation(isPresented: $showingSmartCubeManagement, style: .results) { dismiss in
                    SmartCubeManagementCard(selectedID: managedSmartCubeID, dismiss: dismiss)
                }
            }
            .onChange(of: isRunning) { running in if running { showingSmartCubeManagement = false } }
            .onChange(of: isInspecting) { inspecting in if inspecting { showingSmartCubeManagement = false } }
            .onChange(of: usesSmartCubeInput) { enabled in if !enabled { showingSmartCubeManagement = false } }
            .fullScreenCover(isPresented: $showingScrambleDetail) {
                if let scrambleDiagramPuzzleKey {
                    ScrambleDiagramSheet(title: "timer.scramble_diagram", puzzleKey: scrambleDiagramPuzzleKey,
                        scramble: currentScramble, exportAppearance: timerScrambleExportAppearance)
                }
            }
            .onPreferenceChange(TimerPBObstacleKey.self) { pbObstacles = $0 }
            .onPreferenceChange(TimerPBBannerHeightKey.self) { pbBannerHeight = $0 }
            .onPreferenceChange(TimerRenderedFramePreferenceKey.self) { frame in
                timerRenderedFrame = frame
            }
            .onChange(of: timerTouchIsActive) { active in
                traceTimerTouch(active ? "tracking" : "tracking-ended", location: nil)
            }
            .onPreferenceChange(FloatingScrambleFramePreferenceKey.self) { frame in
                floatingScrambleFrame = frame
            }
            .onPreferenceChange(TimerScrambleAreaBottomPreferenceKey.self) { bottom in
                timerScrambleAreaBottom = bottom
            }
            .animation(.easeInOut(duration: 0.18), value: showsGANResultPopup)
            .onAppear {
                #if DEBUG
                manualProbe?.edit = { manualDraft.edit($0) }
                manualProbe?.save = saveTypedTime
                manualProbe?.snapshot = { (manualDraft.raw, selectedManualTime?.seconds, manualDraft.override) }
                battleProbe?.mode = setLocalBattleMode
                battleProbe?.press = pressLocalBattleTimer
                battleProbe?.release = releaseLocalBattleTimer
                battleProbe?.cancel = { setLocalBattlePressing(false, for: $0) }
                battleProbe?.configure = { localBattleDevices.setConfiguration($1, for: $0) }
                battleProbe?.manual = submitLocalBattleManual
                battleProbe?.snapshot = {
                    .init(scrambles: localBattleScrambles, firstStart: localBattleFirstStartDate,
                          secondStart: localBattleSecondStartDate, firstPressing: isLocalBattleFirstPressing,
                          secondPressing: isLocalBattleSecondPressing, ready: localBattleDevices.ready)
                }
                #endif
                TimerReadyFeedback.shared.prepare()
                migrateTimerArrangementPreferencesIfNeeded()
                normalizeUnavailableFontSelections()
                updateTimerAppearances()
                updateTimerBackgroundImage()
                if localBattleMode == .headToHead || localBattleMode == .sideBySide {
                    configureLocalBattleDevices()
                }
                if usesSmartCubeInput {
                    synchronizeSmartCubeEvent()
                    rehydrateSmartCubePresentation()
                    resumeVisibleSmartCubeGuidance()
                }
                if isRunning || isInspecting { startDisplayTimer() }
                #if DEBUG
                battleProbe?.appearanceCount += 1
                #endif
            }
            .compatibleNavigationBarHidden()
        }
        .compatibleTabBarVisibility(hidden: shouldHideTabBar)
    .task {
        #if DEBUG
        AppExperienceTrace.mark("timer_initialization_begin")
        #endif
        ensureSessionExists()
        _ = synchronizeSelectedSession(idRawValue: selectedSessionID, refreshStatistics: false)
        if scrambleNeedsReplacement || (!hasAssignedScramble
            && !(usesSmartCubeInput && restoreStoredSmartCubePresentation())) {
            generateNewScramble()
        } else {
            scheduleScramblePrefetch(for: scrambleGenerationContext)
        }
        refreshSolveSnapshots()
        refreshStreakSnapshots()
        #if DEBUG
        AppExperienceTrace.mark("timer_initialization_complete")
        #endif
        if usesGANTimerInput {
            ganTimer.prepareIfNeeded()
        }
        if usesSmartCubeInput {
            smartCubeTimingWasActive = true
            synchronizeSmartCubeEvent()
            smartCube.prepareIfNeeded()
            if smartCubeScrambleProgress == nil {
                prepareSmartCubeScrambleTarget()
            } else {
                rehydrateSmartCubePresentation()
            }
            updateSmartCubeConnectionReadiness()
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
        .onReceive(smartCubeGuidance.$publication) { publication in
            if let publication { applySmartCubeGuidance(publication) }
        }
        #if DEBUG
        .onAppear {
            cardEntryProbe?.openTimer = openSmartCubeManagement
            guidanceProbe?.prepare = { scramble in
                invalidateScramblePrefetch()
                scrambleRequestToken = UUID()
                currentScramble = scramble
                displayedScrambleContext = scrambleGenerationContext
                scrambleNeedsReplacement = false
                prepareSmartCubeScrambleTarget()
            }
            guidanceProbe?.snapshot = {
                .init(scramble: currentScramble, sessionID: selectedSession?.id, event: effectiveTimerEvent,
                      assignment: activeSolveAssignment, progress: smartCubeScrambleProgress, recovery: smartCubeRecoveryState,
                      request: smartCubeGuidance.currentRequest, identity: smartCubeScrambleEpoch.currentRecoveryIdentity,
                      diagram: currentCardsDiagram, prefetchIsReady: scramblePrefetchSlot.payload != nil)
            }
            guidanceProbe?.next = { generateNewScramble() }
            guidanceProbe?.start = { startTimer() }
            guidanceProbe?.cancelInspection = cancelInspection
            guidanceProbe?.restartInspection = restartSmartCubeInspection
            guidanceProbe?.inspection = { (isInspecting, canRestartSmartCubeInspection, isRunning) }
            guidanceProbe?.finish = { seconds in
                elapsedSeconds = seconds
                stopTimerAndSave()
                savePendingSolve(as: .solved)
            }
            guidanceProbe?.stop = { seconds in elapsedSeconds = seconds; stopTimerAndSave() }
            guidanceProbe?.save = { savePendingSolve(as: .solved) }
            guidanceProbe?.selectEvent = { selectedEvent = $0 }
            if let progress = smartCubeScrambleProgress, let facelets = smartCube.facelets {
                recordDisplayedGuidance(progress: progress, recovery: smartCubeRecoveryState, facelets: facelets)
            }
        }
        #endif
        .onDisappear {
            #if DEBUG
            battleProbe?.disappearanceCount += 1
            #endif
            showingSmartCubeManagement = false
            if localBattleMode != .solo {
                for player in LocalBattlePlayer.allCases where localBattleIsRunning(player) { cancelLocalBattlePlayer(player) }
            }
            localBattleDevices.setEnabled(false)
            celebrationID = nil
            invalidateScramblePrefetch()
            scrambleRequestToken = UUID()
            if usesSmartCubeInput {
                displayTimer?.invalidate()
                displayTimer = nil
            } else {
                invalidateTimer()
            }
            invalidateLocalBattleTimer()
            cacheSmartCubePresentation()
            cancelSmartCubeRecoveryTask()
            nearbyBattleManager.stop()
        }
        .onChange(of: enteringTimesWith) { newValue in
            if newValue == "typing" { refreshSolveSnapshots() }
            persistTimingMethodToSession(newValue)
            let wasUsingSmartCube = smartCubeTimingWasActive
            let newMode = SessionTimingMethod(rawValue: newValue) ?? .timer
            smartCubeTimingWasActive = newMode.usesSmartCube
            combinedSolveLifecycle.reset()
            pendingWeiPoCombinedStop = nil
            reconstructionCapture.reset()
            pendingSolveInputSource = nil
            pendingSolveReconstruction = nil
            pendingSolveScramble = nil
            if newMode.usesGANTimer {
                ganTimer.prepareIfNeeded()
            }
            if newMode.usesSmartCube {
                resetSmartCubeTimerState()
                synchronizeSmartCubeEvent()
                smartCube.prepareIfNeeded()
                generateNewScramble()
                updateSmartCubeConnectionReadiness()
            } else {
                resetSmartCubeTimerState()
                if wasUsingSmartCube { generateNewScramble() }
            }
        }
        .onChange(of: currentScramble) { newScramble in
            guard usesSmartCubeInput else { return }
            if let snapshot = SmartCubeTimerPresentationStore.shared.snapshot(matching: newScramble),
               snapshot.timerSessionID == selectedSession?.id,
               snapshot.progress == smartCubeScrambleProgress {
                return
            }
            prepareSmartCubeScrambleTarget(scramble: newScramble)
        }
        .onChange(of: smartCube.facelets) { _ in
            guard usesSmartCubeInput else { return }
            consumePendingSmartCubeUpdates()
            updateSmartCubeConnectionReadiness()
            // A pre-target physical event may correctly be ineligible for
            // timing, but its committed, trusted state is still authoritative
            // for guidance. Never require a further turn to observe it.
            if smartCube.puzzleSize == 3, let facelets = smartCube.facelets,
               smartCube.hasTrustedCanonicalState, !isRunning, !isInspecting,
               !showingResultPopup, !combinedSolveLifecycle.isActive, pendingWeiPoCombinedStop == nil {
                handleSmartCubeFacelets(facelets)
            }
        }
        .onChange(of: smartCube.connectionState) { _ in
            updateSmartCubeConnectionReadiness()
        }
        .onChange(of: smartCube.cubeStateRevision) { _ in
            updateSmartCubeConnectionReadiness()
        }
        .onChange(of: smartCube.weiPo2PendingSnapshotCount) { count in
            synchronizeCombinedReadinessUI()
            if count == 0 { finishPendingWeiPoCombinedStop() }
        }
        .onChange(of: smartCube.connectionAttemptID) { _ in
            updateSmartCubeConnectionReadiness()
            refreshScrambleGenerationDeviceOwner()
        }
        .onChange(of: smartCube.activeDeviceID) { _ in
            if usesSmartCubeInput { synchronizeSmartCubeEvent() }
            refreshScrambleGenerationDeviceOwner()
        }
        .onChange(of: smartCube.puzzleSize) { _ in
            if usesSmartCubeInput { synchronizeSmartCubeEvent() }
        }
        .onChange(of: smartCube.connectionPolicyResolvedAttemptID) { _ in
            updateSmartCubeConnectionReadiness()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            smartCubeGuidanceInForeground = false
            cancelSmartCubeRecoveryTask()
            celebrationID = nil
            if usesSmartCubeInput { cacheSmartCubePresentation() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            smartCubeGuidanceInForeground = true
            guard usesSmartCubeInput else { return }
            consumePendingSmartCubeUpdates()
            updateSmartCubeConnectionReadiness()
            resumeVisibleSmartCubeGuidance()
            if isRunning || isInspecting { startDisplayTimer() }
        }
        .onChange(of: isActive) { active in
            if active {
                if solveSnapshotsNeedRefresh { refreshSolveSnapshots() }
                resumeVisibleSmartCubeGuidance()
            } else { cancelSmartCubeRecoveryTask() }
        }
        .onReceive(smartCube.canonicalEvents) { event in
            consumeSmartCubeEvent(event)
        }
        .onChange(of: ganTimer.connectionState) { newValue in
            handleGANTimerStateChange(newValue)
        }
        .onReceive(ganTimer.$connectionState) { state in
            localBattleDevices.receiveSmartTimerState(state, startedAt: ganTimer.activeRunStartedAt)
        }
        .onReceive(ganTimer.$completedSolve.compactMap { $0 }.removeDuplicates()) { solve in
            localBattleDevices.receiveSmartTimerCompletion(solve)
        }
        .onChange(of: ganTimer.completedSolve) { solve in
            guard localBattleMode == .solo, usesGANTimerInput, let solve else { return }
            if usesCombinedInput {
                handleCombinedTimerCompletion(solve)
            } else {
                handleGANCompletedSolve(seconds: solve.seconds)
            }
        }
        .onChange(of: ganTimer.clearButtonEventID) { eventID in
            guard localBattleMode == .solo, usesGANTimerInput, eventID != nil else { return }
            handleGANResultSelectionButtonPress()
        }
        .onChange(of: ganTimer.inspectionToggleEventID) { eventID in
            guard localBattleMode == .solo, usesGANTimerInput, ganInspectionStartsOnPress, eventID != nil else { return }
            handleGANInspectionToggle()
        }
        .onChange(of: isRunning) { running in
            if running {
                currentResultPB.timingDidBegin()
                celebrationID = nil
            }
        }
        .onChange(of: selectedEvent) { newEvent in
            if usesSmartCubeInput, smartCube.isConnected, newEvent != effectiveTimerEvent {
                // A restored/manual value is not a request to replace a live
                // cube. Changing the manager filter here would drop its owner.
                synchronizeSmartCubeEvent()
                return
            }
            currentResultPB.timingDidBegin()
            celebrationID = nil
            floatingScrambleFrame = nil
            if usesSmartCubeInput && !smartCube.isConnected {
                smartCube.setTimerPuzzleSize(newEvent == .twoByTwo ? 2 : 3)
            }
            #if DEBUG
            if let marketingPreviewConfiguration {
                marketingPreviewConfiguration.wrappedValue.event = newEvent
                generateNewScramble()
                if localBattleMode != .solo { resetLocalBattleScrambles() }
                return
            }
            #endif
            persistSelectedEventToSession()
            refreshSolveSnapshots(for: newEvent)
            // A correction from an incompatible selection can be followed by
            // another onChange for the live device's event. Do not replace a
            // compatible target (and suspend timing) just for that write-back.
            if !(usesSmartCubeInput && (restoredSmartCubeEvent == newEvent || displayedScrambleMatchesSelection)) {
                generateNewScramble()
            }
            restoredSmartCubeEvent = nil
            if localBattleMode != .solo { resetLocalBattleScrambles() }
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
            currentResultPB.timingDidBegin()
            celebrationID = nil
            invalidateScramblePrefetch()
            scrambleRequestToken = UUID()
            let previousEvent = selectedEvent
            _ = synchronizeSelectedSession(idRawValue: newSessionID)
            if selectedEvent == previousEvent { generateNewScramble() }
        }
        .onChange(of: sessions.count) { _ in
            invalidateScramblePrefetch()
            scrambleRequestToken = UUID()
            _ = synchronizeSelectedSession(idRawValue: selectedSessionID)
            scheduleScramblePrefetch(for: scrambleGenerationContext)
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
            timerPBState = .empty
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
        .sheet(isPresented: $showingSmartCubeDevicePicker) {
            SmartCubeDevicePickerView(
                manager: smartCube,
                onConnectionStarted: { attemptID in
                    guard smartCube.activeDeviceID == nil || smartCube.connectionAttemptID == attemptID else { return }
                    smartCubeReadinessTracker.begin(attemptID)
                    #if DEBUG
                    SmartCubeDiagnostics.shared.trace("hud.tracker.initialized", attemptID: attemptID, deviceID: smartCube.connectionDeviceID, detail: "source=timer")
                    #endif
                    updateSmartCubeConnectionReadiness()
                },
                onConnectionApproved: { attemptID in
                    guard smartCube.connectionAttemptID == attemptID else { return }
                    smartCubeReadinessTracker.approve(attemptID)
                    #if DEBUG
                    SmartCubeDiagnostics.shared.trace("hud.tracker.approved", attemptID: attemptID, deviceID: smartCube.connectionDeviceID, detail: "source=timer")
                    #endif
                    updateSmartCubeConnectionReadiness()
                }
            )
                .compatibleMediumSheet()
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
            selection: Binding(
                get: { effectiveTimerEvent },
                set: { selectedEvent = $0 }
            ),
            isEnabled: !usesSmartCubeInput || isMarketingPreviewTimer
        )
    }

    private var startTimerGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($timerTouchIsActive) { _, active, _ in active = true }
            .onChanged { value in
                traceTimerTouch("changed", location: value.location)
                armForStartIfNeeded()
            }
            .onEnded { value in
                traceTimerTouch("ended", location: value.location)
                if isRunning {
                    stopTimerAndSave()
                } else {
                    releaseToStartIfReady()
                }
                traceTimerTouch("state-updated", location: value.location)
            }
    }

    private func traceTimerTouch(_ phase: String, location: CGPoint?) {
        #if DEBUG
        guard CompetitionDebugStore.shared.enabled, UserDefaults.standard.bool(forKey: "timerTouchDiagnostics") else { return }
        print("[TimerTouch] \(phase) point=\(String(describing: location)) running=\(isRunning) pressing=\(isPressingToArm) ready=\(isReadyToStart) inspection=\(isInspecting)")
        #endif
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

    private func cancelInspection() {
        guard isInspecting, !isRunning else { return }

        invalidateTimer()
        isInspecting = false
        inspectionElapsed = 0
        announcedInspectionCheckpoints.removeAll()
        currentSolveInspectionPenalty = nil
        isPressingToArm = false
        isReadyToStart = false

        if usesSmartCubeInput && !usesCombinedInput {
            smartCubeScrambleEpoch.cancelInspection(attemptID: smartCube.connectionAttemptID,
                                                    lifecycle: &smartCubeSolveLifecycle)
            smartCubeIsReady = false
            cacheSmartCubePresentation()
        }
    }

    private func startTimer() {
        guard !usesCombinedInput, !isRunning, pendingSolveTime == nil,
              let assignment = currentSolveAssignment else { return }
        activeSolveAssignment = assignment
        pendingSolveScramble = assignment.scramble
        scrambleRequestToken = UUID()

        if isInspecting {
            currentSolveInspectionPenalty = inspectionPenalty(for: inspectionStartDate.map { max(0, Date().timeIntervalSince($0)) } ?? inspectionElapsed)
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
        pendingSolveScramble = activeSolveAssignment?.scramble ?? scrambleToSave
        pendingInspectionPenalty = currentSolveInspectionPenalty
        pendingSolveInputSource = .appTimer
        pendingSolveReconstruction = nil
        showingResultPopup = true
    }

    private func prepareSmartCubeScrambleTarget(scramble: String? = nil) {
        let scramble = scramble ?? currentScramble
        smartCubeRecoveryDisplayRawValue = resolvedSmartCubeRecoveryDisplay.rawValue
        if smartCubeReadySound { SmartCubeReadySoundPlayer.shared.prepare() }
        cancelSmartCubeRecovery()
        SmartCubeTimerPresentationStore.shared.clear()
        guard scramble != "…",
              let progress = SmartCubeScrambleProgress(
                scramble: scramble,
                // Without a connected cube, the Timer event owns generation
                // and its target; a previous device's size is not authoritative.
                puzzleSize: effectiveTimerEvent == .twoByTwo ? 2 : 3
              )
        else {
            smartCubeScrambleProgress = nil
            smartCubeScrambleEpoch.reset()
            smartCubeSolveLifecycle.reset()
            smartCubeIsReady = false
            #if DEBUG
            SmartCubeDiagnostics.shared.guidance("unavailable reason=target-unavailable", force: true)
            #endif
            return
        }

        if isInspecting {
            isInspecting = false
            inspectionStartDate = nil
            inspectionElapsed = 0
            announcedInspectionCheckpoints = []
            currentSolveInspectionPenalty = nil
            invalidateTimer()
        }

        smartCubeScrambleProgress = progress
        smartCubeScrambleEpoch.establish(
            at: .now,
            latestMoveID: smartCube.latestMove?.id,
            canonicalSequence: smartCube.canonicalSequence
        )
        #if DEBUG
        SmartCubeGuidanceTrace.record("target-assigned", identity: smartCubeScrambleEpoch.currentRecoveryIdentity,
            source: smartCube.facelets ?? "none", target: progress.targetFacelets,
            detail: SmartCubeGuidanceTrace.assignment(scramble: scramble, requestID: scrambleRequestToken))
        #endif
        smartCubeSolveLifecycle.reset()
        smartCubeSolveStartMove = nil
        smartCubeIsReady = false
        if let facelets = smartCube.facelets, smartCube.hasTrustedCanonicalState {
            handleSmartCubeFacelets(facelets)
        } else {
            #if DEBUG
            let reason = smartCube.facelets == nil ? "current-facelets-unavailable" : "continuity-untrusted"
            SmartCubeDiagnostics.shared.guidance("waiting reason=\(reason)", force: true)
            #endif
            cacheSmartCubePresentation()
        }
    }

    private func updateSmartCubeConnectionReadiness() {
        guard usesSmartCubeInput else { return }
        defer { synchronizeCombinedReadinessUI() }
        let readiness = smartCube.observationReadiness
        smartCubeReadinessTracker.synchronize(
            attemptID: readiness.attemptID,
            isApproved: readiness.hasResolvedConnectionPolicy
        )
        #if DEBUG
        let attemptMatches = smartCubeReadinessTracker.activeAttemptID == nil
            || smartCubeReadinessTracker.activeAttemptID == readiness.attemptID
        let trackerApproved = smartCubeReadinessTracker.approvedAttemptID == nil
            || smartCubeReadinessTracker.approvedAttemptID == readiness.attemptID
        let presentation = SmartCubeTimerConnectionPresentation.resolve(
            readiness: readiness,
            isAttemptApproved: smartCubeReadinessTracker.permitsReadiness(readiness),
            connectionState: smartCube.connectionState
        )
        let blockers = [
            readiness.attemptID == nil ? "attempt" : nil,
            readiness.isBLEConnected ? nil : "ble",
            readiness.hasResolvedConnectionPolicy ? nil : "policy",
            readiness.hasAuthoritativeState ? nil : "facelets",
            readiness.hasTrustedCanonicalState ? nil : "canonical",
            attemptMatches ? nil : "attemptMatch",
            trackerApproved ? nil : "trackerApproval"
        ].compactMap { $0 }.joined(separator: ",")
        SmartCubeDiagnostics.shared.trace(
            "readiness.changed",
            attemptID: readiness.attemptID,
            deviceID: smartCube.connectionDeviceID,
            detail: "ready=\(readiness.isReady && attemptMatches && trackerApproved) presentation=\(presentation) ble=\(readiness.isBLEConnected) policy=\(readiness.hasResolvedConnectionPolicy) facelets=\(readiness.hasAuthoritativeState) canonical=\(readiness.hasTrustedCanonicalState) attemptMatch=\(attemptMatches) trackerApproval=\(trackerApproved) blocker=\(blockers.isEmpty ? "none" : blockers)",
            deduplicationKey: "timer-readiness"
        )
        #endif
        if smartCubeReadinessTracker.shouldAnnounce(readiness) {
            // Readiness still rehydrates state; normal connection/switch success is quiet.
            rehydrateSmartCubePresentation()
            return
        }

        #if DEBUG
        if readiness.isReady {
            let reason: String
            if smartCubeReadinessTracker.activeAttemptID != readiness.attemptID {
                reason = "stale-attempt"
            } else if smartCubeReadinessTracker.approvedAttemptID != readiness.attemptID {
                reason = "tracker-not-approved"
            } else if smartCubeReadinessTracker.announcedAttemptID == readiness.attemptID {
                reason = "duplicate"
            } else {
                reason = "not-eligible"
            }
            SmartCubeDiagnostics.shared.trace("hud.connected.suppressed", attemptID: readiness.attemptID, deviceID: smartCube.connectionDeviceID, detail: "reason=\(reason)", deduplicationKey: "hud-suppressed")
        }
        #endif

        switch smartCube.connectionState {
        case .disconnected, .failed, .bluetoothUnavailable, .unauthorized:
            smartCubeReadinessTracker.end(readiness.attemptID)
        case .scanning, .connecting, .connected:
            break
        }
    }

    private func synchronizeCombinedReadinessUI() {
        guard usesCombinedInput,
              !combinedSolveLifecycle.isActive,
              !isInspecting else { return }
        isPressingToArm = ganTimer.connectionState == .handsOn || ganTimer.connectionState == .ready
        isReadyToStart = combinedReadiness.isReady
    }

    private func handleSmartCubeFacelets(
        _ facelets: String,
        canonicalMove: String? = nil,
        completingMoveID: UUID? = nil
    ) {
        defer { synchronizeCombinedReadinessUI() }
        if isRunning {
            // Snapshots are not physical completion evidence. Only the ordered
            // continuous move path below may finish an active solve.
            return
        }

        guard var progress = smartCubeScrambleProgress else {
            cancelSmartCubeRecovery()
            smartCubeIsReady = false
            return
        }
        #if DEBUG
        SmartCubeGuidanceTrace.record("canonical-receipt", identity: smartCubeScrambleEpoch.currentRecoveryIdentity,
            source: facelets, target: progress.targetFacelets, detail: "physical=\(canonicalMove != nil)")
        #endif

        if progress.puzzleSize == 3, (progress.isDeviated || progress.needsGuidanceSearch),
           (smartCubeRecoveryState.sourceFacelets == facelets || smartCubeGuidance.currentRequest?.sourceFacelets == facelets),
           canonicalMove == nil {
            #if DEBUG
            SmartCubeGuidanceTrace.record("snapshot-already-covered", identity: smartCubeScrambleEpoch.currentRecoveryIdentity,
                source: facelets, target: progress.targetFacelets)
            #endif
            return
        }

        let previousRecoveryPlan = smartCubeRecoveryState.plan ?? smartCubeRecoveryState.fallbackPlan
        let recoveryIdentity: SmartCubeRecoveryPlanIdentity
        if let pending = smartCubeGuidance.currentRequest, pending.sourceFacelets == facelets {
            recoveryIdentity = pending.identity
        } else if smartCubeRecoveryState.sourceFacelets != facelets {
            recoveryIdentity = smartCubeScrambleEpoch.advanceRecoveryStateVersion()
        } else if let currentIdentity = smartCubeRecoveryState.identity {
            recoveryIdentity = currentIdentity
        } else {
            recoveryIdentity = smartCubeScrambleEpoch.advanceRecoveryStateVersion()
        }
        _ = progress.update(with: facelets, canonicalMove: canonicalMove)
        #if DEBUG
        SmartCubeGuidanceTrace.record("snapshot-acquired", identity: recoveryIdentity,
            source: facelets, target: progress.targetFacelets, detail: "complete=\(progress.isComplete)")
        #endif
        if !progress.isComplete {
            smartCubeIsReady = false
            if smartCube.hasTrustedCanonicalState {
                smartCubeScrambleEpoch.observeScrambleDeparture()
            }
        }

        if progress.puzzleSize == 3, progress.isDeviated {
            let rawTrailPlan = progress.guaranteedRecoveryPlan(
                identity: recoveryIdentity,
                sourceFacelets: facelets
            )
            let rawContinuedPlan = canonicalMove.flatMap { canonicalMove in
                previousRecoveryPlan.flatMap {
                    SmartCubeRecoveryEngine.advancedPlan(
                        from: $0,
                        by: canonicalMove,
                        identity: recoveryIdentity,
                        sourceFacelets: facelets
                    )
                }
            }
            let trailPlan = rawTrailPlan.flatMap { progress.normalizeRecoveryBoundary($0) }
            let continuedPlan = rawContinuedPlan.flatMap {
                progress.normalizeRecoveryBoundary($0)
            }
            let guaranteedPlan: SmartCubeRecoveryPlan?
            if let continuedPlan,
               continuedPlan.totalCost <= (trailPlan?.totalCost ?? .max) {
                guaranteedPlan = continuedPlan
            } else {
                guaranteedPlan = trailPlan
            }
            if progress.isDeviated {
                let recoveryState = SmartCubeReplacementPlanner.initialPresentation(
                    recovery: guaranteedPlan,
                    identity: recoveryIdentity,
                    sourceFacelets: facelets
                )
                publishSmartCubePresentation(progress: progress, recoveryState: recoveryState)
                beginSmartCubeGuidanceSearch(
                    from: facelets,
                    identity: recoveryIdentity,
                    guaranteedPlan: guaranteedPlan
                )
                return
            }
        }

        if progress.needsGuidanceSearch, !progress.isComplete {
            publishSmartCubePresentation(progress: progress, recoveryState: .inactive)
            beginSmartCubeGuidanceSearch(from: facelets, identity: recoveryIdentity, guaranteedPlan: nil)
            return
        }

        publishSmartCubePresentation(progress: progress, recoveryState: .inactive)

        guard progress.isComplete else {
            if progress.puzzleSize == 3 {
                // Following a valid, but not globally optimal, route is not a
                // reason to stop looking for a one-move improvement when idle.
                beginSmartCubeGuidanceSearch(from: facelets, identity: recoveryIdentity, guaranteedPlan: nil)
            } else { cancelSmartCubeRecoveryTask() }
            return
        }
        cancelSmartCubeRecoveryTask()
        if usesCombinedInput, smartCubeSolveLifecycle.phase == .ready {
            smartCubeIsReady = true
            return
        }
        let action = smartCubeScrambleEpoch.completionAction(
            inspectionEnabled: usesCombinedInput ? false : wcaInspectionEnabled,
            completingMoveID: completingMoveID ?? smartCube.latestMove?.id,
            lifecycle: &smartCubeSolveLifecycle
        )
        guard action != .none else { return }
        if smartCubeReadySound, !usesCombinedInput {
            SmartCubeReadySoundPlayer.shared.play()
        }
        switch action {
        case .beginInspection:
            smartCubeIsReady = false
            startInspection()
        case .enteredReady:
            smartCubeIsReady = true
        case .none:
            break
        case .startTiming:
            break
        }
        if smartCubeReadySound, usesCombinedInput, combinedReadiness.isReady {
            SmartCubeReadySoundPlayer.shared.play()
        }
    }

    private func consumePendingSmartCubeUpdates() {
        for event in smartCube.canonicalHistory {
            consumeSmartCubeEvent(event)
        }
    }

    private func consumeSmartCubeEvent(_ event: SmartCubeCanonicalEvent) {
        #if DEBUG
        let isNew = event.sequence > smartCubeScrambleEpoch.consumedCanonicalSequence
        if isNew {
            SmartCubeDiagnostics.shared.mark("guidance.event-received", id: smartCubeScrambleEpoch.recoveryScrambleID,
                detail: "sequence=\(event.sequence) smartMode=\(usesSmartCubeInput) running=\(isRunning) inspecting=\(isInspecting) result=\(showingResultPopup) trusted=\(smartCube.hasTrustedCanonicalState)")
        }
        #endif
        guard usesSmartCubeInput, localBattleMode == .solo else { return }
        switch smartCubeScrambleEpoch.consumeEvent(event) {
        case .ignored:
            #if DEBUG
            if isNew {
                SmartCubeDiagnostics.shared.mark("guidance.event-ineligible-for-epoch", id: smartCubeScrambleEpoch.recoveryScrambleID,
                    detail: "sequence=\(event.sequence)")
            }
            #endif
            return
        case .boundary(let reason, let facelets):
            if case .boundary(let boundary) = event, boundary.reason == .weiPoSnapshot,
               usesWeiPo2NativeVisual {
                if !isRunning, let observedAt = boundary.observedWeiPoTurnAt {
                    smartCubeScrambleEpoch.observeWeiPoTurn(at: observedAt)
                }
                guard isRunning, !usesCombinedInput else {
                    handleSmartCubeContinuityBreak(reason, facelets: facelets)
                    return
                }
                reconstructionCapture.markIncomplete(.historyGap)
                #if DEBUG
                SmartCubeDiagnostics.shared.mark("weiPo.timing-snapshot", id: smartCubeSolveStartMove?.id,
                    detail: "sequence=\(boundary.sequence) revision=\(smartCube.cubeStateRevision) device=\(smartCube.activeDeviceID?.uuidString.prefix(8) ?? "-") event=\(effectiveTimerEvent.rawValue) target=\(smartCubeScrambleEpoch.currentRecoveryIdentity.scrambleEpochID.uuidString.prefix(8)) trusted=\(facelets != nil) observedTurn=\(boundary.observedWeiPoTurnAt != nil) solved=\(facelets.map { CubeStateEquivalence.isSolved($0, puzzleSize: 2) } ?? false)")
                #endif
                if let facelets, CubeStateEquivalence.isSolved(facelets, puzzleSize: 2),
                   let observedAt = boundary.observedWeiPoTurnAt {
                    finishSmartCubeSolve(weiPoTurnObservedAt: observedAt)
                }
                return
            }
            handleSmartCubeContinuityBreak(reason, facelets: facelets)
        case .move(let update):
            consumeSmartCubeUpdate(update)
        }
    }

    private func handleSmartCubeContinuityBreak(_ reason: SmartCubeContinuityReason, facelets: String?) {
        #if DEBUG
        SmartCubeDiagnostics.shared.interrupted(reason)
        SmartCubeDiagnostics.shared.guidance(
            "unavailable reason=continuity-\(reason.rawValue) facelets=\(facelets == nil ? "unavailable" : "authoritative")",
            force: true
        )
        #endif
        cancelSmartCubeRecovery()
        reconstructionCapture.markIncomplete(reason)
        if !usesCombinedInput, isRunning || isInspecting {
            // Smart Cube-only timing cannot produce a trustworthy duration after a continuity break.
            invalidateTimer()
            isRunning = false
            isInspecting = false
            timerStartDate = nil
            inspectionStartDate = nil
            inspectionElapsed = 0
            announcedInspectionCheckpoints = []
            currentSolveInspectionPenalty = nil
            elapsedSeconds = 0
        }
        smartCubeSolveLifecycle.reset()
        smartCubeSolveStartMove = nil
        smartCubeIsReady = false
        if reason == .weiPoSnapshot, let facelets, !isRunning, !isInspecting,
           smartCubeScrambleProgress?.puzzleSize == 2, smartCube.hasTrustedCanonicalState, !showingResultPopup {
            handleSmartCubeFacelets(facelets)
            return
        }
        if var progress = smartCubeScrambleProgress {
            progress.breakContinuity(at: facelets)
            guard (progress.isDeviated || progress.needsGuidanceSearch), !progress.isComplete,
                  let facelets,
                  smartCube.hasTrustedCanonicalState else {
                publishSmartCubePresentation(progress: progress, recoveryState: .inactive)
                return
            }
            let identity = smartCubeScrambleEpoch.currentRecoveryIdentity
            publishSmartCubePresentation(
                progress: progress,
                recoveryState: .searching(
                    identity: identity,
                    sourceFacelets: facelets,
                    fallbackPlan: nil
                )
            )
            beginSmartCubeGuidanceSearch(
                from: facelets,
                identity: identity,
                guaranteedPlan: nil
            )
        }
    }

    private func consumeSmartCubeUpdate(_ update: SmartCubeCanonicalUpdate) {
        #if DEBUG
        SmartCubeDiagnostics.shared.mark("timer.consume", id: update.move.id)
        SmartCubeGuidanceTrace.record("move-consumed", identity: smartCubeScrambleEpoch.currentRecoveryIdentity,
            source: update.facelets, target: smartCubeScrambleProgress?.targetFacelets ?? "none",
            detail: "sequence=\(update.sequence) moveID=\(update.move.id.uuidString.prefix(8)) move=\(update.move.move) trusted=\(update.isStateTrusted) phase=\(smartCubeSolveLifecycle.phase)")
        SmartCubeDiagnostics.shared.traceMove(
            "timer.canonical.consumed",
            move: update.move,
            attemptID: smartCube.connectionAttemptID,
            deviceID: smartCube.connectionDeviceID,
            accepted: true,
            detail: "sequence=\(update.sequence) trusted=\(update.isStateTrusted)"
        )
        #endif
        let belongsToPendingStop = pendingWeiPoCombinedStop.map {
            usesCombinedInput && update.move.localTimestamp <= $0.stoppedAt
        } ?? false
        if isRunning || (usesCombinedInput && combinedSolveLifecycle.isActive) || belongsToPendingStop {
            reconstructionCapture.append(update)
            if let endMove = SmartCubeCanonicalEvent.move(update).solveCompletingMove {
                if !usesCombinedInput {
                    finishSmartCubeSolve(endMove: endMove)
                }
            }
        } else {
            handleSmartCubeMove(update)
        }
    }

    private func handleSmartCubeMove(_ update: SmartCubeCanonicalUpdate) {
        let move = update.move
        let facelets = update.facelets
        #if DEBUG
        if isRunning || showingResultPopup {
            SmartCubeGuidanceTrace.record("move-skipped-for-lifecycle", identity: smartCubeScrambleEpoch.currentRecoveryIdentity,
                source: facelets, target: smartCubeScrambleProgress?.targetFacelets ?? "none",
                detail: "running=\(isRunning) result=\(showingResultPopup)")
        }
        #endif
        guard !isRunning, !showingResultPopup else { return }
        guard smartCubeScrambleEpoch.observePhysicalMove(move) else { return }
        if smartCubeSolveLifecycle.phase == .scrambling {
            handleSmartCubeFacelets(facelets, canonicalMove: move.move, completingMoveID: move.id)
            return
        }
        // Combined mode never starts from this move, but a pre-start turn must
        // invalidate the previously verified scramble/readiness state.
        if usesCombinedInput {
            handleSmartCubeFacelets(facelets, canonicalMove: move.move, completingMoveID: move.id)
            return
        }
        guard case .startTiming(let startMove) = smartCubeSolveLifecycle.physicalMoveDidOccur(move) else {
            return
        }
        guard let assignment = currentSolveAssignment else { smartCubeSolveLifecycle.reset(); return }
        activeSolveAssignment = assignment
        pendingSolveScramble = assignment.scramble
        scrambleRequestToken = UUID()
        #if DEBUG
        SmartCubeDiagnostics.shared.begin(startMove)
        #endif

        smartCubeIsReady = false
        if isInspecting {
            let elapsed = inspectionStartDate.map { max(0, startMove.localTimestamp.timeIntervalSince($0)) }
                ?? inspectionElapsed
            currentSolveInspectionPenalty = inspectionPenalty(for: elapsed)
            isInspecting = false
            inspectionStartDate = nil
            inspectionElapsed = 0
        }
        elapsedSeconds = 0
        smartCubeSolveStartMove = startMove
        timerStartDate = startMove.localTimestamp
        reconstructionCapture.start(
            initialFacelets: smartCube.puzzleSize == 2
                ? update.previousTwoByTwoFacelets ?? facelets
                : smartCubeScrambleProgress?.targetFacelets ?? facelets,
            with: update
        )
        if smartCube.puzzleSize == 2 && update.previousTwoByTwoFacelets == nil {
            reconstructionCapture.markIncomplete(.historyGap)
        }
        isRunning = true
        startDisplayTimer()
    }

    private func publishSmartCubePresentation(
        progress: SmartCubeScrambleProgress,
        recoveryState: SmartCubeRecoveryPresentationState
    ) {
        #if DEBUG
        if let facelets = smartCube.facelets {
            recordDisplayedGuidance(progress: progress, recovery: recoveryState, facelets: facelets)
        }
        #endif
        let highlightedTokenIndex = recoveryState.plan == nil
            ? progress.currentMoveTokenIndex
            : nil

        if resolvedSmartCubeHighlightAnimation.updatesImmediately {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                smartCubeRecoveryState = recoveryState
                smartCubeHighlightedTokenIndex = highlightedTokenIndex
            }
            updateSmartCubeProgress(progress)
        } else if let animation = smartCubeProgressAnimation {
            withAnimation(animation) {
                smartCubeRecoveryState = recoveryState
                smartCubeHighlightedTokenIndex = highlightedTokenIndex
                smartCubeScrambleProgress = progress
            }
        } else {
            smartCubeRecoveryState = recoveryState
            smartCubeHighlightedTokenIndex = highlightedTokenIndex
            smartCubeScrambleProgress = progress
        }
        cacheSmartCubePresentation()
    }

    private func updateSmartCubeProgress(_ progress: SmartCubeScrambleProgress) {
        guard let animation = smartCubeProgressAnimation else {
            smartCubeScrambleProgress = progress
            return
        }
        withAnimation(animation) { smartCubeScrambleProgress = progress }
    }

    private func resumeVisibleSmartCubeGuidance() {
        guard isActive, usesSmartCubeInput, localBattleMode == .solo, let facelets = smartCube.facelets else { return }
        beginSmartCubeGuidanceSearch(from: facelets, identity: smartCubeScrambleEpoch.currentRecoveryIdentity,
            guaranteedPlan: smartCubeRecoveryState.plan ?? smartCubeRecoveryState.fallbackPlan)
    }

    private func beginSmartCubeGuidanceSearch(
        from facelets: String,
        identity: SmartCubeRecoveryPlanIdentity,
        guaranteedPlan: SmartCubeRecoveryPlan?
    ) {
        guard isActive, smartCubeGuidanceInForeground, let progress = smartCubeScrambleProgress,
              progress.puzzleSize == 3, !progress.isComplete,
              smartCube.hasTrustedCanonicalState, !isRunning, !isInspecting else {
            cancelSmartCubeRecoveryTask()
            return
        }
        let recovery = smartCubeRecoveryState.plan ?? smartCubeRecoveryState.fallbackPlan ?? guaranteedPlan
        smartCubeGuidance.submit(.init(identity: identity, sourceFacelets: facelets,
            targetFacelets: progress.targetFacelets, generation: progress.replanGeneration,
            knownPath: recovery?.executableMoves(originalTokens: progress.tokens)
                ?? (progress.isDeviated ? nil : progress.remainingGuidanceMoves),
            continuationOnly: !progress.isDeviated && !progress.needsGuidanceSearch,
            keepsEqualPath: !progress.isDeviated && !progress.needsGuidanceSearch,
            deviceID: smartCube.activeDeviceID,
            canonicalSequence: smartCube.canonicalSequence))
    }

    private func applySmartCubeGuidance(_ publication: SmartCubeGuidanceController.Publication) {
        consumePendingSmartCubeUpdates()
        let improvesContinuation = publication.request.continuationOnly
            && (publication.decision.replacement?.tokens.count ?? .max)
                < (smartCubeScrambleProgress?.remainingGuidanceMoves.count ?? 0)
        #if DEBUG
        SmartCubeGuidanceTrace.record("adoption-check", identity: publication.request.identity,
            source: publication.request.sourceFacelets, target: publication.request.targetFacelets,
            detail: "epochMatch=\(publication.request.identity == smartCubeScrambleEpoch.currentRecoveryIdentity) deviceMatch=\(publication.request.deviceID == smartCube.activeDeviceID) sourceMatch=\(publication.request.sourceFacelets == smartCube.facelets) targetMatch=\(publication.request.targetFacelets == smartCubeScrambleProgress?.targetFacelets) generationMatch=\(publication.request.generation == smartCubeScrambleProgress?.replanGeneration) trusted=\(smartCube.hasTrustedCanonicalState) eligible=\(usesSmartCubeInput && !isRunning && !isInspecting)")
        #endif
        guard let current = smartCubeScrambleProgress,
              publication.request.deviceID == smartCube.activeDeviceID,
              publication.request.identity == smartCubeScrambleEpoch.currentRecoveryIdentity,
              publication.request.sourceFacelets == smartCube.facelets,
              publication.request.targetFacelets == current.targetFacelets,
              publication.request.generation == current.replanGeneration,
              usesSmartCubeInput, smartCube.hasTrustedCanonicalState, !isRunning, !isInspecting,
              current.isDeviated || current.needsGuidanceSearch || improvesContinuation else { return }
        if publication.decision.replacement == nil {
            publishSmartCubePresentation(progress: current, recoveryState:
                SmartCubeReplacementPlanner.fallbackPresentation(from: smartCubeRecoveryState))
            return
        }
        guard let rebased = publication.progress(identity: smartCubeScrambleEpoch.currentRecoveryIdentity,
                facelets: smartCube.facelets ?? "", target: current.targetFacelets,
                generation: current.replanGeneration, trusted: smartCube.hasTrustedCanonicalState,
                eligible: current.isDeviated || current.needsGuidanceSearch || improvesContinuation,
                deviceID: smartCube.activeDeviceID)
        else { return }
        smartCubeScrambleEpoch.rebaseGuidance(latestMoveID: smartCube.latestMove?.id,
                                             canonicalSequence: smartCube.canonicalSequence)
        smartCubeSolveLifecycle.reset()
        smartCubeSolveStartMove = nil
        smartCubeIsReady = false
        publishSmartCubePresentation(progress: rebased, recoveryState: .inactive)
        #if DEBUG
        SmartCubeGuidanceTrace.record("adoption-accepted", identity: publication.request.identity,
            source: publication.request.sourceFacelets, target: publication.request.targetFacelets,
            detail: "count=\(rebased.tokens.count) generation=\(rebased.replanGeneration)")
        #endif
    }

    private var smartCubeGuidanceDiagnosticContext: String? {
        #if DEBUG
        guard SmartCubeDiagnostics.shared.enabled, let progress = smartCubeScrambleProgress else { return nil }
        let plan = smartCubeRecoveryState.plan ?? smartCubeRecoveryState.fallbackPlan
        let moves = plan?.executableMoves(originalTokens: progress.tokens) ?? progress.remainingGuidanceMoves
        let end = moves.reduce(smartCube.facelets) { state, move in
            state.flatMap { SmartCubeBluetoothManager.facelets($0, applying: move) }
        }
        return "epoch=\(smartCubeScrambleEpoch.currentRecoveryIdentity.scrambleEpochID.uuidString.prefix(8)) revision=\(smartCubeScrambleEpoch.currentRecoveryIdentity.stateVersion) source=\(smartCube.facelets.map(SmartCubeGuidanceTrace.digest) ?? "none") target=\(SmartCubeGuidanceTrace.digest(progress.targetFacelets)) generation=\(progress.replanGeneration) count=\(moves.count) valid=\(end == progress.targetFacelets) path=\(SmartCubeGuidanceTrace.digest(moves.joined(separator: " "))) sequence=\(smartCubeScrambleEpoch.consumedCanonicalSequence) \(SmartCubeGuidanceTrace.assignment(scramble: currentScramble, requestID: scrambleRequestToken)) recovery=\(plan != nil)"
        #else
        return nil
        #endif
    }

    #if DEBUG
    private func recordDisplayedGuidance(progress: SmartCubeScrambleProgress,
                                         recovery: SmartCubeRecoveryPresentationState, facelets: String) {
        guard SmartCubeDiagnostics.shared.enabled else { return }
        let plan = recovery.plan ?? recovery.fallbackPlan
        let moves = plan?.executableMoves(originalTokens: progress.tokens) ?? progress.remainingGuidanceMoves
        let end = moves.reduce(Optional(facelets)) { state, move in
            state.flatMap { SmartCubeBluetoothManager.facelets($0, applying: move) }
        }
        SmartCubeGuidanceTrace.record("display-path", identity: smartCubeScrambleEpoch.currentRecoveryIdentity,
            source: facelets, target: progress.targetFacelets,
            detail: "sequence=\(smartCube.canonicalSequence) valid=\(end == progress.targetFacelets) recovery=\(plan != nil) count=\(moves.count) path=\(SmartCubeGuidanceTrace.digest(moves.joined(separator: " "))) deviated=\(progress.isDeviated) needsSearch=\(progress.needsGuidanceSearch) \(SmartCubeGuidanceTrace.assignment(scramble: currentScramble, requestID: scrambleRequestToken))")
    }
    #endif

    private func publishSmartCubeRecoveryPlan(_ plan: SmartCubeRecoveryPlan) {
        if resolvedSmartCubeHighlightAnimation == .animated {
            withAnimation(.easeOut(duration: 0.18)) {
                smartCubeRecoveryState = .recovery(plan)
            }
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                smartCubeRecoveryState = .recovery(plan)
            }
        }
        cacheSmartCubePresentation()
    }

    private func cancelSmartCubeRecoveryTask() {
        smartCubeGuidance.cancel()
    }

    private func cancelSmartCubeRecovery() {
        cancelSmartCubeRecoveryTask()
        smartCubeRecoveryState = .inactive
        smartCubeHighlightedTokenIndex = smartCubeScrambleProgress?.currentMoveTokenIndex
    }

    private func cacheSmartCubePresentation() {
        guard usesSmartCubeInput,
              !scrambleNeedsReplacement,
              !currentScramble.isEmpty,
              let progress = smartCubeScrambleProgress
        else { return }
        guard SmartCubeTimerPresentationStore.shared.save(
            scramble: currentScramble,
            progress: progress,
            epoch: smartCubeScrambleEpoch,
            recoveryState: smartCubeRecoveryState,
            timerSessionID: selectedSession?.id
        ) else { return }
        if let timerSessionID = selectedSession?.id {
            SmartCubeTimerPresentationStore.shared.saveScramble(
                currentScramble, timerSessionID: timerSessionID, puzzleSize: progress.puzzleSize
            )
        }
    }

    @discardableResult
    private func restoreStoredSmartCubePresentation() -> Bool {
        let context = scrambleGenerationContext
        guard let snapshot = SmartCubeTimerPresentationStore.shared.snapshot,
              snapshot.timerSessionID == selectedSession?.id,
              snapshot.progress.puzzleSize == (context.event == .twoByTwo ? 2 : 3) else {
            guard let timerSessionID = selectedSession?.id,
                  let scramble = SmartCubeTimerPresentationStore.shared.restoredScramble(
                    timerSessionID: timerSessionID, puzzleSize: context.event == .twoByTwo ? 2 : 3
                  ),
                  let progress = SmartCubeScrambleProgress(
                    scramble: scramble, puzzleSize: context.event == .twoByTwo ? 2 : 3
                  ) else { return false }
            // Restore the target, never fabricate move continuity or resume a
            // timed solve from a prior process. Fresh BLE state verifies it.
            currentScramble = scramble
            displayedScrambleContext = context
            smartCubeScrambleProgress = progress
            smartCubeScrambleEpoch.establish(at: .now, latestMoveID: smartCube.latestMove?.id,
                                             canonicalSequence: smartCube.canonicalSequence)
            restoredSmartCubeEvent = context.event
            return true
        }
        currentScramble = snapshot.scramble
        displayedScrambleContext = context
        smartCubeScrambleProgress = snapshot.progress
        smartCubeScrambleEpoch = snapshot.epoch
        smartCubeRecoveryState = snapshot.recoveryState
        smartCubeHighlightedTokenIndex = snapshot.recoveryState.plan == nil
            ? snapshot.progress.currentMoveTokenIndex
            : nil
        restoredSmartCubeEvent = context.event
        return true
    }

    private func rehydrateSmartCubePresentation() {
        guard usesSmartCubeInput, !isRunning else { return }
        if smartCubeScrambleProgress == nil {
            _ = restoreStoredSmartCubePresentation()
        }
        consumePendingSmartCubeUpdates()
        guard var progress = smartCubeScrambleProgress else { return }

        cancelSmartCubeRecoveryTask()
        guard let facelets = smartCube.facelets, smartCube.hasTrustedCanonicalState else {
            smartCubeHighlightedTokenIndex = progress.currentMoveTokenIndex
            #if DEBUG
            let reason = smartCube.facelets == nil ? "current-facelets-unavailable" : "continuity-untrusted"
            SmartCubeDiagnostics.shared.guidance("waiting reason=\(reason)")
            #endif
            cacheSmartCubePresentation()
            return
        }

        _ = progress.update(with: facelets)
        if !progress.isComplete { smartCubeScrambleEpoch.observeScrambleDeparture() }
        let identity = smartCubeScrambleEpoch.advanceRecoveryStateVersion()
        if progress.isDeviated || progress.needsGuidanceSearch {
            let guaranteedPlan = progress.guaranteedRecoveryPlan(
                identity: identity,
                sourceFacelets: facelets
            )
            let state = SmartCubeReplacementPlanner.initialPresentation(
                recovery: guaranteedPlan,
                identity: identity,
                sourceFacelets: facelets
            )
            publishSmartCubePresentation(progress: progress, recoveryState: state)
            beginSmartCubeGuidanceSearch(
                from: facelets,
                identity: identity,
                guaranteedPlan: guaranteedPlan
            )
        } else {
            publishSmartCubePresentation(progress: progress, recoveryState: .inactive)
        }
    }

    private var smartCubeProgressAnimation: Animation? {
        switch resolvedSmartCubeScrambleTransition {
        case .blur:
            return .easeOut(duration: 0.26)
        case .fade:
            return .easeOut(duration: 0.2)
        case .slide:
            return .easeInOut(duration: 0.24)
        case .bounce:
            return .spring(duration: 0.32, bounce: 0.38)
        case .instant:
            return nil
        }
    }

    private func finishSmartCubeSolve(endMove: SmartCubeMoveEvent? = nil, weiPoTurnObservedAt: Date? = nil) {
        let recognizedAt = Date.now
        #if DEBUG
        SmartCubeDiagnostics.shared.mark("solve.recognized", id: endMove?.id)
        #endif
        guard isRunning, let startMove = smartCubeSolveStartMove else { return }
        let timing: SmartCubeSolveTiming?
        if let weiPoTurnObservedAt {
            let duration = weiPoTurnObservedAt.timeIntervalSince(startMove.localTimestamp)
            timing = duration.isFinite && duration > 0 ? .init(startDate: startMove.localTimestamp,
                endDate: weiPoTurnObservedAt, duration: duration) : nil
        } else {
            timing = SmartCubeSolveTiming.resolved(startMove: startMove, endMove: endMove ?? smartCube.latestMove,
                solvedObservedAt: recognizedAt)
        }
        guard let timing else { return }
        invalidateTimer()
        isRunning = false
        let duration = timing.duration
        let finishDate = timing.endDate
        elapsedSeconds = duration
        let result = currentSolveInspectionPenalty ?? .solved
        currentSolveInspectionPenalty = nil
        smartCubeSolveLifecycle.solveDidFinish()
        smartCubeSolveStartMove = nil
        timerStartDate = nil
        showingResultPopup = false

        guard let assignment = activeSolveAssignment,
              let selectedSession = try? modelContext.fetchSession(with: assignment.sessionID) else { return }
        let solve = Solve(
            time: duration,
            date: finishDate,
            scramble: assignment.scramble,
            event: assignment.event.rawValue,
            result: result,
            inputSource: .smartCube,
            reconstruction: reconstructionCapture.reconstruction(),
            session: selectedSession,
            context: modelContext
        )
        #if DEBUG
        SmartCubeDiagnostics.shared.finish(
            start: startMove, end: weiPoTurnObservedAt == nil ? endMove ?? smartCube.latestMove : nil,
            recognizedAt: recognizedAt, storedSeconds: solve.time, displayedSeconds: elapsedSeconds
        )
        #endif
        let didPersist = persistSolveChangesAndRefresh(completedSolveID: solve.id)
        #if DEBUG
        if weiPoTurnObservedAt != nil {
            SmartCubeDiagnostics.shared.mark("weiPo.timing-completed", id: startMove.id,
                detail: "event=\(assignment.event.rawValue) persisted=\(didPersist) duration=\(duration)")
        }
        #endif
        reconstructionCapture.reset()
        activeSolveAssignment = nil
        pendingSolveScramble = nil
        generateNewScramble()
    }

    private func resetSmartCubeTimerState() {
        cancelSmartCubeRecovery()
        SmartCubeTimerPresentationStore.shared.clear()
        smartCubeScrambleProgress = nil
        smartCubeScrambleEpoch.reset()
        smartCubeSolveLifecycle.reset()
        if pendingSolveTime == nil { activeSolveAssignment = nil }
        smartCubeSolveStartMove = nil
        smartCubeIsReady = false
        reconstructionCapture.reset()
        combinedSolveLifecycle.reset()
        pendingWeiPoCombinedStop = nil
        if isInspecting {
            isInspecting = false
            inspectionStartDate = nil
            inspectionElapsed = 0
            announcedInspectionCheckpoints = []
            currentSolveInspectionPenalty = nil
            invalidateTimer()
        }
    }

    private func handleGANTimerStateChange(_ state: GANTimerConnectionState) {
        guard localBattleMode == .solo else { return }
        guard usesGANTimerInput else { return }
        if usesCombinedInput {
            handleCombinedGANTimerStateChange(state)
            return
        }

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
            if !isRunning {
                activeSolveAssignment = currentSolveAssignment
                pendingSolveScramble = activeSolveAssignment?.scramble
                scrambleRequestToken = UUID()
            }
            if isInspecting {
                currentSolveInspectionPenalty = inspectionPenalty(for: inspectionStartDate.map { max(0, Date().timeIntervalSince($0)) } ?? inspectionElapsed)
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
        guard localBattleMode == .solo else { return }
        invalidateTimer()
        isRunning = false
        isPressingToArm = false
        isReadyToStart = false

        guard seconds > 0 else { return }
        if activeSolveAssignment == nil { activeSolveAssignment = currentSolveAssignment }
        pendingSolveScramble = activeSolveAssignment?.scramble ?? scrambleToSave
        pendingSolveTime = seconds
        pendingInspectionPenalty = nil
        pendingSolveInputSource = .bluetoothTimer
        pendingSolveReconstruction = nil
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

    private func handleCombinedGANTimerStateChange(_ state: GANTimerConnectionState) {
        defer { synchronizeCombinedReadinessUI() }
        switch state {
        case .handsOn:
            if !combinedSolveLifecycle.isActive && !isInspecting {
                isPressingToArm = true
                isReadyToStart = false
            }
        case .ready:
            if combinedReadiness.isReady && !combinedSolveLifecycle.isActive && !isInspecting && !isReadyToStart {
                triggerReadyHaptic()
            }
            if !combinedSolveLifecycle.isActive && !isInspecting {
                isPressingToArm = true
                isReadyToStart = combinedReadiness.isReady
            }
        case .running:
            beginCombinedSolveFromTimer(startedAt: ganTimer.activeRunStartedAt)
        case .disconnected, .bluetoothUnavailable, .unauthorized, .failed:
            handleCombinedCompletion(combinedSolveLifecycle.timerDidDisconnect())
        case .connected:
            if combinedSolveLifecycle.isActive {
                handleCombinedCompletion(combinedSolveLifecycle.timerDidDisconnect())
            }
        case .finished:
            break
        case .scanning, .connecting:
            break
        }
    }

    private func beginCombinedSolveFromTimer(startedAt: Date?) {
        guard !combinedSolveLifecycle.isActive, pendingSolveTime == nil else { return }
        let readiness = combinedReadiness
        let initialFacelets = smartCube.puzzleSize == 2
            ? smartCube.facelets
            : smartCubeScrambleProgress?.targetFacelets ?? smartCube.facelets
        guard let startedAt,
              combinedSolveLifecycle.timerDidStart(readiness: readiness),
              let initialFacelets
        else {
            isPressingToArm = false
            isReadyToStart = false
            #if DEBUG
            SmartCubeDiagnostics.shared.guidance(
                "combined unavailable reason=devices-not-ready readiness=\(readiness) anchor=\(startedAt == nil ? "missing" : "ready")",
                force: true
            )
            #endif
            return
        }
        reconstructionCapture.start(initialFacelets: initialFacelets, at: startedAt)
        activeSolveAssignment = currentSolveAssignment
        pendingSolveScramble = activeSolveAssignment?.scramble ?? scrambleToSave
        scrambleRequestToken = UUID()

        if isInspecting {
            currentSolveInspectionPenalty = inspectionPenalty(for: inspectionStartDate.map { max(0, startedAt.timeIntervalSince($0)) } ?? inspectionElapsed)
            isInspecting = false
            inspectionStartDate = nil
            inspectionElapsed = 0
        }

        elapsedSeconds = 0
        timerStartDate = startedAt
        isPressingToArm = false
        isReadyToStart = false
        isRunning = true
        startDisplayTimer()
    }

    private func handleCombinedTimerCompletion(_ solve: GANTimerCompletedSolve) {
        guard usesCombinedInput, combinedSolveLifecycle.isActive else { return }
        isRunning = false
        isPressingToArm = false
        isReadyToStart = false
        invalidateTimer()
        let completion = combinedSolveLifecycle.timerDidStop(seconds: solve.seconds)
        if case .save(let seconds) = completion,
           usesWeiPo2NativeVisual, smartCube.weiPo2PendingSnapshotCount > 0 {
            let pending = PendingWeiPoCombinedStop(id: UUID(), seconds: seconds, stoppedAt: solve.stoppedAt)
            pendingWeiPoCombinedStop = pending
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard pendingWeiPoCombinedStop?.id == pending.id else { return }
                finishPendingWeiPoCombinedStop(force: true)
            }
            return
        }
        pendingSolveReconstruction = reconstructionCapture.reconstruction(
            puzzleSize: smartCube.puzzleSize,
            combinedTimerStoppedAt: solve.stoppedAt
        )
        handleCombinedCompletion(completion)
    }

    private func finishPendingWeiPoCombinedStop(force: Bool = false) {
        guard let pending = pendingWeiPoCombinedStop,
              force || smartCube.weiPo2PendingSnapshotCount == 0 else { return }
        pendingWeiPoCombinedStop = nil
        if smartCube.weiPo2PendingSnapshotCount > 0 {
            reconstructionCapture.markIncomplete(.historyGap)
        }
        pendingSolveReconstruction = reconstructionCapture.reconstruction(
            puzzleSize: smartCube.puzzleSize,
            combinedTimerStoppedAt: pending.stoppedAt
        )
        handleCombinedCompletion(.save(seconds: pending.seconds))
    }

    private func handleCombinedCompletion(_ completion: CombinedSolveLifecycle.Completion) {
        switch completion {
        case .none:
            break
        case .timerInterrupted:
            pendingWeiPoCombinedStop = nil
            reconstructionCapture.markIncomplete(.disconnected)
            invalidateTimer()
            isRunning = false
            isPressingToArm = false
            isReadyToStart = false
            smartCubeIsReady = false
            #if DEBUG
            SmartCubeDiagnostics.shared.guidance("combined interrupted reason=timer-disconnected", force: true)
            #endif
            pendingSolveScramble = nil
            reconstructionCapture.reset()
            combinedSolveLifecycle.reset()
        case .save(let seconds):
            pendingSolveTime = seconds
            pendingInspectionPenalty = currentSolveInspectionPenalty
            pendingSolveInputSource = .smartCubeAndBluetoothTimer
            currentSolveInspectionPenalty = nil
            let stopFacelets: String?
            let stopStateTrusted: Bool
            if usesWeiPo2NativeVisual {
                let reconstruction = pendingSolveReconstruction
                stopFacelets = reconstruction?.facelets(afterMoveCount: reconstruction?.moves.count ?? 0)
                stopStateTrusted = smartCube.hasTrustedCanonicalState
                    && reconstruction?.completeness == .complete
            } else {
                stopFacelets = smartCube.facelets
                stopStateTrusted = smartCube.hasTrustedCanonicalState
            }
            ganPendingResultSelection = CombinedPhysicalResultClassifier.result(
                facelets: stopFacelets,
                isStateTrusted: stopStateTrusted
            )
            ganResultPressCount = 0
            ganResultCommitToken = UUID()
            ganResultCommitProgress = 0
            showingResultPopup = ganShowResultPopup
            if !ganShowResultPopup {
                savePendingSolve(as: ganPendingResultSelection)
            } else if resolvedGANResultInputMode == .cycle {
                scheduleGANResultCommit(after: ganResultAutoCommitDelay)
            }
        }
    }

    private func handleGANInspectionToggle() {
        guard !isRunning, !showingResultPopup else { return }

        if isInspecting {
            cancelInspection()
        } else {
            startInspection()
        }
    }

    private func handleGANResultSelectionButtonPress() {
        guard usesGANTimerInput, pendingSolveTime != nil, !isRunning else { return }

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
        guard let assignment = activeSolveAssignment ?? currentSolveAssignment,
              let selectedSession = try? modelContext.fetchSession(with: assignment.sessionID),
              let pendingSolveTime, pendingSolveTime > 0 else {
            discardPendingSolve()
            return
        }

        let finalResult = InspectionPenaltyPolicy.result(result, inspectionPenalty: pendingInspectionPenalty)

        let solve = Solve(
            time: pendingSolveTime,
            date: .now,
            scramble: pendingSolveScramble ?? assignment.scramble,
            event: assignment.event.rawValue,
            result: finalResult,
            inputSource: pendingSolveInputSource ?? assignment.inputSource,
            reconstruction: pendingSolveReconstruction,
            session: selectedSession,
            context: modelContext
        )
        persistSolveChangesAndRefresh(completedSolveID: solve.id)
        discardPendingSolve()
        generateNewScramble()
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
        pendingSolveInputSource = nil
        pendingSolveReconstruction = nil
        pendingSolveScramble = nil
        activeSolveAssignment = nil
        reconstructionCapture.reset()
        combinedSolveLifecycle.reset()
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
                let elapsed = max(0, Date().timeIntervalSince(inspectionStartDate))
                currentSolveInspectionPenalty = inspectionPenalty(for: elapsed)
                if usesSmartCubeInput && !usesCombinedInput {
                    smartCubeSolveLifecycle.inspectionDidAdvance(elapsed: elapsed)
                    inspectionElapsed = min(elapsed, 17)
                } else {
                    inspectionElapsed = elapsed
                }
                announceInspectionCheckpointsIfNeeded()
                if usesSmartCubeInput && !usesCombinedInput && currentSolveInspectionPenalty == .dnf {
                    // Keep the inspection anchor for the first physical solve move,
                    // but the expired inspection no longer counts forever.
                    displayTimer?.invalidate()
                    displayTimer = nil
                }
            }
            if usesGANTimerInput, isRunning {
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
            localBattleDevices.setEnabled(false)
            resetLocalBattleTimers()
            resetLocalBattleScores()
            localBattleScrambles = LocalBattleScrambleState()
        } else {
            if mode != .nearby {
                configureLocalBattleDevices()
            } else { localBattleDevices.setEnabled(false) }
            if localBattleMode == .solo {
                if usesSmartCubeInput { resetSmartCubeTimerState() }
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
        if mode == .solo, usesSmartCubeInput { prepareSmartCubeScrambleTarget(); updateSmartCubeConnectionReadiness() }
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

    private func configureLocalBattleDevices() {
        localBattleDevices.setEnabled(true)
        localBattleDevices.start = { player, date in startLocalBattleTimer(for: player, startedAt: date) }
        localBattleDevices.finish = { player, date in stopLocalBattleTimer(for: player, stoppedAt: date) }
        localBattleDevices.finishSmartTimer = { player, solve in
            stopLocalBattleTimer(for: player, stoppedAt: solve.stoppedAt, hardwareSeconds: solve.seconds)
        }
        localBattleDevices.invalidate = cancelLocalBattlePlayer
        for player in LocalBattlePlayer.allCases {
            if let assignment = localBattleScrambles.displayed[player], localBattleScrambles.requests[player] == nil {
                localBattleDevices.setTarget(assignment.text, event: assignment.request.event,
                    assignment: assignment.request.id, for: player)
            }
            if !didScoreCurrentLocalBattleRound, localBattleRoundTime(for: player) != nil { localBattleDevices.complete(player) }
        }
    }

    private func resetLocalBattleScrambles() {
        localBattleScrambles = LocalBattleScrambleState()
        for player in LocalBattlePlayer.allCases { requestLocalBattleScramble(for: player) }
    }

    private func resetLocalBattleEvents() {
        localBattleFirstEvent = selectedEvent
        localBattleSecondEvent = selectedEvent
        for player in LocalBattlePlayer.allCases { reconcileLocalBattleCube(for: player, event: selectedEvent) }
    }

    private func localBattleScramble(for player: LocalBattlePlayer) -> String {
        localBattleScrambles.failures[player] ?? localBattleScrambles.displayed[player]?.text ?? "…"
    }

    private func requestLocalBattleScramble(for player: LocalBattlePlayer) {
        let event = localBattleEvent(for: player)
        let request = localBattleScrambles.request(player, event: event)
        localBattleDevices.setTarget(nil, event: event, assignment: nil, for: player)
        let context = TimerScrambleGenerationContext(sessionID: nil, event: event,
            multiBlindCount: mblindScrambleCount,
            unavailableMessage: appLocalizedString("timer.scramble_unavailable", languageCode: appLanguage))
        generateTimerScramble(for: context, reason: "battle", prepareDiagram: false) { payload in
            guard localBattleEvent(for: player) == event,
                  payload.context == context else { return }
            let text = payload.scrambles.joined(separator: "\n")
            guard !text.isEmpty, !text.hasPrefix(context.unavailableMessage) else {
                localBattleScrambles.fail(context.unavailableMessage, for: request)
                return
            }
            if localBattleScrambles.receive(text, for: request) {
                localBattleDevices.setTarget(text, event: event, assignment: request.id, for: player)
            }
        }
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
              !localBattleIsPressing(player),
              localBattleEvent(for: player) != event
        else { return }

        switch player {
        case .first:
            localBattleFirstEvent = event
        case .second:
            localBattleSecondEvent = event
        }
        reconcileLocalBattleCube(for: player, event: event)
        requestLocalBattleScramble(for: player)
    }

    private func reconcileLocalBattleCube(for player: LocalBattlePlayer, event: PuzzleEvent) {
        var configuration = localBattleDevices.configuration(player)
        if configuration.input == .smartCube {
            if !localBattleDevices.canUseSmartCube(event) { configuration.input = .touch }
            if let id = configuration.deviceID, !localBattleDevices.devices(for: event, player: player).contains(id) {
                configuration.deviceID = nil
            }
            localBattleDevices.setConfiguration(configuration, for: player)
        }
    }

    private var canEditLocalBattleHandicap: Bool {
        !isLocalBattleFirstRunning && !isLocalBattleSecondRunning && !isLocalBattleFirstPressing && !isLocalBattleSecondPressing
            && (didScoreCurrentLocalBattleRound || (localBattleFirstRoundTime == nil && localBattleSecondRoundTime == nil))
    }

    private func setLocalBattleHandicap(for player: LocalBattlePlayer, seconds: Int) {
        guard canEditLocalBattleHandicap else { return }
        localBattleHandicap.set(seconds, for: player)
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

    private func localBattleOpponent(of player: LocalBattlePlayer) -> LocalBattlePlayer {
        switch player {
        case .first:
            return .second
        case .second:
            return .first
        }
    }

    private func pressLocalBattleTimer(for player: LocalBattlePlayer) {
        guard localBattleDevices.configuration(player).input == .touch else { return }
        prepareNextLocalBattleRoundIfNeeded()
        guard !localBattleIsRunning(player), localBattleRoundTime(for: player) == nil else { return }
        setLocalBattlePressing(true, for: player)
        triggerReadyHaptic()
    }

    private func releaseLocalBattleTimer(for player: LocalBattlePlayer) {
        guard localBattleDevices.configuration(player).input == .touch else { return }
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
        guard opponentCanStart || localBattleDevices.configuration(opponentPlayer).input != .touch else { return }
        startLocalBattleTimer(for: player)
    }

    @discardableResult private func startLocalBattleTimer(for player: LocalBattlePlayer, startedAt: Date = .now) -> Bool {
        prepareNextLocalBattleRoundIfNeeded()
        guard localBattleScrambles.begin(player, event: localBattleEvent(for: player)) else { return false }

        switch player {
        case .first:
            localBattleFirstElapsed = 0
            localBattleFirstStartDate = startedAt
            isLocalBattleFirstRunning = true
            localBattleFirstRoundTime = nil
        case .second:
            localBattleSecondElapsed = 0
            localBattleSecondStartDate = startedAt
            isLocalBattleSecondRunning = true
            localBattleSecondRoundTime = nil
        }
        startLocalBattleDisplayTimerIfNeeded()
        return true
    }

    private func stopLocalBattleTimer(for player: LocalBattlePlayer, stoppedAt: Date = .now, hardwareSeconds: Double? = nil) {
        guard localBattleIsRunning(player), localBattleScrambles.finish(player) != nil else { return }
        switch player {
        case .first:
            if let localBattleFirstStartDate {
                localBattleFirstElapsed = hardwareSeconds ?? max(0, stoppedAt.timeIntervalSince(localBattleFirstStartDate))
            }
            localBattleFirstRoundTime = localBattleFirstElapsed
            localBattleFirstDisplayTime = localBattleHandicap.adjusted(localBattleFirstElapsed, for: .first)
            localBattleFirstStartDate = nil
            isLocalBattleFirstRunning = false
            isLocalBattleFirstPressing = false
        case .second:
            if let localBattleSecondStartDate {
                localBattleSecondElapsed = hardwareSeconds ?? max(0, stoppedAt.timeIntervalSince(localBattleSecondStartDate))
            }
            localBattleSecondRoundTime = localBattleSecondElapsed
            localBattleSecondDisplayTime = localBattleHandicap.adjusted(localBattleSecondElapsed, for: .second)
            localBattleSecondStartDate = nil
            isLocalBattleSecondRunning = false
            isLocalBattleSecondPressing = false
        }

        scoreLocalBattleRoundIfReady()
        requestLocalBattleScramble(for: player)
        localBattleDevices.complete(player)
        if didScoreCurrentLocalBattleRound { localBattleDevices.nextRound() }

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

    private func cancelLocalBattlePlayer(_ player: LocalBattlePlayer) {
        localBattleScrambles.cancel(player)
        if player == .first {
            isLocalBattleFirstRunning = false; localBattleFirstStartDate = nil; localBattleFirstElapsed = 0
        } else {
            isLocalBattleSecondRunning = false; localBattleSecondStartDate = nil; localBattleSecondElapsed = 0
        }
        if !isLocalBattleFirstRunning && !isLocalBattleSecondRunning { invalidateLocalBattleTimer() }
    }

    private func submitLocalBattleManual(_ player: LocalBattlePlayer, _ raw: String) -> Bool {
        guard localBattleDevices.configuration(player).input == .manual, !localBattleIsRunning(player) else { return false }
        prepareNextLocalBattleRoundIfNeeded()
        guard localBattleRoundTime(for: player) == nil,
              let value = ManualTimeParser.candidates(raw, mode: .fixed, format: localBattleDevices.configuration(player).format).first?.seconds,
              value > 0, localBattleScrambles.begin(player, event: localBattleEvent(for: player)),
              localBattleScrambles.finish(player) != nil else { return false }
        if player == .first { localBattleFirstElapsed = value; localBattleFirstRoundTime = value; localBattleFirstDisplayTime = localBattleHandicap.adjusted(value, for: .first) }
        else { localBattleSecondElapsed = value; localBattleSecondRoundTime = value; localBattleSecondDisplayTime = localBattleHandicap.adjusted(value, for: .second) }
        localBattleDevices.complete(player); scoreLocalBattleRoundIfReady(); requestLocalBattleScramble(for: player)
        if didScoreCurrentLocalBattleRound { localBattleDevices.nextRound() }
        return true
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
        didScoreCurrentLocalBattleRound = false
    }

    private func scoreLocalBattleRoundIfReady() {
        guard !didScoreCurrentLocalBattleRound,
              let firstTime = localBattleFirstRoundTime,
              let secondTime = localBattleSecondRoundTime
        else { return }

        let adjustedFirstTime = localBattleHandicap.adjusted(firstTime, for: .first)
        let adjustedSecondTime = localBattleHandicap.adjusted(secondTime, for: .second)

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
        InspectionPenaltyPolicy.penalty(for: elapsed)
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
        #if DEBUG
        if let previewValue = marketingPreviewStatisticValue(for: metric) {
            let previewPresentation = formattedAveragePresentation(max(0, previewValue))
            return TimerStatisticDisplayItem(
                metric: metric,
                title: appLocalizedString(
                    metric.localizedKey,
                    languageCode: appLanguage,
                    defaultValue: metric.defaultTitle
                ),
                value: previewPresentation.value,
                isAvailable: previewPresentation.isAvailable
            )
        }
        #endif
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
            isAvailable: presentation.isAvailable,
            isPersonalBest: timerPBState.metrics.contains(metric.rawValue)
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
        formatDisplayedTime(seconds, decimals: timerDecimals)
    }

    private func formatDisplayedTime(_ seconds: Double, decimals: Int) -> String {
        SolveMetrics.formatTime(
            seconds,
            decimals: decimals,
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

    private var manualCandidates: [ManualTimeCandidate] {
        ManualTimeParser.candidates(manualDraft.raw,
            mode: ManualTimeInterpretation(rawValue: manualInterpretation) ?? .fixed,
            format: ManualTimeFormat(rawValue: manualFormat) ?? .defaultFormat)
    }

    private var selectedManualTime: ManualTimeCandidate? {
        ManualTimeParser.preferred(manualCandidates, reference: manualReference,
            defaultPrecision: ManualTimePrecision(rawValue: manualDefault) ?? .hundredths, override: nil)
    }

    private static let inspectionExitDiameter: CGFloat = 44
    private static let inspectionCornerExitDiameter: CGFloat = 48

    @ViewBuilder
    private func inspectionExitLayer(_ anchor: Anchor<CGRect>?) -> some View {
        // Match the timer's full-viewport geometry, not the tab bar's changing content region.
        GeometryReader { proxy in
            if localBattleMode == .solo && isInspecting {
                if hideElementsWhenSolving {
                    if #available(iOS 16.0, *) {
                        cornerInspectionExit(inset: inspectionCornerInset(in: proxy))
                    } else {
                        // The iOS 15 tab bar remains visible during inspection.
                        cornerInspectionExit(inset: TimerArrangementLayout.outerInset)
                    }
                } else if let anchor {
                    let timerFrame = proxy[anchor]
                    let halfAvailableWidth = min(timerFrame.midX, proxy.size.width - timerFrame.midX)
                    VStack(spacing: 8) {
                        inspectionExitCapsule
                            .frame(maxWidth: max(Self.inspectionExitDiameter, 2 * halfAvailableWidth - 16))
                        if usesSmartCubeInput, showsSmartCubeClassicStatistics {
                            smartCubeClassicStatistics(width: timerFrame.width)
                                .frame(width: timerFrame.width)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.top, max(0, timerFrame.maxY) + 8)
                    .frame(maxWidth: .infinity)
                    .offset(x: timerFrame.midX - proxy.size.width / 2)
                }
            }
        }
        .ignoresSafeArea(.container, edges: inspectionExitViewportEdges)
    }

    private var inspectionExitViewportEdges: Edge.Set {
        if #available(iOS 16.0, *) { return .all }
        return hideElementsWhenSolving ? [] : .all
    }

    private func inspectionCornerInset(in proxy: GeometryProxy) -> CGFloat {
        let isRTL = layoutDirection == .rightToLeft
        let clearanceReduction: CGFloat = 6
        let minimumClearance: CGFloat = 8
        let buttonRadius = Self.inspectionCornerExitDiameter / 2
        if #available(iOS 27.0, *), let radii = proxy.concentricCornerRadii {
            let radius = isRTL ? radii.bottomTrailing : radii.bottomLeading
            if radius > buttonRadius {
                return max(minimumClearance, radius - buttonRadius - clearanceReduction)
            }
        }
        if #available(iOS 26.0, *) {
            let insets = proxy.containerCornerInsets
            let corner = isRTL ? insets.bottomTrailing : insets.bottomLeading
            let extent = max(corner.width, corner.height)
            if extent > buttonRadius {
                return max(minimumClearance, extent - buttonRadius - clearanceReduction)
            }
        }
        // Equal distances keep the control on the corner diagonal without a device model table.
        return minimumClearance
    }

    private func cornerInspectionExit(inset: CGFloat) -> some View {
        Button(action: cancelInspection) {
            Image(systemName: "xmark")
                .font(.system(size: 22, weight: .medium))
                .frame(width: Self.inspectionCornerExitDiameter, height: Self.inspectionCornerExitDiameter)
                .contentShape(Circle())
                .compatibleGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("timer.inspection.exit_accessibility"))
        .accessibilityIdentifier("timer-inspection-exit")
        .padding(inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: layoutDirection == .rightToLeft ? .bottomTrailing : .bottomLeading)
    }

    private var inspectionExitCapsule: some View {
        Group {
            if #available(iOS 26.0, *) {
                TimerInspectionNativeExitButton(
                    title: appLocalizedString("timer.inspection.exit", languageCode: appLanguage),
                    label: appLocalizedString("timer.inspection.exit_accessibility", languageCode: appLanguage),
                    tint: UIColor(Color.accentColor),
                    action: cancelInspection
                )
            } else {
                Button(action: cancelInspection) {
                    Text("timer.inspection.exit")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .compatibleTintedGlass(.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(.interaction, Rectangle().inset(by: -6))
        .accessibilityLabel(Text("timer.inspection.exit_accessibility"))
        .accessibilityIdentifier("timer-inspection-exit")
        .frame(minWidth: Self.inspectionExitDiameter, minHeight: Self.inspectionExitDiameter, alignment: .top)
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
                .accessibilityIdentifier("timer-time-display")
        }
    }

    private var timerArrangementCenterLayer: some View {
        GeometryReader { proxy in
            let geometry = timerArrangementGeometry(for: proxy.size)

            if smartCubeConnectionIsLoading && smartCube.facelets == nil &&
                (!usesWeiPo2NativeVisual || smartCube.weiPo2VisualFacelets == nil) {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("smart_cube.timer.loading")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .position(geometry.timerCenter)
                .accessibilityElement(children: .combine)
            } else if usesSmartCubeInput {
                smartCubeCenterComposition(geometry: geometry)
            } else {
                timerDisplayView
                    .anchorPreference(key: TimerExclusionAnchorPreferenceKey.self, value: .bounds) { $0 }
                    .background {
                        GeometryReader { textProxy in
                            Color.clear.preference(key: TimerRenderedFramePreferenceKey.self,
                                value: textProxy.frame(in: .named(TimerLayoutCoordinateSpace.name)))
                        }
                    }
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
                        .timerPBObstacle()
                        .position(
                            x: geometry.classicStatisticsFrame.midX,
                            y: geometry.classicStatisticsFrame.midY
                        )
                }
            }
        }
    }

    private func smartCubeCenterComposition(
        geometry: TimerArrangementLayout.Geometry
    ) -> some View {
        let size = CGSize(
            width: SmartCubeLayoutDimensions.length(geometry.containerSize.width),
            height: SmartCubeLayoutDimensions.length(geometry.containerSize.height)
        )
        let sideGap: CGFloat = 12
        let outerInset = TimerArrangementLayout.outerInset
        let columnWidth = max(1, (size.width - 2 * outerInset - sideGap) / 2)
        let cubeIsLeading = resolvedSmartCubeTimerPosition == .right
        let isCentered = resolvedSmartCubeTimerLayout == .centered && smartCubeShowVirtualCube
        let leadingX = outerInset + columnWidth / 2
        let trailingX = size.width - outerInset - columnWidth / 2
        let center = CGPoint(
            x: isCentered
                ? (geometry.timerCenter.x.isFinite ? geometry.timerCenter.x : size.width / 2)
                : (cubeIsLeading ? leadingX : trailingX),
            y: geometry.timerCenter.y.isFinite ? geometry.timerCenter.y : size.height / 2
        )
        let lowerBoundary = SmartCubeLayoutDimensions.length(smartCubeLowerContentBoundary(geometry: geometry))
        let identityHeight: CGFloat = usesCombinedInput ? 88 : 44
        let verticalRoom = max(0, lowerBoundary - center.y - (isCentered ? 12 : identityHeight + 12)) * 2
        let preferredCubeSize = min(isCentered ? size.width * 0.43 : columnWidth, size.height * 0.29, 196)
        let cubeSize = smartCubeShowVirtualCube
            ? max(96, min(preferredCubeSize, verticalRoom > 0 ? verticalRoom : preferredCubeSize))
            : 0
        let sideMinX = cubeIsLeading ? center.x + cubeSize / 2 + sideGap : outerInset
        let sideMaxX = cubeIsLeading ? size.width - outerInset : center.x - cubeSize / 2 - sideGap
        let timeWidth = isCentered ? max(1, sideMaxX - sideMinX) : columnWidth
        let sideCenter = CGPoint(
            x: isCentered
                ? sideMinX + timeWidth / 2
                : (cubeIsLeading ? trailingX : leadingX),
            y: center.y
        )

        return ZStack {
            if isActive && smartCubeShowVirtualCube {
                SmartCube3DView(
                    facelets: usesWeiPo2NativeVisual ? smartCube.weiPo2VisualFacelets : smartCube.facelets,
                    stateRevision: usesWeiPo2NativeVisual ? smartCube.weiPo2VisualRevision : smartCube.cubeStateRevision,
                    fixedView: SmartCubeFixedView(rawValue: smartCubeFixedViewRawValue) ?? .urf,
                    cubeSize: smartCube.puzzleSize,
                    events: smartCube.canonicalEvents,
                    connectionAttemptID: smartCube.connectionAttemptID,
                    isStateTrusted: smartCube.hasTrustedCanonicalState,
                    diagnosticOwner: "timer",
                    canonicalSequence: smartCube.canonicalSequence,
                    onTap: smartCubeManagementTapAction,
                    renderingEnabled: !showingSmartCubeManagement
                )
                .frame(width: cubeSize, height: cubeSize)
                .position(center)
            }

            if !shouldHideNonTimerContent {
                let identityWidth = isCentered ? min(size.width * 0.6, 220) : columnWidth
                let identityRows = ConnectedDeviceStatusRows(usesCompactLinks: true, showsSmartTimer: usesCombinedInput,
                    cubeRowHorizontalInset: min(12, identityWidth * 0.06), manageCube: openSmartCubeManagement)
                    .buttonStyle(.plain)
                if smartCubeShowVirtualCube {
                    SmartCubeIdentityAnchor(width: identityWidth,
                        origin: CGPoint(x: center.x, y: center.y + cubeSize / 2 + 4)) { identityRows }
                } else {
                    identityRows.frame(width: identityWidth).position(center)
                }
            }

            smartCubeSideTimer(width: timeWidth)
                .frame(width: timeWidth)
                .position(sideCenter)

        }
    }

    private func openSmartCubeManagement() {
        guard isActive, usesSmartCubeInput,
              !isRunning, !isInspecting, !showingResultPopup else { return }
        let connected = smartCube.managementConnectedDeviceIDs
        managedSmartCubeID = smartCube.activeDeviceID.flatMap { connected.contains($0) ? $0 : nil } ?? connected.first
        showingSmartCubeManagement = true
    }

    private var smartCubeManagementTapAction: (() -> Void)? {
        guard !isRunning, !isInspecting, !showingResultPopup else { return nil }
        return { openSmartCubeManagement() }
    }

    private var showsSmartCubeClassicStatistics: Bool {
        resolvedTimerArrangement == .classic && effectiveTimerPresentation.showsStatistics
            && !statisticsDisplayItems.isEmpty
    }

    private func smartCubeClassicStatistics(width: CGFloat) -> some View {
        let statisticsSize = resolvedSmartCubeTimerLayout == .centered
            ? min(resolvedAverageTextFontSize, max(11, width * 0.15))
            : max(minimumSmartCubeStatisticSize, min(resolvedAverageTextFontSize, width * 0.22))
        return TimerStatisticsView(
            items: statisticsDisplayItems,
            layout: .verticalCentered,
            appearance: averageTextAppearance,
            fontDesign: resolvedAverageTextFontDesign,
            fontStyle: resolvedAverageTextFontStyle,
            fontSize: statisticsSize,
            usesAutomaticSize: false,
            prominent: resolvedSmartCubeTimerLayout != .centered
        )
    }

    private func smartCubeSideTimer(width: CGFloat) -> some View {
        let timerSize = min(timerTextFontSize, max(24, width * 0.54))

        return VStack(spacing: 8) {
            configuredText(
                Text(timerText),
                size: timerSize,
                design: resolvedTimerTextFontDesign,
                style: resolvedTimerTextFontStyle
            )
            .monospacedDigit()
            .foregroundStyle(timerTextStyle)
            .lineLimit(1)
            .minimumScaleFactor(0.42)
            .frame(maxWidth: .infinity)
            .anchorPreference(key: TimerExclusionAnchorPreferenceKey.self, value: .bounds) { $0 }
            .overlay {
                if canRestartSmartCubeInspection {
                    Button(action: restartSmartCubeInspection) {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("timer.inspect"))
                    .accessibilityIdentifier("timer-restart-inspection")
                }
            }

            if !shouldHideNonTimerContent && showsSmartCubeReadyStatus {
                Text("settings.gan_status_ready")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
            }

            if showsSmartCubeClassicStatistics && (!shouldHideNonTimerContent || isInspecting) {
                // Keep the digits in place while the inspection layer owns the visible stats.
                smartCubeClassicStatistics(width: width)
                    .opacity(isInspecting ? 0 : 1)
                    .accessibilityHidden(isInspecting)
                    .allowsHitTesting(!isInspecting)
            }
        }
    }

    private func smartCubeLowerContentBoundary(
        geometry: TimerArrangementLayout.Geometry
    ) -> CGFloat {
        switch resolvedTimerArrangement {
        case .classic:
            if let placement = resolvedArrangementDiagramPlacement,
               effectiveTimerPresentation.showsScrambleDiagram {
                return geometry.independentDiagramFrame(
                    placement: placement,
                    aspectRatio: resolvedScrambleDiagramAspectRatio
                ).minY
            }
            return geometry.containerSize.height
        case .split:
            return min(geometry.splitLeadingFrame.minY, geometry.splitTrailingFrame.minY)
        case .cards:
            return min(geometry.leadingCardFrame.minY, geometry.trailingCardFrame.minY)
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
            .timerPBObstacle()
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
                    .allowsHitTesting(enteringTimesWith != "timer")
                    .timerPBObstacle()
                    .position(x: statisticsFrame.midX, y: statisticsFrame.midY)
            }

            if effectiveTimerPresentation.showsScrambleDiagram {
                arrangedDiagram(width: diagramWidth)
                    .timerPBObstacle()
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
                // Read-only statistics (including their glass) must not consume Timer touches.
                .allowsHitTesting(enteringTimesWith != "timer")
                .timerPBObstacle()
                .position(x: statisticsFrame.midX, y: statisticsFrame.midY)
            }

            if effectiveTimerPresentation.showsScrambleDiagram {
                arrangedDiagram(width: min(diagramWidth, CGFloat(resolvedDrawScrambleFloatingSize)))
                    .frame(width: diagramFrame.width, height: diagramFrame.height)
                    .compatibleGlassFromIOS16(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .timerPBObstacle()
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

    private func manualTimeEntryContent(keypadMetrics: ManualKeypadMetrics? = nil) -> some View {
        VStack(spacing: manualTimeEntrySpacing) {
            ManualTimeEntry(draft: $manualDraft,
                interface: ManualInputInterface(rawValue: manualInputInterface) ?? .keyboard,
                selected: selectedManualTime,
                canSave: (selectedManualTime?.seconds ?? 0) > 0 && currentSolveAssignment != nil,
                compact: resolvedTimerArrangement == .classic, save: saveTypedTime, focus: $isTypingFieldFocused,
                keypadMetrics: keypadMetrics ?? ManualKeypadMetrics(width: 300, availableHeight: 360))

            if !shouldHideNonTimerContent,
               resolvedTimerArrangement == .classic,
               effectiveTimerPresentation.showsStatistics,
               !statisticsDisplayItems.isEmpty {
                statisticsDisplayView(layout: .verticalCentered, automaticSize: false)
                    .allowsHitTesting(false)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ManualTimeEntryHeightPreferenceKey.self, value: proxy.size.height)
                    // The keypad allocation is shared with the scramble owner;
                    // only the keyboard path needs a measured exclusion frame.
                    .preference(key: TimerRenderedFramePreferenceKey.self,
                        value: manualInputInterface == ManualInputInterface.keypad.rawValue ? nil
                            : proxy.frame(in: .named(TimerLayoutCoordinateSpace.name)))
                    .onAppear {
                        if manualInputInterface == ManualInputInterface.keypad.rawValue { updateManualEntryHeight(proxy.size.height) }
                    }
                    .onChange(of: proxy.size.height) { height in
                        if manualInputInterface == ManualInputInterface.keypad.rawValue { updateManualEntryHeight(height) }
                    }
            }
        }
        .onPreferenceChange(ManualTimeEntryHeightPreferenceKey.self) { height in
            if manualInputInterface != ManualInputInterface.keypad.rawValue { updateManualEntryHeight(height) }
        }
    }

    private func updateManualEntryHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        if manualTimeEntryHeight != height { manualTimeEntryHeight = height }
        #if DEBUG
        manualProbe?.measuredHeight = height
        #endif
    }

    private var manualTimeInputField: some View { Text(manualDraft.raw).monospacedDigit() }

    private var manualKeypadLayer: some View {
        GeometryReader { proxy in
            let footer = manualKeypadLowerBoundary(in: proxy)
            VStack(spacing: manualKeypadGap) {
                timerTopControls.fixedSize(horizontal: false, vertical: true)
                // This proposal is the actual remainder after the controls,
                // including Dynamic Type. No asynchronous height preference is needed.
                GeometryReader { remainder in
                    let metrics = ManualKeypadMetrics(width: remainder.size.width,
                        availableHeight: remainder.size.height - TimerArrangementLayout.scrambleContentMinimumHeight - manualKeypadGap,
                        displayHeight: min(96, manualDisplayHeight))
                    VStack(spacing: manualKeypadGap) {
                        positionedScrambleArea(availableHeight: max(0, remainder.size.height - metrics.height - manualKeypadGap))
                        manualTimeEntryContent(keypadMetrics: metrics)
                            .frame(height: metrics.height)
                            #if DEBUG
                            .background { GeometryReader { entry in Color.clear.preference(key: ManualEntryFrameKey.self,
                                value: ["viewport": entry.frame(in: .global)]) } }
                            #endif
                    }
                }
            }
            .padding(.horizontal, TimerArrangementLayout.timerContentHorizontalInset)
            .frame(width: proxy.size.width, height: max(0, footer - manualKeypadGap), alignment: .top)
        }
    }

    private func manualKeypadLowerBoundary(in proxy: GeometryProxy) -> CGFloat {
        let origin = proxy.frame(in: .named(TimerLayoutCoordinateSpace.name)).minY
        guard effectiveTimerPresentation.showsStatistics || showsArrangedDiagram else { return proxy.size.height }
        let geometry = timerArrangementGeometry(for: proxy.size)
        return switch resolvedTimerArrangement {
        case .classic: showsArrangedDiagram ? floatingScrambleFrame.map { $0.minY - origin } ?? proxy.size.height : proxy.size.height
        case .split: min(geometry.splitLeadingFrame.minY, geometry.splitTrailingFrame.minY)
        case .cards: min(geometry.leadingCardFrame.minY, geometry.trailingCardFrame.minY)
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
        guard let parsed = selectedManualTime?.seconds,
              let assignment = currentSolveAssignment,
              manualDraft.savedRequestID != assignment.requestID,
              let selectedSession = try? modelContext.fetchSession(with: assignment.sessionID),
              parsed > 0 else { return }

        let solve = Solve(
            time: parsed,
            date: .now,
            scramble: assignment.scramble,
            event: assignment.event.rawValue,
            result: .solved,
            inputSource: .manualEntry,
            session: selectedSession,
            context: modelContext
        )
        guard persistSolveChangesAndRefresh(completedSolveID: solve.id) else { modelContext.delete(solve); return }
        _ = manualDraft.consume(requestID: assignment.requestID)
        isTypingFieldFocused = false
        generateNewScramble()
    }

    @discardableResult
    private func persistSolveChangesAndRefresh(completedSolveID: UUID? = nil) -> Bool {
        do { try modelContext.save() } catch { return false }
        refreshSolveSnapshots(requiredForCompletedSolve: true)
        if let completedSolveID {
            celebrationID = nil
            currentResultPB.completed(completedSolveID, records: timerPBState)
        }
        if let completedSolveID, celebrationGate.accept(completedSolveID: completedSolveID, state: timerPBState) {
            celebrationID = completedSolveID
        }
        refreshStreakSnapshots()
        NotificationCenter.default.post(name: solvesDidChangeNotification, object: nil)
        return true
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
    private func synchronizeSelectedSession(idRawValue: String, refreshStatistics: Bool = true) -> PuzzleEvent {
        let requestedSession = UUID(uuidString: idRawValue).flatMap { sessionID in
            sessions.first(where: { $0.id == sessionID })
                ?? (try? modelContext.fetchSession(with: sessionID))
        }
        guard let session = requestedSession ?? selectedSession else {
            if refreshStatistics { refreshSolveSnapshots(for: selectedEvent) }
            return selectedEvent
        }

        let configuration = session.restoreTimerConfiguration(
            legacyTimingMethodRawValue: enteringTimesWith
        )
        let restoredEvent = PuzzleEvent(rawValue: configuration.eventRawValue) ?? .threeByThree
        let sessionEvent = configuration.timingMethod.usesSmartCube && smartCube.isConnected
            ? (smartCube.puzzleSize == 2 ? PuzzleEvent.twoByTwo : .threeByThree) : restoredEvent
        if session.selectedEventRawValue != sessionEvent.rawValue {
            session.selectedEventRawValue = sessionEvent.rawValue
        }
        if modelContext.hasChanges {
            try? modelContext.save()
        }
        if selectedEvent != sessionEvent {
            selectedEvent = sessionEvent
        }
        if enteringTimesWith != configuration.timingMethod.rawValue {
            enteringTimesWith = configuration.timingMethod.rawValue
        }
        if refreshStatistics { refreshSolveSnapshots(for: sessionEvent, session: session) }
        return sessionEvent
    }

    private func synchronizeSmartCubeEvent() {
        if smartCube.isConnected {
            let event: PuzzleEvent = smartCube.puzzleSize == 2 ? .twoByTwo : .threeByThree
            if selectedEvent != event { selectedEvent = event }
        } else {
            smartCube.setTimerPuzzleSize(selectedEvent == .twoByTwo ? 2 : 3)
        }
    }

    private func persistSelectedEventToSession() {
        guard let selectedSession else { return }
        let rawValue = selectedEvent.rawValue
        guard selectedSession.selectedEventRawValue != rawValue else { return }
        selectedSession.persistTimerConfiguration(eventRawValue: rawValue)
        try? modelContext.save()
    }

    private func persistTimingMethodToSession(_ rawValue: String) {
        guard let selectedSession,
              SessionTimingMethod(rawValue: rawValue) != nil,
              selectedSession.selectedTimingMethodRawValue != rawValue else { return }
        selectedSession.persistTimerConfiguration(timingMethodRawValue: rawValue)
        try? modelContext.save()
    }

    private func refreshSolveSnapshots(
        for _: PuzzleEvent? = nil,
        session explicitSession: Session? = nil,
        requiredForCompletedSolve: Bool = false
    ) {
        guard isActive || requiredForCompletedSolve else {
            solveSnapshotsNeedRefresh = true
            return
        }
        solveSnapshotsNeedRefresh = false
        guard let resolvedSession = explicitSession ?? selectedSession else {
            manualReference = nil
            sessionStatisticsSnapshot = .empty
            timerPBState = .empty
            return
        }

        let sessionSolves = (try? modelContext.fetchSolves(forSessionID: resolvedSession.id))
            ?? solves.filter { $0.session?.id == resolvedSession.id }
        #if DEBUG
        performanceProbe?.timerStatisticsReads += 1
        #endif
        let samples = sessionSolves.map { solve in
            SessionSolveSample(
                id: solve.id,
                date: solve.date,
                time: solve.time,
                resultRaw: solve.resultRaw,
                scramble: solve.scramble,
                comment: solve.comment,
                eventRawValue: solve.event,
                inputSourceRaw: solve.inputSourceRaw
            )
        }
        manualReference = enteringTimesWith == "typing"
            ? ManualTimeParser.reference(current: samples, historical: [], event: selectedEvent.rawValue) : nil
        if manualReference == nil, enteringTimesWith == "typing" {
            let request = Solve.fetchRequest()
            request.predicate = NSPredicate(format: "event == %@ AND resultRaw != %@ AND time > 0", selectedEvent.rawValue, SolveResult.dnf.rawValue)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Solve.date, ascending: false)]
            request.fetchLimit = 20
            let history = ((try? modelContext.fetch(request)) ?? []).map {
                SessionSolveSample(id: $0.id, date: $0.date, time: $0.time, resultRaw: $0.resultRaw,
                    scramble: "", comment: "", eventRawValue: $0.event)
            }
            manualReference = ManualTimeParser.reference(current: [], historical: history, event: selectedEvent.rawValue)
        }
        sessionStatisticsSnapshot = DataTabComputation.buildSessionStatisticsSnapshot(from: samples)
        timerPBState = TimerPersonalBestState.current(from: samples)
        currentResultPB.reconcile(records: timerPBState)
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

    private var scrambleGenerationContext: TimerScrambleGenerationContext {
        TimerScrambleGenerationContext(
            sessionID: selectedSession?.id,
            event: effectiveTimerEvent,
            multiBlindCount: mblindScrambleCount,
            unavailableMessage: appLocalizedString(
                "timer.scramble_unavailable",
                languageCode: appLanguage
            ),
            deviceID: usesSmartCubeInput ? smartCube.activeDeviceID : nil,
            connectionAttemptID: usesSmartCubeInput ? smartCube.connectionAttemptID : nil
        )
    }

    private func generateNewScramble() {
        guard !isRunning, pendingSolveTime == nil else { return }
        #if DEBUG
        if advanceMarketingPreviewScramble() {
            return
        }
        #endif

        let context = scrambleGenerationContext
        let requestToken = UUID()
        let requestedAt = ProcessInfo.processInfo.systemUptime
        scrambleRequestToken = requestToken
        scrambleNeedsReplacement = true
        #if DEBUG
        AppExperienceTrace.mark("visible_scramble_requested")
        #endif
        if usesSmartCubeInput, let sessionID = context.sessionID {
            // The displayed Cards snapshot may stay visible while loading,
            // but a target explicitly advanced past is no longer restorable.
            SmartCubeTimerPresentationStore.shared.discardScramble(
                timerSessionID: sessionID, puzzleSize: context.event == .twoByTwo ? 2 : 3)
        }

        if !isMarketingPreviewTimer,
           let prefetched = scramblePrefetchSlot.consume(for: context) {
            activateGeneratedScramble(
                prefetched,
                requestToken: requestToken,
                requestedAt: requestedAt,
                source: "prefetch"
            )
            return
        }

        if !isMarketingPreviewTimer,
           scramblePrefetchSlot.hasPendingRequest(for: context) {
            presentScrambleLoading(for: context)
            scramblePrefetchConsumptionToken = requestToken
            scramblePrefetchConsumptionRequestedAt = requestedAt
            #if DEBUG
            print("[ScramblePerf] next waiting_for_prefetch event=\(context.event.rawValue)")
            #endif
            return
        }

        invalidateScramblePrefetch()
        presentScrambleLoading(for: context)
        requestScrambleGeneration(
            for: context,
            requestToken: requestToken,
            requestedAt: requestedAt,
            reason: "foreground"
        )
    }

    #if DEBUG
    private func advanceMarketingPreviewScramble() -> Bool {
        guard var configuration = marketingPreviewConfiguration?.wrappedValue,
              let scramble = configuration.advanceFixedScramble() else { return false }
        marketingPreviewConfiguration?.wrappedValue = configuration
        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
            currentScramble = scramble
        }
        return true
    }
    #endif

    private func presentScrambleLoading(for context: TimerScrambleGenerationContext) {
        // A pending Next is not a new presentation. Keep the complete Cards
        // snapshot until its replacement (including the diagram) is ready.
        if resolvedTimerArrangement == .cards, displayedScrambleContext == context,
           hasAssignedScramble { return }
        currentScramble = "…"
        if context.event == .threeByThreeMBLD {
            mblindScrambles = []
        }
    }

    private func requestScrambleGeneration(
        for context: TimerScrambleGenerationContext,
        requestToken: UUID,
        requestedAt: TimeInterval,
        reason: String
    ) {
        generateTimerScramble(for: context, reason: reason) { payload in
            guard scrambleRequestToken == requestToken,
                  scrambleGenerationContext == context else {
                #if DEBUG
                print("[ScramblePerf] discarded stale foreground event=\(context.event.rawValue)")
                #endif
                return
            }
            activateGeneratedScramble(
                payload,
                requestToken: requestToken,
                requestedAt: requestedAt,
                source: reason
            )
        }
    }

    private func activateGeneratedScramble(
        _ payload: TimerScrambleGenerationPayload,
        requestToken: UUID,
        requestedAt: TimeInterval,
        source: String,
        attemptedDiagramPreparation: Bool = false
    ) {
        guard scrambleRequestToken == requestToken,
              payload.context == scrambleGenerationContext,
              !isRunning, pendingSolveTime == nil else { return }

        if !preparedCardsDiagramIsCurrent(payload), !attemptedDiagramPreparation {
            // A slot filled in another arrangement may not have a diagram yet.
            prepareScramblePresentation(payload) { prepared in
                activateGeneratedScramble(prepared, requestToken: requestToken,
                    requestedAt: requestedAt, source: source, attemptedDiagramPreparation: true)
            }
            return
        }
        // A diagram failure must not destroy an already valid presentation.
        // Initial loading retains the original renderer's error/fallback path.
        if !preparedCardsDiagramIsCurrent(payload), hasAssignedScramble { return }

        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
            if payload.context.event == .threeByThreeMBLD {
                mblindScrambles = payload.scrambles
            }
            currentScramble = payload.primaryScramble
            displayedScrambleContext = payload.context
            currentCardsDiagram = payload.diagram
            scrambleNeedsReplacement = false
            // Commit the text and its original target in the same owner turn.
            // A BLE event can arrive before SwiftUI's later onChange callback.
            if usesSmartCubeInput { prepareSmartCubeScrambleTarget(scramble: payload.primaryScramble) }
        }

        #if DEBUG
        AppExperienceTrace.mark(hasAssignedScramble ? "visible_scramble_ready" : "scramble_unavailable")
        let elapsed = (ProcessInfo.processInfo.systemUptime - requestedAt) * 1_000
        print(
            String(
                format: "[ScramblePerf] activation source=%@ event=%@ wait_ms=%.1f",
                source,
                payload.context.event.rawValue,
                elapsed
            )
        )
        #endif

        scheduleScramblePrefetch(for: payload.context)
        if hasAssignedScramble { TimerScrambleGenerator.prepareSecondaryResources() }
    }

    private var hasAssignedScramble: Bool {
        !currentScramble.isEmpty && currentScramble != "…"
            && !currentScramble.hasPrefix(appLocalizedString("timer.scramble_unavailable", languageCode: appLanguage))
    }

    private var displayedScrambleMatchesSelection: Bool {
        guard let displayedScrambleContext else { return false }
        return displayedScrambleContext.event == effectiveTimerEvent
            && displayedScrambleContext.sessionID == selectedSession?.id
    }

    private var currentSolveAssignment: TimerSolveAssignment? {
        guard hasAssignedScramble, !scrambleNeedsReplacement, let selectedSession else { return nil }
        if usesSmartCubeInput {
            guard displayedScrambleMatchesSelection,
                  let progress = smartCubeScrambleProgress,
                  SmartCubeBluetoothManager.facelets(afterApplying: currentScramble, puzzleSize: progress.puzzleSize) == progress.targetFacelets else { return nil }
        }
        return .init(scramble: scrambleToSave, event: effectiveTimerEvent, sessionID: selectedSession.id,
                     requestID: scrambleRequestToken, inputSource: selectedTimingMethod.solveInputSource)
    }

    private func refreshScrambleGenerationDeviceOwner() {
        guard usesSmartCubeInput else { return }
        invalidateScramblePrefetch()
        scrambleRequestToken = UUID()
        let context = scrambleGenerationContext
        if hasAssignedScramble && !scrambleNeedsReplacement && displayedScrambleMatchesSelection {
            scheduleScramblePrefetch(for: context)
        }
        else { generateNewScramble() }
    }

    private func scheduleScramblePrefetch(for context: TimerScrambleGenerationContext) {
        guard !isMarketingPreviewTimer,
              scrambleGenerationContext == context,
              scramblePrefetchSlot.payload?.context != context,
              !scramblePrefetchSlot.hasPendingRequest(for: context) else { return }

        let request = scramblePrefetchSlot.begin(for: context)
        generateTimerScramble(for: context, reason: "prefetch") { payload in
            guard scramblePrefetchSlot.complete(payload, for: request) else {
                #if DEBUG
                print("[ScramblePerf] discarded stale prefetch event=\(context.event.rawValue)")
                #endif
                return
            }

            guard let waitingToken = scramblePrefetchConsumptionToken else { return }
            let waitingRequestedAt = scramblePrefetchConsumptionRequestedAt
                ?? ProcessInfo.processInfo.systemUptime
            scramblePrefetchConsumptionToken = nil
            scramblePrefetchConsumptionRequestedAt = nil
            guard scrambleRequestToken == waitingToken,
                  scrambleGenerationContext == context,
                  let consumed = scramblePrefetchSlot.consume(for: context) else {
                scramblePrefetchSlot.invalidate()
                return
            }
            activateGeneratedScramble(
                consumed,
                requestToken: waitingToken,
                requestedAt: waitingRequestedAt,
                source: "prefetch-wait"
            )
        }
    }

    private func invalidateScramblePrefetch() {
        scramblePrefetchSlot.invalidate()
        scramblePrefetchConsumptionToken = nil
        scramblePrefetchConsumptionRequestedAt = nil
    }

    private func generateTimerScramble(for context: TimerScrambleGenerationContext, reason: String,
                                      prepareDiagram: Bool = true,
                                      completion: @escaping @MainActor (TimerScrambleGenerationPayload) -> Void) {
        let deliver: @MainActor (TimerScrambleGenerationPayload) -> Void = { payload in
            if prepareDiagram { prepareScramblePresentation(payload, completion: completion) }
            else { completion(payload) }
        }
        #if DEBUG
        if let generate = guidanceProbe?.generate {
            generate(context, reason, deliver)
            return
        }
        #endif
        if reason == "foreground", TimerLaunchScrambleReservation.shared.consume(for: context, completion: deliver) { return }
        TimerScrambleGenerator.generate(for: context, reason: reason, completion: deliver)
    }

    private func prepareScramblePresentation(_ payload: TimerScrambleGenerationPayload,
        completion: @escaping @MainActor (TimerScrambleGenerationPayload) -> Void) {
        guard !preparedCardsDiagramIsCurrent(payload),
              let puzzleKey = payload.context.event.scrambleDiagramPuzzleKey else {
            completion(payload)
            return
        }
        let colors = ScrambleColorConfiguration.decode(
            from: UserDefaults.standard.data(forKey: "scrambleDiagramColorSchemeData")
        ).schemeString(for: puzzleKey)
        let stroke = (DiagramStrokeStyle(rawValue: UserDefaults.standard.string(
            forKey: "scrambleDiagramStrokeStyle") ?? "thin") ?? .thin).scale
        Task { @MainActor in
            var prepared = payload
            if let image = try? await ScrambleDiagramImageRenderer.render(
                puzzleKey: puzzleKey, scramble: payload.primaryScramble, colorScheme: colors,
                strokeScale: stroke
            ), let data = image.pngData() {
                prepared.diagram = .init(puzzleKey: puzzleKey, scramble: payload.primaryScramble,
                    pngData: data, colorScheme: colors, strokeScale: stroke)
            }
            completion(prepared)
        }
    }

    private func preparedCardsDiagramIsCurrent(_ payload: TimerScrambleGenerationPayload) -> Bool {
        guard resolvedTimerArrangement == .cards,
              let puzzleKey = payload.context.event.scrambleDiagramPuzzleKey,
              !payload.primaryScramble.isEmpty,
              !payload.primaryScramble.hasPrefix(payload.context.unavailableMessage) else { return true }
        let colors = ScrambleColorConfiguration.decode(
            from: UserDefaults.standard.data(forKey: "scrambleDiagramColorSchemeData")
        ).schemeString(for: puzzleKey)
        let stroke = (DiagramStrokeStyle(rawValue: UserDefaults.standard.string(
            forKey: "scrambleDiagramStrokeStyle") ?? "thin") ?? .thin).scale
        return payload.diagram?.puzzleKey == puzzleKey && payload.diagram?.scramble == payload.primaryScramble
            && payload.diagram?.colorScheme == colors && payload.diagram?.strokeScale == stroke
    }

    private var isMarketingPreviewTimer: Bool {
        #if DEBUG
        marketingPreviewConfiguration != nil
        #else
        false
        #endif
    }

    #if DEBUG
    private func marketingPreviewStatisticValue(for metric: TimerStatisticMetric) -> Double? {
        guard let configuration = marketingPreviewConfiguration?.wrappedValue else { return nil }
        switch metric {
        case .mean:
            return configuration.mean
        case .ao5:
            return configuration.ao5
        case .ao12:
            return configuration.ao12
        case .ao100:
            return configuration.ao100
        case .best, .mo3, .ao50, .solveCount:
            return nil
        }
    }
    #endif

    private func preferredScramble(for event: PuzzleEvent) -> String {
        TimerScrambleGenerator.preferredScramble(
            for: event,
            unavailableMessage: appLocalizedString(
                "timer.scramble_unavailable",
                languageCode: appLanguage
            )
        )
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
        TimerReadyFeedback.shared.impact()
        #endif
    }

    private var scrambleDiagramPuzzleKey: String? {
        effectiveTimerEvent.scrambleDiagramPuzzleKey
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
                    exportAppearance: timerScrambleExportAppearance,
                    preparedDiagram: resolvedTimerArrangement == .cards ? currentCardsDiagram : nil
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

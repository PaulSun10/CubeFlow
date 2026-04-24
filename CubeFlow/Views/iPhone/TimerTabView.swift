import SwiftUI
import CoreData
#if os(iOS)
import UIKit
#endif

#if os(iOS)
private let solvesDidChangeNotification = Notification.Name("CubeFlowSolvesDidChange")

struct TimerTabView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var ganTimer = GANTimerBluetoothManager.shared
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
    @AppStorage("timerAccuracy") private var timerAccuracy: String = "thousandths"
    @AppStorage("enteringTimesWith") private var enteringTimesWith: String = "timer"
    @AppStorage("hideElementsWhenSolving") private var hideElementsWhenSolving: Bool = false
    @AppStorage("timerBackgroundImageData") private var timerBackgroundImageData: Data?
    @AppStorage("drawScramblePlacement") private var drawScramblePlacement: String = DrawScramblePlacement.inline.rawValue
    @AppStorage("drawScrambleFloatingSize") private var drawScrambleFloatingSize: Double = 132

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
    @State private var filteredSolvesSnapshot: [Solve] = []
    @State private var sessionSolvesSnapshot: [Solve] = []
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

    private let hiddenTimerVerticalOffset: CGFloat = 18
    private let ganResultChoices: [SolveResult] = [.solved, .plusTwo, .dnf]
    private let ganResultAutoCommitDelay: TimeInterval = 1.5

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

    private var filteredSolves: [Solve] {
        filteredSolvesSnapshot
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
            .navigationTitle("timer.mblind.sheet_title")
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
            .navigationTitle("timer.mblind.count_title")
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
            size: scrambleTextFontSize,
            design: resolvedScrambleTextFontDesign,
            weight: resolvedScrambleTextFontWeight
        )
        .id(scrambleDisplayText)
        .foregroundStyle(scrambleTextStyle)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
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

    private var sessionSolves: [Solve] {
        sessionSolvesSnapshot
    }

    private var ao5: Double? {
        SolveMetrics.trimmedAverage(from: filteredSolves, count: 5)
    }

    private var ao12: Double? {
        SolveMetrics.trimmedAverage(from: filteredSolves, count: 12)
    }

    private var timerBackgroundAppearance: AppearanceConfiguration {
        AppearanceConfiguration.decode(from: timerBackgroundAppearanceData, fallback: .defaultBackground)
    }

    private var timerTextAppearance: AppearanceConfiguration {
        AppearanceConfiguration.decode(from: timerTextAppearanceData, fallback: .defaultTimerText)
    }

    private var scrambleTextAppearance: AppearanceConfiguration {
        AppearanceConfiguration.decode(from: scrambleTextAppearanceData, fallback: .defaultScrambleText)
    }

    private var averageTextAppearance: AppearanceConfiguration {
        AppearanceConfiguration.decode(from: averageTextAppearanceData, fallback: .defaultAverageText)
    }

    private var timerTextStyle: AnyShapeStyle {
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
        timerAccuracy == "hundredths" ? 2 : 3
    }

    private var resolvedTimerTextFontDesign: TimerFontDesignOption {
        TimerFontDesignOption(rawValue: timerTextFontDesign) ?? .default
    }

    private var resolvedScrambleTextFontDesign: TimerFontDesignOption {
        TimerFontDesignOption(rawValue: scrambleTextFontDesign) ?? .default
    }

    private var resolvedAverageTextFontDesign: TimerFontDesignOption {
        TimerFontDesignOption(rawValue: averageTextFontDesign) ?? .default
    }

    private var resolvedTimerTextFontWeight: TimerFontWeightOption {
        TimerFontWeightOption(rawValue: timerTextFontWeight) ?? .semibold
    }

    private var resolvedScrambleTextFontWeight: TimerFontWeightOption {
        TimerFontWeightOption(rawValue: scrambleTextFontWeight) ?? .medium
    }

    private var resolvedAverageTextFontWeight: TimerFontWeightOption {
        TimerFontWeightOption(rawValue: averageTextFontWeight) ?? .medium
    }

    private func configuredFont(
        size: Double,
        design: TimerFontDesignOption,
        weight: TimerFontWeightOption
    ) -> Font {
        .system(size: size, weight: weight.fontWeight, design: design.fontDesign)
    }

    @ViewBuilder
    private func configuredText(
        _ text: Text,
        size: Double,
        design: TimerFontDesignOption,
        weight: TimerFontWeightOption
    ) -> some View {
        text
            .font(configuredFont(size: size, design: design, weight: weight))
            .compatibleFontWidth(design)
    }

    private var timerTickInterval: TimeInterval {
        timerAccuracy == "hundredths" ? 0.01 : 0.001
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
            return String(Int(elapsedSeconds.rounded(.down)))
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
            return String(Int(ceil(remaining)))
        }
    }

    private var soloTimerContent: some View {
        VStack(spacing: 0) {
            if !shouldHideNonTimerContent {
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
                .padding(.top, 8)

                HStack(alignment: .top, spacing: 10) {
                    ZStack {
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
                    .animation(.snappy(duration: 0.22, extraBounce: 0), value: scrambleDisplayText)

                    VStack(spacing: 6) {
                        if canShowScrambleDiagram && resolvedDrawScramblePlacement == .inline {
                            circularGlassIconButton(systemName: "eye") {
                                showingScrambleDiagram = true
                            }
                        }

                        circularGlassIconButton(systemName: "arrow.clockwise") {
                            generateNewScramble()
                        }

                        if selectedEvent == .threeByThreeMBLD {
                            circularGlassIconButton(systemName: "gearshape") {
                                mblindCountSelection = mblindScrambleCount
                                showingMblindCountPicker = true
                            }
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 6)
            }

            Spacer()

            if showsOverlayTimer {
                Color.clear
                    .frame(height: max(timerTextFontSize * 1.25, 96))
            } else {
                timerDisplayView
            }

            averageDisplayView
                .opacity(shouldHideNonTimerContent ? 0 : 1)

            Spacer()
        }
        .padding(.horizontal, 24)
        .simultaneousGesture(dismissTypingKeyboardGesture)
    }

    private var dismissTypingKeyboardGesture: some Gesture {
        TapGesture().onEnded {
            guard enteringTimesWith == "typing", isTypingFieldFocused else { return }
            isTypingFieldFocused = false
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
                timerBackgroundView.ignoresSafeArea()

                if localBattleMode == .solo {
                    soloTimerContent
                } else {
                    localBattleContent
                }

                if localBattleMode == .solo && showsOverlayTimer {
                    GeometryReader { proxy in
                        timerDisplayView
                            .position(
                                x: proxy.size.width / 2,
                                y: proxy.frame(in: .global).midY + hiddenTimerVerticalOffset
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                }

                if let floatingPlacement = floatingDrawScramblePlacement,
                   canShowScrambleDiagram,
                   localBattleMode == .solo,
                   !shouldHideNonTimerContent {
                    VStack {
                        Spacer()
                        HStack {
                            if floatingPlacement == .bottomLeft {
                                floatingScrambleDiagram
                                Spacer()
                            } else if floatingPlacement == .bottomCenter {
                                Spacer(minLength: 0)
                                floatingScrambleDiagram
                                Spacer(minLength: 0)
                            } else {
                                Spacer()
                                floatingScrambleDiagram
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
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
            .animation(.easeInOut(duration: 0.18), value: showsGANResultPopup)
            .overlay {
                if localBattleMode == .solo && enteringTimesWith == "timer" {
                    GeometryReader { _ in
                        VStack(spacing: 0) {
                            // Reserve top area for event menu so menu taps don't start/stop timer.
                            Color.clear
                                .frame(height: 146)
                                .allowsHitTesting(false)

                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                                .gesture(startTimerGesture)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
            }
            .compatibleNavigationBarHidden()
        }
        .compatibleTabBarVisibility(hidden: shouldHideTabBar)
    .task {
        ensureSessionExists()
        restoreSelectedEventFromSession()
        refreshSolveSnapshots()
        refreshStreakSnapshots()
        generateNewScramble()
        if enteringTimesWith == "gan" {
            ganTimer.prepareIfNeeded()
        }
    }
        .onDisappear {
            invalidateTimer()
            invalidateLocalBattleTimer()
            nearbyBattleManager.stop()
        }
        .onChange(of: enteringTimesWith) { newValue in
            if newValue == "gan" {
                ganTimer.prepareIfNeeded()
            }
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
        .onChange(of: selectedEvent) { _ in
            persistSelectedEventToSession()
            refreshSolveSnapshots()
            generateNewScramble()
            resetLocalBattleScrambles()
        }
        .onChange(of: selectedSessionID) { _ in
            restoreSelectedEventFromSession()
            refreshSolveSnapshots()
        }
        .onChange(of: solves.count) { _ in
            refreshSolveSnapshots()
            refreshStreakSnapshots()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CubeFlowSessionsWillDelete"))) { _ in
            filteredSolvesSnapshot = []
            sessionSolvesSnapshot = []
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
            Text(SolveMetrics.formatTime(pendingSolveTime ?? 0, decimals: 3))
        }
        .sheet(isPresented: $showingMblindSheet) {
            mblindScrambleSheet
        }
        .sheet(isPresented: $showingMblindCountPicker) {
            mblindCountPickerSheet
        }
        .sheet(isPresented: $showingScrambleDiagram) {
            if let scrambleDiagramPuzzleKey {
                ScrambleDiagramSheet(
                    title: "timer.scramble_diagram",
                    puzzleKey: scrambleDiagramPuzzleKey,
                    scramble: currentScramble
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
// Event selection
    private var eventMenu: some View {
        Menu {
            ForEach(PuzzleEvent.regularCases, id: \.self) { event in
                Button(LocalizedStringKey(event.localizationKey)) {
                    selectedEvent = event
                }
            }

            Menu("timer.menu.bld") {
                ForEach(PuzzleEvent.blindfoldedCases, id: \.self) { event in
                    Button(LocalizedStringKey(event.localizationKey)) {
                        selectedEvent = event
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(selectedEvent.localizationKey))
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

    private var averageDisplayView: some View {
        VStack(spacing: 6) {
            switch resolvedAverageDisplayOption {
            case .none:
                EmptyView()
            case .ao5:
                averageMetricRow(titleKey: "data.ao5", value: ao5)
            case .ao12:
                averageMetricRow(titleKey: "data.ao12", value: ao12)
            case .ao5AndAo12:
                averageMetricRow(titleKey: "data.ao5", value: ao5)
                averageMetricRow(titleKey: "data.ao12", value: ao12)
            }
        }
        .foregroundStyle(averageTextStyle)
    }

    private func averageMetricRow(titleKey: LocalizedStringKey, value: Double?) -> some View {
        let averageString = SolveMetrics.formatAverage(value)
        return configuredText(
            Text("\(Text(titleKey)): \(averageString)"),
            size: averageTextFontSize,
            design: resolvedAverageTextFontDesign,
            weight: resolvedAverageTextFontWeight
        )
    }

    private func formatDisplayedTime(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let hours = Int(clamped) / 3600
        let minutes = (Int(clamped) % 3600) / 60
        let remainingSeconds = clamped - Double(hours * 3600 + minutes * 60)
        if hours > 0 {
            return String(format: "%d:%02d:%0*.*f", hours, minutes, timerDecimals + 3, timerDecimals, remainingSeconds)
        }
        if minutes > 0 {
            return String(format: "%d:%0*.*f", minutes, timerDecimals + 3, timerDecimals, remainingSeconds)
        }
        return String(format: "%.\(timerDecimals)f", remainingSeconds)
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
            VStack(spacing: 12) {
                TextField(LocalizedStringKey("timer.typing_placeholder"), text: $typedTimeInput)
                    .font(.system(size: 40, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .focused($isTypingFieldFocused)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Button("timer.typing_save") {
                    saveTypedTime()
                }
                .compatibleProminentButtonFromIOS16(tint: .blue)
                .disabled(parseTypedTime(typedTimeInput) == nil)
            }
        } else {
            configuredText(
                Text(timerText),
                size: timerTextFontSize,
                design: resolvedTimerTextFontDesign,
                weight: resolvedTimerTextFontWeight
            )
                .monospacedDigit()
                .foregroundStyle(timerTextStyle)
                .contentShape(Rectangle())
        }
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

    private func restoreSelectedEventFromSession() {
        let restoredEvent = selectedSessionEvent
        guard selectedEvent != restoredEvent else { return }
        selectedEvent = restoredEvent
    }

    private func persistSelectedEventToSession() {
        guard let selectedSession else { return }
        let rawValue = selectedEvent.rawValue
        guard selectedSession.selectedEventRawValue != rawValue else { return }
        selectedSession.selectedEventRawValue = rawValue
        try? modelContext.save()
    }

    private func refreshSolveSnapshots() {
        guard let selectedSession else {
            filteredSolvesSnapshot = []
            sessionSolvesSnapshot = []
            return
        }

        let sessionSolves = solves.filter { $0.session?.id == selectedSession.id }
        sessionSolvesSnapshot = sessionSolves
        filteredSolvesSnapshot = sessionSolves.filter { $0.event == selectedEvent.rawValue }
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
        } else if selectedEvent == .fourByFour || selectedEvent == .fourByFourBLD {
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

    private func preferredScramble(for event: PuzzleEvent) -> String {
        let registry = tnoodleRegistry(for: event)
        if let scramble = TNoodleScrambler.scramble(for: registry),
           !scramble.isEmpty {
            return scramble
        }

        if let fallback = fallbackScramble(for: event) {
            return fallback
        }

        if event == .square1, let diagnostic = TNoodleScrambler.diagnostic(for: registry) {
            return "\(appLocalizedString("timer.scramble_unavailable", languageCode: appLanguage))\n\(diagnostic)"
        }

        return appLocalizedString("timer.scramble_unavailable", languageCode: appLanguage)
    }

    private func fallbackScramble(for event: PuzzleEvent) -> String? {
        switch event {
        case .twoByTwo:
            return randomFaceTurnScramble(moves: ["R", "L", "U", "F", "B"], length: 9)
        case .threeByThree, .threeByThreeOH, .threeByThreeBLD, .threeByThreeMBLD:
            return randomFaceTurnScramble(moves: ["R", "L", "U", "D", "F", "B"], length: 20)
        case .threeByThreeFM:
            return randomFaceTurnScramble(moves: ["R", "L", "U", "D", "F", "B"], length: 25)
        case .fourByFour, .fourByFourBLD:
            return randomFaceTurnScramble(
                moves: ["R", "L", "U", "D", "F", "B", "Rw", "Lw", "Uw", "Dw", "Fw", "Bw"],
                length: 40
            )
        case .fiveByFive, .fiveByFiveBLD:
            return randomFaceTurnScramble(
                moves: ["R", "L", "U", "D", "F", "B", "Rw", "Lw", "Uw", "Dw", "Fw", "Bw"],
                length: 60
            )
        case .sixBySix:
            return randomFaceTurnScramble(
                moves: ["R", "L", "U", "D", "F", "B", "3Rw", "3Lw", "3Uw", "3Dw", "3Fw", "3Bw"],
                length: 80
            )
        case .sevenBySeven:
            return randomFaceTurnScramble(
                moves: ["R", "L", "U", "D", "F", "B", "3Rw", "3Lw", "3Uw", "3Dw", "3Fw", "3Bw"],
                length: 100
            )
        case .megaminx:
            return randomMegaminxScramble(lines: 7)
        case .pyraminx:
            return randomPyraminxScramble()
        case .square1:
            return nil
        case .clock:
            return randomClockScramble()
        case .skewb:
            return randomFaceTurnScramble(moves: ["R", "L", "U", "B"], length: 10, includeDoubleTurns: false)
        }
    }

    private func randomFaceTurnScramble(
        moves: [String],
        length: Int,
        includeDoubleTurns: Bool = true
    ) -> String {
        let suffixes = includeDoubleTurns ? ["", "'", "2"] : ["", "'"]
        var result: [String] = []
        var lastAxis: String?

        while result.count < length {
            guard let move = moves.randomElement() else { break }
            let axis = faceTurnAxis(for: move)
            if axis == lastAxis { continue }
            guard let suffix = suffixes.randomElement() else { continue }
            result.append(move + suffix)
            lastAxis = axis
        }

        return result.joined(separator: " ")
    }

    private func faceTurnAxis(for move: String) -> String {
        if move.contains("R") || move.contains("L") { return "RL" }
        if move.contains("U") || move.contains("D") { return "UD" }
        return "FB"
    }

    private func randomMegaminxScramble(lines: Int) -> String {
        let pairMoves = ["R++", "R--", "D++", "D--"]
        return (0..<lines).map { _ in
            let segment = (0..<10).compactMap { _ in pairMoves.randomElement() }.joined(separator: " ")
            let tail = Bool.random() ? "U" : "U'"
            return "\(segment) \(tail)"
        }
        .joined(separator: "\n")
    }

    private func randomPyraminxScramble() -> String {
        let body = randomFaceTurnScramble(moves: ["R", "L", "U", "B"], length: 11, includeDoubleTurns: false)
        let tips = ["r", "l", "u", "b"]
            .compactMap { tip -> String? in
                Bool.random() ? "\(tip)\(Bool.random() ? "'" : "")" : nil
            }
        return ([body] + tips).joined(separator: " ")
    }

    private func randomClockScramble() -> String {
        let moves = [
            "UR", "DR", "DL", "UL", "U", "R", "D", "L", "ALL"
        ].map { face in
            "\(face)\(Int.random(in: 0...6))\(Bool.random() ? "+" : "-")"
        }
        let pins = ["UR", "DR", "DL", "UL"].map { "\(Bool.random() ? "pin" : "unpin") \($0)" }
        return (moves + pins).joined(separator: " / ")
    }


    private func tnoodleRegistry(for event: PuzzleEvent) -> TNoodlePuzzleRegistry {
        switch event {
        case .twoByTwo:
            return .two
        case .threeByThree, .threeByThreeOH, .threeByThreeMBLD:
            return .three
        case .fourByFour:
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
            if let data = timerBackgroundImageData,
               let image = UIImage(data: data) {
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

    private var floatingDrawScramblePlacement: DrawScramblePlacement? {
        if resolvedDrawScramblePlacement.isFloating {
            return resolvedDrawScramblePlacement
        }
        return nil
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

    private var floatingScrambleDiagram: some View {
        Group {
            if let scrambleDiagramPuzzleKey {
                ScrambleDiagramView(puzzleKey: scrambleDiagramPuzzleKey, scramble: currentScramble)
                    .frame(width: drawScrambleFloatingSize, height: drawScrambleFloatingSize)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .onTapGesture {
                        showingScrambleDiagram = true
                    }
            }
        }
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

import SwiftUI
import CoreData
import Charts
import UIKit

#if os(iOS)
private let sessionsWillDeleteNotification = Notification.Name("CubeFlowSessionsWillDelete")
private let solvesDidChangeNotification = Notification.Name("CubeFlowSolvesDidChange")
private let dataSelectionActionDuration: TimeInterval = 0.32

nonisolated enum DataSearchIsolation {
    static let isDisabled: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["CUBEFLOW_DATA_DISABLE_SEARCH"] == "1"
        #else
        false
        #endif
    }()
}

@MainActor
struct DataTabView: View {
    #if DEBUG
    @Environment(\.appPerformanceProbe) private var performanceProbe
    #endif
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.solveTimeAccuracy) private var solveTimeAccuracy

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Session.createdAt, ascending: true)],
        animation: .default
    )
    private var sessions: FetchedResults<Session>

    @AppStorage("selectedSessionID") private var selectedSessionID: String = ""
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("dataSolveSortOption") private var solveSortOptionRawValue = DataSolveSortOption.newest.rawValue
    @AppStorage("dataSolveResultFilter") private var solveResultFilterRawValue = DataSolveResultFilter.all.rawValue
    @AppStorage("dataAverageSortOption") private var averageSortOptionRawValue = DataAverageSortOption.newest.rawValue
    @AppStorage("dataRecordFilterOption") private var recordFilterOptionRawValue = DataRecordFilterOption.all.rawValue
    @AppStorage("appNumeralSystem") private var appNumeralSystem = NumeralSystem.systemDefault.rawValue
    @AppStorage("appNumeralChineseFinancial") private var appNumeralChineseFinancial = false
    @AppStorage("appNumeralChineseNumberFormat") private var appNumeralChineseNumberFormat = ChineseNumeralNumberFormat.digits.rawValue
    @AppStorage("appNumeralChineseDecimalStyle") private var appNumeralChineseDecimalStyle = ChineseNumeralDecimalStyle.period.rawValue

    @State private var selectedSegment: DataSegment = .time
    @State private var segmentTransitionDirection: Edge = .trailing
    private let usesSystemBottomAccessory: Bool
    @Binding private var isSearchAccessoryVisible: Bool
    private let searchRequestID: Int
    @Binding private var isSelectingSolves: Bool
    @State private var isSelecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceSelectionMotion
    @State private var selectedSolveIDs: Set<UUID> = []
    @State private var selectionAnchorID: UUID?
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var listViewport = CGRect.zero
    @State private var rangeControlFrame = CGRect.zero
    @ScaledMetric(relativeTo: .title) private var solveTimeFontSize = 28
    @State private var moveRequest: SolveMoveRequest?
    @State private var showingSessionSheet = false
    @State private var sessionSnapshotDeferred = false
    @State private var solveDetailSample: SessionSolveSample?
    @State private var averageDetailEntry: AverageListEntry?
    @State private var showingTrendSheet = false
    @State private var showingRecordHistory = false
    @State private var recordAverageDetail: RecordAverageDetailSelection?
    @State private var rangeFilterEditor: DataSolveRangeFilterEditor?
    @State private var isShowingSearch = false
    @State private var isTimeRangeFilterEnabled = false
    @State private var minimumTimeFilter = 0.0
    @State private var maximumTimeFilter = 0.0
    @State private var isDateRangeFilterEnabled = false
    @State private var startDateFilter = Date()
    @State private var endDateFilter = Date()
    @State private var selectedAverageType: AverageListType = .mo3
    @State private var recordSnapshot = RecordSnapshot.empty
    @State private var filteredSessionSolves: [SessionSolveSample] = []
    @State private var visibleSessionSolves: [SessionSolveSample] = []
    @State private var solvePositionByID: [UUID: Int] = [:]
    @State private var averageEntriesSnapshot: [AverageListEntry] = []
    @State private var averageEntriesKey: AverageEntriesSnapshotKey?
    @State private var recordSnapshotKey: SessionSnapshotKey?
    @State private var isLoadingSessionSnapshot = false
    @State private var isComputingRecordSnapshot = false
    @State private var isComputingAverageEntries = false
    @State private var sessionSnapshotGeneration = 0
    @State private var snapshotReader: SessionSolveSnapshotReader?
    @State private var sessionSnapshotTask: Task<Void, Never>?
    @State private var recordComputationGeneration = 0
    @State private var recordComputation: (key: SessionSnapshotKey, task: Task<Void, Never>)?
    @State private var averageComputationGeneration = 0
    @State private var isShowingDeleteSelectedSolvesAlert = false

    init(usesSystemBottomAccessory: Bool = false, isSearchAccessoryVisible: Binding<Bool> = .constant(false), searchRequestID: Int = 0,
         isSelectingSolves: Binding<Bool>) {
        self.usesSystemBottomAccessory = usesSystemBottomAccessory
        _isSearchAccessoryVisible = isSearchAccessoryVisible
        self.searchRequestID = searchRequestID
        _isSelectingSolves = isSelectingSolves
    }

    private var selectedSession: Session? {
        sessions.first(where: { $0.id.uuidString == selectedSessionID }) ?? sessions.first
    }

    private var sessionSolves: [SessionSolveSample] {
        filteredSessionSolves
    }

    private var selectedSessionSolveCount: Int {
        filteredSessionSolves.count
    }

    @State private var personalBestSingleSolveIDs = Set<UUID>()

    private var selectedSessionPuzzleKey: String? {
        guard let rawValue = selectedSession?.selectedEventRawValue,
              let event = PuzzleEvent(rawValue: rawValue) else { return nil }
        return event.scrambleDiagramPuzzleKey
    }

    private var availableAverageTypes: [AverageListType] {
        AverageListType.allCases.filter { sessionSolves.count >= $0.solveCount }
    }

    private var currentSessionSnapshotKey: SessionSnapshotKey? {
        guard let selectedSession else { return nil }
        return SessionSnapshotKey(
            sessionID: selectedSession.id,
            solveCount: sessionSolves.count,
            languageCode: appLanguage,
            timeDecimals: solveTimeAccuracy.decimals
        )
    }

    var body: some View {
        let _ = (
            appNumeralSystem,
            appNumeralChineseFinancial,
            appNumeralChineseNumberFormat,
            appNumeralChineseDecimalStyle
        )
        CompatibleNavigationContainer {
            dataContent
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: DataSelectionToolbarWidth.self, value: geometry.size.width)
                }
            }
            .onPreferenceChange(DataSelectionToolbarWidth.self) { selectionToolbarWidth = $0 }
            .modifier(DataLegacySearchInset(enabled: !usesSystemBottomAccessory, visible: canSearch && !isSelecting,
                languageCode: appLanguage, openSearch: { isShowingSearch = true }))
            .modifier(DataSelectionToolbar(actions: isSelecting && selectedSegment == .time
                ? selectionActions(count: selectedSolveIDs.count) : nil))
            .navigationTitle(Text("tab.data"))
            .navigationBarTitleDisplayMode(.inline)
            .modifier(
                DataTabLeadingToolbarModifier {
                    showingSessionSheet = true
                }
            )
            .modifier(
                DataTabTrailingToolbarModifier(
                    segment: selectedSegment,
                    showsListControls: selectedSegment == .time && !filteredSessionSolves.isEmpty,
                    isSelecting: isSelecting,
                    isFilterActive: hasActiveSolveFilters,
                    isAverageFilterActive: averageSortOptionRawValue != DataAverageSortOption.newest.rawValue,
                    isRecordFilterActive: recordFilterOptionRawValue != DataRecordFilterOption.all.rawValue,
                    sortOption: solveSortOptionBinding,
                    resultFilter: solveResultFilterBinding,
                    averageType: $selectedAverageType,
                    averageTypes: availableAverageTypes,
                    averageSortOption: averageSortOptionBinding,
                    recordFilterOption: recordFilterOptionBinding,
                    languageCode: appLanguage,
                    isTimeRangeEnabled: isTimeRangeFilterEnabled,
                    isDateRangeEnabled: isDateRangeFilterEnabled,
                    onSelect: beginSelecting,
                    onCloseSelection: endSelecting,
                    onShowGraph: { showingTrendSheet = true },
                    onShowTimeRange: { rangeFilterEditor = .time },
                    onShowDateRange: { rangeFilterEditor = .date },
                    onResetFilters: resetAllFilters,
                    onResetAverageFilters: resetAverageFilters,
                    onResetRecordFilters: resetRecordFilters
                )
            )
            .compatibleNavigationDestination(isPresented: $isShowingSearch) {
                if let selectedSession {
                    DataSolveSearchView(
                        sessionID: selectedSession.id,
                        fallbackPuzzleKey: selectedSessionPuzzleKey
                    )
                }
            }
            .onAppear { updateSearchAccessoryVisibility(showsSearchAccessory) }
            .onDisappear { isSearchAccessoryVisible = false }
            .onChange(of: showsSearchAccessory) { updateSearchAccessoryVisibility($0) }
            .onChange(of: searchRequestID) { _ in
                guard usesSystemBottomAccessory, canSearch, !isSelecting else { return }
                isShowingSearch = true
            }
        }
        #if DEBUG
        .background {
            if DataSelectionTransitionTrace.isEnabled {
                DataSelectionTransitionTrace(selecting: isSelecting)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        #endif
        .sheet(isPresented: $showingSessionSheet, onDismiss: resumeSessionSnapshotAfterSheet) {
            SessionManagementSheet(selectedSessionID: $selectedSessionID)
                .compatibleLargeSheet()
        }
        .sheet(item: $solveDetailSample) { sample in
            SolveDetailSheet(
                sample: sample,
                position: solvePositionByID[sample.id],
                fallbackPuzzleKey: selectedSessionPuzzleKey
            )
                .compatibleLargeSheet()
        }
        .sheet(item: $averageDetailEntry) { entry in
            AverageDetailSheet(
                entry: entry,
                metric: AverageDetailMetric(selectedAverageType),
                personalBestSingleSolveIDs: personalBestSingleSolveIDs
            )
                .compatibleLargeSheet()
        }
        .sheet(item: $moveRequest) { request in
            SolveMoveDestinationView(sessions: Array(sessions), request: request, languageCode: appLanguage) { destination in
                try SolveSessionMembership.move(ids: request.solveIDs, from: request.sourceID, to: destination, context: modelContext)
                filteredSessionSolves.removeAll { request.solveIDs.contains($0.id) }
                updateVisibleSessionSolves()
                endSelecting()
                NotificationCenter.default.post(name: solvesDidChangeNotification, object: nil)
            }
            .compatibleMediumLargeSheet()
        }
        .sheet(item: $recordAverageDetail) { selection in
            AverageDetailSheet(
                entry: selection.entry,
                metric: selection.metric,
                personalBestSingleSolveIDs: personalBestSingleSolveIDs
            )
            .compatibleLargeSheet()
        }
        .alert("delete.solves.title", isPresented: $isShowingDeleteSelectedSolvesAlert) {
            Button("common.delete", role: .destructive) {
                deleteSelectedSolves()
            }
            Button("common.cancel", role: .cancel) { }
        } message: {
            Text("delete.solves.message")
        }
        .sheet(isPresented: $showingTrendSheet) {
            TimeTrendSheet(solves: sessionSolves, appLanguage: appLanguage)
                .compatibleLargeSheet()
        }
        .sheet(isPresented: $showingRecordHistory) {
            RecordHistorySheet(
                solves: sessionSolves,
                solvePositionByID: solvePositionByID,
                personalBestSingleSolveIDs: personalBestSingleSolveIDs,
                fallbackPuzzleKey: selectedSessionPuzzleKey
            )
            .compatibleMediumLargeSheet()
        }
        .sheet(item: $rangeFilterEditor) { editor in
            DataSolveRangeFilterSheet(
                editor: editor,
                isTimeRangeEnabled: $isTimeRangeFilterEnabled,
                minimumTime: $minimumTimeFilter,
                maximumTime: $maximumTimeFilter,
                isDateRangeEnabled: $isDateRangeFilterEnabled,
                startDate: $startDateFilter,
                endDate: $endDateFilter,
                solves: filteredSessionSolves
            )
            .compatibleMediumLargeSheet()
        }
        .safeAreaInset(edge: .bottom) {
            if selectedSegment == .average && !availableAverageTypes.isEmpty {
                averageTypeBar
            }
        }
        .task {
            ensureSessionExists()
            refreshFilteredSessionSolves()
        }
        .onChange(of: selectedSegment) { newValue in
            if newValue != .time {
                setSelectionMode(false)
                selectedSolveIDs.removeAll()
            }
            if newValue == .average {
                syncSelectedAverageType()
                ensureAverageEntriesSnapshot()
            }
            if newValue == .record {
                refreshRecordSnapshot()
            }
        }
        .modifier(DataTabBarVisibility(hidden: isSelecting))
        .onChange(of: isSelecting) { isSelectingSolves = $0 }
        .onChange(of: selectedSessionID) { _ in
            setSelectionMode(false)
            selectedSolveIDs.removeAll()
            refreshFilteredSessionSolves()
            resetRangeFilters()
        }
        .onChange(of: solveSortOptionRawValue) { _ in
            updateVisibleSessionSolves()
        }
        .onChange(of: solveResultFilterRawValue) { _ in
            updateVisibleSessionSolves()
        }
        .onChange(of: isTimeRangeFilterEnabled) { _ in updateVisibleSessionSolves() }
        .onChange(of: minimumTimeFilter) { _ in if isTimeRangeFilterEnabled { updateVisibleSessionSolves() } }
        .onChange(of: maximumTimeFilter) { _ in if isTimeRangeFilterEnabled { updateVisibleSessionSolves() } }
        .onChange(of: isDateRangeFilterEnabled) { _ in updateVisibleSessionSolves() }
        .onChange(of: startDateFilter) { _ in if isDateRangeFilterEnabled { updateVisibleSessionSolves() } }
        .onChange(of: endDateFilter) { _ in if isDateRangeFilterEnabled { updateVisibleSessionSolves() } }
        .onReceive(NotificationCenter.default.publisher(for: solvesDidChangeNotification)) { _ in
            refreshFilteredSessionSolves()
        }
        .onChange(of: selectedAverageType) { _ in
            if !isLoadingSessionSnapshot {
                ensureAverageEntriesSnapshot()
            }
        }
        .onChange(of: appLanguage) { _ in
            cancelRecordComputation()
            recordSnapshotKey = nil
            if selectedSegment == .record {
                refreshRecordSnapshot()
            }
        }
        .onChange(of: solveTimeAccuracy) { _ in
            cancelRecordComputation()
            recordSnapshotKey = nil
            if selectedSegment == .record {
                refreshRecordSnapshot()
            }
        }
        #if DEBUG
        .onAppear {
            performanceProbe?.dataSelect = { if $0 { beginSelecting() } else { endSelecting() } }
            performanceProbe?.dataToggleAll = toggleAllVisibleSolves
            performanceProbe?.dataToggleOne = { id in
                if let solve = visibleSessionSolves.first(where: { $0.id == id }) { toggleSelection(for: solve) }
            }
            performanceProbe?.dataSelection = { (selectedSolveIDs, Set(visibleSessionSolves.map(\.id))) }
            performanceProbe?.dataOpenSessionSheet = { showingSessionSheet = true }
        }
        #endif
        .onDisappear {
            sessionSnapshotGeneration += 1
            sessionSnapshotTask?.cancel()
            cancelRecordComputation()
        }
    }

    @ViewBuilder
    private var dataContent: some View {
        if #available(iOS 26.0, *) {
            segmentContent
                .safeAreaBar(edge: .top, spacing: 0) {
                    glassSegmentedControl
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            VStack(spacing: 0) {
                glassSegmentedControl
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                Divider()
                segmentContent
            }
        }
    }

    private var segmentContent: some View {
        ZStack {
            switch selectedSegment {
            case .time:
                timeContent
                    .transition(segmentTransition)
            case .average:
                averageContent
                    .transition(segmentTransition)
            case .record:
                recordContent
                    .transition(segmentTransition)
            }
        }
        .animation(.snappy(duration: 0.24, extraBounce: 0), value: selectedSegment)
    }


    private var segmentedControl: some View {
        Picker("Data Segment", selection: segmentSelection) {
            Text("data.segment.time").tag(DataSegment.time)
            Text("data.segment.average").tag(DataSegment.average)
            Text("data.segment.record").tag(DataSegment.record)
        }
        .pickerStyle(.segmented)
    }

    private var glassSegmentedControl: some View {
        HStack {
            segmentedControl
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .compatibleGlass(in: Capsule())
    }

    private var solveSortOptionBinding: Binding<DataSolveSortOption> {
        Binding(
            get: { DataSolveSortOption(rawValue: solveSortOptionRawValue) ?? .newest },
            set: { solveSortOptionRawValue = $0.rawValue }
        )
    }

    private var solveResultFilterBinding: Binding<DataSolveResultFilter> {
        Binding(
            get: { DataSolveResultFilter(rawValue: solveResultFilterRawValue) ?? .all },
            set: { solveResultFilterRawValue = $0.rawValue }
        )
    }

    private var averageSortOptionBinding: Binding<DataAverageSortOption> {
        Binding(
            get: { DataAverageSortOption(rawValue: averageSortOptionRawValue) ?? .newest },
            set: { averageSortOptionRawValue = $0.rawValue }
        )
    }

    private var recordFilterOptionBinding: Binding<DataRecordFilterOption> {
        Binding(
            get: { DataRecordFilterOption(rawValue: recordFilterOptionRawValue) ?? .all },
            set: { recordFilterOptionRawValue = $0.rawValue }
        )
    }

    private var recordFilterOption: DataRecordFilterOption {
        DataRecordFilterOption(rawValue: recordFilterOptionRawValue) ?? .all
    }

    private var visibleAverageEntries: [AverageListEntry] {
        let sortOption = DataAverageSortOption(rawValue: averageSortOptionRawValue) ?? .newest
        return averageEntriesSnapshot.sorted(by: sortOption.areInIncreasingOrder)
    }

    private var hasActiveSolveFilters: Bool {
        solveSortOptionRawValue != DataSolveSortOption.newest.rawValue ||
        solveResultFilterRawValue != DataSolveResultFilter.all.rawValue ||
        isTimeRangeFilterEnabled ||
        isDateRangeFilterEnabled
    }

    private func setSelectionMode(_ selecting: Bool) {
        isSelecting = selecting
        if !selecting { selectionAnchorID = nil }
    }

    private func beginSelecting() {
        withAnimation(selectionTransition) { setSelectionMode(true) }
    }

    private func endSelecting() {
        withAnimation(selectionTransition) {
            setSelectionMode(false)
            selectedSolveIDs.removeAll()
        }
    }

    private var selectionTransition: Animation? {
        guard !reduceSelectionMotion else { return nil }
        if #available(iOS 17.0, *) { return .snappy(duration: 0.2, extraBounce: 0) }
        return .easeInOut(duration: 0.2)
    }

    private var selectionActionTransition: Animation? {
        reduceSelectionMotion ? nil : .spring(response: dataSelectionActionDuration, dampingFraction: 0.9)
    }

    private var canSearch: Bool {
        selectedSegment == .time && !filteredSessionSolves.isEmpty && !isShowingSearch && !DataSearchIsolation.isDisabled
    }

    private var showsSearchAccessory: Bool { canSearch && !isSelecting }

    private func updateSearchAccessoryVisibility(_ visible: Bool) {
        guard usesSystemBottomAccessory, isSearchAccessoryVisible != visible else { return }
        // The navigation toolbar owns the selection transaction. Publish the
        // tab accessory separately rather than rebuilding both hosts in it.
        let animation: Animation?
        if reduceSelectionMotion { animation = nil }
        else if #available(iOS 17.0, *) { animation = .smooth(duration: 0.22) }
        else { animation = .easeInOut(duration: 0.22) }
        withAnimation(animation) { isSearchAccessoryVisible = visible }
    }

    private var timeContent: some View {
        Group {
            if isLoadingSessionSnapshot {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sessionSolves.isEmpty {
                VStack {
                    Text("data.no_solves")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 48)
                    Spacer()
                }
            } else if visibleSessionSolves.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("data.filter.no_matches")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)

                    Button("data.filter.reset") {
                        resetAllFilters()
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
            } else {
                Group {
                    let numberWidth = solveNumberColumnWidth
                    let boundary = rangeBoundary
                    let list = List {
                        Section(selectedSession?.name ?? "") {
                            ForEach(visibleSessionSolves) { solve in
                                solveRow(for: solve, position: solvePositionByID[solve.id] ?? 0, numberWidth: numberWidth)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                    .background {
                                        if tracksSelectionRange {
                                            GeometryReader { rowProxy in
                                                Color.clear.preference(key: SolveRowFramesKey.self,
                                                                       value: [solve.id: rowProxy.frame(in: .global)])
                                            }
                                        }
                                    }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .compatibleSoftScrollEdgeEffect()

                    dataTimeListViewport(list)
                    .background {
                        if tracksSelectionRange {
                            GeometryReader { proxy in
                                Color.clear.preference(key: DataListViewportKey.self, value: proxy.frame(in: .global))
                            }
                        }
                    }
                    .onPreferenceChange(DataListViewportKey.self) { listViewport = $0 }
                    .onPreferenceChange(SolveRowFramesKey.self) { rowFrames = $0 }
                    .onPreferenceChange(SolveRangeControlFrameKey.self) { rangeControlFrame = $0 }
                    .overlay(alignment: .top) {
                        if let boundary, !boundary.anchorIsAbove {
                            selectToHereButton(boundary).padding(.top, 8)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if let boundary, boundary.anchorIsAbove {
                            selectToHereButton(boundary).padding(.bottom, 8)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dataTimeListViewport<Content: View>(_ content: Content) -> some View {
        if #available(iOS 26.0, *), usesSystemBottomAccessory {
            GeometryReader { geometry in
                // Keep the scroll surface under the bars as their safe area changes.
                // Only the content and indicator insets should follow that safe area.
                content
                    .contentMargins(.bottom, geometry.safeAreaInsets.bottom, for: .scrollContent)
                    .contentMargins(.bottom, geometry.safeAreaInsets.bottom, for: .scrollIndicators)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
        } else {
            content
        }
    }

    private var segmentSelection: Binding<DataSegment> {
        Binding(
            get: { selectedSegment },
            set: { newValue in
                let currentIndex = selectedSegment.segmentIndex
                let newIndex = newValue.segmentIndex
                segmentTransitionDirection = newIndex > currentIndex ? .trailing : .leading
                withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                    selectedSegment = newValue
                }
            }
        )
    }

    private var segmentTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: segmentTransitionDirection).combined(with: .opacity),
            removal: .move(edge: segmentTransitionDirection == .trailing ? .leading : .trailing)
                .combined(with: .opacity)
        )
    }

    private var averageContent: some View {
        Group {
            if isLoadingSessionSnapshot {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if availableAverageTypes.isEmpty {
                VStack {
                    Text("data.no_averages")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 48)
                    Spacer()
                }
            } else if isComputingAverageEntries {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visibleAverageEntries) { entry in
                    averageRow(for: entry)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
                .listStyle(.plain)
                .compatibleSoftScrollEdgeEffect()
            }
        }
    }

    private var recordContent: some View {
        Group {
            if isLoadingSessionSnapshot || isComputingRecordSnapshot {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section(selectedSession?.name ?? "") {
                        recordRow(
                            title: localizedRecordLabel("data.session_mean"),
                            value: recordSnapshot.sessionMeanText,
                            suffix: recordSnapshot.sessionMeanSuffix
                        )
                        recordRow(
                            title: localizedRecordLabel("data.best_time"),
                            value: recordSnapshot.bestTimeText,
                            action: showBestSingle
                        )
                        recordRow(
                            title: localizedRecordLabel("data.worst_time"),
                            value: recordSnapshot.worstTimeText,
                            action: showWorstSingle
                        )
                    }

                    if recordFilterOption != .best, !recordSnapshot.currentStats.isEmpty {
                        Section(localizedRecordLabel("common.current")) {
                            ForEach(recordSnapshot.currentStats) { item in
                                recordRow(
                                    title: item.title,
                                    secondaryTitle: item.secondaryTitle,
                                    value: item.value
                                ) {
                                    showRecordDetail(for: item, scope: .current)
                                }
                            }
                        }
                    }

                    if recordFilterOption != .current, !recordSnapshot.bestStats.isEmpty {
                        Section {
                            ForEach(recordSnapshot.bestStats) { item in
                                recordRow(
                                    title: item.title,
                                    secondaryTitle: item.secondaryTitle,
                                    value: item.value
                                ) {
                                    showRecordDetail(for: item, scope: .best)
                                }
                            }
                        } header: {
                            HStack {
                                Text(localizedRecordLabel("common.best"))
                                Spacer()
                                Button {
                                    showingRecordHistory = true
                                } label: {
                                    Text("data.record_history")
                                        .textCase(nil)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.tint)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .compatibleSoftScrollEdgeEffect()
            }
        }
    }

    private func averageCard(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .medium))
            Spacer()
            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .monospacedDigit()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func recordRow(
        title: String,
        secondaryTitle: String? = nil,
        value: String,
        suffix: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        let content = HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)

                if let secondaryTitle {
                    Text(secondaryTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                if let suffix {
                    Text(suffix)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)

            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)

        return Group {
            if let action {
                Button(action: action) {
                    content
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private func averageRow(for entry: AverageListEntry) -> some View {
        Button {
            averageDetailEntry = entry
        } label: {
            HStack(spacing: 12) {
                Text("#\(entry.position)")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer()

                Text(SolveMetrics.formatAverage(entry.value, decimals: solveTimeAccuracy.decimals))
                    .font(.system(size: 24, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(entry.isPersonalBest ? WCAResultEmphasis.personalBest.color : .primary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func solveRow(for solve: SessionSolveSample, position: Int, numberWidth: CGFloat) -> some View {
        Button {
            if isSelecting { toggleSelection(for: solve) } else { solveDetailSample = solve }
        } label: {
            HStack(spacing: 12) {
                Text("#\(NumeralPresentation.formatInteger(position))")
                    .font(.body).monospacedDigit().foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(minWidth: numberWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SolveMetrics.displayTime(for: solve, decimals: solveTimeAccuracy.decimals))
                            .font(.system(size: solveTimeFontSize, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(personalBestSingleSolveIDs.contains(solve.id) ? WCAResultEmphasis.personalBest.color : .primary)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if let glyph = solveEventGlyph(solve) {
                                CompetitionEventGlyph(glyph: glyph, eventName: solveEventName(solve), size: 15, color: .secondary)
                            }
                            Text(appLocalizedString(solve.inputSource?.localizationKey ?? "solve.method.unknown", languageCode: appLanguage))
                                .font(.subheadline).foregroundStyle(.secondary).layoutPriority(1)
                            Spacer(minLength: 2)
                            Text(SolveMetrics.displayDate(solve.date, languageCode: appLanguage))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                    }
                    Text(solve.scramble.isEmpty ? appLocalizedString("data.scramble_empty", languageCode: appLanguage) : solve.scramble)
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if isSelecting {
                        SolveSelectionCheckmark(selected: selectedSolveIDs.contains(solve.id),
                            replacementAnimation: .easeInOut(duration: 0.20))
                    } else {
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 28)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelecting && selectedSolveIDs.contains(solve.id) ? .isSelected : [])
        .accessibilityIdentifier("data-solve-row")
    }

    private var solveNumberColumnWidth: CGFloat {
        let text = "#\(NumeralPresentation.formatInteger(max(filteredSessionSolves.count, 1)))"
        let font = UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private func solveEventGlyph(_ solve: SessionSolveSample) -> String? {
        let id = PuzzleEvent.fromSolveEvent(solve.eventRawValue)?.cubingEventID ?? solve.eventRawValue
        return CompetitionEventIconFont.glyph(for: id)
    }

    private func solveEventName(_ solve: SessionSolveSample) -> String {
        if let event = PuzzleEvent.fromSolveEvent(solve.eventRawValue) {
            return appLocalizedString(event.localizationKey, languageCode: appLanguage)
        }
        return solve.eventRawValue
    }

    @State private var selectionToolbarWidth: CGFloat = 0

    @ScaledMetric(relativeTo: .body) private var selectionTextScale: CGFloat = 1

    private func selectionActions(count: Int) -> DataSelectionToolbarActions {
        // Selection is reconciled to the visible rows whenever the list changes.
        let allSelected = DataSelectionButtonLayout.allSelected(selected: count, visible: visibleSessionSolves.count)
        let hasSelection = count > 0
        let title = appLocalizedString("common.delete", languageCode: appLanguage)
        let all = appLocalizedString(allSelected ? "common.deselect_all" : "common.select_all", languageCode: appLanguage)
        let move = hasSelection ? solveMoveLabel(count: count, languageCode: appLanguage) : nil
        let layout = DataSelectionButtonLayout(availableWidth: selectionToolbarWidth, allTitle: all, moveTitle: move,
                                               deleteTitle: title, textScale: selectionTextScale)
        return (
            DataSelectionToolbarAction(title: all, isDestructive: false, enabled: !visibleSessionSolves.isEmpty,
                identifier: "data-selection-all", perform: toggleAllVisibleSolves,
                systemImage: layout.iconActions[0] ? (allSelected ? "circle" : "checkmark.circle") : nil,
                width: layout.actionWidths[0], height: layout.height),
            move.map { title in DataSelectionToolbarAction(title: title, isDestructive: false, enabled: true,
                identifier: "data-selection-move", perform: {
                    guard !selectedSolveIDs.isEmpty, let source = selectedSession else { return }
                    moveRequest = SolveMoveRequest(sourceID: source.id, solveIDs: selectedSolveIDs)
                }, systemImage: layout.iconActions[1] ? "folder" : nil,
                width: layout.actionWidths[1], height: layout.height) },
            DataSelectionToolbarAction(title: title, isDestructive: true, enabled: hasSelection,
                identifier: "data-selection-delete", perform: {
                    if !selectedSolveIDs.isEmpty { isShowingDeleteSelectedSolvesAlert = true }
                }, systemImage: layout.useTrash ? "trash" : nil, width: layout.width, height: layout.height),
            rowWidth: max(layout.actionWidths.reduce(layout.width, +) + (hasSelection ? 2 : 1) * DataSelectionButtonLayout.spacing,
                selectionToolbarWidth - 2 * DataSelectionButtonLayout.barMargin),
            animation: selectionActionTransition
        )
    }

    private func toggleAllVisibleSolves() {
        let selection = DataSelectionButtonLayout.toggledAll(
            selected: selectedSolveIDs.count, visible: visibleSessionSolves)
        withAnimation(selectionActionTransition) {
            selectionAnchorID = nil
            selectedSolveIDs = selection
        }
    }

    private var tracksSelectionRange: Bool { isSelecting && selectionAnchorID != nil }

    private var rangeBoundary: SolveSelectionRange.Boundary? {
        guard isSelecting, let selectionAnchorID else { return nil }
        let visible = SolveSelectionRange.visuallyVisibleIDs(rowFrames: rowFrames, viewport: listViewport)
        // Local deletion can remove rows before the next snapshot replaces its ranks.
        let usesCurrentRanks = !hasActiveSolveFilters && solvePositionByID.count == visibleSessionSolves.count
        func endpoint(for ids: Set<UUID>) -> SolveSelectionRange.Boundary? {
            if usesCurrentRanks {
                return SolveSelectionRange.boundary(anchor: selectionAnchorID, visibleIDs: ids,
                    newestFirstPositions: solvePositionByID)
            }
            return SolveSelectionRange.boundary(anchor: selectionAnchorID, visibleIDs: ids,
                orderedIDs: visibleSessionSolves.lazy.map(\.id))
        }
        guard let boundary = endpoint(for: visible) else { return nil }
        let endpointRows = SolveSelectionRange.visuallyVisibleIDs(rowFrames: rowFrames, viewport: listViewport,
            control: rangeControlFrame, anchorIsAbove: boundary.anchorIsAbove)
        return endpoint(for: endpointRows)
    }

    private func selectToHereButton(_ boundary: SolveSelectionRange.Boundary) -> some View {
        Button {
            guard let anchor = selectionAnchorID else { return }
            selectedSolveIDs.formUnion(SolveSelectionRange.ids(from: anchor, through: boundary.id, orderedIDs: visibleSessionSolves.map(\.id)))
        } label: {
            Label("data.select.to_here", systemImage: boundary.anchorIsAbove ? "arrow.down" : "arrow.up")
                .font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 9)
        }
        .compatibleGlass(in: Capsule())
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: SolveRangeControlFrameKey.self, value: proxy.frame(in: .global))
            }
        }
    }

    private var averageTypeBar: some View {
        HStack {
            Picker("Average Type", selection: $selectedAverageType) {
                ForEach(availableAverageTypes) { averageType in
                    Text(averageType.title(languageCode: appLanguage)).tag(averageType)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .compatibleGlass(in: Capsule())
    }

    private func toggleSelection(for solve: SessionSolveSample) {
        let removing = selectedSolveIDs.contains(solve.id)
        let changesMovePresence = removing ? selectedSolveIDs.count == 1 : selectedSolveIDs.isEmpty
        withAnimation(changesMovePresence ? selectionActionTransition : nil) {
            if removing { selectedSolveIDs.remove(solve.id) }
            else { selectedSolveIDs.insert(solve.id) }
            selectionAnchorID = SolveSelectionRange.anchorAfterDirectToggle(id: solve.id, selected: !removing, previous: selectionAnchorID)
        }
    }

    private func deleteSelectedSolves() {
        let deletedIDs = selectedSolveIDs
        guard let solves = try? modelContext.fetchSolves(with: deletedIDs) else { return }
        for solve in solves {
            solve.comment = ""
            modelContext.delete(solve)
        }
        try? modelContext.save()
        filteredSessionSolves.removeAll { deletedIDs.contains($0.id) }
        updateVisibleSessionSolves()
        selectedSolveIDs.removeAll()
        NotificationCenter.default.post(name: solvesDidChangeNotification, object: nil)
    }

    private func fetchSolve(with id: UUID) -> Solve? {
        try? modelContext.fetchSolve(with: id)
    }

    private func showBestSingle() {
        solveDetailSample = sessionSolves.lazy
            .compactMap { solve -> (SessionSolveSample, Double)? in
                guard let value = solve.adjustedTime else { return nil }
                return (solve, value)
            }
            .min { $0.1 < $1.1 }?.0
    }

    private func showWorstSingle() {
        solveDetailSample = sessionSolves.lazy
            .compactMap { solve -> (SessionSolveSample, Double)? in
                guard let value = solve.adjustedTime else { return nil }
                return (solve, value)
            }
            .max { $0.1 < $1.1 }?.0
    }

    private func showRecordDetail(for item: RecordStatItem, scope: RecordDetailScope) {
        if item.metricRawValue == "single" {
            switch scope {
            case .current:
                solveDetailSample = sessionSolves.first
            case .best:
                showBestSingle()
            }
            return
        }

        guard let metric = RecordAverageMetric.defaultMetrics.first(where: {
            $0.title == item.metricRawValue
        }) else { return }
        let samples = sessionSolves

        Task {
            let selection = await Task.detached(priority: .userInitiated) {
                Self.makeRecordAverageDetail(metric: metric, scope: scope, solves: samples)
            }.value
            guard !Task.isCancelled else { return }
            recordAverageDetail = selection
        }
    }

    nonisolated private static func makeRecordAverageDetail(
        metric: RecordAverageMetric,
        scope: RecordDetailScope,
        solves: [SessionSolveSample]
    ) -> RecordAverageDetailSelection? {
        let evaluation = DataTabComputation.evaluateRecordMetric(
            metric: metric,
            solves: solves,
            includeWindowValues: true
        )
        guard !evaluation.windowValues.isEmpty else { return nil }

        let index: Int
        switch scope {
        case .current:
            index = 0
        case .best:
            let finiteBest = evaluation.windowValues.enumerated()
                .compactMap { index, value -> (Int, Double)? in
                    guard let value, value.isFinite else { return nil }
                    return (index, value)
                }
                .min { $0.1 < $1.1 }
            index = finiteBest?.0
                ?? evaluation.windowValues.firstIndex(where: { $0 != nil })
                ?? 0
        }

        guard let value = evaluation.windowValues[index] else { return nil }
        let totalWindows = evaluation.windowValues.count
        let averagePosition = totalWindows - index
        let windowSolves = Array(solves[index..<(index + metric.solveCount)])
        let isPersonalBest: Bool
        switch scope {
        case .current: isPersonalBest = false
        case .best: isPersonalBest = true
        }
        return RecordAverageDetailSelection(
            entry: AverageListEntry(
                position: averagePosition,
                date: solves[index].date,
                value: value,
                isPersonalBest: isPersonalBest,
                solves: windowSolves
            ),
            metric: AverageDetailMetric(metric)
        )
    }

    private func localizedRecordLabel(_ key: String) -> String {
        dataTabLocalizedString(for: key, languageCode: appLanguage)
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

    private func refreshFilteredSessionSolves() {
        sessionSnapshotTask?.cancel()
        sessionSnapshotGeneration += 1
        cancelRecordComputation()
        averageComputationGeneration += 1
        recordSnapshotKey = nil
        averageEntriesKey = nil
        if showingSessionSheet || sessionSnapshotDeferred {
            // The sheet commits the real selection immediately. Its parent
            // does not need to load each intermediate session behind it.
            sessionSnapshotDeferred = true
            isLoadingSessionSnapshot = true
            return
        }
        #if DEBUG
        performanceProbe?.dataRequests += 1
        #endif
        guard let selectedSession else {
            filteredSessionSolves = []
            visibleSessionSolves = []
            reconcileVisibleSelection()
            solvePositionByID = [:]
            recordSnapshotKey = nil
            isLoadingSessionSnapshot = false
            return
        }

        let sessionID = selectedSession.id
        let generation = sessionSnapshotGeneration
        let reader = snapshotReader ?? SessionSolveSnapshotReader(viewContext: modelContext)
        snapshotReader = reader
        isLoadingSessionSnapshot = true
        sessionSnapshotTask = Task {
            let snapshots = (try? await reader.load(sessionID: sessionID)) ?? []
            guard !Task.isCancelled, generation == sessionSnapshotGeneration else { return }
            let indexWorker = Task.detached(priority: .userInitiated) { try DataSessionDerivedIndex(snapshots) }
            let index = await withTaskCancellationHandler(operation: { try? await indexWorker.value },
                onCancel: { indexWorker.cancel() })
            guard !Task.isCancelled, generation == sessionSnapshotGeneration, let index else { return }
            filteredSessionSolves = snapshots
            #if DEBUG
            performanceProbe?.dataCount = snapshots.count
            #endif
            initializeRangeFiltersIfNeeded(from: index.bounds)
            personalBestSingleSolveIDs = index.personalBests
            solvePositionByID = index.positions
            updateVisibleSessionSolves()
            isLoadingSessionSnapshot = false
            syncSelectedAverageType()
            prewarmRecordSnapshotIfNeeded()
            ensureAverageEntriesSnapshot()
            if selectedSegment == .record {
                refreshRecordSnapshot()
            }
        }
    }

    private func resumeSessionSnapshotAfterSheet() {
        guard sessionSnapshotDeferred else { return }
        sessionSnapshotDeferred = false
        refreshFilteredSessionSolves()
    }

    private func updateVisibleSessionSolves() {
        guard !sessionSnapshotDeferred else { return }
        let sortOption = DataSolveSortOption(rawValue: solveSortOptionRawValue) ?? .newest
        if !hasActiveSolveFilters {
            visibleSessionSolves = filteredSessionSolves
            reconcileVisibleSelection()
            return
        }
        let calendar = Calendar.current
        let dateLowerBound = calendar.startOfDay(for: min(startDateFilter, endDateFilter))
        let dateUpperDay = calendar.startOfDay(for: max(startDateFilter, endDateFilter))
        let dateUpperBound = calendar.date(byAdding: .day, value: 1, to: dateUpperDay) ?? dateUpperDay
        let timeLowerBound = min(minimumTimeFilter, maximumTimeFilter)
        let timeUpperBound = max(minimumTimeFilter, maximumTimeFilter)
        let resultFilter = DataSolveResultFilter(rawValue: solveResultFilterRawValue) ?? .all
        let matchingSolves = filteredSessionSolves.filter { solve in
            guard resultFilter.matches(solve) else { return false }

            if isTimeRangeFilterEnabled {
                guard let adjustedTime = solve.adjustedTime,
                      adjustedTime >= timeLowerBound,
                      adjustedTime <= timeUpperBound else { return false }
            }

            if isDateRangeFilterEnabled,
               !(solve.date >= dateLowerBound && solve.date < dateUpperBound) {
                return false
            }

            return true
        }
        visibleSessionSolves = sortOption == .newest ? matchingSolves : matchingSolves.sorted(by: sortOption.areInIncreasingOrder)
        reconcileVisibleSelection()
    }

    private func reconcileVisibleSelection() {
        guard !selectedSolveIDs.isEmpty || selectionAnchorID != nil else { return }
        let availableIDs = Set(visibleSessionSolves.map(\.id))
        selectedSolveIDs.formIntersection(availableIDs)
        if let anchor = selectionAnchorID, !availableIDs.contains(anchor) { selectionAnchorID = nil }
    }

    private func initializeRangeFiltersIfNeeded(from bounds: DataSolveFilterBounds) {
        if !isTimeRangeFilterEnabled, let times = bounds.times {
            minimumTimeFilter = times.lowerBound
            maximumTimeFilter = times.upperBound
        }
        if !isDateRangeFilterEnabled, let dates = bounds.dates {
            startDateFilter = dates.lowerBound
            endDateFilter = dates.upperBound
        }
    }

    private func resetRangeFilters() {
        isTimeRangeFilterEnabled = false
        isDateRangeFilterEnabled = false
    }

    private func resetAllFilters() {
        solveSortOptionRawValue = DataSolveSortOption.newest.rawValue
        solveResultFilterRawValue = DataSolveResultFilter.all.rawValue
        resetRangeFilters()
        initializeRangeFiltersIfNeeded(from: DataSolveFilterBounds(filteredSessionSolves,
            includeTimes: true, includeDates: true))
        updateVisibleSessionSolves()
    }

    private func resetAverageFilters() {
        averageSortOptionRawValue = DataAverageSortOption.newest.rawValue
    }

    private func resetRecordFilters() {
        recordFilterOptionRawValue = DataRecordFilterOption.all.rawValue
    }

    private func syncSelectedAverageType() {
        guard let firstAvailable = availableAverageTypes.first else { return }
        if !availableAverageTypes.contains(selectedAverageType) {
            selectedAverageType = firstAvailable
        }
    }

    private func refreshRecordSnapshot() {
        refreshRecordSnapshot(showLoading: true)
    }

    private func prewarmRecordSnapshotIfNeeded() {
        guard selectedSegment != .record else { return }
        refreshRecordSnapshot(showLoading: false)
    }

    private func cancelRecordComputation() {
        recordComputationGeneration += 1
        recordComputation?.task.cancel()
        recordComputation = nil
    }

    private func refreshRecordSnapshot(showLoading: Bool) {
        guard let snapshotKey = currentSessionSnapshotKey else {
            cancelRecordComputation()
            recordSnapshot = .empty
            recordSnapshotKey = nil
            isComputingRecordSnapshot = false
            return
        }

        if recordSnapshotKey == snapshotKey {
            isComputingRecordSnapshot = false
            return
        }

        if let pending = recordComputation, pending.key == snapshotKey {
            if showLoading && !isComputingRecordSnapshot {
                isComputingRecordSnapshot = true
                // Awaiting promotes the same prewarm worker to foreground priority.
                Task(priority: .userInitiated) { await pending.task.value }
            }
            return
        }

        cancelRecordComputation()
        let samples = sessionSolves
        let notAvailable = appLocalizedString("common.not_available", languageCode: appLanguage)
        let languageCode = appLanguage
        let generation = recordComputationGeneration
        isComputingRecordSnapshot = showLoading

        let task = Task.detached(priority: showLoading ? .userInitiated : .utility) {
            guard let snapshot = try? DataTabComputation.buildRecordSnapshotData(
                from: samples,
                notAvailable: notAvailable,
                languageCode: languageCode,
                timeDecimals: snapshotKey.timeDecimals,
                checkCancellation: { try Task.checkCancellation() }
            ), !Task.isCancelled else { return }

            await MainActor.run {
                guard generation == recordComputationGeneration else { return }
                recordComputation = nil
                guard currentSessionSnapshotKey == snapshotKey else { return }
                recordSnapshot = snapshot
                recordSnapshotKey = snapshotKey
                if showLoading || selectedSegment == .record {
                    isComputingRecordSnapshot = false
                }
            }
        }
        recordComputation = (snapshotKey, task)
    }


    private var currentAverageEntriesKey: AverageEntriesSnapshotKey? {
        guard let selectedSession else { return nil }
        return AverageEntriesSnapshotKey(
            sessionID: selectedSession.id,
            solveCount: sessionSolves.count,
            averageType: selectedAverageType
        )
    }

    private func ensureAverageEntriesSnapshot() {
        guard availableAverageTypes.contains(selectedAverageType), let snapshotKey = currentAverageEntriesKey else {
            averageEntriesSnapshot = []
            averageEntriesKey = nil
            isComputingAverageEntries = false
            return
        }

        guard averageEntriesKey != snapshotKey else {
            isComputingAverageEntries = false
            return
        }

        refreshAverageEntries(for: snapshotKey)
    }

    private func refreshAverageEntries(for snapshotKey: AverageEntriesSnapshotKey) {
        let samples = sessionSolves
        let averageType = selectedAverageType
        let generation = averageComputationGeneration + 1
        averageComputationGeneration = generation
        isComputingAverageEntries = selectedSegment == .average && averageEntriesSnapshot.isEmpty

        Task.detached(priority: selectedSegment == .average ? .userInitiated : .utility) {
            let entries = DataTabComputation.buildAverageEntriesSnapshot(
                from: samples,
                averageType: averageType
            )

            await MainActor.run {
                guard generation == averageComputationGeneration, currentAverageEntriesKey == snapshotKey else { return }
                averageEntriesSnapshot = entries
                averageEntriesKey = snapshotKey
                isComputingAverageEntries = false
            }
        }
    }
}


private struct AverageEntriesSnapshotKey: Equatable {
    let sessionID: UUID
    let solveCount: Int
    let averageType: AverageListType
}

private struct DataTabLeadingToolbarModifier: ViewModifier {
    let onShowSessions: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onShowSessions()
                } label: {
                    Text("common.session")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
    }
}

private struct DataSelectionToolbarWidth: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct DataListViewportKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct DataLegacySearchInset: ViewModifier {
    let enabled: Bool
    let visible: Bool
    let languageCode: String
    let openSearch: () -> Void

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if visible {
                    DataBottomSearchBar(languageCode: languageCode, searchAction: openSearch)
                        .compatibleGlass(in: Capsule())
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
        } else {
            content
        }
    }
}

private typealias DataSelectionToolbarActions = (all: DataSelectionToolbarAction, move: DataSelectionToolbarAction?, delete: DataSelectionToolbarAction, rowWidth: CGFloat, animation: Animation?)

private struct DataSelectionToolbar: ViewModifier {
    let actions: DataSelectionToolbarActions?

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.toolbar { modernItems }
                .toolbarBackgroundVisibility(.hidden, for: .bottomBar)
        } else {
            content.toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    if let actions {
                        actions.all
                        Spacer()
                        if let move = actions.move {
                            move
                            Spacer()
                        }
                        actions.delete
                    }
                }
            }
        }
    }

    @available(iOS 26.0, *)
    @ToolbarContentBuilder private var modernItems: some ToolbarContent {
        if let actions {
            // One native toolbar item prevents UIKit from overflowing an
            // individual action. Its own layout budgets all touch targets.
            ToolbarItem(id: "data-selection-actions", placement: .bottomBar) {
                HStack(spacing: 0) {
                    actions.all
                    Spacer(minLength: DataSelectionButtonLayout.spacing)
                    if let move = actions.move {
                        move.transition(.opacity)
                        Spacer(minLength: DataSelectionButtonLayout.spacing)
                    }
                    DataProminentDeleteItem(action: actions.delete)
                        .frame(width: actions.delete.width, height: actions.delete.height)
                }
                .frame(width: actions.rowWidth)
                .animation(actions.animation, value: [actions.all.width, actions.move?.width ?? 0, actions.delete.width])
                .animation(actions.animation, value: actions.delete.enabled)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}

@available(iOS 26.0, *)
@MainActor
private func updateSessionBarItem(_ item: UIBarButtonItem, enabled: Bool, in bar: UIView,
                                  animate: (_ changes: () -> Void) -> Void) {
    guard item.isEnabled != enabled else { return }
    animate {
        // SwiftUI may update the bridge outside a UIKit animation block.
        let inherited = UIView.inheritedAnimationDuration
        let duration = inherited > 0 ? inherited : CATransaction.animationDuration()
        UIView.transition(with: bar, duration: duration,
                          options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction]) {
            item.isEnabled = enabled
            bar.layoutIfNeeded()
        }
    }
}

@available(iOS 26.0, *)
private struct DataProminentDeleteItem: UIViewRepresentable {
    let title: String
    let systemImage: String?
    let enabled: Bool
    let identifier: String
    let usesDataEnabledTransition: Bool
    let perform: () -> Void

    init(action: DataSelectionToolbarAction) {
        self.init(title: action.title, systemImage: action.systemImage, enabled: action.enabled,
                  identifier: action.identifier, usesDataEnabledTransition: true, perform: action.perform)
    }

    init(title: String, systemImage: String? = nil, enabled: Bool, identifier: String,
         usesDataEnabledTransition: Bool = false, perform: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.enabled = enabled
        self.identifier = identifier
        self.usesDataEnabledTransition = usesDataEnabledTransition
        self.perform = perform
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.directionalLayoutMargins = .zero
        toolbar.insetsLayoutMarginsFromSafeArea = false
        let appearance = UIToolbarAppearance()
        appearance.configureWithTransparentBackground()
        toolbar.standardAppearance = appearance
        toolbar.scrollEdgeAppearance = appearance
        updateUIView(toolbar, context: context)
        // Center the native item in the existing slot, without resizing its pill.
        toolbar.items = [.flexibleSpace(), context.coordinator.item, .flexibleSpace()]
        return toolbar
    }

    func updateUIView(_ toolbar: UIToolbar, context: Context) {
        let coordinator = context.coordinator
        coordinator.perform = perform
        let item = coordinator.item
        let itemTitle = systemImage == nil ? title : nil
        // Reapplying unchanged bar item properties can invalidate hosted layout.
        if item.title != itemTitle { item.title = itemTitle }
        if coordinator.systemImage != systemImage {
            coordinator.systemImage = systemImage
            item.image = systemImage.flatMap { UIImage(systemName: $0) }
        }
        if item.accessibilityIdentifier != identifier { item.accessibilityIdentifier = identifier }
        if item.accessibilityLabel != title { item.accessibilityLabel = title }
        if item.isEnabled != enabled {
            if usesDataEnabledTransition, toolbar.window != nil,
               context.transaction.animation != nil,
               !context.transaction.disablesAnimations,
               !UIAccessibility.isReduceMotionEnabled {
                // UIKit switches a bar item's enabled appearance discretely.
                // Transition the rendered states without delaying the item update.
                UIView.transition(with: toolbar, duration: dataSelectionActionDuration,
                    options: [.transitionCrossDissolve, .curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]) {
                    item.isEnabled = enabled
                }
            } else if !usesDataEnabledTransition, toolbar.window != nil, !context.transaction.disablesAnimations,
                      !context.environment.accessibilityReduceMotion, !UIAccessibility.isReduceMotionEnabled {
                updateSessionBarItem(item, enabled: enabled, in: toolbar) { context.animate(changes: $0) }
            } else {
                item.isEnabled = enabled
            }
        }
    }

    final class Coordinator: NSObject {
        var perform: (() -> Void)?
        var systemImage: String?
        lazy var item: UIBarButtonItem = {
            let item = UIBarButtonItem(title: nil, style: .plain, target: self, action: #selector(tap))
            SessionNativeActionStyle.apply(to: item, tint: .systemRed)
            return item
        }()

        @objc private func tap() { perform?() }
    }
}

private struct DataSelectionToolbarAction: View {
    let title: String
    let isDestructive: Bool
    let enabled: Bool
    let identifier: String
    let perform: () -> Void
    let systemImage: String?
    let width: CGFloat
    let height: CGFloat

    @ViewBuilder var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: isDestructive ? .destructive : nil, action: perform) {
                titleContent
                    .foregroundStyle(enabled ? Color.primary : Color.secondary)
                    .frame(width: width, height: height)
                    .contentShape(Capsule())
                    .glassEffect(
                        isDestructive && enabled
                            ? .regular.tint(.red).interactive(true)
                            : .regular.interactive(enabled),
                        in: .capsule
                    )
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityLabel(Text(title))
            .accessibilityIdentifier(identifier)
        } else {
            button
        }
    }

    private var button: some View {
        Button(role: isDestructive ? .destructive : nil, action: perform) {
            titleContent
        }
        .disabled(!enabled)
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier(identifier)
    }

    private var titleContent: some View {
        ZStack {
            if let systemImage {
                Image(systemName: systemImage).transition(.opacity)
            } else {
                Text(title).lineLimit(1).id(title).transition(.opacity)
            }
        }
    }
}

nonisolated struct DataSessionDerivedIndex: Sendable {
    let positions: [UUID: Int]
    let personalBests: Set<UUID>
    let bounds: DataSolveFilterBounds

    init(_ solves: [SessionSolveSample]) throws {
        var positions: [UUID: Int] = [:]
        positions.reserveCapacity(solves.count)
        var personalBests: Set<UUID> = []
        var best: Double?
        var bounds = DataSolveFilterBounds()
        for (offset, solve) in solves.reversed().enumerated() {
            if offset.isMultiple(of: 128) { try Task.checkCancellation() }
            positions[solve.id] = offset + 1
            let time = solve.adjustedTime
            if let time, best.map({ time < $0 }) ?? true {
                personalBests.insert(solve.id)
                best = time
            }
            bounds.include(time: time, date: solve.date)
        }
        self.positions = positions
        self.personalBests = personalBests
        self.bounds = bounds
    }
}

nonisolated struct DataSolveFilterBounds: Sendable {
    private(set) var times: ClosedRange<Double>?
    private(set) var dates: ClosedRange<Date>?

    init() {}

    init(_ solves: [SessionSolveSample], includeTimes: Bool, includeDates: Bool) {
        guard includeTimes || includeDates else { return }
        for solve in solves {
            include(time: includeTimes ? solve.adjustedTime : nil, date: includeDates ? solve.date : nil)
        }
    }

    mutating func include(time: Double?, date: Date?) {
        if let time, !time.isNaN {
            if let times { self.times = min(times.lowerBound, time)...max(times.upperBound, time) }
            else { times = time...time }
        }
        if let date {
            if let dates { self.dates = min(dates.lowerBound, date)...max(dates.upperBound, date) }
            else { dates = date...date }
        }
    }
}

struct DataSelectionButtonLayout {
    static let spacing: CGFloat = 8
    private static let minimumTarget: CGFloat = 44
    private static let preferredTextInset: CGFloat = 14
    private static let compactTextInset: CGFloat = 10
    static let barMargin: CGFloat = 20

    let useTrash: Bool
    let iconActions: [Bool]
    let width: CGFloat
    let height: CGFloat
    let actionWidths: [CGFloat]
    let textInset: CGFloat

    static func allSelected(selected: Int, visible: Int) -> Bool {
        visible > 0 && selected == visible
    }

    static func toggledAll(selected: Int, visible: [SessionSolveSample]) -> Set<UUID> {
        // Changes to the visible list reconcile selection before it is usable.
        allSelected(selected: selected, visible: visible.count) ? [] : Set(visible.lazy.map(\.id))
    }

    init(availableWidth: CGFloat, allTitle: String, moveTitle: String?, deleteTitle: String, textScale: CGFloat = 1) {
        let font = UIFont.systemFont(ofSize: 17 * textScale)
        func measure(_ title: String) -> CGFloat {
            ceil((title as NSString).size(withAttributes: [.font: font]).width)
        }
        let targetHeight = max(Self.minimumTarget, ceil(font.lineHeight) + 12)
        let titles = [measure(allTitle), moveTitle.map(measure) ?? 0, measure(deleteTitle)]
        let contentWidth = max(0, availableWidth - 2 * Self.barMargin)
        // Use the whole row before sacrificing a label; protect the two
        // leading actions before the destructive action.
        let masks = [0, 4, 6, 7]
        func widths(for mask: Int, inset: CGFloat) -> [CGFloat] {
            titles.enumerated().map { index, width in
                if index == 1 && moveTitle == nil { return 0 }
                return mask & (1 << index) == 0 ? max(Self.minimumTarget, width + 2 * inset) : Self.minimumTarget
            }
        }
        let insets = [Self.preferredTextInset, Self.compactTextInset]
        let candidates = masks.flatMap { mask in insets.map { (mask, $0) } }
        let (mask, inset) = candidates.first { mask, inset in
            widths(for: mask, inset: inset).reduce(0, +) + (moveTitle == nil ? 1 : 2) * Self.spacing <= contentWidth
        } ?? (7, Self.preferredTextInset)
        let fitted = widths(for: mask, inset: inset)
        textInset = inset
        iconActions = [mask & 1 != 0, mask & 2 != 0]
        useTrash = mask & 4 != 0
        height = mask == 7 ? Self.minimumTarget : targetHeight
        width = fitted[2]
        actionWidths = Array(fitted.prefix(2))
    }
}

private enum DataSolveSortOption: String, CaseIterable {
    case newest
    case oldest
    case fastest
    case slowest

    var titleKey: LocalizedStringKey {
        switch self {
        case .newest: "data.filter.sort.newest"
        case .oldest: "data.filter.sort.oldest"
        case .fastest: "data.filter.sort.fastest"
        case .slowest: "data.filter.sort.slowest"
        }
    }

    func areInIncreasingOrder(_ lhs: SessionSolveSample, _ rhs: SessionSolveSample) -> Bool {
        switch self {
        case .newest:
            return lhs.date > rhs.date
        case .oldest:
            return lhs.date < rhs.date
        case .fastest:
            return compareByTime(lhs, rhs, dnfFirst: false)
        case .slowest:
            return compareByTime(lhs, rhs, dnfFirst: true)
        }
    }

    private func compareByTime(
        _ lhs: SessionSolveSample,
        _ rhs: SessionSolveSample,
        dnfFirst: Bool
    ) -> Bool {
        switch (lhs.adjustedTime, rhs.adjustedTime) {
        case let (lhsTime?, rhsTime?):
            if lhsTime == rhsTime {
                return lhs.date > rhs.date
            }
            return self == .fastest ? lhsTime < rhsTime : lhsTime > rhsTime
        case (nil, nil):
            return lhs.date > rhs.date
        case (nil, _?):
            return dnfFirst
        case (_?, nil):
            return !dnfFirst
        }
    }
}

private enum DataSolveResultFilter: String, CaseIterable {
    case all
    case solved
    case plusTwo
    case dnf

    var titleKey: LocalizedStringKey {
        switch self {
        case .all: "data.filter.result.all"
        case .solved: "common.solved"
        case .plusTwo: "data.filter.result.plus_two"
        case .dnf: "common.dnf"
        }
    }

    func matches(_ solve: SessionSolveSample) -> Bool {
        guard self != .all else { return true }
        let result = SolveResult(rawValue: solve.resultRaw) ?? .solved
        switch self {
        case .all:
            return true
        case .solved:
            return result == .solved
        case .plusTwo:
            return result == .plusTwo
        case .dnf:
            return result == .dnf
        }
    }
}

private enum DataAverageSortOption: String, CaseIterable {
    case newest
    case oldest
    case fastest
    case slowest

    var titleKey: LocalizedStringKey {
        switch self {
        case .newest: "data.filter.sort.newest"
        case .oldest: "data.filter.sort.oldest"
        case .fastest: "data.filter.sort.fastest"
        case .slowest: "data.filter.sort.slowest"
        }
    }

    func areInIncreasingOrder(_ lhs: AverageListEntry, _ rhs: AverageListEntry) -> Bool {
        switch self {
        case .newest:
            return compareByDate(lhs, rhs, newestFirst: true)
        case .oldest:
            return compareByDate(lhs, rhs, newestFirst: false)
        case .fastest:
            return compareByAverage(lhs, rhs, fastestFirst: true)
        case .slowest:
            return compareByAverage(lhs, rhs, fastestFirst: false)
        }
    }

    private func compareByDate(
        _ lhs: AverageListEntry,
        _ rhs: AverageListEntry,
        newestFirst: Bool
    ) -> Bool {
        if lhs.date == rhs.date {
            return newestFirst ? lhs.position > rhs.position : lhs.position < rhs.position
        }
        return newestFirst ? lhs.date > rhs.date : lhs.date < rhs.date
    }

    private func compareByAverage(
        _ lhs: AverageListEntry,
        _ rhs: AverageListEntry,
        fastestFirst: Bool
    ) -> Bool {
        let lhsValue = lhs.value.flatMap { $0.isFinite ? $0 : nil }
        let rhsValue = rhs.value.flatMap { $0.isFinite ? $0 : nil }

        switch (lhsValue, rhsValue) {
        case let (lhsValue?, rhsValue?):
            if lhsValue == rhsValue {
                return lhs.date > rhs.date
            }
            return fastestFirst ? lhsValue < rhsValue : lhsValue > rhsValue
        case (nil, nil):
            return lhs.date > rhs.date
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        }
    }
}

private enum DataRecordFilterOption: String, CaseIterable {
    case all
    case current
    case best

    var titleKey: LocalizedStringKey {
        switch self {
        case .all: "data.segment.record"
        case .current: "common.current"
        case .best: "common.best"
        }
    }
}

private struct DataTabTrailingToolbarModifier: ViewModifier {
    let segment: DataSegment
    let showsListControls: Bool
    let isSelecting: Bool
    let isFilterActive: Bool
    let isAverageFilterActive: Bool
    let isRecordFilterActive: Bool
    @Binding var sortOption: DataSolveSortOption
    @Binding var resultFilter: DataSolveResultFilter
    @Binding var averageType: AverageListType
    let averageTypes: [AverageListType]
    @Binding var averageSortOption: DataAverageSortOption
    @Binding var recordFilterOption: DataRecordFilterOption
    let languageCode: String
    let isTimeRangeEnabled: Bool
    let isDateRangeEnabled: Bool
    let onSelect: () -> Void
    let onCloseSelection: () -> Void
    let onShowGraph: () -> Void
    let onShowTimeRange: () -> Void
    let onShowDateRange: () -> Void
    let onResetFilters: () -> Void
    let onResetAverageFilters: () -> Void
    let onResetRecordFilters: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.toolbar {
                modernToolbarContent
            }
        } else {
            content.toolbar {
                legacyToolbarContent
            }
        }
    }

    @available(iOS 26.0, *)
    @ToolbarContentBuilder
    private var modernToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            graphButton
            dataFilterButton
        }

        if showsListControls {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            // Replace the bar item itself so the navigation bar owns the transition.
            if isSelecting {
                ToolbarItem(id: "data-selection-close", placement: .topBarTrailing) {
                    Button(action: onCloseSelection) { closeSelectionImage }
                        .accessibilityLabel(Text("common.done"))
                        .accessibilityIdentifier("data-selection-close")
                }
            } else {
                ToolbarItem(id: "data-selection-open", placement: .topBarTrailing) {
                    Button(action: onSelect) { selectTitle }
                        .accessibilityLabel(Text("common.select"))
                        .accessibilityIdentifier("data-selection-open")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var legacyToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            graphButton
            dataFilterButton
            if showsListControls {
                selectionButton
            }
        }
    }

    private var graphButton: some View {
        Button(
            "data.trend.title",
            systemImage: "chart.line.uptrend.xyaxis",
            action: onShowGraph
        )
        .labelStyle(.iconOnly)
        .font(.system(size: 16, weight: .medium))
    }

    private var dataFilterButton: some View {
        Menu {
            activeFilterMenuContent
        } label: {
            Image(systemName: isActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                .font(.system(size: 16, weight: .medium))
        }
        .accessibilityLabel(Text("data.filter.title"))
    }

    @ViewBuilder
    private var activeFilterMenuContent: some View {
        switch segment {
        case .time:
            Section("data.filter.sort") {
                Picker("data.filter.sort", selection: $sortOption) {
                    ForEach(DataSolveSortOption.allCases, id: \.self) { option in
                        Text(option.titleKey).tag(option)
                    }
                }
            }

            Section("data.filter.results") {
                Picker("data.filter.results", selection: $resultFilter) {
                    ForEach(DataSolveResultFilter.allCases, id: \.self) { filter in
                        Text(filter.titleKey).tag(filter)
                    }
                }
            }

            Section("data.filter.title") {
                Button(action: onShowTimeRange) {
                    Label(
                        "data.filter.time_range",
                        systemImage: isTimeRangeEnabled ? "checkmark.circle.fill" : "timer"
                    )
                }
                Button(action: onShowDateRange) {
                    Label(
                        "data.filter.date_range",
                        systemImage: isDateRangeEnabled ? "checkmark.circle.fill" : "calendar"
                    )
                }
            }

            if isFilterActive {
                Divider()
                Button("data.filter.reset", action: onResetFilters)
            }
        case .average:
            Section("data.segment.average") {
                Picker("data.segment.average", selection: $averageType) {
                    ForEach(averageTypes) { type in
                        Text(type.title(languageCode: languageCode)).tag(type)
                    }
                }
            }

            Section("data.filter.sort") {
                Picker("data.filter.sort", selection: $averageSortOption) {
                    ForEach(DataAverageSortOption.allCases, id: \.self) { option in
                        Text(option.titleKey).tag(option)
                    }
                }
            }

            if isAverageFilterActive {
                Divider()
                Button("data.filter.reset", action: onResetAverageFilters)
            }
        case .record:
            Picker("data.filter.title", selection: $recordFilterOption) {
                ForEach(DataRecordFilterOption.allCases, id: \.self) { option in
                    Text(option.titleKey).tag(option)
                }
            }

            if isRecordFilterActive {
                Divider()
                Button("data.filter.reset", action: onResetRecordFilters)
            }
        }
    }

    private var isActiveFilter: Bool {
        switch segment {
        case .time: isFilterActive
        case .average: isAverageFilterActive
        case .record: isRecordFilterActive
        }
    }

    private var selectionButton: some View {
        Button {
            if isSelecting { onCloseSelection() } else { onSelect() }
        } label: {
            if isSelecting { closeSelectionImage } else { selectTitle }
        }
        .accessibilityLabel(Text(isSelecting ? "common.done" : "common.select"))
        .accessibilityIdentifier(isSelecting ? "data-selection-close" : "data-selection-open")
    }

    private var closeSelectionImage: some View {
        Image(systemName: "xmark")
            .font(.system(size: 16, weight: .medium))
    }

    private var selectTitle: some View {
        Text("common.select")
            .font(.system(size: 16, weight: .semibold))
    }
}

private enum DataSolveRangeFilterEditor: String, Identifiable {
    case time
    case date

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .time: "data.filter.time_range"
        case .date: "data.filter.date_range"
        }
    }
}

private struct DataSolveRangeFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let editor: DataSolveRangeFilterEditor
    @Binding var isTimeRangeEnabled: Bool
    @Binding var minimumTime: Double
    @Binding var maximumTime: Double
    @Binding var isDateRangeEnabled: Bool
    @Binding var startDate: Date
    @Binding var endDate: Date
    let solves: [SessionSolveSample]

    private var availableTimeRange: ClosedRange<Double> {
        let values = solves.compactMap(\.adjustedTime)
        let lower = values.min() ?? 0
        let upper = values.max() ?? max(lower + 1, 1)
        return lower...(upper > lower ? upper : lower + 1)
    }

    private var availableDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let lower = calendar.startOfDay(for: solves.map(\.date).min() ?? .now)
        let upper = calendar.startOfDay(for: solves.map(\.date).max() ?? lower)
        return lower...max(lower, upper)
    }

    private var sliderStep: Double {
        let span = availableTimeRange.upperBound - availableTimeRange.lowerBound
        if span > 600 { return 1 }
        if span > 60 { return 0.5 }
        return 0.1
    }

    var body: some View {
        CompatibleNavigationContainer {
            Form {
                if editor == .time {
                    Section {
                        Toggle("data.filter.limit_time", isOn: $isTimeRangeEnabled)

                        if isTimeRangeEnabled {
                            rangeSliderRow(
                                title: "data.filter.minimum",
                                value: minimumTimeBinding
                            )
                            rangeSliderRow(
                                title: "data.filter.maximum",
                                value: maximumTimeBinding
                            )
                        }
                    } footer: {
                        if isTimeRangeEnabled {
                            Text("data.filter.time_range.footer")
                        }
                    }
                } else {
                    Section {
                        Toggle("data.filter.limit_date", isOn: $isDateRangeEnabled)

                        if isDateRangeEnabled {
                            DatePicker(
                                "data.filter.start_date",
                                selection: startDateBinding,
                                in: availableDateRange,
                                displayedComponents: .date
                            )
                            DatePicker(
                                "data.filter.end_date",
                                selection: endDateBinding,
                                in: availableDateRange,
                                displayedComponents: .date
                            )
                        }
                    }
                }
            }
            .compatibleSoftScrollEdgeEffect()
            .navigationTitle(Text(editor.titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("data.filter.reset") {
                        reset()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") {
                        dismiss()
                    }
                }
            }
            .onAppear(perform: normalizeRanges)
        }
    }

    private func rangeSliderRow(title: LocalizedStringKey, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(SolveMetrics.formatTime(value.wrappedValue, decimals: 1))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: availableTimeRange, step: sliderStep)
        }
        .padding(.vertical, 2)
    }

    private var minimumTimeBinding: Binding<Double> {
        Binding(
            get: { minimumTime },
            set: { minimumTime = min($0, maximumTime) }
        )
    }

    private var maximumTimeBinding: Binding<Double> {
        Binding(
            get: { maximumTime },
            set: { maximumTime = max($0, minimumTime) }
        )
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { startDate },
            set: { startDate = min($0, endDate) }
        )
    }

    private var endDateBinding: Binding<Date> {
        Binding(
            get: { endDate },
            set: { endDate = max($0, startDate) }
        )
    }

    private func normalizeRanges() {
        minimumTime = min(max(minimumTime, availableTimeRange.lowerBound), availableTimeRange.upperBound)
        maximumTime = min(max(maximumTime, minimumTime), availableTimeRange.upperBound)
        startDate = min(max(startDate, availableDateRange.lowerBound), availableDateRange.upperBound)
        endDate = min(max(endDate, startDate), availableDateRange.upperBound)
    }

    private func reset() {
        switch editor {
        case .time:
            isTimeRangeEnabled = false
            minimumTime = availableTimeRange.lowerBound
            maximumTime = availableTimeRange.upperBound
        case .date:
            isDateRangeEnabled = false
            startDate = availableDateRange.lowerBound
            endDate = availableDateRange.upperBound
        }
    }
}

struct DataBottomSearchBar: View {
    let languageCode: String
    let searchAction: () -> Void

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            accessoryLabel
        } else {
            searchButton(compact: false)
        }
    }

    @available(iOS 26.0, *)
    private struct AccessoryPlacement<Content: View>: View {
        @Environment(\.tabViewBottomAccessoryPlacement) private var placement
        @ViewBuilder let content: (Bool) -> Content
        var body: some View { content(placement == .inline) }
    }

    @available(iOS 26.0, *)
    private var accessoryLabel: some View {
        AccessoryPlacement { compact in searchButton(compact: compact) }
    }

    private func searchButton(compact: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        return Button(action: searchAction) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                Text(appLocalizedString("data.search.placeholder", languageCode: languageCode))
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, compact ? 0 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(appLocalizedString("data.search.placeholder", languageCode: languageCode)))
        .accessibilityIdentifier("data-bottom-search")
        .contentShape(shape)
    }
}

private struct DataSolveSearchView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.solveTimeAccuracy) private var solveTimeAccuracy
    let sessionID: UUID
    let fallbackPuzzleKey: String?
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var query = ""
    @State private var solves: [SessionSolveSample] = []
    @State private var searchableTextByID: [UUID: String] = [:]
    @State private var selectedSolve: SessionSolveSample?
    @State private var isLoading = true
    @State private var loadTask: Task<Void, Never>?
    @State private var loadGeneration = 0
    @State private var pendingIndexSamples: [SessionSolveSample]?
    @State private var indexTask: Task<Void, Never>?

    private var matchingSolves: [SessionSolveSample] {
        let tokens = normalized(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return solves }

        return solves.filter { solve in
            let haystack = searchableTextByID[solve.id] ?? ""
            return tokens.allSatisfy(haystack.contains)
        }
    }

    private var solvePositionByID: [UUID: Int] {
        Dictionary(
            uniqueKeysWithValues: solves.enumerated().map { index, solve in
                (solve.id, solves.count - index)
            }
        )
    }

    var body: some View {
        let results = isLoading ? [] : matchingSolves
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("data.search.no_results")
                        .font(.headline)
                    Text("data.search.no_results.description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { solve in
                    Button {
                        selectedSolve = solve
                    } label: {
                        searchResultRow(solve)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .compatibleSoftScrollEdgeEffect()
            }
        }
        .navigationTitle(Text("data.search.title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("data.search.placeholder"))
        .sheet(item: $selectedSolve) { solve in
            SolveDetailSheet(
                sample: solve,
                position: solvePositionByID[solve.id],
                fallbackPuzzleKey: fallbackPuzzleKey
            )
                .compatibleLargeSheet()
        }
        .task {
            loadSolves()
        }
        .onDisappear {
            loadTask?.cancel()
            indexTask?.cancel()
            loadGeneration += 1
            pendingIndexSamples = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: solvesDidChangeNotification)) { _ in
            loadSolves()
        }
        .onChange(of: appLanguage) { _ in
            if let pendingIndexSamples { rebuildSearchIndex(for: pendingIndexSamples) }
        }
        .onChange(of: solveTimeAccuracy) { _ in
            if let pendingIndexSamples { rebuildSearchIndex(for: pendingIndexSamples) }
        }
    }

    private func searchResultRow(_ solve: SessionSolveSample) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(SolveMetrics.displayTime(for: solve, decimals: solveTimeAccuracy.decimals))
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()
                Spacer()
                Text(SolveMetrics.displayDate(solve.date, languageCode: appLanguage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !solve.comment.isEmpty {
                Text(solve.comment)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if !solve.scramble.isEmpty {
                Text(solve.scramble)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func loadSolves() {
        isLoading = solves.isEmpty
        loadTask?.cancel(); loadGeneration += 1
        indexTask?.cancel()
        pendingIndexSamples = nil
        let generation = loadGeneration, reader = SessionSolveSnapshotReader(viewContext: modelContext)
        loadTask = Task {
            let snapshots = (try? await reader.load(sessionID: sessionID)) ?? []
            guard !Task.isCancelled, loadGeneration == generation else { return }
            pendingIndexSamples = snapshots
            rebuildSearchIndex(for: snapshots)
        }
    }

    private func rebuildSearchIndex(for samples: [SessionSolveSample]) {
        indexTask?.cancel()
        let language = appLanguage, decimals = solveTimeAccuracy.decimals, generation = loadGeneration
        indexTask = Task {
            let worker = Task.detached(priority: .userInitiated) {
                try DataSolveSearchIndex.make(samples, language: language, decimals: decimals)
            }
            let index = await withTaskCancellationHandler(operation: { try? await worker.value },
                onCancel: { worker.cancel() })
            guard !Task.isCancelled, generation == loadGeneration, let index else { return }
            solves = samples
            searchableTextByID = index
            isLoading = false
        }
    }

    private func normalized(_ value: String) -> String {
        DataSolveSearchIndex.normalized(value, locale: appLocale(for: appLanguage))
    }
}

nonisolated enum DataSolveSearchIndex {
    static func make(_ solves: [SessionSolveSample], language: String, decimals: Int) throws -> [UUID: String] {
        let locale = appLocale(for: language)
        let displayDateFormatter = DateFormatter()
        displayDateFormatter.locale = locale
        displayDateFormatter.dateStyle = .medium
        displayDateFormatter.timeStyle = .short
        let isoDateFormatter = ISO8601DateFormatter()

        let solved = appLocalizedString("common.solved", languageCode: language)
        let dnf = appLocalizedString("common.dnf", languageCode: language)
        var events: [String: String] = [:]
        var index: [UUID: String] = [:]
        index.reserveCapacity(solves.count)
        for (offset, solve) in solves.enumerated() {
            if offset.isMultiple(of: 64) { try Task.checkCancellation() }
            let eventText: String
            if let cached = events[solve.eventRawValue] {
                eventText = cached
            } else {
                eventText = PuzzleEvent(rawValue: solve.eventRawValue).map {
                    appLocalizedString($0.localizationKey, languageCode: language)
                } ?? solve.eventRawValue
                events[solve.eventRawValue] = eventText
            }
            index[solve.id] = searchableText(for: solve, displayDateFormatter: displayDateFormatter,
                isoDateFormatter: isoDateFormatter, locale: locale, decimals: decimals,
                solved: solved, dnf: dnf, eventText: eventText)
        }
        return index
    }

    private static func searchableText(
        for solve: SessionSolveSample,
        displayDateFormatter: DateFormatter,
        isoDateFormatter: ISO8601DateFormatter, locale: Locale, decimals: Int,
        solved: String, dnf: String, eventText: String
    ) -> String {
        let result = SolveResult(rawValue: solve.resultRaw) ?? .solved
        let resultText: String
        switch result {
        case .solved:
            resultText = solved
        case .plusTwo:
            resultText = "+2"
        case .dnf:
            resultText = dnf
        }

        let isoDate = isoDateFormatter.string(from: solve.date)
        let rawSeconds = String(format: "%.3f", solve.time)
        return normalized([
            SolveMetrics.displayTime(for: solve, decimals: decimals),
            rawSeconds,
            solve.comment,
            solve.scramble,
            displayDateFormatter.string(from: solve.date),
            isoDate,
            resultText,
            solve.eventRawValue,
            eventText
        ].joined(separator: " "), locale: locale)
    }

    static func normalized(_ value: String, locale: Locale) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            .lowercased()
    }
}

private enum RecordHistoryMetric: String, CaseIterable, Identifiable, Sendable {
    case single
    case mo3
    case ao5
    case ao12
    case ao50
    case ao100
    case ao500
    case ao1000
    case ao5000
    case ao10000

    nonisolated var id: String { rawValue }

    nonisolated var recordMetric: RecordAverageMetric? {
        guard self != .single else { return nil }
        return RecordAverageMetric.defaultMetrics.first { $0.title == rawValue }
    }

    nonisolated var requiredSolveCount: Int { recordMetric?.solveCount ?? 1 }

    nonisolated func title(languageCode: String) -> String {
        if self == .single {
            return dataTabLocalizedString(for: "data.best_time", languageCode: languageCode)
        }
        return recordMetric?.localizedTitle(languageCode: languageCode) ?? rawValue.uppercased()
    }
}

private enum RecordDetailScope: Sendable {
    case current
    case best
}

private struct AverageDetailMetric: Sendable {
    let rawValue: String
    let solveCount: Int
    let trimmingCount: Int

    nonisolated init(_ type: AverageListType) {
        rawValue = type.rawValue
        solveCount = type.solveCount
        trimmingCount = type.trimmingCount
    }

    nonisolated init(_ metric: RecordAverageMetric) {
        rawValue = metric.title
        solveCount = metric.solveCount
        trimmingCount = metric.trimCount
    }

    nonisolated func title(languageCode: String) -> String {
        RecordAverageMetric.defaultMetrics
            .first { $0.title == rawValue }?
            .localizedTitle(languageCode: languageCode) ?? rawValue.uppercased()
    }
}

private struct RecordAverageDetailSelection: Identifiable, Sendable {
    let entry: AverageListEntry
    let metric: AverageDetailMetric

    nonisolated var id: String { "\(metric.rawValue)-\(entry.position)" }
}

private struct RecordHistoryEntry: Identifiable, Sendable {
    let id: String
    let metric: RecordHistoryMetric
    let value: Double
    let improvement: Double?
    let date: Date
    let displayedPosition: Int
    let averageEntry: AverageListEntry?
    let solve: SessionSolveSample?
}

private struct RecordHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.solveTimeAccuracy) private var solveTimeAccuracy
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    let solves: [SessionSolveSample]
    let solvePositionByID: [UUID: Int]
    let personalBestSingleSolveIDs: Set<UUID>
    let fallbackPuzzleKey: String?

    @State private var selectedMetric: RecordHistoryMetric = .single
    @State private var entries: [RecordHistoryEntry] = []
    @State private var isLoading = true
    @State private var selectedEntry: RecordHistoryEntry?

    private var availableMetrics: [RecordHistoryMetric] {
        RecordHistoryMetric.allCases.filter { solves.count >= $0.requiredSolveCount }
    }

    var body: some View {
        CompatibleNavigationContainer {
            List {
                Section {
                    Picker("data.record_history.metric", selection: $selectedMetric) {
                        ForEach(availableMetrics) { metric in
                            Text(metric.title(languageCode: appLanguage)).tag(metric)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section(selectedMetric.title(languageCode: appLanguage)) {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if entries.isEmpty {
                        Text("data.record_history.empty")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(entries) { entry in
                            historyRow(entry)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .compatibleSoftScrollEdgeEffect()
            .navigationTitle(Text("data.record_history"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("common.done"))
                }
            }
            .task(id: selectedMetric) {
                await loadHistory()
            }
            .sheet(item: $selectedEntry) { entry in
                if let solve = entry.solve {
                    SolveDetailSheet(
                        sample: solve,
                        position: solvePositionByID[solve.id],
                        fallbackPuzzleKey: fallbackPuzzleKey
                    )
                    .compatibleLargeSheet()
                } else if let averageEntry = entry.averageEntry,
                          let recordMetric = entry.metric.recordMetric {
                    AverageDetailSheet(
                        entry: averageEntry,
                        metric: AverageDetailMetric(recordMetric),
                        personalBestSingleSolveIDs: personalBestSingleSolveIDs
                    )
                    .compatibleLargeSheet()
                }
            }
        }
    }

    @ViewBuilder
    private func historyRow(_ entry: RecordHistoryEntry) -> some View {
        let canOpenDetail = entry.solve != nil || entry.averageEntry != nil
        Button {
            if canOpenDetail {
                selectedEntry = entry
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(
                            entry.metric == .single
                                ? SolveMetrics.formatTime(entry.value, decimals: solveTimeAccuracy.decimals)
                                : SolveMetrics.formatAverage(entry.value, decimals: solveTimeAccuracy.decimals)
                        )
                            .font(.system(size: 19, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)

                        if let improvement = entry.improvement {
                            Text("−\(SolveMetrics.formatTime(improvement, decimals: solveTimeAccuracy.decimals))")
                                .font(.system(size: 13, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.green)
                        }
                    }

                    Text(SolveMetrics.displayDate(entry.date, languageCode: appLanguage))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text("#\(entry.displayedPosition)")
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                if canOpenDetail {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canOpenDetail)
    }

    private func loadHistory() async {
        isLoading = true
        let samples = solves
        let metric = selectedMetric
        let positions = solvePositionByID
        let history = await Task.detached(priority: .userInitiated) {
            Self.buildHistory(metric: metric, solves: samples, solvePositionByID: positions)
        }.value
        guard !Task.isCancelled, selectedMetric == metric else { return }
        entries = history
        isLoading = false
    }

    nonisolated private static func buildHistory(
        metric: RecordHistoryMetric,
        solves: [SessionSolveSample],
        solvePositionByID: [UUID: Int]
    ) -> [RecordHistoryEntry] {
        if metric == .single {
            var bestValue: Double?
            var history: [RecordHistoryEntry] = []

            for solve in solves.reversed() {
                guard let value = solve.adjustedTime,
                      bestValue == nil || value < bestValue! else { continue }
                history.append(
                    RecordHistoryEntry(
                        id: "single-\(solve.id.uuidString)",
                        metric: metric,
                        value: value,
                        improvement: bestValue.map { $0 - value },
                        date: solve.date,
                        displayedPosition: solvePositionByID[solve.id] ?? 0,
                        averageEntry: nil,
                        solve: solve
                    )
                )
                bestValue = value
            }
            return history.reversed()
        }

        guard let recordMetric = metric.recordMetric else { return [] }
        let evaluation = DataTabComputation.evaluateRecordMetric(
            metric: recordMetric,
            solves: solves,
            includeWindowValues: true
        )
        let totalWindows = evaluation.windowValues.count
        var bestValue: Double?
        var history: [RecordHistoryEntry] = []

        for index in evaluation.windowValues.indices.reversed() {
            guard let value = evaluation.windowValues[index], value.isFinite,
                  bestValue == nil || value < bestValue! else { continue }
            let averagePosition = totalWindows - index
            let windowSolves = Array(solves[index..<(index + recordMetric.solveCount)])
            let averageEntry = AverageListEntry(
                position: averagePosition,
                date: solves[index].date,
                value: value,
                isPersonalBest: true,
                solves: windowSolves
            )
            history.append(
                RecordHistoryEntry(
                    id: "\(metric.rawValue)-\(averagePosition)",
                    metric: metric,
                    value: value,
                    improvement: bestValue.map { $0 - value },
                    date: solves[index].date,
                    displayedPosition: averagePosition + recordMetric.solveCount - 1,
                    averageEntry: averageEntry,
                    solve: nil
                )
            )
            bestValue = value
        }

        return history.reversed()
    }
}

#if DEBUG
@MainActor final class SolveNotesTestProbe {
    var edit: ((String) -> Void)?
    var done: (() -> Void)?
    var isFocused: (() -> Bool)?
}
private struct SolveNotesTestProbeKey: EnvironmentKey {
    static let defaultValue: SolveNotesTestProbe? = nil
}
private extension EnvironmentValues {
    var solveNotesTestProbe: SolveNotesTestProbe? {
        get { self[SolveNotesTestProbeKey.self] }
        set { self[SolveNotesTestProbeKey.self] = newValue }
    }
}
enum SolveDetailAcceptance {
    static func view(for solve: Solve, notesProbe: SolveNotesTestProbe? = nil) -> some View {
        SolveDetailSheet(sample: SessionSolveSample(id: solve.id, date: solve.date, time: solve.time,
            resultRaw: solve.resultRaw, scramble: solve.scramble, comment: solve.comment,
            eventRawValue: solve.event, inputSourceRaw: solve.inputSourceRaw), position: nil, fallbackPuzzleKey: nil)
            .environment(\.solveNotesTestProbe, notesProbe)
    }
}
#endif

private struct SolveNotesScrollDismissal: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 16.0, *) { content.scrollDismissesKeyboard(.interactively) }
        else { content }
    }
}

private struct SolveDetailSheet: View {
    #if DEBUG
    @Environment(\.solveNotesTestProbe) private var notesProbe
    #endif
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.solveTimeAccuracy) private var solveTimeAccuracy
    private let sample: SessionSolveSample
    private let position: Int?
    private let fallbackPuzzleKey: String?
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var showingScrambleDetail = false
    @State private var isShowingDeleteSolveAlert = false
    @FocusState private var notesAreFocused: Bool
    @State private var selectedPenalty: SolveResult
    @State private var commentText: String
    @State private var sharedSolveImage: SharedImageItem?
    @State private var isRenderingShareImage = false
    @State private var shareErrorMessage: String?
    @State private var showingShareOptions = false
    @State private var shareContentKind: SolveShareContentKind = .solveCard
    @State private var shareBackground: SolveShareBackground = .light
    @State private var reconstruction: SolveReconstruction?

    init(sample: SessionSolveSample, position: Int?, fallbackPuzzleKey: String?) {
        self.sample = sample
        self.position = position
        self.fallbackPuzzleKey = fallbackPuzzleKey
        _commentText = State(initialValue: sample.comment)
        _selectedPenalty = State(initialValue: SolveResult(rawValue: sample.resultRaw) ?? .solved)
    }

    private var navigationTitle: String {
        let title = appLocalizedString("common.solve", languageCode: appLanguage)
        guard let position else { return title }
        return "\(title) #\(position)"
    }

    private var puzzleKey: String? {
        if let event = PuzzleEvent.fromSolveEvent(sample.eventRawValue) {
            return event.scrambleDiagramPuzzleKey
        }
        return nil
    }

    private var shouldShowScrambleDetail: Bool {
        let scramble = sample.scramble
        return !scramble.isEmpty && (scramble.count > 90 || scramble.contains("\n"))
    }

    private var canShowScrambleDiagram: Bool {
        puzzleKey != nil && !sample.scramble.isEmpty
    }

    var body: some View {
        CompatibleNavigationContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(SolveMetrics.displayDate(sample.date, languageCode: appLanguage))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(SolveMetrics.displayTime(for: sample, decimals: solveTimeAccuracy.decimals))
                            .font(.system(size: 44, weight: .semibold))
                            .monospacedDigit()
                        HStack(spacing: 8) {
                            if let event = PuzzleEvent.fromSolveEvent(sample.eventRawValue),
                               let glyph = CompetitionEventIconFont.glyph(for: event.cubingEventID) {
                                CompetitionEventGlyph(glyph: glyph,
                                    eventName: appLocalizedString(event.localizationKey, languageCode: appLanguage), size: 17, color: .secondary)
                            }
                            Text(appLocalizedString(sample.inputSource?.localizationKey ?? "solve.method.unknown", languageCode: appLanguage))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    scrambleSection

                    if canShowScrambleDiagram, let puzzleKey {
                        let aspectRatio = ScrambleDiagramView.diagramAspectRatio(for: puzzleKey)
                        ScrambleDiagramView(
                            puzzleKey: puzzleKey,
                            scramble: sample.scramble,
                            exportAppearance: .solveDetail(.light)
                        )
                            .aspectRatio(aspectRatio, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                    }

                    if let reconstruction {
                        reconstructionSection(reconstruction)
                    }

                    commentSection

                    actionSection
                }
                .padding(20)
            }
            .modifier(SolveNotesScrollDismissal())
            .compatibleSoftScrollEdgeEffect()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("common.done", action: finishEditingNotes)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingShareOptions = true
                    } label: {
                        if isRenderingShareImage {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(isRenderingShareImage)
                    .accessibilityLabel("Share this solve")
                    .popover(
                        isPresented: $showingShareOptions,
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .top
                    ) {
                        solveShareOptions
                    }
                    .alert(
                        "Unable to Share Solve",
                        isPresented: Binding(
                            get: { shareErrorMessage != nil },
                            set: { if !$0 { shareErrorMessage = nil } }
                        )
                    ) {
                        Button("OK", role: .cancel) { shareErrorMessage = nil }
                    } message: {
                        Text(shareErrorMessage ?? "")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveComment()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("common.done"))
                }
            }
            .sheet(item: $sharedSolveImage) { item in
                SystemShareSheet(items: [item.image])
            }
            #if DEBUG
            .onAppear {
                notesProbe?.edit = { commentText = $0; notesAreFocused = true }
                notesProbe?.done = finishEditingNotes
                notesProbe?.isFocused = { notesAreFocused }
            }
            #endif
            .task { loadReconstruction() }
            .onDisappear(perform: saveComment)
            .alert("delete.solve.title", isPresented: $isShowingDeleteSolveAlert) {
                Button("common.delete", role: .destructive) {
                    deleteSolve()
                }
                Button("common.cancel", role: .cancel) { }
            } message: {
                Text("delete.solve.message")
            }
            .sheet(isPresented: $showingScrambleDetail) {
                CompatibleNavigationContainer {
                    ScrollView {
                        Text(sample.scramble)
                            .font(.system(size: 17, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(24)
                            .selectableContent()
                    }
                    .compatibleSoftScrollEdgeEffect()
                    .navigationTitle(appLocalizedString("common.scramble", languageCode: appLanguage))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showingScrambleDetail = false
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .accessibilityLabel(Text("common.done"))
                        }
                    }
                }
                .compatibleLargeSheet()
            }
        }
    }

    private func reconstructionSection(_ reconstruction: SolveReconstruction) -> some View {
        Group {
            if reconstruction.isReplayable {
                NavigationLink {
                    ReconstructionReplayView(reconstruction: reconstruction, actualSolveDuration: sample.time)
                } label: {
                    replayRow(reconstruction)
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Replay unavailable")
                        .font(.headline)
                    Text("Stored cube state or moves cannot be reconstructed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
        }
    }

    private func replayRow(_ reconstruction: SolveReconstruction) -> some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Replay")
                        .font(.headline)
                    Text(replaySubtitle(reconstruction))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func replaySubtitle(_ reconstruction: SolveReconstruction) -> String {
        let moveCount = "\(reconstruction.moves.count) moves"
        if let tps = reconstruction.turnsPerSecond(actualDuration: sample.time) {
            return "\(moveCount) · \(String(format: "%.2f", tps)) TPS"
        }
        return reconstruction.completeness == .complete ? moveCount : "\(moveCount) · Incomplete"
    }

    private func loadReconstruction() {
        guard let solve = try? modelContext.fetchSolve(with: sample.id) else { return }
        reconstruction = solve.reconstruction
    }

    @ViewBuilder
    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("solve.comment")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            if #available(iOS 16.0, *) {
                TextField("solve.comment.placeholder", text: $commentText, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .focused($notesAreFocused)
            } else {
                TextEditor(text: $commentText)
                    .focused($notesAreFocused)
                    .frame(minHeight: 88)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.secondary.opacity(0.25), lineWidth: 1)
                    }
            }
        }
    }

    private var scrambleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("common.scramble")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                if shouldShowScrambleDetail {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(sample.scramble.isEmpty ? "-" : sample.scramble)
                .font(.system(size: 18, weight: .semibold))
                .monospacedDigit()
                .lineLimit(shouldShowScrambleDetail ? 3 : nil)
                .fixedSize(horizontal: false, vertical: !shouldShowScrambleDetail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            finishEditingNotes()
            if shouldShowScrambleDetail {
                showingScrambleDetail = true
            }
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            SolvePenaltySelector(selected: selectedPenalty, language: appLanguage, select: updateResult)
                .frame(maxWidth: .infinity)

            SmartCubeNativeAction(title: appLocalizedString("common.delete", languageCode: appLanguage),
                tint: .systemRed, enabled: true, identifier: "solve-detail-delete",
                perform: { isShowingDeleteSolveAlert = true }, isLarge: true)
                .frame(height: 50)
        }
    }

    private func updateResult(_ result: SolveResult) {
        guard let solve = try? modelContext.fetchSolve(with: sample.id) else {
            dismiss()
            return
        }

        selectedPenalty = result
        notesAreFocused = false
        solve.result = result
        solve.comment = normalizedComment
        try? modelContext.save()
        NotificationCenter.default.post(name: solvesDidChangeNotification, object: nil)
        dismiss()
    }

    private var normalizedComment: String {
        commentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func finishEditingNotes() {
        notesAreFocused = false
        saveComment()
    }

    private func saveComment() {
        guard let solve = try? modelContext.fetchSolve(with: sample.id),
              normalizedComment != solve.comment else { return }
        solve.comment = normalizedComment
        try? modelContext.save()
        NotificationCenter.default.post(name: solvesDidChangeNotification, object: nil)
    }

    private func deleteSolve() {
        if let solve = try? modelContext.fetchSolve(with: sample.id) {
            solve.comment = ""
            modelContext.delete(solve)
            try? modelContext.save()
            NotificationCenter.default.post(name: solvesDidChangeNotification, object: nil)
        }
        dismiss()
    }

    @ViewBuilder
    private var solveShareOptions: some View {
        let options = VStack(alignment: .leading, spacing: 18) {
            Text("Share Solve")
                .font(.headline)

            VStack(alignment: .leading, spacing: 7) {
                Text("Content")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Content", selection: $shareContentKind) {
                    ForEach(availableShareContentKinds) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Background")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Background", selection: $shareBackground) {
                    ForEach(SolveShareBackground.allCases) { background in
                        Text(background.title).tag(background)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Button {
                shareSolve(contentKind: shareContentKind, background: shareBackground)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .compatibleProminentButtonFromIOS16(tint: .blue)
            .disabled(isRenderingShareImage)
        }
        .padding(18)
        .frame(width: 310)

        if #available(iOS 16.4, *) {
            options.presentationCompactAdaptation(.popover)
        } else {
            options
        }
    }

    private var availableShareContentKinds: [SolveShareContentKind] {
        canShowScrambleDiagram
            ? SolveShareContentKind.allCases
            : [.solveCard]
    }

    private func shareSolve(
        contentKind: SolveShareContentKind,
        background: SolveShareBackground
    ) {
        guard !isRenderingShareImage else { return }
        showingShareOptions = false
        isRenderingShareImage = true
        Task {
            defer { isRenderingShareImage = false }
            do {
                let image = try await SolveShareRenderer.render(
                    sample: sample,
                    position: position,
                    puzzleKey: puzzleKey,
                    comment: commentText,
                    decimals: solveTimeAccuracy.decimals,
                    contentKind: contentKind,
                    background: background
                )
                sharedSolveImage = SharedImageItem(image: image)
            } catch {
                shareErrorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }
}


private struct AverageDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.solveTimeAccuracy) private var solveTimeAccuracy
    let entry: AverageListEntry
    let metric: AverageDetailMetric
    let personalBestSingleSolveIDs: Set<UUID>
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var selectedSolve: SessionSolveSample?

    private var orderedSolves: [SessionSolveSample] {
        Array(entry.solves.reversed())
    }

    private var bestSolve: SessionSolveSample? {
        guard let bestSolveID = entry.bestSolveID else { return nil }
        return entry.solves.first { $0.id == bestSolveID }
    }

    private var worstSolve: SessionSolveSample? {
        guard let worstSolveID = entry.worstSolveID else { return nil }
        return entry.solves.first { $0.id == worstSolveID }
    }

    private var trimmedSolveIDs: Set<UUID> {
        let trimmingCount = metric.trimmingCount
        guard trimmingCount > 0 else { return [] }

        let fastestFiniteIDs = entry.solves
            .compactMap { solve -> (UUID, Double)? in
                guard let adjustedTime = solve.adjustedTime else { return nil }
                return (solve.id, adjustedTime)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(trimmingCount)
            .map(\.0)

        let slowestIDs = entry.solves
            .map { solve -> (UUID, Double) in
                (solve.id, solve.adjustedTime ?? .infinity)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(trimmingCount)
            .map(\.0)

        return Set(fastestFiniteIDs + slowestIDs)
    }

    private var endingSolvePosition: Int {
        entry.position + metric.solveCount - 1
    }

    private var navigationTitle: String {
        "\(metric.title(languageCode: appLanguage)) #\(endingSolvePosition)"
    }

    private var standardDeviation: Double? {
        SolveMetrics.standardDeviation(
            from: entry.solves,
            trimmingCount: metric.trimmingCount
        )
    }

    private var standardDeviationLabel: String {
        let value = standardDeviation.map {
            SolveMetrics.formatTime($0, decimals: solveTimeAccuracy.decimals)
        } ?? "-"
        return "(σ = \(value))"
    }

    private var solvePositionByID: [UUID: Int] {
        Dictionary(
            uniqueKeysWithValues: orderedSolves.enumerated().map { index, solve in
                (solve.id, entry.position + index)
            }
        )
    }

    var body: some View {
        CompatibleNavigationContainer {
            List {
                Section {
                    averageSummaryRow(
                        title: metric.title(languageCode: appLanguage),
                        secondaryTitle: standardDeviationLabel,
                        value: SolveMetrics.formatAverage(entry.value, decimals: solveTimeAccuracy.decimals),
                        isPrimary: true
                    )
                    averageSummaryRow(
                        title: dataTabLocalizedString(for: "data.best_time", languageCode: appLanguage),
                        value: bestSolve.map { SolveMetrics.displayTime(for: $0, decimals: solveTimeAccuracy.decimals) } ?? appLocalizedString("common.not_available", languageCode: appLanguage)
                    )
                    averageSummaryRow(
                        title: dataTabLocalizedString(for: "data.worst_time", languageCode: appLanguage),
                        value: worstSolve.map { SolveMetrics.displayTime(for: $0, decimals: solveTimeAccuracy.decimals) } ?? appLocalizedString("common.not_available", languageCode: appLanguage)
                    )
                }

                Section(NumeralPresentation.formatLocalizedInteger(
                    entry.solves.count,
                    template: dataTabLocalizedString(for: "common.solves_format", languageCode: appLanguage)
                )) {
                    ForEach(Array(orderedSolves.enumerated()), id: \.element.id) { index, solve in
                        averageSolveRow(solve, position: entry.position + index)
                    }
                }
            }
            .compatibleSoftScrollEdgeEffect()
            .listStyle(.insetGrouped)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("common.done"))
                }
            }
            .sheet(item: $selectedSolve) { solve in
                SolveDetailSheet(
                    sample: solve,
                    position: solvePositionByID[solve.id],
                    fallbackPuzzleKey: nil
                )
                .compatibleLargeSheet()
            }
        }
    }

    private func averageSummaryRow(
        title: String,
        secondaryTitle: String? = nil,
        value: String,
        isPrimary: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)

                if let secondaryTitle {
                    Text(secondaryTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(value)
                .font(.system(size: isPrimary ? 26 : 18, weight: isPrimary ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(isPrimary && entry.isPersonalBest ? WCAResultEmphasis.personalBest.color : .primary)
                .layoutPriority(1)
        }
        .padding(.vertical, isPrimary ? 6 : 3)
    }

    private func averageSolveRow(_ solve: SessionSolveSample, position: Int) -> some View {
        let timeText = SolveMetrics.displayTime(for: solve, decimals: solveTimeAccuracy.decimals)
        let displayText = trimmedSolveIDs.contains(solve.id) ? "(\(timeText))" : timeText

        return Button {
            selectedSolve = solve
        } label: {
            HStack(spacing: 12) {
                Text("#\(position)")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayText)
                        .font(.system(size: 21, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(personalBestSingleSolveIDs.contains(solve.id) ? WCAResultEmphasis.personalBest.color : .primary)

                    Text(SolveMetrics.displayDate(solve.date, languageCode: appLanguage))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(solve.scramble.isEmpty ? "-" : solve.scramble)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


private struct SessionManagementToolbarConfigurator: UIViewControllerRepresentable {
    let isEditing: Bool
    let canRename: Bool
    let languageCode: String
    let onAdd: () -> Void
    let onRename: () -> Void
    let onEdit: () -> Void
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        context.coordinator.configuration = self
        if #available(iOS 26.0, *),
           context.coordinator.updateRenameIfMounted(in: viewController, context: context) {
            return
        }
        DispatchQueue.main.async {
            context.coordinator.apply(to: viewController)
        }
    }

    static func dismantleUIViewController(_ viewController: UIViewController, coordinator: Coordinator) {
        coordinator.clear(from: viewController)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(configuration: self)
    }

    final class Coordinator: NSObject {
        private struct ToolbarState: Equatable {
            let isEditing: Bool
            let canRename: Bool
            let languageCode: String
        }

        var configuration: SessionManagementToolbarConfigurator
        private var appliedState: ToolbarState?
        private weak var installedRename: UIBarButtonItem?

        init(configuration: SessionManagementToolbarConfigurator) {
            self.configuration = configuration
        }

        @available(iOS 26.0, *)
        func updateRenameIfMounted(in viewController: UIViewController, context: Context) -> Bool {
            guard configuration.isEditing, appliedState?.isEditing == true,
                  appliedState?.languageCode == configuration.languageCode,
                  let bar = viewController.navigationController?.navigationBar,
                  let rename = installedRename,
                  bar.topItem?.rightBarButtonItems?.contains(where: { $0 === rename }) == true else { return false }
            let enabled = configuration.canRename
            appliedState = ToolbarState(isEditing: true, canRename: enabled, languageCode: configuration.languageCode)
            guard rename.isEnabled != enabled else { return true }
            if bar.window != nil, !context.transaction.disablesAnimations,
               !context.environment.accessibilityReduceMotion, !UIAccessibility.isReduceMotionEnabled {
                updateSessionBarItem(rename, enabled: enabled, in: bar) { context.animate(changes: $0) }
            } else {
                rename.isEnabled = enabled
            }
            return true
        }

        func apply(to viewController: UIViewController) {
            guard let navigationItem = navigationItem(for: viewController) else { return }

            let state = ToolbarState(
                isEditing: configuration.isEditing,
                canRename: configuration.canRename,
                languageCode: configuration.languageCode
            )
            let shouldAnimate = appliedState != nil && appliedState?.isEditing != state.isEditing

            guard appliedState != state else { return }
            appliedState = state

            let secondaryItem: UIBarButtonItem
            if configuration.isEditing {
                secondaryItem = UIBarButtonItem(
                    title: appLocalizedString("common.rename", languageCode: configuration.languageCode),
                    style: .plain,
                    target: self,
                    action: #selector(renameTapped)
                )
                secondaryItem.isEnabled = configuration.canRename
                installedRename = secondaryItem
            } else {
                installedRename = nil
                secondaryItem = UIBarButtonItem(
                    image: UIImage(systemName: "plus"),
                    style: .plain,
                    target: self,
                    action: #selector(addTapped)
                )
            }

            let primaryItem = UIBarButtonItem(
                title: appLocalizedString(configuration.isEditing ? "common.done" : "common.edit", languageCode: configuration.languageCode),
                style: .plain,
                target: self,
                action: configuration.isEditing ? #selector(doneTapped) : #selector(editTapped)
            )
            SessionNativeActionStyle.apply(to: primaryItem, tint: .systemBlue)

            if #available(iOS 26.0, *),
               let bar = viewController.navigationController?.navigationBar, bar.topItem === navigationItem {
                // The app can choose a direction independently of the system language.
                let direction: UISemanticContentAttribute = appUsesRightToLeftLayout(for: state.languageCode)
                    ? .forceRightToLeft : .forceLeftToRight
                if bar.semanticContentAttribute != direction { bar.semanticContentAttribute = direction }
            }
            if #available(iOS 27.2, *) {
                navigationItem.titleAlignment = state.isEditing ? .leading : .center
            } else if #available(iOS 26.0, *) {
                // This sheet has no back button, search controller or center items.
                // Keep the native inline title in both modes rather than replacing it with a titleView.
                navigationItem.style = state.isEditing ? .editor : .navigator
            }
            navigationItem.setRightBarButtonItems([primaryItem, secondaryItem], animated: shouldAnimate)
        }

        func clear(from viewController: UIViewController) {
            appliedState = nil
            installedRename = nil
            navigationItem(for: viewController)?.setRightBarButtonItems(nil, animated: false)
        }

        private func navigationItem(for viewController: UIViewController) -> UINavigationItem? {
            if let navigationController = viewController.navigationController {
                return navigationController.topViewController?.navigationItem
            }
            if let navigationController = viewController.parent?.navigationController {
                return navigationController.topViewController?.navigationItem
            }
            var parent = viewController.parent
            while let current = parent {
                if let navigationController = current as? UINavigationController {
                    return navigationController.topViewController?.navigationItem
                }
                if let navigationController = current.navigationController {
                    return navigationController.topViewController?.navigationItem
                }
                parent = current.parent
            }
            return viewController.parent?.navigationItem
        }

        @objc private func addTapped() {
            configuration.onAdd()
        }

        @objc private func renameTapped() {
            configuration.onRename()
        }

        @objc private func editTapped() {
            configuration.onEdit()
        }

        @objc private func doneTapped() {
            configuration.onDone()
        }
    }
}

private struct SessionDeletionRequest: Identifiable {
    let id = UUID()
    let sessionIDs: Set<UUID>
    let nextSelectedSessionID: UUID?
    let isMultiple: Bool
}

private struct SessionManagementSheet: View {
    #if DEBUG
    @Environment(\.appPerformanceProbe) private var performanceProbe
    #endif
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Session.createdAt, ascending: true)],
        animation: .default
    )
    private var sessions: FetchedResults<Session>

    @Binding var selectedSessionID: String
    @State private var isEditing = false
    @State private var selectedSessionIDs: Set<UUID> = []
    @State private var renamingSession: Session?
    @State private var renameSessionName: String = ""
    @State private var isShowingDeselectAllLabel = false
    @State private var selectAllButtonTextOpacity = 1.0
    @State private var recentlyDeselectedSessionID: String?
    @State private var sessionSwitchGeneration = 0
    @State private var isDeletingSessions = false
    @State private var deleteProgressCurrent = 0
    @State private var deleteProgressTotal = 1
    @State private var pendingSessionDeletion: SessionDeletionRequest?
    @State private var solveCounts: [UUID: Int] = [:]
    private let animation = Animation.spring(response: 0.3, dampingFraction: 0.86)

    private var sessionNavigationTitle: Text {
        if #available(iOS 26.0, *) { return Text("common.session") }
        return isEditing ? Text("") : Text("common.session")
    }

    var body: some View {
        CompatibleNavigationContainer {
            Group {
                if isDeletingSessions {
                    Color.clear
                } else {
                    sessionListViewport(List {
                        ForEach(sessions) { session in
                            sessionRow(session)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isEditing {
                                    withAnimation(animation) {
                                        toggleSelection(for: session)
                                    }
                                } else {
                                    selectSession(session)
                                }
                            }
                            .contextMenu {
                                if !isEditing {
                                    Button {
                                        beginRenaming(session)
                                    } label: {
                                        Label("common.rename", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        startDeletingSessions([session])
                                    } label: {
                                        Label("common.delete", systemImage: "trash")
                                    }
                                    .disabled(sessions.count <= 1)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: sessions.count > 1) {
                                if !isEditing {
                                    Button(role: .destructive) {
                                        startDeletingSessions([session])
                                    } label: {
                                        Label("common.delete", systemImage: "trash")
                                    }
                                    .disabled(sessions.count <= 1)
                                }
                            }
                        }
                    }
                    .compatibleSoftScrollEdgeEffect()
                    .listStyle(.plain))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(sessionNavigationTitle)
            .animation(animation, value: isEditing)
            .animation(animation, value: selectedSessionIDs)
            .animation(animation, value: selectedSessionID)
            .alert(item: $pendingSessionDeletion) { request in
                Alert(
                    title: Text(request.isMultiple ? "delete.sessions.title" : "delete.session.title"),
                    message: Text(request.isMultiple ? "delete.sessions.message" : "delete.session.message"),
                    primaryButton: .destructive(Text("common.delete")) {
                        performSessionDeletion(request)
                    },
                    secondaryButton: .cancel()
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                    }
                }

                ToolbarItem(placement: .principal) {
                    if #unavailable(iOS 26.0), isEditing {
                        Text("common.session")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 8)
                    }
                }

            }
            .background {
                SessionManagementToolbarConfigurator(
                    isEditing: isEditing,
                    canRename: selectedSessionIDs.count == 1,
                    languageCode: appLanguage,
                    onAdd: addSession,
                    onRename: renameSelectedSession,
                    onEdit: beginEditing,
                    onDone: finishEditing
                )
                .frame(width: 0, height: 0)
            }
            .safeAreaInset(edge: .bottom) {
                if isEditing {
                    bottomEditBar
                }
            }
            .overlay {
                if isDeletingSessions {
                    ZStack {
                        Color.black.opacity(0.12)
                            .ignoresSafeArea()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("data.deleting_sessions")
                                .font(.system(size: 16, weight: .semibold))

                            ProgressView(
                                value: Double(deleteProgressCurrent),
                                total: Double(max(deleteProgressTotal, 1))
                            )
                            .progressViewStyle(.linear)
                            .tint(.blue)

                            Text("\(deleteProgressCurrent)/\(deleteProgressTotal)")
                                .font(.system(size: 13, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .frame(maxWidth: 280, alignment: .leading)
                        .compatibleGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .animation(.easeInOut(duration: 0.16), value: deleteProgressCurrent)
                    }
                    .transition(.opacity)
                }
            }
            .onAppear {
                isShowingDeselectAllLabel = allSessionsSelected
                selectAllButtonTextOpacity = 1
                #if DEBUG
                performanceProbe?.dataChooseSession = { id in
                    if let session = sessions.first(where: { $0.id == id }) { selectSession(session) }
                }
                performanceProbe?.dataCloseSessionSheet = { dismiss() }
                performanceProbe?.dataSessionSelection = { selectedSessionID }
                #endif
            }
            #if DEBUG
            .onDisappear {
                performanceProbe?.dataChooseSession = nil
                performanceProbe?.dataCloseSessionSheet = nil
                performanceProbe?.dataSessionSelection = nil
            }
            #endif
            .task(id: sessions.map(\.id)) {
                let ids = sessions.map(\.id)
                let reader = SessionSolveSnapshotReader(viewContext: modelContext)
                if let counts = try? await reader.counts(sessionIDs: ids), !Task.isCancelled {
                    solveCounts = counts
                }
            }
            .onChange(of: allSessionsSelected) { newValue in
                animateSelectAllButtonLabel(to: newValue)
            }
            .alert("common.rename", isPresented: renameAlertBinding) {
                TextField("common.rename", text: $renameSessionName)
                Button("common.cancel", role: .cancel) {
                    clearRenameState()
                }
                Button("common.done") {
                    applySessionRename()
                }
            }
        }
    }

    private func addSession() {
        let newSession = Session(name: "Session \(sessions.count + 1)", context: modelContext)
        try? modelContext.save()
        selectedSessionID = newSession.id.uuidString
    }

    private var allSessionsSelected: Bool {
        !sessions.isEmpty && selectedSessionIDs.count == sessions.count
    }

    @ViewBuilder
    private func sessionRow(_ session: Session) -> some View {
        let isSelected = selectedSessionID == session.id.uuidString
        let solveCountPhase: SessionSolveCountPhase = {
            if isSelected {
                return .selected
            } else if recentlyDeselectedSessionID == session.id.uuidString {
                return .deselecting
            } else {
                return .normal
            }
        }()

        HStack(spacing: 10) {
            sessionSelectionIndicator(for: session)

            Text(session.name)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()

            AnimatedSessionSolveCountText(
                text: solveCounts[session.id].map(sessionSolveCountText) ?? "…",
                phase: solveCountPhase
            )

        }
        .overlay(alignment: .trailing) {
            sessionCurrentIndicator(for: session)
        }
    }

    @ViewBuilder
    private func sessionSelectionIndicator(for session: Session) -> some View {
        if isEditing {
            let isSelected = selectedSessionIDs.contains(session.id)
            SolveSelectionCheckmark(selected: isSelected, size: 20, weight: .semibold)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    )
                )
        }
    }

    @ViewBuilder
    private func sessionCurrentIndicator(for session: Session) -> some View {
        AnimatedSessionCheckmark(
            isSelected: selectedSessionID == session.id.uuidString
        )
        .frame(width: 18, alignment: .trailing)
    }

    @ViewBuilder
    private func sessionListViewport<Content: View>(_ list: Content) -> some View {
        if #available(iOS 26.0, *) {
            GeometryReader { geometry in
                // Keep the scroll surface beneath the glass; inset only the rows and indicators.
                list
                    .contentMargins(.bottom, geometry.safeAreaInsets.bottom, for: .scrollContent)
                    .contentMargins(.bottom, geometry.safeAreaInsets.bottom, for: .scrollIndicators)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
        } else {
            list
        }
    }

    private var bottomEditBar: some View {
        HStack(alignment: .bottom) {
            Button {
                withAnimation(animation) {
                    if allSessionsSelected {
                        selectedSessionIDs.removeAll()
                    } else {
                        selectedSessionIDs = Set(sessions.map(\.id))
                    }
                }
            } label: {
                Text(isShowingDeselectAllLabel ? "common.deselect_all" : "common.select_all")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .opacity(selectAllButtonTextOpacity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(.capsule)
                    .compatibleGlassFromIOS16(in: Capsule())
                    .animation(.easeInOut(duration: 0.22), value: isShowingDeselectAllLabel)
            }
            .buttonStyle(.plain)

            Spacer()

            sessionDeleteButton
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, -8)
        .transition(.opacity)
    }

    private var sessionDeleteLabel: some View {
        Text("common.delete")
            .font(.system(size: 17, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    @ViewBuilder
    private var sessionDeleteButton: some View {
        let enabled = !selectedSessionIDs.isEmpty && !isDeletingSessions
        if #available(iOS 26.0, *) {
            // Let the existing label and padding size the slot, not the embedded toolbar.
            sessionDeleteLabel.hidden().accessibilityHidden(true)
                .overlay {
                    DataProminentDeleteItem(title: appLocalizedString("common.delete", languageCode: appLanguage),
                        enabled: enabled, identifier: "sessions-edit-delete", perform: startDeletingSelectedSessions)
                }
        } else {
            Button(action: startDeletingSelectedSessions) {
                sessionDeleteLabel.compatibleTintedGlassFromIOS16(.red, in: Capsule())
            }
            .tint(.red)
            .buttonStyle(.plain)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.48)
        }
    }

    private func sessionSolveCountText(_ count: Int) -> String {
        NumeralPresentation.formatLocalizedInteger(
            count,
            template: dataTabLocalizedString(for: "common.solves_format", languageCode: appLanguage)
        )
    }

    private func toggleSelection(for session: Session) {
        if selectedSessionIDs.contains(session.id) {
            selectedSessionIDs.remove(session.id)
        } else {
            selectedSessionIDs.insert(session.id)
        }
    }

    private func animateSelectAllButtonLabel(to showDeselect: Bool) {
        guard isShowingDeselectAllLabel != showDeselect else { return }

        withAnimation(.easeOut(duration: 0.16)) {
            selectAllButtonTextOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            isShowingDeselectAllLabel = showDeselect
            withAnimation(.easeIn(duration: 0.2)) {
                selectAllButtonTextOpacity = 1
            }
        }
    }

    private func selectSession(_ session: Session) {
        let newID = session.id.uuidString
        guard selectedSessionID != newID else { return }

        sessionSwitchGeneration += 1
        let generation = sessionSwitchGeneration
        recentlyDeselectedSessionID = selectedSessionID.isEmpty ? nil : selectedSessionID

        withAnimation(animation) {
            selectedSessionID = newID
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard generation == sessionSwitchGeneration else { return }
            recentlyDeselectedSessionID = nil
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingSession != nil },
            set: { newValue in
                if !newValue {
                    clearRenameState()
                }
            }
        )
    }

    private func clearRenameState() {
        renamingSession = nil
        renameSessionName = ""
    }

    private func beginRenaming(_ session: Session) {
        renamingSession = session
        renameSessionName = session.name
    }

    private func beginEditing() {
        withAnimation(animation) {
            isEditing = true
        }
    }

    private func finishEditing() {
        withAnimation(animation) {
            isEditing = false
            selectedSessionIDs.removeAll()
        }
    }

    private func renameSelectedSession() {
        guard selectedSessionIDs.count == 1,
              let selectedID = selectedSessionIDs.first,
              let session = sessions.first(where: { $0.id == selectedID }) else { return }
        beginRenaming(session)
    }

    private func applySessionRename() {
        let trimmed = renameSessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let renamingSession, !trimmed.isEmpty else {
            clearRenameState()
            return
        }

        renamingSession.name = trimmed
        try? modelContext.save()
        clearRenameState()
    }

    private func startDeletingSelectedSessions() {
        let toDelete = sessions.filter { selectedSessionIDs.contains($0.id) }
        guard !toDelete.isEmpty else { return }
        startDeletingSessions(toDelete)
    }

    private func startDeletingSessions(_ sessionsToDelete: [Session]) {
        guard !isDeletingSessions else { return }

        let sessionIDsToDelete = Set(sessionsToDelete.map(\.id))
        let remainingSessions = sessions.filter { !sessionIDsToDelete.contains($0.id) }
        let nextSelectedSessionID = remainingSessions.first?.id

        let deletingSelected = sessionsToDelete.contains {
            $0.id.uuidString == selectedSessionID
        }

        pendingSessionDeletion = SessionDeletionRequest(
            sessionIDs: sessionIDsToDelete,
            nextSelectedSessionID: deletingSelected ? nextSelectedSessionID : UUID(uuidString: selectedSessionID),
            isMultiple: sessionsToDelete.count > 1
        )
    }

    private func performSessionDeletion(_ request: SessionDeletionRequest) {
        isDeletingSessions = true
        deleteProgressCurrent = 0
        deleteProgressTotal = max(request.sessionIDs.count, 1)
        isEditing = false
        selectedSessionIDs.removeAll()
        if let nextSelectedSessionID = request.nextSelectedSessionID {
            selectedSessionID = nextSelectedSessionID.uuidString
        }
        NotificationCenter.default.post(name: sessionsWillDeleteNotification, object: nil)

        deleteSessions(request.sessionIDs, nextSelectedSessionID: request.nextSelectedSessionID)
    }

    private func deleteSessions(_ sessionIDsToDelete: Set<UUID>, nextSelectedSessionID: UUID?) {
        let sessionsToDelete = sessions
            .filter { sessionIDsToDelete.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }

        let total = max(sessionsToDelete.count + (nextSelectedSessionID == nil ? 1 : 0) + 1, 1)
        deleteProgressCurrent = 0
        deleteProgressTotal = total

        for session in sessionsToDelete {
            session.solves?.forEach { $0.comment = "" }
            modelContext.delete(session)
            deleteProgressCurrent = min(deleteProgressCurrent + 1, total - 1)
        }

        let resolvedSelectedSessionID: UUID
        if let nextSelectedSessionID {
            resolvedSelectedSessionID = nextSelectedSessionID
        } else {
            let fallbackSession = Session(name: "Session", context: modelContext)
            resolvedSelectedSessionID = fallbackSession.id
            deleteProgressCurrent = min(deleteProgressCurrent + 1, total - 1)
        }

        try? modelContext.save()
        selectedSessionID = resolvedSelectedSessionID.uuidString
        deleteProgressCurrent = total
        isDeletingSessions = false
        deleteProgressCurrent = 0
        deleteProgressTotal = 1
    }
}

private struct AnimatedSessionCheckmark: View {
    let isSelected: Bool
    @State private var showsAnimatedCheckmark = false
    @State private var showsStaticCheckmark = false
    @State private var animationGeneration = 0

    var body: some View {
        ZStack {
            if showsStaticCheckmark {
                checkmark
            }

            if showsAnimatedCheckmark {
                checkmark
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            syncState(for: isSelected, animate: false)
        }
        .onChange(of: isSelected) { newValue in
            syncState(for: newValue, animate: true)
        }
    }

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.blue)
    }

    private func syncState(for isSelected: Bool, animate: Bool) {
        animationGeneration += 1
        let generation = animationGeneration

        guard isSelected else {
            withTransaction(Transaction(animation: nil)) {
                showsAnimatedCheckmark = false
                showsStaticCheckmark = false
            }
            return
        }

        guard animate else {
            withTransaction(Transaction(animation: nil)) {
                showsAnimatedCheckmark = false
                showsStaticCheckmark = true
            }
            return
        }

        withTransaction(Transaction(animation: nil)) {
            showsStaticCheckmark = false
            showsAnimatedCheckmark = false
        }

        withAnimation(.easeOut(duration: 0.28)) {
            showsAnimatedCheckmark = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard generation == animationGeneration else { return }

            withTransaction(Transaction(animation: nil)) {
                showsAnimatedCheckmark = false
                showsStaticCheckmark = true
            }
        }
    }
}

private struct AnimatedSessionSolveCountText: View {
    let text: String
    let phase: SessionSolveCountPhase

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .offset(x: phase == .selected ? -24 : 0)
            .animation(animation(for: phase), value: phase)
    }

    private func animation(for phase: SessionSolveCountPhase) -> Animation {
        switch phase {
        case .selected:
            return .spring(response: 0.3, dampingFraction: 0.75)
        case .deselecting:
            return .easeOut(duration: 0.3)
        case .normal:
            return .default
        }
    }
}

struct TimeTrendSheet: View {
    @Environment(\.solveTimeAccuracy) private var solveTimeAccuracy
    let appLanguage: String

    @State private var trendMode: TrendMode = .histogram
    @State private var lineHistory: SessionPerformanceHistory?
    @State private var selectedHistogramX: Double?

    private let trend: SessionSolveTrend
    private let solves: [SessionSolveSample]
    private let histogramDomain: ClosedRange<Double>
    private let best: Double
    private let mean: Double
    private let median: Double

    init(solves: [SessionSolveSample], appLanguage: String, initialMode: TrendMode = .histogram) {
        self.appLanguage = appLanguage
        self.solves = solves
        let snapshot = SessionSolveTrend(solves: solves)
        trend = snapshot
        let values = snapshot.points.map(\.time)
        histogramDomain = (snapshot.bins.first?.lower ?? 0)...(snapshot.bins.last?.upper ?? 1)
        let sorted = values.sorted()
        best = sorted.first ?? 0
        mean = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        median = sorted.isEmpty ? 0 : sorted.count.isMultiple(of: 2)
            ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2 : sorted[sorted.count / 2]
        _trendMode = State(initialValue: initialMode)
    }

    private var solvePoints: [SessionSolveTrend.Point] { trend.points }
    private var histogramBins: [SessionSolveTrend.Bin] { trend.bins }

    private var selectedHistogramBin: SessionSolveTrend.Bin? {
        guard let selectedHistogramX else { return nil }
        return histogramBins.first { selectedHistogramX >= $0.lower && selectedHistogramX < $0.upper }
    }

    var body: some View {
        CompatibleNavigationContainer {
            ScrollView {
            VStack(spacing: 20) {
                Picker("data.trend.mode", selection: $trendMode) {
                    Text("data.trend.histogram").tag(TrendMode.histogram)
                    Text("data.trend.graph").tag(TrendMode.graph)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if trendMode == .graph && !solves.isEmpty {
                    lineChart
                } else if solvePoints.isEmpty {
                    Text("data.no_solves")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    chartSummary
                    HStack(spacing: 0) {
                        statistic("common.best", value: best)
                        Divider()
                        statistic("data.trend.mean", value: mean)
                        Divider()
                        statistic("data.trend.median", value: median)
                    }.frame(height: 52)
                    histogramChart
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                    Text(String(format: appLocalizedString("data.trend.solve_count", languageCode: appLanguage), solvePoints.count))
                        .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(appLocalizedString("data.trend.title", languageCode: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func statistic(_ key: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(appLocalizedString(key, languageCode: appLanguage)).font(.caption).foregroundStyle(.secondary)
            Text(SolveMetrics.formatTime(value, decimals: solveTimeAccuracy.decimals))
                .font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, key == "common.best" ? 0 : 16)
    }

    private var chartSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let bin = selectedHistogramBin {
                Text("\(SolveMetrics.formatTime(bin.lower, decimals: solveTimeAccuracy.decimals)) - \(SolveMetrics.formatTime(bin.upper, decimals: solveTimeAccuracy.decimals))")
                    .font(.title3.weight(.semibold)).monospacedDigit()
                Text(String(format: appLocalizedString("data.trend.solve_count", languageCode: appLanguage), bin.count))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(SolveMetrics.formatTime(median, decimals: solveTimeAccuracy.decimals))
                    .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(appLocalizedString("data.trend.median", languageCode: appLanguage))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var lineChart: some View {
        if #available(iOS 16.0, *) {
            if let lineHistory {
                SessionPerformanceLineChart(history: lineHistory, language: appLanguage)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 242)
                    .task {
                        let worker = Task.detached(priority: .userInitiated) { [solves] in
                            try SessionPerformanceHistory(solves)
                        }
                        let snapshot = await withTaskCancellationHandler(operation: { try? await worker.value },
                            onCancel: { worker.cancel() })
                        if !Task.isCancelled { lineHistory = snapshot }
                    }
            }
        } else {
            chartUnavailableView
        }
    }

    @ViewBuilder
    private var histogramChart: some View {
        if #available(iOS 16.0, *) {
            if #available(iOS 17.0, *) {
                histogramChartContent
                    .chartXSelection(value: $selectedHistogramX)
            } else {
                histogramChartContent
            }
        } else {
            chartUnavailableView
        }
    }

    @available(iOS 16.0, *)
    private var histogramChartContent: some View {
        let selected = selectedHistogramBin
        return Chart {
            ForEach(histogramBins) { bin in
            RectangleMark(
                xStart: .value("Start", bin.lower + (bin.upper - bin.lower) * 0.025),
                xEnd: .value("End", bin.upper - (bin.upper - bin.lower) * 0.025),
                yStart: .value("Zero", 0),
                yEnd: .value("Count", bin.count)
            )
            .foregroundStyle(Color.accentColor.opacity(selected == nil || selected?.id == bin.id ? 0.85 : 0.25))
            .cornerRadius(5)
            }

            if let bin = selected {
                let center = (bin.lower + bin.upper) / 2
                RuleMark(x: .value("Selected Bin", center))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                AxisValueLabel { if let count = value.as(Int.self) { Text(NumeralPresentation.formatInteger(count)).font(.caption2) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel { if let seconds = value.as(Double.self) { Text(SolveMetrics.formatTime(seconds, decimals: 1)).font(.caption2).monospacedDigit() } }
            }
        }
        .chartXScale(domain: histogramDomain)
        .chartYScale(domain: 0...max(1, (histogramBins.map(\.count).max() ?? 0) + 1))
        .frame(height: 260)
    }

    private var chartUnavailableView: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Charts require iOS 16 or newer.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(height: 330)
        .frame(maxWidth: .infinity)
    }
}

enum TrendMode: String, CaseIterable {
    case histogram
    case graph
}
#endif

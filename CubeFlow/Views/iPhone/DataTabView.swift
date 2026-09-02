import SwiftUI
import CoreData
import Charts
import UIKit

#if os(iOS)
private let sessionsWillDeleteNotification = Notification.Name("CubeFlowSessionsWillDelete")
private let solvesDidChangeNotification = Notification.Name("CubeFlowSolvesDidChange")

@MainActor
struct DataTabView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.solveTimeAccuracy) private var solveTimeAccuracy

    private let usesSystemBottomAccessory: Bool
    @Binding private var isBottomAccessoryVisible: Bool
    @Binding private var searchRequestID: Int

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
    @State private var isSelecting = false
    @State private var selectedSolveIDs: Set<UUID> = []
    @State private var showingSessionSheet = false
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
    @State private var recordComputationGeneration = 0
    @State private var averageComputationGeneration = 0
    @State private var isShowingDeleteSelectedSolvesAlert = false

    init(
        usesSystemBottomAccessory: Bool = false,
        isBottomAccessoryVisible: Binding<Bool> = .constant(false),
        searchRequestID: Binding<Int> = .constant(0)
    ) {
        self.usesSystemBottomAccessory = usesSystemBottomAccessory
        _isBottomAccessoryVisible = isBottomAccessoryVisible
        _searchRequestID = searchRequestID
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

    private var personalBestSingleSolveIDs: Set<UUID> {
        var bestTime: Double?
        var recordIDs = Set<UUID>()

        for solve in sessionSolves.reversed() {
            guard let adjustedTime = solve.adjustedTime else { continue }
            if bestTime == nil || adjustedTime < bestTime! {
                bestTime = adjustedTime
                recordIDs.insert(solve.id)
            }
        }

        return recordIDs
    }

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
        }
        .sheet(isPresented: $showingSessionSheet) {
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
            if selectedSegment == .time && isSelecting && !selectedSolveIDs.isEmpty {
                selectionActionBar
            } else if selectedSegment == .average && !availableAverageTypes.isEmpty {
                averageTypeBar
            } else if !usesSystemBottomAccessory && shouldShowBottomAccessory {
                DataBottomSearchBar(languageCode: appLanguage, usesContainerGlass: true) {
                    isShowingSearch = true
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .task {
            ensureSessionExists()
            refreshFilteredSessionSolves()
        }
        .onChange(of: selectedSegment) { newValue in
            if newValue != .time {
                isSelecting = false
                selectedSolveIDs.removeAll()
            }
            if newValue == .average {
                syncSelectedAverageType()
                ensureAverageEntriesSnapshot()
            }
            if newValue == .record {
                refreshRecordSnapshot()
            }
            updateBottomAccessoryVisibility()
        }
        .onChange(of: isSelecting) { _ in
            updateBottomAccessoryVisibility()
        }
        .onChange(of: selectedSessionID) { _ in
            isSelecting = false
            selectedSolveIDs.removeAll()
            resetRangeFilters()
            refreshFilteredSessionSolves()
        }
        .onChange(of: selectedSessionSolveCount) { _ in
            refreshFilteredSessionSolves()
        }
        .onChange(of: solveSortOptionRawValue) { _ in
            updateVisibleSessionSolves()
        }
        .onChange(of: solveResultFilterRawValue) { _ in
            updateVisibleSessionSolves()
        }
        .onChange(of: isTimeRangeFilterEnabled) { _ in updateVisibleSessionSolves() }
        .onChange(of: minimumTimeFilter) { _ in updateVisibleSessionSolves() }
        .onChange(of: maximumTimeFilter) { _ in updateVisibleSessionSolves() }
        .onChange(of: isDateRangeFilterEnabled) { _ in updateVisibleSessionSolves() }
        .onChange(of: startDateFilter) { _ in updateVisibleSessionSolves() }
        .onChange(of: endDateFilter) { _ in updateVisibleSessionSolves() }
        .onReceive(NotificationCenter.default.publisher(for: solvesDidChangeNotification)) { _ in
            refreshFilteredSessionSolves()
        }
        .onChange(of: selectedAverageType) { _ in
            if !isLoadingSessionSnapshot {
                ensureAverageEntriesSnapshot()
            }
        }
        .onChange(of: appLanguage) { _ in
            recordSnapshotKey = nil
            if selectedSegment == .record {
                refreshRecordSnapshot()
            }
        }
        .onChange(of: solveTimeAccuracy) { _ in
            recordSnapshotKey = nil
            if selectedSegment == .record {
                refreshRecordSnapshot()
            }
        }
        .onChange(of: searchRequestID) { _ in
            guard usesSystemBottomAccessory, shouldShowBottomAccessory else { return }
            isShowingSearch = true
        }
        .onAppear(perform: updateBottomAccessoryVisibility)
        .onDisappear {
            if usesSystemBottomAccessory {
                isBottomAccessoryVisible = false
            }
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

    private func beginSelecting() {
        withAnimation(.snappy(duration: 0.2, extraBounce: 0)) {
            isSelecting = true
        }
    }

    private func endSelecting() {
        withAnimation(.snappy(duration: 0.2, extraBounce: 0)) {
            isSelecting = false
            selectedSolveIDs.removeAll()
        }
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
                List {
                    Section(selectedSession?.name ?? "") {
                        ForEach(visibleSessionSolves) { solve in
                            solveRow(
                                for: solve,
                                position: solvePositionByID[solve.id] ?? 0
                            )
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .compatibleSoftScrollEdgeEffect()
            }
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
                    .foregroundStyle(entry.isPersonalBest ? .orange : .primary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func solveRow(for solve: SessionSolveSample, position: Int) -> some View {
        Button {
            if isSelecting {
                toggleSelection(for: solve)
            } else {
                solveDetailSample = solve
            }
        } label: {
            HStack(spacing: 12) {
                Text("#\(position)")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 6) {
                    Text(SolveMetrics.displayTime(for: solve, decimals: solveTimeAccuracy.decimals))
                        .font(.system(size: 28, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(personalBestSingleSolveIDs.contains(solve.id) ? .orange : .primary)

                    Text(SolveMetrics.displayDate(solve.date, languageCode: appLanguage))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)

                    if solve.scramble.isEmpty {
                        Text("data.scramble_empty")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        HStack(spacing: 0) {
                            Text("data.scramble_prefix")
                            Text(solve.scramble)
                        }
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }

                Spacer()

                if isSelecting {
                    Image(systemName: selectedSolveIDs.contains(solve.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(selectedSolveIDs.contains(solve.id) ? .blue : .secondary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var selectionActionBar: some View {
        HStack {
            Button("common.select_all") {
                selectedSolveIDs = Set(visibleSessionSolves.map(\.id))
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .compatibleGlassFromIOS16(in: Capsule())

            Spacer()

            Button(role: .destructive) {
                isShowingDeleteSelectedSolvesAlert = true
            } label: {
                    Text("common.delete")
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
            .compatibleGlassFromIOS16(in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
        if selectedSolveIDs.contains(solve.id) {
            selectedSolveIDs.remove(solve.id)
        } else {
            selectedSolveIDs.insert(solve.id)
        }
    }

    private func deleteSelectedSolves() {
        let deletedIDs = selectedSolveIDs
        for solveID in selectedSolveIDs {
            if let solve = fetchSolve(with: solveID) {
                solve.comment = ""
                modelContext.delete(solve)
            }
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
        solveDetailSample = sessionSolves
            .compactMap { solve -> (SessionSolveSample, Double)? in
                guard let value = solve.adjustedTime else { return nil }
                return (solve, value)
            }
            .min { $0.1 < $1.1 }?.0
    }

    private func showWorstSingle() {
        solveDetailSample = sessionSolves
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
        guard let selectedSession else {
            filteredSessionSolves = []
            visibleSessionSolves = []
            solvePositionByID = [:]
            recordSnapshotKey = nil
            isLoadingSessionSnapshot = false
            updateBottomAccessoryVisibility()
            return
        }

        let persistenceController = PersistenceController.shared
        let sessionID = selectedSession.id
        let generation = sessionSnapshotGeneration + 1
        sessionSnapshotGeneration = generation
        isLoadingSessionSnapshot = true

        Task.detached(priority: .userInitiated) {
            let context = persistenceController.newBackgroundContext()
            let solves = (try? context.fetchSolves(forSessionID: sessionID, ascending: false)) ?? []
            let snapshots = solves.map { solve in
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

            await MainActor.run {
                guard generation == sessionSnapshotGeneration else { return }
                filteredSessionSolves = snapshots
                initializeRangeFiltersIfNeeded(from: snapshots)
                updateVisibleSessionSolves()
                isLoadingSessionSnapshot = false
                updateBottomAccessoryVisibility()
                syncSelectedAverageType()
                prewarmRecordSnapshotIfNeeded()
                ensureAverageEntriesSnapshot()
                if selectedSegment == .record {
                    refreshRecordSnapshot()
                }
            }
        }
    }

    private func updateVisibleSessionSolves() {
        solvePositionByID = Dictionary(
            uniqueKeysWithValues: filteredSessionSolves.enumerated().map { index, solve in
                (solve.id, filteredSessionSolves.count - index)
            }
        )

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
        let sortOption = DataSolveSortOption(rawValue: solveSortOptionRawValue) ?? .newest
        visibleSessionSolves = matchingSolves.sorted(by: sortOption.areInIncreasingOrder)
    }

    private var shouldShowBottomAccessory: Bool {
        selectedSegment == .time && !filteredSessionSolves.isEmpty && !isSelecting
    }

    private func updateBottomAccessoryVisibility() {
        guard usesSystemBottomAccessory else { return }
        withAnimation(.smooth(duration: 0.22)) {
            isBottomAccessoryVisible = shouldShowBottomAccessory
        }
    }

    private func initializeRangeFiltersIfNeeded(from solves: [SessionSolveSample]) {
        if let minimum = solves.compactMap(\.adjustedTime).min(),
           let maximum = solves.compactMap(\.adjustedTime).max(),
           !isTimeRangeFilterEnabled {
            minimumTimeFilter = minimum
            maximumTimeFilter = maximum
        }

        if let earliest = solves.map(\.date).min(),
           let latest = solves.map(\.date).max(),
           !isDateRangeFilterEnabled {
            startDateFilter = earliest
            endDateFilter = latest
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
        initializeRangeFiltersIfNeeded(from: filteredSessionSolves)
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

    private func refreshRecordSnapshot(showLoading: Bool) {
        guard let snapshotKey = currentSessionSnapshotKey else {
            recordSnapshot = .empty
            recordSnapshotKey = nil
            isComputingRecordSnapshot = false
            return
        }

        if recordSnapshotKey == snapshotKey {
            isComputingRecordSnapshot = false
            return
        }

        let samples = sessionSolves
        let notAvailable = appLocalizedString("common.not_available", languageCode: appLanguage)
        let languageCode = appLanguage
        let generation = recordComputationGeneration + 1
        recordComputationGeneration = generation
        if showLoading {
            isComputingRecordSnapshot = true
        }

        Task.detached(priority: showLoading ? .userInitiated : .utility) {
            let snapshot = DataTabComputation.buildRecordSnapshotData(
                from: samples,
                notAvailable: notAvailable,
                languageCode: languageCode,
                timeDecimals: snapshotKey.timeDecimals
            )

            await MainActor.run {
                guard generation == recordComputationGeneration else { return }
                recordSnapshot = snapshot
                recordSnapshotKey = snapshotKey
                if showLoading || selectedSegment == .record {
                    isComputingRecordSnapshot = false
                }
            }
        }
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
                guard generation == averageComputationGeneration else { return }
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

            ToolbarItem(placement: .topBarTrailing) {
                selectionButton
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

    @ViewBuilder
    private var selectionButton: some View {
        if isSelecting {
            Button {
                onCloseSelection()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
            }
            .accessibilityLabel(Text("common.done"))
        } else {
            Button {
                onSelect()
            } label: {
                Text("common.select")
                    .font(.system(size: 16, weight: .semibold))
            }
        }
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
    let usesContainerGlass: Bool
    let searchAction: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        Button(action: searchAction) {
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
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .background(shape.fill(.black.opacity(0.001)))
        .contentShape(shape)
        .modifier(DataBottomSearchBarGlassModifier(isEnabled: usesContainerGlass, shape: shape))
    }
}

private struct DataBottomSearchBarGlassModifier: ViewModifier {
    let isEnabled: Bool
    let shape: RoundedRectangle

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.compatibleGlass(in: shape)
        } else {
            content
        }
    }
}

private struct DataSolveSearchView: View {
    @Environment(\.solveTimeAccuracy) private var solveTimeAccuracy
    let sessionID: UUID
    let fallbackPuzzleKey: String?
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var query = ""
    @State private var solves: [SessionSolveSample] = []
    @State private var searchableTextByID: [UUID: String] = [:]
    @State private var selectedSolve: SessionSolveSample?
    @State private var isLoading = true

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
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if matchingSolves.isEmpty {
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
                List(matchingSolves) { solve in
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
        .onReceive(NotificationCenter.default.publisher(for: solvesDidChangeNotification)) { _ in
            loadSolves()
        }
        .onChange(of: appLanguage) { _ in
            searchableTextByID = makeSearchIndex(for: solves)
        }
        .onChange(of: solveTimeAccuracy) { _ in
            searchableTextByID = makeSearchIndex(for: solves)
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
        let persistenceController = PersistenceController.shared
        let selectedSessionID = sessionID

        Task.detached(priority: .userInitiated) {
            let context = persistenceController.newBackgroundContext()
            let fetched = (try? context.fetchSolves(forSessionID: selectedSessionID, ascending: false)) ?? []
            let snapshots = fetched.map {
                SessionSolveSample(
                    id: $0.id,
                    date: $0.date,
                    time: $0.time,
                    resultRaw: $0.resultRaw,
                    scramble: $0.scramble,
                    comment: $0.comment,
                    eventRawValue: $0.event
                )
            }

            await MainActor.run {
                solves = snapshots
                searchableTextByID = makeSearchIndex(for: snapshots)
                isLoading = false
            }
        }
    }

    private func makeSearchIndex(for solves: [SessionSolveSample]) -> [UUID: String] {
        let displayDateFormatter = DateFormatter()
        displayDateFormatter.locale = appLocale(for: appLanguage)
        displayDateFormatter.dateStyle = .medium
        displayDateFormatter.timeStyle = .short
        let isoDateFormatter = ISO8601DateFormatter()

        return Dictionary(uniqueKeysWithValues: solves.map { solve in
            (
                solve.id,
                searchableText(
                    for: solve,
                    displayDateFormatter: displayDateFormatter,
                    isoDateFormatter: isoDateFormatter
                )
            )
        })
    }

    private func searchableText(
        for solve: SessionSolveSample,
        displayDateFormatter: DateFormatter,
        isoDateFormatter: ISO8601DateFormatter
    ) -> String {
        let result = SolveResult(rawValue: solve.resultRaw) ?? .solved
        let resultText: String
        switch result {
        case .solved:
            resultText = appLocalizedString("common.solved", languageCode: appLanguage)
        case .plusTwo:
            resultText = "+2"
        case .dnf:
            resultText = appLocalizedString("common.dnf", languageCode: appLanguage)
        }

        let eventText = PuzzleEvent(rawValue: solve.eventRawValue).map {
            appLocalizedString($0.localizationKey, languageCode: appLanguage)
        } ?? solve.eventRawValue
        let isoDate = isoDateFormatter.string(from: solve.date)
        let rawSeconds = String(format: "%.3f", solve.time)
        return normalized([
            SolveMetrics.displayTime(for: solve, decimals: solveTimeAccuracy.decimals),
            rawSeconds,
            solve.comment,
            solve.scramble,
            displayDateFormatter.string(from: solve.date),
            isoDate,
            resultText,
            solve.eventRawValue,
            eventText
        ].joined(separator: " "))
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: appLocale(for: appLanguage))
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

private struct SolveDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.solveTimeAccuracy) private var solveTimeAccuracy
    private let sample: SessionSolveSample
    private let position: Int?
    private let fallbackPuzzleKey: String?
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var showingScrambleDetail = false
    @State private var isShowingDeleteSolveAlert = false
    @State private var commentText: String
    @State private var sharedSolveImage: SharedImageItem?
    @State private var isRenderingShareImage = false
    @State private var shareErrorMessage: String?
    @State private var showingShareOptions = false
    @State private var shareContentKind: SolveShareContentKind = .solveCard
    @State private var shareBackground: SolveShareBackground = .light

    init(sample: SessionSolveSample, position: Int?, fallbackPuzzleKey: String?) {
        self.sample = sample
        self.position = position
        self.fallbackPuzzleKey = fallbackPuzzleKey
        _commentText = State(initialValue: sample.comment)
    }

    private var navigationTitle: String {
        let title = appLocalizedString("common.solve", languageCode: appLanguage)
        guard let position else { return title }
        return "\(title) #\(position)"
    }

    private var puzzleKey: String? {
        if let event = PuzzleEvent(rawValue: sample.eventRawValue) {
            return event.scrambleDiagramPuzzleKey
        }
        return fallbackPuzzleKey
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

                    commentSection

                    actionSection
                }
                .padding(20)
            }
            .compatibleSoftScrollEdgeEffect()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            } else {
                TextEditor(text: $commentText)
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
            if shouldShowScrambleDetail {
                showingScrambleDetail = true
            }
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button("common.dnf") {
                    updateResult(.dnf)
                }
                .compatibleProminentButtonFromIOS16(tint: .blue)

                Button("+2") {
                    updateResult(.plusTwo)
                }
                .compatibleProminentButtonFromIOS16(tint: .blue)

                Button("common.solved") {
                    updateResult(.solved)
                }
                .compatibleProminentButtonFromIOS16(tint: .blue)
            }
            .controlSize(.large)

            Button {
                isShowingDeleteSolveAlert = true
            } label: {
                Text("common.delete")
                    .frame(maxWidth: .infinity)
            }
            .compatibleProminentButtonFromIOS16(tint: .red)
            .controlSize(.large)
        }
    }

    private func updateResult(_ result: SolveResult) {
        guard let solve = try? modelContext.fetchSolve(with: sample.id) else {
            dismiss()
            return
        }

        solve.result = result
        solve.comment = normalizedComment
        try? modelContext.save()
        NotificationCenter.default.post(name: solvesDidChangeNotification, object: nil)
        dismiss()
    }

    private var normalizedComment: String {
        commentText.trimmingCharacters(in: .whitespacesAndNewlines)
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
                .foregroundStyle(isPrimary && entry.isPersonalBest ? .orange : .primary)
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
                        .foregroundStyle(personalBestSingleSolveIDs.contains(solve.id) ? .orange : .primary)

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

        init(configuration: SessionManagementToolbarConfigurator) {
            self.configuration = configuration
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
            } else {
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
            primaryItem.tintColor = .systemBlue
            if #available(iOS 26.0, *) {
                primaryItem.style = .prominent
            } else {
                primaryItem.style = .done
            }

            navigationItem.setRightBarButtonItems([primaryItem, secondaryItem], animated: shouldAnimate)
        }

        func clear(from viewController: UIViewController) {
            appliedState = nil
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
    private let animation = Animation.spring(response: 0.3, dampingFraction: 0.86)

    var body: some View {
        CompatibleNavigationContainer {
            Group {
                if isDeletingSessions {
                    Color.clear
                } else {
                    List {
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
                    .listStyle(.plain)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
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
                    Text("common.session")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: isEditing ? .leading : .center)
                        .padding(.leading, isEditing ? 8 : 0)
                        .animation(animation, value: isEditing)
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
                text: sessionSolveCountText(session.solveCount),
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
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? .blue : .secondary)
                .animation(animation, value: isSelected)
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

            Button {
                startDeletingSelectedSessions()
            } label: {
                Text("common.delete")
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .compatibleTintedGlassFromIOS16(.red, in: Capsule())
            }
            .tint(.red)
            .buttonStyle(.plain)
            .disabled(selectedSessionIDs.isEmpty || isDeletingSessions)
            .opacity(selectedSessionIDs.isEmpty || isDeletingSessions ? 0.48 : 1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, -8)
        .transition(.opacity)
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

private struct TimeTrendSheet: View {
    @Environment(\.solveTimeAccuracy) private var solveTimeAccuracy
    let solves: [SessionSolveSample]
    let appLanguage: String

    @State private var trendMode: TrendMode = .histogram
    @State private var selectedDate: Date?
    @State private var selectedHistogramX: Double?

    private var solvePoints: [SolvePoint] {
        solves
            .sorted { $0.date < $1.date }
            .compactMap { solve in
                guard let adjusted = SolveMetrics.adjustedTime(for: solve) else { return nil }
                return SolvePoint(id: solve.id, date: solve.date, time: adjusted)
            }
    }

    private var histogramBins: [HistogramBin] {
        let values = solvePoints.map(\.time)
        guard let minValue = values.min(), let maxValue = values.max() else { return [] }

        let lower = floor(minValue)
        let upper = ceil(maxValue)
        let width = max(0.5, (upper - lower) / 8.0)

        var bins: [HistogramBin] = []
        var start = lower
        while start <= upper {
            let end = start + width
            let count = values.filter { value in
                value >= start && (value < end || (end >= upper && value <= end))
            }.count
            bins.append(HistogramBin(lower: start, upper: end, count: count))
            start += width
        }
        return bins
    }

    private var nearestSelectedPoint: SolvePoint? {
        guard let selectedDate else { return nil }
        return solvePoints.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var selectedHistogramBin: HistogramBin? {
        guard let selectedHistogramX else { return nil }
        return histogramBins.first { selectedHistogramX >= $0.lower && selectedHistogramX < $0.upper }
    }

    var body: some View {
        CompatibleNavigationContainer {
            VStack(spacing: 14) {
                Picker("data.trend.mode", selection: $trendMode) {
                    Text("data.trend.histogram").tag(TrendMode.histogram)
                    Text("data.trend.graph").tag(TrendMode.graph)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if solvePoints.isEmpty {
                    Text("data.no_solves")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    Group {
                        if trendMode == .histogram {
                            histogramChart
                        } else {
                            lineChart
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle(appLocalizedString("data.trend.title", languageCode: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var lineChart: some View {
        if #available(iOS 16.0, *) {
            if #available(iOS 17.0, *) {
                lineChartContent
                    .chartXSelection(value: $selectedDate)
            } else {
                lineChartContent
            }
        } else {
            chartUnavailableView
        }
    }

    @available(iOS 16.0, *)
    private var lineChartContent: some View {
        Chart(solvePoints) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Time", point.time)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.blue)

            PointMark(
                x: .value("Date", point.date),
                y: .value("Time", point.time)
            )
            .foregroundStyle(.blue)

            if let selected = nearestSelectedPoint {
                RuleMark(x: .value("Selected Date", selected.date))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .annotation(position: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(SolveMetrics.formatTime(selected.time, decimals: solveTimeAccuracy.decimals))
                                .font(.system(size: 12, weight: .semibold))
                            Text(SolveMetrics.displayDate(selected.date, languageCode: appLanguage))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
            }
        }
        .frame(height: 330)
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
        Chart(histogramBins) { bin in
            RectangleMark(
                xStart: .value("Start", bin.lower),
                xEnd: .value("End", bin.upper),
                yStart: .value("Zero", 0),
                yEnd: .value("Count", bin.count)
            )
            .foregroundStyle(.blue.gradient)

            if let bin = selectedHistogramBin {
                let center = (bin.lower + bin.upper) / 2
                RuleMark(x: .value("Selected Bin", center))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .annotation(position: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(SolveMetrics.formatTime(bin.lower, decimals: solveTimeAccuracy.decimals)) - \(SolveMetrics.formatTime(bin.upper, decimals: solveTimeAccuracy.decimals))")
                                .font(.system(size: 12, weight: .semibold))
                            Text(NumeralPresentation.formatInteger(bin.count))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
            }
        }
        .frame(height: 330)
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

private struct SolvePoint: Identifiable {
    let id: UUID
    let date: Date
    let time: Double
}

private struct HistogramBin: Identifiable {
    let lower: Double
    let upper: Double
    let count: Int

    var id: Double { lower }
}

private enum TrendMode {
    case histogram
    case graph
}
#endif

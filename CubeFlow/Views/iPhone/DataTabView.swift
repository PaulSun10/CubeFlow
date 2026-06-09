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

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Session.createdAt, ascending: true)],
        animation: .default
    )
    private var sessions: FetchedResults<Session>

    @AppStorage("selectedSessionID") private var selectedSessionID: String = ""
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    @State private var selectedSegment: DataSegment = .time
    @State private var segmentTransitionDirection: Edge = .trailing
    @State private var isSelecting = false
    @State private var selectedSolveIDs: Set<UUID> = []
    @State private var showingSessionSheet = false
    @State private var solveDetailSample: SessionSolveSample?
    @State private var averageDetailEntry: AverageListEntry?
    @State private var showingTrendSheet = false
    @State private var selectedAverageType: AverageListType = .mo3
    @State private var recordSnapshot = RecordSnapshot.empty
    @State private var filteredSessionSolves: [SessionSolveSample] = []
    @State private var averageEntriesSnapshot: [AverageListEntry] = []
    @State private var averageEntriesKey: AverageEntriesSnapshotKey?
    @State private var recordSnapshotKey: SessionSnapshotKey?
    @State private var isLoadingSessionSnapshot = false
    @State private var isComputingRecordSnapshot = false
    @State private var isComputingAverageEntries = false
    @State private var measuredLeadingToolbarFrame: CGRect = .zero
    @State private var measuredTrailingToolbarFrame: CGRect = .zero
    @State private var measuredSegmentedFrame: CGRect = .zero
    @State private var toolbarMeasurementGeneration = 0
    @State private var sessionSnapshotGeneration = 0
    @State private var recordComputationGeneration = 0
    @State private var averageComputationGeneration = 0
    @State private var isShowingDeleteSelectedSolvesAlert = false

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
            languageCode: appLanguage
        )
    }

    var body: some View {
        CompatibleNavigationContainer {
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    segmentedControl
                }
            }
            .modifier(
                DataTabLeadingToolbarModifier(frame: $measuredLeadingToolbarFrame) {
                    showingSessionSheet = true
                }
            )
            .modifier(
                DataTabTrailingToolbarModifier(
                    mode: trailingToolbarMode,
                    frame: $measuredTrailingToolbarFrame,
                    measurementGeneration: toolbarMeasurementGeneration,
                    onSelect: beginSelecting,
                    onCloseSelection: endSelecting,
                    onShowGraph: { showingTrendSheet = true }
                )
            )
        }
        .sheet(isPresented: $showingSessionSheet) {
            SessionManagementSheet(selectedSessionID: $selectedSessionID)
                .compatibleLargeSheet()
        }
        .sheet(item: $solveDetailSample) { sample in
            SolveDetailSheet(sample: sample, fallbackPuzzleKey: selectedSessionPuzzleKey)
                .compatibleLargeSheet()
        }
        .sheet(item: $averageDetailEntry) { entry in
            AverageDetailSheet(entry: entry, averageType: selectedAverageType)
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
        .safeAreaInset(edge: .bottom) {
            if selectedSegment == .time && isSelecting && !selectedSolveIDs.isEmpty {
                selectionActionBar
            } else if selectedSegment == .average && !availableAverageTypes.isEmpty {
                averageTypeBar
            }
        }
        .task {
            ensureSessionExists()
            refreshFilteredSessionSolves()
        }
        .onAppear {
            toolbarMeasurementGeneration += 1
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
        }
        .onChange(of: selectedSessionID) { _ in
            isSelecting = false
            selectedSolveIDs.removeAll()
            refreshFilteredSessionSolves()
        }
        .onChange(of: selectedSessionSolveCount) { _ in
            refreshFilteredSessionSolves()
        }
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
    }


    private var segmentedControl: some View {
        Picker("Data Segment", selection: segmentSelection) {
            Text("data.segment.time").tag(DataSegment.time)
            Text("data.segment.average").tag(DataSegment.average)
            Text("data.segment.record").tag(DataSegment.record)
        }
        .pickerStyle(.segmented)
        .modifier(
            DataTabSegmentedWidthModifier(
                fallbackWidth: segmentedWidth,
                leadingToolbarFrame: measuredLeadingToolbarFrame,
                trailingToolbarFrame: measuredTrailingToolbarFrame,
                segmentedFrame: $measuredSegmentedFrame
            )
        )
    }


    private var trailingToolbarMode: DataTabTrailingToolbarMode {
        if selectedSegment == .time {
            return isSelecting ? .closeSelection : .select
        }
        return .graph
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
            } else {
                List {
                    Section(selectedSession?.name ?? "") {
                        ForEach(Array(sessionSolves.enumerated()), id: \.element.id) { index, solve in
                            solveRow(
                                for: solve,
                                position: sessionSolves.count - index
                            )
                        }
                    }
                }
                .listStyle(.insetGrouped)
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

    private var segmentedWidth: CGFloat {
        200
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
                List(averageEntriesSnapshot) { entry in
                    averageRow(for: entry)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
                .listStyle(.plain)
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
                            value: recordSnapshot.bestTimeText
                        )
                        recordRow(
                            title: localizedRecordLabel("data.worst_time"),
                            value: recordSnapshot.worstTimeText
                        )
                    }

                    if !recordSnapshot.currentStats.isEmpty {
                        Section(localizedRecordLabel("common.current")) {
                            ForEach(recordSnapshot.currentStats) { item in
                                recordRow(title: item.title, value: item.value)
                            }
                        }
                    }

                    if !recordSnapshot.bestStats.isEmpty {
                        Section(localizedRecordLabel("common.best")) {
                            ForEach(recordSnapshot.bestStats) { item in
                                recordRow(title: item.title, value: item.value)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
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

    private func recordRow(title: String, value: String, suffix: String? = nil) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)

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
        }
        .padding(.vertical, 4)
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

                Text(SolveMetrics.formatAverage(entry.value))
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
                    Text(SolveMetrics.displayTime(for: solve))
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
                selectedSolveIDs = Set(sessionSolves.map(\.id))
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
                modelContext.delete(solve)
            }
        }
        try? modelContext.save()
        filteredSessionSolves.removeAll { deletedIDs.contains($0.id) }
        selectedSolveIDs.removeAll()
        NotificationCenter.default.post(name: solvesDidChangeNotification, object: nil)
    }

    private func fetchSolve(with id: UUID) -> Solve? {
        try? modelContext.fetchSolve(with: id)
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
            recordSnapshotKey = nil
            isLoadingSessionSnapshot = false
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
                    eventRawValue: solve.event
                )
            }

            await MainActor.run {
                guard generation == sessionSnapshotGeneration else { return }
                filteredSessionSolves = snapshots
                isLoadingSessionSnapshot = false
                syncSelectedAverageType()
                prewarmRecordSnapshotIfNeeded()
                ensureAverageEntriesSnapshot()
                if selectedSegment == .record {
                    refreshRecordSnapshot()
                }
            }
        }
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
                languageCode: languageCode
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

private enum DataTabTrailingToolbarMode: Equatable {
    case select
    case closeSelection
    case graph
}

private let dataTabDebugToolbarMarkerLeftInset: CGFloat = 14
private let dataTabDebugToolbarMarkerRightInset: CGFloat = 16

private struct DataTabToolbarFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let nextFrame = nextValue()
        if nextFrame != .zero {
            value = nextFrame
        }
    }
}

private extension CGRect {
    func isNearlyEqual(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance &&
        abs(minY - other.minY) <= tolerance &&
        abs(width - other.width) <= tolerance &&
        abs(height - other.height) <= tolerance
    }
}

private struct DataTabToolbarFrameReader: View {
    @Binding var frame: CGRect

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: DataTabToolbarFramePreferenceKey.self,
                    value: proxy.frame(in: .global)
                )
        }
        .onPreferenceChange(DataTabToolbarFramePreferenceKey.self) { newFrame in
            guard newFrame != .zero else { return }
            guard !frame.isNearlyEqual(to: newFrame) else { return }
            frame = newFrame
        }
    }
}


private struct DataTabGraphToolbarFrameReader: View {
    @Binding var frame: CGRect
    let generation: Int
    @State private var acceptedGeneration: Int?

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: DataTabToolbarFramePreferenceKey.self,
                    value: proxy.frame(in: .global)
                )
        }
        .onPreferenceChange(DataTabToolbarFramePreferenceKey.self) { newFrame in
            guard newFrame != .zero else { return }
            if acceptedGeneration != generation {
                acceptedGeneration = generation
                frame = newFrame
                return
            }
            if frame == .zero || newFrame.minX > frame.minX + 0.5 {
                frame = newFrame
            }
        }
    }
}

private struct DataTabLeadingToolbarModifier: ViewModifier {
    @Binding var frame: CGRect
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
                .background(DataTabToolbarFrameReader(frame: $frame))
            }
        }
    }
}

private struct DataTabSegmentedWidthModifier: ViewModifier {
    let fallbackWidth: CGFloat
    let leadingToolbarFrame: CGRect
    let trailingToolbarFrame: CGRect
    @Binding var segmentedFrame: CGRect

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            ZStack(alignment: .leading) {
                Color.clear
                    .frame(width: fallbackWidth)
                    .background(DataTabToolbarFrameReader(frame: $segmentedFrame))

                content
                    .frame(width: measuredAvailableWidth)
                    .offset(x: measuredLeftOffsetX)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
            }
            .frame(width: fallbackWidth, alignment: .leading)
            .layoutPriority(1)
        } else {
            content
                .frame(width: fallbackWidth)
        }
    }

    private var measuredAvailableWidth: CGFloat {
        guard hasMeasuredToolbarFrames else { return fallbackWidth }
        return max(measuredRightX - measuredLeftX, 0)
    }

    private var measuredLeftOffsetX: CGFloat {
        guard hasMeasuredToolbarFrames, segmentedFrame != .zero else { return 0 }
        return measuredLeftX - segmentedFrame.minX
    }


    private var measuredLeftX: CGFloat {
        leadingToolbarFrame.maxX + dataTabDebugToolbarMarkerLeftInset
    }

    private var measuredRightX: CGFloat {
        trailingToolbarFrame.minX - dataTabDebugToolbarMarkerRightInset
    }

    private var hasMeasuredToolbarFrames: Bool {
        leadingToolbarFrame != .zero && trailingToolbarFrame != .zero
    }
}

private struct DataTabTrailingToolbarModifier: ViewModifier {
    let mode: DataTabTrailingToolbarMode
    @Binding var frame: CGRect
    let measurementGeneration: Int
    let onSelect: () -> Void
    let onCloseSelection: () -> Void
    let onShowGraph: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            trailingToolbarContent
        }
    }

    @ToolbarContentBuilder
    private var trailingToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            switch mode {
            case .select:
                Button {
                    onSelect()
                } label: {
                    Text("common.select")
                        .font(.system(size: 16, weight: .semibold))
                }
                .background(DataTabToolbarFrameReader(frame: $frame))
            case .closeSelection:
                Button {
                    onCloseSelection()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                }
                .background(DataTabToolbarFrameReader(frame: $frame))
            case .graph:
                Button {
                    onShowGraph()
                } label: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 16, weight: .medium))
                }
                .background(DataTabGraphToolbarFrameReader(frame: $frame, generation: measurementGeneration))
            }
        }
    }
}

private struct SolveDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    private let sample: SessionSolveSample
    private let fallbackPuzzleKey: String?
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var showingScrambleDetail = false
    @State private var isShowingDeleteSolveAlert = false

    init(sample: SessionSolveSample, fallbackPuzzleKey: String?) {
        self.sample = sample
        self.fallbackPuzzleKey = fallbackPuzzleKey
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

                        Text(SolveMetrics.displayTime(for: sample))
                            .font(.system(size: 44, weight: .semibold))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    scrambleSection

                    if canShowScrambleDiagram, let puzzleKey {
                        let aspectRatio = ScrambleDiagramView.diagramAspectRatio(for: puzzleKey)
                        ScrambleDiagramView(puzzleKey: puzzleKey, scramble: sample.scramble)
                            .aspectRatio(aspectRatio, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                    }

                    actionSection
                }
                .padding(20)
            }
            .navigationTitle(appLocalizedString("common.solve", languageCode: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") {
                        dismiss()
                    }
                }
            }
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
                    }
                    .navigationTitle(appLocalizedString("common.scramble", languageCode: appLanguage))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("common.done") {
                                showingScrambleDetail = false
                            }
                        }
                    }
                }
                .compatibleLargeSheet()
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
                .foregroundStyle(.blue)
                .compatibleProminentButtonFromIOS16(tint: .blue)

                Button("+2") {
                    updateResult(.plusTwo)
                }
                .foregroundStyle(.blue)
                .compatibleProminentButtonFromIOS16(tint: .blue)

                Button("common.solved") {
                    updateResult(.solved)
                }
                .foregroundStyle(.blue)
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
            .foregroundStyle(.red)
            .controlSize(.large)
        }
    }

    private func updateResult(_ result: SolveResult) {
        guard let solve = try? modelContext.fetchSolve(with: sample.id) else {
            dismiss()
            return
        }

        solve.result = result
        try? modelContext.save()
        NotificationCenter.default.post(name: solvesDidChangeNotification, object: nil)
        dismiss()
    }

    private func deleteSolve() {
        if let solve = try? modelContext.fetchSolve(with: sample.id) {
            modelContext.delete(solve)
            try? modelContext.save()
            NotificationCenter.default.post(name: solvesDidChangeNotification, object: nil)
        }
        dismiss()
    }
}


private struct AverageDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: AverageListEntry
    let averageType: AverageListType
    @AppStorage("appLanguage") private var appLanguage: String = "en"

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
        let trimmingCount = averageType.trimmingCount
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

    var body: some View {
        CompatibleNavigationContainer {
            List {
                Section {
                    averageSummaryRow(
                        title: dataTabLocalizedString(for: "data.segment.average", languageCode: appLanguage),
                        value: SolveMetrics.formatAverage(entry.value),
                        isPrimary: true
                    )
                    averageSummaryRow(
                        title: dataTabLocalizedString(for: "data.best_time", languageCode: appLanguage),
                        value: bestSolve.map { SolveMetrics.displayTime(for: $0) } ?? appLocalizedString("common.not_available", languageCode: appLanguage)
                    )
                    averageSummaryRow(
                        title: dataTabLocalizedString(for: "data.worst_time", languageCode: appLanguage),
                        value: worstSolve.map { SolveMetrics.displayTime(for: $0) } ?? appLocalizedString("common.not_available", languageCode: appLanguage)
                    )
                }

                Section(String(format: dataTabLocalizedString(for: "common.solves_format", languageCode: appLanguage), entry.solves.count)) {
                    ForEach(Array(orderedSolves.enumerated()), id: \.element.id) { index, solve in
                        averageSolveRow(solve, position: index + 1)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(averageType.title(languageCode: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func averageSummaryRow(title: String, value: String, isPrimary: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()

            Text(value)
                .font(.system(size: isPrimary ? 26 : 18, weight: isPrimary ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(isPrimary && entry.isPersonalBest ? .orange : .primary)
        }
        .padding(.vertical, isPrimary ? 6 : 3)
    }

    private func averageSolveRow(_ solve: SessionSolveSample, position: Int) -> some View {
        let timeText = SolveMetrics.displayTime(for: solve)
        let displayText = trimmedSolveIDs.contains(solve.id) ? "(\(timeText))" : timeText

        return HStack(spacing: 12) {
            Text("#\(position)")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayText)
                    .font(.system(size: 21, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(color(for: solve))

                Text(SolveMetrics.displayDate(solve.date, languageCode: appLanguage))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func color(for solve: SessionSolveSample) -> Color {
        if solve.id == entry.bestSolveID { return .orange }
        if solve.id == entry.worstSolveID { return .red }
        return .primary
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
        String(format: dataTabLocalizedString(for: "common.solves_format", languageCode: appLanguage), count)
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
                            Text(SolveMetrics.formatTime(selected.time, decimals: 3))
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
                            Text("\(SolveMetrics.formatTime(bin.lower, decimals: 2)) - \(SolveMetrics.formatTime(bin.upper, decimals: 2))")
                                .font(.system(size: 12, weight: .semibold))
                            Text("\(bin.count)")
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

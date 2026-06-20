import SwiftUI
import UIKit
import MapKit
import CoreLocation
import Combine
import WeatherKit
import CoreText

#if os(iOS)
private struct CompetitionSkeletonBreathingModifier: ViewModifier {
    @State private var isDimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(isDimmed ? 0.6 : 1.0)
            .brightness(isDimmed ? 0.08 : -0.03)
            .scaleEffect(isDimmed ? 0.988 : 1.0)
            .onAppear {
                guard !isDimmed else { return }
                withAnimation(.easeInOut(duration: 0.82).repeatForever(autoreverses: true)) {
                    isDimmed = true
                }
            }
    }
}

private extension View {
    func competitionSkeletonBreathing() -> some View {
        modifier(CompetitionSkeletonBreathingModifier())
    }
}

private struct CompetitionDetailScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CompetitionCardSurfaceModifier: ViewModifier {
    let isGlass: Bool
    let shape: RoundedRectangle

    @ViewBuilder
    func body(content: Content) -> some View {
        if isGlass {
            content
                .compatibleGlass(in: shape)
        } else {
            content
        }
    }
}

private struct CompetitionListRowBackgroundModifier: ViewModifier {
    let isGlass: Bool
    let shape: RoundedRectangle

    @ViewBuilder
    func body(content: Content) -> some View {
        if isGlass {
            content
                .background(
                    shape
                        .fill(.black.opacity(0.001))
                )
        } else {
            content
        }
    }
}

private extension ShapeStyle where Self == Color {
    static var competitionSkeletonFill: Color {
        Color(uiColor: .secondarySystemFill)
    }
}

#if DEBUG
private struct CompetitionSizeDebugModifier: ViewModifier {
    let label: String
    let color: Color

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(color.opacity(0.75), lineWidth: 0.75)
                    .allowsHitTesting(false)
            )
            .overlay(alignment: .topTrailing) {
                GeometryReader { proxy in
                    Text("\(label) \(Int(proxy.size.width))")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(.regularMaterial, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .allowsHitTesting(false)
                }
            }
    }
}
#endif

private extension View {
    @ViewBuilder
    func competitionSizeDebug(_ label: String, color: Color) -> some View {
        #if DEBUG
        modifier(CompetitionSizeDebugModifier(label: label, color: color))
        #else
        self
        #endif
    }
}

private extension String {
    func competitionSingleLineWidth(using font: UIFont) -> CGFloat {
        ceil((self as NSString).size(withAttributes: [.font: font]).width)
    }
}

@available(iOS 16.0, *)
private struct CompetitionWrappingLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    private func measuredSize(for subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        if maxWidth.isFinite,
           let preferredWidth = subview[CompetitionWrappingPreferredWidthKey.self] {
            let proposedWidth = min(preferredWidth, maxWidth)
            return subview.sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil))
        }

        let naturalSize = subview.sizeThatFits(.unspecified)
        guard naturalSize.width > maxWidth else { return naturalSize }
        return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = measuredSize(for: subview, maxWidth: maxWidth)
            let startsNewRow = currentRowWidth > 0 && currentRowWidth + horizontalSpacing + size.width > maxWidth

            if startsNewRow {
                totalWidth = max(totalWidth, currentRowWidth)
                totalHeight += currentRowHeight + verticalSpacing
                currentRowWidth = size.width
                currentRowHeight = size.height
            } else {
                currentRowWidth += (currentRowWidth > 0 ? horizontalSpacing : 0) + size.width
                currentRowHeight = max(currentRowHeight, size.height)
            }
        }

        totalWidth = max(totalWidth, currentRowWidth)
        totalHeight += currentRowHeight

        return CGSize(
            width: proposal.width ?? totalWidth,
            height: totalHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var currentRowHeight: CGFloat = 0

        for subview in subviews {
            let size = measuredSize(for: subview, maxWidth: maxWidth)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += currentRowHeight + verticalSpacing
                currentRowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + horizontalSpacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
    }
}

@available(iOS 16.0, *)
private struct CompetitionWrappingPreferredWidthKey: LayoutValueKey {
    nonisolated static let defaultValue: CGFloat? = nil
}

@available(iOS 16.0, *)
private struct CompetitionTopCuberChipLayout: Layout {
    var spacing: CGFloat = 8
    var minimumNameWidth: CGFloat = 96

    private func badgeSizes(for subviews: Subviews) -> [CGSize] {
        guard subviews.count > 1 else { return [] }
        return subviews.dropFirst().map { $0.sizeThatFits(.unspecified) }
    }

    private func badgeWidth(from sizes: [CGSize]) -> CGFloat {
        guard !sizes.isEmpty else { return 0 }
        return sizes.map(\.width).reduce(0, +) + CGFloat(sizes.count) * spacing
    }

    private func measuredNameSize(
        for subviews: Subviews,
        badgeWidth: CGFloat,
        maxWidth: CGFloat
    ) -> CGSize {
        guard let name = subviews.first else { return .zero }

        let naturalNameSize = name.sizeThatFits(.unspecified)
        let naturalWidth = naturalNameSize.width + badgeWidth
        guard maxWidth.isFinite, naturalWidth > maxWidth else {
            return naturalNameSize
        }

        let proposedNameWidth = max(minimumNameWidth, maxWidth - badgeWidth)
        return name.sizeThatFits(ProposedViewSize(width: proposedNameWidth, height: nil))
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let badgeSizes = badgeSizes(for: subviews)
        let badgesWidth = badgeWidth(from: badgeSizes)
        let nameSize = measuredNameSize(for: subviews, badgeWidth: badgesWidth, maxWidth: maxWidth)
        let contentWidth = nameSize.width + badgesWidth
        let contentHeight = max(nameSize.height, badgeSizes.map(\.height).max() ?? 0)

        return CGSize(
            width: maxWidth.isFinite ? min(contentWidth, maxWidth) : contentWidth,
            height: contentHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        guard let name = subviews.first else { return }

        let badgeSizes = badgeSizes(for: subviews)
        let badgesWidth = badgeWidth(from: badgeSizes)
        let nameSize = measuredNameSize(for: subviews, badgeWidth: badgesWidth, maxWidth: bounds.width)
        let nameY = bounds.minY + (bounds.height - nameSize.height) / 2

        name.place(
            at: CGPoint(x: bounds.minX, y: nameY),
            proposal: ProposedViewSize(nameSize)
        )

        var badgeX = bounds.minX + nameSize.width + spacing
        for (index, badge) in subviews.dropFirst().enumerated() {
            let size = badgeSizes[index]
            let badgeY = bounds.minY + (bounds.height - size.height) / 2
            badge.place(
                at: CGPoint(x: badgeX, y: badgeY),
                proposal: ProposedViewSize(size)
            )
            badgeX += size.width + spacing
        }
    }
}

private enum CompetitionTopCuberLoadState: Equatable {
    case idle
    case loading
    case loaded([CompetitionTopCuberPreview])
    case empty
    case failed
}

private enum CompetitionScheduleDisplayMode: String, CaseIterable, Identifiable {
    case calendar
    case table

    var id: String { rawValue }
}

private enum CompetitionScheduleTableStyle: String, CaseIterable, Identifiable {
    case cards
    case table

    var id: String { rawValue }
}

@MainActor
private final class CompetitionListRuntimeCache {
    struct Snapshot {
        let competitions: [CompetitionSummary]
        let visibleCompetitionsSnapshot: [CompetitionSummary]
        let publishedVisibleCompetitions: [CompetitionSummary]
        let nextPage: Int?
        let topCuberStatesByCompetitionID: [String: CompetitionTopCuberLoadState]
    }

    static let shared = CompetitionListRuntimeCache()

    private var snapshotsBySignature: [String: Snapshot] = [:]

    func snapshot(for signature: String) -> Snapshot? {
        snapshotsBySignature[signature]
    }

    func store(_ snapshot: Snapshot, for signature: String) {
        snapshotsBySignature[signature] = snapshot
    }
}

enum CompetitionCardStyleOption: String, CaseIterable, Identifiable {
    case list
    case glass

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .list:
            return "settings.competition_card_style_list"
        case .glass:
            return "settings.competition_card_style_glass"
        }
    }
}

struct CompetitionTabView: View {
    private static let initialTopCuberPreloadCount = 8
    private static let nextTopCuberPrefetchCount = 16
    private static let topCuberLoadConcurrency = 3

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("competitionCardStyle") private var competitionCardStyle: String = CompetitionCardStyleOption.list.rawValue
    @AppStorage("competitionsBackgroundAppearanceData") private var competitionsBackgroundAppearanceData: Data?
    @AppStorage("competitionsBackgroundImageData") private var competitionsBackgroundImageData: Data?
    @AppStorage("competition_filter_region") private var storedRegionID: String = CompetitionRegionFilter.all.id
    @AppStorage("competition_filter_events") private var storedEventIDs: String = CompetitionEventFilter.selectableCases
        .map(\.rawValue)
        .sorted()
        .joined(separator: ",")
    @AppStorage("competition_filter_year") private var storedYearRawValue: String = CompetitionYearFilter.all.rawValue
    @AppStorage("competition_filter_status") private var storedStatusRawValue: String = CompetitionStatusFilter.upcoming.rawValue
    @AppStorage("competition_show_top_cubers") private var showsTopCubers: Bool = false
    @State private var showsFilterPopover = false
    @State private var competitions: [CompetitionSummary] = []
    @State private var visibleCompetitionsSnapshot: [CompetitionSummary] = []
    @State private var publishedVisibleCompetitions: [CompetitionSummary] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var isPrefetchingRemainingCompetitions = false
    @State private var errorMessage: String?
    @State private var nextPage: Int? = 1
    @State private var showsMapView = false
    @State private var isShowingSearch = false
    @State private var selectedCompetitionForDetail: CompetitionSummary?
    @State private var cubingRowClassesByKey: [String: String] = [:]
    @State private var showsRefreshSuccessBanner = false
    @State private var topCuberStatesByCompetitionID: [String: CompetitionTopCuberLoadState] = [:]
    @State private var topCuberRefreshingIDs: Set<String> = []
    @State private var areCompetitionEventIconsReady = CompetitionEventIconFont.isAvailable
    @State private var competitionNavigationSubtitleText = ""
    @State private var topCubersTaskSignatureText = "off"
    @State private var topCuberPreloadCompetitionIDs: [String] = []
    @State private var topCuberPrefetchCompetitionIDs: [String] = []

    private let usesSystemBottomAccessory: Bool
    @Binding private var isBottomAccessoryVisible: Bool
    @Binding private var searchRequestID: Int

    init(
        usesSystemBottomAccessory: Bool = false,
        isBottomAccessoryVisible: Binding<Bool> = .constant(false),
        searchRequestID: Binding<Int> = .constant(0)
    ) {
        self.usesSystemBottomAccessory = usesSystemBottomAccessory
        _isBottomAccessoryVisible = isBottomAccessoryVisible
        _searchRequestID = searchRequestID
    }

    var body: some View {
        CompatibleNavigationContainer {
            List {
                if showsRefreshSuccessBanner {
                    refreshSuccessRow
                }

                if isLoading {
                    competitionLoadingSkeletonRows
                } else if publishedVisibleCompetitions.isEmpty {
                    if let errorMessage {
                        errorRow(message: errorMessage)
                    } else {
                        emptyRow
                    }
                } else {
                    ForEach(publishedVisibleCompetitions) { competition in
                        competitionListRow(competition)
                    }

                    if isLoadingMore {
                        loadingMoreRow
                    } else if nextPage != nil {
                        Color.clear
                            .frame(height: 1)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .onAppear {
                                Task {
                                    await loadMoreCompetitionsIfNeeded()
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
            .compatibleScrollContentBackgroundHidden()
            .background(competitionsTabBackgroundView.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if !usesSystemBottomAccessory && shouldShowCompetitionBottomAccessory {
                    competitionBottomSearchBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle(Text(localizedCompetitionStringInView(key: "tab.competitions", languageCode: appLanguage)))
            .compatibleNavigationSubtitle(Text(competitionNavigationSubtitle))
            .navigationBarTitleDisplayMode(.large)
            .background(CompetitionNavigationBarFontConfigurator(largeSubtitle: competitionNavigationSubtitle))
            .task {
                areCompetitionEventIconsReady = CompetitionEventIconFont.ensureRegistered()
            }
            .onAppear(perform: updateBottomAccessoryVisibility)
            .onDisappear {
                if usesSystemBottomAccessory {
                    isBottomAccessoryVisible = false
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    mapButton
                    filterButton
                }
            }
            .refreshable {
                await refreshCompetitionsForPullToRefresh()
            }
            .task(id: appLanguage) {
                await CompetitionService.warmRecognizedCountriesCache()
                await CompetitionService.warmCompetitionLocalizedNamesCache(languageCode: appLanguage)
                cubingRowClassesByKey = await fetchCubingRowClasses(languageCode: appLanguage)
            }
            .onChange(of: cubingRowClassesByKey) { _ in
                syncVisibleCompetitionsSnapshot(query: competitionQuery)
                publishVisibleCompetitionsSnapshot()
            }
            .onChange(of: showsTopCubers) { _ in
                updateCompetitionListDerivedState(for: publishedVisibleCompetitions)
            }
            .onChange(of: publishedVisibleCompetitions) { _ in
                updateBottomAccessoryVisibility()
            }
            .onChange(of: searchRequestID) { _ in
                guard usesSystemBottomAccessory else { return }
                isShowingSearch = true
            }
            .task(id: filterSignature) {
                await loadCompetitions()
            }
            .task(id: topCubersTaskSignature) {
                await loadVisibleTopCuberPreviewsIfNeeded()
            }
            .compatibleNavigationDestination(isPresented: $showsMapView) {
                competitionMapDestination
            }
            .compatibleNavigationDestination(isPresented: $isShowingSearch) {
                CompetitionSearchView(
                    competitions: publishedVisibleCompetitions,
                    appLanguage: appLanguage
                )
            }
            .compatibleNavigationDestination(item: $selectedCompetitionForDetail) { competition in
                CompetitionDetailView(
                    competition: competition,
                    appLanguage: appLanguage
                )
            }
        }
    }

    private var competitionsBackgroundAppearance: AppearanceConfiguration {
        AppearanceConfiguration.decode(
            from: competitionsBackgroundAppearanceData,
            fallback: .defaultBackground
        )
    }

    private var competitionsTabBackgroundView: some View {
        let usesGlassStyle = CompetitionCardStyleOption(rawValue: competitionCardStyle) == .glass

        guard usesGlassStyle else {
            return AnyView(Color.clear)
        }

        switch competitionsBackgroundAppearance.style {
        case .system:
            return AnyView(Color.clear)
        case .color:
            return AnyView(competitionsBackgroundAppearance.color(for: colorScheme))
        case .gradient:
            let gradient = competitionsBackgroundAppearance.gradient(for: colorScheme)
            return AnyView(
                LinearGradient(
                    gradient: Gradient(stops: gradient.resolvedStops),
                    startPoint: competitionsGradientStartPoint(angle: gradient.angle),
                    endPoint: competitionsGradientEndPoint(angle: gradient.angle)
                )
            )
        case .photo:
            #if os(iOS)
            if let data = competitionsBackgroundImageData,
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

    private func competitionsGradientStartPoint(angle: Double) -> UnitPoint {
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 - cos(radians) * 0.5, y: 0.5 - sin(radians) * 0.5)
    }

    private func competitionsGradientEndPoint(angle: Double) -> UnitPoint {
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 + cos(radians) * 0.5, y: 0.5 + sin(radians) * 0.5)
    }

    private var selectedRegion: CompetitionRegionFilter {
        get { CompetitionRegionFilter(storedID: storedRegionID) ?? .all }
        nonmutating set { storedRegionID = newValue.id }
    }

    private var selectedEvents: Set<CompetitionEventFilter> {
        get {
            let restored = Set(
                storedEventIDs
                    .split(separator: ",")
                    .compactMap { CompetitionEventFilter(rawValue: String($0)) }
            )
            return restored.isEmpty ? Set(CompetitionEventFilter.selectableCases) : restored
        }
        nonmutating set {
            let normalized = newValue.isEmpty ? Set(CompetitionEventFilter.selectableCases) : newValue
            storedEventIDs = normalized.map(\.rawValue).sorted().joined(separator: ",")
        }
    }

    private var selectedYear: CompetitionYearFilter {
        get { CompetitionYearFilter(rawValue: storedYearRawValue) ?? .all }
        nonmutating set { storedYearRawValue = newValue.rawValue }
    }

    private var selectedStatus: CompetitionStatusFilter {
        get { CompetitionStatusFilter(rawValue: storedStatusRawValue) ?? .upcoming }
        nonmutating set { storedStatusRawValue = newValue.rawValue }
    }

    private var filterButton: some View {
        Button {
            showsFilterPopover = true
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .popover(
            isPresented: $showsFilterPopover,
            attachmentAnchor: .point(.bottom),
            arrowEdge: .top
        ) {
            CompetitionFiltersPopover(
                selectedRegion: Binding(
                    get: { selectedRegion },
                    set: { selectedRegion = $0 }
                ),
                selectedEvents: Binding(
                    get: { selectedEvents },
                    set: { selectedEvents = $0 }
                ),
                selectedYear: Binding(
                    get: { selectedYear },
                    set: { selectedYear = $0 }
                ),
                selectedStatus: Binding(
                    get: { selectedStatus },
                    set: { selectedStatus = $0 }
                ),
                showsTopCubers: $showsTopCubers,
                appLanguage: appLanguage,
                showsFilterPopover: $showsFilterPopover
            )
            .compatibleClearPresentationBackground()
            .compatiblePopoverCompactAdaptation()
        }
    }

    private var mapButton: some View {
        Button {
            showsMapView = true
        } label: {
            Image(systemName: "map")
        }
    }

    @ViewBuilder
    private var competitionMapDestination: some View {
        if #available(iOS 17.0, *) {
            CompetitionMapView(
                query: competitionQuery,
                appLanguage: appLanguage
            )
        } else {
            VStack(spacing: 12) {
                Image(systemName: "map")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(localizedCompetitionStringInView(key: "competitions.map_title", languageCode: appLanguage))
                    .font(.system(size: 18, weight: .semibold))
                Text("iOS 17+")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var competitionNavigationSubtitle: String {
        competitionNavigationSubtitleText
    }

    private var filterSignature: String {
        [
            selectedRegion.id,
            selectedEvents
                .map(\.rawValue)
                .sorted()
                .joined(separator: ","),
            selectedYear.rawValue,
            selectedStatus.rawValue,
            appLanguage
        ].joined(separator: "|")
    }

    private var topCubersTaskSignature: String {
        topCubersTaskSignatureText
    }

    private var competitionQuery: CompetitionQuery {
        CompetitionQuery(
            languageCode: appLanguage,
            region: selectedRegion,
            events: selectedEvents,
            year: selectedYear,
            status: selectedStatus
        )
    }

    private var shouldShowCompetitionBottomAccessory: Bool {
        !publishedVisibleCompetitions.isEmpty
    }

    private var competitionBottomSearchBar: some View {
        CompetitionBottomSearchBar(
            languageCode: appLanguage,
            usesContainerGlass: true
        ) {
            isShowingSearch = true
        }
    }

    private func updateBottomAccessoryVisibility() {
        guard usesSystemBottomAccessory else { return }
        isBottomAccessoryVisible = shouldShowCompetitionBottomAccessory
    }

    private var competitionLoadingSkeletonRows: some View {
        ForEach(0..<6, id: \.self) { _ in
            competitionSkeletonRow
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    private var competitionSkeletonRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.competitionSkeletonFill)
                        .frame(width: 220, height: 20)
                        .competitionSkeletonBreathing()

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.competitionSkeletonFill)
                        .frame(width: 132, height: 16)
                        .competitionSkeletonBreathing()

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.competitionSkeletonFill)
                        .frame(width: 164, height: 16)
                        .competitionSkeletonBreathing()
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    Capsule()
                        .fill(.competitionSkeletonFill)
                        .frame(width: 72, height: 28)
                        .competitionSkeletonBreathing()

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.competitionSkeletonFill)
                        .frame(width: 56, height: 14)
                        .competitionSkeletonBreathing()
                }
            }

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.competitionSkeletonFill)
                .frame(width: 188, height: 16)
                .competitionSkeletonBreathing()
        }
        .padding(.vertical, 8)
        .redacted(reason: .placeholder)
    }

    private var emptyRow: some View {
        Text(localizedCompetitionStringInView(key: "competitions.empty", languageCode: appLanguage))
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.vertical, 24)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private var loadingMoreRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.9)
            Text(localizedCompetitionStringInView(key: "competitions.loading", languageCode: appLanguage))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .center)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func errorRow(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            Button(localizedCompetitionStringInView(key: "wca.results_retry", languageCode: appLanguage)) {
                Task {
                    await loadCompetitions()
                }
            }
            .font(.system(size: 16, weight: .semibold))
        }
        .padding(.vertical, 18)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var refreshSuccessRow: some View {
        Text(localizedCompetitionStringInView(key: "competitions.refresh_success", languageCode: appLanguage))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func competitionRow(_ competition: CompetitionSummary) -> some View {
        let usesGlassStyle = CompetitionCardStyleOption(rawValue: competitionCardStyle) == .glass
        return usesGlassStyle ? AnyView(glassCompetitionRow(competition)) : AnyView(listCompetitionRow(competition))
    }

    private func listCompetitionRow(_ competition: CompetitionSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(competitionFlagEmoji(for: competition.countryISO2))
                            .font(.system(size: 18))
                        Text(competition.name)
                            .font(.system(size: 18, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(localizedCompetitionDateRange(for: competition))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(competition.locationLine)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    statusBadge(
                        for: competitionAvailabilityStatus(for: competition),
                        competition: competition,
                        languageCode: appLanguage
                    )

                    if let competitorLimit = competition.competitorLimit {
                        Text(String(format: localizedCompetitionStringInView(key: "competitions.competitor_limit_format", languageCode: appLanguage), competitorLimit))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            if !competition.venueLine.isEmpty {
                Text(competition.venueLine)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsTopCubers {
                competitionTopCubersContent(for: competition)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .task(id: showsTopCubers ? "\(competition.id)|\(appLanguage)" : "off") {
            await loadTopCuberPreviewIfNeeded(for: competition)
        }
    }

    private func glassCompetitionRow(_ competition: CompetitionSummary) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(competitionFlagEmoji(for: competition.countryISO2))
                                .font(.system(size: 18))
                            Text(competition.name)
                                .font(.system(size: 18, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(localizedCompetitionDateRange(for: competition))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(competition.locationLine)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 8) {
                        statusBadge(
                            for: competitionAvailabilityStatus(for: competition),
                            competition: competition,
                            languageCode: appLanguage
                        )

                        if let competitorLimit = competition.competitorLimit {
                            Text(String(format: localizedCompetitionStringInView(key: "competitions.competitor_limit_format", languageCode: appLanguage), competitorLimit))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                            }
                    }
                }
                .padding(.trailing, 18)

                if !competition.venueLine.isEmpty {
                    Text(competition.venueLine)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showsTopCubers {
                    competitionTopCubersContent(for: competition)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CompetitionCardSurfaceModifier(isGlass: true, shape: shape))
        .modifier(CompetitionListRowBackgroundModifier(isGlass: true, shape: shape))
        .task(id: showsTopCubers ? "\(competition.id)|\(appLanguage)" : "off") {
            await loadTopCuberPreviewIfNeeded(for: competition)
        }
    }

    @ViewBuilder
    private func competitionTopCubersContent(for competition: CompetitionSummary) -> some View {
        if let state = topCuberStatesByCompetitionID[competition.id] {
            switch state {
            case .loading:
                Divider()
                competitionTopCubersSkeletonSection
            case .loaded(let previews):
                if !previews.isEmpty {
                    Divider()
                    competitionTopCubersSection(previews: previews)
                }
            case .idle, .empty, .failed:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func competitionTopCubersSection(previews: [CompetitionTopCuberPreview]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizedCompetitionStringInView(key: "competitions.top_cubers", languageCode: appLanguage))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if #available(iOS 16.0, *) {
                CompetitionWrappingLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(previews) { preview in
                        topCuberChip(for: preview)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .competitionSizeDebug("section", color: .blue)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(previews) { preview in
                        topCuberChip(for: preview)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func topCuberChip(for preview: CompetitionTopCuberPreview) -> some View {
        if #available(iOS 16.0, *) {
            topCuberChipSurface {
                CompetitionTopCuberChipLayout(spacing: 8) {
                    topCuberChipName(preview.name)
                    topCuberChipBadges(preview.badges)
                }
            }
            .competitionSizeDebug("chip", color: .red)
            .layoutValue(
                key: CompetitionWrappingPreferredWidthKey.self,
                value: topCuberChipPreferredWidth(for: preview)
            )
        } else {
            topCuberChipSurface {
                HStack(spacing: 8) {
                    topCuberChipName(preview.name)
                    topCuberChipBadges(preview.badges)
                }
            }
        }
    }

    private func topCuberChipName(_ name: String) -> some View {
        Text(name)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func topCuberChipBadges(_ badges: [CompetitionTopCuberBadge]) -> some View {
        ForEach(badges) { badge in
            topCuberEventBadge(for: badge)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func topCuberChipPreferredWidth(for preview: CompetitionTopCuberPreview) -> CGFloat {
        let nameFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
        let nameWidth = preview.name.competitionSingleLineWidth(using: nameFont)
        let badgesWidth = preview.badges.reduce(CGFloat.zero) { partialWidth, badge in
            partialWidth + topCuberBadgePreferredWidth(for: badge)
        }
        let gapsWidth = CGFloat(preview.badges.count) * 8
        let chipHorizontalPadding: CGFloat = 20

        return ceil(nameWidth + badgesWidth + gapsWidth + chipHorizontalPadding)
    }

    private func topCuberBadgePreferredWidth(for badge: CompetitionTopCuberBadge) -> CGFloat {
        let horizontalPadding: CGFloat = 12

        if areCompetitionEventIconsReady,
           let glyph = CompetitionEventIconFont.glyph(for: badge.eventID) {
            let font = UIFont(name: CompetitionEventIconFont.fontName, size: 13)
                ?? .systemFont(ofSize: 13, weight: .regular)
            return glyph.competitionSingleLineWidth(using: font) + horizontalPadding
        }

        let label = localizedEventShortName(for: badge.eventID)
        let font = UIFont.systemFont(ofSize: 11, weight: .bold)
        return label.competitionSingleLineWidth(using: font) + horizontalPadding
    }

    private func topCuberChipSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.secondary.opacity(0.08), in: Capsule())
    }

    private var competitionTopCubersSkeletonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizedCompetitionStringInView(key: "competitions.top_cubers", languageCode: appLanguage))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<2, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.competitionSkeletonFill)
                        .frame(width: index == 0 ? 188 : 172, height: 34)
                        .competitionSkeletonBreathing()
                }
            }
        }
    }

    private func topCuberColor(for tier: CompetitionTopCuberTier) -> Color {
        switch tier {
        case .wr:
            return .red
        case .cr:
            return .orange
        case .nr:
            return .yellow
        }
    }

    @ViewBuilder
    private func topCuberEventBadge(for badge: CompetitionTopCuberBadge) -> some View {
        let color = topCuberColor(for: badge.tier)

        if areCompetitionEventIconsReady,
           let glyph = CompetitionEventIconFont.glyph(for: badge.eventID) {
            Text(glyph)
                .font(.custom(CompetitionEventIconFont.fontName, size: 13))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(color.opacity(0.14), in: Capsule())
                .accessibilityLabel(localizedEventShortName(for: badge.eventID))
        } else {
            Text(localizedEventShortName(for: badge.eventID))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(color.opacity(0.14), in: Capsule())
        }
    }

    private func localizedEventShortName(for eventID: String) -> String {
        switch eventID {
        case "222":
            return localizedCompetitionStringInView(key: "wca.event.short.2x2", languageCode: appLanguage)
        case "333":
            return localizedCompetitionStringInView(key: "wca.event.short.3x3", languageCode: appLanguage)
        case "444":
            return localizedCompetitionStringInView(key: "wca.event.short.4x4", languageCode: appLanguage)
        case "555":
            return localizedCompetitionStringInView(key: "wca.event.short.5x5", languageCode: appLanguage)
        case "666":
            return localizedCompetitionStringInView(key: "wca.event.short.6x6", languageCode: appLanguage)
        case "777":
            return localizedCompetitionStringInView(key: "wca.event.short.7x7", languageCode: appLanguage)
        case "333oh":
            return localizedCompetitionStringInView(key: "wca.event.short.oh", languageCode: appLanguage)
        case "333bf":
            return localizedCompetitionStringInView(key: "wca.event.short.bf", languageCode: appLanguage)
        case "333fm":
            return localizedCompetitionStringInView(key: "wca.event.short.fm", languageCode: appLanguage)
        case "clock":
            return localizedCompetitionStringInView(key: "wca.event.short.clock", languageCode: appLanguage)
        case "minx":
            return localizedCompetitionStringInView(key: "wca.event.short.megaminx", languageCode: appLanguage)
        case "pyram":
            return localizedCompetitionStringInView(key: "wca.event.short.pyraminx", languageCode: appLanguage)
        case "skewb":
            return localizedCompetitionStringInView(key: "wca.event.short.skewb", languageCode: appLanguage)
        case "sq1":
            return localizedCompetitionStringInView(key: "wca.event.short.square1", languageCode: appLanguage)
        case "444bf":
            return localizedCompetitionStringInView(key: "wca.event.short.444bf", languageCode: appLanguage)
        case "555bf":
            return localizedCompetitionStringInView(key: "wca.event.short.555bf", languageCode: appLanguage)
        case "333mbf":
            return localizedCompetitionStringInView(key: "wca.event.short.mbf", languageCode: appLanguage)
        default:
            return eventID
        }
    }

    private func competitionListRow(_ competition: CompetitionSummary) -> some View {
        let usesGlassStyle = CompetitionCardStyleOption(rawValue: competitionCardStyle) == .glass

        return Button {
            selectedCompetitionForDetail = competition
        } label: {
            competitionRow(competition)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(usesGlassStyle ? .hidden : .visible)
        .listRowBackground(Color.clear)
        .onAppear {
            guard competition.id == publishedVisibleCompetitions.last?.id else { return }
            Task {
                await loadMoreCompetitionsIfNeeded()
            }
        }
    }

    private func statusBadge(for status: CompetitionAvailabilityStatus, competition: CompetitionSummary, languageCode: String) -> some View {
        let badgeColor = statusColor(for: status, competition: competition)
        return Text(statusBadgeTitle(for: status, competition: competition, languageCode: languageCode))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(badgeColor.opacity(0.12), in: Capsule())
    }

    private func statusBadgeTitle(for status: CompetitionAvailabilityStatus, competition: CompetitionSummary, languageCode: String) -> String {
        if let rowClass = cubingRowClass(for: competition) {
            switch rowClass {
            case "info":
                if let waitlistStart = competition.localizedWaitlistStartOverride, Date() < waitlistStart {
                    let days = daysUntil(waitlistStart)
                    return String(
                        format: localizedCompetitionStringInView(
                            key: "competitions.status.waitlist_in_format",
                            languageCode: languageCode
                        ),
                        days
                    )
                }
                return CompetitionAvailabilityStatus.upcoming.localizedTitle(languageCode: languageCode)
            case "danger":
                if let waitlistStart = competition.localizedWaitlistStartOverride, Date() >= waitlistStart {
                    return localizedCompetitionStringInView(
                        key: "competitions.status.waitlist_open",
                        languageCode: languageCode
                    )
                }
                return CompetitionAvailabilityStatus.registrationOpen.localizedTitle(languageCode: languageCode)
            default:
                break
            }
        }

        switch status {
        case .registrationNotOpenYet:
            let days = daysUntil(competition.localizedRegistrationStartOverride)
            return String(
                format: localizedCompetitionStringInView(
                    key: "competitions.status.registration_not_open_yet_in_format",
                    languageCode: languageCode
                ),
                days
            )
        case .upcoming:
            if let waitlistStart = competition.localizedWaitlistStartOverride, Date() < waitlistStart {
                let days = daysUntil(waitlistStart)
                return String(
                    format: localizedCompetitionStringInView(
                        key: "competitions.status.waitlist_in_format",
                        languageCode: languageCode
                    ),
                    days
                )
            }
            return status.localizedTitle(languageCode: languageCode)
        case .waitlist:
            if let waitlistStart = competition.localizedWaitlistStartOverride, Date() < waitlistStart {
                let days = daysUntil(waitlistStart)
                return String(
                    format: localizedCompetitionStringInView(
                        key: "competitions.status.waitlist_in_format",
                        languageCode: languageCode
                        ),
                        days
                    )
                }
            return localizedCompetitionStringInView(
                key: "competitions.status.waitlist_open",
                languageCode: languageCode
            )
        default:
            return status.localizedTitle(languageCode: languageCode)
        }
    }

    private func daysUntil(_ date: Date?) -> Int {
        guard let date else { return 0 }
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return max(calendar.dateComponents([.day], from: now, to: target).day ?? 0, 0)
    }

    private func daysUntil(_ date: Date) -> Int {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return max(calendar.dateComponents([.day], from: now, to: target).day ?? 0, 0)
    }

    private func statusColor(for status: CompetitionAvailabilityStatus, competition: CompetitionSummary) -> Color {
        if let rowClass = cubingRowClass(for: competition) {
            switch rowClass {
            case "info":
                if let waitlistStart = competition.localizedWaitlistStartOverride, Date() < waitlistStart {
                    return .teal
                }
                return .orange
            case "danger":
                if let waitlistStart = competition.localizedWaitlistStartOverride, Date() >= waitlistStart {
                    return .teal
                }
                return .green
            default:
                break
            }
        }

        if status == .waitlist {
            if let waitlistStart = competition.localizedWaitlistStartOverride, Date() < waitlistStart {
                return .teal
            }
            return .teal
        }

        return statusColor(for: status)
    }

    private func competitionAvailabilityStatus(for competition: CompetitionSummary) -> CompetitionAvailabilityStatus {
        if let localizedStatusOverride = competition.localizedStatusOverride {
            return localizedStatusOverride
        }

        let now = Date()
        let today = Calendar.current.startOfDay(for: now)

        if competition.endDate < today {
            return .ended
        }

        let startOfCompetition = Calendar.current.startOfDay(for: competition.startDate)
        let endOfCompetition = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: competition.endDate))
            ?? competition.endDate
        if now >= startOfCompetition && now < endOfCompetition {
            return .ongoing
        }

        if let open = competition.registrationOpen,
           let close = competition.registrationClose,
           open <= now && close >= now {
            return .registrationOpen
        }

        return .upcoming
    }

    private func statusColor(for status: CompetitionAvailabilityStatus) -> Color {
        switch status {
        case .upcoming:
            return .orange
        case .registrationNotOpenYet:
            return .yellow
        case .registrationOpen:
            return .green
        case .waitlist:
            return .mint
        case .ongoing:
            return .blue
        case .ended:
            return .secondary
        }
    }

    private func isCancellationLikeError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }

        let lowered = nsError.localizedDescription.lowercased()
        return lowered.contains("cancelled")
    }

    private func isTimeoutLikeError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
            return true
        }
        return nsError.localizedDescription.lowercased().contains("timed out")
    }

    private func competitionListErrorMessage(for error: Error) -> String {
        if isTimeoutLikeError(error) {
            return localizedCompetitionStringInView(key: "competitions.error_timed_out", languageCode: appLanguage)
        }
        return localizedCompetitionStringInView(key: "competitions.error_request_failed", languageCode: appLanguage)
    }

    @MainActor
    private func loadCompetitions() async {
        let query = competitionQuery
        let expectedSignature = filterSignature
        errorMessage = nil

        if competitions.isEmpty,
           let runtimeSnapshot = CompetitionListRuntimeCache.shared.snapshot(for: expectedSignature) {
            restoreCompetitionRuntimeSnapshot(runtimeSnapshot)
            return
        }

        let cachedSnapshot = await CompetitionService.cachedCompetitions(for: query)
        let localizedCachedCompetitions = await CompetitionService.localizeCompetitionNamesIfNeeded(
            cachedSnapshot?.competitions ?? [],
            languageCode: appLanguage
        )
        competitions = uniqueCompetitions(localizedCachedCompetitions)
        syncVisibleCompetitionsSnapshot(query: query)
        publishVisibleCompetitionsSnapshot()
        nextPage = nil
        isLoading = publishedVisibleCompetitions.isEmpty
        isLoadingMore = false
        storeCompetitionRuntimeSnapshot(signature: expectedSignature)

        if publishedVisibleCompetitions.isEmpty {
            do {
                try await loadMoreCompetitions(minimumVisibleCount: 1, replaceExisting: true)
                isLoading = false
                storeCompetitionRuntimeSnapshot(signature: expectedSignature)

                if nextPage != nil {
                    Task {
                        await prefetchRemainingCompetitions(for: query, expectedSignature: expectedSignature)
                    }
                } else {
                    await CompetitionService.cacheCompetitions(
                        competitions,
                        totalCount: competitions.count,
                        for: query
                    )
                }
                return
            } catch {
                if isCancellationLikeError(error) {
                    return
                }
                competitions = []
                errorMessage = competitionListErrorMessage(for: error)
                isLoading = false
                isLoadingMore = false
                return
            }
        }

        isLoading = false
        isLoadingMore = false

        do {
            try await refreshFirstCompetitionPageFromNetwork(
                for: query,
                expectedSignature: expectedSignature,
                cachedCompetitions: competitions
            )
        } catch {
            if isCancellationLikeError(error) {
                return
            }
            if publishedVisibleCompetitions.isEmpty {
                competitions = []
                visibleCompetitionsSnapshot = []
                publishedVisibleCompetitions = []
                errorMessage = competitionListErrorMessage(for: error)
            }
        }

        if nextPage != nil {
            Task {
                await prefetchRemainingCompetitions(for: query, expectedSignature: expectedSignature)
            }
        }
    }

    @MainActor
    private func refreshCompetitionsForPullToRefresh() async {
        let query = competitionQuery
        let expectedSignature = filterSignature
        let hadVisibleCompetitions = !competitions.isEmpty

        errorMessage = nil

        do {
            var aggregated: [CompetitionSummary] = []
            var pageToFetch: Int? = 1
            var totalCount: Int?
            var visibleCompetitions: [CompetitionSummary] = []

            while let page = pageToFetch {
                let result = try await CompetitionService.fetchCompetitionsPage(query: query, page: page)

                aggregated = uniqueCompetitions(aggregated + result.competitions)
                visibleCompetitions = normalizedVisibleCompetitions(aggregated, query: query)
                pageToFetch = result.nextPage
                totalCount = result.totalCount ?? totalCount

                if hadVisibleCompetitions || !visibleCompetitions.isEmpty || result.nextPage == nil {
                    break
                }
            }

            guard expectedSignature == filterSignature else { return }

            if !visibleCompetitions.isEmpty || publishedVisibleCompetitions.isEmpty {
                competitions = uniqueCompetitions(aggregated)
                visibleCompetitionsSnapshot = uniqueCompetitions(visibleCompetitions)
                publishVisibleCompetitionsSnapshot()
            }
            nextPage = pageToFetch
            isLoading = false
            isLoadingMore = false
            storeCompetitionRuntimeSnapshot(signature: expectedSignature)

            announceRefreshSuccess()

            if let totalCount, pageToFetch == nil {
                await CompetitionService.cacheCompetitions(
                    competitions,
                    totalCount: totalCount,
                    for: query
                )
            }

            if pageToFetch != nil {
                Task {
                    await prefetchRemainingCompetitions(for: query, expectedSignature: expectedSignature)
                }
            }
        } catch {
            if isCancellationLikeError(error) {
                return
            }
            if publishedVisibleCompetitions.isEmpty {
                errorMessage = competitionListErrorMessage(for: error)
            }
            isLoading = false
            isLoadingMore = false
        }
    }

    @MainActor
    private func loadMoreCompetitionsIfNeeded() async {
        guard !isLoading, !isLoadingMore, nextPage != nil, errorMessage == nil else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            try await loadMoreCompetitions(minimumVisibleCount: 1, replaceExisting: false)
        } catch {
            if isCancellationLikeError(error) {
                return
            }
            if publishedVisibleCompetitions.isEmpty {
                errorMessage = competitionListErrorMessage(for: error)
            }
        }
    }

    @MainActor
    private func loadMoreCompetitions(minimumVisibleCount: Int, replaceExisting: Bool) async throws {
        var aggregated: [CompetitionSummary] = replaceExisting ? [] : competitions
        var pageToFetch = replaceExisting ? 1 : nextPage
        let query = competitionQuery
        let targetVisibleCount = max(1, minimumVisibleCount)

        while let page = pageToFetch {
            let result = try await CompetitionService.fetchCompetitionsPage(query: query, page: page)
            aggregated = uniqueCompetitions(aggregated + result.competitions)
            pageToFetch = result.nextPage

            let visibleCompetitions = normalizedVisibleCompetitions(aggregated, query: query)
            if visibleCompetitions.count >= targetVisibleCount || result.nextPage == nil {
                break
            }
        }

        competitions = uniqueCompetitions(aggregated)
        visibleCompetitionsSnapshot = normalizedVisibleCompetitions(aggregated, query: query)
        publishVisibleCompetitionsSnapshot()
        nextPage = pageToFetch
        storeCompetitionRuntimeSnapshot()
    }

    @MainActor
    private func prefetchRemainingCompetitions(for query: CompetitionQuery, expectedSignature: String) async {
        guard expectedSignature == filterSignature else { return }
        guard !isPrefetchingRemainingCompetitions else { return }

        isPrefetchingRemainingCompetitions = true
        defer { isPrefetchingRemainingCompetitions = false }

        while let page = nextPage {
            guard expectedSignature == filterSignature else { return }

            do {
                let result = try await CompetitionService.fetchCompetitionsPage(query: query, page: page)
                competitions = uniqueCompetitions(competitions + result.competitions)
                syncVisibleCompetitionsSnapshot(query: query)
                nextPage = result.nextPage
                if !visibleCompetitionsSnapshot.isEmpty {
                    publishVisibleCompetitionsSnapshot()
                }
                storeCompetitionRuntimeSnapshot(signature: expectedSignature)

                if result.nextPage == nil {
                    if !visibleCompetitionsSnapshot.isEmpty {
                        publishVisibleCompetitionsSnapshot()
                    }
                    storeCompetitionRuntimeSnapshot(signature: expectedSignature)
                    await CompetitionService.cacheCompetitions(
                        competitions,
                        totalCount: result.totalCount ?? competitions.count,
                        for: query
                    )
                }
            } catch {
                if isCancellationLikeError(error) {
                    return
                }
                if publishedVisibleCompetitions.isEmpty {
                    errorMessage = competitionListErrorMessage(for: error)
                }
                return
            }
        }
    }

    @MainActor
    private func announceRefreshSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.snappy(duration: 0.22)) {
            showsRefreshSuccessBanner = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                withAnimation(.snappy(duration: 0.22)) {
                    showsRefreshSuccessBanner = false
                }
            }
        }
    }

    @MainActor
    private func refreshFirstCompetitionPageFromNetwork(
        for query: CompetitionQuery,
        expectedSignature: String,
        cachedCompetitions: [CompetitionSummary]
    ) async throws {
        guard expectedSignature == filterSignature else { return }

        let result = try await CompetitionService.fetchCompetitionsPage(query: query, page: 1)
        competitions = mergedCompetitions(cached: cachedCompetitions, fresh: result.competitions)
        syncVisibleCompetitionsSnapshot(query: query)
        publishVisibleCompetitionsSnapshot()
        nextPage = result.nextPage
        storeCompetitionRuntimeSnapshot(signature: expectedSignature)

        if result.nextPage == nil {
            await CompetitionService.cacheCompetitions(
                result.competitions,
                totalCount: result.totalCount ?? result.competitions.count,
                for: query
            )
        }
    }

    private func mergedCompetitions(
        cached: [CompetitionSummary],
        fresh: [CompetitionSummary]
    ) -> [CompetitionSummary] {
        uniqueCompetitions(fresh + cached)
    }

    private func uniqueCompetitions(_ competitions: [CompetitionSummary]) -> [CompetitionSummary] {
        var seenIDs = Set<String>()
        return competitions.filter { competition in
            seenIDs.insert(competition.id).inserted
        }
    }

    private func normalizedVisibleCompetitions(
        _ competitions: [CompetitionSummary],
        query: CompetitionQuery
    ) -> [CompetitionSummary] {
        let sortedCompetitions = CompetitionService.filterCompetitions(
            uniqueCompetitions(competitions),
            for: query
        )
        return uniqueCompetitions(filterCompetitionsForVisibleStatus(sortedCompetitions, query: query))
    }

    private func syncVisibleCompetitionsSnapshot(query: CompetitionQuery) {
        visibleCompetitionsSnapshot = normalizedVisibleCompetitions(competitions, query: query)
    }

    private func publishVisibleCompetitionsSnapshot() {
        let published = uniqueCompetitions(visibleCompetitionsSnapshot)
        publishedVisibleCompetitions = published
        updateCompetitionListDerivedState(for: published)
    }

    private func updateCompetitionListDerivedState(for publishedCompetitions: [CompetitionSummary]) {
        var ongoingCount = 0
        var upcomingCount = 0
        var registrationOpenCount = 0

        for competition in publishedCompetitions {
            switch competitionAvailabilityStatus(for: competition) {
            case .ongoing:
                ongoingCount += 1
            case .upcoming:
                upcomingCount += 1
            case .registrationOpen:
                registrationOpenCount += 1
            default:
                break
            }
        }

        competitionNavigationSubtitleText = [
            "\(ongoingCount) \(localizedCompetitionStringInView(key: "competitions.status.ongoing", languageCode: appLanguage))",
            "\(upcomingCount) \(localizedCompetitionStringInView(key: "competitions.status.upcoming", languageCode: appLanguage))",
            "\(registrationOpenCount) \(localizedCompetitionStringInView(key: "competitions.status.registration_open", languageCode: appLanguage))"
        ].joined(separator: " · ")

        topCuberPreloadCompetitionIDs = Array(
            publishedCompetitions
                .prefix(Self.initialTopCuberPreloadCount)
                .map(\.id)
        )
        topCuberPrefetchCompetitionIDs = Array(
            publishedCompetitions
                .dropFirst(Self.initialTopCuberPreloadCount)
                .prefix(Self.nextTopCuberPrefetchCount)
                .map(\.id)
        )
        topCubersTaskSignatureText = [
            showsTopCubers ? "on" : "off",
            appLanguage,
            (topCuberPreloadCompetitionIDs + topCuberPrefetchCompetitionIDs).joined(separator: ",")
        ].joined(separator: "|")
    }

    @MainActor
    private func restoreCompetitionRuntimeSnapshot(_ snapshot: CompetitionListRuntimeCache.Snapshot) {
        guard !snapshot.publishedVisibleCompetitions.isEmpty else { return }
        competitions = uniqueCompetitions(snapshot.competitions)
        visibleCompetitionsSnapshot = uniqueCompetitions(snapshot.visibleCompetitionsSnapshot)
        publishedVisibleCompetitions = uniqueCompetitions(snapshot.publishedVisibleCompetitions)
        updateCompetitionListDerivedState(for: publishedVisibleCompetitions)
        nextPage = snapshot.nextPage
        topCuberStatesByCompetitionID = snapshot.topCuberStatesByCompetitionID
        errorMessage = nil
        isLoading = false
        isLoadingMore = false
    }

    @MainActor
    private func storeCompetitionRuntimeSnapshot(signature: String? = nil) {
        guard !publishedVisibleCompetitions.isEmpty else { return }
        CompetitionListRuntimeCache.shared.store(
            CompetitionListRuntimeCache.Snapshot(
                competitions: uniqueCompetitions(competitions),
                visibleCompetitionsSnapshot: uniqueCompetitions(visibleCompetitionsSnapshot),
                publishedVisibleCompetitions: uniqueCompetitions(publishedVisibleCompetitions),
                nextPage: nextPage,
                topCuberStatesByCompetitionID: topCuberStatesByCompetitionID
            ),
            for: signature ?? filterSignature
        )
    }

    @MainActor
    private func loadTopCuberPreviewIfNeeded(for competition: CompetitionSummary) async {
        guard showsTopCubers else {
            topCuberStatesByCompetitionID = [:]
            topCuberRefreshingIDs = []
            return
        }

        switch topCuberStatesByCompetitionID[competition.id] ?? .idle {
        case .loading, .loaded, .empty:
            return
        case .idle, .failed:
            break
        }

        if let cached = await CompetitionService.cachedCompetitionTopCuberPreviews(for: competition.id) {
            topCuberStatesByCompetitionID[competition.id] = cached.isEmpty ? .empty : .loaded(cached)
            storeCompetitionRuntimeSnapshot()
            await refreshTopCuberPreview(for: competition, usesLoadingPlaceholder: false)
            return
        }

        await refreshTopCuberPreview(for: competition, usesLoadingPlaceholder: true)
    }

    @MainActor
    private func loadVisibleTopCuberPreviewsIfNeeded() async {
        guard showsTopCubers else {
            topCuberStatesByCompetitionID = [:]
            topCuberRefreshingIDs = []
            return
        }

        for competition in publishedVisibleCompetitions {
            if let cached = await CompetitionService.cachedCompetitionTopCuberPreviews(for: competition.id) {
                topCuberStatesByCompetitionID[competition.id] = cached.isEmpty ? .empty : .loaded(cached)
            }
        }
        storeCompetitionRuntimeSnapshot()

        let preloadIDs = Set(topCuberPreloadCompetitionIDs)
        let prefetchIDs = Set(topCuberPrefetchCompetitionIDs)

        let preloadTargets = publishedVisibleCompetitions
            .filter { preloadIDs.contains($0.id) }
            .filter { competition in !topCuberRefreshingIDs.contains(competition.id) }

        let prefetchTargets = publishedVisibleCompetitions
            .filter { prefetchIDs.contains($0.id) }
            .filter { competition in
                topCuberStatesByCompetitionID[competition.id] == nil &&
                !topCuberRefreshingIDs.contains(competition.id)
            }

        let jobs: [(competition: CompetitionSummary, usesLoadingPlaceholder: Bool)] =
            preloadTargets.map { competition in
                (
                    competition,
                    topCuberStatesByCompetitionID[competition.id] == nil
                )
            } +
            prefetchTargets.map { competition in
                (competition, false)
            }

        guard !jobs.isEmpty else { return }

        for job in jobs where job.usesLoadingPlaceholder {
            topCuberStatesByCompetitionID[job.competition.id] = .loading
        }
        for job in jobs {
            topCuberRefreshingIDs.insert(job.competition.id)
        }

        var nextIndex = 0
        await withTaskGroup(of: (String, [CompetitionTopCuberPreview]?, Bool).self) { group in
            let initialCount = min(Self.topCuberLoadConcurrency, jobs.count)

            func enqueueJob(_ job: (competition: CompetitionSummary, usesLoadingPlaceholder: Bool)) {
                group.addTask {
                    let previews = await CompetitionService.fetchCompetitionTopCuberPreviews(
                        for: job.competition,
                        languageCode: appLanguage
                    )
                    return (job.competition.id, previews, job.usesLoadingPlaceholder)
                }
            }

            while nextIndex < initialCount {
                enqueueJob(jobs[nextIndex])
                nextIndex += 1
            }

            while let (competitionID, previews, usesLoadingPlaceholder) = await group.next() {
                topCuberRefreshingIDs.remove(competitionID)

                if let previews {
                    topCuberStatesByCompetitionID[competitionID] = previews.isEmpty ? .empty : .loaded(previews)
                } else if usesLoadingPlaceholder {
                    topCuberStatesByCompetitionID[competitionID] = .failed
                }
                storeCompetitionRuntimeSnapshot()

                if nextIndex < jobs.count {
                    enqueueJob(jobs[nextIndex])
                    nextIndex += 1
                }
            }
        }
    }

    @MainActor
    private func refreshTopCuberPreview(
        for competition: CompetitionSummary,
        usesLoadingPlaceholder: Bool
    ) async {
        guard showsTopCubers else { return }
        guard !topCuberRefreshingIDs.contains(competition.id) else { return }

        topCuberRefreshingIDs.insert(competition.id)
        if usesLoadingPlaceholder {
            topCuberStatesByCompetitionID[competition.id] = .loading
        }

        defer {
            topCuberRefreshingIDs.remove(competition.id)
        }

        guard let previews = await CompetitionService.fetchCompetitionTopCuberPreviews(
            for: competition,
            languageCode: appLanguage
        ) else {
            if usesLoadingPlaceholder {
                topCuberStatesByCompetitionID[competition.id] = .failed
            }
            return
        }

        topCuberStatesByCompetitionID[competition.id] = previews.isEmpty ? .empty : .loaded(previews)
        storeCompetitionRuntimeSnapshot()
    }


    private func filterCompetitionsForVisibleStatus(
        _ competitions: [CompetitionSummary],
        query: CompetitionQuery
    ) -> [CompetitionSummary] {
        guard query.status == .registrationOpen else {
            return competitions
        }

        return competitions.filter { competition in
            guard cubingRowClass(for: competition) == "info",
                  let waitlistStart = competition.localizedWaitlistStartOverride else {
                return true
            }

            return Date() >= waitlistStart
        }
    }

    private func localizedCompetitionDateRange(for competition: CompetitionSummary) -> String {
        let locale = appLocale(for: appLanguage)
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar

        let sameYear = calendar.component(.year, from: competition.startDate) == calendar.component(.year, from: competition.endDate)
        let sameMonth = sameYear && calendar.component(.month, from: competition.startDate) == calendar.component(.month, from: competition.endDate)
        let sameDay = sameMonth && calendar.component(.day, from: competition.startDate) == calendar.component(.day, from: competition.endDate)

        formatter.dateFormat = localizedCompetitionStringInView(key: "competition.date.full_format", languageCode: appLanguage)
        if sameDay {
            return formatter.string(from: competition.startDate)
        }
        if sameMonth {
            let monthFormatter = DateFormatter()
            monthFormatter.locale = locale
            monthFormatter.calendar = calendar
            monthFormatter.dateFormat = localizedCompetitionStringInView(key: "competition.date.month_day_format", languageCode: appLanguage)
            let start = monthFormatter.string(from: competition.startDate)
            formatter.dateFormat = localizedCompetitionStringInView(key: "competition.date.day_suffix_format", languageCode: appLanguage)
            return "\(start) - \(formatter.string(from: competition.endDate))"
        }
        return "\(formatter.string(from: competition.startDate)) - \(formatter.string(from: competition.endDate))"
    }

    private func cubingRowClass(for competition: CompetitionSummary) -> String? {
        let keys = [
            normalizeCompetitionLookupKeyForUI(competition.id),
            normalizeCompetitionLookupKeyForUI(competition.website ?? ""),
            normalizeCompetitionLookupKeyForUI(competition.name)
        ]

        for key in keys where !key.isEmpty {
            if let value = cubingRowClassesByKey[key] {
                return value
            }
        }
        return nil
    }

    private func fetchCubingRowClasses(languageCode: String) async -> [String: String] {
        let cubingLanguage = cubingLanguageCode(for: languageCode)
        guard let url = URL(string: "https://cubing.com/competition?lang=\(cubingLanguage)&year=&type=WCA&province=&event=") else {
            return [:]
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(appAcceptLanguageHeader(for: languageCode), forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode,
              let html = String(data: data, encoding: .utf8) else {
            return [:]
        }

        let pattern = #"(?s)<tr[^>]*class=\"([^\"]+)\"[^>]*>\s*<td[^>]*>.*?</td>\s*<td[^>]*>\s*<a[^>]*class="comp-type-wca"[^>]*href="(?:https://cubing\.com)?/(?:competition|live)/([^"]+)"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [:]
        }

        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)
        var mapping: [String: String] = [:]

        regex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 4 else { return }
            let rowClass = cleanCompetitionHTMLTextForUI(nsHTML.substring(with: match.range(at: 1))).lowercased()
            let slug = nsHTML.substring(with: match.range(at: 2))
            let titleHTML = nsHTML.substring(with: match.range(at: 3))
            let localizedName = cleanCompetitionHTMLTextForUI(titleHTML)

            let slugKey = normalizeCompetitionLookupKeyForUI(slug)
            if !slugKey.isEmpty, !rowClass.isEmpty {
                mapping[slugKey] = rowClass
            }

            let nameKey = normalizeCompetitionLookupKeyForUI(localizedName)
            if !nameKey.isEmpty, !rowClass.isEmpty {
                mapping[nameKey] = rowClass
            }
        }

        return mapping
    }

    private func cleanCompetitionHTMLTextForUI(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"&nbsp;"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeCompetitionLookupKeyForUI(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"^https?://www\.worldcubeassociation\.org/competitions/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^/competitions/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^https?://cubing\.com/competition/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^/competition/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^https?://cubing\.com/live/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^/live/"#, with: "", options: .regularExpression)
            .components(separatedBy: "/").first ?? value
            .components(separatedBy: "?").first ?? value
            .components(separatedBy: "#").first ?? value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "", options: .regularExpression)
            .lowercased()
    }
}

struct CompetitionBottomSearchBar: View {
    let languageCode: String
    let usesContainerGlass: Bool
    let searchAction: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        Button(action: searchAction) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                Text(localizedCompetitionStringInView(key: "competitions.search_placeholder", languageCode: languageCode))
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .background(
            shape
                .fill(.black.opacity(0.001))
        )
        .contentShape(shape)
        .modifier(CompetitionBottomSearchBarGlassModifier(isEnabled: usesContainerGlass, shape: shape))
    }
}

private struct CompetitionBottomSearchBarGlassModifier: ViewModifier {
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

private struct CompetitionNavigationSubtitleModifier: ViewModifier {
    let subtitle: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), let subtitle, !subtitle.isEmpty {
            content.navigationSubtitle(Text(subtitle))
        } else {
            content
        }
    }
}

enum CompetitionDetailTabKind: Hashable {
    case info
    case rules
    case register
    case competitors
    case schedule
    case events
    case travel
    case live
    case custom(String)
}

struct CompetitionDetailTab: Identifiable, Hashable {
    let kind: CompetitionDetailTabKind
    let titleOverride: String?

    static func == (lhs: CompetitionDetailTab, rhs: CompetitionDetailTab) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }

    static let info = CompetitionDetailTab(kind: .info)
    static let rules = CompetitionDetailTab(kind: .rules)
    static let register = CompetitionDetailTab(kind: .register)
    static let competitors = CompetitionDetailTab(kind: .competitors)
    static let schedule = CompetitionDetailTab(kind: .schedule)
    static let events = CompetitionDetailTab(kind: .events)
    static let travel = CompetitionDetailTab(kind: .travel)
    static let live = CompetitionDetailTab(kind: .live)

    static let standardCases: [CompetitionDetailTab] = [.info, .register, .competitors, .schedule, .live]

    init(kind: CompetitionDetailTabKind, titleOverride: String? = nil) {
        self.kind = kind
        self.titleOverride = titleOverride
    }

    static func custom(id: String, title: String) -> CompetitionDetailTab {
        CompetitionDetailTab(kind: .custom(id), titleOverride: title)
    }

    func titled(_ title: String?) -> CompetitionDetailTab {
        CompetitionDetailTab(kind: kind, titleOverride: title)
    }

    var id: String { rawValue }

    var rawValue: String {
        switch kind {
        case .info: return "info"
        case .rules: return "rules"
        case .register: return "register"
        case .competitors: return "competitors"
        case .schedule: return "schedule"
        case .events: return "events"
        case .travel: return "travel"
        case .live: return "live"
        case .custom(let id): return "custom-\(id)"
        }
    }

    func localizedTitle(languageCode: String) -> String {
        if let titleOverride, !titleOverride.isEmpty {
            return titleOverride
        }

        switch kind {
        case .info:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.info", languageCode: languageCode)
        case .rules:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.rules", languageCode: languageCode)
        case .register:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.register", languageCode: languageCode)
        case .competitors:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.competitors", languageCode: languageCode)
        case .schedule:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.schedule", languageCode: languageCode)
        case .events:
            return localizedCompetitionStringInView(key: "competitions.detail.section.events", languageCode: languageCode)
        case .travel:
            return localizedCompetitionStringInView(key: "competitions.detail.section.travel", languageCode: languageCode)
        case .live:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.live", languageCode: languageCode)
        case .custom:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.info", languageCode: languageCode)
        }
    }
}

struct CompetitionDetailTabStrip: View {
    let tabs: [CompetitionDetailTab]
    let languageCode: String
    @Binding var selection: CompetitionDetailTab

    @State private var tabWidths: [String: CGFloat] = [:]
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var pressedTab: CompetitionDetailTab?

    private let spacing: CGFloat = 8
    private let horizontalPadding: CGFloat = 6
    private let labelHorizontalPadding: CGFloat = 14
    private let selectedHeight: CGFloat = 34

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .leading) {
                selectionIndicator
                    .zIndex(0)

                tabLabelsLayer
                    .zIndex(1)

                dragOverlay
                    .zIndex(2)
            }
            .onPreferenceChange(CompetitionTabWidthPreferenceKey.self) { widths in
                let cleanedWidths = widths.filter { $0.value.isFinite && $0.value > 0 }
                guard !cleanedWidths.isApproximatelyEqual(to: tabWidths) else { return }
                DispatchQueue.main.async {
                    guard !cleanedWidths.isApproximatelyEqual(to: tabWidths) else { return }
                    tabWidths = cleanedWidths
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 48)
    }

    private var selectionIndicator: some View {
        Capsule()
            .fill(Color.primary.opacity(isDragging ? 0.12 : 0.08))
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.6)
            }
            .compatibleGlassFromIOS16(in: Capsule())
            .frame(width: selectedWidth, height: selectedHeight)
            .scaleEffect(isDragging ? 1.04 : 1.0)
            .offset(x: clampedIndicatorOffset)
            .shadow(color: .black.opacity(0.08), radius: isDragging ? 10 : 6, y: 3)
            .animation(.spring(response: 0.32, dampingFraction: 0.76), value: selection)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isDragging)
            .allowsHitTesting(false)
    }

    private var tabLabelsLayer: some View {
        HStack(spacing: spacing) {
            ForEach(tabs) { tab in
                tabLabel(for: tab)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 5)
    }

    private func tabLabel(for tab: CompetitionDetailTab) -> some View {
        Text(tab.localizedTitle(languageCode: languageCode))
            .font(.system(size: 15, weight: fontWeight(for: tab)))
            .foregroundStyle(foregroundStyle(for: tab))
            .lineLimit(1)
            .padding(.horizontal, labelHorizontalPadding)
            .padding(.vertical, 9)
            .scaleEffect(pressedTab == tab ? 0.97 : 1.0)
            .contentShape(Rectangle())
            .modifier(CompetitionDetailTabMeasurementModifier(tabID: tab.id))
            .onTapGesture {
                pressThenSelect(tab)
            }
            .animation(.spring(response: 0.18, dampingFraction: 0.78), value: pressedTab)
    }

    private var dragOverlay: some View {
        Color.clear
            .frame(width: selectedWidth, height: selectedHeight)
            .contentShape(Capsule())
            .offset(x: selectedBaseOffset, y: 5)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        pressedTab = selection
                        dragOffset = gesture.translation.width
                    }
                    .onEnded { gesture in
                        snapToNearestTab(dragDistance: gesture.translation.width)
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                            dragOffset = 0
                            isDragging = false
                            pressedTab = nil
                        }
                    }
            )
    }

    private var selectedWidth: CGFloat {
        max(width(for: selection), 44)
    }

    private var selectedBaseOffset: CGFloat {
        offset(for: selection)
    }

    private var clampedIndicatorOffset: CGFloat {
        let proposed = selectedBaseOffset + dragOffset
        let maximum = max(horizontalPadding, totalTabsWidth - selectedWidth + horizontalPadding)
        return min(max(proposed, horizontalPadding), maximum)
    }

    private var totalTabsWidth: CGFloat {
        tabs.reduce(CGFloat(0)) { partial, tab in
            partial + width(for: tab)
        } + CGFloat(max(tabs.count - 1, 0)) * spacing
    }

    private func width(for tab: CompetitionDetailTab) -> CGFloat {
        tabWidths[tab.id] ?? fallbackWidth(for: tab)
    }

    private func offset(for tab: CompetitionDetailTab) -> CGFloat {
        guard let index = tabs.firstIndex(of: tab) else { return horizontalPadding }
        let previousWidths = tabs.prefix(index).reduce(CGFloat(0)) { partial, tab in
            partial + width(for: tab)
        }
        return horizontalPadding + previousWidths + CGFloat(index) * spacing
    }

    private func fallbackWidth(for tab: CompetitionDetailTab) -> CGFloat {
        let title = tab.localizedTitle(languageCode: languageCode)
        return max(CGFloat(title.count) * 8.5 + labelHorizontalPadding * 2, 54)
    }

    private func fontWeight(for tab: CompetitionDetailTab) -> Font.Weight {
        selection == tab ? .semibold : .regular
    }

    private func foregroundStyle(for tab: CompetitionDetailTab) -> Color {
        selection == tab ? .primary : .secondary
    }

    private func pressThenSelect(_ tab: CompetitionDetailTab) {
        withAnimation(.spring(response: 0.16, dampingFraction: 0.74)) {
            pressedTab = tab
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            select(tab)
            withAnimation(.spring(response: 0.20, dampingFraction: 0.84)) {
                pressedTab = nil
            }
        }
    }

    private func select(_ tab: CompetitionDetailTab) {
        guard selection != tab else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
            selection = tab
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func snapToNearestTab(dragDistance: CGFloat) {
        let proposedCenter = selectedBaseOffset + dragDistance + selectedWidth / 2
        let nearest = tabs.min { lhs, rhs in
            let lhsDistance = abs((offset(for: lhs) + width(for: lhs) / 2) - proposedCenter)
            let rhsDistance = abs((offset(for: rhs) + width(for: rhs) / 2) - proposedCenter)
            return lhsDistance < rhsDistance
        }

        if let nearest {
            select(nearest)
        }
    }
}

private struct CompetitionTabWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private extension Dictionary where Key == String, Value == CGFloat {
    func isApproximatelyEqual(to other: [String: CGFloat]) -> Bool {
        guard count == other.count else { return false }
        return allSatisfy { entry in
            guard let otherValue = other[entry.key] else { return false }
            return abs(entry.value - otherValue) < 0.5
        }
    }
}

private struct CompetitionDetailTabMeasurementModifier: ViewModifier {
    let tabID: String

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CompetitionTabWidthPreferenceKey.self,
                    value: [tabID: proxy.size.width]
                )
            }
        )
    }
}

private enum CompetitionCompetitorsMode: String, CaseIterable, Identifiable {
    case registration
    case psych

    var id: String { rawValue }

    func localizedTitle(languageCode: String) -> String {
        switch self {
        case .registration:
            return localizedCompetitionStringInView(key: "competitions.detail.competitors_mode.registration", languageCode: languageCode)
        case .psych:
            return localizedCompetitionStringInView(key: "competitions.detail.competitors_mode.psych", languageCode: languageCode)
        }
    }
}

private struct CompetitionLiveResultRow: Identifiable, Hashable {
    let id: String
    let rankText: String
    let numberText: String
    let name: String
    let bestResultText: String
    let averageResultText: String?
    let regionText: String?
    let detailText: String?
}

private struct CompetitionLiveChatEntry: Identifiable, Hashable {
    let id: String
    let author: String
    let timestamp: Int
    let body: String
    let linkURL: URL?
    let isResult: Bool
}

@MainActor
private final class CompetitionCubingLiveSession: ObservableObject {
    @Published var selectedRoundOptionID: String = ""
    @Published var selectedFilterValue: String = "all"
    @Published var onlineNumber: Int = 0
    @Published var resultRows: [CompetitionLiveResultRow] = []
    @Published var chatEntries: [CompetitionLiveChatEntry] = []
    @Published var isLoadingResults = false
    @Published var isLoadingMessages = false
    @Published var connectionError: String?
    @Published var showsMessagesInChat = true
    @Published var showsResultsInChat = true

    private struct LiveUser {
        let name: String
        let region: String?
    }

    private let session = URLSession(configuration: .default)
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var content: CompetitionLiveContent?
    private var usersByNumber: [Int: LiveUser] = [:]
    private var latestRawResults: [[String: Any]] = []
    private var liveStaticEntries: [CompetitionLiveChatEntry] = []
    private var liveMessageEntries: [CompetitionLiveChatEntry] = []
    private var hasFetchedMessages = false

    var staticChatEntries: [CompetitionLiveChatEntry] {
        liveStaticEntries.sorted { lhs, rhs in lhs.timestamp < rhs.timestamp }
    }

    var recentChatEntries: [CompetitionLiveChatEntry] {
        liveMessageEntries.sorted { lhs, rhs in lhs.timestamp < rhs.timestamp }
    }

    func configure(with content: CompetitionLiveContent) {
        let isNewCompetition = self.content?.competitionID != content.competitionID
        self.content = content

        if isNewCompetition {
            selectedRoundOptionID = "\(content.defaultEventID)|\(content.defaultRoundID)"
            selectedFilterValue = content.defaultFilterValue
            usersByNumber = [:]
            latestRawResults = []
            onlineNumber = 0
            resultRows = []
            connectionError = nil
            hasFetchedMessages = false
            liveStaticEntries = content.staticMessages.map {
                CompetitionLiveChatEntry(
                    id: "static-\($0.id)",
                    author: $0.author,
                    timestamp: $0.timestamp,
                    body: $0.text,
                    linkURL: $0.linkURL,
                    isResult: false
                )
            }
            liveMessageEntries = []
            rebuildChatEntries()
        } else {
            if !content.roundOptions.contains(where: { $0.id == selectedRoundOptionID }) {
                selectedRoundOptionID = "\(content.defaultEventID)|\(content.defaultRoundID)"
            }
            if !content.filterOptions.contains(where: { $0.id == selectedFilterValue }) {
                selectedFilterValue = content.defaultFilterValue
            }
            liveStaticEntries = content.staticMessages.map {
                CompetitionLiveChatEntry(
                    id: "static-\($0.id)",
                    author: $0.author,
                    timestamp: $0.timestamp,
                    body: $0.text,
                    linkURL: $0.linkURL,
                    isResult: false
                )
            }
            rebuildChatEntries()
        }
    }

    func start() {
        guard receiveTask == nil else {
            Task {
                await fetchResults()
                await fetchMessagesIfNeeded(force: false)
            }
            return
        }

        guard let url = URL(string: "wss://cubing.com/ws") else { return }
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop(task: task)
        }

        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 150_000_000)
            await self.sendCompetitionSubscription()
            await self.fetchResults()
            await self.fetchMessagesIfNeeded(force: true)
        }
    }

    func stop() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    func selectionDidChange() {
        Task { [weak self] in
            guard let self else { return }
            await self.fetchResults()
        }
    }

    func messagesPreferenceDidChange() {
        Task { [weak self] in
            guard let self else { return }
            await self.fetchMessagesIfNeeded(force: false)
        }
    }

    var currentRoundOption: CompetitionLiveRoundOption? {
        content?.roundOptions.first(where: { $0.id == selectedRoundOptionID })
    }

    private func sendCompetitionSubscription() async {
        guard let competitionID = content?.competitionID else { return }
        await send([
            "type": "competition",
            "competitionId": competitionID
        ])
    }

    private func fetchResults() async {
        guard let round = currentRoundOption else { return }
        isLoadingResults = true
        await send([
            "type": "result",
            "action": "fetch",
            "params": [
                "event": round.eventID,
                "round": round.roundID,
                "filter": selectedFilterValue
            ]
        ])
    }

    private func fetchMessagesIfNeeded(force: Bool) async {
        guard showsMessagesInChat else {
            rebuildChatEntries()
            return
        }
        guard force || !hasFetchedMessages else { return }
        hasFetchedMessages = true
        isLoadingMessages = true
        await send([
            "type": "chat",
            "action": "fetch"
        ])
    }

    private func send(_ object: [String: Any]) async {
        guard let task = webSocketTask,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        do {
            try await task.send(.string(text))
        } catch {
            connectionError = error.localizedDescription
        }
    }

    private func receiveLoop(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                let payloadText: String
                switch message {
                case .string(let string):
                    payloadText = string
                case .data(let data):
                    payloadText = String(data: data, encoding: .utf8) ?? ""
                @unknown default:
                    payloadText = ""
                }

                if payloadText.isEmpty { continue }
                handleIncomingMessage(payloadText)
            } catch {
                if Task.isCancelled { return }
                connectionError = error.localizedDescription
                isLoadingResults = false
                isLoadingMessages = false
                return
            }
        }
    }

    private func handleIncomingMessage(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else {
            return
        }

        if let onlineNumber = json["onlineNumber"] as? Int {
            self.onlineNumber = onlineNumber
        }

        switch type {
        case "users":
            handleUsers(json["data"])
            rebuildResultRows()

        case "result.all":
            latestRawResults = (json["data"] as? [[String: Any]]) ?? []
            isLoadingResults = false
            rebuildResultRows()

        case "message.recent":
            handleRecentMessages(json["data"])

        case "message.new":
            if let entry = makeChatEntry(from: json["data"], fallbackIDPrefix: "live-message") {
                liveMessageEntries.append(entry)
                rebuildChatEntries()
            }

        case "result.new", "result.update":
            if showsResultsInChat, let entry = makeResultChatEntry(from: json["data"]) {
                liveMessageEntries.append(entry)
                rebuildChatEntries()
            }
            if let result = json["data"] as? [String: Any],
               currentRoundMatches(result: result) {
                replaceOrAppendResult(result)
                rebuildResultRows()
            }

        default:
            break
        }
    }

    private func handleUsers(_ payload: Any?) {
        guard let dictionary = payload as? [String: Any] else { return }
        var users: [Int: LiveUser] = [:]
        for (_, value) in dictionary {
            guard let user = value as? [String: Any],
                  let number = user["number"] as? Int else {
                continue
            }
            users[number] = LiveUser(
                name: user["name"] as? String ?? "",
                region: user["region"] as? String
            )
        }
        usersByNumber = users
    }

    private func handleRecentMessages(_ payload: Any?) {
        let entries = (payload as? [Any] ?? []).compactMap {
            makeChatEntry(from: $0, fallbackIDPrefix: "recent-message")
        }
        liveMessageEntries = entries
        isLoadingMessages = false
        rebuildChatEntries()
    }

    private func rebuildChatEntries() {
        chatEntries = showsMessagesInChat
            ? (staticChatEntries + recentChatEntries)
            : []
    }

    private func rebuildResultRows() {
        guard let round = currentRoundOption else {
            resultRows = []
            return
        }

        let sortedResults = latestRawResults.sorted { lhs, rhs in
            compareLiveResults(lhs, rhs, for: round)
        }

        let rankValues = sortedResults.map { result in
            rankMetric(for: result, round: round)
        }

        var rows: [CompetitionLiveResultRow] = []
        var lastMetric: (Int, Int)?
        var lastRank = 0

        for (index, result) in sortedResults.enumerated() {
            let metric = rankValues[index]
            let rankText: String
            if metric == nil {
                rankText = "—"
            } else if let lastMetric, let metric, metric == lastMetric {
                rankText = "\(lastRank)"
            } else {
                lastRank = index + 1
                rankText = "\(lastRank)"
            }
            lastMetric = metric

            let number = result["n"] as? Int ?? 0
            let user = usersByNumber[number]
            let name = user?.name ?? "\(number)"
            let best = result["b"] as? Int ?? 0
            let average = result["a"] as? Int ?? 0
            let attempts = result["v"] as? [Int] ?? []

            let bestText = formatCompetitionLiveResultValue(best, eventID: round.eventID)
            let averageText = formatCompetitionLiveResultValue(average, eventID: round.eventID)

            rows.append(
                CompetitionLiveResultRow(
                    id: "\(result["i"] as? Int ?? index)",
                    rankText: rankText,
                    numberText: number > 0 ? "\(number)" : "—",
                    name: name,
                    bestResultText: bestText,
                    averageResultText: averageText.isEmpty ? nil : averageText,
                    regionText: user?.region,
                    detailText: attempts.isEmpty ? nil : attempts
                        .map { formatCompetitionLiveResultValue($0, eventID: round.eventID) }
                        .filter { !$0.isEmpty }
                        .joined(separator: "  ")
                )
            )
        }

        resultRows = rows
    }

    private func replaceOrAppendResult(_ result: [String: Any]) {
        let resultID = result["i"] as? Int
        if let resultID,
           let index = latestRawResults.firstIndex(where: { ($0["i"] as? Int) == resultID }) {
            latestRawResults[index] = result
        } else {
            latestRawResults.append(result)
        }
    }

    private func currentRoundMatches(result: [String: Any]) -> Bool {
        guard let round = currentRoundOption else { return false }
        return (result["e"] as? String) == round.eventID
            && (result["r"] as? String) == round.roundID
    }

    private func compareLiveResults(_ lhs: [String: Any], _ rhs: [String: Any], for round: CompetitionLiveRoundOption) -> Bool {
        let lhsMetric = rankMetric(for: lhs, round: round)
        let rhsMetric = rankMetric(for: rhs, round: round)

        switch (lhsMetric, rhsMetric) {
        case let (lhs?, rhs?):
            if lhs != rhs { return lhs < rhs }
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            break
        }

        let lhsNumber = lhs["n"] as? Int ?? .max
        let rhsNumber = rhs["n"] as? Int ?? .max
        return lhsNumber < rhsNumber
    }

    private func rankMetric(for result: [String: Any], round: CompetitionLiveRoundOption) -> (Int, Int)? {
        let best = result["b"] as? Int ?? 0
        let average = result["a"] as? Int ?? 0

        if usesCompetitionLiveAverage(formatID: round.formatID) {
            if average > 0 { return (average, best > 0 ? best : .max) }
            if best > 0 { return (Int.max - 1, best) }
            return nil
        }

        if best > 0 { return (best, average > 0 ? average : .max) }
        if average > 0 { return (average, .max) }
        return nil
    }

    private func makeChatEntry(from payload: Any?, fallbackIDPrefix: String) -> CompetitionLiveChatEntry? {
        guard let dictionary = payload as? [String: Any] else { return nil }
        let user = dictionary["user"] as? [String: Any]
        let rawContent = dictionary["content"] as? String ?? ""
        let body = competitionLiveDecodeHTMLEntities(rawContent)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: NSString.CompareOptions.regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: NSString.CompareOptions.regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        let identifier = (dictionary["id"] as? String).flatMap { "\($0)-\(dictionary["time"] as? Int ?? 0)" } ?? "\(fallbackIDPrefix)-\(UUID().uuidString)"
        let linkURL = competitionLiveFirstCapture(
            in: rawContent,
            pattern: #"href=\"([^\"]+)\""#
        ).flatMap(URL.init(string:))

        return CompetitionLiveChatEntry(
            id: identifier,
            author: user?["name"] as? String ?? "System",
            timestamp: dictionary["time"] as? Int ?? 0,
            body: body,
            linkURL: linkURL,
            isResult: false
        )
    }

    private func makeResultChatEntry(from payload: Any?) -> CompetitionLiveChatEntry? {
        guard let dictionary = payload as? [String: Any] else { return nil }
        let number = dictionary["n"] as? Int ?? 0
        let round = currentRoundOption
        let eventID = dictionary["e"] as? String ?? round?.eventID ?? ""
        let best = dictionary["b"] as? Int ?? 0
        let average = dictionary["a"] as? Int ?? 0
        let user = usersByNumber[number]
        let resultText = usesCompetitionLiveAverage(formatID: round?.formatID ?? "")
            ? formatCompetitionLiveResultValue(average, eventID: eventID)
            : formatCompetitionLiveResultValue(best, eventID: eventID)
        guard !resultText.isEmpty else { return nil }

        return CompetitionLiveChatEntry(
            id: "result-\(dictionary["i"] as? Int ?? Int.random(in: 1...999999))",
            author: "System",
            timestamp: Int(Date().timeIntervalSince1970),
            body: "\(user?.name ?? "\(number)") · \(resultText)",
            linkURL: nil,
            isResult: true
        )
    }
}

nonisolated private func competitionLiveFirstCapture(in text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
        return nil
    }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          match.numberOfRanges > 1,
          let captureRange = Range(match.range(at: 1), in: text) else {
        return nil
    }
    return String(text[captureRange])
}

nonisolated private func competitionLiveDecodeHTMLEntities(_ text: String) -> String {
    let replacements: [(String, String)] = [
        ("&quot;", "\""),
        ("&#34;", "\""),
        ("&apos;", "'"),
        ("&#39;", "'"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&amp;", "&"),
        ("&nbsp;", " ")
    ]

    var value = text
    for (source, target) in replacements {
        value = value.replacingOccurrences(of: source, with: target)
    }
    return value
}

private func usesCompetitionLiveAverage(formatID: String) -> Bool {
    formatID == "a" || formatID == "m"
}

private func formatCompetitionLiveResultValue(_ value: Int, eventID: String) -> String {
    guard value != 0 else { return "" }
    if value == -1 { return "DNF" }
    if value == -2 { return "DNS" }

    switch eventID {
    case "333fm":
        return value > 1000 ? String(format: "%.2f", Double(value) / 100.0) : "\(value)"
    case "333mbf":
        return "\(value)"
    default:
        let minutes = value / 6000
        let seconds = (value % 6000) / 100
        let hundredths = value % 100
        if minutes > 0 {
            return String(format: "%d:%02d.%02d", minutes, seconds, hundredths)
        }
        return String(format: "%d.%02d", seconds, hundredths)
    }
}

private func secondaryCompetitionLiveResultText(best: Int, average: Int, eventID: String) -> String? {
    let bestText = formatCompetitionLiveResultValue(best, eventID: eventID)
    let averageText = formatCompetitionLiveResultValue(average, eventID: eventID)

    if !averageText.isEmpty && !bestText.isEmpty {
        return "\(bestText) / \(averageText)"
    }
    if !bestText.isEmpty {
        return bestText
    }
    if !averageText.isEmpty {
        return averageText
    }
    return nil
}

private func competitionLiveShortEventTitle(for eventID: String, languageCode: String) -> String {
    switch eventID {
    case "222":
        return localizedCompetitionStringInView(key: "wca.event.short.2x2", languageCode: languageCode)
    case "333":
        return localizedCompetitionStringInView(key: "wca.event.short.3x3", languageCode: languageCode)
    case "444":
        return localizedCompetitionStringInView(key: "wca.event.short.4x4", languageCode: languageCode)
    case "555":
        return localizedCompetitionStringInView(key: "wca.event.short.5x5", languageCode: languageCode)
    case "666":
        return localizedCompetitionStringInView(key: "wca.event.short.6x6", languageCode: languageCode)
    case "777":
        return localizedCompetitionStringInView(key: "wca.event.short.7x7", languageCode: languageCode)
    case "333oh":
        return localizedCompetitionStringInView(key: "wca.event.short.oh", languageCode: languageCode)
    case "333bf":
        return localizedCompetitionStringInView(key: "wca.event.short.bf", languageCode: languageCode)
    case "333fm":
        return localizedCompetitionStringInView(key: "wca.event.short.fm", languageCode: languageCode)
    case "clock":
        return localizedCompetitionStringInView(key: "wca.event.short.clock", languageCode: languageCode)
    case "minx":
        return localizedCompetitionStringInView(key: "wca.event.short.minx", languageCode: languageCode)
    case "pyram":
        return localizedCompetitionStringInView(key: "wca.event.short.pyram", languageCode: languageCode)
    case "skewb":
        return localizedCompetitionStringInView(key: "wca.event.short.skewb", languageCode: languageCode)
    case "sq1":
        return localizedCompetitionStringInView(key: "wca.event.short.sq1", languageCode: languageCode)
    case "444bf":
        return localizedCompetitionStringInView(key: "wca.event.short.444bf", languageCode: languageCode)
    case "555bf":
        return localizedCompetitionStringInView(key: "wca.event.short.555bf", languageCode: languageCode)
    case "333mbf":
        return localizedCompetitionStringInView(key: "wca.event.short.mbf", languageCode: languageCode)
    default:
        return eventID.uppercased()
    }
}

private struct CompetitionLiveEventIconView: View {
    let eventID: String
    let languageCode: String
    let isReady: Bool
    var color: Color = .primary
    var size: CGFloat = 15

    var body: some View {
        if isReady, let glyph = CompetitionEventIconFont.glyph(for: eventID) {
            Text(glyph)
                .font(.custom(CompetitionEventIconFont.fontName, size: size))
                .foregroundStyle(color)
                .accessibilityLabel(competitionLiveShortEventTitle(for: eventID, languageCode: languageCode))
        } else {
            Text(competitionLiveShortEventTitle(for: eventID, languageCode: languageCode))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }
}

private struct CompetitionCubingLiveSection: View {
    let content: CompetitionLiveContent
    let appLanguage: String
    let liveURL: URL?
    let areCompetitionEventIconsReady: Bool

    @StateObject private var session = CompetitionCubingLiveSession()
    @State private var showsSettings = false
    @State private var showsSumOfRanks = false
    @State private var showsPodiums = false

    private var selectedRoundOption: CompetitionLiveRoundOption? {
        content.roundOptions.first(where: { $0.id == session.selectedRoundOptionID })
    }

    private var groupedRoundOptions: [(title: String, options: [CompetitionLiveRoundOption])] {
        var grouped: [(title: String, options: [CompetitionLiveRoundOption])] = []
        for option in content.roundOptions {
            if let index = grouped.firstIndex(where: { $0.title == option.eventName }) {
                grouped[index].options.append(option)
            } else {
                grouped.append((title: option.eventName, options: [option]))
            }
        }
        return grouped
    }

    private var recentChatEntryIDs: [String] {
        session.recentChatEntries.map(\.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            actionBar
            if session.showsMessagesInChat {
                chatCard
            }
            controlBar
            if let selectedRoundOption {
                roundSummaryCard(selectedRoundOption)
            }
            resultsCard
        }
        .task(id: content.competitionID) {
            session.configure(with: content)
            session.start()
        }
        .onChange(of: content.competitionID) { _ in
            session.configure(with: content)
            session.start()
        }
        .onChange(of: session.selectedRoundOptionID) { _ in
            session.selectionDidChange()
        }
        .onChange(of: session.selectedFilterValue) { _ in
            session.selectionDidChange()
        }
        .onChange(of: session.showsMessagesInChat) { _ in
            session.messagesPreferenceDidChange()
        }
        .onDisappear {
            session.stop()
        }
        .sheet(isPresented: $showsSettings) {
            CompatibleNavigationContainer {
                Form {
                    Toggle(
                        localizedCompetitionStringInView(key: "competitions.detail.live.settings.show_messages", languageCode: appLanguage),
                        isOn: $session.showsMessagesInChat
                    )
                    Toggle(
                        localizedCompetitionStringInView(key: "competitions.detail.live.settings.show_results", languageCode: appLanguage),
                        isOn: $session.showsResultsInChat
                    )
                }
                .navigationTitle(localizedCompetitionStringInView(key: "competitions.detail.live.settings.title", languageCode: appLanguage))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(localizedCompetitionStringInView(key: "common.done", languageCode: appLanguage)) {
                            showsSettings = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showsSumOfRanks) {
            CompatibleNavigationContainer {
                CompetitionLiveSumOfRanksSheet(
                    content: content.sumOfRanksContent,
                    appLanguage: appLanguage,
                    areCompetitionEventIconsReady: areCompetitionEventIconsReady
                )
            }
        }
        .sheet(isPresented: $showsPodiums) {
            CompatibleNavigationContainer {
                CompetitionLivePodiumsSheet(
                    sections: content.podiumSections,
                    appLanguage: appLanguage
                )
            }
        }
    }

    private var actionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button {
                    showsSettings = true
                } label: {
                    liveActionPill(
                        title: localizedCompetitionStringInView(key: "competitions.detail.live.settings", languageCode: appLanguage),
                        systemImage: "gearshape"
                    )
                }
                .buttonStyle(.plain)

                if content.sumOfRanksContent != nil || content.sumOfRanksURL != nil {
                    Button {
                        showsSumOfRanks = true
                    } label: {
                        liveActionPill(
                            title: localizedCompetitionStringInView(key: "competitions.detail.live.sum_of_ranks", languageCode: appLanguage),
                            systemImage: "sum"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if !content.podiumSections.isEmpty || content.podiumsURL != nil {
                    Button {
                        showsPodiums = true
                    } label: {
                        liveActionPill(
                            title: localizedCompetitionStringInView(key: "competitions.detail.live.podiums", languageCode: appLanguage),
                            systemImage: "medal"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let liveURL {
                    Link(destination: liveURL) {
                        liveActionPill(
                            title: localizedCompetitionStringInView(key: "competitions.detail.open_live", languageCode: appLanguage),
                            systemImage: "safari"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var controlBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(groupedRoundOptions, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.options) { option in
                                Button {
                                    session.selectedRoundOptionID = option.id
                                } label: {
                                    Text(option.roundName)
                                }
                            }
                        }
                    }
                } label: {
                    liveControlPill(
                        title: selectedRoundOption.map(roundLabel) ?? localizedCompetitionStringInView(key: "competitions.detail.live.round", languageCode: appLanguage),
                        systemImage: "list.bullet"
                    )
                }
                .buttonStyle(.plain)
                .tint(.primary)

                Menu {
                    ForEach(content.filterOptions) { filter in
                        Button {
                            session.selectedFilterValue = filter.id
                        } label: {
                            Text(filter.label)
                        }
                    }
                } label: {
                    let selectedFilter = content.filterOptions.first(where: { $0.id == session.selectedFilterValue })?.label
                        ?? localizedCompetitionStringInView(key: "competitions.detail.live.filter", languageCode: appLanguage)
                    liveControlPill(
                        title: selectedFilter,
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }
                .buttonStyle(.plain)
                .tint(.primary)
            }
        }
    }

    private func roundSummaryCard(_ round: CompetitionLiveRoundOption) -> some View {
        liveCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    CompetitionLiveEventIconView(
                        eventID: round.eventID,
                        languageCode: appLanguage,
                        isReady: areCompetitionEventIconsReady,
                        color: .orange,
                        size: 18
                    )
                    Text(roundLabel(round))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if session.onlineNumber > 0 {
                        Text(String(
                            format: localizedCompetitionStringInView(key: "competitions.detail.live.online_count", languageCode: appLanguage),
                            session.onlineNumber
                        ))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                }

                Text(
                    String(
                        format: localizedCompetitionStringInView(key: "competitions.detail.live.progress", languageCode: appLanguage),
                        round.recordedCount,
                        max(round.totalCount - round.recordedCount, 0),
                        round.totalCount
                    )
                )
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

                if let error = session.connectionError, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var resultsCard: some View {
        liveCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(localizedCompetitionStringInView(key: "competitions.detail.live.results", languageCode: appLanguage))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                if session.isLoadingResults {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(localizedCompetitionStringInView(key: "competitions.loading", languageCode: appLanguage))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else if session.resultRows.isEmpty {
                    Text(localizedCompetitionStringInView(key: "competitions.detail.live.results_empty", languageCode: appLanguage))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(session.resultRows) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    Text(row.rankText)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.orange)
                                        .frame(width: 24, alignment: .leading)

                                    Text(row.numberText)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        if let regionText = row.regionText, !regionText.isEmpty {
                                            Text(regionText)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer(minLength: 8)

                                    VStack(alignment: .trailing, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(localizedCompetitionStringInView(key: "common.best", languageCode: appLanguage))
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(.secondary)
                                            Text(row.bestResultText.isEmpty ? "—" : row.bestResultText)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(.primary)
                                        }

                                        if let average = row.averageResultText, !average.isEmpty {
                                            HStack(spacing: 6) {
                                                Text(localizedCompetitionStringInView(key: "wca.results_average", languageCode: appLanguage))
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(.secondary)
                                                Text(average)
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }

                                if let detailText = row.detailText, !detailText.isEmpty {
                                    Text(detailText)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                if row.id != session.resultRows.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var chatCard: some View {
        liveCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(localizedCompetitionStringInView(key: "competitions.detail.live.chat", languageCode: appLanguage))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                if session.isLoadingMessages {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(localizedCompetitionStringInView(key: "competitions.loading", languageCode: appLanguage))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else if session.chatEntries.isEmpty {
                    Text(localizedCompetitionStringInView(key: "competitions.detail.live.chat_empty", languageCode: appLanguage))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    if !session.staticChatEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(session.staticChatEntries) { entry in
                                chatEntryView(entry, isLast: entry.id == session.staticChatEntries.last?.id)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.orange.opacity(0.08))
                        )
                    }

                    if !session.recentChatEntries.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    ForEach(session.recentChatEntries) { entry in
                                        chatEntryView(entry, isLast: entry.id == session.recentChatEntries.last?.id)
                                            .id(entry.id)
                                    }

                                    Color.clear
                                        .frame(height: 1)
                                        .id("chat-bottom-anchor")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(maxHeight: 280)
                            .onAppear {
                                scrollChatToBottom(using: proxy, animated: false)
                            }
                            .onChange(of: recentChatEntryIDs) { _ in
                                scrollChatToBottom(using: proxy, animated: true)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chatEntryView(_ entry: CompetitionLiveChatEntry, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(entry.author)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(entry.isResult ? .orange : .primary)
                if entry.timestamp > 0 {
                    Text(competitionLiveFormattedChatTime(entry.timestamp))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(entry.body)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let linkURL = entry.linkURL {
                Link(destination: linkURL) {
                    Text(linkURL.absoluteString)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            if !isLast {
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scrollChatToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                action()
            }
        } else {
            action()
        }
    }

    private func roundLabel(_ option: CompetitionLiveRoundOption) -> String {
        if let statusText = option.statusText, !statusText.isEmpty {
            return "\(option.eventName) · \(option.roundName) · \(statusText)"
        }
        return "\(option.eventName) · \(option.roundName)"
    }

    private func liveCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }

    private func liveActionPill(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
    }

    private func liveControlPill(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.primary)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private func competitionLiveFormattedChatTime(_ timestamp: Int) -> String {
    guard timestamp > 0 else { return "" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MM-dd HH:mm:ss"
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
}

private struct CompetitionLiveSumOfRanksSheet: View {
    let content: CompetitionLiveSumOfRanksContent?
    let appLanguage: String
    let areCompetitionEventIconsReady: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let content, !content.entries.isEmpty {
                ForEach(content.entries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text(entry.placeText)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.orange)
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .font(.system(size: 15, weight: .semibold))
                                if !entry.region.isEmpty {
                                    Text(entry.region)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(localizedCompetitionStringInView(key: "competitions.detail.live.total", languageCode: appLanguage))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text(entry.totalText)
                                    .font(.system(size: 15, weight: .semibold))
                            }
                        }

                        if !entry.items.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(entry.items) { item in
                                        HStack(spacing: 6) {
                                            CompetitionLiveEventIconView(
                                                eventID: item.eventID,
                                                languageCode: appLanguage,
                                                isReady: areCompetitionEventIconsReady,
                                                color: .orange,
                                                size: 14
                                            )
                                            Text(item.rankText)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.primary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text(localizedCompetitionStringInView(key: "competitions.detail.live.local_empty", languageCode: appLanguage))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(localizedCompetitionStringInView(key: "competitions.detail.live.sum_of_ranks", languageCode: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(localizedCompetitionStringInView(key: "common.done", languageCode: appLanguage)) {
                    dismiss()
                }
            }
        }
    }
}

private struct CompetitionLivePodiumsSheet: View {
    let sections: [CompetitionLivePodiumSection]
    let appLanguage: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if sections.isEmpty || sections.allSatisfy({ $0.placements.isEmpty }) {
                Text(localizedCompetitionStringInView(key: "competitions.detail.live.local_empty", languageCode: appLanguage))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sections) { section in
                    Section(section.title ?? localizedCompetitionStringInView(key: "competitions.detail.live.podiums", languageCode: appLanguage)) {
                        ForEach(section.placements) { placement in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    Text(placement.placeText)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.orange)
                                        .frame(width: 28, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(placement.name)
                                            .font(.system(size: 15, weight: .semibold))
                                        if !placement.region.isEmpty {
                                            Text(placement.region)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                HStack(spacing: 12) {
                                    if !placement.bestText.isEmpty {
                                        Text("\(localizedCompetitionStringInView(key: "common.best", languageCode: appLanguage)) \(placement.bestText)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    if !placement.averageText.isEmpty {
                                        Text("\(localizedCompetitionStringInView(key: "wca.results_average", languageCode: appLanguage)) \(placement.averageText)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle(localizedCompetitionStringInView(key: "competitions.detail.live.podiums", languageCode: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(localizedCompetitionStringInView(key: "common.done", languageCode: appLanguage)) {
                    dismiss()
                }
            }
        }
    }
}

struct CompetitionDetailView: View {
    let competition: CompetitionSummary
    let appLanguage: String

    @State private var selectedTab: CompetitionDetailTab = .info
    @State private var detailContent: CompetitionDetailContent = .empty
    @State private var isLoadingDetail = true
    @State private var competitorSearchText = ""
    @State private var selectedCompetitorEventID: String = ""
    @State private var selectedCompetitorsMode: CompetitionCompetitorsMode = .registration
    @State private var areCompetitionEventIconsReady = CompetitionEventIconFont.isAvailable
    @State private var isLoadingPsych = false
    @State private var isLoadingCompetitors = false
    @State private var isRefreshingDetail = false
    @State private var psychPreviewCache: [String: [CompetitionCompetitorPsychPreview]] = [:]
    @State private var isLoadingWCALive = false
    @State private var wcaLiveContentOverride: CompetitionWCALiveContent?
    @State private var selectedWCALiveRoundID = ""
    @State private var selectedScheduleDisplayMode: CompetitionScheduleDisplayMode = .calendar
    @AppStorage("competitionScheduleTableStyle") private var selectedScheduleTableStyleRaw = CompetitionScheduleTableStyle.cards.rawValue
    @State private var filteredCompetitorsSnapshot: [CompetitionCompetitorPreview] = []
    @State private var competitorMatrixEventIDsSnapshot: [String] = []
    @State private var showsCompetitorNumbersSnapshot = false
    @State private var showsCompetitorGenderSnapshot = false
    @State private var filteredPsychCompetitorsSnapshot: [CompetitionCompetitorPsychPreview] = []
    @State private var displayedPsychCompetitorsSnapshot: [CompetitionCompetitorPsychPreview] = []
    @State private var psychOverallRankByCompetitorIDSnapshot: [String: Int] = [:]
    @State private var psychMatrixEventIDsSnapshot: [String] = []
    @State private var showsCollapsedNavigationTitle = false
    @State private var navigationTitleBaselineY: CGFloat?

    private var selectedScheduleTableStyle: CompetitionScheduleTableStyle {
        CompetitionScheduleTableStyle(rawValue: selectedScheduleTableStyleRaw) ?? .cards
    }

    private var displayCompetitionName: String {
        guard let localizedName = detailContent.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !localizedName.isEmpty else {
            return competition.name
        }
        return localizedName
    }

    private var sourceTitle: String {
        localizedCompetitionStringInView(
            key: isMainlandChinaCompetition ? "competitions.detail.source.cubingchina" : "competitions.detail.source.wca",
            languageCode: appLanguage
        )
    }

    private var isMainlandChinaCompetition: Bool {
        competition.countryISO2.uppercased() == "CN"
    }

    private var eventTitles: [String] {
        competition.eventIDs.compactMap { eventID in
            CompetitionEventFilter.selectableCases.first(where: { $0.wcaEventID == eventID })?.localizedTitle(languageCode: appLanguage)
            ?? eventID.uppercased()
        }
    }

    private var officialURL: URL? {
        if isMainlandChinaCompetition, let website = competition.website, let url = URL(string: website) {
            return url
        }
        return URL(string: competition.url)
    }

    private var registerURL: URL? {
        if isMainlandChinaCompetition,
           let website = competition.website,
           let url = URL(string: website.replacingOccurrences(of: "/competition/", with: "/competition/").appending("/registration")) {
            return url
        }

        if let url = URL(string: competition.url + "/register") {
            return url
        }

        return officialURL
    }

    private var competitorsURL: URL? {
        if isMainlandChinaCompetition,
           let website = competition.website,
           let url = URL(string: website.replacingOccurrences(of: "/competition/", with: "/competition/").appending("/competitors")) {
            return url
        }

        if let url = URL(string: competition.url + "/registrations") {
            return url
        }

        return officialURL
    }

    private var mapsURL: URL? {
        let query = [competition.venue, competition.venueAddress, competition.city]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        guard !query.isEmpty else { return nil }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: "http://maps.apple.com/?q=\(encoded)")
    }

    private var travelMapLocations: [CompetitionTravelMapLocation] {
        if !detailContent.travelMapLocations.isEmpty {
            return detailContent.travelMapLocations
        }

        guard let latitude = competition.latitude,
              let longitude = competition.longitude else {
            return []
        }

        return [
            CompetitionTravelMapLocation(
                id: "competition-location-\(competition.id)",
                latitude: latitude,
                longitude: longitude,
                venue: competition.venue,
                address: [competition.venueAddress, competition.city].filter { !$0.isEmpty }.joined(separator: ", ")
            )
        ]
    }

    private var travelMapURL: URL? {
        guard let location = travelMapLocations.first else { return mapsURL }
        let query = [location.venue, location.address]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        if !query.isEmpty {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            return URL(string: "http://maps.apple.com/?q=\(encoded)&ll=\(location.latitude),\(location.longitude)")
        }

        return URL(string: "http://maps.apple.com/?ll=\(location.latitude),\(location.longitude)")
    }

    private var liveURL: URL? {
        if isMainlandChinaCompetition,
           let website = competition.website,
           let liveURL = URL(string: website.replacingOccurrences(of: "/competition/", with: "/live/")) {
            return liveURL
        }

        return detailContent.liveURLOverride
    }

    private var effectiveWCALiveContent: CompetitionWCALiveContent? {
        wcaLiveContentOverride ?? detailContent.wcaLiveContent
    }

    private var shouldRefreshWCALiveContent: Bool {
        guard !isMainlandChinaCompetition else { return false }
        guard let content = effectiveWCALiveContent else { return true }
        guard !content.rounds.isEmpty else { return true }
        return content.rounds.allSatisfy { $0.results.isEmpty }
    }

    private var wcaLiveRounds: [CompetitionWCALiveRound] {
        effectiveWCALiveContent?.rounds ?? []
    }

    private var effectiveWCALiveRoundID: String {
        if wcaLiveRounds.contains(where: { $0.id == selectedWCALiveRoundID }) {
            return selectedWCALiveRoundID
        }
        return wcaLiveRounds.first(where: { !$0.results.isEmpty })?.id
            ?? wcaLiveRounds.first?.id
            ?? ""
    }

    private var selectedWCALiveRound: CompetitionWCALiveRound? {
        guard !effectiveWCALiveRoundID.isEmpty else { return nil }
        return wcaLiveRounds.first(where: { $0.id == effectiveWCALiveRoundID })
    }

    private var shouldShowLiveLink: Bool {
        if !isMainlandChinaCompetition {
            return liveURL != nil
        }

        switch detailContent.liveAvailability {
        case .available, .ended:
            return liveURL != nil
        case .upcoming:
            return !isMainlandChinaCompetition && liveURL != nil
        case .unavailable:
            return false
        }
    }

    private var canShowCubingCalendarSchedule: Bool {
        guard isMainlandChinaCompetition else { return false }
        return detailContent.scheduleDays.contains { day in
            day.venues.count > 1 || day.venues.contains { $0.title != "赛程" && !$0.entries.isEmpty }
        }
    }

    private var liveStatusTitle: String {
        if !isMainlandChinaCompetition {
            if detailContent.liveAvailability == .ended {
                return localizedCompetitionStringInView(key: "competitions.detail.live_status.ended", languageCode: appLanguage)
            }
            return localizedCompetitionStringInView(key: "competitions.detail.live_status.available", languageCode: appLanguage)
        }

        switch detailContent.liveAvailability {
        case .available:
            return localizedCompetitionStringInView(key: "competitions.detail.live_status.available", languageCode: appLanguage)
        case .unavailable:
            return localizedCompetitionStringInView(key: "competitions.detail.live_status.unavailable", languageCode: appLanguage)
        case .upcoming:
            return localizedCompetitionStringInView(key: "competitions.detail.live_status.upcoming", languageCode: appLanguage)
        case .ended:
            return localizedCompetitionStringInView(key: "competitions.detail.live_status.ended", languageCode: appLanguage)
        }
    }

    private var liveStatusBody: String {
        if !isMainlandChinaCompetition {
            if detailContent.liveAvailability == .ended {
                return localizedCompetitionStringInView(key: "competitions.detail.live_body_ended", languageCode: appLanguage)
            }
            return localizedCompetitionStringInView(key: "competitions.detail.live_body_available", languageCode: appLanguage)
        }

        switch detailContent.liveAvailability {
        case .available:
            return localizedCompetitionStringInView(key: "competitions.detail.live_body_available", languageCode: appLanguage)
        case .unavailable:
            return localizedCompetitionStringInView(key: "competitions.detail.live_body_unavailable", languageCode: appLanguage)
        case .upcoming:
            return localizedCompetitionStringInView(key: "competitions.detail.live_body_upcoming", languageCode: appLanguage)
        case .ended:
            return localizedCompetitionStringInView(key: "competitions.detail.live_body_ended", languageCode: appLanguage)
        }
    }

    private var visibleTabs: [CompetitionDetailTab] {
        if isMainlandChinaCompetition {
            return [
                .info.titled(localizedCompetitionStringInView(key: "competitions.detail.tab.main_page", languageCode: appLanguage)),
                .rules.titled(localizedCompetitionStringInView(key: "competitions.detail.tab.regulations", languageCode: appLanguage)),
                .schedule,
                .travel,
                .competitors,
                .register.titled(localizedCompetitionStringInView(key: "competitions.detail.tab.registration", languageCode: appLanguage))
            ]
        }

        let wcaTabs = detailContent.noteBlocks.compactMap(wcaTab(for:))
        if wcaTabs.isEmpty {
            return [.info, .register, .competitors, .schedule]
        }

        var tabs = wcaTabs
        if wcaHasRegisterLink, !tabs.contains(where: { $0.kind == .register }) {
            tabs.append(.register.titled("Register"))
        }
        if wcaHasCompetitorsLink, !tabs.contains(where: { $0.kind == .competitors }) {
            tabs.append(.competitors.titled("Competitors"))
        }
        if shouldShowLiveTab, !tabs.contains(where: { $0.kind == .live }) {
            tabs.append(.live.titled("Live"))
        }
        return tabs
    }

    private var effectiveSelectedTab: CompetitionDetailTab {
        visibleTabs.first(where: { $0.rawValue == selectedTab.rawValue }) ?? selectedTab
    }

    private var selectedCustomTabBlock: CompetitionDetailTextBlock? {
        guard case .custom(let id) = selectedTab.kind else { return nil }
        return detailContent.noteBlocks.first { $0.id == id }
    }

    private var selectedWCASourceBlock: CompetitionDetailTextBlock? {
        wcaSourceBlock(for: selectedTab.kind)
    }

    private var wcaHasRegisterLink: Bool {
        detailContent.hasRegisterLink
    }

    private var wcaHasCompetitorsLink: Bool {
        detailContent.hasCompetitorsLink
    }

    private var shouldShowLiveTab: Bool {
        detailContent.liveURLOverride != nil || detailContent.wcaLiveContent != nil
    }

    private func wcaTab(for block: CompetitionDetailTextBlock) -> CompetitionDetailTab? {
        guard let title = block.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }

        switch normalizedWCASourceID(block.id) {
        case "general-info": return .info.titled(title)
        case "competition-events": return .events.titled(title)
        case "competition-schedule": return .schedule.titled(title)
        case "register", "registration", "registrations": return .register.titled(title)
        case "competitors", "registrations-list": return .competitors.titled(title)
        case "live": return .live.titled(title)
        default: return .custom(id: block.id, title: title)
        }
    }

    private func wcaSourceBlock(for kind: CompetitionDetailTabKind) -> CompetitionDetailTextBlock? {
        let candidates: Set<String>
        switch kind {
        case .info:
            candidates = ["general-info"]
        case .events:
            candidates = ["competition-events"]
        case .schedule:
            candidates = ["competition-schedule"]
        case .register:
            candidates = ["register", "registration", "registrations"]
        case .competitors:
            candidates = ["competitors", "registrations-list"]
        case .travel:
            candidates = ["travel"]
        case .rules, .live, .custom:
            return nil
        }

        return detailContent.noteBlocks.first { block in
            let normalizedID = normalizedWCASourceID(block.id)
            return candidates.contains(normalizedID) || candidates.contains(where: { normalizedID.hasSuffix("-\($0)") })
        }
    }

    private func normalizedWCASourceID(_ id: String) -> String {
        id.replacingOccurrences(of: "wca-", with: "")
    }

    private var overviewDescription: String {
        let status = competitionAvailabilityStatus(for: competition).localizedTitle(languageCode: appLanguage)
        let eventCount = eventTitles.count
        let formatKey = isMainlandChinaCompetition
            ? "competitions.detail.overview_cn_format"
            : "competitions.detail.overview_wca_format"
        return String(
            format: localizedCompetitionStringInView(key: formatKey, languageCode: appLanguage),
            status,
            eventCount
        )
    }

    private var travelDescription: String {
        localizedCompetitionStringInView(
            key: isMainlandChinaCompetition ? "competitions.detail.travel_cn_body" : "competitions.detail.travel_wca_body",
            languageCode: appLanguage
        )
    }

    private var eventSummaryText: String {
        String(
            format: localizedCompetitionStringInView(
                key: "competitions.detail.events_count_format",
                languageCode: appLanguage
            ),
            eventTitles.count
        )
    }

    private var competitionDayTexts: [String] {
        let calendar = Calendar(identifier: .gregorian)
        let dayCount = max(calendar.dateComponents([.day], from: calendar.startOfDay(for: competition.startDate), to: calendar.startOfDay(for: competition.endDate)).day ?? 0, 0)

        return (0...dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: competition.startDate) else { return nil }
            return localizedCompetitionDateRange(startingAt: date)
        }
    }

    private var registrationSummaryText: String {
        if let competitorLimit = competition.competitorLimit {
            return String(
                format: localizedCompetitionStringInView(key: "competitions.detail.registration_summary_limit_format", languageCode: appLanguage),
                competitorLimit
            )
        }
        return localizedCompetitionStringInView(key: "competitions.detail.registration_summary_open", languageCode: appLanguage)
    }

    private var filteredCompetitors: [CompetitionCompetitorPreview] {
        filteredCompetitorsSnapshot
    }

    private var competitorMatrixEventIDs: [String] {
        competitorMatrixEventIDsSnapshot
    }

    private var showsCompetitorNumbers: Bool {
        showsCompetitorNumbersSnapshot
    }

    private var showsCompetitorGender: Bool {
        showsCompetitorGenderSnapshot
    }

    private var currentPsychCacheKey: String {
        selectedCompetitorEventID.isEmpty ? "__all__" : selectedCompetitorEventID
    }

    private var isPsychModeAvailable: Bool {
        !selectedCompetitorEventID.isEmpty
    }

    private var filteredPsychCompetitors: [CompetitionCompetitorPsychPreview] {
        filteredPsychCompetitorsSnapshot
    }

    private var showsPsychOverallRank: Bool {
        selectedCompetitorEventID.isEmpty
    }

    private var psychOverallRankByCompetitorID: [String: Int] {
        psychOverallRankByCompetitorIDSnapshot
    }

    private var displayedPsychCompetitors: [CompetitionCompetitorPsychPreview] {
        displayedPsychCompetitorsSnapshot
    }

    private var psychMatrixEventIDs: [String] {
        psychMatrixEventIDsSnapshot
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: CompetitionDetailScrollOffsetPreferenceKey.self,
                            value: proxy.frame(in: .global).minY
                        )
                }
                .frame(height: 0)

                if !isMainlandChinaCompetition {
                    heroCard
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                tabStrip
                    .padding(.top, isMainlandChinaCompetition ? 8 : 0)

                if isMainlandChinaCompetition {
                    cubingPageHeader
                        .padding(.horizontal, 16)
                }

                tabContent
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(isMainlandChinaCompetition ? "" : displayCompetitionName)
        .navigationBarTitleDisplayMode(.inline)
        .onPreferenceChange(CompetitionDetailScrollOffsetPreferenceKey.self) { currentY in
            if navigationTitleBaselineY == nil {
                navigationTitleBaselineY = currentY
            }

            let scrollDistance = (navigationTitleBaselineY ?? currentY) - currentY
            let shouldShowTitle = isMainlandChinaCompetition && scrollDistance > 72
            guard shouldShowTitle != showsCollapsedNavigationTitle else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                showsCollapsedNavigationTitle = shouldShowTitle
            }
        }
        .task(id: "\(competition.id)|\(appLanguage)") {
            areCompetitionEventIconsReady = CompetitionEventIconFont.ensureRegistered()
            await loadDetailContent()
        }
        .task(id: "\(competition.id)|\(appLanguage)|\(selectedTab.rawValue)|\(selectedCompetitorsMode.rawValue)|\(selectedCompetitorEventID)") {
            await loadCompetitionCompetitorsIfNeeded()
            await loadPsychPreviewsIfNeeded()
        }
        .task(id: "\(competition.id)|\(appLanguage)|\(selectedTab.rawValue)") {
            await loadWCALiveContentIfNeeded()
        }
        .onChange(of: competitorSearchText) { _ in
            updateCompetitionDetailDerivedState()
        }
        .onChange(of: selectedCompetitorEventID) { _ in
            updateCompetitionDetailDerivedState()
        }
        .onChange(of: selectedCompetitorsMode) { _ in
            updateCompetitionDetailDerivedState()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                if isMainlandChinaCompetition {
                    Text(displayCompetitionName)
                        .font(.headline)
                        .lineLimit(1)
                        .opacity(showsCollapsedNavigationTitle ? 1 : 0)
                        .animation(.easeInOut(duration: 0.16), value: showsCollapsedNavigationTitle)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                if isMainlandChinaCompetition {
                    if isRefreshingDetail {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            Task {
                                await refreshDetailContent()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .tint(.primary)
                    }
                } else {
                    EmptyView()
                }
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(displayCompetitionName)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                statusBadge(
                    for: competitionAvailabilityStatus(for: competition),
                    competition: competition,
                    languageCode: appLanguage
                )

                Text(sourceTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.secondary.opacity(0.1), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                detailLine(systemImage: "calendar", text: localizedCompetitionDateRange(for: competition))
                detailLine(systemImage: "location", text: competition.locationLine)
                if !competition.venueLine.isEmpty {
                    detailLine(systemImage: "mappin.and.ellipse", text: competition.venueLine)
                }
            }

            HStack(spacing: 10) {
                if let officialURL {
                    Link(destination: officialURL) {
                        detailActionLabel(
                            title: localizedCompetitionStringInView(key: "competitions.detail.open_official", languageCode: appLanguage),
                            systemImage: "safari"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let liveURL {
                    Link(destination: liveURL) {
                        detailActionLabel(
                            title: localizedCompetitionStringInView(key: "competitions.detail.open_live", languageCode: appLanguage),
                            systemImage: "dot.radiowaves.left.and.right"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.background)
        )
    }

    private var tabStrip: some View {
        CompetitionDetailTabStrip(
            tabs: visibleTabs,
            languageCode: appLanguage,
            selection: $selectedTab
        )
    }

    private var cubingPageHeader: some View {
        VStack(spacing: 8) {
            Text(displayCompetitionName)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(effectiveSelectedTab.localizedTitle(languageCode: appLanguage))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab.kind {
        case .info:
            detailSectionStack {
                if isLoadingDetail && detailContent == .empty {
                    detailLoadingCard
                }

                if isMainlandChinaCompetition {
                    if detailContent.overviewBlocks.isEmpty {
                        detailSectionCard(title: selectedTab.localizedTitle(languageCode: appLanguage)) {
                            Text(localizedCompetitionStringInView(key: "competitions.detail.unavailable", languageCode: appLanguage))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        cubingDetailDocument(
                            detailContent.overviewBlocks,
                            fallbackTitle: selectedTab.localizedTitle(languageCode: appLanguage)
                        )
                    }
                } else if let sourceBlock = selectedWCASourceBlock {
                    detailSectionCard(title: sourceBlock.title ?? selectedTab.localizedTitle(languageCode: appLanguage)) {
                        detailTextBlocks([sourceBlock])
                    }
                } else {
                    detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.section.overview", languageCode: appLanguage)) {
                        VStack(alignment: .leading, spacing: 10) {
                            if detailContent.overviewBlocks.isEmpty {
                                Text(overviewDescription)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                detailTextBlocks(detailContent.overviewBlocks)
                            }

                            detailLine(systemImage: "calendar", text: localizedCompetitionDateRange(for: competition))
                            detailLine(systemImage: "location", text: competition.locationLine)
                            detailLine(systemImage: "square.grid.2x2", text: eventSummaryText)
                        }
                    }

                    detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.section.venue", languageCode: appLanguage)) {
                        VStack(alignment: .leading, spacing: 10) {
                            detailLine(systemImage: "building.2", text: competition.venue)
                            if !competition.venueAddress.isEmpty {
                                detailLine(systemImage: "map", text: competition.venueAddress)
                            }
                            if let venueDetails = competition.venueDetails, !venueDetails.isEmpty {
                                detailLine(systemImage: "info.circle", text: venueDetails)
                            }

                            if let mapsURL {
                                Link(destination: mapsURL) {
                                    detailSecondaryLink(localizedCompetitionStringInView(key: "competitions.detail.open_maps", languageCode: appLanguage))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !eventTitles.isEmpty {
                        detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.section.events", languageCode: appLanguage)) {
                            FlexibleTagFlow(items: eventTitles)
                        }
                    }

                    detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.section.travel", languageCode: appLanguage)) {
                        VStack(alignment: .leading, spacing: 10) {
                            if detailContent.travelBlocks.isEmpty {
                                Text(travelDescription)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                detailTextBlocks(detailContent.travelBlocks)
                            }

                            if let officialURL {
                                Link(destination: officialURL) {
                                    detailSecondaryLink(localizedCompetitionStringInView(key: "competitions.detail.open_official", languageCode: appLanguage))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

        case .rules:
            detailSectionStack {
                if isLoadingDetail && detailContent == .empty {
                    detailLoadingCard
                }

                if isMainlandChinaCompetition {
                    if detailContent.regulationBlocks.isEmpty {
                        detailSectionCard(title: selectedTab.localizedTitle(languageCode: appLanguage)) {
                            Text(localizedCompetitionStringInView(key: "competitions.detail.unavailable", languageCode: appLanguage))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        cubingDetailDocument(
                            detailContent.regulationBlocks,
                            fallbackTitle: selectedTab.localizedTitle(languageCode: appLanguage)
                        )
                    }
                } else {
                    detailSectionCard(title: selectedTab.localizedTitle(languageCode: appLanguage)) {
                        if detailContent.registerBlocks.isEmpty {
                            Text(localizedCompetitionStringInView(key: "competitions.detail.unavailable", languageCode: appLanguage))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            detailTextBlocks(detailContent.registerBlocks)
                        }
                    }
                }
            }

        case .events:
            detailSectionStack {
                if isLoadingDetail && detailContent == .empty {
                    detailLoadingCard
                }

                if let sourceBlock = selectedWCASourceBlock, !sourceBlock.body.isEmpty {
                    detailSectionCard(title: sourceBlock.title ?? selectedTab.localizedTitle(languageCode: appLanguage)) {
                        detailTextBlocks([sourceBlock])
                    }
                }

                if !eventTitles.isEmpty {
                    detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.section.events", languageCode: appLanguage)) {
                        FlexibleTagFlow(items: eventTitles)
                    }
                }
            }

        case .travel:
            detailSectionStack {
                if isLoadingDetail && detailContent == .empty {
                    detailLoadingCard
                }

                if !isMainlandChinaCompetition {
                    detailSectionCard(title: selectedTab.localizedTitle(languageCode: appLanguage)) {
                        if let sourceBlock = selectedWCASourceBlock {
                            detailTextBlocks([sourceBlock])
                        } else if detailContent.travelBlocks.isEmpty {
                            Text(travelDescription)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            detailTextBlocks(detailContent.travelBlocks)
                        }
                    }
                } else if detailContent.travelBlocks.isEmpty {
                    Text(travelDescription)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    cubingDetailDocumentBody(
                        detailContent.travelBlocks,
                        fallbackTitle: selectedTab.localizedTitle(languageCode: appLanguage),
                        mapLocations: travelMapLocations,
                        mapURL: travelMapURL
                    )
                }

                if let officialURL {
                    Link(destination: officialURL) {
                        detailSecondaryLink(localizedCompetitionStringInView(key: "competitions.detail.open_official", languageCode: appLanguage))
                    }
                    .buttonStyle(.plain)
                }
            }

        case .custom:
            detailSectionStack {
                if isLoadingDetail && detailContent == .empty {
                    detailLoadingCard
                }

                if let selectedCustomTabBlock {
                    detailSectionCard(title: selectedCustomTabBlock.title ?? selectedTab.localizedTitle(languageCode: appLanguage)) {
                        detailTextBlocks([selectedCustomTabBlock])
                    }
                } else {
                    detailSectionCard(title: selectedTab.localizedTitle(languageCode: appLanguage)) {
                        Text(localizedCompetitionStringInView(key: "competitions.detail.unavailable", languageCode: appLanguage))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

        case .register:
            detailSectionStack {
                if isLoadingDetail && detailContent == .empty {
                    detailLoadingCard
                }

                detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.section.registration_status", languageCode: appLanguage)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(registrationSummaryText)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        statusBadge(
                            for: competitionAvailabilityStatus(for: competition),
                            competition: competition,
                            languageCode: appLanguage
                        )

                        if let registrationOpen = competition.registrationOpen {
                            detailLine(systemImage: "calendar.badge.plus", text: String(format: localizedCompetitionStringInView(key: "competitions.detail.registration_open_format", languageCode: appLanguage), localizedCompetitionDateRange(startingAt: registrationOpen)))
                        }

                        if let registrationClose = competition.registrationClose {
                            detailLine(systemImage: "calendar.badge.clock", text: String(format: localizedCompetitionStringInView(key: "competitions.detail.registration_close_format", languageCode: appLanguage), localizedCompetitionDateRange(startingAt: registrationClose)))
                        }

                        if let competitorLimit = competition.competitorLimit {
                            detailLine(systemImage: "person.3", text: String(format: localizedCompetitionStringInView(key: "competitions.competitor_limit_format", languageCode: appLanguage), competitorLimit))
                        }

                        if detailContent.registrationRequiresSignIn {
                            detailLine(
                                systemImage: "person.crop.circle.badge.exclamationmark",
                                text: localizedCompetitionStringInView(key: "competitions.detail.registration_login_required", languageCode: appLanguage)
                            )
                        }
                    }
                }

                if !isMainlandChinaCompetition && !detailContent.registerBlocks.isEmpty {
                    detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.section.notes", languageCode: appLanguage)) {
                        detailTextBlocks(detailContent.registerBlocks)
                    }
                }

                if !isMainlandChinaCompetition, !eventTitles.isEmpty {
                    detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.section.events", languageCode: appLanguage)) {
                        FlexibleTagFlow(items: eventTitles)
                    }
                }

                if let registerURL {
                    Link(destination: registerURL) {
                        detailPrimaryButton(localizedCompetitionStringInView(key: "competitions.detail.open_registration", languageCode: appLanguage))
                    }
                    .buttonStyle(.plain)
                }
            }

        case .competitors:
            detailSectionStack {
                if isLoadingDetail && detailContent == .empty {
                    detailLoadingCard
                }

                detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.section.competitors", languageCode: appLanguage)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_body", languageCode: appLanguage))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let competitorLimit = competition.competitorLimit {
                            detailLine(systemImage: "person.2", text: String(format: localizedCompetitionStringInView(key: "competitions.competitor_limit_format", languageCode: appLanguage), competitorLimit))
                        }

                        if let competitorsCount = detailContent.competitorsCount {
                            detailLine(
                                systemImage: "person.3.sequence",
                                text: String(format: localizedCompetitionStringInView(key: "competitions.detail.competitors_count_format", languageCode: appLanguage), competitorsCount)
                            )
                        }

                        if !detailContent.competitorPreviews.isEmpty {
                            competitorSearchField
                            competitorEventFilterStrip
                            competitorsModePicker

                            if selectedCompetitorsMode == .registration,
                               let competitorsCount = detailContent.competitorsCount,
                               competitorsCount > detailContent.competitorPreviews.count {
                                Text(
                                    String(
                                        format: localizedCompetitionStringInView(
                                            key: competitorSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                                ? "competitions.detail.competitors_preview_format"
                                                : "competitions.detail.competitors_filtered_format",
                                            languageCode: appLanguage
                                        ),
                                        filteredCompetitors.count,
                                        competitorsCount
                                    )
                                )
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                            }

                            if selectedCompetitorsMode == .registration {
                                competitorsMatrixTable
                            } else if isLoadingPsych {
                                competitorsPsychLoadingCard
                            } else if filteredPsychCompetitors.isEmpty {
                                Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_psych_unavailable", languageCode: appLanguage))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                            } else {
                                competitorsPsychTable
                            }
                        } else if isLoadingCompetitors {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(localizedCompetitionStringInView(key: "competitions.loading", languageCode: appLanguage))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        } else if !isLoadingDetail {
                            Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_unavailable", languageCode: appLanguage))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        if let competitorsURL {
                            Link(destination: competitorsURL) {
                                detailSecondaryLink(localizedCompetitionStringInView(key: "competitions.detail.open_competitors", languageCode: appLanguage))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

        case .schedule:
            detailSectionStack {
                if isLoadingDetail && detailContent == .empty {
                    detailLoadingCard
                }

                detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.section.schedule", languageCode: appLanguage)) {
                    VStack(alignment: .leading, spacing: 12) {
                        if detailContent.scheduleDays.isEmpty {
                            Text(localizedCompetitionStringInView(key: "competitions.detail.schedule_body", languageCode: appLanguage))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            if !competitionDayTexts.isEmpty {
                                detailLine(
                                    systemImage: "calendar.day.timeline.left",
                                    text: String(
                                        format: localizedCompetitionStringInView(
                                            key: "competitions.detail.schedule_days_format",
                                            languageCode: appLanguage
                                        ),
                                        competitionDayTexts.count
                                    )
                                )

                                FlexibleTagFlow(items: competitionDayTexts)
                            }

                            if !eventTitles.isEmpty {
                                FlexibleTagFlow(items: eventTitles)
                            }
                        } else {
                            if canShowCubingCalendarSchedule {
                                Picker("", selection: $selectedScheduleDisplayMode) {
                                    Text("项目列表").tag(CompetitionScheduleDisplayMode.calendar)
                                    Text("赛程安排").tag(CompetitionScheduleDisplayMode.table)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }

                            if canShowCubingCalendarSchedule && selectedScheduleDisplayMode == .calendar {
                                cubingScheduleCalendar
                            } else {
                                scheduleTableStyleMenu

                                if isMainlandChinaCompetition, selectedScheduleTableStyle == .table {
                                    cubingScheduleWebsiteIntro
                                }

                                ForEach(detailContent.scheduleDays) { day in
                                    detailScheduleDayCard(day)
                                }

                                if isMainlandChinaCompetition, selectedScheduleTableStyle == .table {
                                    cubingScheduleWebsiteComment
                                }
                            }
                        }

                        if let officialURL {
                            Link(destination: officialURL) {
                                detailSecondaryLink(localizedCompetitionStringInView(key: "competitions.detail.open_official", languageCode: appLanguage))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

        case .live:
            detailSectionStack {
                if isMainlandChinaCompetition, let liveContent = detailContent.liveContent {
                    CompetitionCubingLiveSection(
                        content: liveContent,
                        appLanguage: appLanguage,
                        liveURL: liveURL,
                        areCompetitionEventIconsReady: areCompetitionEventIconsReady
                    )
                } else if let wcaLiveContent = effectiveWCALiveContent {
                    if let selectedRound = selectedWCALiveRound {
                        detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.live.wca.rounds", languageCode: appLanguage)) {
                            VStack(alignment: .leading, spacing: 14) {
                                wcaLiveRoundPicker
                                wcaLiveResultsTable(selectedRound)
                            }
                        }
                    }

                    if !wcaLiveContent.venues.isEmpty {
                        detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.live.wca.rooms", languageCode: appLanguage)) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(wcaLiveContent.venues) { venue in
                                    wcaLiveVenueCard(venue)
                                }
                            }
                        }
                    }

                    if wcaLiveContent.rounds.isEmpty, !detailContent.scheduleDays.isEmpty {
                        detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.section.schedule", languageCode: appLanguage)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(localizedCompetitionStringInView(key: "competitions.detail.wca_live_rounds_body", languageCode: appLanguage))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                ForEach(detailContent.scheduleDays) { day in
                                    detailScheduleDayCard(day)
                                }
                            }
                        }
                    }
                } else {
                    detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.section.live", languageCode: appLanguage)) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(liveStatusTitle)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text(liveStatusBody)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            detailLine(
                                systemImage: "dot.radiowaves.left.and.right",
                                text: localizedCompetitionStringInView(
                                    key: isMainlandChinaCompetition
                                        ? "competitions.detail.source.cubingchina"
                                        : "competitions.detail.source.wca_live",
                                    languageCode: appLanguage
                                )
                            )

                            if !eventTitles.isEmpty {
                                FlexibleTagFlow(items: eventTitles)
                            }

                            if shouldShowLiveLink, let liveURL {
                                Link(destination: liveURL) {
                                    detailPrimaryButton(localizedCompetitionStringInView(key: "competitions.detail.open_live", languageCode: appLanguage))
                                }
                                .buttonStyle(.plain)
                            }

                            if isLoadingWCALive {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text(localizedCompetitionStringInView(key: "competitions.loading", languageCode: appLanguage))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 4)
                            }
                        }
                    }

                    if !detailContent.scheduleDays.isEmpty {
                        detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.section.schedule", languageCode: appLanguage)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(localizedCompetitionStringInView(key: "competitions.detail.wca_live_rounds_body", languageCode: appLanguage))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                ForEach(detailContent.scheduleDays) { day in
                                    detailScheduleDayCard(day)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var detailLoadingCard: some View {
        detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.loading", languageCode: appLanguage)) {
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemFill))
                    .frame(maxWidth: 220)
                    .frame(height: 16)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemFill))
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemFill))
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemFill))
                    .frame(maxWidth: 168)
                    .frame(height: 14)
            }
            .redacted(reason: .placeholder)
        }
    }

    private var competitorSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(
                localizedCompetitionStringInView(key: "competitions.detail.competitors_search_placeholder", languageCode: appLanguage),
                text: $competitorSearchText
            )
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var competitorEventFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                competitorEventFilterChip(
                    title: localizedCompetitionStringInView(key: "competitions.event.all", languageCode: appLanguage),
                    eventID: ""
                )

                ForEach(competitorMatrixEventIDs, id: \.self) { eventID in
                    competitorEventFilterChip(
                        title: shortEventTitle(for: eventID),
                        eventID: eventID
                    )
                }
            }
        }
    }

    private var competitorsModePicker: some View {
        HStack(spacing: 8) {
            ForEach(CompetitionCompetitorsMode.allCases) { mode in
                let isSelected = selectedCompetitorsMode == mode
                let isEnabled = mode == .registration || isPsychModeAvailable
                Button {
                    guard isEnabled else { return }
                    withAnimation(.snappy(duration: 0.18)) {
                        selectedCompetitorsMode = mode
                    }
                } label: {
                    Text(mode.localizedTitle(languageCode: appLanguage))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isEnabled ? (isSelected ? .primary : .secondary) : .tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(
                                    isEnabled
                                        ? (isSelected ? Color.primary.opacity(0.08) : Color(uiColor: .secondarySystemGroupedBackground))
                                        : Color(uiColor: .tertiarySystemGroupedBackground)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }
        }
    }

    private func competitorEventFilterChip(title: String, eventID: String) -> some View {
        let isSelected = selectedCompetitorEventID == eventID
        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                selectedCompetitorEventID = eventID
                if eventID.isEmpty, selectedCompetitorsMode == .psych {
                    selectedCompetitorsMode = .registration
                }
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.primary.opacity(0.08) : Color(uiColor: .secondarySystemGroupedBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private var competitorsMatrixTable: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    competitorsMatrixHeader

                    Divider()
                        .padding(.vertical, 8)

                    VStack(spacing: 10) {
                        ForEach(filteredCompetitors) { competitor in
                            competitorsMatrixRow(competitor)
                        }
                    }
                }
                .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var competitorsMatrixHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            if showsCompetitorNumbers {
                Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_column.number", languageCode: appLanguage))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
            }

            Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_column.name", languageCode: appLanguage))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)

            if showsCompetitorGender {
                Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_column.gender", languageCode: appLanguage))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
            }

            Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_column.region", languageCode: appLanguage))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)

            ForEach(competitorMatrixEventIDs, id: \.self) { eventID in
                competitionEventIconLabel(
                    for: eventID,
                    isEmphasized: false
                )
                .frame(width: 44, alignment: .center)
            }
        }
    }

    private func competitorsMatrixRow(_ competitor: CompetitionCompetitorPreview) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if showsCompetitorNumbers {
                Text(competitor.number ?? "—")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
            }

            Text(competitor.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 180, alignment: .leading)

            if showsCompetitorGender {
                Text(localizedCompetitorGender(competitor.gender))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
            }

            Text(competitor.subtitle ?? "—")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)

            ForEach(competitorMatrixEventIDs, id: \.self) { eventID in
                competitorMatrixEventCell(
                    eventID: eventID,
                    isRegistered: competitor.registeredEventIDs.contains(eventID)
                )
            }
        }
        .padding(.vertical, 2)
    }

    private var competitorsPsychLoadingCard: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_psych_loading", languageCode: appLanguage))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
            }
            .frame(height: 72)
    }

    private var competitorsPsychTable: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    competitorsPsychHeader

                    Divider()
                        .padding(.vertical, 8)

                    VStack(spacing: 10) {
                        ForEach(displayedPsychCompetitors) { competitor in
                            competitorsPsychRow(competitor)
                        }
                    }
                }
                .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var competitorsPsychHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_column.name", languageCode: appLanguage))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)

            if showsPsychOverallRank {
                Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_column.overall", languageCode: appLanguage))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .center)
            }

            ForEach(psychMatrixEventIDs, id: \.self) { eventID in
                competitionEventIconLabel(
                    for: eventID,
                    isEmphasized: false
                )
                .frame(width: 92, alignment: .center)
            }
        }
    }

    private func competitorsPsychRow(_ competitor: CompetitionCompetitorPsychPreview) -> some View {
        let itemsByEvent = Dictionary(uniqueKeysWithValues: competitor.items.map { ($0.eventID, $0) })

        return HStack(alignment: .center, spacing: 10) {
            Text(competitor.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 180, alignment: .leading)

            if showsPsychOverallRank {
                psychOverallRankCell(psychOverallRankByCompetitorID[competitor.id])
            }

            ForEach(psychMatrixEventIDs, id: \.self) { eventID in
                competitorPsychCell(itemsByEvent[eventID], eventID: eventID)
            }
        }
        .padding(.vertical, 2)
    }

    private func psychOverallRankCell(_ rank: Int?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rank == nil ? Color.clear : Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(rank == nil ? Color.secondary.opacity(0.12) : Color.orange.opacity(0.22), lineWidth: 1)
                )

            if let rank {
                Text("\(rank)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.orange)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 56, height: 32)
    }

    @ViewBuilder
    private func competitorPsychCell(_ item: CompetitionPsychItem?, eventID: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(item == nil ? Color.clear : Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(item == nil ? Color.secondary.opacity(0.12) : Color.orange.opacity(0.22), lineWidth: 1)
                )

            if let item {
                HStack(spacing: 4) {
                    Text("\(item.rank)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.orange)

                    competitionEventIconLabel(for: eventID, isEmphasized: true)

                    Text(item.resultText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 6)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 92, height: 32)
    }

    private func competitorMatrixEventCell(eventID: String, isRegistered: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isRegistered ? Color.orange.opacity(0.14) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isRegistered ? Color.orange.opacity(0.25) : Color.secondary.opacity(0.12), lineWidth: 1)
                )

            if isRegistered {
                competitionEventIconLabel(
                    for: eventID,
                    isEmphasized: true
                )
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 44, height: 32)
    }

    @ViewBuilder
    private func competitionEventIconLabel(for eventID: String, isEmphasized: Bool) -> some View {
        if areCompetitionEventIconsReady,
           let glyph = CompetitionEventIconFont.glyph(for: eventID) {
            Text(glyph)
                .font(.custom(CompetitionEventIconFont.fontName, size: isEmphasized ? 17 : 15))
                .foregroundStyle(isEmphasized ? Color.orange : Color.secondary)
                .accessibilityLabel(shortEventTitle(for: eventID))
        } else {
            Text(shortEventTitle(for: eventID))
                .font(.system(size: isEmphasized ? 12 : 11, weight: .semibold))
                .foregroundStyle(isEmphasized ? Color.orange : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .accessibilityLabel(shortEventTitle(for: eventID))
        }
    }

    private func shortEventTitle(for eventID: String) -> String {
        switch eventID {
        case "222":
            return localizedCompetitionStringInView(key: "wca.event.short.2x2", languageCode: appLanguage)
        case "333":
            return localizedCompetitionStringInView(key: "wca.event.short.3x3", languageCode: appLanguage)
        case "444":
            return localizedCompetitionStringInView(key: "wca.event.short.4x4", languageCode: appLanguage)
        case "555":
            return localizedCompetitionStringInView(key: "wca.event.short.5x5", languageCode: appLanguage)
        case "666":
            return localizedCompetitionStringInView(key: "wca.event.short.6x6", languageCode: appLanguage)
        case "777":
            return localizedCompetitionStringInView(key: "wca.event.short.7x7", languageCode: appLanguage)
        case "333oh":
            return localizedCompetitionStringInView(key: "wca.event.short.oh", languageCode: appLanguage)
        case "clock":
            return localizedCompetitionStringInView(key: "wca.event.short.clock", languageCode: appLanguage)
        case "minx":
            return localizedCompetitionStringInView(key: "wca.event.short.megaminx", languageCode: appLanguage)
        case "pyram":
            return localizedCompetitionStringInView(key: "wca.event.short.pyraminx", languageCode: appLanguage)
        case "skewb":
            return localizedCompetitionStringInView(key: "wca.event.short.skewb", languageCode: appLanguage)
        case "sq1":
            return localizedCompetitionStringInView(key: "wca.event.short.square1", languageCode: appLanguage)
        case "333bf":
            return "3BLD"
        case "444bf":
            return "4BLD"
        case "555bf":
            return "5BLD"
        case "333fm":
            return "FMC"
        case "333mbf":
            return "MBLD"
        default:
            return eventID.uppercased()
        }
    }

    private func localizedCompetitorGender(_ rawValue: String?) -> String {
        guard let rawValue else { return "—" }

        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "m", "male", "男":
            return localizedCompetitionStringInView(key: "wca.gender.male", languageCode: appLanguage)
        case "f", "female", "女":
            return localizedCompetitionStringInView(key: "wca.gender.female", languageCode: appLanguage)
        case "o", "other", "其他":
            return localizedCompetitionStringInView(key: "wca.gender.other", languageCode: appLanguage)
        default:
            return rawValue
        }
    }

    private func detailTextBlockCards(_ blocks: [CompetitionDetailTextBlock], fallbackTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks) { block in
                detailSectionCard(title: block.title?.isEmpty == false ? block.title! : fallbackTitle) {
                    detailTextBlockBody(block)
                }
            }
        }
    }

    private func cubingDetailDocument(_ blocks: [CompetitionDetailTextBlock], fallbackTitle: String) -> some View {
        cubingDetailDocumentBody(blocks, fallbackTitle: fallbackTitle)
    }

    private func cubingDetailDocumentBody(
        _ blocks: [CompetitionDetailTextBlock],
        fallbackTitle: String,
        mapLocations: [CompetitionTravelMapLocation] = [],
        mapURL: URL? = nil
    ) -> some View {
        let visibleBlocks = blocks.filter { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let mapBlockID = cubingTravelMapAnchorBlockID(in: visibleBlocks, mapLocations: mapLocations)

        return VStack(alignment: .leading, spacing: 14) {
            ForEach(visibleBlocks) { block in
                CubingDetailDocumentBlock(
                    block: block,
                    fallbackTitle: fallbackTitle,
                    areEventIconsReady: areCompetitionEventIconsReady
                )

                if block.id == mapBlockID {
                    CompetitionTravelMapCard(
                        locations: mapLocations,
                        openMapsURL: mapURL
                    )
                }
            }
        }
    }

    private func cubingTravelMapAnchorBlockID(
        in blocks: [CompetitionDetailTextBlock],
        mapLocations: [CompetitionTravelMapLocation]
    ) -> String? {
        guard !mapLocations.isEmpty else { return nil }

        if let block = blocks.first(where: { $0.html?.contains("location-map") == true }) {
            return block.id
        }

        if let block = blocks.first(where: { block in
            let title = block.title ?? ""
            return title.localizedCaseInsensitiveContains("location")
                || title.localizedCaseInsensitiveContains("venue")
                || title.contains("地点")
                || title.contains("地址")
                || title.contains("地點")
                || title.contains("場地")
        }) {
            return block.id
        }

        return blocks.first?.id
    }

    private func detailTextBlocks(_ blocks: [CompetitionDetailTextBlock]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                VStack(alignment: .leading, spacing: 6) {
                    if let title = block.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                    detailTextBlockBody(block)
                }
            }
        }
    }

    @ViewBuilder
    private func detailTextBlockBody(_ block: CompetitionDetailTextBlock) -> some View {
        if let html = block.html, !html.isEmpty {
            CompetitionRichHTMLContent(html: html)
        } else {
            Text(block.body)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scheduleTableStyleMenu: some View {
        HStack {
            Spacer(minLength: 0)

            Menu {
                Button {
                    selectedScheduleTableStyleRaw = CompetitionScheduleTableStyle.cards.rawValue
                } label: {
                    Label(
                        localizedScheduleTableStyleTitle(.cards),
                        systemImage: selectedScheduleTableStyle == .cards ? "checkmark" : "rectangle.stack"
                    )
                }

                Button {
                    selectedScheduleTableStyleRaw = CompetitionScheduleTableStyle.table.rawValue
                } label: {
                    Label(
                        localizedScheduleTableStyleTitle(.table),
                        systemImage: selectedScheduleTableStyle == .table ? "checkmark" : "tablecells"
                    )
                }
            } label: {
                Label(localizedScheduleFieldLabel(.display), systemImage: "ellipsis.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func detailScheduleDayCard(_ day: CompetitionScheduleDay) -> some View {
        if selectedScheduleTableStyle == .table, isMainlandChinaCompetition {
            detailScheduleWebsiteDayPanel(day)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)

                    Text(day.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Text(String(format: "%d", day.entries.count))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.10), in: Capsule())
                }

                switch selectedScheduleTableStyle {
                case .cards:
                    ForEach(day.entries) { entry in
                        detailScheduleEntryCard(entry, showsVenue: true)
                    }
                case .table:
                    detailScheduleTraditionalTable(day, showsVenue: true)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.background)
            )
        }
    }

    private var cubingScheduleWebsiteIntro: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !detailContent.scheduleEventSummaries.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 148), alignment: .leading)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(detailContent.scheduleEventSummaries) { summary in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Image(systemName: "square")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(.secondary)

                            if let code = summary.eventCode,
                               !code.isEmpty,
                               let glyph = CompetitionEventIconFont.glyph(for: code) {
                                Text(glyph)
                                    .font(.custom(CompetitionEventIconFont.fontName, size: 15))
                                    .foregroundStyle(.primary)
                                    .frame(width: 18, alignment: .center)
                                    .offset(y: 1)
                            }

                            Text(summary.detail)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let html = detailContent.scheduleIntroHTML, !html.isEmpty {
                CompetitionRichHTMLContent(html: html, areEventIconsReady: areCompetitionEventIconsReady)
                    .font(.system(size: 13, weight: .regular))
            }
        }
    }

    @ViewBuilder
    private var cubingScheduleWebsiteComment: some View {
        if let html = detailContent.scheduleCommentHTML, !html.isEmpty {
            CompetitionRichHTMLContent(html: html, areEventIconsReady: areCompetitionEventIconsReady)
                .padding(.top, 2)
        }
    }

    private func detailScheduleWebsiteDayPanel(_ day: CompetitionScheduleDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(day.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(detailScheduleWebsiteDateTextColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(detailScheduleWebsiteDateBarColor)

            detailScheduleTraditionalTable(day, showsVenue: false)
        }
        .overlay(
            Rectangle()
                .stroke(detailScheduleWebsitePanelBorderColor, lineWidth: 1)
        )
    }

    private var cubingScheduleCalendar: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(detailContent.scheduleDays) { day in
                cubingScheduleCalendarDay(day)
            }
        }
    }

    private func cubingScheduleCalendarDay(_ day: CompetitionScheduleDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)

                Text(day.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(String(format: "%d 项", day.entries.count))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(day.venues) { venue in
                        cubingScheduleCalendarVenueColumn(venue)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.background)
        )
    }

    private func cubingScheduleCalendarVenueColumn(_ venue: CompetitionScheduleVenue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(venue.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text("\(venue.entries.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.10), in: Capsule())
            }

            ForEach(venue.entries) { entry in
                cubingScheduleCalendarBlock(entry)
            }
        }
        .padding(12)
        .frame(width: 210, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func cubingScheduleCalendarBlock(_ entry: CompetitionScheduleEntry) -> some View {
        let color = cubingScheduleEventColor(for: entry)
        let chips = cubingScheduleCalendarChips(for: entry)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.timeText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)

                Spacer(minLength: 6)

                if let eventCode = entry.eventCode, !eventCode.isEmpty {
                    Text(shortEventTitle(for: eventCode))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.12), in: Capsule())
                }
            }

            Text(entry.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !chips.isEmpty {
                FlexibleTagFlow(items: Array(chips.prefix(3)))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }

    private func cubingScheduleCalendarChips(for entry: CompetitionScheduleEntry) -> [String] {
        var chips: [String] = []

        if let round = entry.round, !round.isEmpty {
            chips.append(round)
        }
        if let cutoff = entry.cutoff, !cutoff.isEmpty {
            chips.append(appLanguage.hasPrefix("zh") ? "及格线 \(cutoff)" : "Cutoff \(cutoff)")
        }
        if let timeLimit = entry.timeLimit, !timeLimit.isEmpty {
            chips.append(appLanguage.hasPrefix("zh") ? "时限 \(timeLimit)" : "Limit \(timeLimit)")
        }
        if let advancingCount = entry.advancingCount, !advancingCount.isEmpty {
            chips.append(appLanguage.hasPrefix("zh") ? "晋级 \(advancingCount)" : "Top \(advancingCount)")
        }

        return chips
    }

    private func cubingScheduleEventColor(for entry: CompetitionScheduleEntry) -> Color {
        switch entry.eventCode ?? "" {
        case "222":
            return .cyan
        case "333":
            return .blue
        case "444":
            return .indigo
        case "555", "666", "777":
            return .purple
        case "333bf", "444bf", "555bf", "333mbf":
            return .red
        case "333oh":
            return .orange
        case "clock":
            return .pink
        case "minx":
            return .teal
        case "pyram", "skewb":
            return .green
        case "sq1":
            return .yellow
        default:
            return .orange
        }
    }

    private func detailScheduleEntryCard(_ entry: CompetitionScheduleEntry, showsVenue: Bool) -> some View {
        let times = detailScheduleTimeParts(entry.timeText)
        let roundValue = detailScheduleOptionalValue(entry.round)
        let venueValue = showsVenue ? detailScheduleOptionalValue(entry.venueName) : nil
        let groupValue = detailScheduleOptionalValue(entry.group)
        let formatValue = detailScheduleOptionalValue(entry.format)
        let cutoffValue = detailScheduleOptionalValue(entry.cutoff)
        let timeLimitValue = detailScheduleOptionalValue(entry.timeLimit)
        let proceedValue = detailScheduleOptionalValue(entry.advancingCount)
        let color = cubingScheduleEventColor(for: entry)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(times.start)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    HStack(spacing: 4) {
                        Text(localizedScheduleFieldLabel(.start))
                        if let end = times.end {
                            Text("->")
                            Text(end)
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }
                .frame(width: 86, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let eventCode = entry.eventCode, !eventCode.isEmpty {
                            competitionEventIconLabel(for: eventCode, isEmphasized: true)
                                .frame(width: 24, alignment: .center)
                        }

                        Text(entry.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 6) {
                        if let roundValue {
                            detailScheduleCapsule(roundValue, color: color)
                        }
                        if let formatValue {
                            detailScheduleCapsule(formatValue, color: .secondary)
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 8) {
                if let cutoffValue {
                    detailScheduleInfoPill(
                        label: localizedScheduleFieldLabel(.cutoff),
                        value: cutoffValue
                    )
                }
                if let timeLimitValue {
                    detailScheduleInfoPill(
                        label: localizedScheduleFieldLabel(.timeLimit),
                        value: timeLimitValue
                    )
                }
                if let proceedValue {
                    detailScheduleInfoPill(
                        label: localizedScheduleFieldLabel(.proceed),
                        value: proceedValue
                    )
                }
            }

            if venueValue != nil || groupValue != nil {
                HStack(spacing: 8) {
                    if let venueValue {
                        detailScheduleMetaText(
                        label: localizedScheduleFieldLabel(.venue),
                            value: venueValue
                    )
                    }

                    if let groupValue {
                        detailScheduleMetaText(
                        label: localizedScheduleFieldLabel(.group),
                            value: groupValue
                    )
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }

    private func detailScheduleTraditionalTable(_ day: CompetitionScheduleDay, showsVenue: Bool) -> some View {
        let isWebsiteTable = selectedScheduleTableStyle == .table && isMainlandChinaCompetition

        return ScrollView(.horizontal, showsIndicators: true) {
            ZStack(alignment: .topTrailing) {
                if isWebsiteTable {
                    detailScheduleWebsiteWatermark
                        .padding(.top, 20)
                        .padding(.trailing, 20)
                }

                VStack(spacing: 0) {
                    detailScheduleTraditionalHeader(showsVenue: showsVenue)

                    ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                        detailScheduleHorizontalDivider
                        detailScheduleTraditionalRow(entry, index: index, showsVenue: showsVenue)
                    }
                }
                .frame(minWidth: detailScheduleTraditionalTableWidth(showsVenue: showsVenue), alignment: .leading)
            }
        }
        .background(isWebsiteTable ? Color.white : Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(
            Rectangle()
                .stroke(isWebsiteTable ? detailScheduleWebsitePanelBorderColor : Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .clipShape(Rectangle())
    }

    private func detailScheduleTraditionalHeader(showsVenue: Bool) -> some View {
        HStack(spacing: 0) {
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.start), width: detailScheduleStartColumnWidth)
            detailScheduleVerticalDivider
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.end), width: detailScheduleEndColumnWidth)
            detailScheduleVerticalDivider
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.event), width: detailScheduleEventColumnWidth)
            detailScheduleVerticalDivider
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.round), width: detailScheduleRoundColumnWidth)
            detailScheduleVerticalDivider
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.format), width: detailScheduleFormatColumnWidth)
            detailScheduleVerticalDivider
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.cutoff), width: detailScheduleCutoffColumnWidth)
            detailScheduleVerticalDivider
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.timeLimit), width: detailScheduleTimeLimitColumnWidth)
            detailScheduleVerticalDivider
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.proceed), width: detailScheduleCompetitorsColumnWidth)

            if showsVenue {
                detailScheduleVerticalDivider
                detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.venue), width: 120)
                detailScheduleVerticalDivider
                detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.group), width: 96)
            }
        }
        .background(selectedScheduleTableStyle == .table && isMainlandChinaCompetition ? detailScheduleWebsiteHeaderColor : Color.secondary.opacity(0.08))
    }

    private func detailScheduleTraditionalRow(_ entry: CompetitionScheduleEntry, index: Int, showsVenue: Bool) -> some View {
        let times = detailScheduleTimeParts(entry.timeText)
        let roundValue = detailScheduleOptionalValue(entry.round)
        let venueValue = showsVenue ? detailScheduleOptionalValue(entry.venueName) : nil
        let groupValue = detailScheduleOptionalValue(entry.group)
        let formatValue = detailScheduleOptionalValue(entry.format)
        let cutoffValue = detailScheduleOptionalValue(entry.cutoff)
        let timeLimitValue = detailScheduleOptionalValue(entry.timeLimit)
        let proceedValue = detailScheduleOptionalValue(entry.advancingCount)

        let blankValue = selectedScheduleTableStyle == .table && isMainlandChinaCompetition ? "" : "—"

        return HStack(spacing: 0) {
            detailScheduleTraditionalCell(times.start, width: detailScheduleStartColumnWidth, role: .time)
            detailScheduleVerticalDivider
            detailScheduleTraditionalCell(times.end ?? blankValue, width: detailScheduleEndColumnWidth, role: .time)
            detailScheduleVerticalDivider
            detailScheduleTraditionalEventCell(entry, width: detailScheduleEventColumnWidth)
            detailScheduleVerticalDivider
            detailScheduleTraditionalCell(roundValue ?? blankValue, width: detailScheduleRoundColumnWidth, role: .secondary)
            detailScheduleVerticalDivider
            detailScheduleTraditionalCell(formatValue ?? blankValue, width: detailScheduleFormatColumnWidth, role: .secondary)
            detailScheduleVerticalDivider
            detailScheduleTraditionalCell(cutoffValue ?? blankValue, width: detailScheduleCutoffColumnWidth, role: .secondary)
            detailScheduleVerticalDivider
            detailScheduleTraditionalCell(timeLimitValue ?? blankValue, width: detailScheduleTimeLimitColumnWidth, role: .secondary)
            detailScheduleVerticalDivider
            detailScheduleTraditionalCell(proceedValue ?? blankValue, width: detailScheduleCompetitorsColumnWidth, role: .secondary)

            if showsVenue {
                detailScheduleVerticalDivider
                detailScheduleTraditionalCell(venueValue ?? "—", width: 120, role: .secondary)
                detailScheduleVerticalDivider
                detailScheduleTraditionalCell(groupValue ?? "—", width: 96, role: .secondary)
            }
        }
        .background(selectedScheduleTableStyle == .table && isMainlandChinaCompetition ? Color.clear : (index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.025)))
    }

    private func detailScheduleCapsule(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.10), in: Capsule())
    }

    private func detailScheduleInfoPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.70), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func detailScheduleMetaText(label: String, value: String) -> some View {
        Text("\(label): \(value)")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private enum DetailScheduleCellRole {
        case time
        case event
        case secondary
    }

    private func detailScheduleTraditionalHeaderCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(selectedScheduleTableStyle == .table && isMainlandChinaCompetition ? Color.white : Color.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(width: width, alignment: .leading)
    }

    private func detailScheduleTraditionalCell(_ text: String, width: CGFloat, role: DetailScheduleCellRole) -> some View {
        Text(text)
            .font(detailScheduleCellValueFont(for: role))
            .foregroundStyle(Color.primary.opacity(role == .secondary ? 0.88 : 1))
            .lineLimit(role == .event ? 2 : 1)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
            .frame(width: width, alignment: .leading)
    }

    private func detailScheduleTraditionalEventCell(_ entry: CompetitionScheduleEntry, width: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            detailScheduleEventIcon(for: entry)
                .frame(width: 22, alignment: .center)

            Text(entry.title)
                .font(detailScheduleCellValueFont(for: .event))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func detailScheduleEventIcon(for entry: CompetitionScheduleEntry) -> some View {
        let code = entry.eventCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let code, !code.isEmpty {
            competitionEventIconLabel(for: code, isEmphasized: true)
                .accessibilityLabel(entry.title)
        }
    }

    private var detailScheduleHorizontalDivider: some View {
        Rectangle()
            .fill(selectedScheduleTableStyle == .table && isMainlandChinaCompetition ? detailScheduleWebsiteGridColor : Color.secondary.opacity(0.10))
            .frame(height: 1)
    }

    private var detailScheduleVerticalDivider: some View {
        Rectangle()
            .fill(selectedScheduleTableStyle == .table && isMainlandChinaCompetition ? detailScheduleWebsiteGridColor : Color.secondary.opacity(0.10))
            .frame(width: 1)
    }

    private func detailScheduleCellValueFont(for role: DetailScheduleCellRole) -> Font {
        switch role {
        case .time:
            return .system(size: selectedScheduleTableStyle == .table && isMainlandChinaCompetition ? 12 : 14, weight: .regular, design: .default)
        case .event:
            return .system(size: selectedScheduleTableStyle == .table && isMainlandChinaCompetition ? 12 : 15, weight: selectedScheduleTableStyle == .table && isMainlandChinaCompetition ? .regular : .semibold)
        case .secondary:
            return .system(size: selectedScheduleTableStyle == .table && isMainlandChinaCompetition ? 12 : 13, weight: .regular)
        }
    }

    private var detailScheduleStartColumnWidth: CGFloat { selectedScheduleTableStyle == .table && isMainlandChinaCompetition ? 72 : 74 }
    private var detailScheduleEndColumnWidth: CGFloat { selectedScheduleTableStyle == .table && isMainlandChinaCompetition ? 72 : 74 }
    private var detailScheduleEventColumnWidth: CGFloat { selectedScheduleTableStyle == .table && isMainlandChinaCompetition ? 236 : 230 }
    private var detailScheduleRoundColumnWidth: CGFloat { selectedScheduleTableStyle == .table && isMainlandChinaCompetition ? 102 : 108 }
    private var detailScheduleFormatColumnWidth: CGFloat { selectedScheduleTableStyle == .table && isMainlandChinaCompetition ? 156 : 132 }
    private var detailScheduleCutoffColumnWidth: CGFloat { selectedScheduleTableStyle == .table && isMainlandChinaCompetition ? 145 : 132 }
    private var detailScheduleTimeLimitColumnWidth: CGFloat { selectedScheduleTableStyle == .table && isMainlandChinaCompetition ? 145 : 132 }
    private var detailScheduleCompetitorsColumnWidth: CGFloat { selectedScheduleTableStyle == .table && isMainlandChinaCompetition ? 72 : 92 }

    private var detailScheduleWebsiteHeaderColor: Color { Color(red: 0.38, green: 0.57, blue: 0.73) }
    private var detailScheduleWebsiteDateBarColor: Color { Color(red: 0.84, green: 0.94, blue: 0.98) }
    private var detailScheduleWebsiteDateTextColor: Color { Color(red: 0.22, green: 0.51, blue: 0.66) }
    private var detailScheduleWebsiteGridColor: Color { Color(red: 0.86, green: 0.86, blue: 0.86) }
    private var detailScheduleWebsitePanelBorderColor: Color { Color(red: 0.70, green: 0.88, blue: 0.94) }

    private var detailScheduleWebsiteWatermark: some View {
        Image(systemName: "circle.hexagongrid.circle")
            .font(.system(size: 180, weight: .light))
            .foregroundStyle(Color(red: 0.38, green: 0.57, blue: 0.73).opacity(0.06))
            .allowsHitTesting(false)
    }

    private func detailScheduleTraditionalTableWidth(showsVenue: Bool) -> CGFloat {
        let baseWidth = detailScheduleStartColumnWidth
            + detailScheduleEndColumnWidth
            + detailScheduleEventColumnWidth
            + detailScheduleRoundColumnWidth
            + detailScheduleFormatColumnWidth
            + detailScheduleCutoffColumnWidth
            + detailScheduleTimeLimitColumnWidth
            + detailScheduleCompetitorsColumnWidth
            + 7
        return showsVenue ? baseWidth + 120 + 96 + 2 : baseWidth
    }

    private func detailScheduleOptionalValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func detailScheduleTimeParts(_ timeText: String) -> (start: String, end: String?) {
        let separators = ["–", "-", "—", "~"]
        for separator in separators {
            let parts = timeText.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.count >= 2 {
                return (parts[0], parts[1])
            }
        }

        return (timeText, nil)
    }

    private enum ScheduleFieldLabel {
        case display
        case start
        case end
        case event
        case round
        case format
        case cutoff
        case timeLimit
        case proceed
        case venue
        case group
    }

    private func localizedScheduleFieldLabel(_ label: ScheduleFieldLabel) -> String {
        let isChinese = appLanguage.hasPrefix("zh")
        switch label {
        case .display:
            return isChinese ? "显示方式" : "View"
        case .start:
            return isChinese ? "开始" : "Start"
        case .end:
            return isChinese ? "结束" : "End"
        case .event:
            return isChinese ? "项目" : "Event"
        case .round:
            return isChinese ? "轮次" : "Round"
        case .format:
            return isChinese ? "赛制" : "Format"
        case .cutoff:
            return isChinese ? "及格线" : "Cutoff"
        case .timeLimit:
            return isChinese ? "时限" : "Time Limit"
        case .proceed:
            return isChinese ? "晋级" : "Proceed"
        case .venue:
            return isChinese ? "场地" : "Venue"
        case .group:
            return isChinese ? "分组" : "Group"
        }
    }

    private func localizedScheduleTableStyleTitle(_ style: CompetitionScheduleTableStyle) -> String {
        let isChinese = appLanguage.hasPrefix("zh")
        switch style {
        case .cards:
            return isChinese ? "卡片" : "Cards"
        case .table:
            return isChinese ? "表格" : "Table"
        }
    }

    private var wcaLiveRoundPicker: some View {
        Picker(
            localizedCompetitionStringInView(key: "competitions.detail.live.wca.rounds", languageCode: appLanguage),
            selection: Binding(
                get: { effectiveWCALiveRoundID },
                set: { selectedWCALiveRoundID = $0 }
            )
        ) {
            ForEach(groupedWCALiveRounds, id: \.eventID) { group in
                Section(shortEventTitle(for: group.eventID)) {
                    ForEach(group.rounds) { round in
                        Text(round.roundName)
                            .tag(round.id)
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .tint(.primary)
    }

    private var groupedWCALiveRounds: [(eventID: String, rounds: [CompetitionWCALiveRound])] {
        Dictionary(grouping: wcaLiveRounds, by: \.eventID)
            .keys
            .sorted()
            .map { eventID in
                let rounds = wcaLiveRounds
                    .filter { $0.eventID == eventID }
                    .sorted { lhs, rhs in (lhs.number ?? 0) < (rhs.number ?? 0) }
                return (eventID: eventID, rounds: rounds)
            }
    }

    private func wcaLiveResultsTable(_ round: CompetitionWCALiveRound) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                competitionEventIconLabel(for: round.eventID, isEmphasized: true)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(round.roundName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(round.eventName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                if round.isActive || round.isOpen {
                    Text(
                        localizedCompetitionStringInView(
                            key: round.isActive ? "competitions.detail.live.wca.active" : "competitions.detail.live.wca.open",
                            languageCode: appLanguage
                        )
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(round.isActive ? Color.orange : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(round.isActive ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.08))
                    )
                }
            }

            if round.results.isEmpty {
                Text(liveStatusBody)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        wcaLiveResultsHeader

                        Divider()
                            .padding(.vertical, 8)

                        VStack(spacing: 10) {
                            ForEach(round.results) { result in
                                wcaLiveResultsRow(result, eventID: round.eventID)
                            }
                        }
                    }
                    .padding(12)
                }
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var wcaLiveResultsHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            wcaLiveHeaderCell("#", width: 36)
            wcaLiveHeaderCell(localizedCompetitionStringInView(key: "competitions.detail.competitors_column.name", languageCode: appLanguage), width: 180)
            wcaLiveHeaderCell(localizedCompetitionStringInView(key: "competitions.detail.competitors_column.region", languageCode: appLanguage), width: 96)
            ForEach(1...5, id: \.self) { attempt in
                wcaLiveHeaderCell("\(attempt)", width: 58)
            }
            wcaLiveHeaderCell(localizedCompetitionStringInView(key: "wca.results_average", languageCode: appLanguage), width: 78)
            wcaLiveHeaderCell(localizedCompetitionStringInView(key: "common.best", languageCode: appLanguage), width: 68)
        }
    }

    private func wcaLiveHeaderCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
    }

    private func wcaLiveResultsRow(_ result: CompetitionWCALiveResultPreview, eventID: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(result.ranking)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.orange)
                .frame(width: 36, alignment: .leading)

            Text(result.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)

            Text(result.region ?? "—")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)

            ForEach(0..<5, id: \.self) { index in
                Text(wcaLiveAttemptText(result.attempts, index: index, eventID: eventID))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 58, alignment: .leading)
            }

            Text(formatCompetitionLiveResultValue(result.average, eventID: eventID))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 78, alignment: .leading)

            Text(formatCompetitionLiveResultValue(result.best, eventID: eventID))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 68, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private func wcaLiveAttemptText(_ attempts: [Int], index: Int, eventID: String) -> String {
        guard attempts.indices.contains(index) else { return "—" }
        return formatCompetitionLiveResultValue(attempts[index], eventID: eventID)
    }

    private func wcaLiveVenueCard(_ venue: CompetitionWCALiveVenue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(venue.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                if let countryName = venue.countryName, !countryName.isEmpty {
                    Text(countryName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(venue.rooms) { room in
                VStack(alignment: .leading, spacing: 3) {
                    Text(room.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let subtitle = wcaLiveRoomSubtitle(room) {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.background)
        )
    }

    private func wcaLiveRoomSubtitle(_ room: CompetitionWCALiveRoom) -> String? {
        if let currentActivityName = room.currentActivityName {
            if let start = room.currentActivityStart, let end = room.currentActivityEnd {
                return "\(localizedCompetitionStringInView(key: "competitions.detail.live.wca.now", languageCode: appLanguage)) · \(localizedCompetitionTime(start))–\(localizedCompetitionTime(end)) · \(currentActivityName)"
            }
            return "\(localizedCompetitionStringInView(key: "competitions.detail.live.wca.now", languageCode: appLanguage)) · \(currentActivityName)"
        }

        if let nextActivityName = room.nextActivityName,
           let nextActivityStart = room.nextActivityStart {
            return "\(localizedCompetitionStringInView(key: "competitions.detail.live.wca.next", languageCode: appLanguage)) · \(localizedCompetitionTime(nextActivityStart)) · \(nextActivityName)"
        }

        return nil
    }

    private func localizedCompetitionTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLocale(for: appLanguage)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func loadDetailContent() async {
        isLoadingDetail = true
        detailContent = .empty
        updateCompetitionDetailDerivedState()
        let fetched = await CompetitionService.fetchCompetitionDetail(
            for: competition,
            languageCode: appLanguage
        )
        detailContent = fetched
        updateCompetitionDetailDerivedState()
        isLoadingDetail = false

        await loadCompetitionCompetitorsIfNeeded()
        await loadWCALiveContentIfNeeded()
    }

    private func refreshDetailContent() async {
        guard !isRefreshingDetail else { return }
        isRefreshingDetail = true
        defer { isRefreshingDetail = false }

        let fetched = await CompetitionService.fetchCompetitionDetail(
            for: competition,
            languageCode: appLanguage,
            forceRefresh: true,
            includeCompetitors: selectedTab == .competitors,
            includeLive: selectedTab == .live
        )
        detailContent = fetched
        psychPreviewCache = [:]
        wcaLiveContentOverride = nil
        updateCompetitionDetailDerivedState()

        await loadCompetitionCompetitorsIfNeeded()
        await loadWCALiveContentIfNeeded()

        if selectedTab == .competitors,
           selectedCompetitorsMode == .psych,
           isPsychModeAvailable {
            await loadPsychPreviewsIfNeeded()
        }
    }

    private func loadCompetitionCompetitorsIfNeeded() async {
        guard selectedTab == .competitors else { return }
        guard detailContent.competitorPreviews.isEmpty else { return }
        guard !isLoadingCompetitors else { return }

        isLoadingCompetitors = true
        let fetched = await CompetitionService.fetchCompetitionDetail(
            for: competition,
            languageCode: appLanguage,
            includeCompetitors: true
        )
        detailContent = detailContent.replacingCompetitors(from: fetched)
        updateCompetitionDetailDerivedState()
        isLoadingCompetitors = false
    }

    private func loadWCALiveContentIfNeeded() async {
        guard selectedTab == .live else { return }
        guard !isLoadingWCALive else { return }

        if isMainlandChinaCompetition {
            guard detailContent.liveContent == nil else { return }
        } else {
            guard shouldRefreshWCALiveContent else { return }
        }

        isLoadingWCALive = true
        let fetched = await CompetitionService.fetchCompetitionDetail(
            for: competition,
            languageCode: appLanguage,
            includeLive: true
        )
        detailContent = detailContent.replacingLive(from: fetched)
        wcaLiveContentOverride = nil
        isLoadingWCALive = false
    }

    private func loadPsychPreviewsIfNeeded() async {
        guard selectedTab == .competitors,
              selectedCompetitorsMode == .psych,
              isPsychModeAvailable else { return }

        if psychPreviewCache[currentPsychCacheKey] != nil {
            return
        }

        isLoadingPsych = true
        let previews = await CompetitionService.fetchCompetitionPsychPreviews(
            for: competition,
            languageCode: appLanguage,
            eventID: selectedCompetitorEventID.isEmpty ? nil : selectedCompetitorEventID
        )
        psychPreviewCache[currentPsychCacheKey] = previews
        updateCompetitionDetailDerivedState()
        isLoadingPsych = false
    }

    private func updateCompetitionDetailDerivedState() {
        let matrixEventIDs = CompetitionEventFilter.selectableCases
            .map(\.wcaEventID)
            .filter { competition.eventIDs.contains($0) }
        competitorMatrixEventIDsSnapshot = matrixEventIDs
        showsCompetitorNumbersSnapshot = detailContent.competitorPreviews.contains { $0.number != nil }
        showsCompetitorGenderSnapshot = detailContent.competitorPreviews.contains { $0.gender != nil }

        let query = competitorSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredCompetitorsSnapshot = detailContent.competitorPreviews.filter { competitor in
            let matchesQuery = query.isEmpty
                || competitor.name.localizedCaseInsensitiveContains(query)
                || (competitor.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
            let matchesEvent = selectedCompetitorEventID.isEmpty
                || competitor.registeredEventIDs.contains(selectedCompetitorEventID)
            return matchesQuery && matchesEvent
        }

        let psychEventIDs = selectedCompetitorEventID.isEmpty
            ? matrixEventIDs
            : matrixEventIDs.filter { $0 == selectedCompetitorEventID }
        psychMatrixEventIDsSnapshot = psychEventIDs

        let psychPreviews = psychPreviewCache[currentPsychCacheKey] ?? []
        let filteredPsych = query.isEmpty
            ? psychPreviews
            : psychPreviews.filter { $0.name.localizedCaseInsensitiveContains(query) }
        filteredPsychCompetitorsSnapshot = filteredPsych

        guard selectedCompetitorEventID.isEmpty else {
            psychOverallRankByCompetitorIDSnapshot = [:]
            displayedPsychCompetitorsSnapshot = filteredPsych
            return
        }

        let scored = filteredPsych.map { competitor in
            (
                competitor,
                competitor.items
                    .filter { psychEventIDs.contains($0.eventID) }
                    .map(\.rank)
                    .reduce(0, +)
            )
        }
        .filter { !$0.0.items.isEmpty && $0.1 > 0 }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
        }

        let rankByID = Dictionary(uniqueKeysWithValues: scored.enumerated().map { index, element in
            (element.0.id, index + 1)
        })
        psychOverallRankByCompetitorIDSnapshot = rankByID
        displayedPsychCompetitorsSnapshot = filteredPsych.sorted { lhs, rhs in
            let lhsRank = rankByID[lhs.id] ?? .max
            let rhsRank = rankByID[rhs.id] ?? .max
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func detailSectionStack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
    }

    private func detailSectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.background)
        )
    }

    private func detailLine(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .center)

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detailActionLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.secondary.opacity(0.08))
        )
    }

    private func detailPrimaryButton(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.orange)
            )
    }

    private func detailSecondaryLink(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Color.orange)
    }

    private func localizedCompetitionDateRange(startingAt date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLocale(for: appLanguage)
        formatter.dateFormat = localizedCompetitionStringInView(key: "competition.date.full_format", languageCode: appLanguage)
        return formatter.string(from: date)
    }

    private func localizedCompetitionDateRange(for competition: CompetitionSummary) -> String {
        let locale = appLocale(for: appLanguage)
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar

        let sameYear = calendar.component(.year, from: competition.startDate) == calendar.component(.year, from: competition.endDate)
        let sameMonth = sameYear && calendar.component(.month, from: competition.startDate) == calendar.component(.month, from: competition.endDate)
        let sameDay = sameMonth && calendar.component(.day, from: competition.startDate) == calendar.component(.day, from: competition.endDate)

        formatter.dateFormat = localizedCompetitionStringInView(key: "competition.date.full_format", languageCode: appLanguage)
        if sameDay {
            return formatter.string(from: competition.startDate)
        }
        if sameMonth {
            let monthFormatter = DateFormatter()
            monthFormatter.locale = locale
            monthFormatter.calendar = calendar
            monthFormatter.dateFormat = localizedCompetitionStringInView(key: "competition.date.month_day_format", languageCode: appLanguage)
            let start = monthFormatter.string(from: competition.startDate)
            formatter.dateFormat = localizedCompetitionStringInView(key: "competition.date.day_suffix_format", languageCode: appLanguage)
            return "\(start) - \(formatter.string(from: competition.endDate))"
        }
        return "\(formatter.string(from: competition.startDate)) - \(formatter.string(from: competition.endDate))"
    }

    private func competitionAvailabilityStatus(for competition: CompetitionSummary) -> CompetitionAvailabilityStatus {
        if let localizedStatusOverride = competition.localizedStatusOverride {
            return localizedStatusOverride
        }

        let now = Date()
        let today = Calendar.current.startOfDay(for: now)

        if competition.endDate < today {
            return .ended
        }

        let startOfCompetition = Calendar.current.startOfDay(for: competition.startDate)
        let endOfCompetition = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: competition.endDate))
            ?? competition.endDate
        if now >= startOfCompetition && now < endOfCompetition {
            return .ongoing
        }

        if let open = competition.registrationOpen,
           let close = competition.registrationClose,
           open <= now && close >= now {
            return .registrationOpen
        }

        return .upcoming
    }

    private func daysUntil(_ date: Date?) -> Int {
        guard let date else { return 0 }
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return max(calendar.dateComponents([.day], from: now, to: target).day ?? 0, 0)
    }

    private func statusBadge(for status: CompetitionAvailabilityStatus, competition: CompetitionSummary, languageCode: String) -> some View {
        let badgeColor = statusColor(for: status, competition: competition)
        return Text(statusBadgeTitle(for: status, competition: competition, languageCode: languageCode))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(badgeColor.opacity(0.12), in: Capsule())
    }

    private func statusBadgeTitle(for status: CompetitionAvailabilityStatus, competition: CompetitionSummary, languageCode: String) -> String {
        switch status {
        case .registrationNotOpenYet:
            let days = daysUntil(competition.localizedRegistrationStartOverride)
            return String(
                format: localizedCompetitionStringInView(
                    key: "competitions.status.registration_not_open_yet_in_format",
                    languageCode: languageCode
                ),
                days
            )
        case .waitlist:
            if let waitlistStart = competition.localizedWaitlistStartOverride, Date() < waitlistStart {
                let days = daysUntil(waitlistStart)
                return String(
                    format: localizedCompetitionStringInView(
                        key: "competitions.status.waitlist_in_format",
                        languageCode: languageCode
                    ),
                    days
                )
            }
            return localizedCompetitionStringInView(
                key: "competitions.status.waitlist_open",
                languageCode: languageCode
            )
        default:
            return status.localizedTitle(languageCode: languageCode)
        }
    }

    private func statusColor(for status: CompetitionAvailabilityStatus, competition: CompetitionSummary) -> Color {
        if status == .waitlist {
            if let waitlistStart = competition.localizedWaitlistStartOverride, Date() < waitlistStart {
                return .teal
            }
            return .teal
        }

        switch status {
        case .upcoming:
            return .orange
        case .registrationNotOpenYet:
            return .yellow
        case .registrationOpen:
            return .green
        case .waitlist:
            return .mint
        case .ongoing:
            return .blue
        case .ended:
            return .secondary
        }
    }
}

private struct CubingDetailDocumentBlock: View {
    let block: CompetitionDetailTextBlock
    let fallbackTitle: String
    let areEventIconsReady: Bool

    @State private var isExpanded = false

    private var title: String? {
        guard let title = block.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }
        return title
    }

    private var isEntryFeeBlock: Bool {
        title?.localizedCaseInsensitiveContains("entry fee") == true
            || title?.contains("报名费") == true
            || title?.contains("報名費") == true
    }

    private var isContactBlock: Bool {
        guard let title else { return false }
        return title.localizedCaseInsensitiveContains("organizer")
            || title.localizedCaseInsensitiveContains("delegate")
            || title.contains("主办")
            || title.contains("主辦")
            || title.contains("代表")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    if isEntryFeeBlock {
                        Button {
                            withAnimation(.snappy(duration: 0.18)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Text(isExpanded ? "less" : "more")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                }
            }

            if isContactBlock, let html = block.html {
                let contacts = CubingContactLink.links(from: html)
                if contacts.isEmpty {
                    richContent
                } else {
                    CubingContactLinksView(contacts: contacts)
                }
            } else {
                richContent
            }
        }
    }

    private var richContent: some View {
        CompetitionRichHTMLContent(
            html: block.html ?? block.body,
            tableRowLimit: isEntryFeeBlock && !isExpanded ? 2 : nil,
            areEventIconsReady: areEventIconsReady
        )
    }
}

private struct CubingContactLink: Identifiable {
    let id: String
    let name: String
    let email: String

    var url: URL? {
        URL(string: "mailto:\(email)")
    }

    static func links(from html: String) -> [CubingContactLink] {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<a\b[^>]*href=['\"]mailto:([^'\"]+)['\"][^>]*>(.*?)</a>"#) else {
            return []
        }
        let nsHTML = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)).compactMap { match in
            guard match.numberOfRanges > 2 else { return nil }
            let email = simpleHTMLDecode(nsHTML.substring(with: match.range(at: 1))).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawName = nsHTML.substring(with: match.range(at: 2))
            let name = simpleHTMLDecode(
                rawName.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !email.isEmpty, !name.isEmpty else { return nil }
            return CubingContactLink(id: "\(email)-\(name)", name: name, email: email)
        }
    }
}

private struct CubingContactLinksView: View {
    let contacts: [CubingContactLink]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(contacts) { contact in
                if let url = contact.url {
                    Link(destination: url) {
                        contactLabel(contact.name)
                    }
                } else {
                    contactLabel(contact.name)
                }
            }
        }
    }

    private func contactLabel(_ name: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(name)
                .font(.system(size: 15, weight: .regular))
        }
        .foregroundStyle(.blue)
    }
}

private struct CompetitionTravelMapAnnotation: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
}

private struct CompetitionTravelMapCard: View {
    let locations: [CompetitionTravelMapLocation]
    let openMapsURL: URL?

    @State private var region: MKCoordinateRegion

    init(locations: [CompetitionTravelMapLocation], openMapsURL: URL?) {
        self.locations = locations
        self.openMapsURL = openMapsURL
        _region = State(initialValue: Self.initialRegion(for: locations))
    }

    private var annotationItems: [CompetitionTravelMapAnnotation] {
        locations.map { location in
            CompetitionTravelMapAnnotation(
                id: location.id,
                title: location.venue.isEmpty ? location.address : location.venue,
                subtitle: location.address,
                coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            )
        }
    }

    var body: some View {
        Map(coordinateRegion: $region, annotationItems: annotationItems) { item in
            MapAnnotation(coordinate: item.coordinate) {
                Image(systemName: "mappin")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.red)
                    .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            if let openMapsURL {
                Link(destination: openMapsURL) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 34, height: 34)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
    }

    private static func initialRegion(for locations: [CompetitionTravelMapLocation]) -> MKCoordinateRegion {
        let coordinates = locations.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }

        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }

        guard coordinates.count > 1 else {
            return MKCoordinateRegion(
                center: first,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            )
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLatitude = latitudes.min() ?? first.latitude
        let maxLatitude = latitudes.max() ?? first.latitude
        let minLongitude = longitudes.min() ?? first.longitude
        let maxLongitude = longitudes.max() ?? first.longitude

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLatitude - minLatitude) * 1.6, 0.012),
                longitudeDelta: max((maxLongitude - minLongitude) * 1.6, 0.012)
            )
        )
    }
}

private func simpleHTMLDecode(_ text: String) -> String {
    text
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&apos;", with: "'")
}

private struct CompetitionRichHTMLContent: View {
    let elements: [CompetitionRichHTMLElement]
    let tableRowLimit: Int?
    let areEventIconsReady: Bool

    init(html: String, tableRowLimit: Int? = nil, areEventIconsReady: Bool = false) {
        self.elements = CompetitionRichHTMLElement.parse(html)
        self.tableRowLimit = tableRowLimit
        self.areEventIconsReady = areEventIconsReady
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                switch element.kind {
                case .heading(let text, let level):
                    Text(text)
                        .font(.system(size: level <= 2 ? 18 : 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, level <= 2 ? 4 : 2)
                case .paragraph(let text):
                    Text(text)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.primary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                case .linkedText(let runs):
                    LinkedTextFlow(runs: runs)
                case .list(let items):
                    richList(items: items)
                case .eventLine(let eventID, let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if areEventIconsReady, let glyph = CompetitionEventIconFont.glyph(for: eventID) {
                            richEventIcon(glyph, size: 15)
                        }

                        Text(text)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.primary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .info(let text):
                    Text(text)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.blue)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 2)
                case .table(let table):
                    richTable(table)
                case .image(let source):
                    CompetitionRichHTMLImage(source: source)
                case .separator:
                    Divider()
                        .padding(.vertical, 4)
                }
            }
        }
    }

    private func richList(items: [CompetitionRichHTMLListItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(item.marker)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: item.markerWidth, alignment: .trailing)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            if let eventID = item.eventID,
                               areEventIconsReady,
                               let glyph = CompetitionEventIconFont.glyph(for: eventID) {
                                richEventIcon(glyph, size: 15)
                            }

                            if !item.runs.isEmpty {
                                LinkedTextFlow(runs: item.runs)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        ForEach(Array(item.imageSources.enumerated()), id: \.offset) { _, source in
                            CompetitionRichHTMLImage(source: source)
                        }
                    }
                }
                .padding(.leading, CGFloat(item.depth) * 20)
            }
        }
        .padding(.vertical, 1)
    }

    private func richEventIcon(_ glyph: String, size: CGFloat) -> some View {
        Text(glyph)
            .font(.custom(CompetitionEventIconFont.fontName, size: size))
            .foregroundStyle(.primary)
            .frame(width: 20, alignment: .center)
            .offset(y: 1)
    }

    private func richTable(_ table: CompetitionRichHTMLTable) -> some View {
        let rows = tableRowLimit.map { Array(table.rows.prefix($0)) } ?? table.rows
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.system(size: 14, weight: rowIndex == 0 ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                    }
                }
                .background(rowIndex == 0 ? Color.secondary.opacity(0.08) : Color.clear)

                if rowIndex < rows.count - 1 {
                    Divider()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.7)
        }
    }
}

private struct CompetitionRichHTMLImage: View {
    let source: String

    var body: some View {
        Group {
            if let image = dataImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let url = resolvedURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        imagePlaceholder(systemImage: "photo.badge.exclamationmark")
                    case .empty:
                        imagePlaceholder(systemImage: "photo")
                    @unknown default:
                        imagePlaceholder(systemImage: "photo")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var dataImage: UIImage? {
        guard source.lowercased().hasPrefix("data:image"),
              let commaIndex = source.firstIndex(of: ",") else { return nil }
        let payload = String(source[source.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: payload) else { return nil }
        return UIImage(data: data)
    }

    private var resolvedURL: URL? {
        if source.hasPrefix("//") {
            return URL(string: "https:\(source)")
        }
        if source.hasPrefix("/") {
            return URL(string: "https://cubing.com\(source)")
        }
        return URL(string: source)
    }

    private func imagePlaceholder(systemImage: String) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.secondary.opacity(0.08))
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 120)
    }
}

private struct CompetitionRichHTMLElement {
    enum Kind {
        case heading(String, Int)
        case paragraph(String)
        case linkedText([CompetitionRichHTMLTextRun])
        case list([CompetitionRichHTMLListItem])
        case eventLine(eventID: String, text: String)
        case info(String)
        case table(CompetitionRichHTMLTable)
        case image(String)
        case separator
    }

    let kind: Kind

    static func parse(_ html: String) -> [CompetitionRichHTMLElement] {
        let cleanedHTML = normalizeCubingIconHTML(html)
            .replacingOccurrences(of: #"(?is)<script\b.*?</script>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style\b.*?</style>"#, with: "", options: .regularExpression)

        let pattern = #"(?is)<table\b[^>]*>(.*?)</table>|<div\b[^>]*class=['\"][^'\"]*text-info[^'\"]*['\"][^>]*>(.*?)</div>|<h([1-6])[^>]*>(.*?)</h\3>|<ol\b[^>]*>(.*?)</ol>|<ul\b[^>]*>(.*?)</ul>|<p\b[^>]*>(.*?)</p>|<li\b[^>]*>(.*?)</li>|<hr\b[^>]*>|<img\b[^>]*src=['\"]([^'\"]+)['\"][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return paragraphElements(from: cleanedHTML)
        }

        let nsHTML = cleanedHTML as NSString
        let matches = regex.matches(in: cleanedHTML, range: NSRange(location: 0, length: nsHTML.length))
        var elements: [CompetitionRichHTMLElement] = []
        var cursor = 0

        for match in matches {
            if match.range.location > cursor {
                let fragment = nsHTML.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                elements.append(contentsOf: paragraphElements(from: fragment))
            }

            if match.range(at: 1).location != NSNotFound {
                if let table = table(from: nsHTML.substring(with: match.range(at: 1))) {
                    elements.append(CompetitionRichHTMLElement(kind: .table(table)))
                }
            } else if match.range(at: 2).location != NSNotFound {
                let infoHTML = nsHTML.substring(with: match.range(at: 2))
                let plain = plainText(from: infoHTML)
                if !plain.isEmpty {
                    elements.append(CompetitionRichHTMLElement(kind: .info(plain)))
                }
            } else if match.range(at: 4).location != NSNotFound {
                let levelText = nsHTML.substring(with: match.range(at: 3))
                let level = Int(levelText) ?? 3
                let title = plainText(from: nsHTML.substring(with: match.range(at: 4)))
                if !title.isEmpty {
                    elements.append(CompetitionRichHTMLElement(kind: .heading(title, level)))
                }
            } else if match.range(at: 5).location != NSNotFound {
                if let list = listElement(from: nsHTML.substring(with: match.range(at: 5)), ordered: true, depth: 0) {
                    elements.append(list)
                }
            } else if match.range(at: 6).location != NSNotFound {
                if let list = listElement(from: nsHTML.substring(with: match.range(at: 6)), ordered: false, depth: 0) {
                    elements.append(list)
                }
            } else if match.range(at: 7).location != NSNotFound {
                elements.append(contentsOf: inlineElements(from: nsHTML.substring(with: match.range(at: 7))))
            } else if match.range(at: 8).location != NSNotFound {
                let itemHTML = "• " + nsHTML.substring(with: match.range(at: 8))
                elements.append(contentsOf: inlineElements(from: itemHTML))
            } else if match.range(at: 9).location != NSNotFound {
                let source = decodeHTMLText(nsHTML.substring(with: match.range(at: 9)))
                if !source.isEmpty {
                    elements.append(CompetitionRichHTMLElement(kind: .image(source)))
                }
            } else {
                elements.append(CompetitionRichHTMLElement(kind: .separator))
            }

            cursor = match.range.location + match.range.length
        }

        if cursor < nsHTML.length {
            let fragment = nsHTML.substring(with: NSRange(location: cursor, length: nsHTML.length - cursor))
            elements.append(contentsOf: paragraphElements(from: fragment))
        }

        return coalesced(elements)
    }

    private static func listElement(from html: String, ordered: Bool, depth: Int) -> CompetitionRichHTMLElement? {
        let items = listItems(from: html, ordered: ordered, depth: depth)

        guard !items.isEmpty else { return nil }
        return CompetitionRichHTMLElement(kind: .list(items))
    }

    private static func listItems(from html: String, ordered: Bool, depth: Int) -> [CompetitionRichHTMLListItem] {
        let trimmedHTML = html.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nestedList = leadingNestedList(in: trimmedHTML) {
            return listItems(
                from: nestedList.body,
                ordered: nestedList.ordered,
                depth: depth + 1
            )
        }

        let itemHTMLs = htmlCaptures(in: html, pattern: #"(?is)<li\b[^>]*>(.*?)</li>"#)
            .compactMap(\.first)
        if itemHTMLs.isEmpty {
            return nestedListItems(in: html, depth: depth + 1)
        }

        return itemHTMLs.enumerated().flatMap { index, itemHTML -> [CompetitionRichHTMLListItem] in
            var result: [CompetitionRichHTMLListItem] = []
            let contentHTML = removingNestedListContainers(from: itemHTML)
            let marker = ordered ? "\(index + 1)." : "•"

            if let item = listItem(from: contentHTML, marker: marker, depth: depth) {
                result.append(item)
            }

            result.append(contentsOf: nestedListItems(in: itemHTML, depth: depth + 1))
            return result
        }
    }

    private static func listItem(from html: String, marker: String, depth: Int) -> CompetitionRichHTMLListItem? {
        let runs = textRuns(from: html)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let imageSources = imageSources(from: html)
        guard !runs.isEmpty || !imageSources.isEmpty else { return nil }

        return CompetitionRichHTMLListItem(
            marker: marker,
            depth: depth,
            eventID: eventIconID(in: html),
            runs: runs,
            imageSources: imageSources
        )
    }

    private static func leadingNestedList(in html: String) -> (ordered: Bool, body: String)? {
        let lowercased = html.lowercased()
        guard lowercased.hasPrefix("<ul") || lowercased.hasPrefix("<ol"),
              let closeBracket = html.firstIndex(of: ">") else {
            return nil
        }

        let ordered = lowercased.hasPrefix("<ol")
        let body = String(html[html.index(after: closeBracket)...])
            .replacingOccurrences(of: #"(?is)</(?:ol|ul)>\s*$"#, with: "", options: .regularExpression)
        return (ordered, body)
    }

    private static func nestedListItems(in html: String, depth: Int) -> [CompetitionRichHTMLListItem] {
        let pattern = #"(?is)<(ol|ul)\b[^>]*>(.*?)</\1>"#
        let captures = htmlCaptures(in: html, pattern: pattern)
        return captures.flatMap { capture -> [CompetitionRichHTMLListItem] in
            guard capture.count >= 2 else { return [] }
            return listItems(
                from: capture[1],
                ordered: capture[0].lowercased() == "ol",
                depth: depth
            )
        }
    }

    private static func removingNestedListContainers(from html: String) -> String {
        html.replacingOccurrences(
            of: #"(?is)<(?:ol|ul)\b[^>]*>.*?</(?:ol|ul)>"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func inlineElements(from html: String) -> [CompetitionRichHTMLElement] {
        let pattern = #"(?is)<img\b[^>]*src=['\"]([^'\"]+)['\"][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return paragraphElements(from: html)
        }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        var elements: [CompetitionRichHTMLElement] = []
        var cursor = 0

        for match in matches {
            if match.range.location > cursor {
                let fragment = nsHTML.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                elements.append(contentsOf: paragraphElements(from: fragment))
            }
            let source = decodeHTMLText(nsHTML.substring(with: match.range(at: 1)))
            if !source.isEmpty {
                elements.append(CompetitionRichHTMLElement(kind: .image(source)))
            }
            cursor = match.range.location + match.range.length
        }

        if cursor < nsHTML.length {
            let fragment = nsHTML.substring(with: NSRange(location: cursor, length: nsHTML.length - cursor))
            elements.append(contentsOf: paragraphElements(from: fragment))
        }
        return elements
    }

    private static func paragraphElements(from html: String) -> [CompetitionRichHTMLElement] {
        normalizeCubingIconHTML(html)
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .components(separatedBy: .newlines)
            .compactMap { fragment -> CompetitionRichHTMLElement? in
                if let eventLine = eventLineElement(from: fragment) {
                    return eventLine
                }
                if let linkedText = linkedTextElement(from: fragment) {
                    return linkedText
                }
                let plain = plainText(from: fragment)
                guard !plain.isEmpty else { return nil }
                return CompetitionRichHTMLElement(kind: .paragraph(plain))
            }
    }

    private static func linkedTextElement(from html: String) -> CompetitionRichHTMLElement? {
        let runs = textRuns(from: html)
        guard runs.contains(where: { $0.url != nil || $0.isBold || $0.color != .primary }) else { return nil }
        let nonEmptyRuns = runs.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmptyRuns.isEmpty else { return nil }
        return CompetitionRichHTMLElement(kind: .linkedText(nonEmptyRuns))
    }

    private static func textRuns(from html: String) -> [CompetitionRichHTMLTextRun] {
        coalescedTextRuns(
            from: inlineTextRuns(
                from: normalizeCubingIconHTML(html),
                style: CompetitionRichHTMLInlineStyle()
            )
        )
    }

    private static func inlineTextRuns(
        from html: String,
        style: CompetitionRichHTMLInlineStyle
    ) -> [CompetitionRichHTMLTextRun] {
        let pattern = #"(?is)<(a|strong|b|span)\b([^>]*)>(.*?)</\1>|<br\s*/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return plainInlineRuns(from: html, style: style)
        }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        var runs: [CompetitionRichHTMLTextRun] = []
        var cursor = 0

        for match in matches {
            if match.range.location > cursor {
                let prefix = nsHTML.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                runs.append(contentsOf: plainInlineRuns(from: prefix, style: style))
            }

            if match.range(at: 1).location != NSNotFound {
                let tag = nsHTML.substring(with: match.range(at: 1)).lowercased()
                let attributes = nsHTML.substring(with: match.range(at: 2))
                let body = nsHTML.substring(with: match.range(at: 3))
                runs.append(contentsOf: inlineTextRuns(from: body, style: style.applying(tag: tag, attributes: attributes)))
            } else {
                runs.append(CompetitionRichHTMLTextRun(text: "\n", url: style.url, isBold: style.isBold, color: style.color))
            }

            cursor = match.range.location + match.range.length
        }

        if cursor < nsHTML.length {
            let suffix = nsHTML.substring(with: NSRange(location: cursor, length: nsHTML.length - cursor))
            runs.append(contentsOf: plainInlineRuns(from: suffix, style: style))
        }

        return runs
    }

    private static func plainInlineRuns(
        from html: String,
        style: CompetitionRichHTMLInlineStyle
    ) -> [CompetitionRichHTMLTextRun] {
        let text = plainText(from: html)
        guard !text.isEmpty else { return [] }
        return [
            CompetitionRichHTMLTextRun(
                text: text,
                url: style.url,
                isBold: style.isBold,
                color: style.color
            )
        ]
    }

    private static func coalescedTextRuns(from runs: [CompetitionRichHTMLTextRun]) -> [CompetitionRichHTMLTextRun] {
        var result: [CompetitionRichHTMLTextRun] = []
        for run in runs where !run.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let last = result.last,
               last.url == run.url,
               last.isBold == run.isBold,
               last.color == run.color {
                result[result.count - 1] = CompetitionRichHTMLTextRun(
                    text: last.text + run.text,
                    url: last.url,
                    isBold: last.isBold,
                    color: last.color
                )
            } else {
                result.append(run)
            }
        }
        return result
    }

    fileprivate static func resolvedURL(from href: String) -> URL? {
        if href.hasPrefix("mailto:") {
            return URL(string: href)
        }
        if href.hasPrefix("//") {
            return URL(string: "https:\(href)")
        }
        if href.hasPrefix("/") {
            return URL(string: "https://cubing.com\(href)")
        }
        return URL(string: href)
    }

    private static func imageSources(from html: String) -> [String] {
        htmlCaptures(in: html, pattern: #"(?is)<img\b[^>]*src=['\"]([^'\"]+)['\"][^>]*>"#)
            .compactMap(\.first)
            .map(decodeHTMLText)
            .filter { !$0.isEmpty }
    }

    private static func eventLineElement(from html: String) -> CompetitionRichHTMLElement? {
        guard let eventID = eventIconID(in: html) else { return nil }
        let text = plainText(
            from: html.replacingOccurrences(of: #"\[\[event-icon:[A-Za-z0-9_]+\]\]"#, with: "", options: .regularExpression)
        )
        guard !eventID.isEmpty, !text.isEmpty else { return nil }
        return CompetitionRichHTMLElement(kind: .eventLine(eventID: eventID, text: text))
    }

    private static func eventIconID(in html: String) -> String? {
        let pattern = #"\[\[event-icon:([A-Za-z0-9_]+)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsHTML = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: nsHTML.length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        return nsHTML.substring(with: match.range(at: 1)).lowercased()
    }

    private static func table(from html: String) -> CompetitionRichHTMLTable? {
        let rowCaptures = htmlCaptures(in: html, pattern: #"(?is)<tr\b[^>]*>(.*?)</tr>"#)
        let rows = rowCaptures.compactMap { rowCapture -> [String]? in
            guard let rowHTML = rowCapture.first else { return nil }
            let cellCaptures = htmlCaptures(in: rowHTML, pattern: #"(?is)<t[hd]\b[^>]*>(.*?)</t[hd]>"#)
            let cells = cellCaptures.compactMap { cellCapture -> String? in
                guard let cellHTML = cellCapture.first else { return nil }
                let plain = plainText(from: cellHTML.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression))
                guard !plain.isEmpty else { return nil }
                return plain
            }
            return cells.isEmpty ? nil : cells
        }
        guard !rows.isEmpty else { return nil }
        return CompetitionRichHTMLTable(rows: rows)
    }

    private static func htmlCaptures(in text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                let range = match.range(at: index)
                guard range.location != NSNotFound else { return nil }
                return nsText.substring(with: range)
            }
        }
    }

    private static func plainText(from html: String) -> String {
        decodeHTMLText(
            normalizeCubingIconHTML(html)
                .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
                .replacingOccurrences(of: #"\[\[event-icon:[A-Za-z0-9_]+\]\]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        )
        .replacingOccurrences(of: #"[ \t\r\f]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated fileprivate static func decodeHTMLText(_ text: String) -> String {
        var decoded = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&yen;", with: "¥")
            .replacingOccurrences(of: "&rmb;", with: "¥")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&hellip;", with: "…")

        decoded = decodeNumericHTMLEntities(in: decoded, pattern: #"&#(\d+);"#, radix: 10)
        decoded = decodeNumericHTMLEntities(in: decoded, pattern: #"&#x([0-9A-Fa-f]+);"#, radix: 16)
        return decoded
    }

    nonisolated private static func decodeNumericHTMLEntities(in text: String, pattern: String, radix: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).reversed()
        let result = NSMutableString(string: text)

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let fullRange = match.range(at: 0)
            let valueRange = match.range(at: 1)
            guard valueRange.location != NSNotFound else { continue }
            let valueText = nsText.substring(with: valueRange)
            guard let value = Int(valueText, radix: radix),
                  let scalar = UnicodeScalar(value) else { continue }
            result.replaceCharacters(in: fullRange, with: String(scalar))
        }

        return result as String
    }

    private static func normalizeCubingIconHTML(_ html: String) -> String {
        injectEventIconMarkers(in: html)
            .replacingOccurrences(of: #"(?is)<i\b[^>]*class=['\"][^'\"]*fa-rmb[^'\"]*['\"][^>]*>\s*</i>"#, with: "¥", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<i\b[^>]*class=['\"][^'\"]*(?:fa|event-icon)[^'\"]*['\"][^>]*>\s*</i>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "　", with: " ")
    }

    private static func injectEventIconMarkers(in html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)<i\b[^>]*class=['\"][^'\"]*event-icon-([A-Za-z0-9_]+)[^'\"]*['\"][^>]*>\s*</i>"#
        ) else {
            return html
        }

        let nsHTML = html as NSString
        let result = NSMutableString(string: html)
        for match in regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)).reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let eventID = nsHTML.substring(with: match.range(at: 1))
            result.replaceCharacters(in: match.range(at: 0), with: " [[event-icon:\(eventID)]] ")
        }
        return result as String
    }

    private static func coalesced(_ elements: [CompetitionRichHTMLElement]) -> [CompetitionRichHTMLElement] {
        var result: [CompetitionRichHTMLElement] = []
        var previousWasSeparator = false

        for element in elements {
            if case .separator = element.kind {
                guard !previousWasSeparator, !result.isEmpty else { continue }
                previousWasSeparator = true
            } else {
                previousWasSeparator = false
            }
            result.append(element)
        }

        if result.last.map({ if case .separator = $0.kind { return true }; return false }) == true {
            result.removeLast()
        }
        return result
    }
}

private struct CompetitionRichHTMLInlineStyle {
    var url: URL?
    var isBold = false
    var color: CompetitionRichHTMLTextColor = .primary

    func applying(tag: String, attributes: String) -> CompetitionRichHTMLInlineStyle {
        var copy = self
        switch tag {
        case "a":
            if let href = Self.attribute("href", in: attributes) {
                copy.url = CompetitionRichHTMLElement.resolvedURL(from: href)
            }
        case "strong", "b":
            copy.isBold = true
        case "span":
            if let color = Self.colorRole(from: attributes) {
                copy.color = color
            }
        default:
            break
        }
        return copy
    }

    private static func attribute(_ name: String, in attributes: String) -> String? {
        let patterns = [
            #"\#(name)\s*=\s*"([^"]*)""#,
            #"\#(name)\s*=\s*'([^']*)'"#
        ]
        let nsAttributes = attributes as NSString

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: attributes, range: NSRange(location: 0, length: nsAttributes.length)),
                  match.numberOfRanges > 1 else {
                continue
            }
            return CompetitionRichHTMLElement.decodeHTMLText(nsAttributes.substring(with: match.range(at: 1)))
        }

        return nil
    }

    private static func colorRole(from attributes: String) -> CompetitionRichHTMLTextColor? {
        let lowercased = attributes.lowercased()
        if lowercased.contains("text-danger")
            || lowercased.contains("color:#e53333")
            || lowercased.contains("color: #e53333")
            || lowercased.contains("color:red")
            || lowercased.contains("color: red") {
            return .danger
        }
        if lowercased.contains("text-info") || lowercased.contains("color:#31708f") {
            return .info
        }
        return nil
    }
}

private struct CompetitionRichHTMLTable {
    let rows: [[String]]
}

private struct CompetitionRichHTMLListItem: Hashable {
    let marker: String
    let depth: Int
    let eventID: String?
    let runs: [CompetitionRichHTMLTextRun]
    let imageSources: [String]

    var markerWidth: CGFloat {
        marker == "•" ? 16 : 24
    }
}

private enum CompetitionRichHTMLTextColor: Hashable {
    case primary
    case info
    case danger

    var swiftUIColor: Color {
        switch self {
        case .primary:
            return .primary
        case .info:
            return .blue
        case .danger:
            return Color(red: 229 / 255, green: 51 / 255, blue: 51 / 255)
        }
    }

    var uiColor: UIColor {
        switch self {
        case .primary:
            return .label
        case .info:
            return .systemBlue
        case .danger:
            return UIColor(red: 229 / 255, green: 51 / 255, blue: 51 / 255, alpha: 1)
        }
    }
}

private struct CompetitionRichHTMLTextRun: Hashable {
    let text: String
    let url: URL?
    let isBold: Bool
    let color: CompetitionRichHTMLTextColor

    init(
        text: String,
        url: URL?,
        isBold: Bool = false,
        color: CompetitionRichHTMLTextColor = .primary
    ) {
        self.text = text
        self.url = url
        self.isBold = isBold
        self.color = color
    }
}

private struct LinkedTextFlow: View {
    let runs: [CompetitionRichHTMLTextRun]

    var body: some View {
        Text(attributedString)
            .foregroundStyle(.primary)
            .tint(.blue)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedString: AttributedString {
        var result = AttributedString()
        var plainText = ""
        for run in runs {
            let text = resolvedText(for: run, after: plainText)
            guard !text.isEmpty else { continue }

            var part = AttributedString(text)
            part.font = Font.system(size: 15, weight: run.isBold ? .semibold : .regular)
            part.foregroundColor = run.url == nil ? run.color.swiftUIColor : .blue
            if let url = run.url {
                part.link = url
            }

            result.append(part)
            plainText += text
        }
        return result
    }

    private func resolvedText(for run: CompetitionRichHTMLTextRun, after currentText: String) -> String {
        if !currentText.isEmpty, shouldInsertSpace(before: run.text, after: currentText) {
            return " " + run.text
        }
        return run.text
    }

    private func shouldInsertSpace(before nextText: String, after currentText: String) -> Bool {
        guard !nextText.isEmpty else { return false }
        let previous = String(currentText.suffix(1))
        guard !previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if nextText.hasPrefix(" ") { return false }

        let noSpacePrefixes = [".", ",", ";", ":", "!", "?", ")", "]", "}", "。", "，", "；", "：", "！", "？", "、"]
        if noSpacePrefixes.contains(where: { nextText.hasPrefix($0) }) {
            return false
        }

        let noSpaceAfter = ["(", "[", "{"]
        if noSpaceAfter.contains(previous) {
            return false
        }

        return true
    }
}

private struct FlexibleTagFlow: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chunkedItems, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        Text(item)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.secondary.opacity(0.08), in: Capsule())
                    }
                }
            }
        }
    }

    private var chunkedItems: [[String]] {
        stride(from: 0, to: items.count, by: 3).map { start in
            Array(items[start ..< min(start + 3, items.count)])
        }
    }
}

private enum CompetitionEventIconFont {
    static let fontName = "event-icon"

    private static let glyphs: [String: String] = [
        "333": "\u{e900}",
        "222": "\u{e901}",
        "444": "\u{e902}",
        "555": "\u{e903}",
        "666": "\u{e904}",
        "777": "\u{e905}",
        "333bf": "\u{e906}",
        "333bfcheck": "\u{e906}",
        "333fm": "\u{e907}",
        "333oh": "\u{e908}",
        "333ft": "\u{e909}",
        "minx": "\u{e90a}",
        "pyram": "\u{e90b}",
        "clock": "\u{e90c}",
        "skewb": "\u{e90d}",
        "sq1": "\u{e90e}",
        "444bf": "\u{e90f}",
        "444bfcheck": "\u{e90f}",
        "555bf": "\u{e910}",
        "555bfcheck": "\u{e910}",
        "333mbf": "\u{e911}",
        "333mbo": "\u{e911}",
        "submission": "\u{e911}",
        "magic": "\u{e912}",
        "mmagic": "\u{e913}",
        "stack": "\u{e914}",
        "registration": "\u{e915}",
        "intro": "\u{e916}",
        "break": "\u{e917}",
        "lunch": "\u{e918}",
        "ceremony": "\u{e919}",
        "lucky": "\u{e91a}",
        "funny": "\u{e91b}",
        "333relay": "\u{e91c}",
        "redi": "\u{e91d}",
        "kilominx": "\u{e91e}",
        "mirror": "\u{e91f}",
        "ivy": "\u{e920}",
        "custom": "\u{f00c}"
    ]

    static var isAvailable: Bool {
        UIFont(name: fontName, size: 12) != nil
    }

    static func glyph(for eventID: String) -> String? {
        glyphs[eventID.lowercased()]
    }

    @discardableResult
    static func ensureRegistered() -> Bool {
        if isAvailable { return true }
        guard let fontURL = bundleFontURL() else { return false }

        var error: Unmanaged<CFError>?
        let didRegister = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)
        if didRegister { return true }

        if let error {
            let nsError = error.takeRetainedValue() as Error as NSError
            if nsError.domain == kCTFontManagerErrorDomain as String,
               nsError.code == CTFontManagerError.alreadyRegistered.rawValue {
                return true
            }
        }

        return isAvailable
    }

    private static func bundleFontURL() -> URL? {
        if let url = Bundle.main.url(forResource: "event-icon", withExtension: "ttf") {
            return url
        }
        if let url = Bundle.main.url(forResource: "event-icon", withExtension: "ttf", subdirectory: "CompetitionIcons") {
            return url
        }
        if let url = Bundle.main.url(forResource: "event-icon", withExtension: "ttf", subdirectory: "Resources/CompetitionIcons") {
            return url
        }
        guard let resourceURL = Bundle.main.resourceURL,
              let enumerator = FileManager.default.enumerator(
                at: resourceURL,
                includingPropertiesForKeys: nil
              ) else {
            return nil
        }

        for case let url as URL in enumerator where url.lastPathComponent == "event-icon.ttf" {
            return url
        }
        return nil
    }
}

#endif

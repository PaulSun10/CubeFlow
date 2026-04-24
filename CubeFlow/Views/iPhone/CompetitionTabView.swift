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
                if !publishedVisibleCompetitions.isEmpty {
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
        let ongoingCount = publishedVisibleCompetitions.filter { competitionAvailabilityStatus(for: $0) == .ongoing }.count
        let upcomingCount = publishedVisibleCompetitions.filter { competitionAvailabilityStatus(for: $0) == .upcoming }.count
        let registrationOpenCount = publishedVisibleCompetitions.filter { competitionAvailabilityStatus(for: $0) == .registrationOpen }.count

        let parts = [
            "\(ongoingCount) \(localizedCompetitionStringInView(key: "competitions.status.ongoing", languageCode: appLanguage))",
            "\(upcomingCount) \(localizedCompetitionStringInView(key: "competitions.status.upcoming", languageCode: appLanguage))",
            "\(registrationOpenCount) \(localizedCompetitionStringInView(key: "competitions.status.registration_open", languageCode: appLanguage))"
        ]

        return parts.joined(separator: " · ")
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
        let preloadLimit = Self.initialTopCuberPreloadCount + Self.nextTopCuberPrefetchCount
        let preloadedCompetitionIDs = publishedVisibleCompetitions
            .prefix(preloadLimit)
            .map(\.id)
            .joined(separator: ",")

        return [
            showsTopCubers ? "on" : "off",
            appLanguage,
            preloadedCompetitionIDs
        ].joined(separator: "|")
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

    private var competitionBottomSearchBar: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        return Button {
            isShowingSearch = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                Text(localizedCompetitionStringInView(key: "competitions.search_placeholder", languageCode: appLanguage))
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
        .compatibleGlass(in: shape)
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
                        Text(flagEmoji(for: competition.countryISO2))
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
                            Text(flagEmoji(for: competition.countryISO2))
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

    @MainActor
    private func loadCompetitions() async {
        let query = competitionQuery
        let expectedSignature = filterSignature
        errorMessage = nil
        let cachedSnapshot = await CompetitionService.cachedCompetitions(for: query)
        let localizedCachedCompetitions = await CompetitionService.localizeCompetitionNamesIfNeeded(
            cachedSnapshot?.competitions ?? [],
            languageCode: appLanguage
        )
        let visibleCachedCompetitions = CompetitionService.filterCompetitions(
            localizedCachedCompetitions,
            for: query
        )

        competitions = visibleCachedCompetitions
        syncVisibleCompetitionsSnapshot(query: query)
        publishVisibleCompetitionsSnapshot()
        nextPage = nil
        isLoading = publishedVisibleCompetitions.isEmpty
        isLoadingMore = !publishedVisibleCompetitions.isEmpty

        if publishedVisibleCompetitions.isEmpty {
            do {
                try await loadMoreCompetitions(minimumVisibleCount: 10, replaceExisting: true)
                isLoading = false

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
                errorMessage = error.localizedDescription
                isLoading = false
                isLoadingMore = false
                return
            }
        }

        do {
            try await refreshCompetitionsFromNetwork(
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
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
        isLoadingMore = false
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
                let localizedCompetitions = await CompetitionService.localizeCompetitionNamesIfNeeded(
                    result.competitions,
                    languageCode: appLanguage
                )

                aggregated.append(contentsOf: localizedCompetitions)
                visibleCompetitions = normalizedVisibleCompetitions(aggregated, query: query)
                pageToFetch = result.nextPage
                totalCount = result.totalCount ?? totalCount

                if hadVisibleCompetitions || !visibleCompetitions.isEmpty || result.nextPage == nil {
                    break
                }
            }

            guard expectedSignature == filterSignature else { return }

            if !visibleCompetitions.isEmpty || publishedVisibleCompetitions.isEmpty {
                competitions = aggregated
                visibleCompetitionsSnapshot = visibleCompetitions
                publishVisibleCompetitionsSnapshot()
            }
            nextPage = pageToFetch
            isLoading = false
            isLoadingMore = false

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
                errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadMoreCompetitions(minimumVisibleCount: Int, replaceExisting: Bool) async throws {
        var aggregated: [CompetitionSummary] = replaceExisting ? [] : competitions
        var pageToFetch = replaceExisting ? 1 : nextPage
        let query = competitionQuery

        var newlyLoadedVisibleItems: [CompetitionSummary] = []

        while let page = pageToFetch {
            let result = try await CompetitionService.fetchCompetitionsPage(query: query, page: page)
            let localizedCompetitions = await CompetitionService.localizeCompetitionNamesIfNeeded(
                result.competitions,
                languageCode: appLanguage
            )
            newlyLoadedVisibleItems.append(contentsOf: localizedCompetitions)
            aggregated.append(contentsOf: localizedCompetitions)
            pageToFetch = result.nextPage

            if newlyLoadedVisibleItems.count >= minimumVisibleCount || result.nextPage == nil {
                break
            }
        }

        competitions = aggregated
        visibleCompetitionsSnapshot = normalizedVisibleCompetitions(aggregated, query: query)
        publishVisibleCompetitionsSnapshot()
        nextPage = pageToFetch
    }

    @MainActor
    private func prefetchRemainingCompetitions(for query: CompetitionQuery, expectedSignature: String) async {
        guard expectedSignature == filterSignature else { return }
        guard !isLoadingMore else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        while let page = nextPage {
            guard expectedSignature == filterSignature else { return }

            do {
                let result = try await CompetitionService.fetchCompetitionsPage(query: competitionQuery, page: page)
                let localizedCompetitions = await CompetitionService.localizeCompetitionNamesIfNeeded(
                    result.competitions,
                    languageCode: appLanguage
                )
                competitions.append(contentsOf: localizedCompetitions)
                syncVisibleCompetitionsSnapshot(query: query)
                nextPage = result.nextPage

                if result.nextPage == nil {
                    publishVisibleCompetitionsSnapshot()
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
                    errorMessage = error.localizedDescription
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
    private func refreshCompetitionsFromNetwork(
        for query: CompetitionQuery,
        expectedSignature: String,
        cachedCompetitions: [CompetitionSummary]
    ) async throws {
        var freshCompetitions: [CompetitionSummary] = []
        var page = 1

        while true {
            guard expectedSignature == filterSignature else { return }

            let result = try await CompetitionService.fetchCompetitionsPage(query: query, page: page)
            let localizedCompetitions = await CompetitionService.localizeCompetitionNamesIfNeeded(
                result.competitions,
                languageCode: appLanguage
            )
            freshCompetitions.append(contentsOf: localizedCompetitions)
            competitions = mergedCompetitions(cached: cachedCompetitions, fresh: freshCompetitions)
            syncVisibleCompetitionsSnapshot(query: query)

            guard let nextPage = result.nextPage else {
                competitions = freshCompetitions
                syncVisibleCompetitionsSnapshot(query: query)
                publishVisibleCompetitionsSnapshot()
                await CompetitionService.cacheCompetitions(
                    freshCompetitions,
                    totalCount: result.totalCount ?? freshCompetitions.count,
                    for: query
                )
                return
            }

            page = nextPage
            if freshCompetitions.count >= 25 {
                isLoading = false
                isLoadingMore = true
            }
        }
    }

    private func mergedCompetitions(
        cached: [CompetitionSummary],
        fresh: [CompetitionSummary]
    ) -> [CompetitionSummary] {
        let freshIDs = Set(fresh.map(\.id))
        let staleCache = cached.filter { !freshIDs.contains($0.id) }
        return fresh + staleCache
    }

    private func normalizedVisibleCompetitions(
        _ competitions: [CompetitionSummary],
        query: CompetitionQuery
    ) -> [CompetitionSummary] {
        let sortedCompetitions = CompetitionService.filterCompetitions(competitions, for: query)
        return filterCompetitionsForVisibleStatus(sortedCompetitions, query: query)
    }

    private func syncVisibleCompetitionsSnapshot(query: CompetitionQuery) {
        visibleCompetitionsSnapshot = normalizedVisibleCompetitions(competitions, query: query)
    }

    private func publishVisibleCompetitionsSnapshot() {
        publishedVisibleCompetitions = visibleCompetitionsSnapshot
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

        let preloadTargets = publishedVisibleCompetitions
            .prefix(Self.initialTopCuberPreloadCount)
            .filter { competition in !topCuberRefreshingIDs.contains(competition.id) }

        let prefetchTargets = publishedVisibleCompetitions
            .dropFirst(Self.initialTopCuberPreloadCount)
            .prefix(Self.nextTopCuberPrefetchCount)
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

private enum CompetitionDetailTab: String, CaseIterable, Identifiable {
    case info
    case register
    case competitors
    case schedule
    case live

    var id: String { rawValue }

    func localizedTitle(languageCode: String) -> String {
        switch self {
        case .info:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.info", languageCode: languageCode)
        case .register:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.register", languageCode: languageCode)
        case .competitors:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.competitors", languageCode: languageCode)
        case .schedule:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.schedule", languageCode: languageCode)
        case .live:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.live", languageCode: languageCode)
        }
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

private struct CompetitionDetailView: View {
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
    @State private var isRefreshingDetail = false
    @State private var psychPreviewCache: [String: [CompetitionCompetitorPsychPreview]] = [:]
    @State private var isLoadingWCALive = false
    @State private var wcaLiveContentOverride: CompetitionWCALiveContent?
    @State private var selectedWCALiveRoundID = ""

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

    private var liveURL: URL? {
        if isMainlandChinaCompetition,
           let website = competition.website,
           let liveURL = URL(string: website.replacingOccurrences(of: "/competition/", with: "/live/")) {
            return liveURL
        }

        if let liveURLOverride = detailContent.liveURLOverride {
            return liveURLOverride
        }

        return URL(string: "https://live.worldcubeassociation.org/link/competitions/\(competition.id)")
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
            return true
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
        CompetitionDetailTab.allCases
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
        let query = competitorSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return detailContent.competitorPreviews.filter { competitor in
            let matchesQuery = query.isEmpty
                || competitor.name.localizedCaseInsensitiveContains(query)
                || (competitor.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
            let matchesEvent = selectedCompetitorEventID.isEmpty
                || competitor.registeredEventIDs.contains(selectedCompetitorEventID)
            return matchesQuery && matchesEvent
        }
    }

    private var competitorMatrixEventIDs: [String] {
        CompetitionEventFilter.selectableCases
            .map(\.wcaEventID)
            .filter { competition.eventIDs.contains($0) }
    }

    private var showsCompetitorNumbers: Bool {
        detailContent.competitorPreviews.contains { $0.number != nil }
    }

    private var showsCompetitorGender: Bool {
        detailContent.competitorPreviews.contains { $0.gender != nil }
    }

    private var currentPsychCacheKey: String {
        selectedCompetitorEventID.isEmpty ? "__all__" : selectedCompetitorEventID
    }

    private var isPsychModeAvailable: Bool {
        !selectedCompetitorEventID.isEmpty
    }

    private var filteredPsychCompetitors: [CompetitionCompetitorPsychPreview] {
        let query = competitorSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let previews = psychPreviewCache[currentPsychCacheKey] ?? []
        guard !query.isEmpty else { return previews }
        return previews.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var showsPsychOverallRank: Bool {
        selectedCompetitorEventID.isEmpty
    }

    private var psychOverallRankByCompetitorID: [String: Int] {
        guard showsPsychOverallRank else { return [:] }

        let scored = filteredPsychCompetitors.map { competitor in
            (
                competitor,
                competitor.items
                    .filter { psychMatrixEventIDs.contains($0.eventID) }
                    .map(\.rank)
                    .reduce(0, +)
            )
        }
        .filter { !$0.0.items.isEmpty && $0.1 > 0 }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
        }

        return Dictionary(uniqueKeysWithValues: scored.enumerated().map { index, element in
            (element.0.id, index + 1)
        })
    }

    private var displayedPsychCompetitors: [CompetitionCompetitorPsychPreview] {
        guard showsPsychOverallRank else { return filteredPsychCompetitors }
        return filteredPsychCompetitors.sorted { lhs, rhs in
            let lhsRank = psychOverallRankByCompetitorID[lhs.id] ?? .max
            let rhsRank = psychOverallRankByCompetitorID[rhs.id] ?? .max
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var psychMatrixEventIDs: [String] {
        if !selectedCompetitorEventID.isEmpty {
            return competitorMatrixEventIDs.filter { $0 == selectedCompetitorEventID }
        }
        return competitorMatrixEventIDs
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                tabStrip

                tabContent
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(competition.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(competition.id)|\(appLanguage)") {
            areCompetitionEventIconsReady = CompetitionEventIconFont.ensureRegistered()
            await loadDetailContent()
        }
        .task(id: "\(competition.id)|\(appLanguage)|\(selectedTab.rawValue)|\(selectedCompetitorsMode.rawValue)|\(selectedCompetitorEventID)") {
            await loadPsychPreviewsIfNeeded()
        }
        .task(id: "\(competition.id)|\(appLanguage)|\(selectedTab.rawValue)") {
            await loadWCALiveContentIfNeeded()
        }
        .toolbar {
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
            Text(competition.name)
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
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(visibleTabs) { tab in
                        Button {
                            withAnimation(.snappy(duration: 0.22)) {
                                selectedTab = tab
                            }
                        } label: {
                            Text(tab.localizedTitle(languageCode: appLanguage))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(selectedTab == tab ? Color.primary.opacity(0.08) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minWidth: geometry.size.width - 32, alignment: .center)
                .padding(.horizontal, 16)
            }
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .info:
            detailSectionStack {
                if isLoadingDetail && detailContent == .empty {
                    detailLoadingCard
                }

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

                if !detailContent.noteBlocks.isEmpty {
                    detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.section.notes", languageCode: appLanguage)) {
                        detailTextBlocks(detailContent.noteBlocks)
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

                if !detailContent.registerBlocks.isEmpty {
                    detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.section.notes", languageCode: appLanguage)) {
                        detailTextBlocks(detailContent.registerBlocks)
                    }
                }

                if !eventTitles.isEmpty {
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
                            ForEach(detailContent.scheduleDays) { day in
                                detailScheduleDayCard(day)
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

                            if !isMainlandChinaCompetition, isLoadingWCALive {
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

    private func detailTextBlocks(_ blocks: [CompetitionDetailTextBlock]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                VStack(alignment: .leading, spacing: 6) {
                    if let title = block.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                    Text(block.body)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func detailScheduleDayCard(_ day: CompetitionScheduleDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(day.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)

            ForEach(day.entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.timeText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(entry.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let detailText = entry.detailText, !detailText.isEmpty {
                        Text(detailText)
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
        let fetched = await CompetitionService.fetchCompetitionDetail(for: competition, languageCode: appLanguage)
        detailContent = fetched
        isLoadingDetail = false
    }

    private func refreshDetailContent() async {
        guard !isRefreshingDetail else { return }
        isRefreshingDetail = true
        defer { isRefreshingDetail = false }

        let fetched = await CompetitionService.fetchCompetitionDetail(for: competition, languageCode: appLanguage)
        detailContent = fetched
        psychPreviewCache = [:]
        wcaLiveContentOverride = nil

        if selectedTab == .competitors,
           selectedCompetitorsMode == .psych,
           isPsychModeAvailable {
            await loadPsychPreviewsIfNeeded()
        }
    }

    private func loadWCALiveContentIfNeeded() async {
        guard selectedTab == .live, !isMainlandChinaCompetition else { return }
        guard shouldRefreshWCALiveContent else { return }
        guard !isLoadingWCALive else { return }

        isLoadingWCALive = true
        let fetched = await CompetitionService.fetchCompetitionWCALiveContent(
            for: competition,
            languageCode: appLanguage
        )
        wcaLiveContentOverride = fetched
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
        isLoadingPsych = false
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
    static let fontName = "cubing-icons"

    private static let glyphs: [String: String] = [
        "222": "\u{f10a}",
        "333": "\u{f106}",
        "444": "\u{f101}",
        "555": "\u{f10c}",
        "666": "\u{f113}",
        "777": "\u{f111}",
        "333oh": "\u{f115}",
        "clock": "\u{f108}",
        "minx": "\u{f103}",
        "pyram": "\u{f112}",
        "skewb": "\u{f105}",
        "sq1": "\u{f102}",
        "333bf": "\u{f107}",
        "444bf": "\u{f104}",
        "555bf": "\u{f114}",
        "333fm": "\u{f10d}",
        "333mbf": "\u{f10e}"
    ]

    static var isAvailable: Bool {
        UIFont(name: fontName, size: 12) != nil
    }

    static func glyph(for eventID: String) -> String? {
        glyphs[eventID]
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
        if let url = Bundle.main.url(forResource: "cubing-icons", withExtension: "woff2") {
            return url
        }
        if let url = Bundle.main.url(forResource: "cubing-icons", withExtension: "woff2", subdirectory: "CompetitionIcons") {
            return url
        }
        if let url = Bundle.main.url(forResource: "cubing-icons", withExtension: "woff2", subdirectory: "Resources/CompetitionIcons") {
            return url
        }
        guard let resourceURL = Bundle.main.resourceURL,
              let enumerator = FileManager.default.enumerator(
                at: resourceURL,
                includingPropertiesForKeys: nil
              ) else {
            return nil
        }

        for case let url as URL in enumerator where url.lastPathComponent == "cubing-icons.woff2" {
            return url
        }
        return nil
    }
}

@available(iOS 17.0, *)
private struct CompetitionMapView: View {
    let query: CompetitionQuery
    let appLanguage: String

    @AppStorage("competition_map_mode") private var storedMapModeRawValue: String = CompetitionMapMode.satellite.rawValue
    @AppStorage("competition_map_look") private var storedMapLookRawValue: String = CompetitionMapLook.globe.rawValue
    @State private var competitions: [CompetitionSummary] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var selectedCompetitionID: String?
    @State private var selectedClusterCompetitions: [CompetitionSummary] = []
    @State private var selectedMapItemID: String?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var currentMapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694),
        span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
    )
    @State private var hasPositionedCamera = false
    @State private var isFollowingUserLocation = false
    @State private var shouldRefocusToUserLocation = false
    @StateObject private var locationManager = CompetitionLocationManager()
    @State private var weatherSnapshot: CompetitionWeatherSnapshot?
    @State private var isLoadingWeather = false
    @State private var lastWeatherLocation: CLLocation?
    @State private var currentCityName: String?
    @State private var isResolvingCity = false
    @State private var lastResolvedCityLocation: CLLocation?
    @State private var selectedCardHeight: CGFloat = 0
    @State private var showsRefreshProgress = false
    @State private var expectedCompetitionCount: Int?
    @State private var selectedCompetitionForDetail: CompetitionSummary?

    private var mappableCompetitions: [CompetitionSummary] {
        competitions.filter { $0.latitude != nil && $0.longitude != nil }
    }

    private var selectedCompetition: CompetitionSummary? {
        competitions.first { $0.id == selectedCompetitionID }
    }

    private var mapModeSelection: CompetitionMapMode {
        get { CompetitionMapMode(rawValue: storedMapModeRawValue) ?? .satellite }
        nonmutating set { storedMapModeRawValue = newValue.rawValue }
    }

    private var mapLookSelection: CompetitionMapLook {
        get { CompetitionMapLook(rawValue: storedMapLookRawValue) ?? .globe }
        nonmutating set { storedMapLookRawValue = newValue.rawValue }
    }

    private var mapDisplayItems: [CompetitionMapDisplayItem] {
        clusteredMapDisplayItems(from: mappableCompetitions, in: currentMapRegion)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition, selection: $selectedMapItemID) {
                UserAnnotation()

                ForEach(mapDisplayItems) { item in
                    Annotation(
                        item.title,
                        coordinate: item.coordinate,
                        anchor: .bottom
                    ) {
                        mapAnnotationView(for: item)
                    }
                    .tag(item.id)
                }
            }
            .mapStyle(mapModeSelection.mapStyle(look: mapLookSelection))
            .ignoresSafeArea(edges: .bottom)
            .onMapCameraChange(frequency: .onEnd) { context in
                currentMapRegion = context.region
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    withAnimation(.snappy(duration: 0.28)) {
                        selectedCompetitionID = nil
                        selectedClusterCompetitions = []
                        selectedMapItemID = nil
                    }
                }
            )
            .overlay(alignment: .center) {
                if let errorMessage, competitions.isEmpty {
                    mapErrorOverlay(message: errorMessage)
                } else if mappableCompetitions.isEmpty, !isLoading {
                    mapEmptyOverlay
                }
            }
            .overlay(alignment: .bottom) {
                mapBottomOverlay
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                    .animation(.snappy(duration: 0.28), value: selectedCompetition != nil)
                    .animation(.snappy(duration: 0.28), value: selectedCardHeight)
            }
        }
        .navigationTitle(Text(localizedCompetitionStringInView(key: "competitions.map_title", languageCode: appLanguage)))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedCompetitionForDetail) { competition in
            CompetitionDetailView(
                competition: competition,
                appLanguage: appLanguage
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                mapRefreshToolbarControl
            }
        }
        .task {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }
            await requestLocationIfAuthorized()
            await loadMapCompetitions()
            if let currentLocation = locationManager.currentLocation {
                async let weatherLoad: Void = loadWeatherIfNeeded(for: currentLocation)
                async let cityLoad: Void = loadCityIfNeeded(for: currentLocation)
                _ = await (weatherLoad, cityLoad)
            }
        }
        .onChange(of: locationManager.authorizationStatus) { newValue in
            if newValue == .authorizedAlways || newValue == .authorizedWhenInUse {
                locationManager.requestCurrentLocation()
                if isFollowingUserLocation {
                    focusOnUserLocation()
                }
            }
        }
        .onChange(of: locationManager.currentLocation) { newLocation in
            guard let newLocation else { return }
            if shouldRefocusToUserLocation {
                focusOnUserLocation(using: newLocation)
                shouldRefocusToUserLocation = false
            }
            Task {
                async let weatherLoad: Void = loadWeatherIfNeeded(for: newLocation)
                async let cityLoad: Void = loadCityIfNeeded(for: newLocation)
                _ = await (weatherLoad, cityLoad)
            }
        }
        .onChange(of: cameraPosition.positionedByUser) { positionedByUser in
            if positionedByUser {
                isFollowingUserLocation = false
                shouldRefocusToUserLocation = false
            }
        }
        .onChange(of: selectedMapItemID) { newValue in
            guard let newValue,
                  let item = mapDisplayItems.first(where: { $0.id == newValue }) else {
                return
            }

            switch item.kind {
            case .competition(let competitionID):
                selectedClusterCompetitions = []
                selectedCompetitionID = competitionID
            case .cluster(let competitions):
                selectedCompetitionID = nil
                if shouldShowClusterCards(for: competitions) {
                    selectedClusterCompetitions = competitions
                } else {
                    selectedClusterCompetitions = []
                    zoomToCluster(competitions)
                }
                Task { @MainActor in
                    selectedMapItemID = nil
                }
            }
        }
        .onPreferenceChange(CompetitionMapCardHeightPreferenceKey.self) { height in
            selectedCardHeight = height
        }
    }

    private var bottomControlsSpacing: CGFloat {
        selectedCompetition == nil && selectedClusterCompetitions.isEmpty ? 0 : 12
    }

    @ViewBuilder
    private func mapAnnotationView(for item: CompetitionMapDisplayItem) -> some View {
        switch item.kind {
        case .competition(let competitionID):
            Image(systemName: "mappin")
                .font(.system(size: selectedCompetitionID == competitionID ? 26 : 22, weight: .semibold))
                .foregroundStyle(selectedCompetitionID == competitionID ? .red : .blue)
                .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
                .contentShape(Rectangle())
        case .cluster:
            Image(systemName: "mappin")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.blue)
                .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
            .contentShape(Rectangle())
        }
    }

    private func clusteredMapDisplayItems(
        from competitions: [CompetitionSummary],
        in region: MKCoordinateRegion
    ) -> [CompetitionMapDisplayItem] {
        let latitudeThreshold = max(region.span.latitudeDelta * 0.04, 0.0012)
        let longitudeThreshold = max(region.span.longitudeDelta * 0.04, 0.0012)
        var remaining = competitions
        var items: [CompetitionMapDisplayItem] = []

        while let seed = remaining.first {
            remaining.removeFirst()

            let nearby = remaining.filter { candidate in
                guard let seedLatitude = seed.latitude,
                      let seedLongitude = seed.longitude,
                      let candidateLatitude = candidate.latitude,
                      let candidateLongitude = candidate.longitude else {
                    return false
                }

                return abs(seedLatitude - candidateLatitude) <= latitudeThreshold
                    && abs(seedLongitude - candidateLongitude) <= longitudeThreshold
            }

            let nearbyIDs = Set(nearby.map(\.id))
            remaining.removeAll { nearbyIDs.contains($0.id) }

            let group = [seed] + nearby

            if group.count == 1,
               let competition = group.first,
               let latitude = competition.latitude,
               let longitude = competition.longitude {
                items.append(
                    CompetitionMapDisplayItem(
                        id: competition.id,
                        title: competition.name,
                        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                        kind: .competition(competition.id)
                    )
                )
            } else {
                let averagedLatitude = group.compactMap(\.latitude).reduce(0, +) / Double(group.count)
                let averagedLongitude = group.compactMap(\.longitude).reduce(0, +) / Double(group.count)
                let combinedTitle = group.map(\.name).joined(separator: " & ")
                items.append(
                    CompetitionMapDisplayItem(
                        id: "cluster:" + group.map(\.id).sorted().joined(separator: ","),
                        title: combinedTitle,
                        coordinate: CLLocationCoordinate2D(latitude: averagedLatitude, longitude: averagedLongitude),
                        kind: .cluster(group)
                    )
                )
            }
        }

        return items
    }

    private func zoomToCluster(_ competitions: [CompetitionSummary]) {
        let coordinates = competitions.compactMap { competition -> CLLocationCoordinate2D? in
            guard let latitude = competition.latitude,
                  let longitude = competition.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        guard !coordinates.isEmpty else { return }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max() else {
            return
        }

        let rawLatitudeDelta = maxLatitude - minLatitude
        let rawLongitudeDelta = maxLongitude - minLongitude

        let paddedLatitudeDelta = max(rawLatitudeDelta * 1.7, 0.0045)
        let paddedLongitudeDelta = max(rawLongitudeDelta * 1.7, 0.0045)

        let center = CLLocationCoordinate2D(
            latitude: ((minLatitude + maxLatitude) / 2) - (paddedLatitudeDelta * 0.10),
            longitude: (minLongitude + maxLongitude) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: paddedLatitudeDelta,
            longitudeDelta: paddedLongitudeDelta
        )

        withAnimation(.snappy(duration: 0.3)) {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    private var mapBottomOverlay: some View {
        VStack(spacing: bottomControlsSpacing) {
            HStack(alignment: .bottom) {
                mapBottomLeadingControls
                Spacer(minLength: 16)
                mapControls
            }

            if !selectedClusterCompetitions.isEmpty {
                VStack(spacing: 10) {
                    ForEach(selectedClusterCompetitions, id: \.id) { competition in
                        mapCompetitionCard(competition)
                    }
                }
                .measureHeight { height in
                    selectedCardHeight = height
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let selectedCompetition {
                mapCompetitionCard(selectedCompetition)
                    .measureHeight { height in
                        selectedCardHeight = height
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func shouldShowClusterCards(for competitions: [CompetitionSummary]) -> Bool {
        guard competitions.count > 1 else { return false }
        let normalizedAddresses = Set(
            competitions.map { competition in
                competition.venueLine.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
        return normalizedAddresses.count == 1 && !(normalizedAddresses.first?.isEmpty ?? true)
    }

    private var mapBottomLeadingControls: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await refreshWeather()
                }
            } label: {
                Group {
                    if isLoadingWeather {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.9)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: weatherSnapshot?.symbolName ?? "cloud.sun.fill")
                                .font(.system(size: 16, weight: .semibold))
                            if let weatherSnapshot {
                                Text(weatherSnapshot.temperatureText)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                    }
                }
                .frame(minWidth: 40, minHeight: 40)
                .padding(.horizontal, weatherSnapshot == nil ? 0 : 12)
            }
            .buttonStyle(.plain)
            .modifier(MapAccessoryGlassModifier(shape: weatherSnapshot == nil ? .circle : .capsule))

            if let currentCityName {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(currentCityName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .modifier(MapAccessoryGlassModifier(shape: .capsule))
            }

            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                Text(mapInfoDateText)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .modifier(MapAccessoryGlassModifier(shape: .capsule))
        }
    }

    private var mapRefreshControl: some View {
        Button {
            withAnimation(.snappy(duration: 0.24)) {
                showsRefreshProgress = true
            }
            Task {
                await loadMapCompetitions()
                try? await Task.sleep(for: .seconds(1.2))
                await MainActor.run {
                    withAnimation(.snappy(duration: 0.24)) {
                        showsRefreshProgress = false
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Group {
                    if isLoading || isLoadingMore {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }

                if showsRefreshProgress || isLoading || isLoadingMore {
                    Text(refreshProgressText)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .foregroundStyle(.primary)
            .frame(minHeight: 40)
            .padding(.horizontal, showsRefreshProgress || isLoading || isLoadingMore ? 16 : 0)
            .frame(width: showsRefreshProgress || isLoading || isLoadingMore ? nil : 40)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isLoadingMore)
        .modifier(MapAccessoryGlassModifier(shape: showsRefreshProgress || isLoading || isLoadingMore ? .capsule : .circle))
    }

    private var mapRefreshToolbarControl: some View {
        Button {
            withAnimation(.snappy(duration: 0.24)) {
                showsRefreshProgress = true
            }
            Task {
                await loadMapCompetitions()
                try? await Task.sleep(for: .seconds(1.2))
                await MainActor.run {
                    withAnimation(.snappy(duration: 0.24)) {
                        showsRefreshProgress = false
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Group {
                    if isLoading || isLoadingMore {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }

                if showsRefreshProgress || isLoading || isLoadingMore {
                    Text(refreshProgressText)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .opacity(showsRefreshProgress || isLoading || isLoadingMore ? 1 : 0)
                        .scaleEffect(showsRefreshProgress || isLoading || isLoadingMore ? 1 : 0.92, anchor: .trailing)
                }
            }
            .padding(.horizontal, showsRefreshProgress || isLoading || isLoadingMore ? 10 : 0)
            .animation(.snappy(duration: 0.22), value: showsRefreshProgress || isLoading || isLoadingMore)
            .animation(.snappy(duration: 0.22), value: refreshProgressText)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isLoadingMore)
    }

    private var refreshProgressText: String {
        let denominator = max(expectedCompetitionCount ?? competitions.count, competitions.count)

        if isLoading || isLoadingMore {
            return String(
                format: localizedCompetitionStringInView(key: "competition.refresh_progress.loaded_format", languageCode: appLanguage),
                competitions.count,
                denominator
            )
        }

        return String(
            format: localizedCompetitionStringInView(key: "competition.refresh_progress.refreshed_format", languageCode: appLanguage),
            competitions.count,
            denominator
        )
    }

    private var mapControls: some View {
        VStack(spacing: 0) {
            mapStyleButton
            locationButton
        }
        .fixedSize()
        .padding(2)
        .modifier(MapAccessoryGlassModifier(shape: .capsule))
    }

    private var isExperimentalExploreGlobe: Bool {
        mapModeSelection == .explore && mapLookSelection == .globe
    }

    private var mapStyleButton: some View {
        Menu {
            Section(localizedCompetitionStringInView(key: "competitions.map_mode.title", languageCode: appLanguage)) {
                Button {
                    mapModeSelection = .explore
                } label: {
                    CompetitionFilterOptionLabel(
                        title: localizedCompetitionStringInView(key: "competitions.map_style.explore", languageCode: appLanguage),
                        isSelected: mapModeSelection == .explore
                    )
                }

                Button {
                    mapModeSelection = .satellite
                } label: {
                    CompetitionFilterOptionLabel(
                        title: localizedCompetitionStringInView(key: "competitions.map_style.satellite", languageCode: appLanguage),
                        isSelected: mapModeSelection == .satellite
                    )
                }
            }

            Section(localizedCompetitionStringInView(key: "competitions.map_look.title", languageCode: appLanguage)) {
                Button {
                    mapLookSelection = .globe
                } label: {
                    CompetitionFilterOptionLabel(
                        title: localizedCompetitionStringInView(key: "competitions.map_look.globe", languageCode: appLanguage),
                        isSelected: mapLookSelection == .globe
                    )
                }

                Button {
                    mapLookSelection = .flat
                } label: {
                    CompetitionFilterOptionLabel(
                        title: localizedCompetitionStringInView(key: "competitions.map_look.flat", languageCode: appLanguage),
                        isSelected: mapLookSelection == .flat
                    )
                }
            }

            if isExperimentalExploreGlobe {
                Section {
                    Text(localizedCompetitionStringInView(key: "competitions.map_look.explore_globe_experimental", languageCode: appLanguage))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Group {
                if mapLookSelection == .globe {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 18, weight: .semibold))
                } else if mapModeSelection == .explore {
                    Image(systemName: "map.fill")
                        .font(.system(size: 18, weight: .semibold))
                } else {
                    Text("🛰️")
                        .font(.system(size: 20))
                }
            }
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
    }

    private var locationButton: some View {
        Button {
            handleLocationButtonTap()
        } label: {
            Image(systemName: isFollowingUserLocation ? "location.fill" : "location")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
    }

    private func mapErrorOverlay(message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(localizedCompetitionStringInView(key: "wca.results_retry", languageCode: appLanguage)) {
                Task {
                    await loadMapCompetitions()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 24)
    }

    private var mapEmptyOverlay: some View {
        Text(localizedCompetitionStringInView(key: "competitions.empty", languageCode: appLanguage))
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func mapCompetitionCard(_ competition: CompetitionSummary) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return Button {
            selectedCompetitionForDetail = competition
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(flagEmoji(for: competition.countryISO2))
                                .font(.system(size: 17))
                            Text(competition.name)
                                .font(.system(size: 17, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(localizedCompetitionDateRange(for: competition))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(competition.locationLine)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            mapStatusBadge(
                                for: mapCompetitionAvailabilityStatus(for: competition),
                                competition: competition
                            )

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }

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
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
            .modifier(CompetitionMapCardBackground())
        }
        .buttonStyle(.plain)
        .background(shape.fill(.black.opacity(0.001)))
        .contentShape(shape)
    }

    private func mapStatusBadge(for status: CompetitionAvailabilityStatus, competition: CompetitionSummary) -> some View {
        Text(statusBadgeTitle(for: status, competition: competition, languageCode: appLanguage))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(mapStatusColor(for: status))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(mapStatusColor(for: status).opacity(0.12), in: Capsule())
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

    private func mapCompetitionAvailabilityStatus(for competition: CompetitionSummary) -> CompetitionAvailabilityStatus {
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

    private func mapStatusColor(for status: CompetitionAvailabilityStatus) -> Color {
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

    @MainActor
    private func loadMapCompetitions() async {
        let cachedSnapshot = await CompetitionService.cachedCompetitions(for: query)
        let localizedCachedCompetitions = await CompetitionService.localizeCompetitionNamesIfNeeded(
            cachedSnapshot?.competitions ?? [],
            languageCode: appLanguage
        )

        competitions = CompetitionService.filterCompetitions(localizedCachedCompetitions, for: query)
        expectedCompetitionCount = cachedSnapshot?.totalCount
        isLoading = competitions.isEmpty
        isLoadingMore = !competitions.isEmpty
        errorMessage = nil
        selectedCompetitionID = nil
        selectedClusterCompetitions = []
        selectedMapItemID = nil
        if !competitions.isEmpty {
            fitCameraToVisibleCompetitions()
            hasPositionedCamera = true
        } else {
            hasPositionedCamera = false
        }

        do {
            try await refreshMapCompetitionsFromNetwork(cachedCompetitions: competitions)
        } catch {
            if competitions.isEmpty {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
        isLoadingMore = false
    }

    private var mapInfoDateText: String {
        let formatter = DateFormatter()
        formatter.locale = appLocale(for: appLanguage)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = localizedCompetitionStringInView(key: "competition.map_info_date_format", languageCode: appLanguage)
        return formatter.string(from: Date())
    }

    private func handleLocationButtonTap() {
        withAnimation(.snappy(duration: 0.28)) {
            selectedCompetitionID = nil
            selectedClusterCompetitions = []
        }
        isFollowingUserLocation = true
        shouldRefocusToUserLocation = true

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            withAnimation(.snappy(duration: 0.28)) {
                focusOnUserLocation()
            }
            locationManager.requestCurrentLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            isFollowingUserLocation = false
        }
    }

    private func focusOnUserLocation() {
        isFollowingUserLocation = true
        cameraPosition = .userLocation(
            followsHeading: false,
            fallback: .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694),
                    span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
                )
            )
        )
    }

    private func focusOnUserLocation(using location: CLLocation) {
        cameraPosition = .region(
            MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: 0.0035,
                    longitudeDelta: 0.0035
                )
            )
        )
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

    private func fitCameraToVisibleCompetitions() {
        let coordinates = mappableCompetitions.compactMap { competition -> CLLocationCoordinate2D? in
            guard let latitude = competition.latitude,
                  let longitude = competition.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        guard !coordinates.isEmpty else { return }

        if coordinates.count == 1, let coordinate = coordinates.first {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6)
                )
            )
            return
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max() else {
            return
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLatitude - minLatitude) * 1.4, 8),
            longitudeDelta: max((maxLongitude - minLongitude) * 1.4, 8)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    @MainActor
    private func requestLocationIfAuthorized() async {
        guard locationManager.authorizationStatus == .authorizedAlways
            || locationManager.authorizationStatus == .authorizedWhenInUse else {
            return
        }
        locationManager.requestCurrentLocation()
        if let currentLocation = locationManager.currentLocation {
            await loadCityIfNeeded(for: currentLocation)
            await loadWeatherIfNeeded(for: currentLocation)
        }
    }

    @MainActor
    private func refreshWeather() async {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if let currentLocation = locationManager.currentLocation {
                await loadWeather(for: currentLocation)
            } else {
                locationManager.requestCurrentLocation()
            }
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            weatherSnapshot = nil
        }
    }

    @MainActor
    private func loadWeatherIfNeeded(for location: CLLocation) async {
        if let lastWeatherLocation,
           location.distance(from: lastWeatherLocation) < 500,
           weatherSnapshot != nil {
            return
        }
        await loadWeather(for: location)
    }

    @MainActor
    private func loadWeather(for location: CLLocation) async {
        isLoadingWeather = true
        defer { isLoadingWeather = false }

        do {
            let weather = try await WeatherService.shared.weather(for: location)
            weatherSnapshot = CompetitionWeatherSnapshot(
                currentWeather: weather.currentWeather,
                languageCode: appLanguage
            )
            lastWeatherLocation = location
        } catch {
            weatherSnapshot = nil
        }
    }

    @MainActor
    private func loadCityIfNeeded(for location: CLLocation) async {
        if let lastResolvedCityLocation,
           location.distance(from: lastResolvedCityLocation) < 500,
           currentCityName != nil {
            return
        }

        guard !isResolvingCity else { return }
        isResolvingCity = true
        defer { isResolvingCity = false }

        do {
            if #available(iOS 26.0, *) {
                guard let request = MKReverseGeocodingRequest(location: location) else { return }
                let mapItems = try await request.mapItems
                guard let mapItem = mapItems.first else { return }
                let addressRepresentations = mapItem.addressRepresentations
                let cityName = addressRepresentations?.cityName
                let cityWithContext = addressRepresentations?.cityWithContext
                let shortCityWithContext = addressRepresentations?.cityWithContext(.short)
                let regionName = addressRepresentations?.regionName
                let shortAddress = mapItem.address?.shortAddress
                let fullAddress = mapItem.address?.fullAddress
                currentCityName = cityName
                    ?? cityWithContext
                    ?? shortCityWithContext
                    ?? regionName
                    ?? shortAddress
                    ?? fullAddress
            } else {
                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                guard let placemark = placemarks.first else { return }
                currentCityName =
                    placemark.locality
                    ?? placemark.subAdministrativeArea
                    ?? placemark.administrativeArea
                    ?? placemark.country
            }
            lastResolvedCityLocation = location
        } catch {
            currentCityName = nil
        }
    }

    @MainActor
    private func refreshMapCompetitionsFromNetwork(cachedCompetitions: [CompetitionSummary]) async throws {
        var freshCompetitions: [CompetitionSummary] = []
        var page = 1

        while true {
            let result = try await CompetitionService.fetchCompetitionsPage(query: query, page: page)
            if expectedCompetitionCount == nil, let totalCount = result.totalCount {
                expectedCompetitionCount = totalCount
            }

            let localizedCompetitions = await CompetitionService.localizeCompetitionNamesIfNeeded(
                result.competitions,
                languageCode: appLanguage
            )
            freshCompetitions.append(contentsOf: localizedCompetitions)
            competitions = CompetitionService.filterCompetitions(
                mergedMapCompetitions(cached: cachedCompetitions, fresh: freshCompetitions),
                for: query
            )

            if !hasPositionedCamera {
                fitCameraToVisibleCompetitions()
                hasPositionedCamera = true
            }

            guard let nextPage = result.nextPage else {
                competitions = CompetitionService.filterCompetitions(freshCompetitions, for: query)
                expectedCompetitionCount = result.totalCount ?? freshCompetitions.count
                await CompetitionService.cacheCompetitions(
                    competitions,
                    totalCount: expectedCompetitionCount,
                    for: query
                )
                return
            }

            page = nextPage
            isLoading = false
            isLoadingMore = true
        }
    }

    private func mergedMapCompetitions(
        cached: [CompetitionSummary],
        fresh: [CompetitionSummary]
    ) -> [CompetitionSummary] {
        let freshIDs = Set(fresh.map(\.id))
        let staleCache = cached.filter { !freshIDs.contains($0.id) }
        return fresh + staleCache
    }
}

@available(iOS 17.0, *)
private enum CompetitionMapMode: String, CaseIterable {
    case satellite
    case explore

    func mapStyle(look: CompetitionMapLook) -> MapStyle {
        switch self {
        case .satellite:
            return .hybrid(elevation: look.elevation)
        case .explore:
            return .standard(elevation: look.elevation)
        }
    }
}

@available(iOS 17.0, *)
private enum CompetitionMapLook: String, CaseIterable {
    case globe
    case flat

    var elevation: MapStyle.Elevation {
        switch self {
        case .globe:
            return .realistic
        case .flat:
            return .flat
        }
    }
}

@MainActor
private final class CompetitionLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var currentLocation: CLLocation?

    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus
        self.currentLocation = manager.location
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.delegate = self
        if manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
            manager.requestLocation()
        }
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestCurrentLocation() {
        manager.startUpdatingLocation()
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedAlways
                || manager.authorizationStatus == .authorizedWhenInUse {
                self.manager.startUpdatingLocation()
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            currentLocation = location
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the last known location if the refresh fails.
    }
}

@available(iOS 16.0, *)
private struct CompetitionWeatherSnapshot {
    let symbolName: String
    let temperatureText: String

    init(currentWeather: CurrentWeather, languageCode: String) {
        symbolName = currentWeather.symbolName

        let formatter = MeasurementFormatter()
        formatter.locale = appLocale(for: languageCode)
        formatter.unitOptions = .temperatureWithoutUnit
        formatter.numberFormatter.maximumFractionDigits = 0
        formatter.numberFormatter.minimumFractionDigits = 0
        temperatureText = formatter.string(from: currentWeather.temperature)
    }
}
#endif

private enum MapAccessoryGlassShape {
    case circle
    case capsule
}

private struct MapAccessoryGlassModifier: ViewModifier {
    let shape: MapAccessoryGlassShape

    @ViewBuilder
    func body(content: Content) -> some View {
        switch shape {
        case .circle:
            if #available(iOS 26.0, *) {
                content
                    .foregroundStyle(.primary)
                    .glassEffect(.regular.interactive(), in: .circle)
            } else {
                content
                    .foregroundStyle(.primary)
                    .background(.regularMaterial, in: Circle())
            }
        case .capsule:
            if #available(iOS 26.0, *) {
                content
                    .foregroundStyle(.primary)
                    .glassEffect(.regular.interactive(), in: .capsule)
            } else {
                content
                    .foregroundStyle(.primary)
                    .background(.regularMaterial, in: Capsule())
            }
        }
    }
}

private struct CompetitionMapCardHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CompetitionMapCardBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
    }
}

private extension View {
    func measureHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: CompetitionMapCardHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(CompetitionMapCardHeightPreferenceKey.self, perform: onChange)
    }
}

private struct CompetitionFilterButtonBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .clipShape(.circle)
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(.thinMaterial, in: Circle())
        }
    }
}

private struct CompetitionFiltersPopover: View {
    @Binding var selectedRegion: CompetitionRegionFilter
    @Binding var selectedEvents: Set<CompetitionEventFilter>
    @Binding var selectedYear: CompetitionYearFilter
    @Binding var selectedStatus: CompetitionStatusFilter
    @Binding var showsTopCubers: Bool
    let appLanguage: String
    @Binding var showsFilterPopover: Bool
    @State private var showsRegionPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(localizedCompetitionStringInView(key: "competitions.filter", languageCode: appLanguage))
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button {
                    showsFilterPopover = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }

            CompetitionFilterButtonRow(
                title: localizedCompetitionStringInView(key: "competitions.filter.region_country", languageCode: appLanguage),
                selectionTitle: selectedRegion.localizedTitle(languageCode: appLanguage)
            ) {
                showsRegionPicker = true
            }

            CompetitionEventMultiSelectSection(
                title: localizedCompetitionStringInView(key: "competitions.filter.event", languageCode: appLanguage),
                selectedEvents: $selectedEvents,
                appLanguage: appLanguage
            )

            CompetitionFilterMenuRow(
                title: localizedCompetitionStringInView(key: "competitions.filter.year", languageCode: appLanguage),
                selectionTitle: selectedYear.localizedTitle(languageCode: appLanguage)
            ) {
                ForEach(CompetitionYearFilter.allCases) { year in
                    Button {
                        selectedYear = year
                    } label: {
                        CompetitionFilterOptionLabel(
                            title: year.localizedTitle(languageCode: appLanguage),
                            isSelected: selectedYear == year
                        )
                    }
                }
            }

            CompetitionFilterMenuRow(
                title: localizedCompetitionStringInView(key: "competitions.filter.status", languageCode: appLanguage),
                selectionTitle: selectedStatus.localizedTitle(languageCode: appLanguage)
            ) {
                ForEach(CompetitionStatusFilter.selectableCases) { status in
                    Button {
                        selectedStatus = status
                    } label: {
                        CompetitionFilterOptionLabel(
                            title: status.localizedTitle(languageCode: appLanguage),
                            isSelected: selectedStatus == status
                        )
                    }
                }
            }

            Toggle(isOn: $showsTopCubers) {
                Text(localizedCompetitionStringInView(key: "competitions.filter.show_top_cubers", languageCode: appLanguage))
                    .font(.system(size: 16, weight: .medium))
            }
            .toggleStyle(.switch)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(width: 290)
        .task {
            await CompetitionService.warmRecognizedCountriesCache()
        }
        .sheet(isPresented: $showsRegionPicker) {
            CompetitionRegionPickerView(
                selectedRegion: $selectedRegion,
                appLanguage: appLanguage
            )
        }
    }
}

private struct CompetitionFilterOptionLabel: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
            }
        }
    }
}

private struct CompetitionEventMultiSelectSection: View {
    let title: String
    @Binding var selectedEvents: Set<CompetitionEventFilter>
    let appLanguage: String

    private var allSelectableEvents: Set<CompetitionEventFilter> {
        Set(CompetitionEventFilter.selectableCases)
    }

    private var allEventsSelected: Bool {
        selectedEvents == allSelectableEvents
    }

    private var selectionTitle: String {
        if allEventsSelected {
            return CompetitionEventFilter.all.localizedTitle(languageCode: appLanguage)
        }

        if selectedEvents.count == 1, let first = selectedEvents.first {
            return first.localizedTitle(languageCode: appLanguage)
        }

        return String(
            format: localizedCompetitionStringInView(
                key: "competitions.event.selected_count",
                languageCode: appLanguage
            ),
            selectedEvents.count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Menu {
                Button {
                    toggle(.all)
                } label: {
                    CompetitionFilterOptionLabel(
                        title: CompetitionEventFilter.all.localizedTitle(languageCode: appLanguage),
                        isSelected: allEventsSelected
                    )
                }

                Divider()

                ForEach(CompetitionEventFilter.selectableCases) { event in
                    Button {
                        toggle(event)
                    } label: {
                        CompetitionFilterOptionLabel(
                            title: event.localizedTitle(languageCode: appLanguage),
                            isSelected: isSelected(event)
                        )
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectionTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .compatibleMenuActionDismissBehaviorDisabled()
        }
    }

    private func isSelected(_ event: CompetitionEventFilter) -> Bool {
        if event == .all {
            return allEventsSelected
        }
        return selectedEvents.contains(event)
    }

    private func toggle(_ event: CompetitionEventFilter) {
        if event == .all {
            selectedEvents = allSelectableEvents
            return
        }

        if allEventsSelected {
            selectedEvents = [event]
            return
        }

        if selectedEvents.contains(event) {
            if selectedEvents.count == 1 {
                selectedEvents = allSelectableEvents
            } else {
                selectedEvents.remove(event)
            }
        } else {
            selectedEvents.insert(event)
        }
    }
}

private struct CompetitionFilterButtonRow: View {
    let title: String
    let selectionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Button(action: action) {
                HStack(spacing: 8) {
                    Text(selectionTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CompetitionFilterMenuRow<MenuContent: View>: View {
    let title: String
    let selectionTitle: String
    @ViewBuilder let menuContent: () -> MenuContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Menu {
                menuContent()
            } label: {
                HStack(spacing: 8) {
                    Text(selectionTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CompetitionRegionPickerView: View {
    private struct CountryOption: Identifiable, Hashable {
        let code: String
        let title: String
        let wcaName: String

        var id: String { code }

        var searchableText: String {
            [title, wcaName, code].joined(separator: " ").lowercased()
        }
    }

    @Binding var selectedRegion: CompetitionRegionFilter
    let appLanguage: String

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var countries: [CountryOption] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredCountries: [CountryOption] {
        guard !normalizedSearchText.isEmpty else {
            return countries
        }

        return countries.filter { country in
            country.searchableText.contains(normalizedSearchText)
        }
    }

    var body: some View {
        CompatibleNavigationContainer {
            List {
                allRegionsSection
                continentSection
                countrySection
            }
            .listStyle(.insetGrouped)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: localizedCompetitionStringInView(
                    key: "competitions.region.search",
                    languageCode: appLanguage
                )
            )
            .navigationTitle(localizedCompetitionStringInView(key: "competitions.filter.region_country", languageCode: appLanguage))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localizedCompetitionStringInView(key: "common.done", languageCode: appLanguage)) {
                        dismiss()
                    }
                }
            }
            .task {
                guard countries.isEmpty else { return }
                isLoading = true
                errorMessage = nil

                do {
                    let recognizedCountries = try await CompetitionService.fetchRecognizedCountries()
                    countries = recognizedCountries.map { country in
                        CountryOption(
                            code: country.code,
                            title: country.localizedTitle(languageCode: appLanguage),
                            wcaName: country.wcaName
                        )
                    }
                } catch {
                    errorMessage = error.localizedDescription
                    countries = []
                }

                isLoading = false
            }
        }
        .compatibleMediumLargeSheet()
    }

    private var allRegionsSection: some View {
        Section {
            regionButton(
                title: CompetitionRegionFilter.all.localizedTitle(languageCode: appLanguage),
                isSelected: selectedRegion == .all
            ) {
                applyRegionSelection(.all)
            }
        }
    }

    private var continentSection: some View {
        Section {
            ForEach(CompetitionContinent.allCases) { continent in
                let option = CompetitionRegionFilter.continent(continent)
                regionButton(
                    title: option.localizedTitle(languageCode: appLanguage),
                    isSelected: selectedRegion == option
                ) {
                    applyRegionSelection(option)
                }
            }
        }
    }

    @ViewBuilder
    private var countrySection: some View {
        Section {
            if isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(localizedCompetitionStringInView(key: "competitions.loading", languageCode: appLanguage))
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredCountries) { country in
                    countryButton(for: country)
                }
            }
        }
    }

    private func countryButton(for country: CountryOption) -> some View {
        let option = CompetitionRegionFilter.country(country.code)

        return Button {
            applyRegionSelection(option)
        } label: {
            HStack(spacing: 12) {
                Text(flagEmoji(for: country.code))
                CompetitionFilterOptionLabel(
                    title: country.title,
                    isSelected: selectedRegion == option
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func applyRegionSelection(_ region: CompetitionRegionFilter) {
        dismiss()
        DispatchQueue.main.async {
            selectedRegion = region
        }
    }

    private func regionButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            CompetitionFilterOptionLabel(
                title: title,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
    }
}

private func localizedCompetitionStringInView(key: String, languageCode: String) -> String {
    appLocalizedString(key, languageCode: languageCode)
}

private func flagEmoji(for countryCode: String) -> String {
    guard countryCode.count == 2 else { return "" }

    let regionalIndicatorBase: UInt32 = 127397
    let scalars = countryCode.uppercased().unicodeScalars.compactMap { scalar in
        UnicodeScalar(regionalIndicatorBase + scalar.value)
    }
    return String(String.UnicodeScalarView(scalars))
}

private struct CompetitionMapDisplayItem: Identifiable {
    enum Kind {
        case competition(String)
        case cluster([CompetitionSummary])
    }

    let id: String
    let title: String
    let coordinate: CLLocationCoordinate2D
    let kind: Kind
}

private struct CompetitionSearchView: View {
    let competitions: [CompetitionSummary]
    let appLanguage: String

    @State private var searchText = ""

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredCompetitions: [CompetitionSummary] {
        guard !normalizedSearchText.isEmpty else { return competitions }

        return competitions.filter { competition in
            let haystack = [
                competition.name,
                competition.locationLine,
                competition.venueLine
            ]
            .joined(separator: " ")
            .lowercased()

            return haystack.contains(normalizedSearchText)
        }
    }

    var body: some View {
        List {
            if normalizedSearchText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizedCompetitionStringInView(key: "competitions.search.empty_query_title", languageCode: appLanguage))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(localizedCompetitionStringInView(key: "competitions.search.empty_query_body", languageCode: appLanguage))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else if filteredCompetitions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizedCompetitionStringInView(key: "competitions.search.no_results_title", languageCode: appLanguage))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(localizedCompetitionStringInView(key: "competitions.search.no_results_body", languageCode: appLanguage))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredCompetitions) { competition in
                    NavigationLink {
                        CompetitionDetailView(
                            competition: competition,
                            appLanguage: appLanguage
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text(flagEmoji(for: competition.countryISO2))
                                            .font(.system(size: 18))
                                        Text(competition.name)
                                            .font(.system(size: 18, weight: .semibold))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Text(competition.locationLine)
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 12)
                            }

                            if !competition.venueLine.isEmpty {
                                Text(competition.venueLine)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
        }
        .listStyle(.plain)
        .compatibleScrollContentBackgroundHidden()
        .navigationTitle(Text(localizedCompetitionStringInView(key: "competitions.search_title", languageCode: appLanguage)))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(localizedCompetitionStringInView(key: "competitions.search_placeholder", languageCode: appLanguage))
        )
    }
}

#if os(iOS)
private struct CompetitionNavigationBarFontConfigurator: UIViewControllerRepresentable {
    let largeSubtitle: String

    func makeUIViewController(context: Context) -> CompetitionNavigationBarFontConfiguratorController {
        CompetitionNavigationBarFontConfiguratorController()
    }

    func updateUIViewController(_ uiViewController: CompetitionNavigationBarFontConfiguratorController, context: Context) {
        uiViewController.applyFontsIfNeeded(largeSubtitle: largeSubtitle)
    }
}

private final class CompetitionNavigationBarFontConfiguratorController: UIViewController {
    func applyFontsIfNeeded(largeSubtitle: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let navigationController = self.resolvedNavigationController() else { return }
            let navigationBar = navigationController.navigationBar

            let largeTitleBase = UIFont.preferredFont(forTextStyle: .largeTitle)
            let largeTitleFont = UIFont.systemFont(ofSize: largeTitleBase.pointSize, weight: .bold)
            let inlineTitleFont = UIFont.systemFont(ofSize: 15, weight: .semibold)
            let inlineSubtitleFont = UIFont.systemFont(ofSize: 12, weight: .medium)

            let standardAppearance = navigationBar.standardAppearance.copy()
            standardAppearance.titleTextAttributes[.font] = inlineTitleFont
            if #available(iOS 26.0, *) {
                standardAppearance.subtitleTextAttributes[.font] = inlineSubtitleFont
            }

            let scrollEdgeAppearance = navigationBar.scrollEdgeAppearance?.copy() ?? standardAppearance.copy()
            scrollEdgeAppearance.largeTitleTextAttributes[.font] = largeTitleFont
            scrollEdgeAppearance.titleTextAttributes[.font] = inlineTitleFont
            if #available(iOS 26.0, *) {
                scrollEdgeAppearance.subtitleTextAttributes[.font] = inlineSubtitleFont
            }

            navigationBar.standardAppearance = standardAppearance
            navigationBar.compactAppearance = standardAppearance
            navigationBar.scrollEdgeAppearance = scrollEdgeAppearance
            if #available(iOS 17.0, *) {
                navigationBar.compactScrollEdgeAppearance = scrollEdgeAppearance
            }

            guard let targetNavigationItem = self.resolvedNavigationItem(from: navigationController) else { return }

            if #available(iOS 16.0, *) {
                targetNavigationItem.style = .browser
            }
            if #available(iOS 26.0, *) {
                targetNavigationItem.largeSubtitleView = CompetitionLargeSubtitleContainerView(
                    text: largeSubtitle,
                    topInset: 4
                )
            }
        }
    }

    private func resolvedNavigationController() -> UINavigationController? {
        if let navigationController {
            return navigationController
        }

        var current: UIViewController? = parent
        while let controller = current {
            if let navigationController = controller.navigationController {
                return navigationController
            }
            current = controller.parent
        }

        return nil
    }

    private func resolvedNavigationItem(from navigationController: UINavigationController) -> UINavigationItem? {
        if let topItem = navigationController.topViewController?.navigationItem {
            return topItem
        }

        var current: UIViewController? = parent
        while let controller = current {
            let item = controller.navigationItem
            if item.title != nil {
                return item
            }
            if #available(iOS 26.0, *), item.subtitle != nil || item.largeSubtitle != nil {
                return item
            }
            current = controller.parent
        }

        return navigationController.visibleViewController?.navigationItem
    }
}

private final class CompetitionLargeSubtitleContainerView: UIView {
    private let label = UILabel()
    private let topInset: CGFloat

    init(text: String, topInset: CGFloat) {
        self.topInset = topInset
        super.init(frame: .zero)

        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabel
        label.text = text
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: topInset),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let labelSize = label.intrinsicContentSize
        return CGSize(width: labelSize.width, height: labelSize.height + topInset)
    }
}
#endif

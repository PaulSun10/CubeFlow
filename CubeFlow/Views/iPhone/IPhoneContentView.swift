
import SwiftUI

#if os(iOS)
struct IPhoneContentView: View {
    #if DEBUG
    private let marketingPreviewConfiguration: Binding<MarketingTimerPreviewConfiguration>?
    #endif
    @State private var isDataSelectingSolves = false
    @State private var selectedTab: IPhoneTab = .timer
    @State private var algsSearchRequestID = 0
    @State private var exploreCompetitionRequestID = 0
    @State private var exploreCompetitionSearchRequestID = 0
    @State private var isExploreCompetitionBottomAccessoryVisible = false
    @State private var dataSearchRequestID = 0
    @State private var isAlgsOverviewBottomAccessoryVisible = false
    @State private var isDataBottomAccessoryVisible = false
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("requestedIPhoneTab") private var requestedIPhoneTab: String = ""
    @AppStorage("algBrowseViewModeStore") private var algBrowseViewModeStore: String = AlgBrowseViewMode.list.rawValue

    #if DEBUG
    init(marketingPreviewConfiguration: Binding<MarketingTimerPreviewConfiguration>? = nil) {
        self.marketingPreviewConfiguration = marketingPreviewConfiguration
    }
    #endif

    private var contentLocale: Locale {
        appLocale(for: appLanguage)
    }

    private var usesSystemTabBottomAccessory: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    var body: some View {
        TabView(selection: Binding(get: { selectedTab }, set: { if !isDataSelectingSolves { selectedTab = $0 } })) {
            timerTabContent
                .tabItem {
                    Label {
                        Text(appLocalizedString("tab.timer", languageCode: appLanguage))
                    } icon: {
                        Image(systemName: "clock.fill")
                    }
                }
                .tag(IPhoneTab.timer)

            DataTabView(
                usesSystemBottomAccessory: usesSystemTabBottomAccessory,
                isBottomAccessoryVisible: $isDataBottomAccessoryVisible,
                searchRequestID: $dataSearchRequestID,
                isSelectingSolves: $isDataSelectingSolves
            )
                .tabItem {
                    Label {
                        Text(appLocalizedString("tab.data", languageCode: appLanguage))
                    } icon: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                }
                .tag(IPhoneTab.data)

            AlgsTabView(
                usesSystemBottomAccessory: usesSystemTabBottomAccessory,
                isActive: selectedTab == .algs,
                isOverviewBottomAccessoryVisible: $isAlgsOverviewBottomAccessoryVisible,
                searchRequestID: $algsSearchRequestID
            )
                .tabItem {
                    Label {
                        Text(appLocalizedString("tab.algs", languageCode: appLanguage))
                    } icon: {
                        Image(systemName: "book.closed.fill")
                    }
                }
                .tag(IPhoneTab.algs)

            ExploreView(
                isActive: selectedTab == .explore,
                competitionRequestID: exploreCompetitionRequestID,
                usesSystemBottomAccessory: usesSystemTabBottomAccessory,
                isCompetitionBottomAccessoryVisible: $isExploreCompetitionBottomAccessoryVisible,
                searchRequestID: $exploreCompetitionSearchRequestID
            )
                .tabItem {
                    Label(appLocalizedString("tab.explore", languageCode: appLanguage), systemImage: "binoculars")
                }
                .tag(IPhoneTab.explore)

            SettingsTabView(isActive: selectedTab == .settings)
                .tabItem {
                    Label {
                        Text(appLocalizedString("tab.settings", languageCode: appLanguage))
                    } icon: {
                        Image(systemName: "gearshape.fill")
                    }
                }
                .tag(IPhoneTab.settings)
        }
        .compatibleSoftScrollEdgeEffect()
        .compatibleTabViewBottomAccessory(isEnabled: shouldShowTabBottomAccessory) {
            tabBottomAccessoryContent
        }
        .compatibleTabBarMinimizeOnScrollDown(
            isEnabled: !isDataSelectingSolves && (selectedTab == .data || selectedTab == .algs || selectedTab == .explore)
        )
        .compatibleTabBarBackground()
        .environment(\.locale, contentLocale)
        .environment(\.layoutDirection, appUsesRightToLeftLayout(for: appLanguage) ? .rightToLeft : .leftToRight)
        .onAppear(perform: handleRequestedTab)
        .onChange(of: requestedIPhoneTab) { _ in
            handleRequestedTab()
        }
        .onChange(of: isDataSelectingSolves) { selecting in
            if !selecting { handleRequestedTab() }
        }
    }

    @ViewBuilder
    private var timerTabContent: some View {
        #if DEBUG
        TimerTabView(isActive: selectedTab == .timer, marketingPreviewConfiguration: marketingPreviewConfiguration)
        #else
        TimerTabView(isActive: selectedTab == .timer)
        #endif
    }

    private var shouldShowTabBottomAccessory: Bool {
        shouldShowDataBottomAccessory || shouldShowAlgsBottomAccessory
            || (selectedTab == .explore && isExploreCompetitionBottomAccessoryVisible)
    }

    private var shouldShowDataBottomAccessory: Bool {
        selectedTab == .data && isDataBottomAccessoryVisible
    }

    private var shouldShowAlgsBottomAccessory: Bool {
        selectedTab == .algs && isAlgsOverviewBottomAccessoryVisible
    }

    @ViewBuilder
    private var tabBottomAccessoryContent: some View {
        switch selectedTab {
        case .data:
            DataBottomSearchBar(languageCode: appLanguage, usesContainerGlass: false) {
                dataSearchRequestID += 1
            }
        case .algs:
            AlgOverviewBottomBar(
                languageCode: appLanguage,
                browseViewModeSelection: algsOverviewBrowseViewModeSelection,
                usesContainerGlass: false
            ) {
                algsSearchRequestID += 1
            }
        case .explore:
            CompetitionBottomSearchBar(languageCode: appLanguage, usesContainerGlass: false) {
                exploreCompetitionSearchRequestID += 1
            }
        default:
            EmptyView()
        }
    }

    private var algsOverviewBrowseViewMode: AlgBrowseViewMode {
        algBrowseViewMode(setID: "global", storage: algBrowseViewModeStore)
    }

    private var algsOverviewBrowseViewModeSelection: Binding<String> {
        Binding(
            get: { algsOverviewBrowseViewMode.rawValue },
            set: { newValue in
                guard let mode = AlgBrowseViewMode(rawValue: newValue) else { return }
                algBrowseViewModeStore = updatedAlgBrowseViewModeStorage(
                    storage: algBrowseViewModeStore,
                    setID: "global",
                    mode: mode
                )
            }
        )
    }

    private func handleRequestedTab() {
        guard !isDataSelectingSolves else { return }
        if requestedIPhoneTab == "competitions" {
            selectedTab = .explore
            exploreCompetitionRequestID += 1
            requestedIPhoneTab = ""
            return
        }
        guard let requested = IPhoneTab(rawValue: requestedIPhoneTab) else { return }
        selectedTab = requested
        requestedIPhoneTab = ""
    }
}

private extension View {
    @ViewBuilder
    func compatibleTabViewBottomAccessory<Content: View>(
        isEnabled: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(iOS 26.1, *) {
            self.tabViewBottomAccessory(isEnabled: isEnabled) {
                content()
            }
        } else if #available(iOS 26.0, *) {
            if isEnabled {
                self.tabViewBottomAccessory {
                    content()
                }
            } else {
                self
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleTabBarMinimizeOnScrollDown(isEnabled: Bool) -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(isEnabled ? .onScrollDown : .never)
        } else {
            self
        }
    }
}
#endif

private enum IPhoneTab: String {
    case timer
    case data
    case algs
    case explore
    case settings
}

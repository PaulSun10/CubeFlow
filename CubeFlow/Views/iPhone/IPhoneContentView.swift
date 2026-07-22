import SwiftUI

#if os(iOS)
struct IPhoneContentView: View {
    @State private var selectedTab: IPhoneTab = .timer
    @State private var algsSearchRequestID = 0
    @State private var competitionSearchRequestID = 0
    @State private var dataSearchRequestID = 0
    @State private var isAlgsOverviewBottomAccessoryVisible = false
    @State private var isCompetitionBottomAccessoryVisible = false
    @State private var isDataBottomAccessoryVisible = false
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("requestedIPhoneTab") private var requestedIPhoneTab: String = ""
    @AppStorage("algBrowseViewModeStore") private var algBrowseViewModeStore: String = AlgBrowseViewMode.list.rawValue

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
        TabView(selection: $selectedTab) {
            TimerTabView()
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
                searchRequestID: $dataSearchRequestID
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

            CompetitionTabView(
                usesSystemBottomAccessory: usesSystemTabBottomAccessory,
                isActive: selectedTab == .competitions,
                isBottomAccessoryVisible: $isCompetitionBottomAccessoryVisible,
                searchRequestID: $competitionSearchRequestID
            )
                .tabItem {
                    Label {
                        Text(appLocalizedString("tab.competitions", languageCode: appLanguage))
                    } icon: {
                        Image(systemName: competitionsTabSystemImage)
                    }
                }
                .tag(IPhoneTab.competitions)

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
        .compatibleTabViewBottomAccessory(isEnabled: shouldShowTabBottomAccessory) {
            tabBottomAccessoryContent
        }
        .compatibleTabBarMinimizeOnScrollDown(
            isEnabled: selectedTab == .data || selectedTab == .algs || selectedTab == .competitions
        )
        .compatibleTabBarBackground()
        .environment(\.locale, contentLocale)
        .environment(\.layoutDirection, appUsesRightToLeftLayout(for: appLanguage) ? .rightToLeft : .leftToRight)
        .onAppear(perform: handleRequestedTab)
        .onChange(of: requestedIPhoneTab) { _ in
            handleRequestedTab()
        }
    }

    private var shouldShowTabBottomAccessory: Bool {
        shouldShowDataBottomAccessory || shouldShowAlgsBottomAccessory || shouldShowCompetitionBottomAccessory
    }

    private var shouldShowDataBottomAccessory: Bool {
        selectedTab == .data && isDataBottomAccessoryVisible
    }

    private var shouldShowAlgsBottomAccessory: Bool {
        selectedTab == .algs && isAlgsOverviewBottomAccessoryVisible
    }

    private var shouldShowCompetitionBottomAccessory: Bool {
        selectedTab == .competitions && isCompetitionBottomAccessoryVisible
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
        case .competitions:
            CompetitionBottomSearchBar(
                languageCode: appLanguage,
                usesContainerGlass: false
            ) {
                competitionSearchRequestID += 1
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

    private var competitionsTabSystemImage: String {
        if #available(iOS 16.0, *) {
            return "trophy.fill"
        }
        return "flag.2.crossed.fill"
    }

    private func handleRequestedTab() {
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
    case competitions
    case settings
}

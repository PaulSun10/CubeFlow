import SwiftUI

#if os(iOS)
struct IPhoneContentView: View {
    @State private var selectedTab: IPhoneTab = .timer
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("requestedIPhoneTab") private var requestedIPhoneTab: String = ""

    private var contentLocale: Locale {
        appLocale(for: appLanguage)
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

            DataTabView()
                .tabItem {
                    Label {
                        Text(appLocalizedString("tab.data", languageCode: appLanguage))
                    } icon: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                }
                .tag(IPhoneTab.data)

            AlgsTabView()
                .tabItem {
                    Label {
                        Text(appLocalizedString("tab.algs", languageCode: appLanguage))
                    } icon: {
                        Image(systemName: "book.closed.fill")
                    }
                }
                .tag(IPhoneTab.algs)

            CompetitionTabView()
                .tabItem {
                    Label {
                        Text(appLocalizedString("tab.competitions", languageCode: appLanguage))
                    } icon: {
                        Image(systemName: competitionsTabSystemImage)
                    }
                }
                .tag(IPhoneTab.competitions)

            SettingsTabView()
                .tabItem {
                    Label {
                        Text(appLocalizedString("tab.settings", languageCode: appLanguage))
                    } icon: {
                        Image(systemName: "gearshape.fill")
                    }
                }
                .tag(IPhoneTab.settings)
        }
        .compatibleTabBarBackground()
        .environment(\.locale, contentLocale)
        .environment(\.layoutDirection, appUsesRightToLeftLayout(for: appLanguage) ? .rightToLeft : .leftToRight)
        .onAppear(perform: handleRequestedTab)
        .onChange(of: requestedIPhoneTab) { _ in
            handleRequestedTab()
        }
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
#endif

private enum IPhoneTab: String {
    case timer
    case data
    case algs
    case competitions
    case settings
}

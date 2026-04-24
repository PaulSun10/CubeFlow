import SwiftUI

#if os(iOS)
struct IPhoneContentView: View {
    @State private var selectedTab: IPhoneTab = .timer
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    private var contentLocale: Locale {
        appLocale(for: appLanguage)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TimerTabView()
                .tabItem {
                    Label("tab.timer", systemImage: "clock.fill")
                }
                .tag(IPhoneTab.timer)

            DataTabView()
                .tabItem {
                    Label("tab.data", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(IPhoneTab.data)

            AlgsTabView()
                .tabItem {
                    Label("tab.algs", systemImage: "book.closed.fill")
                }
                .tag(IPhoneTab.algs)

            CompetitionTabView()
                .tabItem {
                    Label("tab.competitions", systemImage: competitionsTabSystemImage)
                }
                .tag(IPhoneTab.competitions)

            SettingsTabView()
                .tabItem {
                    Label("tab.settings", systemImage: "gearshape.fill")
                }
                .tag(IPhoneTab.settings)
        }
        .compatibleTabBarBackground()
        .environment(\.locale, contentLocale)
    }

    private var competitionsTabSystemImage: String {
        if #available(iOS 16.0, *) {
            return "trophy.fill"
        }
        return "flag.2.crossed.fill"
    }
}
#endif

private enum IPhoneTab {
    case timer
    case data
    case algs
    case competitions
    case settings
}

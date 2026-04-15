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
                    Label("tab.competitions", systemImage: "trophy.fill")
                }
                .tag(IPhoneTab.competitions)

            SettingsTabView()
                .tabItem {
                    Label("tab.settings", systemImage: "gearshape.fill")
                }
                .tag(IPhoneTab.settings)
        }
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .environment(\.locale, contentLocale)
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

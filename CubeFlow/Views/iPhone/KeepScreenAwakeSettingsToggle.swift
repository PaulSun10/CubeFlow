import SwiftUI

#if os(iOS)
struct KeepScreenAwakeSettingsToggle: View {
    @Binding var isOn: Bool
    @Environment(\.featureBadgeMarketingVersion) private var marketingVersion

    var body: some View {
        Toggle(isOn: $isOn) {
            label
        }
        .accessibilityLabel(label.accessibilityTitle(marketingVersion: marketingVersion))
    }

    private var label: FeatureBadgeTitle {
        FeatureBadgeTitle(title: Text("settings.keep_screen_awake"), placement: .keepScreenAwake)
    }
}

#if DEBUG
struct KeepScreenAwakeSettingsToggle_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            row().preferredColorScheme(.light)
            row().preferredColorScheme(.dark).environment(\.locale, Locale(identifier: "zh-Hans"))
            row().environment(\.locale, Locale(identifier: "de")).dynamicTypeSize(.accessibility2)
            row().environment(\.locale, Locale(identifier: "ar")).environment(\.layoutDirection, .rightToLeft)
            row(version: "0.16.2")
        }
    }

    private static func row(version: String = "0.16.1") -> some View {
        List {
            Section {
                KeepScreenAwakeSettingsToggle(isOn: .constant(true))
            } header: {
                Text("settings.section.timer")
            } footer: {
                Text("settings.keep_screen_awake_description")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.featureBadgeMarketingVersion, version)
    }
}
#endif
#endif

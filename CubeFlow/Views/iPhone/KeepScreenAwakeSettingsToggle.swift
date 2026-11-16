import SwiftUI

#if os(iOS)
struct KeepScreenAwakeSettingsToggle: View {
    @Binding var isOn: Bool
    var badge: FeatureBadgeKind? = .new

    var body: some View {
        Toggle(isOn: $isOn) {
            label
        }
        .accessibilityLabel(label.accessibilityTitle)
    }

    private var label: FeatureBadgeTitle {
        FeatureBadgeTitle(title: Text("settings.keep_screen_awake"), kind: badge)
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
            row(badge: nil)
        }
    }

    private static func row(badge: FeatureBadgeKind? = .new) -> some View {
        List {
            Section {
                KeepScreenAwakeSettingsToggle(isOn: .constant(true), badge: badge)
            } header: {
                Text("settings.section.timer")
            } footer: {
                Text("settings.keep_screen_awake_description")
            }
        }
        .listStyle(.insetGrouped)
    }
}
#endif
#endif

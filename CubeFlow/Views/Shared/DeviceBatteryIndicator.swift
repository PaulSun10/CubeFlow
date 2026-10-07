#if os(iOS)
import SwiftUI

nonisolated enum DeviceBatteryLevel {
    static func clamped(_ percentage: Int) -> Int {
        min(max(percentage, 0), 100)
    }
}

struct DeviceBatteryIndicator: View {
    let percentage: Int

    private var level: Int { DeviceBatteryLevel.clamped(percentage) }
    private var batteryColor: Color {
        level <= 20 ? Color(uiColor: .systemRed) : .primary
    }

    var body: some View {
        Text("\(level)%")
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(batteryColor)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("smart_cube.battery"))
        .accessibilityValue(Text("\(level)%"))
    }
}
#endif

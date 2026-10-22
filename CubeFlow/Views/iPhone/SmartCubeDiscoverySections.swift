#if os(iOS)
import SwiftUI

struct SmartCubeDeviceListSnapshot {
    let saved: [SavedSmartCubeDevice]
    let other: [SmartCubeDiscoveredDevice]
    let connectableSavedIDs: Set<UUID>

    init(saved: [SavedSmartCubeDevice], discovered: [SmartCubeDiscoveredDevice], connected: Set<UUID>, connecting: Set<UUID>) {
        self.saved = saved
        let savedIDs = Set(saved.map(\.id))
        var seen = savedIDs.union(connected)
        other = discovered.filter { seen.insert($0.id).inserted }
        connectableSavedIDs = savedIDs.intersection(discovered.map(\.id)).subtracting(connected).subtracting(connecting)
    }
}

/// Shared native list sections for Settings and Timer's existing device picker.
struct SmartCubeDiscoverySections: View {
    @ObservedObject var manager: SmartCubeBluetoothManager
    @ObservedObject var saved: SavedSmartCubeDevices
    @AppStorage("appLanguage") private var languageCode = "en"
    var showsDiagnostics = false
    let connect: (UUID) -> Void
    let manage: (UUID) -> Void

    private var snapshot: SmartCubeDeviceListSnapshot {
        .init(saved: saved.devices, discovered: manager.discoveredDevices,
              connected: Set(manager.connectedDeviceIDs),
              connecting: Set(saved.devices.filter { manager.session(for: $0.id)?.connectionState == .connecting }.map(\.id)))
    }

    var body: some View {
        let rows = snapshot
        if !rows.saved.isEmpty {
            savedDevicesSection(rows)
        }
        otherDevicesSection(rows)
    }

    private func savedDevicesSection(_ rows: SmartCubeDeviceListSnapshot) -> some View {
        Section("smart_cube.my_devices") {
            if manager.compatibleConnectedDeviceIDs.count > 1 {
                HStack { Text("smart_cube.device.active"); Spacer(); SmartCubeActiveDeviceMenu() }
            }
            ForEach(rows.saved) { device in
                HStack {
                    if manager.session(for: device.id)?.isConnected == true {
                        Button { manage(device.id) } label: { label(device) }.buttonStyle(.plain)
                    } else {
                        label(device).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if rows.connectableSavedIDs.contains(device.id) {
                        SmartCubeNativeAction(title: appLocalizedString("smart_cube.device.connect", languageCode: languageCode),
                            tint: .systemBlue, enabled: true, identifier: "smart-cube-connect-" + device.id.uuidString) {
                            guard manager.discoveredDevices.contains(where: { $0.id == device.id }) else { return }
                            connect(device.id)
                        }
                        .fixedSize()
                    }
                }.accessibilityIdentifier("smart-cube-saved-" + device.id.uuidString)
            }
        }
    }

    private func otherDevicesSection(_ rows: SmartCubeDeviceListSnapshot) -> some View {
        Section {
            ForEach(rows.other) { device in
                Button {
                    guard manager.discoveredDevices.contains(where: { $0.id == device.id }) else { return }
                    connect(device.id)
                } label: {
                    HStack {
                        SmartCubeDiscoveredDeviceRow(device: device, showsDiagnostics: showsDiagnostics)
                        if manager.session(for: device.id)?.connectionState == .connecting { ProgressView() }
                    }
                }
                    .disabled(manager.session(for: device.id)?.connectionState == .connecting)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("smart-cube-discovered-" + device.id.uuidString)
            }
        } header: {
            HStack(spacing: 8) {
                Text("smart_cube.other_devices")
                if manager.isScanningForDevices {
                    ProgressView().progressViewStyle(.circular).controlSize(.regular)
                        .accessibilityLabel(Text("smart_cube.status.scanning"))
                        .accessibilityIdentifier("smart-cube-discovery-scanning")
                }
            }
        }
    }

    private func label(_ device: SavedSmartCubeDevice) -> some View {
        SmartCubeDeviceLabel(device: device, isConnected: manager.session(for: device.id)?.isConnected == true,
            isConnecting: manager.session(for: device.id)?.connectionState == .connecting,
            battery: manager.session(for: device.id)?.batteryLevel)
    }
}
#endif

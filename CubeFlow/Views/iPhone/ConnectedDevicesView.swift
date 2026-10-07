#if os(iOS)
import SwiftUI

struct ConnectedDeviceStatusRows: View {
    @ObservedObject private var smartCube = SmartCubeBluetoothManager.shared
    @ObservedObject private var smartTimer = GANTimerBluetoothManager.shared
    @ObservedObject private var savedCubes = SavedSmartCubeDevices.shared
    let usesCompactLinks: Bool
    let showsSmartTimer: Bool

    init(usesCompactLinks: Bool = false, showsSmartTimer: Bool = true) {
        self.usesCompactLinks = usesCompactLinks
        self.showsSmartTimer = showsSmartTimer
    }

    var body: some View {
        if usesCompactLinks {
            VStack(alignment: .leading, spacing: 8) { compactDeviceLinks }
        } else {
            statusRow(
                "smart_cube.title",
                identity: smartCube.isConnected ? connectedCubeName : nil,
                model: smartCube.isConnected ? connectedCubeModel : nil,
                battery: smartCube.isConnected ? smartCube.batteryLevel : nil,
                status: smartCubeConnectionStatusKey(smartCube.connectionState),
                cubeSize: smartCube.isConnected ? smartCube.puzzleSize : nil
            )
            statusRow(
                "connected_devices.smart_timer",
                identity: smartTimer.isConnected ? smartTimer.deviceName : nil,
                battery: smartTimer.isConnected ? smartTimer.batteryLevel : nil,
                status: LocalizedStringKey(smartTimer.statusLocalizedKey)
            )
        }
    }

    @ViewBuilder
    private var compactDeviceLinks: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    NavigationLink { SmartCubeLabView() } label: {
                        if let name = connectedCubeName, smartCube.isConnected {
                            Text(name).lineLimit(1)
                        } else {
                            Text("smart_cube.title")
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    if smartCube.compatibleConnectedDeviceIDs.count > 1 {
                        SmartCubeActiveDeviceMenu()
                    }
                }
                if !smartCube.isConnected {
                    Text(smartCube.activeDeviceID == nil && !smartCube.compatibleConnectedDeviceIDs.isEmpty
                         ? "smart_cube.device.no_active" : smartCubeConnectionStatusKey(smartCube.connectionState))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let model = connectedCubeModel, smartCube.isConnected {
                    Text(model).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if smartCube.isConnected, let battery = smartCube.batteryLevel {
                DeviceBatteryIndicator(percentage: battery)
            }
        }
        if showsSmartTimer {
            NavigationLink {
                SmartTimerDeviceView()
            } label: {
                compactRow(
                    "connected_devices.smart_timer",
                    name: smartTimer.isConnected ? smartTimer.deviceName : nil,
                    battery: smartTimer.isConnected ? smartTimer.batteryLevel : nil,
                    status: LocalizedStringKey(smartTimer.statusLocalizedKey),
                    isConnected: smartTimer.isConnected,
                    showsConnectedStatus: smartTimer.connectionState != .connected
                )
            }
        }
    }

    private var connectedCubeName: String? {
        guard let id = smartCube.connectionDeviceID else { return nil }
        return savedCubes.device(id)?.displayName ?? smartCube.connectedDeviceName
    }

    private var connectedCubeModel: String? {
        guard let id = smartCube.connectionDeviceID else { return nil }
        guard let device = savedCubes.device(id) else { return smartCube.identity?.resolvedModel }
        return SmartCubeDeviceNamePresentation.showsModel(
            originalName: device.originalName, customName: device.customName, model: device.modelName
        ) ? device.modelName : nil
    }

    private func compactRow(
        _ title: LocalizedStringKey,
        name: String?,
        model: String? = nil,
        battery: Int?,
        status: LocalizedStringKey,
        isConnected: Bool,
        showsConnectedStatus: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if isConnected {
                    if let name, !name.isEmpty {
                        Text(name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    } else {
                        Text(title)
                            .font(.subheadline.weight(.medium))
                    }
                } else {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !isConnected || showsConnectedStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let model {
                    Text(model)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let battery { DeviceBatteryIndicator(percentage: battery) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func statusRow(
        _ title: LocalizedStringKey,
        identity: String?,
        model: String? = nil,
        battery: Int?,
        status: LocalizedStringKey,
        cubeSize: Int? = nil
    ) -> some View {
        HStack(spacing: 12) {
            cubeIcon(size: cubeSize)
            VStack(alignment: .leading, spacing: 3) {
                if let identity, !identity.isEmpty {
                    Text(identity).font(.body)
                } else {
                    Text(title).font(.body)
                }
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let model {
                    Text(model)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let battery { DeviceBatteryIndicator(percentage: battery) }
        }
    }

    @ViewBuilder
    private func cubeIcon(size: Int?) -> some View {
        if let size, let glyph = CompetitionEventIconFont.glyph(for: size == 2 ? "222" : "333") {
            CompetitionEventGlyph(
                glyph: glyph, eventName: size == 2 ? "2x2" : "3x3", size: 19,
                color: smartCube.connectionDeviceID.flatMap { savedCubes.device($0)?.iconColor?.color } ?? .accentColor
            )
        }
    }
}

struct ConnectedDevicesView: View {
    @ObservedObject private var smartCube = SmartCubeBluetoothManager.shared
    @ObservedObject private var smartTimer = GANTimerBluetoothManager.shared
    @ObservedObject private var savedCubes = SavedSmartCubeDevices.shared

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SmartCubeLabView()
                } label: {
                    deviceLabel(
                        "smart_cube.title",
                        name: smartCube.isConnected ? connectedCubeName : nil,
                        status: smartCubeConnectionStatusKey(smartCube.connectionState),
                        battery: smartCube.isConnected ? smartCube.batteryLevel : nil,
                        cubeSize: smartCube.isConnected ? smartCube.puzzleSize : nil,
                        model: smartCube.connectionDeviceID.flatMap { savedCubes.device($0)?.modelName },
                        cubeColor: smartCube.connectionDeviceID.flatMap { savedCubes.device($0)?.iconColor?.color } ?? .accentColor
                    )
                }
                NavigationLink {
                    SmartTimerDeviceView()
                } label: {
                    deviceLabel(
                        "connected_devices.smart_timer",
                        name: smartTimer.isConnected ? smartTimer.deviceName : nil,
                        status: LocalizedStringKey(smartTimer.statusLocalizedKey),
                        battery: smartTimer.isConnected ? smartTimer.batteryLevel : nil
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("connected_devices.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var connectedCubeName: String? {
        guard let id = smartCube.connectionDeviceID else { return nil }
        return savedCubes.device(id)?.displayName ?? smartCube.connectedDeviceName
    }

    private func deviceLabel(
        _ title: LocalizedStringKey,
        name: String?,
        status: LocalizedStringKey,
        battery: Int?,
        cubeSize: Int? = nil,
        model: String? = nil,
        cubeColor: Color = .accentColor
    ) -> some View {
        HStack(spacing: 12) {
            if let cubeSize, let glyph = CompetitionEventIconFont.glyph(for: cubeSize == 2 ? "222" : "333") {
                CompetitionEventGlyph(glyph: glyph, eventName: cubeSize == 2 ? "2x2" : "3x3", size: 20, color: cubeColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                if let name, !name.isEmpty {
                    Text(name).font(.body)
                    if let model {
                        Text(model)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(title).font(.body)
                }
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let battery { DeviceBatteryIndicator(percentage: battery) }
        }
    }
}

private func smartCubeConnectionStatusKey(_ state: SmartCubeConnectionState) -> LocalizedStringKey {
    switch state {
    case .disconnected: "smart_cube.status.disconnected"
    case .bluetoothUnavailable: "smart_cube.status.bluetooth_unavailable"
    case .unauthorized: "smart_cube.status.unauthorized"
    case .scanning: "smart_cube.status.scanning"
    case .connecting: "smart_cube.status.connecting"
    case .connected: "smart_cube.status.connected"
    case .failed: "smart_cube.status.failed"
    }
}

struct SmartCubeDeviceLabel: View {
    let device: SavedSmartCubeDevice
    let isConnected: Bool
    var isConnecting = false
    let battery: Int?

    var body: some View {
        HStack(spacing: 12) {
            if let glyph = CompetitionEventIconFont.glyph(for: device.puzzleSize == 2 ? "222" : "333") {
                CompetitionEventGlyph(
                    glyph: glyph,
                    eventName: device.puzzleSize == 2 ? "2x2" : "3x3",
                    size: 22,
                    color: device.iconColor?.color ?? .accentColor
                )
                .frame(width: 32)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(device.modelName)
                    Text("·")
                    Text(LocalizedStringKey(
                        isConnected ? "smart_cube.status.connected"
                            : isConnecting ? "smart_cube.status.connecting" : "smart_cube.status.disconnected"
                    ))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            if isConnected, let battery {
                DeviceBatteryIndicator(percentage: battery)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SmartCubeDeviceDetailView: View {
    let deviceID: UUID
    @ObservedObject private var manager = SmartCubeBluetoothManager.shared
    @ObservedObject private var savedDevices = SavedSmartCubeDevices.shared
    @State private var showingRename = false
    @State private var proposedName = ""
    @State private var showingMarkSolved = false

    private var device: SavedSmartCubeDevice? { savedDevices.device(deviceID) }
    private var session: SmartCubePeripheralSession? { manager.session(for: deviceID) }
    private var isConnected: Bool { session?.isConnected == true }

    var body: some View {
        List {
            if let device {
                Section {
                    SmartCubeDeviceLabel(
                        device: device,
                        isConnected: isConnected,
                        isConnecting: session?.connectionState == .connecting,
                        battery: isConnected ? session?.batteryLevel : nil
                    )
                    detailRow("smart_cube.device.model", value: device.modelName)
                    if device.customName != nil {
                        detailRow("smart_cube.device.original_name", value: device.originalName)
                    }
                    ColorPicker("smart_cube.device.icon_color", selection: Binding(
                        get: { savedDevices.device(deviceID)?.iconColor?.color ?? .accentColor },
                        set: { savedDevices.setIconColor(StoredColorData(color: $0), for: deviceID) }
                    ), supportsOpacity: false)
                    if device.iconColor != nil {
                        Button("smart_cube.device.reset_icon_color") {
                            savedDevices.setIconColor(nil, for: deviceID)
                        }
                    }
                    Button("smart_cube.device.rename") {
                        proposedName = device.customName ?? ""
                        showingRename = true
                    }
                    if device.customName != nil {
                        Button("smart_cube.device.reset_name") {
                            savedDevices.rename(deviceID, to: nil)
                        }
                    }
                }

                Section {
                    Toggle("smart_cube.device.auto_connect", isOn: Binding(
                        get: { savedDevices.device(deviceID)?.autoConnect ?? false },
                        set: {
                            savedDevices.setAutoConnect($0, for: deviceID)
                            manager.autoConnectPreferenceDidChange(for: deviceID, enabled: $0)
                        }
                    ))
                    if isConnected {
                        Button("smart_cube.disconnect", role: .destructive) { manager.disconnect(deviceID: deviceID) }
                    } else if manager.discoveredDevices.contains(where: { $0.id == deviceID }) {
                        Button("smart_cube.device.connect") {
                            _ = manager.connectSavedDevice(deviceID)
                        }
                    } else {
                        Button("smart_cube.scan") {
                            manager.startScanning()
                        }
                        .disabled(manager.isScanningForDevices)
                    }
                }

                if isConnected {
                    Section {
                        Button("smart_cube.reset_action") { showingMarkSolved = true }
                            .disabled(session?.hasTrustedCanonicalState != true || (session?.weiPo2PendingSnapshotCount ?? 0) > 0)
                    } footer: {
                        Text("smart_cube.device.mark_solved_help")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(device?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .alert("smart_cube.device.rename", isPresented: $showingRename) {
            TextField("smart_cube.device.name", text: $proposedName)
            Button("common.cancel", role: .cancel) {}
            Button("common.done") { savedDevices.rename(deviceID, to: proposedName) }
        }
        .confirmationDialog("smart_cube.reset_action", isPresented: $showingMarkSolved) {
            Button("smart_cube.reset_action") { manager.resetCubeStateToSolved(deviceID: deviceID) }
        } message: {
            Text("smart_cube.reset_footer")
        }
        .onAppear { manager.prepareIfNeeded() }
    }

    private func detailRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}


struct SmartCubeActiveDeviceMenu: View {
    @ObservedObject private var manager = SmartCubeBluetoothManager.shared
    @ObservedObject private var savedDevices = SavedSmartCubeDevices.shared

    var body: some View {
        Menu {
            Picker("smart_cube.device.active", selection: Binding<UUID?>(
                get: { manager.activeDeviceID },
                set: { if let id = $0 { manager.selectActiveDevice(id) } }
            )) {
                if manager.activeDeviceID == nil {
                    Text("smart_cube.device.no_active").tag(Optional<UUID>.none).disabled(true)
                }
                ForEach(manager.compatibleConnectedDeviceIDs, id: \.self) { id in
                    if let device = savedDevices.device(id) {
                        Label {
                            Text(device.displayName)
                        } icon: {
                            if let icon = CompetitionEventIconFont.templateImage(for: device.puzzleSize == 2 ? "222" : "333", pointSize: 20) {
                                Image(uiImage: icon.withTintColor(
                                    UIColor(device.iconColor?.color ?? .accentColor), renderingMode: .alwaysOriginal
                                ))
                            }
                        }
                        .tag(Optional(id))
                    }
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "chevron.up.chevron.down")
                .font(.subheadline)
                .padding(8)
        }
        .accessibilityLabel(Text("smart_cube.device.active"))
    }
}

struct SmartTimerDeviceView: View {
    @ObservedObject private var ganTimer = GANTimerBluetoothManager.shared
    @AppStorage("appLanguage") private var appLanguage = "en"
    @State private var showingGANDevicePicker = false

    var body: some View {
        List {
            Section {
                ganTimerConnectionRow
                ganTimerActionRow
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("connected_devices.smart_timer")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingGANDevicePicker) {
            ganDevicePickerSheet
        }
        .onAppear { ganTimer.prepareIfNeeded() }
    }

    private var ganTimerConnectionRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if ganTimer.isConnected, let name = ganTimer.deviceName, !name.isEmpty {
                    Text(name).font(.headline)
                } else {
                    Text("settings.gan_timer").font(.headline)
                }
                Text(LocalizedStringKey(ganTimer.statusLocalizedKey))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if ganTimer.isConnected, let battery = ganTimer.batteryLevel {
                DeviceBatteryIndicator(percentage: battery)
            }
        }
    }

    private var ganTimerActionRow: some View {
        Button {
                switch ganTimer.connectionState {
                case .scanning, .connecting, .connected, .handsOn, .ready, .running, .finished:
                    ganTimer.performPrimaryAction()
                default:
                    ganTimer.startDeviceDiscovery()
                    showingGANDevicePicker = true
                }
        } label: {
            HStack(spacing: 6) {
                if case .scanning = ganTimer.connectionState {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(LocalizedStringKey(ganTimer.actionLocalizedKey))
            }
        }
    }

    var ganDevicePickerSheet: some View {
        CompatibleNavigationContainer {
            List {
                if ganTimer.discoveredDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.gan_no_devices")
                            .font(.system(size: 16, weight: .semibold))

                        Text("settings.gan_scanning_help")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(ganTimer.discoveredDevices) { device in
                        Button {
                            ganTimer.connect(to: device.id)
                            showingGANDevicePicker = false
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(Text(appLocalizedString("settings.gan_choose_device", languageCode: appLanguage)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel") {
                        ganTimer.stopScanning()
                        showingGANDevicePicker = false
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(appLocalizedString("common.refresh", languageCode: appLanguage, defaultValue: "Refresh")) {
                        ganTimer.startDeviceDiscovery()
                    }
                }
            }
            .onAppear {
                ganTimer.startDeviceDiscovery()
            }
        }
        .compatibleMediumLargeSheet()
    }

}
#endif

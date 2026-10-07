#if os(iOS)
import SwiftUI
import UIKit

struct SmartCubeLabView: View {
    @StateObject private var manager = SmartCubeBluetoothManager.shared
    @ObservedObject private var savedDevices = SavedSmartCubeDevices.shared
    @AppStorage("smartCubeFixedView") private var fixedViewRawValue = SmartCubeFixedView.urf.rawValue
    @AppStorage("smartCubeAnimationTPS") private var animationTPS = 10
    @AppStorage("smartCubeAppearance") private var appearanceRawValue = VirtualCubeAppearance.classic.rawValue
    @AppStorage("smartCubeInternalPlastic") private var plasticRawValue = VirtualCubePlastic.black.rawValue
    @AppStorage("smartCubeReflections") private var reflections = false
    @AppStorage("smartCubePlasticColorData") private var plasticColorData: Data?
    @AppStorage("smartCubeResetPolicy") private var resetPolicyRawValue = SmartCubeResetPolicy.prompt.rawValue
    @AppStorage("smartCubeReadySound") private var readySound = true
    @AppStorage("smartCubeDebugMode") private var debugMode = false
    @AppStorage("smartCubeShowVirtualCube") private var showVirtualCube = true
    @AppStorage("smartCubeTimerPosition") private var timerPositionRawValue = SmartCubeTimerPosition.right.rawValue
    @AppStorage("smartCubeTimerLayout") private var timerLayoutRawValue = SmartCubeTimerLayout.centered.rawValue
    @AppStorage("smartCubeCurrentMovePresentation") private var currentMovePresentationRawValue = SmartCubeCurrentMovePresentation.highlight.rawValue
    @AppStorage("smartCubeHighlightColorMode") private var highlightColorModeRawValue = SmartCubeHighlightColorMode.automatic.rawValue
    @AppStorage("smartCubeHighlightTextMode") private var highlightTextModeRawValue = SmartCubeHighlightColorMode.automatic.rawValue
    @AppStorage("smartCubeHighlightColorData") private var highlightColorData: Data?
    @AppStorage("smartCubeHighlightTextColorData") private var highlightTextColorData: Data?
    @AppStorage("smartCubeCompletedMovesBehavior") private var completedMovesBehaviorRawValue = SmartCubeCompletedMovesBehavior.collapse.rawValue
    @AppStorage("smartCubeScrambleTransition") private var scrambleTransitionRawValue = SmartCubeScrambleTransition.instant.rawValue
    @AppStorage("smartCubeRecoveryDisplay") private var recoveryDisplayRawValue = SmartCubeRecoveryDisplay.inline.rawValue
    @AppStorage("smartCubeHighlightAnimation") private var highlightAnimationRawValue = SmartCubeHighlightAnimation.instant.rawValue
    @State private var showingResetPrompt = false
    @State private var policyAttemptID: UUID?

    private var fixedView: SmartCubeFixedView {
        SmartCubeFixedView(rawValue: fixedViewRawValue) ?? .urf
    }

    private var usesWeiPo2NativeVisual: Bool {
        manager.connectedProtocol == .moyu && manager.puzzleSize == 2
    }

    private var showsDiscoveryDiagnostics: Bool {
        #if DEBUG
        debugMode
        #else
        false
        #endif
    }

    private var resetPolicy: SmartCubeResetPolicy {
        SmartCubeResetPolicy(rawValue: resetPolicyRawValue) ?? .prompt
    }

    private var completedMovesBehavior: SmartCubeCompletedMovesBehavior {
        SmartCubeCompletedMovesBehavior(rawValue: completedMovesBehaviorRawValue) ?? .collapse
    }

    private var currentMovePresentation: SmartCubeCurrentMovePresentation {
        SmartCubeCurrentMovePresentation(rawValue: currentMovePresentationRawValue) ?? .highlight
    }

    private var highlightColorMode: SmartCubeHighlightColorMode {
        SmartCubeHighlightColorMode(rawValue: highlightColorModeRawValue) ?? .automatic
    }

    private var highlightTextMode: SmartCubeHighlightColorMode {
        SmartCubeHighlightColorMode(rawValue: highlightTextModeRawValue) ?? .automatic
    }

    private var customHighlightColor: Binding<Color> {
        Binding(
            get: {
                StoredColorData.decode(
                    from: highlightColorData,
                    fallback: SmartCubeHighlightColorDefaults.background
                ).color
            },
            set: { highlightColorData = StoredColorData(color: $0).encodedData }
        )
    }

    private var customPlasticColor: Binding<Color> {
        Binding(
            get: { StoredColorData.decode(from: plasticColorData, fallback: StoredColorData(r: 0.5, g: 0, b: 0.5)).color },
            set: { plasticColorData = StoredColorData(color: $0).encodedData }
        )
    }

    private var customHighlightTextColor: Binding<Color> {
        Binding(
            get: {
                StoredColorData.decode(
                    from: highlightTextColorData,
                    fallback: SmartCubeHighlightColorDefaults.text
                ).color
            },
            set: { highlightTextColorData = StoredColorData(color: $0).encodedData }
        )
    }

    private var transitionSelection: Binding<String> {
        Binding(
            get: {
                SmartCubeScrambleTransition.resolved(
                    storedRawValue: scrambleTransitionRawValue,
                    behavior: completedMovesBehavior
                ).rawValue
            },
            set: { scrambleTransitionRawValue = $0 }
        )
    }

    var body: some View {
        List {
            statusSection
            discoveredDevicesSection
            cube3DSection
            displaySettingsSection
            scrambleProgressSettingsSection
            settingsSection
            #if DEBUG
            if debugMode {
                liveStateSection
                faceletsSection
                servicesSection
                protocolLogSection
                logSection
            }
            #endif
        }
        .listStyle(.insetGrouped)
        .navigationTitle("smart_cube.title")
        .navigationBarTitleDisplayMode(.large)
        #if DEBUG
        .modifier(SmartCubeDebugToolbar(enabled: debugMode) { manager.clearLog() })
        #endif
        .onAppear {
            recoveryDisplayRawValue = SmartCubeRecoveryDisplay.resolved(recoveryDisplayRawValue).rawValue
            manager.prepareIfNeeded()
        }
        .onChange(of: manager.pendingPolicyAttemptID) { pending in
            guard let attemptID = pending else { return }
            policyAttemptID = attemptID
            #if DEBUG
            SmartCubeDiagnostics.shared.trace("policy.pending", attemptID: attemptID, deviceID: manager.connectionDeviceID, detail: "source=settings policy=\(resetPolicy.rawValue)")
            #endif
            switch resetPolicy.connectionAction {
            case .reset:
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("policy.decision", attemptID: attemptID, deviceID: manager.connectionDeviceID, detail: "source=settings action=reset")
                #endif
                manager.resetCubeStateToSolved(attemptID: attemptID)
                manager.resolveConnectionPolicy(for: attemptID)
            case .prompt:
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("policy.prompt.presented", attemptID: attemptID, deviceID: manager.connectionDeviceID, detail: "source=settings")
                #endif
                showingResetPrompt = true
            case .continueWithoutReset:
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("policy.decision", attemptID: attemptID, deviceID: manager.connectionDeviceID, detail: "source=settings action=continue")
                #endif
                manager.resolveConnectionPolicy(for: attemptID)
            }
        }
        .smartCubeResetConfirmation(
            isPresented: $showingResetPrompt,
            onReset: {
                guard let attemptID = policyAttemptID else { return }
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("policy.decision", attemptID: attemptID, deviceID: manager.connectionDeviceID, detail: "source=settings prompt=mark-as-solved")
                #endif
                manager.resetCubeStateToSolved(attemptID: attemptID)
                manager.resolveConnectionPolicy(for: attemptID)
            },
            onContinue: {
                guard let attemptID = policyAttemptID else { return }
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("policy.decision", attemptID: attemptID, deviceID: manager.connectionDeviceID, detail: "source=settings prompt=continue")
                #endif
                manager.resolveConnectionPolicy(for: attemptID)
            }
        )
    }

    private var statusSection: some View {
        Section("smart_cube.my_devices") {
            if manager.compatibleConnectedDeviceIDs.count > 1 {
                HStack { Text("smart_cube.device.active"); Spacer(); SmartCubeActiveDeviceMenu() }
            }
            if savedDevices.devices.isEmpty {
                Text("smart_cube.no_saved_devices")
                    .foregroundStyle(.secondary)
            }
            ForEach(savedDevices.devices) { device in
                NavigationLink {
                    SmartCubeDeviceDetailView(deviceID: device.id)
                } label: {
                    SmartCubeDeviceLabel(
                        device: device,
                        isConnected: manager.session(for: device.id)?.isConnected == true,
                        isConnecting: manager.session(for: device.id)?.connectionState == .connecting,
                        battery: manager.session(for: device.id)?.batteryLevel
                    )
                }
            }

            #if DEBUG
            if manager.isConnected, debugMode {
                HStack(spacing: 10) {
                    Button("Request Facelets") { manager.requestFacelets() }
                    Button("Battery") { manager.requestBattery() }
                    Button("Hardware") { manager.requestHardware() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Protocol Debug", isOn: $manager.protocolDebugLogging)
                    Toggle("Coalesce Slice Moves", isOn: $manager.coalesceSliceMoves)
                    Toggle("Verbose Packets", isOn: $manager.verbosePacketLogging)
                    HStack(spacing: 10) {
                        Button(manager.isPacketCaptureFinishing ? "Finishing Capture..." : (manager.isPacketCaptureActive ? "Stop Capture" : "Start Capture")) {
                            if manager.isPacketCaptureActive {
                                manager.finishPacketCapture()
                            } else {
                                manager.startPacketCapture()
                            }
                        }
                        .disabled(manager.isPacketCaptureFinishing)
                        Button("Copy Capture") {
                            UIPasteboard.general.string = manager.packetCaptureText
                        }
                        .disabled(manager.isPacketCaptureActive)
                    }
                }
                .font(.footnote)
            }
            #endif
        }
    }

    @ViewBuilder
    private var discoveredDevicesSection: some View {
        Section {
            if manager.discoveredDevices.filter({ savedDevices.device($0.id) == nil }).isEmpty {
                Text("smart_cube.no_devices")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(manager.discoveredDevices.filter { savedDevices.device($0.id) == nil }) { device in
                    Button {
                        let attemptID = manager.connect(to: device.id)
                        #if DEBUG
                        if let attemptID {
                            SmartCubeDiagnostics.shared.trace("attempt.source", attemptID: attemptID, deviceID: device.id, detail: "source=settings")
                        }
                        #endif
                    } label: {
                        SmartCubeDiscoveredDeviceRow(
                            device: device,
                            showsDiagnostics: showsDiscoveryDiagnostics
                        )
                    }
                }
            }
        } header: {
            HStack {
                Text("smart_cube.nearby_devices")
                Spacer()
                Button(manager.isScanningForDevices ? "smart_cube.stop_scanning" : "smart_cube.scan") {
                    if manager.isScanningForDevices {
                        manager.stopScanning()
                    } else {
                        manager.startScanning()
                    }
                }
                .font(.subheadline)
            }
        }
    }

    private var connectionStateKey: LocalizedStringKey {
        switch manager.connectionState {
        case .disconnected: "smart_cube.status.disconnected"
        case .bluetoothUnavailable: "smart_cube.status.bluetooth_unavailable"
        case .unauthorized: "smart_cube.status.unauthorized"
        case .scanning: "smart_cube.status.scanning"
        case .connecting: "smart_cube.status.connecting"
        case .connected: "smart_cube.status.connected"
        case .failed: "smart_cube.status.failed"
        }
    }

    private var liveStateSection: some View {
        Section("smart_cube.live_state") {
            if let battery = manager.batteryLevel {
                HStack {
                    Text("smart_cube.battery")
                    Spacer()
                    DeviceBatteryIndicator(percentage: battery)
                }
            }
            labeledValue("smart_cube.latest_move", manager.latestMove?.move ?? "—")
            labeledValue("smart_cube.move_count", "\(manager.moveHistory.count)")

            if debugMode {
                labeledValue("Protocol", manager.connectedProtocol.rawValue)
                labeledValue("MAC", manager.connectedMACAddress ?? "Unknown")
                labeledValue("Hardware", manager.hardwareSummary ?? "Unknown")
                labeledValue("Gyro", manager.gyroState?.summary ?? "No gyro data")
                #if DEBUG
                labeledValue("Identity", manager.debugIdentityDump)
                #endif
            }

            if !manager.moveHistory.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(manager.moveHistory.suffix(32)) { move in
                            Text(move.move)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.blue.opacity(0.14)))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var cube3DSection: some View {
        Section {
            SmartCube3DView(
                facelets: usesWeiPo2NativeVisual ? manager.weiPo2VisualFacelets : manager.facelets,
                stateRevision: usesWeiPo2NativeVisual ? manager.weiPo2VisualRevision : manager.cubeStateRevision,
                fixedView: fixedView,
                cubeSize: manager.puzzleSize,
                events: manager.canonicalEvents,
                connectionAttemptID: manager.connectionAttemptID,
                isStateTrusted: manager.hasTrustedCanonicalState,
                diagnosticOwner: "lab"
            )
                .frame(height: 280)
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
        } header: {
            Text("smart_cube.virtual_cube")
        }
    }

    private var settingsSection: some View {
        Section("smart_cube.settings") {
            Picker("smart_cube.animation_speed", selection: $animationTPS) {
                ForEach(1...20, id: \.self) { speed in
                    Text("\(speed) TPS").tag(speed)
                }
                Text("smart_cube.animation_unlimited").tag(0)
            }
            Picker("smart_cube.appearance", selection: $appearanceRawValue) {
                ForEach(VirtualCubeAppearance.allCases) { appearance in
                    Text(LocalizedStringKey(appearance.localizedKey)).tag(appearance.rawValue)
                }
            }
            Picker("smart_cube.plastic", selection: $plasticRawValue) {
                ForEach(VirtualCubePlastic.allCases) { plastic in
                    Text(LocalizedStringKey(plastic.localizedKey)).tag(plastic.rawValue)
                }
            }
            if plasticRawValue == VirtualCubePlastic.custom.rawValue {
                ColorPicker("smart_cube.plastic.custom_color", selection: customPlasticColor, supportsOpacity: false)
            }
            Toggle("smart_cube.reflections", isOn: $reflections)

            Picker("settings.smart_cube.fixed_view", selection: $fixedViewRawValue) {
                ForEach(SmartCubeFixedView.allCases) { view in
                    Text(view.localizedKey).tag(view.rawValue)
                }
            }

            Picker("settings.smart_cube.reset_on_connect", selection: $resetPolicyRawValue) {
                ForEach(SmartCubeResetPolicy.allCases) { policy in
                    Text(policy.localizedKey).tag(policy.rawValue)
                }
            }

            Toggle("settings.smart_cube.ready_sound", isOn: $readySound)
            #if DEBUG
            Toggle("settings.smart_cube.debug_mode", isOn: $debugMode)
            #endif
        }
    }

    private var displaySettingsSection: some View {
        Section("settings.smart_cube.display") {
            Toggle("settings.smart_cube.show_virtual_cube", isOn: $showVirtualCube)

            if showVirtualCube {
                Picker("settings.smart_cube.timer_layout", selection: $timerLayoutRawValue) {
                    ForEach(SmartCubeTimerLayout.allCases) { layout in
                        Text(layout.localizedKey).tag(layout.rawValue)
                    }
                }
                Picker("settings.smart_cube.timer_position", selection: $timerPositionRawValue) {
                    ForEach(SmartCubeTimerPosition.allCases) { position in
                        Text(position.localizedKey).tag(position.rawValue)
                    }
                }
            }
        }
    }

    private var scrambleProgressSettingsSection: some View {
        Section("settings.smart_cube.scramble_progress") {
            Picker("settings.smart_cube.current_move", selection: $currentMovePresentationRawValue) {
                ForEach(SmartCubeCurrentMovePresentation.allCases) { presentation in
                    Text(presentation.localizedKey).tag(presentation.rawValue)
                }
            }

            if currentMovePresentation == .highlight {
                Picker("settings.smart_cube.highlight_animation", selection: $highlightAnimationRawValue) {
                    ForEach(SmartCubeHighlightAnimation.allCases) { animation in
                        Text(animation.localizedKey).tag(animation.rawValue)
                    }
                }

                Picker("settings.smart_cube.highlight_color", selection: $highlightColorModeRawValue) {
                    ForEach(SmartCubeHighlightColorMode.allCases) { mode in
                        Text(mode.localizedKey).tag(mode.rawValue)
                    }
                }

                if highlightColorMode == .custom {
                    ColorPicker(
                        "settings.smart_cube.highlight_color.custom",
                        selection: customHighlightColor,
                        supportsOpacity: false
                    )
                }

                Picker("settings.smart_cube.highlight_text", selection: $highlightTextModeRawValue) {
                    ForEach(SmartCubeHighlightColorMode.allCases) { mode in
                        Text(mode.localizedKey).tag(mode.rawValue)
                    }
                }

                if highlightTextMode == .custom {
                    ColorPicker(
                        "settings.smart_cube.highlight_text.custom",
                        selection: customHighlightTextColor,
                        supportsOpacity: false
                    )
                }
            }

            Picker("settings.smart_cube.completed_moves", selection: $completedMovesBehaviorRawValue) {
                ForEach(SmartCubeCompletedMovesBehavior.allCases) { behavior in
                    Text(behavior.localizedKey).tag(behavior.rawValue)
                }
            }

            Picker("settings.smart_cube.recovery_display", selection: $recoveryDisplayRawValue) {
                ForEach(SmartCubeRecoveryDisplay.allCases) { display in
                    Text(display.localizedKey).tag(display.rawValue)
                }
            }

            Picker("settings.smart_cube.transition", selection: transitionSelection) {
                ForEach(SmartCubeScrambleTransition.allowed(for: completedMovesBehavior)) { transition in
                    Text(transition.localizedKey).tag(transition.rawValue)
                }
            }
        }
    }

    @ViewBuilder
    private var faceletsSection: some View {
        Section {
            if let facelets = manager.facelets {
                CubeFaceletsNet(facelets: facelets)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)

                Text(facelets)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                Text("No facelets yet. Tap Reset State after putting the physical cube in solved state, or request a valid cube snapshot.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Facelets")
        } footer: {
            Text("This is CubeFlow's local sticker state. After Reset State, incoming moves update this 2D net; gyro-driven 3D rendering is a later step.")
        }
    }

    private var servicesSection: some View {
        Section("BLE") {
            labeledValue("Services", manager.discoveredServiceUUIDs.isEmpty ? "None" : manager.discoveredServiceUUIDs.joined(separator: "\n"))
            labeledValue("Characteristics", manager.discoveredCharacteristicUUIDs.isEmpty ? "None" : manager.discoveredCharacteristicUUIDs.joined(separator: "\n"))
        }
    }

    private var protocolLogSection: some View {
        Section {
            if manager.protocolLogEntries.isEmpty {
                Text("No protocol events yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(manager.protocolLogEntries.prefix(80)) { entry in
                    logRow(entry)
                }
            }
        } header: {
            Text("Protocol Log")
        } footer: {
            Text("Filtered diagnostics for move counters, GAN history packets, emitted moves, and slice detection. This stays readable even when verbose raw packets are noisy.")
        }
    }

    private var logSection: some View {
        Section("Log") {
            if manager.logEntries.isEmpty {
                Text("No log entries")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(manager.logEntries.prefix(80)) { entry in
                    logRow(entry)
                }
            }
        }
    }

    private func logRow(_ entry: SmartCubeLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(entry.date, style: .time)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(entry.detail)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func labeledValue(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

private struct CubeFaceletsNet: View {
    let facelets: String

    private var chars: [Character] { Array(facelets) }

    var body: some View {
        VStack(spacing: 4) {
            faceView(faceIndex: 0)
                .padding(.leading, 76)
            HStack(spacing: 4) {
                faceView(faceIndex: 4)
                faceView(faceIndex: 2)
                faceView(faceIndex: 1)
                faceView(faceIndex: 5)
            }
            faceView(faceIndex: 3)
                .padding(.leading, 76)
        }
    }

    private func faceView(faceIndex: Int) -> some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { column in
                        let index = faceIndex * 9 + row * 3 + column
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color(for: index < chars.count ? chars[index] : "U"))
                            .frame(width: 20, height: 20)
                            .overlay {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .stroke(Color.black.opacity(0.18), lineWidth: 0.5)
                            }
                    }
                }
            }
        }
    }

    private func color(for facelet: Character) -> Color {
        switch facelet {
        case "U": return Color(red: 1, green: 1, blue: 1)
        case "R": return Color(red: 1, green: 0, blue: 0)
        case "F": return Color(red: 0, green: 0.87, blue: 0)
        case "D": return Color(red: 1, green: 1, blue: 0)
        case "L": return Color(red: 1, green: 0.67, blue: 0)
        case "B": return Color(red: 0, green: 0, blue: 1)
        default: return Color(white: 0.5)
        }
    }
}

struct SmartCubeDevicePickerView: View {
    @ObservedObject var manager: SmartCubeBluetoothManager
    let onConnectionStarted: ((UUID) -> Void)?
    let onConnectionApproved: ((UUID) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("smartCubeResetPolicy") private var resetPolicyRawValue = SmartCubeResetPolicy.prompt.rawValue
    @State private var selectedAttemptID: UUID?
    @State private var showingResetPrompt = false
    private var selectedSession: SmartCubePeripheralSession? {
        selectedAttemptID.flatMap { manager.session(attemptID: $0) }
    }

    init(
        manager: SmartCubeBluetoothManager,
        onConnectionStarted: ((UUID) -> Void)? = nil,
        onConnectionApproved: ((UUID) -> Void)? = nil
    ) {
        self.manager = manager
        self.onConnectionStarted = onConnectionStarted
        self.onConnectionApproved = onConnectionApproved
    }

    private var resetPolicy: SmartCubeResetPolicy {
        SmartCubeResetPolicy(rawValue: resetPolicyRawValue) ?? .prompt
    }

    var body: some View {
        CompatibleNavigationContainer {
            List {
                Section {
                    if manager.discoveredDevices.isEmpty {
                        Text("smart_cube.no_devices")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(manager.discoveredDevices) { device in
                            Button {
                                guard let attemptID = manager.connect(to: device.id) else { return }
                                selectedAttemptID = attemptID
                                #if DEBUG
                                SmartCubeDiagnostics.shared.trace(
                                    "attempt.source",
                                    attemptID: attemptID,
                                    deviceID: device.id,
                                    detail: "source=\(onConnectionStarted == nil ? "settings-picker" : "timer")"
                                )
                                #endif
                                onConnectionStarted?(attemptID)
                            } label: {
                                SmartCubeDiscoveredDeviceRow(
                                    device: device,
                                    showsDiagnostics: false
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("smart_cube.devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel") {
                        if let session = selectedSession, !session.isReadyForMoveObservation,
                           let id = session.connectionDeviceID {
                            manager.disconnect(deviceID: id)
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(manager.isScanningForDevices
                           ? "smart_cube.stop_scanning"
                           : "smart_cube.scan") {
                        if manager.isScanningForDevices {
                            manager.stopScanning()
                        } else {
                            manager.startScanning()
                        }
                    }
                }
            }
        }
        .onAppear {
            manager.prepareIfNeeded()
            if !manager.isConnected, manager.connectionState != .scanning {
                manager.startScanning()
            }
        }
        .onChange(of: selectedSession?.connectionState) { state in
            guard state == .connected, let selectedAttemptID, let session = selectedSession else { return }
            if session.connectionPolicyResolvedAttemptID == selectedAttemptID {
                onConnectionApproved?(selectedAttemptID)
                dismiss()
                return
            }
            #if DEBUG
            let source = onConnectionStarted == nil ? "settings-picker" : "timer"
            SmartCubeDiagnostics.shared.trace("policy.pending", attemptID: selectedAttemptID, deviceID: manager.connectionDeviceID, detail: "source=\(source) policy=\(resetPolicy.rawValue)")
            #endif
            switch resetPolicy.connectionAction {
            case .reset:
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("policy.decision", attemptID: selectedAttemptID, deviceID: manager.connectionDeviceID, detail: "source=\(source) action=reset")
                #endif
                manager.resetCubeStateToSolved(attemptID: selectedAttemptID)
                manager.resolveConnectionPolicy(for: selectedAttemptID)
                onConnectionApproved?(selectedAttemptID)
                dismiss()
            case .prompt:
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("policy.prompt.presented", attemptID: selectedAttemptID, deviceID: manager.connectionDeviceID, detail: "source=\(source)")
                #endif
                showingResetPrompt = true
            case .continueWithoutReset:
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("policy.decision", attemptID: selectedAttemptID, deviceID: manager.connectionDeviceID, detail: "source=\(source) action=continue")
                #endif
                manager.resolveConnectionPolicy(for: selectedAttemptID)
                onConnectionApproved?(selectedAttemptID)
                dismiss()
            }
        }
        .smartCubeResetConfirmation(
            isPresented: $showingResetPrompt,
            onReset: {
                guard let selectedAttemptID,
                      selectedAttemptID == selectedSession?.connectionAttemptID else { return }
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("policy.decision", attemptID: selectedAttemptID, deviceID: manager.connectionDeviceID, detail: "source=\(onConnectionStarted == nil ? "settings-picker" : "timer") prompt=mark-as-solved")
                #endif
                manager.resetCubeStateToSolved(attemptID: selectedAttemptID)
                manager.resolveConnectionPolicy(for: selectedAttemptID)
                onConnectionApproved?(selectedAttemptID)
                dismiss()
            },
            onContinue: {
                guard let selectedAttemptID,
                      selectedAttemptID == selectedSession?.connectionAttemptID else { return }
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("policy.decision", attemptID: selectedAttemptID, deviceID: manager.connectionDeviceID, detail: "source=\(onConnectionStarted == nil ? "settings-picker" : "timer") prompt=continue")
                #endif
                manager.resolveConnectionPolicy(for: selectedAttemptID)
                onConnectionApproved?(selectedAttemptID)
                dismiss()
            }
        )
        .onDisappear {
            if manager.isScanningForDevices {
                manager.stopScanning()
            }
        }
    }
}

private struct SmartCubeResetConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onReset: () -> Void
    let onContinue: () -> Void

    func body(content: Content) -> some View {
        content.alert("smart_cube.reset_prompt_title", isPresented: $isPresented) {
            Button("smart_cube.reset_action", action: onReset)
            Button("common.cancel", role: .cancel, action: onContinue)
        } message: {
            Text("smart_cube.reset_prompt_message")
        }
    }
}

private extension View {
    func smartCubeResetConfirmation(
        isPresented: Binding<Bool>,
        onReset: @escaping () -> Void,
        onContinue: @escaping () -> Void = {}
    ) -> some View {
        modifier(SmartCubeResetConfirmationModifier(
            isPresented: isPresented,
            onReset: onReset,
            onContinue: onContinue
        ))
    }
}

#if DEBUG
private struct SmartCubeDebugToolbar: ViewModifier {
    let enabled: Bool
    let clear: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: clear) {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Clear log")
                }
            }
        } else {
            content
        }
    }
}
#endif

private struct SmartCubeDiscoveredDeviceRow: View {
    let device: SmartCubeDiscoveredDevice
    let showsDiagnostics: Bool

    private var detectedIdentity: SmartCubeIdentity {
        SmartCubeIdentity.resolve(
            advertisedName: device.name,
            protocolFamily: device.protocolHint,
            protocolConfirmed: false,
            protocolInfo: nil,
            serviceIdentifiers: device.advertisedServices
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            if let glyph = CompetitionEventIconFont.glyph(
                for: detectedIdentity.puzzleKind == .twoByTwo ? "222" : "333"
            ) {
                CompetitionEventGlyph(
                    glyph: glyph,
                    eventName: detectedIdentity.puzzleKind == .twoByTwo ? "2x2" : "3x3",
                    size: 22,
                    color: .accentColor
                )
                .frame(width: 32)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(detectedIdentity.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            #if DEBUG
            if showsDiagnostics {
                Text(device.protocolHint.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("RSSI \(device.rssi) dBm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let mac = device.macAddress {
                    Text(mac)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if !device.advertisedServices.isEmpty {
                    Text("ADV services: \(device.advertisedServices.joined(separator: ", "))")
                        .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                }
                if let manufacturerDataHex = device.manufacturerDataHex {
                    Text("Manufacturer: \(manufacturerDataHex)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            #endif
            }
        }
        .padding(.vertical, 3)
    }
}
#endif

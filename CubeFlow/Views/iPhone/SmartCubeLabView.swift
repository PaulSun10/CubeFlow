#if os(iOS)
import SwiftUI

struct SmartCubeLabView: View {
    @StateObject private var manager = SmartCubeBluetoothManager.shared

    var body: some View {
        List {
            statusSection
            discoveredDevicesSection
            liveStateSection
            cube3DSection
            faceletsSection
            servicesSection
            protocolLogSection
            logSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Smart Cube Lab")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    manager.clearLog()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Clear log")
            }
        }
        .onAppear {
            manager.prepareIfNeeded()
        }
    }

    private var statusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: manager.isConnected ? "cube.transparent.fill" : "cube.transparent")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(manager.isConnected ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(manager.connectedDeviceName ?? "No smart cube connected")
                            .font(.system(size: 16, weight: .semibold))
                        Text(manager.connectionState.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    if manager.connectionState == .scanning {
                        Button("Stop Scanning") { manager.stopScanning() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Scan") { manager.startScanning() }
                            .buttonStyle(.borderedProminent)
                    }

                    Button("Disconnect") { manager.disconnect() }
                        .buttonStyle(.bordered)
                        .disabled(!manager.isConnected)
                }

                if manager.isConnected {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Button("Facelets") { manager.requestFacelets() }
                            Button("Battery") { manager.requestBattery() }
                            Button("Hardware") { manager.requestHardware() }
                        }

                        Button {
                            manager.resetCubeStateToSolved()
                        } label: {
                            Label("Reset State", systemImage: "arrow.counterclockwise")
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Protocol Debug", isOn: $manager.protocolDebugLogging)
                            Toggle("Coalesce Slice Moves", isOn: $manager.coalesceSliceMoves)
                            Toggle("Verbose Packets", isOn: $manager.verbosePacketLogging)
                        }
                        .font(.system(size: 13, weight: .medium))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Reset State assumes the physical cube is already solved, then resets CubeFlow's local cube state and move history.")
        }
    }

    @ViewBuilder
    private var discoveredDevicesSection: some View {
        Section("Devices") {
            if manager.discoveredDevices.isEmpty {
                Text("No smart cubes found yet. Wake the cube, keep it nearby, then scan.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(manager.discoveredDevices) { device in
                    Button {
                        manager.connect(to: device.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(device.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(device.protocolHint.rawValue)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                Label("\(device.rssi) dBm", systemImage: "dot.radiowaves.left.and.right")
                                if let mac = device.macAddress {
                                    Label(mac, systemImage: "key.horizontal")
                                } else {
                                    Label("No MAC salt", systemImage: "exclamationmark.triangle")
                                }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                            if !device.advertisedServices.isEmpty {
                                Text("ADV services: \(device.advertisedServices.joined(separator: ", "))")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            if let manufacturerDataHex = device.manufacturerDataHex {
                                Text("Manufacturer: \(manufacturerDataHex)")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private var liveStateSection: some View {
        Section("Live State") {
            labeledValue("Protocol", manager.connectedProtocol.rawValue)
            labeledValue("MAC", manager.connectedMACAddress ?? "Unknown")
            labeledValue("Battery", manager.batteryLevel.map { "\($0)%" } ?? "Unknown")
            labeledValue("Hardware", manager.hardwareSummary ?? "Unknown")
            labeledValue("Latest Move", manager.latestMove?.move ?? "None")
            labeledValue("Move Count", "\(manager.moveHistory.count)")

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
                facelets: manager.facelets,
                latestMove: manager.latestMove,
                gyroState: manager.gyroState,
                stateRevision: manager.cubeStateRevision
            )
                .frame(height: 280)
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
        } header: {
            Text("3D Cube")
        } footer: {
            Text("The native 3D model follows incoming smart-cube moves. Drag the model to inspect the cube; Reset State rebuilds it from solved state.")
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

    private func labeledValue(_ title: String, _ value: String) -> some View {
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
        case "U": return .white
        case "R": return .red
        case "F": return .green
        case "D": return .yellow
        case "L": return .orange
        case "B": return .blue
        default: return .gray
        }
    }
}
#endif

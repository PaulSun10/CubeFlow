#if os(iOS)
import Foundation
import CoreBluetooth
import Combine
import UIKit

final class SmartCubePeripheralSession: NSObject, ObservableObject {
    private var connectionTimeout: DispatchWorkItem?
    var onConnectionTimeout: (() -> Void)?
    @Published private(set) var connectionState: SmartCubeConnectionState = .disconnected
    @Published private(set) var connectionAttemptID: UUID?
    @Published private(set) var connectionDeviceID: UUID?
    @Published private(set) var connectionPolicyResolvedAttemptID: UUID?
    private var discoveredDevices: [SmartCubeDiscoveredDevice] = []
    @Published private(set) var connectedDeviceName: String?
    @Published private(set) var connectedProtocol: SmartCubeProtocolKind = .unknown
    @Published private(set) var identity: SmartCubeIdentity?
    @Published private(set) var connectedMACAddress: String?
    @Published private(set) var discoveredServiceUUIDs: [String] = []
    @Published private(set) var discoveredCharacteristicUUIDs: [String] = []
    @Published private(set) var latestMove: SmartCubeMoveEvent?
    @Published private(set) var moveHistory: [SmartCubeMoveEvent] = []
    private let canonicalFeed = SmartCubeCanonicalFeed()
    var canonicalEvents: AnyPublisher<SmartCubeCanonicalEvent, Never> {
        canonicalFeed.events
    }
    var canonicalHistory: [SmartCubeCanonicalEvent] { canonicalFeed.eventHistory }
    var canonicalSequence: UInt64 { canonicalFeed.sequence }
    var hasTrustedCanonicalState: Bool { canonicalFeed.isStateTrusted }
    var puzzleSize: Int {
        identity?.puzzleKind.size ?? (facelets?.count == 24 ? 2 : 3)
    }
    @Published private(set) var facelets: String?
    @Published private(set) var cubeStateRevision = 0
    @Published private(set) var weiPo2LastNativeSnapshot: WeiPo2NativeState?
    @Published private(set) var weiPo2LatestNativeTurn: WeiPo2NativeTurn?
    @Published private(set) var weiPo2VisualFacelets: String?
    @Published private(set) var weiPo2VisualRevision = 0
    private var weiPo2VisualAdapter = WeiPo2NativeVisualAdapter()
    private var weiPo2LocalReference: SmartCubeSoftwareResetReference?
    private var weiPo2PendingMoves: [UInt8: SmartCubeMoveEvent] = [:]
    private var weiPo2PendingSnapshotCounters: Set<UInt8> = []
    @Published private(set) var weiPo2PendingSnapshotCount = 0
    private(set) var weiPo2ReferenceOrientation: SmartCubeGyroState?
    private(set) var gyroState: SmartCubeGyroState?
    let gyroFeed = SmartCubeGyroFeed()
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var hardwareSummary: String?
    @Published private(set) var logEntries: [SmartCubeLogEntry] = []
    @Published private(set) var protocolLogEntries: [SmartCubeLogEntry] = []
    @Published var protocolDebugLogging = false
    @Published var coalesceSliceMoves = false
    @Published var verbosePacketLogging = false
    @Published private(set) var isPacketCaptureActive = false
    @Published private(set) var isPacketCaptureFinishing = false
    private var packetCaptureStartedAt: Date?
    private var packetCaptureLines: [String] = []
    #if DEBUG
    private var weiPo2ConnectionCaptureStartedAt: Date?
    private var weiPo2ConnectionCaptureLines: [String] = []
    #endif
    private var verbosePacketSampleCount = 0
    private var gyroLogSampleCount = 0

    nonisolated static let solvedFacelets = "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB"

    private let ganGen2ServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DC4179")
    private let ganGen2CommandCharacteristicUUID = CBUUID(string: "28BE4A4A-CD67-11E9-A32F-2A2AE2DBCCE4")
    private let ganGen2StateCharacteristicUUID = CBUUID(string: "28BE4CB6-CD67-11E9-A32F-2A2AE2DBCCE4")

    private let ganGen3ServiceUUID = CBUUID(string: "8653000A-43E6-47B7-9CB0-5FC21D4AE340")
    private let ganGen3CommandCharacteristicUUID = CBUUID(string: "8653000C-43E6-47B7-9CB0-5FC21D4AE340")
    private let ganGen3StateCharacteristicUUID = CBUUID(string: "8653000B-43E6-47B7-9CB0-5FC21D4AE340")

    private let ganGen4ServiceUUID = CBUUID(string: "00000010-0000-FFF7-FFF6-FFF5FFF4FFF0")
    private let ganGen4CommandCharacteristicUUID = CBUUID(string: "0000FFF5-0000-1000-8000-00805F9B34FB")
    private let ganGen4StateCharacteristicUUID = CBUUID(string: "0000FFF6-0000-1000-8000-00805F9B34FB")

    private let moyuMainServiceUUID = CBUUID(string: "0783B03E-7735-B5A0-1760-A305D2795CB0")
    private let moyuNotifyCharacteristicUUID = CBUUID(string: "0783B03E-7735-B5A0-1760-A305D2795CB1")
    private let moyuWriteCharacteristicUUID = CBUUID(string: "0783B03E-7735-B5A0-1760-A305D2795CB2")
    private let qiyiServiceUUID = CBUUID(string: "FFF0")
    private let qiyiStateCharacteristicUUID = CBUUID(string: "FFF6")

    private let centralManager: CBCentralManager
    private let parserQueue = DispatchQueue(label: "CubeFlow.SmartCube.Parser", qos: .userInteractive)
    private var discoveredPeripheralsByID: [UUID: CBPeripheral] = [:]
    private var discoveredSaltByID: [UUID: [UInt8]] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var pendingProtocolHint: SmartCubeProtocolKind = .unknown
    private var isConnectedProtocolConfirmed = false
    private var protocolIdentityInfo: SmartCubeProtocolIdentityInfo?
    private var bootstrapAttemptID: UUID?
    private var commandCharacteristic: CBCharacteristic?
    private var stateCharacteristic: CBCharacteristic?
    private var parser: GANCubeProtocolParser?
    private var qiyiParser: QiYiCubeProtocolParser?
    private var parserGeneration = 0
    private var historyRetryWorkItem: DispatchWorkItem?
    private var cipher: GANCubeCipher?
    private var isLocalFaceletStateLocked = false
    private var shouldAcceptNextFaceletsSnapshot = false
    private enum PendingCubeResetPhase {
        case awaitingTransport
        case awaitingHardwareWrite
        case awaitingHardwareSnapshot
        case awaitingSoftwareSnapshot
    }
    private struct PendingCubeReset {
        let identity: SmartCubeResetRequestIdentity
        let previousFacelets: String?
        var phase: PendingCubeResetPhase
        var readbackAttempts = 0
    }
    private var pendingCubeReset: PendingCubeReset?
    private var cubeResetReadbackWorkItem: DispatchWorkItem?
    private var softwareResetReferences: [UUID: SmartCubeSoftwareResetReference] = [:]
    private var pendingMoveEvent: SmartCubeMoveEvent?
    private var pendingMoveFlushWorkItem: DispatchWorkItem?
    private var packetRateWindowStart = Date()
    private var packetCountsByCharacteristic: [String: Int] = [:]
    private var sampledCharacteristicUUIDs: Set<String> = []
    private var wcuMY22DebugPacketCount = 0

    init(central: CBCentralManager) {
        centralManager = central
        super.init()
    }

    func configure(peripheral: CBPeripheral, discovery: SmartCubeDiscoveredDevice, salt: [UInt8]?) {
        discoveredPeripheralsByID[peripheral.identifier] = peripheral
        discoveredDevices = [discovery]
        discoveredSaltByID[peripheral.identifier] = salt
    }

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    var observationReadiness: SmartCubeObservationReadiness {
        SmartCubeObservationReadiness(
            attemptID: connectionAttemptID,
            isBLEConnected: isConnected,
            hasResolvedConnectionPolicy: connectionPolicyResolvedAttemptID == connectionAttemptID,
            hasAuthoritativeState: facelets != nil,
            hasTrustedCanonicalState: hasTrustedCanonicalState
        )
    }

    var isReadyForMoveObservation: Bool { observationReadiness.isReady }

    @discardableResult
    func connect(to deviceID: UUID, connectTransport: Bool = true) -> UUID? {
        guard centralManager.state == .poweredOn || !connectTransport else {
            connectionState = .bluetoothUnavailable
            return nil
        }
        guard let peripheral = discoveredPeripheralsByID[deviceID] else {
            connectionState = .failed("Device is no longer available")
            return nil
        }

        #if DEBUG
        let previousAttemptID = connectionAttemptID
        let previousDeviceID = connectionDeviceID
        if previousAttemptID != nil {
            SmartCubeDiagnostics.shared.trace(
                "attempt.superseded",
                attemptID: previousAttemptID,
                deviceID: previousDeviceID,
                detail: "replacementDevice=\(String(deviceID.uuidString.prefix(8)))"
            )
        }
        #endif
        disconnectConnectedPeripheralIfNeeded()
        resetSessionData(keepLogs: true)
        let attemptID = UUID()
        connectionAttemptID = attemptID
        connectionDeviceID = deviceID
        connectedPeripheral = peripheral
        let selectedDevice = discoveredDevices.first(where: { $0.id == deviceID })
        pendingProtocolHint = selectedDevice?.protocolHint
            ?? SavedSmartCubeDevices.shared.device(deviceID).flatMap { SmartCubeProtocolKind(rawValue: $0.protocolFamily) }
            ?? .unknown
        connectedProtocol = pendingProtocolHint
        connectedDeviceName = selectedDevice?.name
            ?? SavedSmartCubeDevices.shared.device(deviceID)?.originalName
            ?? peripheral.name
        connectedMACAddress = selectedDevice?.macAddress
        identity = SmartCubeIdentity.resolve(
            advertisedName: connectedDeviceName,
            protocolFamily: connectedProtocol,
            protocolConfirmed: false,
            protocolInfo: nil,
            serviceIdentifiers: selectedDevice?.advertisedServices ?? []
        )
        #if DEBUG
        if pendingProtocolHint == .moyu,
           SmartCubePuzzleKind.resolve(advertisedName: connectedDeviceName, protocolModelIdentifier: nil) == .twoByTwo {
            weiPo2ConnectionCaptureStartedAt = Date()
            weiPo2ConnectionCaptureLines = []
            captureEvent("connect requested device=\(connectedDeviceName ?? "unknown") attempt=\(attemptID.uuidString)")
        }
        #endif
        if let salt = discoveredSaltByID[deviceID] {
            cipher = GANCubeCipher(salt: salt)
            appendLog("MAC", connectedMACAddress ?? "Salt found in manufacturer data")
        } else {
            cipher = nil
            appendLog("MAC", "No cube MAC salt found yet; raw packets will still be logged")
        }

        connectionState = .connecting
        #if DEBUG
        SmartCubeDiagnostics.shared.trace(
            "attempt.created",
            attemptID: attemptID,
            deviceID: deviceID,
            detail: "name=\(connectedDeviceName ?? "unknown") protocolHint=\(pendingProtocolHint.rawValue)"
        )
        SmartCubeDiagnostics.shared.trace("ble.connecting", attemptID: attemptID, deviceID: deviceID)
        #endif
        peripheral.delegate = self
        if connectTransport { centralManager.connect(peripheral, options: nil) }
        let timeout = DispatchWorkItem { [weak self] in
            guard let self,
                  SmartCubeConnectionAttemptPolicy.shouldExpire(
                    expected: attemptID, current: self.connectionAttemptID,
                    state: self.connectionState
                  ) else { return }
            self.disconnect()
            self.onConnectionTimeout?()
        }
        connectionTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
        return attemptID
    }

    @discardableResult
    func connectSavedDevice(_ deviceID: UUID) -> UUID? {
        guard SavedSmartCubeDevices.shared.device(deviceID) != nil else { return nil }
        return connect(to: deviceID)
    }

    @discardableResult
    func resolveConnectionPolicy(for attemptID: UUID) -> Bool {
        guard connectionAttemptID == attemptID else {
            #if DEBUG
            SmartCubeDiagnostics.shared.trace(
                "policy.resolve.rejected",
                attemptID: attemptID,
                deviceID: connectionDeviceID,
                detail: "reason=stale-attempt current=\(connectionAttemptID.map { String($0.uuidString.prefix(8)) } ?? "none")"
            )
            #endif
            return false
        }
        connectionPolicyResolvedAttemptID = attemptID
        #if DEBUG
        SmartCubeDiagnostics.shared.trace("policy.resolved", attemptID: attemptID, deviceID: connectionDeviceID)
        #endif
        return true
    }

    func disconnect() {
        #if DEBUG
        SmartCubeDiagnostics.shared.trace(
            "attempt.cancelled",
            attemptID: connectionAttemptID,
            deviceID: connectionDeviceID,
            detail: "reason=user-disconnect"
        )
        #endif
        disconnectConnectedPeripheralIfNeeded()
        resetSessionData(keepLogs: true)
        connectionState = .disconnected
        appendLog("Disconnect", "Smart cube disconnected")
    }

    func clearLog() {
        logEntries = []
        protocolLogEntries = []
    }

    func startPacketCapture() {
        packetCaptureStartedAt = Date()
        isPacketCaptureFinishing = false
        #if DEBUG
        let connectionPrelude = weiPo2ConnectionCaptureLines
        weiPo2ConnectionCaptureStartedAt = nil
        weiPo2ConnectionCaptureLines = []
        #else
        let connectionPrelude: [String] = []
        #endif
        packetCaptureLines = [
            "CubeFlow Smart Cube packet capture",
            "device=\(connectedDeviceName ?? "unknown") protocol=\(connectedProtocol.rawValue) puzzle=\(puzzleSize)x\(puzzleSize)",
            "attempt=\(connectionAttemptID?.uuidString ?? "none")"
        ] + connectionPrelude + ["capture+0.000 manual start"]
        isPacketCaptureActive = true
        if isConnected, connectedProtocol == .moyu, puzzleSize == 2 {
            requestCaptureFacelets("initial")
        }
    }

    func stopPacketCapture() {
        isPacketCaptureActive = false
        isPacketCaptureFinishing = false
        packetCaptureStartedAt = nil
    }

    func finishPacketCapture() {
        guard isPacketCaptureActive, !isPacketCaptureFinishing else { return }
        guard isConnected, connectedProtocol == .moyu, puzzleSize == 2 else {
            stopPacketCapture()
            return
        }
        isPacketCaptureFinishing = true
        let started = packetCaptureStartedAt
        requestCaptureFacelets("final")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.packetCaptureStartedAt == started else { return }
            self.stopPacketCapture()
        }
    }

    private func requestCaptureFacelets(_ label: String) {
        guard isPacketCaptureActive, isConnected, connectedProtocol == .moyu, puzzleSize == 2 else { return }
        // Capture-only requests must not alter the app's facelet reference or reset state.
        captureEvent("auto Request Facelets \(label)")
        _ = sendCommand(.requestFacelets)
    }

    private func requestCaptureFaceletsAfterMove(packetByte13: UInt8?) {
        guard isPacketCaptureActive, !isPacketCaptureFinishing,
              connectedProtocol == .moyu, puzzleSize == 2 else { return }
        let started = packetCaptureStartedAt
        let attempt = connectionAttemptID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, self.packetCaptureStartedAt == started,
                  self.connectionAttemptID == attempt, !self.isPacketCaptureFinishing else { return }
            let label = packetByte13.map { "after A5 byte13=\(String(format: "%02X", $0))" } ?? "after A5"
            self.requestCaptureFacelets(label)
        }
    }

    var packetCaptureText: String { packetCaptureLines.joined(separator: "\n") }

    private func captureEvent(_ detail: String) {
        if isPacketCaptureActive, let started = packetCaptureStartedAt {
            let elapsed = Date().timeIntervalSince(started)
            if elapsed >= 30 || packetCaptureLines.count >= 4000 {
                stopPacketCapture()
                return
            }
            packetCaptureLines.append(String(format: "+%.3f %@", elapsed, detail))
            return
        }
        #if DEBUG
        guard let started = weiPo2ConnectionCaptureStartedAt,
              weiPo2ConnectionCaptureLines.count < 1200 else { return }
        let elapsed = Date().timeIntervalSince(started)
        weiPo2ConnectionCaptureLines.append(String(format: "pre+%.3f %@", elapsed, detail))
        #endif
    }

    private func capturePacket(_ label: String, _ bytes: [UInt8]) {
        #if DEBUG
        guard isPacketCaptureActive ||
            (weiPo2ConnectionCaptureStartedAt != nil && weiPo2ConnectionCaptureLines.count < 1200) else { return }
        #else
        guard isPacketCaptureActive else { return }
        #endif
        captureEvent("\(label) \(Self.hexString(bytes))")
    }

    func requestFacelets() {
        captureEvent("ui Request Facelets tapped")
        if let connectionDeviceID {
            softwareResetReferences[connectionDeviceID] = nil
        }
        isLocalFaceletStateLocked = false
        shouldAcceptNextFaceletsSnapshot = true
        #if DEBUG
        SmartCubeDiagnostics.shared.trace(
            "snapshot.requested",
            attemptID: connectionAttemptID,
            deviceID: connectionDeviceID,
            detail: "source=manual-authoritative"
        )
        #endif
        sendCommand(.requestFacelets)
    }

    func requestBattery() {
        sendCommand(.requestBattery)
    }

    func requestHardware() {
        sendCommand(.requestHardware)
    }

    func resetCubeStateToSolved() {
        guard let connectionAttemptID, let connectionDeviceID, isConnected else {
            appendLog("Reset", "No active Smart Cube connection")
            return
        }
        if connectedProtocol == .moyu, puzzleSize == 2 {
            guard let native = weiPo2VisualAdapter.renderableFacelets,
                  weiPo2LastNativeSnapshot != nil,
                  weiPo2PendingSnapshotCount == 0,
                  hasTrustedCanonicalState else {
                appendLog("Reset", "Wait for an authoritative WeiPo state before marking solved")
                _ = sendCommand(.requestFacelets)
                return
            }
            let solved = CubeSurface.solved(size: 2)
            weiPo2LocalReference = SmartCubeSoftwareResetReference(
                deviceID: connectionDeviceID,
                expectedDeviceFacelets: native,
                localFacelets: solved
            )
            weiPo2PendingMoves.removeAll()
            weiPo2PendingSnapshotCounters.removeAll()
            weiPo2PendingSnapshotCount = 0
            latestMove = nil
            moveHistory = []
            canonicalFeed.clearHistory()
            facelets = solved
            cubeStateRevision += 1
            weiPo2VisualFacelets = solved
            weiPo2VisualRevision += 1
            canonicalFeed.acceptAuthoritativeSnapshot(solved, stateChanged: true)
            appendLog("Reset", "Local WeiPo solved reference established from current A3 state")
            return
        }
        #if DEBUG
        SmartCubeDiagnostics.shared.trace(
            "reset.requested",
            attemptID: connectionAttemptID,
            deviceID: connectionDeviceID,
            detail: "capability=\(connectedProtocol.stateResetCapability)"
        )
        #endif
        cubeResetReadbackWorkItem?.cancel()
        cubeResetReadbackWorkItem = nil
        parserGeneration += 1
        #if DEBUG
        SmartCubeDiagnostics.shared.trace("parser.generation", attemptID: connectionAttemptID, deviceID: connectionDeviceID, detail: "generation=\(parserGeneration) reason=reset")
        #endif
        historyRetryWorkItem?.cancel()
        historyRetryWorkItem = nil
        cancelPendingMove()
        latestMove = nil
        moveHistory = []
        canonicalFeed.clearHistory()
        let previousFacelets = facelets
        facelets = nil
        canonicalFeed.breakContinuity(.reset, facelets: nil)
        #if DEBUG
        SmartCubeDiagnostics.shared.trace("canonical.trust.changed", attemptID: connectionAttemptID, deviceID: connectionDeviceID, detail: "trusted=false reason=reset")
        #endif
        cubeStateRevision += 1
        isLocalFaceletStateLocked = false
        shouldAcceptNextFaceletsSnapshot = false
        pendingCubeReset = PendingCubeReset(
            identity: SmartCubeResetRequestIdentity(
                id: UUID(),
                connectionAttemptID: connectionAttemptID,
                deviceID: connectionDeviceID
            ),
            previousFacelets: previousFacelets,
            phase: .awaitingTransport
        )
        if let parser {
            parserQueue.async {
                parser.resetMoveTracking()
            }
        }
        appendLog("Reset", "Reset requested; waiting for authoritative cube state")
        continuePendingCubeResetIfPossible()
    }

    nonisolated static func facelets(afterApplying algorithm: String, puzzleSize: Int = 3) -> String? {
        let moves = algorithm.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return faceletStates(afterApplying: moves, puzzleSize: puzzleSize)?.last
    }

    nonisolated static func faceletStates(afterApplying moves: [String], puzzleSize: Int = 3) -> [String]? {
        guard !moves.isEmpty else { return nil }
        let solved = CubeSurface.solved(size: puzzleSize)
        var states = [solved]
        var state = solved
        for move in moves {
            guard let next = facelets(state, applying: move) else { return nil }
            state = next
            states.append(state)
        }
        return states
    }

    private func disconnectConnectedPeripheralIfNeeded() {
        if let connectedPeripheral {
            centralManager.cancelPeripheralConnection(connectedPeripheral)
        }
        connectedPeripheral = nil
        pendingProtocolHint = .unknown
        commandCharacteristic = nil
        stateCharacteristic = nil
        setParser(nil)
        qiyiParser = nil
        cipher = nil
        cancelPendingMove()
    }

    private func resetSessionData(keepLogs: Bool) {
        connectionTimeout?.cancel()
        connectionTimeout = nil
        #if DEBUG
        let invalidatedAttemptID = connectionAttemptID
        let invalidatedDeviceID = connectionDeviceID
        #endif
        cubeResetReadbackWorkItem?.cancel()
        cubeResetReadbackWorkItem = nil
        pendingCubeReset = nil
        connectionAttemptID = nil
        connectionDeviceID = nil
        connectionPolicyResolvedAttemptID = nil
        bootstrapAttemptID = nil
        connectedDeviceName = nil
        connectedProtocol = .unknown
        identity = nil
        isConnectedProtocolConfirmed = false
        protocolIdentityInfo = nil
        connectedMACAddress = nil
        discoveredServiceUUIDs = []
        discoveredCharacteristicUUIDs = []
        latestMove = nil
        moveHistory = []
        canonicalFeed.clearHistory()
        facelets = nil
        canonicalFeed.breakContinuity(.disconnected, facelets: nil)
        cubeStateRevision += 1
        weiPo2LastNativeSnapshot = nil
        weiPo2LatestNativeTurn = nil
        weiPo2VisualAdapter.reset()
        weiPo2LocalReference = nil
        weiPo2PendingMoves.removeAll()
        weiPo2PendingSnapshotCounters.removeAll()
        weiPo2PendingSnapshotCount = 0
        weiPo2VisualFacelets = nil
        weiPo2VisualRevision += 1
        weiPo2ReferenceOrientation = nil
        gyroState = nil
        #if DEBUG
        weiPo2ConnectionCaptureStartedAt = nil
        weiPo2ConnectionCaptureLines = []
        #endif
        gyroFeed.send(nil)
        batteryLevel = nil
        hardwareSummary = nil
        commandCharacteristic = nil
        stateCharacteristic = nil
        setParser(nil)
        qiyiParser = nil
        isLocalFaceletStateLocked = false
        shouldAcceptNextFaceletsSnapshot = false
        packetRateWindowStart = Date()
        packetCountsByCharacteristic = [:]
        sampledCharacteristicUUIDs = []
        wcuMY22DebugPacketCount = 0
        cancelPendingMove()
        #if DEBUG
        if invalidatedAttemptID != nil {
            SmartCubeDiagnostics.shared.trace(
                "attempt.invalidated",
                attemptID: invalidatedAttemptID,
                deviceID: invalidatedDeviceID,
                detail: "parserGeneration=\(parserGeneration)"
            )
        }
        #endif
        if !keepLogs {
            logEntries = []
            protocolLogEntries = []
        }
    }

    private func setParser(_ newParser: GANCubeProtocolParser?) {
        historyRetryWorkItem?.cancel()
        historyRetryWorkItem = nil
        parser = newParser
        parserGeneration += 1
        #if DEBUG
        SmartCubeDiagnostics.shared.trace(
            "parser.generation",
            attemptID: connectionAttemptID,
            deviceID: connectionDeviceID,
            detail: "generation=\(parserGeneration) parser=\(newParser == nil ? "none" : connectedProtocol.rawValue)"
        )
        #endif
    }

    private func bootstrapWhenSubscribed() {
        guard let attempt = connectionAttemptID, isConnected,
              commandCharacteristic != nil, stateCharacteristic?.isNotifying == true,
              bootstrapAttemptID != attempt else { return }
        bootstrapAttemptID = attempt
        if connectedProtocol == .moyu {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.sendInitialRequests(for: attempt)
            }
        } else {
            sendInitialRequests(for: attempt)
        }
    }

    func transportBecameUnavailable() {
        connectedPeripheral = nil
        resetSessionData(keepLogs: true)
        connectionState = .bluetoothUnavailable
    }

    func refreshAfterForeground() {
        guard isConnected, let peripheral = connectedPeripheral else { return }
        if continuePendingCubeResetIfPossible() { return }
        guard let stateCharacteristic, commandCharacteristic != nil else {
            peripheral.discoverServices(nil)
            return
        }
        if !stateCharacteristic.isNotifying {
            bootstrapAttemptID = nil
            peripheral.setNotifyValue(true, for: stateCharacteristic)
        } else if let attempt = connectionAttemptID {
            sendInitialRequests(for: attempt)
        }
    }

    private func sendInitialRequests(for attemptID: UUID) {
        guard connectionAttemptID == attemptID, isConnected else {
            #if DEBUG
            SmartCubeDiagnostics.shared.trace("snapshot.request.rejected", attemptID: attemptID, deviceID: connectionDeviceID, detail: "reason=stale-attempt-or-disconnected")
            #endif
            return
        }
        if connectedProtocol == .qiyi {
            sendCommand(.requestFacelets)
            return
        }
        if connectedProtocol == .moyu {
            sendCommand(.requestHardware)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, self.connectionAttemptID == attemptID, self.isConnected else { return }
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("snapshot.requested", attemptID: attemptID, deviceID: self.connectionDeviceID, detail: "source=initial protocol=moyu")
                #endif
                self.sendCommand(.requestFacelets)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
                guard let self, self.connectionAttemptID == attemptID, self.isConnected else { return }
                self.sendCommand(.requestBattery)
            }
            return
        }

        #if DEBUG
        SmartCubeDiagnostics.shared.trace("snapshot.requested", attemptID: attemptID, deviceID: connectionDeviceID, detail: "source=initial protocol=\(connectedProtocol.rawValue)")
        #endif
        sendCommand(.requestFacelets)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.connectionAttemptID == attemptID, self.isConnected else { return }
            self.sendCommand(.requestBattery)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            guard let self, self.connectionAttemptID == attemptID, self.isConnected else { return }
            self.sendCommand(.requestHardware)
        }
    }

    @discardableResult
    private func continuePendingCubeResetIfPossible() -> Bool {
        guard var pending = pendingCubeReset,
              pending.phase == .awaitingTransport,
              pending.identity.matches(
                connectionAttemptID: connectionAttemptID,
                deviceID: connectionDeviceID
              ),
              (parser != nil || qiyiParser != nil),
              commandCharacteristic != nil else { return false }

        switch connectedProtocol.stateResetCapability {
        case .deviceResetWithAuthoritativeReadback:
            pending.phase = .awaitingHardwareWrite
            pendingCubeReset = pending
            #if DEBUG
            SmartCubeDiagnostics.shared.trace("gan.reset.command.requested", attemptID: pending.identity.connectionAttemptID, deviceID: pending.identity.deviceID, detail: "reset=\(String(pending.identity.id.uuidString.prefix(8)))")
            #endif
            guard sendCommand(.requestReset) else {
                failPendingCubeReset(
                    resetID: pending.identity.id,
                    disposition: .restorePreviousState,
                    message: "Device reset command could not be sent"
                )
                return true
            }
            appendLog("Reset", "Device-side state reset sent; awaiting verified read-back")
        case .softwareReference:
            pending.phase = .awaitingSoftwareSnapshot
            pendingCubeReset = pending
            #if DEBUG
            SmartCubeDiagnostics.shared.trace("moyu.reference.snapshot.requested", attemptID: pending.identity.connectionAttemptID, deviceID: pending.identity.deviceID, detail: "reset=\(String(pending.identity.id.uuidString.prefix(8)))")
            #endif
            guard sendCommand(.requestFacelets) else {
                failPendingCubeReset(
                    resetID: pending.identity.id,
                    disposition: .restorePreviousState,
                    message: "Software reset reference could not request device state"
                )
                return true
            }
            scheduleSoftwareResetSnapshotTimeout(for: pending.identity.id)
            appendLog("Reset", "Hardware reset unsupported; awaiting a device snapshot for software reference")
        }
        return true
    }

    private func requestHardwareResetReadback(for resetID: UUID) {
        guard var pending = pendingCubeReset,
              pending.identity.id == resetID,
              pending.phase == .awaitingHardwareSnapshot,
              pending.identity.matches(
                connectionAttemptID: connectionAttemptID,
                deviceID: connectionDeviceID
              ) else { return }
        pending.readbackAttempts += 1
        pendingCubeReset = pending
        #if DEBUG
        SmartCubeDiagnostics.shared.trace(
            "gan.reset.readback.requested",
            attemptID: pending.identity.connectionAttemptID,
            deviceID: pending.identity.deviceID,
            detail: "reset=\(String(resetID.uuidString.prefix(8))) retry=\(pending.readbackAttempts)"
        )
        #endif
        guard sendCommand(.requestFacelets) else {
            failPendingCubeReset(
                resetID: resetID,
                disposition: .requireAuthoritativeState,
                message: "Authoritative reset read-back could not be requested"
            )
            return
        }

        cubeResetReadbackWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  let current = self.pendingCubeReset,
                  current.identity.id == resetID,
                  current.phase == .awaitingHardwareSnapshot else { return }
            if SmartCubeResetReadbackPolicy.shouldRetry(afterAttempt: current.readbackAttempts) {
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("gan.reset.readback.timeout", attemptID: current.identity.connectionAttemptID, deviceID: current.identity.deviceID, detail: "retry=\(current.readbackAttempts) action=retry")
                #endif
                self.requestHardwareResetReadback(for: resetID)
            } else {
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("gan.reset.readback.timeout", attemptID: current.identity.connectionAttemptID, deviceID: current.identity.deviceID, detail: "retry=\(current.readbackAttempts) action=fail")
                #endif
                self.failPendingCubeReset(
                    resetID: resetID,
                    disposition: .requireAuthoritativeState,
                    message: "Device reset was not confirmed by authoritative read-back"
                )
            }
        }
        cubeResetReadbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func scheduleSoftwareResetSnapshotTimeout(for resetID: UUID) {
        cubeResetReadbackWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  let current = self.pendingCubeReset,
                  current.identity.id == resetID,
                  current.phase == .awaitingSoftwareSnapshot else { return }
            self.failPendingCubeReset(
                resetID: resetID,
                disposition: .restorePreviousState,
                message: "Software reset reference was not confirmed by a device snapshot"
            )
        }
        cubeResetReadbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: workItem)
    }

    private func failPendingCubeReset(
        resetID: UUID,
        disposition: SmartCubeResetFailureDisposition,
        message: String
    ) {
        guard let pending = pendingCubeReset,
              pending.identity.id == resetID,
              pending.identity.matches(
                connectionAttemptID: connectionAttemptID,
                deviceID: connectionDeviceID
              ) else { return }
        cubeResetReadbackWorkItem?.cancel()
        cubeResetReadbackWorkItem = nil
        pendingCubeReset = nil
        #if DEBUG
        SmartCubeDiagnostics.shared.trace("reset.failed", attemptID: pending.identity.connectionAttemptID, deviceID: pending.identity.deviceID, detail: "disposition=\(disposition) reason=\(message)")
        #endif
        if let resolvedFacelets = disposition.resolvedFacelets(previousFacelets: pending.previousFacelets) {
            facelets = resolvedFacelets
            canonicalFeed.breakContinuity(.resync, facelets: resolvedFacelets)
            cubeStateRevision += 1
        }
        appendLog("Reset", message)
    }

    private func sendPostResetMetadataRequests(for attemptID: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.connectionAttemptID == attemptID, self.isConnected else { return }
            _ = self.sendCommand(.requestBattery)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            guard let self, self.connectionAttemptID == attemptID, self.isConnected else { return }
            _ = self.sendCommand(.requestHardware)
        }
    }

    @discardableResult
    private func sendCommand(_ command: GANCubeCommand) -> Bool {
        guard let commandCharacteristic, let connectedPeripheral else {
            captureEvent("tx \(command.label) rejected: no writable characteristic")
            appendLog("Command", "No writable command characteristic")
            return false
        }
        if connectedProtocol == .qiyi {
            guard let qiyiParser else { return false }
            switch command {
            case .requestFacelets, .requestBattery:
                guard let packet = qiyiParser.helloPacket() else { return false }
                let type: CBCharacteristicWriteType = commandCharacteristic.properties.contains(.writeWithoutResponse)
                    ? .withoutResponse : .withResponse
                connectedPeripheral.writeValue(Data(packet), for: commandCharacteristic, type: type)
                return true
            case .requestHardware, .requestReset, .requestMoveHistory:
                return false
            }
        }
        guard let parser else {
            captureEvent("tx \(command.label) rejected: protocol not ready")
            appendLog("Command", "Protocol not ready")
            return false
        }
        let message = parserQueue.sync {
            parser.commandMessage(for: command)
        }
        guard let message else {
            captureEvent("tx \(command.label) rejected: unsupported command")
            appendLog("Command", "Unsupported command for \(connectedProtocol.rawValue)")
            return false
        }
        let encrypted = cipher?.encrypt(message) ?? message
        let writeType = Self.writeType(for: command, characteristic: commandCharacteristic)
        capturePacket(
            "tx queued \(command.label) opcode=\(String(format: "%02X", message[0])) char=\(commandCharacteristic.uuid.uuidString) props=\(Self.propertySummary(commandCharacteristic.properties)) mode=\(writeType == .withResponse ? "withResponse" : "withoutResponse") cipher=\(cipher == nil ? "missing" : "present")",
            encrypted
        )
        connectedPeripheral.writeValue(Data(encrypted), for: commandCharacteristic, type: writeType)
        if protocolDebugLogging || !command.isHighFrequency {
            appendLog("Command", "\(command.label) [\(writeType == .withoutResponse ? "noRsp" : "rsp")]: \(Self.hexString(encrypted))")
        }
        return true
    }

    private static func writeType(for command: GANCubeCommand, characteristic: CBCharacteristic) -> CBCharacteristicWriteType {
        if case .requestMoveHistory = command,
           characteristic.properties.contains(.writeWithoutResponse) {
            return .withoutResponse
        }
        return .withResponse
    }

    private func handleStateData(_ data: Data, characteristic: CBCharacteristic) {
        #if DEBUG
        let packetID = UUID()
        SmartCubeDiagnostics.shared.mark("ble.rx", id: packetID)
        #endif
        let raw = [UInt8](data)
        capturePacket("rx \(characteristic.uuid.uuidString)", raw)
        verbosePacketSampleCount += 1
        let shouldLogVerbosePacket = verbosePacketLogging
            && (verbosePacketSampleCount <= 16 || verbosePacketSampleCount % 25 == 0)
        if shouldLogVerbosePacket {
            appendLog("Raw \(characteristic.uuid.uuidString)", Self.hexString(raw))
        }

        if connectedProtocol == .qiyi {
            guard let qiyiParser else { return }
            let generation = parserGeneration
            parserQueue.async { [weak self, qiyiParser] in
                let result = qiyiParser.consume(raw)
                DispatchQueue.main.async {
                    guard let self, self.parserGeneration == generation else { return }
                    self.capturePacket("qiyi parsed-events", [UInt8(clamping: result.events.count)])
                    for event in result.events { self.apply(event) }
                    if let packet = result.acknowledgement,
                       let commandCharacteristic = self.commandCharacteristic,
                       let connectedPeripheral = self.connectedPeripheral {
                        let type: CBCharacteristicWriteType = commandCharacteristic.properties.contains(.writeWithoutResponse)
                            ? .withoutResponse : .withResponse
                        connectedPeripheral.writeValue(Data(packet), for: commandCharacteristic, type: type)
                    }
                }
            }
            return
        }

        guard let parser else {
            captureEvent("decode skipped char=\(characteristic.uuid.uuidString) reason=parser-unavailable")
            #if DEBUG
            SmartCubeDiagnostics.shared.trace("packet.rejected", attemptID: connectionAttemptID, deviceID: connectionDeviceID, detail: "reason=parser-unavailable characteristic=\(characteristic.uuid.uuidString)")
            #endif
            return
        }
        guard let cipher else {
            captureEvent("decode skipped char=\(characteristic.uuid.uuidString) reason=cipher-unavailable")
            appendLog("Decode", "Missing cube MAC salt; cannot decrypt this packet")
            #if DEBUG
            SmartCubeDiagnostics.shared.trace("packet.rejected", attemptID: connectionAttemptID, deviceID: connectionDeviceID, detail: "reason=cipher-unavailable characteristic=\(characteristic.uuid.uuidString)")
            #endif
            return
        }
        let generation = parserGeneration
        let attemptID = connectionAttemptID
        let deviceID = connectionDeviceID
        let shouldLogPackets = shouldLogVerbosePacket
        let shouldTraceWCU2 = protocolDebugLogging
            && identity?.protocolModelIdentifier == "WCU_MY22"
        let sourceCharacteristicID = characteristic.uuid.uuidString

        parserQueue.async { [weak self, parser, cipher] in
            #if DEBUG
            SmartCubeDiagnostics.shared.mark("parser.begin", id: packetID)
            #endif
            guard let decrypted = cipher.decrypt(raw) else {
                DispatchQueue.main.async {
                    guard self?.parserGeneration == generation else {
                        #if DEBUG
                        SmartCubeDiagnostics.shared.trace("packet.rejected", attemptID: attemptID, deviceID: deviceID, detail: "reason=stale-parser-generation stage=decrypt")
                        #endif
                        return
                    }
                    self?.captureEvent("decode failed char=\(sourceCharacteristicID) reason=AES-decrypt-failed")
                    self?.appendLog("Decode", "AES decrypt failed")
                    #if DEBUG
                    SmartCubeDiagnostics.shared.trace("packet.rejected", attemptID: attemptID, deviceID: deviceID, detail: "reason=decrypt-failed")
                    #endif
                }
                return
            }

            let parsedEvents = parser.handleStateEvent(decrypted)
            #if DEBUG
            SmartCubeDiagnostics.shared.mark("parser.end", id: packetID)
            for event in parsedEvents {
                if case .move(let move) = event {
                    SmartCubeDiagnostics.shared.mark("protocol.move", id: move.id, detail: "\(move.move) source=\(move.timestampSource)")
                    SmartCubeDiagnostics.shared.traceMove("move.protocol.received", move: move, attemptID: attemptID, deviceID: deviceID, accepted: true, detail: "generation=\(generation)")
                }
            }
            #endif
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.parserGeneration == generation else {
                    #if DEBUG
                    SmartCubeDiagnostics.shared.trace("packet.rejected", attemptID: attemptID, deviceID: deviceID, detail: "reason=stale-parser-generation stage=main-apply generation=\(generation)")
                    #endif
                    return
                }
                #if DEBUG
                SmartCubeDiagnostics.shared.mark("main.apply", id: packetID)
                #endif
                if shouldLogPackets {
                    self.appendLog("Decrypted", Self.hexString(decrypted))
                }
                self.capturePacket("decoded \(sourceCharacteristicID)", decrypted)
                if decrypted.first == 0xA5 {
                    self.requestCaptureFaceletsAfterMove(packetByte13: decrypted.count > 13 ? decrypted[13] : nil)
                }
                if shouldTraceWCU2, self.wcuMY22DebugPacketCount < 16 {
                    self.wcuMY22DebugPacketCount += 1
                    let type = decrypted.first.map { String(format: "%02X", $0) } ?? "--"
                    self.appendProtocolLog(
                        "WCU_MY22 packet \(self.wcuMY22DebugPacketCount)",
                        "char \(sourceCharacteristicID), type 0x\(type), bytes \(decrypted.count), parsed \(parsedEvents.count), raw \(Self.hexString(raw)), decrypted \(Self.hexString(decrypted))"
                    )
                }
                for event in parsedEvents {
                    self.apply(event)
                }
            }
        }
    }

    private func apply(_ event: SmartCubeParsedEvent) {
        switch event {
        case .move(let move):
            enqueueMove(move)
        case .weiPo2State(let state):
            weiPo2LastNativeSnapshot = state
            let nativeVisual = weiPo2VisualAdapter.accept(state)
            if weiPo2VisualAdapter.rejectedNewSnapshot {
                weiPo2LocalReference = nil
                weiPo2PendingMoves.removeAll()
                weiPo2PendingSnapshotCounters.removeAll()
                weiPo2PendingSnapshotCount = 0
                weiPo2VisualFacelets = nil
                weiPo2VisualRevision += 1
                facelets = nil
                cubeStateRevision += 1
                canonicalFeed.breakContinuity(.historyGap, facelets: nil)
                break
            }
            guard weiPo2VisualAdapter.acceptedNewSnapshot else { break }
            var visual = nativeVisual
            var localTurnEndpoints: [String] = []
            var referenceInvalidated = false
            if let reference = weiPo2LocalReference, let nativeVisual {
                var next = reference
                let steps = weiPo2VisualAdapter.validatedTurns
                if !steps.isEmpty {
                    for step in steps {
                        guard next.apply(step.notation) else { break }
                        localTurnEndpoints.append(next.localFacelets)
                    }
                }
                if localTurnEndpoints.count == steps.count,
                   next.expectedDeviceFacelets == nativeVisual {
                    weiPo2LocalReference = next
                    visual = next.localFacelets
                } else {
                    weiPo2LocalReference = nil
                    referenceInvalidated = true
                }
            } else if weiPo2LocalReference != nil {
                weiPo2LocalReference = nil
                referenceInvalidated = true
            }
            if weiPo2VisualFacelets != visual {
                weiPo2VisualFacelets = visual
                weiPo2VisualRevision += 1
            }
            let previousFacelets = facelets
            let wasTrusted = canonicalFeed.isStateTrusted
            facelets = visual
            cubeStateRevision += 1
            if let visual {
                let steps = weiPo2VisualAdapter.validatedTurns
                let moves = steps.compactMap { weiPo2PendingMoves[$0.turnCounter] }
                if !referenceInvalidated, !steps.isEmpty, moves.count == steps.count,
                   previousFacelets != nil, wasTrusted {
                    for (index, pair) in zip(steps, moves).enumerated() {
                        let (step, move) = pair
                        latestMove = move
                        moveHistory.append(move)
                        canonicalFeed.send(
                            move: move,
                            facelets: localTurnEndpoints.isEmpty ? step.facelets : localTurnEndpoints[index]
                        )
                    }
                    trimMoveHistoryIfNeeded()
                } else if previousFacelets != visual || !wasTrusted || !steps.isEmpty {
                    canonicalFeed.breakContinuity(.resync, facelets: visual)
                }
                weiPo2PendingMoves = weiPo2PendingMoves.filter {
                    let ahead = Int($0.key &- state.turnCounter)
                    return ahead > 0 && ahead < 128
                }
                weiPo2PendingSnapshotCounters = Set(weiPo2PendingSnapshotCounters.filter {
                    let ahead = Int($0 &- state.turnCounter)
                    return ahead > 0 && ahead < 128
                })
                weiPo2PendingSnapshotCount = weiPo2PendingSnapshotCounters.count
            } else {
                weiPo2PendingMoves.removeAll()
                weiPo2PendingSnapshotCounters.removeAll()
                weiPo2PendingSnapshotCount = 0
                canonicalFeed.breakContinuity(.historyGap, facelets: nil)
            }
            if protocolDebugLogging {
                appendProtocolLog("WeiPo 2x2 native state", "counter \(state.turnCounter), values \(state.stickerValues.map(String.init).joined()), layouts \(weiPo2VisualAdapter.possibleLayoutCount), validated turns \(weiPo2VisualAdapter.validatedTurns.count), renderable \(visual != nil)")
            }
        case .weiPo2Turn(let turn):
            weiPo2LatestNativeTurn = turn
            weiPo2VisualAdapter.note(turn)
            weiPo2PendingSnapshotCounters.insert(turn.turnCounter)
            weiPo2PendingSnapshotCount = weiPo2PendingSnapshotCounters.count
            let nativeNotation = ["F", "F'", "U", "U'", "R", "R'"]
            if Int(turn.code) < nativeNotation.count, turn.missedTurnCount == 0 {
                weiPo2PendingMoves[turn.turnCounter] = SmartCubeMoveEvent(
                    move: nativeNotation[Int(turn.code)],
                    serial: Int(turn.turnCounter),
                    face: nil,
                    direction: nil,
                    localTimestamp: .now,
                    cubeTimestampMilliseconds: nil
                )
            }
            if !isPacketCaptureActive, isConnected {
                _ = sendCommand(.requestFacelets)
            }
            if protocolDebugLogging {
                appendProtocolLog("WeiPo 2x2 native turn", "counter \(turn.turnCounter), code \(turn.code), missed \(turn.missedTurnCount)")
            }
        case .facelets(let value, let serial):
            flushPendingMove()
            #if DEBUG
            SmartCubeDiagnostics.shared.trace("snapshot.received", attemptID: connectionAttemptID, deviceID: connectionDeviceID, detail: "serial=\(serial) phase=\(pendingCubeReset.map { String(describing: $0.phase) } ?? "normal")")
            #endif
            guard Self.isPlausibleFacelets(value) else {
                appendLog("Ignored facelets", "serial \(serial): \(value)")
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("snapshot.rejected", attemptID: connectionAttemptID, deviceID: connectionDeviceID, detail: "serial=\(serial) reason=implausible-facelets")
                #endif
                return
            }
            if reconcileResetSnapshotIfNeeded(value, serial: serial) {
                return
            }
            guard let connectionDeviceID else {
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("snapshot.rejected", attemptID: connectionAttemptID, detail: "serial=\(serial) reason=device-identity-unavailable")
                #endif
                return
            }
            let resolvedFacelets: String
            if let reference = softwareResetReferences[connectionDeviceID] {
                switch reference.resolve(
                    deviceID: connectionDeviceID,
                    snapshot: value,
                    forceAuthoritative: shouldAcceptNextFaceletsSnapshot
                ) {
                case .preserveLocal(let localFacelets):
                    resolvedFacelets = localFacelets
                    isLocalFaceletStateLocked = true
                    appendLog("Facelets", "serial \(serial): software reset reference reconciled")
                    #if DEBUG
                    SmartCubeDiagnostics.shared.trace("moyu.reference.accepted", attemptID: connectionAttemptID, deviceID: connectionDeviceID, detail: "serial=\(serial) relationship=raw-baseline-matched")
                    #endif
                case .useAuthoritative(let authoritativeFacelets):
                    softwareResetReferences[connectionDeviceID] = nil
                    resolvedFacelets = authoritativeFacelets
                    isLocalFaceletStateLocked = false
                    appendLog("Facelets", "serial \(serial): software reference discarded; device state changed")
                    #if DEBUG
                    SmartCubeDiagnostics.shared.trace("moyu.reference.discarded", attemptID: connectionAttemptID, deviceID: connectionDeviceID, detail: "serial=\(serial) reason=raw-baseline-diverged")
                    #endif
                }
            } else {
                resolvedFacelets = value
                isLocalFaceletStateLocked = false
            }
            let stateChanged = facelets != resolvedFacelets || shouldAcceptNextFaceletsSnapshot
            facelets = resolvedFacelets
            // Equal snapshots still restore trust after a lost-history segment.
            canonicalFeed.acceptAuthoritativeSnapshot(resolvedFacelets, stateChanged: stateChanged)
            cubeStateRevision += 1
            shouldAcceptNextFaceletsSnapshot = false
            appendLog("Facelets", "serial \(serial): \(resolvedFacelets)")
            #if DEBUG
            SmartCubeDiagnostics.shared.trace("snapshot.accepted", attemptID: connectionAttemptID, deviceID: connectionDeviceID, detail: "serial=\(serial) source=\(isLocalFaceletStateLocked ? "software-reference" : "authoritative") revision=\(cubeStateRevision) canonicalTrusted=\(canonicalFeed.isStateTrusted)")
            SmartCubeDiagnostics.shared.trace("ui.facelets.published", attemptID: connectionAttemptID, deviceID: connectionDeviceID, detail: "revision=\(cubeStateRevision) source=snapshot")
            #endif
        case .battery(let level):
            flushPendingMove()
            batteryLevel = level
            appendLog("Battery", "\(level)%")
        case .hardware(let summary):
            flushPendingMove()
            guard Self.isPlausibleHardware(summary) else {
                appendLog("Ignored hardware", summary)
                return
            }
            hardwareSummary = summary
            protocolIdentityInfo = SmartCubeProtocolIdentityInfo(hardwareSummary: summary)
            refreshIdentity()
            appendLog("Hardware", summary)
        case .gyro(let state):
            flushPendingMove()
            gyroState = state
            gyroFeed.send(state)
            if connectedProtocol == .moyu, puzzleSize == 2 {
                weiPo2ReferenceOrientation = state
            }
            if verbosePacketLogging {
                gyroLogSampleCount += 1
                if gyroLogSampleCount <= 8 || gyroLogSampleCount % 25 == 0 {
                    appendLog("Gyro", state.summary)
                }
            }
        case .debug(let title, let detail):
            if protocolDebugLogging {
                appendProtocolLog(title, detail)
            }
        case .holdPendingMove(let seconds):
            #if DEBUG
            SmartCubeDiagnostics.shared.mark("history.coalescingHold", detail: "requested=\(seconds)s applied=\(coalesceSliceMoves)")
            #endif
            if coalesceSliceMoves {
                holdPendingMoveFlush(seconds: seconds)
            }
        case .requestMoveHistory(let startMoveCount, let numberOfMoves):
            #if DEBUG
            SmartCubeDiagnostics.shared.mark("history.request", detail: "start=\(startMoveCount) count=\(numberOfMoves)")
            #endif
            if protocolDebugLogging {
                appendProtocolLog("GAN request history", "start \(startMoveCount), moves \(numberOfMoves)")
            }
            sendCommand(.requestMoveHistory(startMoveCount: startMoveCount, numberOfMoves: numberOfMoves))
            scheduleHistoryRetry()
        case .continuityLost:
            canonicalFeed.breakContinuity(.historyGap, facelets: nil)
            #if DEBUG
            SmartCubeDiagnostics.shared.trace("canonical.trust.changed", attemptID: connectionAttemptID, deviceID: connectionDeviceID, detail: "trusted=false reason=history-gap")
            #endif
        }
    }

    private func reconcileResetSnapshotIfNeeded(_ value: String, serial: Int) -> Bool {
        guard let pending = pendingCubeReset,
              pending.identity.matches(
                connectionAttemptID: connectionAttemptID,
                deviceID: connectionDeviceID
              ) else { return false }

        switch pending.phase {
        case .awaitingTransport, .awaitingHardwareWrite:
            appendLog("Ignored facelets", "serial \(serial): reset command has not reached read-back phase")
            #if DEBUG
            SmartCubeDiagnostics.shared.trace("snapshot.rejected", attemptID: pending.identity.connectionAttemptID, deviceID: pending.identity.deviceID, detail: "serial=\(serial) reason=reset-not-in-readback-phase phase=\(pending.phase)")
            #endif
            return true
        case .awaitingHardwareSnapshot:
            cubeResetReadbackWorkItem?.cancel()
            cubeResetReadbackWorkItem = nil
            pendingCubeReset = nil
            softwareResetReferences[pending.identity.deviceID] = nil
            facelets = value
            canonicalFeed.acceptAuthoritativeSnapshot(value, stateChanged: true)
            cubeStateRevision += 1
            shouldAcceptNextFaceletsSnapshot = false
            isLocalFaceletStateLocked = false
            #if DEBUG
            let solvedFacelets = CubeSurface.solved(size: value.count == 24 ? 2 : 3)
            SmartCubeDiagnostics.shared.trace("gan.reset.readback.received", attemptID: pending.identity.connectionAttemptID, deviceID: pending.identity.deviceID, detail: "serial=\(serial) solved=\(value == solvedFacelets) retry=\(pending.readbackAttempts)")
            SmartCubeDiagnostics.shared.trace("canonical.trust.changed", attemptID: pending.identity.connectionAttemptID, deviceID: pending.identity.deviceID, detail: "trusted=\(canonicalFeed.isStateTrusted) source=gan-authoritative-readback")
            SmartCubeDiagnostics.shared.trace("ui.facelets.published", attemptID: pending.identity.connectionAttemptID, deviceID: pending.identity.deviceID, detail: "revision=\(cubeStateRevision) source=gan-authoritative-readback")
            #endif
            if CubeStateEquivalence.isSolved(value, puzzleSize: value.count == 24 ? 2 : 3) {
                appendLog("Reset", "Device reset verified by solved authoritative facelets")
            } else {
                appendLog("Reset", "Device reset read-back was not solved; using authoritative device state")
            }
            sendPostResetMetadataRequests(for: pending.identity.connectionAttemptID)
            return true
        case .awaitingSoftwareSnapshot:
            cubeResetReadbackWorkItem?.cancel()
            cubeResetReadbackWorkItem = nil
            let solvedFacelets = CubeSurface.solved(size: value.count == 24 ? 2 : puzzleSize)
            let reference = SmartCubeSoftwareResetReference(
                deviceID: pending.identity.deviceID,
                expectedDeviceFacelets: value,
                localFacelets: solvedFacelets
            )
            softwareResetReferences[pending.identity.deviceID] = reference
            pendingCubeReset = nil
            facelets = solvedFacelets
            canonicalFeed.acceptAuthoritativeSnapshot(solvedFacelets, stateChanged: true)
            cubeStateRevision += 1
            shouldAcceptNextFaceletsSnapshot = false
            isLocalFaceletStateLocked = true
            #if DEBUG
            SmartCubeDiagnostics.shared.trace("moyu.reference.created", attemptID: pending.identity.connectionAttemptID, deviceID: pending.identity.deviceID, detail: "serial=\(serial) relationship=authoritative-baseline-to-local-solved")
            SmartCubeDiagnostics.shared.trace("canonical.trust.changed", attemptID: pending.identity.connectionAttemptID, deviceID: pending.identity.deviceID, detail: "trusted=\(canonicalFeed.isStateTrusted) source=moyu-software-reference")
            SmartCubeDiagnostics.shared.trace("ui.facelets.published", attemptID: pending.identity.connectionAttemptID, deviceID: pending.identity.deviceID, detail: "revision=\(cubeStateRevision) source=moyu-software-reference")
            #endif
            appendLog("Reset", "Software reset reference established from authoritative device snapshot")
            sendPostResetMetadataRequests(for: pending.identity.connectionAttemptID)
            return true
        }
    }

    private func scheduleHistoryRetry() {
        guard historyRetryWorkItem == nil, let parser else { return }
        let generation = parserGeneration
        let work = DispatchWorkItem { [weak self, parser] in
            guard let self, self.parserGeneration == generation else { return }
            self.historyRetryWorkItem = nil
            self.parserQueue.async { [weak self, parser] in
                let events = parser.retryPendingGANHistory()
                let needsRetry = parser.hasRetryableGANHistory
                DispatchQueue.main.async {
                    guard let self, self.parserGeneration == generation else { return }
                    for event in events { self.apply(event) }
                    if needsRetry { self.scheduleHistoryRetry() }
                }
            }
        }
        historyRetryWorkItem = work
        // A lost-response retry, never a delay before the initial gap request.
        // The parser caps attempts per unresolved window and throttles duplicate events.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func enqueueMove(_ move: SmartCubeMoveEvent) {
        guard coalesceSliceMoves else {
            emitMove(move)
            return
        }

        pendingMoveFlushWorkItem?.cancel()

        guard let previousMove = pendingMoveEvent else {
            pendingMoveEvent = move
            schedulePendingMoveFlush()
            return
        }

        if let sliceMove = coalescedSliceMove(first: previousMove, second: move) {
            #if DEBUG
            SmartCubeDiagnostics.shared.mark("coalesce.merge", id: sliceMove.id, detail: "\(previousMove.move)+\(move.move)->\(sliceMove.move) parents=\(previousMove.id),\(move.id)")
            #endif
            pendingMoveEvent = nil
            emitMove(sliceMove, logTitle: "Slice", logDetail: "\(sliceMove.move) from paired outer moves")
            return
        }

        emitMove(previousMove)
        pendingMoveEvent = move
        schedulePendingMoveFlush()
    }

    private func schedulePendingMoveFlush() {
        schedulePendingMoveFlush(after: 0.26)
    }

    private func holdPendingMoveFlush(seconds: TimeInterval) {
        guard pendingMoveEvent != nil else { return }
        pendingMoveFlushWorkItem?.cancel()
        schedulePendingMoveFlush(after: seconds)
        if protocolDebugLogging {
            appendProtocolLog("Hold pending move", String(format: "%.2fs", seconds))
        }
    }

    private func schedulePendingMoveFlush(after delay: TimeInterval) {
        #if DEBUG
        SmartCubeDiagnostics.shared.mark("coalesce.pending", id: pendingMoveEvent?.id, detail: "scheduled=\(delay)s")
        #endif
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushPendingMove()
        }
        pendingMoveFlushWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func flushPendingMove() {
        pendingMoveFlushWorkItem?.cancel()
        pendingMoveFlushWorkItem = nil
        guard let pendingMove = pendingMoveEvent else { return }
        #if DEBUG
        SmartCubeDiagnostics.shared.mark("coalesce.flush", id: pendingMove.id)
        #endif
        pendingMoveEvent = nil
        emitMove(pendingMove)
    }

    private func cancelPendingMove() {
        pendingMoveFlushWorkItem?.cancel()
        pendingMoveFlushWorkItem = nil
        pendingMoveEvent = nil
    }

    private func emitMove(_ move: SmartCubeMoveEvent, logTitle: String = "Move", logDetail: String? = nil) {
        latestMove = move
        moveHistory.append(move)
        if let currentFacelets = facelets, let updatedFacelets = Self.facelets(currentFacelets, applying: move.move) {
            facelets = updatedFacelets
            if let connectionDeviceID, var reference = softwareResetReferences[connectionDeviceID] {
                if reference.apply(move.move) {
                    softwareResetReferences[connectionDeviceID] = reference
                } else {
                    softwareResetReferences[connectionDeviceID] = nil
                    isLocalFaceletStateLocked = false
                    canonicalFeed.breakContinuity(.resync, facelets: updatedFacelets)
                    #if DEBUG
                    SmartCubeDiagnostics.shared.trace("moyu.reference.discarded", attemptID: connectionAttemptID, deviceID: connectionDeviceID, detail: "reason=move-application-failed canonicalTrusted=\(canonicalFeed.isStateTrusted)")
                    #endif
                }
            }
            #if DEBUG
            SmartCubeDiagnostics.shared.mark("canonical.publish", id: move.id, detail: "\(move.move) source=\(move.timestampSource) trusted=\(canonicalFeed.isStateTrusted)")
            #endif
            // Synchronous, ordered delivery after the paired state is committed.
            // Unlike SwiftUI onChange, this does not collapse packet/history bursts.
            canonicalFeed.send(move: move, facelets: updatedFacelets)
            #if DEBUG
            SmartCubeDiagnostics.shared.traceMove("move.canonical.published", move: move, attemptID: connectionAttemptID, deviceID: connectionDeviceID, accepted: true, detail: "revision=\(cubeStateRevision) trusted=\(canonicalFeed.isStateTrusted)")
            SmartCubeDiagnostics.shared.traceMove("ui.facelets.published", move: move, attemptID: connectionAttemptID, deviceID: connectionDeviceID, accepted: true, detail: "source=move canonicalSequence=\(canonicalFeed.sequence)")
            #endif
        } else {
            #if DEBUG
            let reason = facelets == nil ? "facelets-unavailable" : "move-application-failed"
            SmartCubeDiagnostics.shared.traceMove("move.withheld", move: move, attemptID: connectionAttemptID, deviceID: connectionDeviceID, accepted: false, detail: "reason=\(reason) canonicalTrusted=\(canonicalFeed.isStateTrusted)")
            #endif
        }
        trimMoveHistoryIfNeeded()
        if protocolDebugLogging {
            appendProtocolLog(logTitle, logDetail ?? move.move)
        }
    }

    private func coalescedSliceMove(first previousMove: SmartCubeMoveEvent, second move: SmartCubeMoveEvent) -> SmartCubeMoveEvent? {
        guard movesAreCloseEnoughForSlice(previousMove, move) else { return nil }
        guard let sliceMoveName = Self.sliceMoveName(first: previousMove.move, second: move.move) else { return nil }

        return SmartCubeMoveEvent(
            move: sliceMoveName,
            serial: move.serial,
            face: nil,
            direction: nil,
            localTimestamp: move.localTimestamp,
            cubeTimestampMilliseconds: move.cubeTimestampMilliseconds,
            timestampSource: move.timestampSource
        )
    }

    private func movesAreCloseEnoughForSlice(_ first: SmartCubeMoveEvent, _ second: SmartCubeMoveEvent) -> Bool {
        if let firstTimestamp = first.cubeTimestampMilliseconds,
           let secondTimestamp = second.cubeTimestampMilliseconds {
            return abs(secondTimestamp - firstTimestamp) <= 360
        }
        return second.localTimestamp.timeIntervalSince(first.localTimestamp) <= 0.36
    }

    private func trimMoveHistoryIfNeeded() {
        if moveHistory.count > 120 {
            moveHistory.removeFirst(moveHistory.count - 120)
        }
    }

    private func appendLog(_ title: String, _ detail: String) {
        logEntries.insert(SmartCubeLogEntry(date: Date(), title: title, detail: detail), at: 0)
        if logEntries.count > 240 {
            logEntries.removeLast(logEntries.count - 240)
        }
    }

    private func appendProtocolLog(_ title: String, _ detail: String) {
        protocolLogEntries.insert(SmartCubeLogEntry(date: Date(), title: title, detail: detail), at: 0)
        if protocolLogEntries.count > 200 {
            protocolLogEntries.removeLast(protocolLogEntries.count - 200)
        }
    }

    private func refreshIdentity() {
        identity = SmartCubeIdentity.resolve(
            advertisedName: connectedDeviceName,
            protocolFamily: connectedProtocol,
            protocolConfirmed: isConnectedProtocolConfirmed,
            protocolInfo: protocolIdentityInfo,
            serviceIdentifiers: discoveredServiceUUIDs
        )
        if let connectionDeviceID, let identity {
            SavedSmartCubeDevices.shared.remember(
                id: connectionDeviceID, identity: identity, fallbackName: connectedDeviceName
            )

        }
    }

    #if DEBUG
    var debugIdentityDump: String {
        guard let identity else { return "No connected identity" }
        return [
            "Advertised name: \(identity.advertisedName ?? "Unknown")",
            "Manufacturer: \(identity.manufacturer.rawValue)",
            "Protocol family: \(identity.protocolFamily.rawValue)",
            "Protocol model ID: \(identity.protocolModelIdentifier ?? "Unavailable")",
            "Hardware version: \(identity.hardwareVersion ?? "Unavailable")",
            "Firmware/software version: \(identity.firmwareVersion ?? "Unavailable")",
            "Resolved consumer model: \(identity.resolvedModel ?? "Unknown")",
            "Puzzle: \(identity.puzzleKind == .twoByTwo ? "2x2" : "3x3")",
            "Confidence: \(identity.identificationConfidence.rawValue)",
            "Services: \(identity.serviceIdentifiers.isEmpty ? "None" : identity.serviceIdentifiers.joined(separator: ", "))",
            "Product date: \(identity.productDate ?? "Unavailable")"
        ].joined(separator: "\n")
    }
    #endif

    private static func hexString(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private static func propertySummary(_ properties: CBCharacteristicProperties) -> String {
        var labels: [String] = []
        if properties.contains(.read) { labels.append("read") }
        if properties.contains(.write) { labels.append("write") }
        if properties.contains(.writeWithoutResponse) { labels.append("writeNoRsp") }
        if properties.contains(.notify) { labels.append("notify") }
        if properties.contains(.indicate) { labels.append("indicate") }
        if properties.contains(.broadcast) { labels.append("broadcast") }
        return labels.isEmpty ? "none" : labels.joined(separator: ",")
    }

    private func recordTransportPacket(_ data: Data, from characteristic: CBCharacteristic) {
        guard protocolDebugLogging else { return }

        let uuid = characteristic.uuid.uuidString
        if characteristic.isNotifying {
            packetCountsByCharacteristic[uuid, default: 0] += 1
        }

        if sampledCharacteristicUUIDs.insert(uuid).inserted {
            let service = characteristic.service?.uuid.uuidString ?? "Unknown service"
            appendProtocolLog(
                "BLE sample \(uuid)",
                "\(service) [\(Self.propertySummary(characteristic.properties))] \(Self.hexString([UInt8](data)))"
            )
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(packetRateWindowStart)
        guard elapsed >= 1 else { return }

        let rates = packetCountsByCharacteristic
            .sorted { $0.key < $1.key }
            .map { uuid, count in
                String(format: "%@ %.1f/s", uuid, Double(count) / elapsed)
            }
            .joined(separator: ", ")
        appendProtocolLog("BLE notify rates", rates.isEmpty ? "No notifications" : rates)
        packetRateWindowStart = now
        packetCountsByCharacteristic = [:]
    }

    nonisolated private static func isPlausibleFacelets(_ value: String) -> Bool {
        let characters = Array(value)
        let stickersPerFace: Int
        switch characters.count {
        case 24: stickersPerFace = 4
        case 54: stickersPerFace = 9
        default: return false
        }
        let allowed = Set("URFDLB")
        guard characters.allSatisfy({ allowed.contains($0) }) else { return false }
        return Array("URFDLB").allSatisfy {
            face in characters.filter { $0 == face }.count == stickersPerFace
        }
    }

    private static func isPlausibleHardware(_ value: String) -> Bool {
        guard let hwRange = value.range(of: " HW "), let swRange = value.range(of: " SW "), hwRange.upperBound < swRange.lowerBound else {
            return false
        }
        let model = String(value[..<hwRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, model.contains(where: { $0.isLetter || $0.isNumber }) else { return false }
        guard hardwareVersionIsPlausible(String(value[hwRange.upperBound..<swRange.lowerBound])) else { return false }
        let swSuffix = value[swRange.upperBound...].split(separator: " ").first.map(String.init) ?? ""
        guard hardwareVersionIsPlausible(swSuffix) else { return false }
        return true
    }

    private static func hardwareVersionIsPlausible(_ value: String) -> Bool {
        let components = value.split(separator: ".")
        guard components.count == 2, let major = Int(components[0]), let minor = Int(components[1]) else { return false }
        return (0...30).contains(major) && (0...255).contains(minor)
    }

    nonisolated private struct Sticker: Hashable {
        var x: Int
        var y: Int
        var z: Int
        var nx: Int
        var ny: Int
        var nz: Int
    }

    private static func sliceMoveName(first: String, second: String) -> String? {
        switch (first, second) {
        case ("R'", "L"), ("L", "R'"):
            return "M'"
        case ("R", "L'"), ("L'", "R"):
            return "M"
        case ("U'", "D"), ("D", "U'"):
            return "E"
        case ("U", "D'"), ("D'", "U"):
            return "E'"
        case ("F", "B'"), ("B'", "F"):
            return "S'"
        case ("F'", "B"), ("B", "F'"):
            return "S"
        default:
            return nil
        }
    }

    private static func inverseMove(_ move: String) -> String {
        if move.hasSuffix("'") { return String(move.dropLast()) }
        if move.hasSuffix("2") { return move }
        return move + "'"
    }

    nonisolated static func facelets(_ value: String, applying move: String) -> String? {
        guard isPlausibleFacelets(value) else { return nil }
        if value.count == 24 {
            return CubeLayerTurn(move)?.applying(to: value, size: 2)
        }
        guard let face = move.first else { return nil }
        let turns: Int
        if move.hasSuffix("2") {
            turns = 2
        } else if move.contains("'") {
            turns = 3
        } else {
            turns = 1
        }
        var result = value
        for _ in 0..<turns {
            guard let next = faceletsAfterClockwiseTurn(result, move: face) else { return nil }
            result = next
        }
        return result
    }

    nonisolated private static func faceletsAfterClockwiseTurn(_ value: String, move: Character) -> String? {
        var output = Array(value)
        let input = output
        for stickerIndex in 0..<54 {
            let sticker = sticker(for: stickerIndex)
            guard stickerIsOnLayer(sticker, move: move) else { continue }
            let rotated = rotate(sticker, move: move)
            guard let target = index(for: rotated) else { return nil }
            output[target] = input[stickerIndex]
        }
        return String(output)
    }

    nonisolated private static func stickerIsOnLayer(_ sticker: Sticker, move: Character) -> Bool {
        switch move {
        case "U": return sticker.y == 1
        case "R": return sticker.x == 1
        case "F": return sticker.z == 1
        case "D": return sticker.y == -1
        case "L": return sticker.x == -1
        case "B": return sticker.z == -1
        case "M": return sticker.x == 0
        case "E": return sticker.y == 0
        case "S": return sticker.z == 0
        default: return false
        }
    }

    nonisolated private static func rotate(_ sticker: Sticker, move: Character) -> Sticker {
        var sticker = sticker
        switch move {
        case "U":
            (sticker.x, sticker.z) = (-sticker.z, sticker.x)
            (sticker.nx, sticker.nz) = (-sticker.nz, sticker.nx)
        case "D", "E":
            (sticker.x, sticker.z) = (sticker.z, -sticker.x)
            (sticker.nx, sticker.nz) = (sticker.nz, -sticker.nx)
        case "F", "S":
            (sticker.x, sticker.y) = (sticker.y, -sticker.x)
            (sticker.nx, sticker.ny) = (sticker.ny, -sticker.nx)
        case "B":
            (sticker.x, sticker.y) = (-sticker.y, sticker.x)
            (sticker.nx, sticker.ny) = (-sticker.ny, sticker.nx)
        case "R":
            (sticker.y, sticker.z) = (sticker.z, -sticker.y)
            (sticker.ny, sticker.nz) = (sticker.nz, -sticker.ny)
        case "L", "M":
            (sticker.y, sticker.z) = (-sticker.z, sticker.y)
            (sticker.ny, sticker.nz) = (-sticker.nz, sticker.ny)
        default:
            break
        }
        return sticker
    }

    nonisolated private static func sticker(for index: Int) -> Sticker {
        let face = index / 9
        let offset = index % 9
        let row = offset / 3
        let column = offset % 3
        switch face {
        case 0:
            return Sticker(x: column - 1, y: 1, z: row - 1, nx: 0, ny: 1, nz: 0)
        case 1:
            return Sticker(x: 1, y: 1 - row, z: 1 - column, nx: 1, ny: 0, nz: 0)
        case 2:
            return Sticker(x: column - 1, y: 1 - row, z: 1, nx: 0, ny: 0, nz: 1)
        case 3:
            return Sticker(x: column - 1, y: -1, z: 1 - row, nx: 0, ny: -1, nz: 0)
        case 4:
            return Sticker(x: -1, y: 1 - row, z: column - 1, nx: -1, ny: 0, nz: 0)
        default:
            return Sticker(x: 1 - column, y: 1 - row, z: -1, nx: 0, ny: 0, nz: -1)
        }
    }

    nonisolated private static func index(for sticker: Sticker) -> Int? {
        switch (sticker.nx, sticker.ny, sticker.nz) {
        case (0, 1, 0):
            return (sticker.z + 1) * 3 + (sticker.x + 1)
        case (1, 0, 0):
            return 9 + (1 - sticker.y) * 3 + (1 - sticker.z)
        case (0, 0, 1):
            return 18 + (1 - sticker.y) * 3 + (sticker.x + 1)
        case (0, -1, 0):
            return 27 + (1 - sticker.z) * 3 + (sticker.x + 1)
        case (-1, 0, 0):
            return 36 + (1 - sticker.y) * 3 + (sticker.z + 1)
        case (0, 0, -1):
            return 45 + (1 - sticker.y) * 3 + (1 - sticker.x)
        default:
            return nil
        }
    }

    private static func manufacturerInfo(from data: Data?) -> (hex: String?, mac: String?, salt: [UInt8]?) {
        guard let data, data.count >= 8 else { return (nil, nil, nil) }
        let bytes = [UInt8](data)
        let hex = hexString(bytes)
        let payload = bytes.count >= 11 ? Array(bytes.dropFirst(2).prefix(9)) : bytes
        guard payload.count >= 6 else { return (hex, nil, nil) }
        let salt = Array(payload.suffix(6))
        let mac = salt.reversed().map { String(format: "%02X", $0) }.joined(separator: ":")
        return (hex, mac, salt)
    }

}

extension SmartCubePeripheralSession {
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard connectedPeripheral?.identifier == peripheral.identifier,
              connectionDeviceID == peripheral.identifier,
              connectionAttemptID != nil else {
            #if DEBUG
            SmartCubeDiagnostics.shared.trace("ble.callback.rejected", attemptID: connectionAttemptID, deviceID: peripheral.identifier, detail: "callback=didConnect reason=stale-attempt-or-device")
            #endif
            return
        }
        connectionState = .connected
        connectionTimeout?.cancel()
        connectionTimeout = nil
        captureEvent("ble connected; discovering services")
        #if DEBUG
        SmartCubeDiagnostics.shared.trace("ble.transport.connected", attemptID: connectionAttemptID, deviceID: peripheral.identifier, detail: "name=\(peripheral.name ?? "unknown")")
        #endif
        appendLog("Connect", "\(peripheral.name ?? peripheral.identifier.uuidString) as \(pendingProtocolHint.rawValue)")
        // Discover every service in the lab. GAN is parsed specially below; MoYu/Giiker need full UUID evidence first.
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard connectedPeripheral?.identifier == peripheral.identifier,
              connectionDeviceID == peripheral.identifier else { return }
        connectionState = .failed(
            error.map { appUserFacingErrorMessage($0, languageCode: currentAppLanguageCode()) }
                ?? "Failed to connect"
        )
        connectionTimeout?.cancel()
        connectionTimeout = nil
        #if DEBUG
        SmartCubeDiagnostics.shared.trace("ble.connect.failed", attemptID: connectionAttemptID, deviceID: peripheral.identifier, detail: "reason=\(error?.localizedDescription ?? "unknown")")
        #endif
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error {
            appendLog("Disconnect", error.localizedDescription)
        }
        if connectedPeripheral?.identifier == peripheral.identifier {
            #if DEBUG
            SmartCubeDiagnostics.shared.trace("ble.disconnected", attemptID: connectionAttemptID, deviceID: peripheral.identifier, detail: "reason=\(error?.localizedDescription ?? "none")")
            #endif
            disconnectConnectedPeripheralIfNeeded()
            resetSessionData(keepLogs: true)
            connectionState = .disconnected

        }
    }
}

extension SmartCubePeripheralSession: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard connectedPeripheral?.identifier == peripheral.identifier,
              connectionDeviceID == peripheral.identifier,
              connectionAttemptID != nil,
              isConnected else { return }
        if let error {
            connectionState = .failed(appUserFacingErrorMessage(error, languageCode: currentAppLanguageCode()))
            return
        }
        let services = peripheral.services ?? []
        discoveredServiceUUIDs = services.map { $0.uuid.uuidString }.sorted()
        captureEvent("services \(discoveredServiceUUIDs.joined(separator: ", "))")
        appendLog("Services", discoveredServiceUUIDs.isEmpty ? "None" : discoveredServiceUUIDs.joined(separator: ", "))

        var foundKnownProtocol = false
        for service in services {
            switch service.uuid {
            case ganGen4ServiceUUID:
                foundKnownProtocol = true
                connectedProtocol = .ganGen4
                let resolvedPuzzle = SmartCubePuzzleKind.resolve(
                    advertisedName: connectedDeviceName,
                    protocolModelIdentifier: protocolIdentityInfo?.modelIdentifier
                )
                setParser(GANCubeProtocolParser(kind: .ganGen4, puzzleSize: resolvedPuzzle.size))
                if resolvedPuzzle == .twoByTwo,
                   let salt = discoveredSaltByID[peripheral.identifier] {
                    cipher = GANCubeCipher(
                        rootKey: [0x58, 0x98, 0x61, 0xFC, 0x1F, 0xEC, 0xD7, 0x60, 0x9F, 0x85, 0xD3, 0x62, 0xBE, 0x37, 0x17, 0x2C],
                        rootIV: [0x7F, 0x61, 0xD0, 0x52, 0x75, 0xC1, 0x39, 0x52, 0x08, 0x2E, 0x54, 0x1D, 0x8A, 0x78, 0x63, 0x4D],
                        salt: salt
                    )
                    appendLog("GAN 251 cipher", "Using ProtocolV3-2 key with manufacturer MAC salt")
                }
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("protocol.confirmed", attemptID: connectionAttemptID, deviceID: connectionDeviceID, detail: "protocol=ganGen4")
                #endif
                // GAN16UI is newer than the public Gen4 references. Enumerate the
                // complete service so any additional notify stream remains visible.
                peripheral.discoverCharacteristics(nil, for: service)
            case ganGen3ServiceUUID:
                foundKnownProtocol = true
                connectedProtocol = .ganGen3
                setParser(GANCubeProtocolParser(kind: .ganGen3, puzzleSize: 3))
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("protocol.confirmed", attemptID: connectionAttemptID, deviceID: connectionDeviceID, detail: "protocol=ganGen3")
                #endif
                peripheral.discoverCharacteristics([ganGen3CommandCharacteristicUUID, ganGen3StateCharacteristicUUID], for: service)
            case ganGen2ServiceUUID:
                foundKnownProtocol = true
                connectedProtocol = .ganGen2
                setParser(GANCubeProtocolParser(kind: .ganGen2, puzzleSize: 3))
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("protocol.confirmed", attemptID: connectionAttemptID, deviceID: connectionDeviceID, detail: "protocol=ganGen2")
                #endif
                peripheral.discoverCharacteristics([ganGen2CommandCharacteristicUUID, ganGen2StateCharacteristicUUID], for: service)
            case moyuMainServiceUUID:
                foundKnownProtocol = true
                connectedProtocol = .moyu
                let resolvedPuzzle = SmartCubePuzzleKind.resolve(
                    advertisedName: connectedDeviceName,
                    protocolModelIdentifier: protocolIdentityInfo?.modelIdentifier
                )
                setParser(GANCubeProtocolParser(kind: .moyu, puzzleSize: resolvedPuzzle.size))
                #if DEBUG
                SmartCubeDiagnostics.shared.trace("protocol.confirmed", attemptID: connectionAttemptID, deviceID: connectionDeviceID, detail: "protocol=moyu")
                #endif
                if let salt = discoveredSaltByID[peripheral.identifier] {
                    cipher = GANCubeCipher(
                        rootKey: [0x15, 0x77, 0x3A, 0x5C, 0x67, 0x0E, 0x2D, 0x1F, 0x17, 0x67, 0x2A, 0x13, 0x9B, 0x67, 0x52, 0x57],
                        rootIV: [0x11, 0x23, 0x26, 0x25, 0x86, 0x2A, 0x2C, 0x3B, 0x55, 0x06, 0x7F, 0x31, 0x7E, 0x67, 0x21, 0x57],
                        salt: salt
                    )
                    appendLog("MoYu cipher", "Using V10/WCU key with manufacturer MAC salt")
                } else {
                    appendLog("MoYu cipher", "Missing manufacturer MAC salt; cannot decrypt V10 packets")
                }
                peripheral.discoverCharacteristics([moyuNotifyCharacteristicUUID, moyuWriteCharacteristicUUID], for: service)
            case qiyiServiceUUID where pendingProtocolHint == .qiyi:
                foundKnownProtocol = true
                connectedProtocol = .qiyi
                let mac = QiYiCubeProtocolParser.resolvedMAC(
                    manufacturerDataHex: discoveredDevices.first(where: { $0.id == peripheral.identifier })?.manufacturerDataHex,
                    deviceName: connectedDeviceName
                )
                qiyiParser = mac.flatMap { QiYiCubeProtocolParser(macAddress: $0) }
                setParser(nil)
                if qiyiParser == nil {
                    appendLog("QiYi", "Cube address unavailable; cannot send protocol hello")
                }
                peripheral.discoverCharacteristics([qiyiStateCharacteristicUUID], for: service)
            default:
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
        if !foundKnownProtocol {
            connectedProtocol = pendingProtocolHint
        }
        isConnectedProtocolConfirmed = foundKnownProtocol
        refreshIdentity()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard connectedPeripheral?.identifier == peripheral.identifier,
              connectionDeviceID == peripheral.identifier,
              let attemptID = connectionAttemptID,
              isConnected else { return }
        if let error {
            appendLog("Characteristics", error.localizedDescription)
            return
        }
        let characteristics = service.characteristics ?? []
        discoveredCharacteristicUUIDs = (discoveredCharacteristicUUIDs + characteristics.map { $0.uuid.uuidString }).uniqued().sorted()
        captureEvent("characteristics service=\(service.uuid.uuidString) \(characteristics.map { "\($0.uuid.uuidString)[\(Self.propertySummary($0.properties))]" }.joined(separator: ", "))")

        for characteristic in characteristics {
            appendLog("Characteristic", "\(characteristic.uuid.uuidString) [\(Self.propertySummary(characteristic.properties))]")
            switch characteristic.uuid {
            case ganGen4CommandCharacteristicUUID, ganGen3CommandCharacteristicUUID, ganGen2CommandCharacteristicUUID, moyuWriteCharacteristicUUID:
                commandCharacteristic = characteristic
                appendLog("Command characteristic", characteristic.uuid.uuidString)
            case ganGen4StateCharacteristicUUID, ganGen3StateCharacteristicUUID, ganGen2StateCharacteristicUUID, moyuNotifyCharacteristicUUID:
                stateCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                appendLog("State characteristic", characteristic.uuid.uuidString)
            case qiyiStateCharacteristicUUID where connectedProtocol == .qiyi:
                commandCharacteristic = characteristic
                stateCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                appendLog("QiYi state/command characteristic", characteristic.uuid.uuidString)
            default:
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic)
                    appendLog("Read characteristic", characteristic.uuid.uuidString)
                }
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: characteristic)
                    appendLog("Notify characteristic", characteristic.uuid.uuidString)
                }
            }
        }

        if commandCharacteristic != nil, stateCharacteristic != nil {
            #if DEBUG
            SmartCubeDiagnostics.shared.trace("transport.ready", attemptID: attemptID, deviceID: connectionDeviceID, detail: "command=true state=true protocol=\(connectedProtocol.rawValue)")
            #endif
            if continuePendingCubeResetIfPossible() {
                return
            }
            bootstrapWhenSubscribed()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard connectedPeripheral?.identifier == peripheral.identifier,
              connectionDeviceID == peripheral.identifier,
              connectionAttemptID != nil,
              isConnected else {
            #if DEBUG
            SmartCubeDiagnostics.shared.trace("ble.callback.rejected", attemptID: connectionAttemptID, deviceID: peripheral.identifier, detail: "callback=didUpdateValue reason=stale-attempt-device-or-disconnected")
            #endif
            return
        }
        if let error {
            captureEvent("rx error char=\(characteristic.uuid.uuidString) detail=\(error.localizedDescription)")
            appendLog("Notify error", error.localizedDescription)
            return
        }
        guard let data = characteristic.value else { return }
        recordTransportPacket(data, from: characteristic)
        handleStateData(data, characteristic: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard connectedPeripheral?.identifier == peripheral.identifier,
              connectionDeviceID == peripheral.identifier,
              connectionAttemptID != nil,
              isConnected else { return }
        if characteristic.uuid == moyuNotifyCharacteristicUUID,
           protocolDebugLogging,
           identity?.protocolModelIdentifier == "WCU_MY22" {
            appendProtocolLog(
                "WCU_MY22 notify",
                error.map { "failed: \($0.localizedDescription)" }
                    ?? "enabled \(characteristic.isNotifying), char \(characteristic.uuid.uuidString)"
            )
        }
        if let error {
            appendLog("Notify state", "\(characteristic.uuid.uuidString): \(error.localizedDescription)")
            captureEvent("notify char=\(characteristic.uuid.uuidString) error=\(error.localizedDescription)")
            return
        }
        captureEvent("notify char=\(characteristic.uuid.uuidString) active=\(characteristic.isNotifying)")
        appendLog("Notify state", "\(characteristic.uuid.uuidString): \(characteristic.isNotifying ? "active" : "inactive")")
        bootstrapWhenSubscribed()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard connectedPeripheral?.identifier == peripheral.identifier,
              connectionDeviceID == peripheral.identifier,
              connectionAttemptID != nil,
              isConnected else { return }
        captureEvent(
            "tx callback char=\(characteristic.uuid.uuidString) result=\(error.map { "error: \($0.localizedDescription)" } ?? "write completed")"
        )
        guard characteristic.uuid == commandCharacteristic?.uuid,
              var pending = pendingCubeReset,
              pending.phase == .awaitingHardwareWrite,
              pending.identity.matches(
                connectionAttemptID: connectionAttemptID,
                deviceID: connectionDeviceID
              ) else { return }
        if let error {
            appendLog("Write error", error.localizedDescription)
            #if DEBUG
            SmartCubeDiagnostics.shared.trace("gan.reset.write.failed", attemptID: pending.identity.connectionAttemptID, deviceID: pending.identity.deviceID, detail: "reason=\(error.localizedDescription)")
            #endif
            failPendingCubeReset(
                resetID: pending.identity.id,
                disposition: .restorePreviousState,
                message: "Device reset command failed before state changed"
            )
            return
        }
        pending.phase = .awaitingHardwareSnapshot
        pendingCubeReset = pending
        #if DEBUG
        SmartCubeDiagnostics.shared.trace("gan.reset.write.succeeded", attemptID: pending.identity.connectionAttemptID, deviceID: pending.identity.deviceID)
        #endif
        requestHardwareResetReadback(for: pending.identity.id)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
#endif

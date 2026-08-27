#if os(iOS)
import Foundation
import CoreBluetooth
import Combine

struct SmartCubeDiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let protocolHint: SmartCubeProtocolKind
    let advertisedServices: [String]
    let manufacturerDataHex: String?
    let macAddress: String?

    var hasEncryptionSalt: Bool { macAddress != nil }
}

enum SmartCubeProtocolKind: String, CaseIterable, Equatable {
    case ganGen2 = "GAN Gen2"
    case ganGen3 = "GAN Gen3"
    case ganGen4 = "GAN Gen4"
    case moyu = "MoYu/WCU"
    case giiker = "Giiker"
    case unknown = "Unknown"
}

enum SmartCubeConnectionState: Equatable {
    case disconnected
    case bluetoothUnavailable
    case unauthorized
    case scanning
    case connecting
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .bluetoothUnavailable: return "Bluetooth unavailable"
        case .unauthorized: return "Bluetooth unauthorized"
        case .scanning: return "Scanning"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .failed(let message): return "Failed: \(message)"
        }
    }
}

struct SmartCubeMoveEvent: Identifiable, Equatable {
    let id = UUID()
    let move: String
    let serial: Int?
    let face: Int?
    let direction: Int?
    let localTimestamp: Date
    let cubeTimestampMilliseconds: Int?
}

struct SmartCubeLogEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let title: String
    let detail: String
}

struct SmartCubeGyroState: Equatable {
    let x: Double
    let y: Double
    let z: Double
    let w: Double
    let velocityX: Double?
    let velocityY: Double?
    let velocityZ: Double?

    init(
        x: Double,
        y: Double,
        z: Double,
        w: Double,
        velocityX: Double? = nil,
        velocityY: Double? = nil,
        velocityZ: Double? = nil
    ) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.velocityZ = velocityZ
    }

    var summary: String {
        let quaternion = String(format: "x %.2f y %.2f z %.2f w %.2f", x, y, z, w)
        guard let velocityX, let velocityY, let velocityZ else { return quaternion }
        return quaternion + String(format: " v %.0f %.0f %.0f", velocityX, velocityY, velocityZ)
    }
}

@MainActor
final class SmartCubeGyroFeed {
    typealias Observer = (SmartCubeGyroState?) -> Void

    private var observers: [UUID: Observer] = [:]
    private(set) var latestState: SmartCubeGyroState?

    @discardableResult
    func addObserver(_ observer: @escaping Observer) -> UUID {
        let id = UUID()
        observers[id] = observer
        observer(latestState)
        return id
    }

    func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    func send(_ state: SmartCubeGyroState?) {
        latestState = state
        for observer in observers.values {
            observer(state)
        }
    }
}

final class SmartCubeBluetoothManager: NSObject, ObservableObject {
    static let shared = SmartCubeBluetoothManager()

    @Published private(set) var connectionState: SmartCubeConnectionState = .disconnected
    @Published private(set) var discoveredDevices: [SmartCubeDiscoveredDevice] = []
    @Published private(set) var connectedDeviceName: String?
    @Published private(set) var connectedProtocol: SmartCubeProtocolKind = .unknown
    @Published private(set) var connectedMACAddress: String?
    @Published private(set) var discoveredServiceUUIDs: [String] = []
    @Published private(set) var discoveredCharacteristicUUIDs: [String] = []
    @Published private(set) var latestMove: SmartCubeMoveEvent?
    @Published private(set) var moveHistory: [SmartCubeMoveEvent] = []
    @Published private(set) var facelets: String?
    @Published private(set) var cubeStateRevision = 0
    private(set) var gyroState: SmartCubeGyroState?
    let gyroFeed = SmartCubeGyroFeed()
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var hardwareSummary: String?
    @Published private(set) var logEntries: [SmartCubeLogEntry] = []
    @Published private(set) var protocolLogEntries: [SmartCubeLogEntry] = []
    @Published var protocolDebugLogging = false
    @Published var coalesceSliceMoves = false
    @Published var verbosePacketLogging = false

    static let solvedFacelets = "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB"

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

    private lazy var centralManager = CBCentralManager(delegate: self, queue: nil)
    private let parserQueue = DispatchQueue(label: "CubeFlow.SmartCube.Parser", qos: .userInteractive)
    private var isPrepared = false
    private var discoveredPeripheralsByID: [UUID: CBPeripheral] = [:]
    private var discoveredSaltByID: [UUID: [UInt8]] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var pendingProtocolHint: SmartCubeProtocolKind = .unknown
    private var commandCharacteristic: CBCharacteristic?
    private var stateCharacteristic: CBCharacteristic?
    private var parser: GANCubeProtocolParser?
    private var parserGeneration = 0
    private var cipher: GANCubeCipher?
    private var isLocalFaceletStateLocked = false
    private var shouldAcceptNextFaceletsSnapshot = false
    private var pendingMoveEvent: SmartCubeMoveEvent?
    private var pendingMoveFlushWorkItem: DispatchWorkItem?
    private var packetRateWindowStart = Date()
    private var packetCountsByCharacteristic: [String: Int] = [:]
    private var sampledCharacteristicUUIDs: Set<String> = []

    private override init() {
        super.init()
    }

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    func prepareIfNeeded() {
        guard !isPrepared else { return }
        isPrepared = true
        _ = centralManager
    }

    func startScanning() {
        prepareIfNeeded()
        switch centralManager.state {
        case .poweredOn:
            disconnectConnectedPeripheralIfNeeded()
            discoveredDevices = []
            discoveredPeripheralsByID = [:]
            discoveredSaltByID = [:]
            appendLog("Scan", "Looking for GAN / MoYu / Giiker smart cubes")
            connectionState = .scanning
            centralManager.scanForPeripherals(withServices: nil, options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ])
        case .unauthorized:
            connectionState = .unauthorized
        default:
            connectionState = .bluetoothUnavailable
        }
    }

    func stopScanning() {
        centralManager.stopScan()
        if case .scanning = connectionState {
            connectionState = .disconnected
        }
        appendLog("Scan", "Stopped")
    }

    func connect(to deviceID: UUID) {
        prepareIfNeeded()
        guard centralManager.state == .poweredOn else {
            connectionState = .bluetoothUnavailable
            return
        }
        guard let peripheral = discoveredPeripheralsByID[deviceID] else {
            connectionState = .failed("Device is no longer available")
            return
        }

        stopScanning()
        resetSessionData(keepLogs: true)
        connectedPeripheral = peripheral
        let selectedDevice = discoveredDevices.first(where: { $0.id == deviceID })
        pendingProtocolHint = selectedDevice?.protocolHint ?? .unknown
        connectedProtocol = pendingProtocolHint
        connectedDeviceName = selectedDevice?.name ?? peripheral.name
        connectedMACAddress = selectedDevice?.macAddress
        if let salt = discoveredSaltByID[deviceID] {
            cipher = GANCubeCipher(salt: salt)
            appendLog("MAC", connectedMACAddress ?? "Salt found in manufacturer data")
        } else {
            cipher = nil
            appendLog("MAC", "No cube MAC salt found yet; raw packets will still be logged")
        }

        connectionState = .connecting
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        stopScanning()
        disconnectConnectedPeripheralIfNeeded()
        resetSessionData(keepLogs: true)
        connectionState = .disconnected
        appendLog("Disconnect", "Smart cube disconnected")
    }

    func clearLog() {
        logEntries = []
        protocolLogEntries = []
    }

    func requestFacelets() {
        shouldAcceptNextFaceletsSnapshot = true
        sendCommand(.requestFacelets)
    }

    func requestBattery() {
        sendCommand(.requestBattery)
    }

    func requestHardware() {
        sendCommand(.requestHardware)
    }

    func resetCubeStateToSolved() {
        cancelPendingMove()
        latestMove = nil
        moveHistory = []
        facelets = Self.solvedFacelets
        cubeStateRevision += 1
        isLocalFaceletStateLocked = true
        shouldAcceptNextFaceletsSnapshot = false
        if let parser {
            parserQueue.async {
                parser.resetMoveTracking()
            }
        }
        appendLog("Reset", "Local cube state set to solved. Put the physical cube in solved state before using this.")
        appendLog("Reset", "No hardware reset command was sent; this only resets CubeFlow's local state.")
    }

    static func facelets(afterApplying algorithm: String) -> String? {
        var state = solvedFacelets
        let moves = algorithm.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !moves.isEmpty else { return nil }
        for move in moves {
            guard let next = facelets(state, applying: move) else { return nil }
            state = next
        }
        return state
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
        cipher = nil
        cancelPendingMove()
    }

    private func resetSessionData(keepLogs: Bool) {
        connectedDeviceName = nil
        connectedProtocol = .unknown
        connectedMACAddress = nil
        discoveredServiceUUIDs = []
        discoveredCharacteristicUUIDs = []
        latestMove = nil
        moveHistory = []
        facelets = nil
        cubeStateRevision += 1
        gyroState = nil
        gyroFeed.send(nil)
        batteryLevel = nil
        hardwareSummary = nil
        commandCharacteristic = nil
        stateCharacteristic = nil
        setParser(nil)
        isLocalFaceletStateLocked = false
        shouldAcceptNextFaceletsSnapshot = false
        packetRateWindowStart = Date()
        packetCountsByCharacteristic = [:]
        sampledCharacteristicUUIDs = []
        cancelPendingMove()
        if !keepLogs {
            logEntries = []
            protocolLogEntries = []
        }
    }

    private func setParser(_ newParser: GANCubeProtocolParser?) {
        parser = newParser
        parserGeneration += 1
    }

    private func updateDiscoveredDevice(_ device: SmartCubeDiscoveredDevice, peripheral: CBPeripheral, salt: [UInt8]?) {
        discoveredPeripheralsByID[device.id] = peripheral
        if let salt {
            discoveredSaltByID[device.id] = salt
        }

        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[index] = device
        } else {
            discoveredDevices.append(device)
            discoveredDevices.sort { lhs, rhs in
                if lhs.protocolHint == rhs.protocolHint { return lhs.rssi > rhs.rssi }
                return lhs.protocolHint.rawValue < rhs.protocolHint.rawValue
            }
        }
    }

    private func sendInitialRequests() {
        if connectedProtocol == .moyu {
            sendCommand(.requestHardware)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.sendCommand(.requestFacelets)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
                self?.sendCommand(.requestBattery)
            }
            return
        }

        sendCommand(.requestFacelets)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.sendCommand(.requestBattery)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            self?.sendCommand(.requestHardware)
        }
    }

    private func sendCommand(_ command: GANCubeCommand) {
        guard let commandCharacteristic, let connectedPeripheral else {
            appendLog("Command", "No writable command characteristic")
            return
        }
        guard let parser else {
            appendLog("Command", "Protocol not ready")
            return
        }
        let message = parserQueue.sync {
            parser.commandMessage(for: command)
        }
        guard let message else {
            appendLog("Command", "Unsupported command for \(connectedProtocol.rawValue)")
            return
        }
        let encrypted = cipher?.encrypt(message) ?? message
        let writeType = Self.writeType(for: command, characteristic: commandCharacteristic)
        connectedPeripheral.writeValue(Data(encrypted), for: commandCharacteristic, type: writeType)
        if protocolDebugLogging || !command.isHighFrequency {
            appendLog("Command", "\(command.label) [\(writeType == .withoutResponse ? "noRsp" : "rsp")]: \(Self.hexString(encrypted))")
        }
    }

    private static func writeType(for command: GANCubeCommand, characteristic: CBCharacteristic) -> CBCharacteristicWriteType {
        if case .requestMoveHistory = command,
           characteristic.properties.contains(.writeWithoutResponse) {
            return .withoutResponse
        }
        return .withResponse
    }

    private func handleStateData(_ data: Data, characteristic: CBCharacteristic) {
        let raw = [UInt8](data)
        if verbosePacketLogging {
            appendLog("Raw \(characteristic.uuid.uuidString)", Self.hexString(raw))
        }

        guard let parser else { return }
        guard let cipher else {
            appendLog("Decode", "Missing cube MAC salt; cannot decrypt this packet")
            return
        }
        let generation = parserGeneration
        let shouldLogPackets = verbosePacketLogging

        parserQueue.async { [weak self, parser, cipher] in
            guard let decrypted = cipher.decrypt(raw) else {
                DispatchQueue.main.async {
                    guard self?.parserGeneration == generation else { return }
                    self?.appendLog("Decode", "AES decrypt failed")
                }
                return
            }

            let parsedEvents = parser.handleStateEvent(decrypted)
            DispatchQueue.main.async {
                guard let self, self.parserGeneration == generation else { return }
                if shouldLogPackets {
                    self.appendLog("Decrypted", Self.hexString(decrypted))
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
        case .facelets(let value, let serial):
            flushPendingMove()
            guard Self.isPlausibleFacelets(value) else {
                appendLog("Ignored facelets", "serial \(serial): \(value)")
                return
            }
            if isLocalFaceletStateLocked, !shouldAcceptNextFaceletsSnapshot {
                appendLog("Ignored facelets", "local reset state is locked; tap Facelets to resync from cube")
                return
            }
            facelets = value
            cubeStateRevision += 1
            isLocalFaceletStateLocked = false
            shouldAcceptNextFaceletsSnapshot = false
            appendLog("Facelets", "serial \(serial): \(value)")
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
            appendLog("Hardware", summary)
        case .gyro(let state):
            flushPendingMove()
            gyroState = state
            gyroFeed.send(state)
            if verbosePacketLogging {
                appendLog("Gyro", state.summary)
            }
        case .debug(let title, let detail):
            if protocolDebugLogging {
                appendProtocolLog(title, detail)
            }
        case .holdPendingMove(let seconds):
            if coalesceSliceMoves {
                holdPendingMoveFlush(seconds: seconds)
            }
        case .requestMoveHistory(let startMoveCount, let numberOfMoves):
            if protocolDebugLogging {
                appendProtocolLog("GAN request history", "start \(startMoveCount), moves \(numberOfMoves)")
            }
            sendCommand(.requestMoveHistory(startMoveCount: startMoveCount, numberOfMoves: numberOfMoves))
        }
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
            cubeTimestampMilliseconds: move.cubeTimestampMilliseconds
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

    private static func isPlausibleFacelets(_ value: String) -> Bool {
        let characters = Array(value)
        guard characters.count == 54 else { return false }
        let allowed = Set("URFDLB")
        guard characters.allSatisfy({ allowed.contains($0) }) else { return false }
        return Array("URFDLB").allSatisfy { face in characters.filter { $0 == face }.count == 9 }
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

    private struct Sticker: Hashable {
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

    private static func facelets(_ value: String, applying move: String) -> String? {
        guard isPlausibleFacelets(value), let face = move.first else { return nil }
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

    private static func faceletsAfterClockwiseTurn(_ value: String, move: Character) -> String? {
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

    private static func stickerIsOnLayer(_ sticker: Sticker, move: Character) -> Bool {
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

    private static func rotate(_ sticker: Sticker, move: Character) -> Sticker {
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

    private static func sticker(for index: Int) -> Sticker {
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

    private static func index(for sticker: Sticker) -> Int? {
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

    private func protocolHint(name: String, services: [CBUUID]) -> SmartCubeProtocolKind {
        if services.contains(ganGen4ServiceUUID) { return .ganGen4 }
        if services.contains(ganGen3ServiceUUID) { return .ganGen3 }
        if services.contains(ganGen2ServiceUUID) { return .ganGen2 }
        if services.contains(moyuMainServiceUUID) { return .moyu }

        let lowercased = name.lowercased()
        if lowercased.hasPrefix("gan") || lowercased.hasPrefix("mg") || lowercased.hasPrefix("aicube") {
            return .ganGen4
        }
        if lowercased.contains("moyu") || lowercased.contains("mhd") || lowercased.contains("mhc") || lowercased.contains("wcu") || lowercased.contains("my32") || lowercased.contains("weilong") {
            return .moyu
        }
        if lowercased.contains("gi") || lowercased.contains("mi smart") || lowercased.contains("giiker") {
            return .giiker
        }
        return .unknown
    }

    private func isLikelySmartCube(name: String, services: [CBUUID], protocolHint: SmartCubeProtocolKind) -> Bool {
        if protocolHint != .unknown { return true }
        if services.contains(ganGen2ServiceUUID) || services.contains(ganGen3ServiceUUID) || services.contains(ganGen4ServiceUUID) || services.contains(moyuMainServiceUUID) { return true }
        let lowercased = name.lowercased()
        return ["cube", "gan", "moyu", "giiker", "aicube", "wcu", "mhc", "my32", "weilong"].contains { lowercased.contains($0) }
    }
}

extension SmartCubeBluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if case .bluetoothUnavailable = connectionState {
                connectionState = .disconnected
            }
        case .unauthorized:
            connectionState = .unauthorized
        case .unsupported, .poweredOff, .resetting, .unknown:
            connectionState = .bluetoothUnavailable
        @unknown default:
            connectionState = .bluetoothUnavailable
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = localName ?? peripheral.name ?? "Unknown Device"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let hint = protocolHint(name: name, services: services)
        guard isLikelySmartCube(name: name, services: services, protocolHint: hint) else { return }

        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let manufacturer = Self.manufacturerInfo(from: manufacturerData)
        let device = SmartCubeDiscoveredDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            protocolHint: hint,
            advertisedServices: services.map(\.uuidString).sorted(),
            manufacturerDataHex: manufacturer.hex,
            macAddress: manufacturer.mac
        )
        updateDiscoveredDevice(device, peripheral: peripheral, salt: manufacturer.salt)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected
        appendLog("Connect", "\(peripheral.name ?? peripheral.identifier.uuidString) as \(pendingProtocolHint.rawValue)")
        // Discover every service in the lab. GAN is parsed specially below; MoYu/Giiker need full UUID evidence first.
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .failed(
            error.map { appUserFacingErrorMessage($0, languageCode: currentAppLanguageCode()) }
                ?? "Failed to connect"
        )
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error {
            appendLog("Disconnect", error.localizedDescription)
        }
        if connectedPeripheral?.identifier == peripheral.identifier {
            disconnectConnectedPeripheralIfNeeded()
            connectionState = .disconnected
        }
    }
}

extension SmartCubeBluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            connectionState = .failed(appUserFacingErrorMessage(error, languageCode: currentAppLanguageCode()))
            return
        }
        let services = peripheral.services ?? []
        discoveredServiceUUIDs = services.map { $0.uuid.uuidString }.sorted()
        appendLog("Services", discoveredServiceUUIDs.isEmpty ? "None" : discoveredServiceUUIDs.joined(separator: ", "))

        var foundKnownProtocol = false
        for service in services {
            switch service.uuid {
            case ganGen4ServiceUUID:
                foundKnownProtocol = true
                connectedProtocol = .ganGen4
                setParser(GANCubeProtocolParser(kind: .ganGen4))
                // GAN16UI is newer than the public Gen4 references. Enumerate the
                // complete service so any additional notify stream remains visible.
                peripheral.discoverCharacteristics(nil, for: service)
            case ganGen3ServiceUUID:
                foundKnownProtocol = true
                connectedProtocol = .ganGen3
                setParser(GANCubeProtocolParser(kind: .ganGen3))
                peripheral.discoverCharacteristics([ganGen3CommandCharacteristicUUID, ganGen3StateCharacteristicUUID], for: service)
            case ganGen2ServiceUUID:
                foundKnownProtocol = true
                connectedProtocol = .ganGen2
                setParser(GANCubeProtocolParser(kind: .ganGen2))
                peripheral.discoverCharacteristics([ganGen2CommandCharacteristicUUID, ganGen2StateCharacteristicUUID], for: service)
            case moyuMainServiceUUID:
                foundKnownProtocol = true
                connectedProtocol = .moyu
                setParser(GANCubeProtocolParser(kind: .moyu))
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
            default:
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
        if !foundKnownProtocol {
            connectedProtocol = pendingProtocolHint
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            appendLog("Characteristics", error.localizedDescription)
            return
        }
        let characteristics = service.characteristics ?? []
        discoveredCharacteristicUUIDs = (discoveredCharacteristicUUIDs + characteristics.map { $0.uuid.uuidString }).uniqued().sorted()

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
            if connectedProtocol == .moyu {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.sendInitialRequests()
                }
            } else {
                sendInitialRequests()
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendLog("Notify error", error.localizedDescription)
            return
        }
        guard let data = characteristic.value else { return }
        recordTransportPacket(data, from: characteristic)
        handleStateData(data, characteristic: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendLog("Notify state", "\(characteristic.uuid.uuidString): \(error.localizedDescription)")
            return
        }
        appendLog("Notify state", "\(characteristic.uuid.uuidString): \(characteristic.isNotifying ? "active" : "inactive")")
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendLog("Write error", error.localizedDescription)
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
#endif

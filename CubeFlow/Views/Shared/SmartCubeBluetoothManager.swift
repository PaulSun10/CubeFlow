#if os(iOS)
import Foundation
import CoreBluetooth
import Combine
import UIKit

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

nonisolated enum SmartCubeProtocolKind: String, CaseIterable, Equatable {
    case ganGen2 = "GAN Gen2"
    case ganGen3 = "GAN Gen3"
    case ganGen4 = "GAN Gen4"
    case moyu = "MoYu/WCU"
    case qiyi = "QiYi"
    case giiker = "Giiker"
    case unknown = "Unknown"

    var stateResetCapability: SmartCubeStateResetCapability {
        switch self {
        case .ganGen2, .ganGen3, .ganGen4:
            return .deviceResetWithAuthoritativeReadback
        case .moyu, .qiyi, .giiker, .unknown:
            return .softwareReference
        }
    }
}

nonisolated enum SmartCubeDiscoveryClassifier {
    private static let ganTimerServices: Set<String> = [
        "FFF0",
        "0000FFF0-0000-1000-8000-00805F9B34FB"
    ]
    private static let ganGen2Service = "6E400001-B5A3-F393-E0A9-E50E24DC4179"
    private static let ganGen3Service = "8653000A-43E6-47B7-9CB0-5FC21D4AE340"
    private static let ganGen4Service = "00000010-0000-FFF7-FFF6-FFF5FFF4FFF0"
    private static let moyuService = "0783B03E-7735-B5A0-1760-A305D2795CB0"
    private static let qiyiService = "0000FFF0-0000-1000-8000-00805F9B34FB"

    private static func isQiYiName(_ name: String) -> Bool {
        let upper = name.uppercased()
        return upper.hasPrefix("QY-QYSC") || upper.hasPrefix("XMD-TORNADOV4-I")
    }

    static func protocolHint(name: String, serviceIdentifiers: [String]) -> SmartCubeProtocolKind {
        let services = Set(serviceIdentifiers.map { $0.uppercased() })
        if services.contains(ganGen4Service) { return .ganGen4 }
        if services.contains(ganGen3Service) { return .ganGen3 }
        if services.contains(ganGen2Service) { return .ganGen2 }
        if services.contains(moyuService) { return .moyu }
        if isQiYiName(name) { return .qiyi }
        guard services.isDisjoint(with: ganTimerServices) else { return .unknown }

        let lowered = name.lowercased()
        if lowered.hasPrefix("gan") || lowered.hasPrefix("mg") || lowered.hasPrefix("aicube") {
            return .ganGen4
        }
        if lowered.contains("moyu") || lowered.contains("mhd") || lowered.contains("mhc")
            || lowered.contains("wcu") || lowered.contains("my32") || lowered.contains("weilong") {
            return .moyu
        }
        if lowered.contains("gi") || lowered.contains("mi smart") || lowered.contains("giiker") {
            return .giiker
        }
        return .unknown
    }

    static func isSupportedSmartCube(
        name: String,
        serviceIdentifiers: [String],
        protocolHint: SmartCubeProtocolKind
    ) -> Bool {
        let services = Set(serviceIdentifiers.map { $0.uppercased() })
        let knownCubeServices = Set([ganGen2Service, ganGen3Service, ganGen4Service, moyuService])
        if protocolHint == .qiyi,
           services.contains(qiyiService) || services.contains("FFF0") || services.isEmpty { return true }
        if !services.isDisjoint(with: ganTimerServices), services.isDisjoint(with: knownCubeServices) {
            return false
        }
        if protocolHint != .unknown || !services.isDisjoint(with: knownCubeServices) { return true }
        let lowered = name.lowercased()
        return ["cube", "gan", "moyu", "giiker", "aicube", "wcu", "mhc", "my32", "weilong"]
            .contains { lowered.contains($0) }
    }
}

nonisolated enum SmartCubeStateResetCapability: Equatable {
    case deviceResetWithAuthoritativeReadback
    case softwareReference
}

nonisolated struct SmartCubeResetRequestIdentity: Equatable {
    let id: UUID
    let connectionAttemptID: UUID
    let deviceID: UUID

    func matches(connectionAttemptID: UUID?, deviceID: UUID?) -> Bool {
        self.connectionAttemptID == connectionAttemptID && self.deviceID == deviceID
    }
}

nonisolated enum SmartCubeSoftwareSnapshotResolution: Equatable {
    case preserveLocal(String)
    case useAuthoritative(String)
}

nonisolated enum SmartCubeResetFailureDisposition: Equatable {
    case restorePreviousState
    case requireAuthoritativeState

    func resolvedFacelets(previousFacelets: String?) -> String? {
        self == .restorePreviousState ? previousFacelets : nil
    }
}

nonisolated enum SmartCubeResetReadbackPolicy {
    static let maximumAttempts = 3

    static func shouldRetry(afterAttempt attempt: Int) -> Bool {
        attempt < maximumAttempts
    }
}

nonisolated struct SmartCubeSoftwareResetReference: Equatable {
    let deviceID: UUID
    private(set) var expectedDeviceFacelets: String
    private(set) var localFacelets: String

    mutating func apply(_ move: String) -> Bool {
        guard let nextDevice = SmartCubeBluetoothManager.facelets(expectedDeviceFacelets, applying: move),
              let nextLocal = SmartCubeBluetoothManager.facelets(localFacelets, applying: move) else {
            return false
        }
        expectedDeviceFacelets = nextDevice
        localFacelets = nextLocal
        return true
    }

    func resolve(deviceID: UUID, snapshot: String, forceAuthoritative: Bool) -> SmartCubeSoftwareSnapshotResolution {
        guard !forceAuthoritative,
              self.deviceID == deviceID,
              snapshot == expectedDeviceFacelets else {
            return .useAuthoritative(snapshot)
        }
        return .preserveLocal(localFacelets)
    }
}

nonisolated enum SmartCubeManufacturer: String, Equatable {
    case gan = "GAN"
    case moYu = "MoYu"
    case qiYi = "QiYi"
    case unknown = "Unknown"
}

nonisolated enum SmartCubePuzzleKind: String, Equatable, Sendable {
    case twoByTwo
    case threeByThree

    var size: Int { self == .twoByTwo ? 2 : 3 }

    static func resolve(advertisedName: String?, protocolModelIdentifier: String?) -> Self {
        let identifiers = [advertisedName, protocolModelIdentifier]
            .compactMap { $0?.lowercased() }
        if identifiers.contains(where: {
            $0.hasPrefix("gan251ui") || $0.hasPrefix("ganic251") || $0.hasPrefix("wcu_my22")
        }) {
            return .twoByTwo
        }
        return .threeByThree
    }
}

nonisolated enum SmartCubeIdentificationConfidence: String, Equatable {
    case advertisementHint = "Advertisement hint"
    case protocolFamily = "Protocol family"
    case protocolReportedIdentity = "Protocol-reported identity"
}

nonisolated struct SmartCubeProtocolIdentityInfo: Equatable {
    let modelIdentifier: String?
    let hardwareVersion: String?
    let firmwareVersion: String?
    let productDate: String?

    init?(hardwareSummary: String) {
        guard let hardwareRange = hardwareSummary.range(of: " HW "),
              let firmwareRange = hardwareSummary.range(of: " SW "),
              hardwareRange.upperBound < firmwareRange.lowerBound
        else { return nil }

        let model = hardwareSummary[..<hardwareRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hardware = hardwareSummary[hardwareRange.upperBound..<firmwareRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firmwareAndExtra = hardwareSummary[firmwareRange.upperBound...]
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)

        modelIdentifier = model.isEmpty || model == "GAN" || model == "MoYu" ? nil : model
        hardwareVersion = hardware.isEmpty ? nil : hardware
        firmwareVersion = firmwareAndExtra.first.map(String.init)
        productDate = firmwareAndExtra.count > 1 ? String(firmwareAndExtra[1]) : nil
    }
}

nonisolated struct SmartCubeIdentity: Equatable {
    let manufacturer: SmartCubeManufacturer
    let protocolFamily: SmartCubeProtocolKind
    let advertisedName: String?
    let protocolModelIdentifier: String?
    let hardwareVersion: String?
    let firmwareVersion: String?
    let resolvedModel: String?
    let identificationConfidence: SmartCubeIdentificationConfidence
    let serviceIdentifiers: [String]
    let productDate: String?
    let puzzleKind: SmartCubePuzzleKind

    var displayName: String {
        if let resolvedModel { return resolvedModel }
        switch manufacturer {
        case .gan: return "GAN Smart Cube"
        case .moYu: return "MoYu Smart Cube"
        case .qiYi: return advertisedName ?? "QiYi Smart Cube"
        case .unknown: return "Smart Cube"
        }
    }

    static func resolve(
        advertisedName: String?,
        protocolFamily: SmartCubeProtocolKind,
        protocolConfirmed: Bool,
        protocolInfo: SmartCubeProtocolIdentityInfo?,
        serviceIdentifiers: [String]
    ) -> Self {
        let manufacturer: SmartCubeManufacturer
        switch protocolFamily {
        case .ganGen2, .ganGen3, .ganGen4:
            manufacturer = .gan
        case .moyu:
            manufacturer = .moYu
        case .qiyi:
            manufacturer = .qiYi
        case .giiker, .unknown:
            manufacturer = .unknown
        }

        let confidence: SmartCubeIdentificationConfidence
        if protocolInfo != nil {
            confidence = .protocolReportedIdentity
        } else if protocolConfirmed {
            confidence = .protocolFamily
        } else {
            confidence = .advertisementHint
        }

        let resolvedModel = resolvedConsumerModel(
            protocolFamily: protocolFamily,
            protocolModelIdentifier: protocolInfo?.modelIdentifier,
            advertisedName: advertisedName
        )
        let puzzleKind = SmartCubePuzzleKind.resolve(
            advertisedName: advertisedName,
            protocolModelIdentifier: protocolInfo?.modelIdentifier
        )

        return Self(
            manufacturer: manufacturer,
            protocolFamily: protocolFamily,
            advertisedName: advertisedName,
            protocolModelIdentifier: protocolInfo?.modelIdentifier,
            hardwareVersion: protocolInfo?.hardwareVersion,
            firmwareVersion: protocolInfo?.firmwareVersion,
            resolvedModel: resolvedModel,
            identificationConfidence: confidence,
            serviceIdentifiers: serviceIdentifiers.sorted(),
            productDate: protocolInfo?.productDate,
            puzzleKind: puzzleKind
        )
    }

    private static func resolvedConsumerModel(
        protocolFamily: SmartCubeProtocolKind,
        protocolModelIdentifier: String?,
        advertisedName: String?
    ) -> String? {
        if protocolFamily == .moyu, protocolModelIdentifier == "WCU_MY22" {
            return "MoYu WeiPo V5 AI"
        }
        if protocolFamily == .moyu, protocolModelIdentifier == nil {
            let name = advertisedName?.uppercased() ?? ""
            if name == "WCU_MY22" || name.hasPrefix("WCU_MY22_") {
                return "MoYu WeiPo V5 AI"
            }
        }
        guard protocolFamily == .ganGen4 else { return nil }
        switch protocolModelIdentifier {
        case "GAN16ui": return "GAN 16 ui"
        case "GAN12uiM": return "GAN 12 ui MagLev"
        case "GANi4": return "GAN i4 MagLev"
        case "GAN251Ui", "GAN251UI", "GANic251": return "GAN 251 ui"
        default: return nil
        }
    }
}

nonisolated enum SmartCubeMoveTimestampSource: Equatable {
    case deviceClock
    case reconstructed
    case hostReceipt
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

nonisolated struct SmartCubeCanonicalUpdate: Equatable {
    let sequence: UInt64
    let move: SmartCubeMoveEvent
    let facelets: String
    var isStateTrusted = true

    var puzzleSize: Int? {
        switch facelets.count {
        case 24: 2
        case 54: 3
        default: nil
        }
    }

    var isSolved: Bool {
        guard let puzzleSize else { return false }
        return CubeStateEquivalence.isSolved(facelets, puzzleSize: puzzleSize)
    }

    var previousTwoByTwoFacelets: String? {
        guard puzzleSize == 2 else { return nil }
        let notation = move.move
        let inverse = notation.hasSuffix("2") ? notation
            : notation.hasSuffix("'") ? String(notation.dropLast()) : notation + "'"
        return CubeLayerTurn(inverse)?.applying(to: facelets, size: 2)
    }
}

nonisolated enum SmartCubeContinuityReason: String, Equatable {
    case reset, resync, disconnected, historyGap, truncatedHistory
}

nonisolated struct SmartCubeContinuityBoundary: Equatable {
    let sequence: UInt64
    let reason: SmartCubeContinuityReason
    let facelets: String?
}

nonisolated enum SmartCubeCanonicalEvent: Equatable {
    case move(SmartCubeCanonicalUpdate)
    case boundary(SmartCubeContinuityBoundary)

    var sequence: UInt64 {
        switch self {
        case .move(let update): update.sequence
        case .boundary(let boundary): boundary.sequence
        }
    }

    var solveCompletingMove: SmartCubeMoveEvent? {
        guard case .move(let update) = self,
              update.isStateTrusted,
              update.isSolved else { return nil }
        return update.move
    }
}

@MainActor
final class SmartCubeCanonicalFeed {
    private let subject = PassthroughSubject<SmartCubeCanonicalEvent, Never>()
    private(set) var eventHistory: [SmartCubeCanonicalEvent] = []
    var history: [SmartCubeCanonicalUpdate] {
        eventHistory.compactMap { if case .move(let update) = $0 { update } else { nil } }
    }
    private(set) var sequence: UInt64 = 0
    private(set) var isStateTrusted = true
    var events: AnyPublisher<SmartCubeCanonicalEvent, Never> { subject.eraseToAnyPublisher() }
    var updates: AnyPublisher<SmartCubeCanonicalUpdate, Never> {
        events.compactMap { if case .move(let update) = $0 { update } else { nil } }.eraseToAnyPublisher()
    }

    func send(move: SmartCubeMoveEvent, facelets: String) {
        sequence &+= 1
        let update = SmartCubeCanonicalUpdate(
            sequence: sequence, move: move, facelets: facelets, isStateTrusted: isStateTrusted
        )
        publish(.move(update))
    }

    func breakContinuity(_ reason: SmartCubeContinuityReason, facelets: String?) {
        isStateTrusted = facelets != nil
        sequence &+= 1
        publish(.boundary(SmartCubeContinuityBoundary(sequence: sequence, reason: reason, facelets: facelets)))
    }

    func acceptAuthoritativeSnapshot(_ facelets: String, stateChanged: Bool) {
        guard stateChanged || !isStateTrusted else { return }
        breakContinuity(.resync, facelets: facelets)
    }

    private func publish(_ event: SmartCubeCanonicalEvent) {
        eventHistory.append(event)
        if eventHistory.count > 120 { eventHistory.removeFirst(eventHistory.count - 120) }
        subject.send(event)
    }

    func clearHistory() {
        eventHistory.removeAll()
        // Keep sequence monotonic across connections and local state resets.
    }
}

nonisolated struct SmartCubeMoveEvent: Identifiable, Equatable {
    let id: UUID
    let move: String
    let serial: Int?
    let face: Int?
    let direction: Int?
    let localTimestamp: Date
    let cubeTimestampMilliseconds: Int?
    let timestampSource: SmartCubeMoveTimestampSource

    init(
        id: UUID = UUID(),
        move: String,
        serial: Int?,
        face: Int?,
        direction: Int?,
        localTimestamp: Date,
        cubeTimestampMilliseconds: Int?,
        timestampSource: SmartCubeMoveTimestampSource = .hostReceipt
    ) {
        self.id = id
        self.move = move
        self.serial = serial
        self.face = face
        self.direction = direction
        self.localTimestamp = localTimestamp
        self.cubeTimestampMilliseconds = cubeTimestampMilliseconds
        self.timestampSource = timestampSource
    }
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


@MainActor
final class SmartCubeActiveFeedRouter {
    let feed = SmartCubeCanonicalFeed()
    private(set) var activeID: UUID?

    func activate(_ id: UUID?, facelets: String?, trusted: Bool) {
        guard activeID != id else { return }
        activeID = id
        feed.breakContinuity(.disconnected, facelets: nil)
        if trusted, let facelets { feed.acceptAuthoritativeSnapshot(facelets, stateChanged: true) }
    }

    func consume(_ event: SmartCubeCanonicalEvent, from deviceID: UUID, connected: Bool) {
        guard activeID == deviceID, connected else { return }
        switch event {
        case .move(let update): feed.send(move: update.move, facelets: update.facelets)
        case .boundary(let boundary): feed.breakContinuity(boundary.reason, facelets: boundary.facelets)
        }
    }
}

// Transport/parser ownership is per peripheral. Only the selected session is
// relayed into this stable, monotonically sequenced Timer feed.
nonisolated enum SmartCubeConnectionAttemptPolicy {
    static func shouldExpire(expected: UUID, current: UUID?, state: SmartCubeConnectionState) -> Bool {
        guard current == expected else { return false }
        if case .connecting = state { return true }
        return false
    }
}

nonisolated enum SmartCubeAutoConnectionPolicy {
    static func canAttempt(now: Date, advertisementAt: Date?, retryAfter: Date?) -> Bool {
        guard let advertisementAt, now.timeIntervalSince(advertisementAt) >= 0,
              now.timeIntervalSince(advertisementAt) <= 5 else { return false }
        return retryAfter.map { now >= $0 } ?? true
    }
}

final class SmartCubeBluetoothManager: NSObject, ObservableObject {
    static let shared = SmartCubeBluetoothManager()
    @Published private(set) var activeDeviceID: UUID?
    @Published private(set) var pendingPolicyAttemptID: UUID?
    @Published private(set) var discoveredDevices: [SmartCubeDiscoveredDevice] = []
    @Published private(set) var isScanningForDevices = false
    @Published var protocolDebugLogging = false { didSet { sessions.values.forEach { $0.protocolDebugLogging = protocolDebugLogging } } }
    @Published var verbosePacketLogging = false { didSet { sessions.values.forEach { $0.verbosePacketLogging = verbosePacketLogging } } }
    @Published var coalesceSliceMoves = false { didSet { sessions.values.forEach { $0.coalesceSliceMoves = coalesceSliceMoves } } }

    private lazy var central = CBCentralManager(delegate: self, queue: nil, options: [
        CBCentralManagerOptionRestoreIdentifierKey: "CubeFlow.SmartCubes.central.v1"
    ])
    private var sessions: [UUID: SmartCubePeripheralSession] = [:]
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var salts: [UUID: [UInt8]] = [:]
    private var subscriptions: [UUID: Set<AnyCancellable>] = [:]
    private var gyroObservers: [UUID: UUID] = [:]
    private var automaticallyApproved: Set<UUID> = []
    private var reconnectIDs: Set<UUID> = []
    private var manuallyDisconnectedIDs: Set<UUID> = []
    private var retryAfter: [UUID: Date] = [:]
    private var advertisementDates: [UUID: Date] = [:]
    private var retryDiscovery: [UUID: DispatchWorkItem] = [:]
    private var refreshScheduled = false
    private var prepared = false
    private var radioState: SmartCubeConnectionState = .disconnected
    private(set) var requestedPuzzleSize = 3
    private let activeFeed = SmartCubeActiveFeedRouter()
    private var canonicalFeed: SmartCubeCanonicalFeed { activeFeed.feed }
    let gyroFeed = SmartCubeGyroFeed()
    private var activeSession: SmartCubePeripheralSession? { activeDeviceID.flatMap { sessions[$0] } }

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    func session(for id: UUID) -> SmartCubePeripheralSession? { sessions[id] }
    func session(attemptID: UUID) -> SmartCubePeripheralSession? {
        sessions.values.first { $0.connectionAttemptID == attemptID }
    }
    func autoConnectPreferenceDidChange(for id: UUID, enabled: Bool) {
        if enabled {
            manuallyDisconnectedIDs.remove(id)
            resumeSavedDeviceDiscovery()
        }
    }
    var compatibleConnectedDeviceIDs: [UUID] {
        sessions.filter { $0.value.isConnected && $0.value.puzzleSize == requestedPuzzleSize }
            .map(\.key).sorted { $0.uuidString < $1.uuidString }
    }
    var connectionState: SmartCubeConnectionState {
        activeSession?.connectionState ?? (sessions.values.contains { $0.connectionState == .connecting && $0.puzzleSize == requestedPuzzleSize }
            ? .connecting : radioState)
    }
    var connectionDeviceID: UUID? { activeDeviceID }
    var isConnected: Bool { activeSession?.isConnected == true }
    var puzzleSize: Int { activeSession?.puzzleSize ?? requestedPuzzleSize }
    var canonicalEvents: AnyPublisher<SmartCubeCanonicalEvent, Never> { canonicalFeed.events }
    var canonicalHistory: [SmartCubeCanonicalEvent] { canonicalFeed.eventHistory }
    var canonicalSequence: UInt64 { canonicalFeed.sequence }
    var hasTrustedCanonicalState: Bool { activeSession?.hasTrustedCanonicalState == true }
    var observationReadiness: SmartCubeObservationReadiness {
        activeSession?.observationReadiness ?? SmartCubeObservationReadiness(
            attemptID: nil, isBLEConnected: false, hasResolvedConnectionPolicy: false,
            hasAuthoritativeState: false, hasTrustedCanonicalState: false
        )
    }
    var isReadyForMoveObservation: Bool { observationReadiness.isReady }

    func setTimerPuzzleSize(_ size: Int) {
        guard requestedPuzzleSize != size else { return }
        requestedPuzzleSize = size
        reconcileActive()
        objectWillChange.send()
    }
    func selectActiveDevice(_ id: UUID) {
        guard compatibleConnectedDeviceIDs.contains(id) else { return }
        SavedSmartCubeDevices.shared.markActive(id)
        switchActive(to: id)
    }
    private func reconcileActive() {
        let next = SavedSmartCubeSelection.activeID(
            current: activeDeviceID,
            remembered: SavedSmartCubeDevices.shared.lastActiveID(puzzleSize: requestedPuzzleSize),
            compatibleIDs: Set(compatibleConnectedDeviceIDs)
        )
        switchActive(to: next)
        let pending = sessions.values.filter {
            $0.isConnected && $0.connectionPolicyResolvedAttemptID != $0.connectionAttemptID
        }.compactMap(\.connectionAttemptID).sorted { $0.uuidString < $1.uuidString }.first
        if pendingPolicyAttemptID != pending { pendingPolicyAttemptID = pending }
    }
    private func switchActive(to id: UUID?) {
        guard activeDeviceID != id else { return }
        activeDeviceID = id
        if let id { SavedSmartCubeDevices.shared.markActive(id) }
        activeFeed.activate(id, facelets: activeSession?.facelets, trusted: activeSession?.hasTrustedCanonicalState == true)
        gyroFeed.send(activeSession?.gyroState)
    }
    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.reconcileActive()
            self.objectWillChange.send()
        }
    }
    private func makeSession(id: UUID) -> SmartCubePeripheralSession {
        if let existing = sessions[id] { return existing }
        let session = SmartCubePeripheralSession(central: central)
        session.protocolDebugLogging = protocolDebugLogging
        session.verbosePacketLogging = verbosePacketLogging
        session.coalesceSliceMoves = coalesceSliceMoves
        sessions[id] = session
        var tokens = Set<AnyCancellable>()
        session.objectWillChange.sink { [weak self] in
            guard let self, self.activeDeviceID == id else { return }
            self.scheduleRefresh()
        }.store(in: &tokens)
        // Inactive sessions keep parsing, but only device-row/readiness changes
        // propagate to the shared UI, not their moves, logs or state revisions.
        let deviceChanges: [AnyPublisher<Void, Never>] = [
            session.$connectionState.map { _ in () }.eraseToAnyPublisher(),
            session.$connectionAttemptID.map { _ in () }.eraseToAnyPublisher(),
            session.$connectionPolicyResolvedAttemptID.map { _ in () }.eraseToAnyPublisher(),
            session.$identity.map { _ in () }.eraseToAnyPublisher(),
            session.$batteryLevel.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(deviceChanges).sink { [weak self] in
            self?.scheduleRefresh()
        }.store(in: &tokens)
        session.onConnectionTimeout = { [weak self] in
            guard let self else { return }
            self.waitForRediscovery(id)
            self.automaticallyApproved.remove(id)
            self.reconcileActive()
            if UIApplication.shared.applicationState == .active { self.startScanning() }
        }
        session.canonicalEvents.sink { [weak self, weak session] event in
            self?.activeFeed.consume(event, from: id, connected: session?.isConnected == true)
        }.store(in: &tokens)
        subscriptions[id] = tokens
        gyroObservers[id] = session.gyroFeed.addObserver { [weak self] state in
            guard let self, self.activeDeviceID == id else { return }
            self.gyroFeed.send(state)
        }
        return session
    }

    private func waitForRediscovery(_ id: UUID) {
        advertisementDates[id] = nil
        retryAfter[id] = Date().addingTimeInterval(30)
        retryDiscovery[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.retryDiscovery[id] = nil
            guard !self.manuallyDisconnectedIDs.contains(id),
                  self.sessions[id]?.isConnected != true,
                  SavedSmartCubeDevices.shared.device(id)?.autoConnect == true || self.reconnectIDs.contains(id),
                  UIApplication.shared.applicationState == .active,
                  self.central.state == .poweredOn else { return }
            // Backoff resumes discovery, never a connection to a cached UUID.
            self.stopScanning()
            self.startScanning()
        }
        retryDiscovery[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
    }

    func prepareIfNeeded() {
        prepared = true
        _ = central
        resumeSavedDeviceDiscovery()
    }
    @objc private func foreground() {
        guard prepared else { return }
        sessions.values.filter(\.isConnected).forEach { $0.refreshAfterForeground() }
        resumeSavedDeviceDiscovery()
    }
    @objc private func background() {
        // Existing connections and notify subscriptions are deliberately retained.
        if isScanningForDevices { stopScanning() }
    }
    @objc func resumeSavedDeviceDiscovery() {
        guard prepared, central.state == .poweredOn else { return }
        let wanted = Set(SavedSmartCubeDevices.shared.devices.filter(\.autoConnect).map(\.id))
            .union(reconnectIDs).subtracting(manuallyDisconnectedIDs)
        for id in wanted where sessions[id]?.isConnected != true && sessions[id]?.connectionState != .connecting {
            if SmartCubeAutoConnectionPolicy.canAttempt(now: Date(), advertisementAt: advertisementDates[id], retryAfter: retryAfter[id]) {
                _ = connect(to: id, automatically: true)
            }
        }
        let missing = wanted.filter { sessions[$0]?.isConnected != true && sessions[$0]?.connectionState != .connecting }
        if !missing.isEmpty, UIApplication.shared.applicationState == .active, !isScanningForDevices {
            startScanning()
        }
    }
    func startScanning() {
        prepared = true
        guard central.state == .poweredOn else { return }
        isScanningForDevices = true
        radioState = .scanning
        advertisementDates.removeAll()
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    func stopScanning() {
        central.stopScan()
        isScanningForDevices = false
        radioState = .disconnected
        objectWillChange.send()
    }
    @discardableResult
    func connect(to id: UUID) -> UUID? { connect(to: id, automatically: false) }
    @discardableResult
    func connectSavedDevice(_ id: UUID) -> UUID? { connect(to: id) }
    private func discovery(for id: UUID, peripheral: CBPeripheral) -> SmartCubeDiscoveredDevice? {
        if let discovered = discoveredDevices.first(where: { $0.id == id }) { return discovered }
        guard let saved = SavedSmartCubeDevices.shared.device(id) else { return nil }
        return SmartCubeDiscoveredDevice(id: id, name: saved.originalName, rssi: 0,
            protocolHint: SmartCubeProtocolKind(rawValue: saved.protocolFamily) ?? .unknown,
            advertisedServices: [], manufacturerDataHex: saved.manufacturerDataHex, macAddress: saved.macAddress)
    }
    private func connect(to id: UUID, automatically: Bool, restored: Bool = false) -> UUID? {
        prepared = true
        if automatically, !restored,
           !SmartCubeAutoConnectionPolicy.canAttempt(now: Date(), advertisementAt: advertisementDates[id], retryAfter: retryAfter[id]) { return nil }
        retryAfter[id] = nil
        retryDiscovery.removeValue(forKey: id)?.cancel()
        guard central.state == .poweredOn || restored,
              let peripheral = peripherals[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first,
              let discovery = discovery(for: id, peripheral: peripheral) else { return nil }
        if let session = sessions[id], session.isConnected || session.connectionState == .connecting {
            return session.connectionAttemptID
        }
        manuallyDisconnectedIDs.remove(id)
        peripherals[id] = peripheral
        let session = makeSession(id: id)
        session.configure(peripheral: peripheral, discovery: discovery,
            salt: salts[id] ?? SavedSmartCubeDevices.shared.device(id)?.encryptionSalt)
        if automatically { automaticallyApproved.insert(id) }
        let attempt = session.connect(to: id, connectTransport: !restored)
        objectWillChange.send()
        return attempt
    }
    @discardableResult
    func resolveConnectionPolicy(for attemptID: UUID) -> Bool {
        guard let session = session(attemptID: attemptID) else { return false }
        let result = session.resolveConnectionPolicy(for: attemptID)
        reconcileActive()
        objectWillChange.send()
        return result
    }
    func disconnect(deviceID: UUID? = nil) {
        guard let id = deviceID ?? activeDeviceID else { return }
        manuallyDisconnectedIDs.insert(id)
        retryDiscovery.removeValue(forKey: id)?.cancel()
        reconnectIDs.remove(id)
        sessions[id]?.disconnect()
        reconcileActive()
        objectWillChange.send()
    }
    func resetCubeStateToSolved(deviceID: UUID? = nil, attemptID: UUID? = nil) {
        let session = attemptID.flatMap { self.session(attemptID: $0) }
            ?? (deviceID ?? activeDeviceID).flatMap { sessions[$0] }
        session?.resetCubeStateToSolved()
    }
    func clearLog() { activeSession?.clearLog() }
    func requestFacelets() { activeSession?.requestFacelets() }
    func requestBattery() { activeSession?.requestBattery() }
    func requestHardware() { activeSession?.requestHardware() }
    func startPacketCapture() { activeSession?.startPacketCapture() }
    func stopPacketCapture() { activeSession?.stopPacketCapture() }
    func finishPacketCapture() { activeSession?.finishPacketCapture() }

    nonisolated static var solvedFacelets: String { SmartCubePeripheralSession.solvedFacelets }
    nonisolated static func facelets(afterApplying algorithm: String, puzzleSize: Int = 3) -> String? {
        SmartCubePeripheralSession.facelets(afterApplying: algorithm, puzzleSize: puzzleSize)
    }
    nonisolated static func faceletStates(afterApplying moves: [String], puzzleSize: Int = 3) -> [String]? {
        SmartCubePeripheralSession.faceletStates(afterApplying: moves, puzzleSize: puzzleSize)
    }
    nonisolated static func facelets(_ value: String, applying move: String) -> String? {
        SmartCubePeripheralSession.facelets(value, applying: move)
    }
    var connectionAttemptID: UUID? { activeSession?.connectionAttemptID }
    var connectionPolicyResolvedAttemptID: UUID? { activeSession?.connectionPolicyResolvedAttemptID }
    var connectedDeviceName: String? { activeSession?.connectedDeviceName }
    var connectedProtocol: SmartCubeProtocolKind { activeSession?.connectedProtocol ?? .unknown }
    var identity: SmartCubeIdentity? { activeSession?.identity }
    var connectedMACAddress: String? { activeSession?.connectedMACAddress }
    var discoveredServiceUUIDs: [String] { activeSession?.discoveredServiceUUIDs ?? [] }
    var discoveredCharacteristicUUIDs: [String] { activeSession?.discoveredCharacteristicUUIDs ?? [] }
    var latestMove: SmartCubeMoveEvent? { activeSession?.latestMove }
    var moveHistory: [SmartCubeMoveEvent] { activeSession?.moveHistory ?? [] }
    var facelets: String? { activeSession?.facelets }
    var cubeStateRevision: Int { activeSession?.cubeStateRevision ?? 0 }
    var weiPo2LastNativeSnapshot: WeiPo2NativeState? { activeSession?.weiPo2LastNativeSnapshot }
    var weiPo2LatestNativeTurn: WeiPo2NativeTurn? { activeSession?.weiPo2LatestNativeTurn }
    var weiPo2VisualFacelets: String? { activeSession?.weiPo2VisualFacelets }
    var weiPo2VisualRevision: Int { activeSession?.weiPo2VisualRevision ?? 0 }
    var weiPo2PendingSnapshotCount: Int { activeSession?.weiPo2PendingSnapshotCount ?? 0 }
    var weiPo2ReferenceOrientation: SmartCubeGyroState? { activeSession?.weiPo2ReferenceOrientation }
    var gyroState: SmartCubeGyroState? { activeSession?.gyroState }
    var batteryLevel: Int? { activeSession?.batteryLevel }
    var hardwareSummary: String? { activeSession?.hardwareSummary }
    var logEntries: [SmartCubeLogEntry] { activeSession?.logEntries ?? [] }
    var protocolLogEntries: [SmartCubeLogEntry] { activeSession?.protocolLogEntries ?? [] }
    var isPacketCaptureActive: Bool { activeSession?.isPacketCaptureActive ?? false }
    var isPacketCaptureFinishing: Bool { activeSession?.isPacketCaptureFinishing ?? false }
    var packetCaptureText: String { activeSession?.packetCaptureText ?? "" }
    #if DEBUG
    var debugIdentityDump: String { activeSession?.debugIdentityDump ?? "No active identity" }
    #endif
}

extension SmartCubeBluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            if isScanningForDevices { stopScanning() }
            sessions.values.forEach { $0.transportBecameUnavailable() }
        }
        switch central.state {
        case .poweredOn:
            radioState = .disconnected
            resumeSavedDeviceDiscovery()
        case .unauthorized:
            radioState = .unauthorized
            switchActive(to: nil)
        default:
            radioState = .bluetoothUnavailable
            switchActive(to: nil)
        }
        objectWillChange.send()
    }
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        prepared = true
        for peripheral in dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? [] {
            let id = peripheral.identifier
            // A saved salt/metadata is necessary to rebuild the verified cipher.
            guard SavedSmartCubeDevices.shared.device(id) != nil else {
                central.cancelPeripheralConnection(peripheral)
                continue
            }
            peripherals[id] = peripheral
            reconnectIDs.insert(id)
            guard peripheral.state == .connected || peripheral.state == .connecting else { continue }
            if connect(to: id, automatically: true, restored: true) != nil, peripheral.state == .connected {
                self.centralManager(central, didConnect: peripheral)
            }
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Unknown Device"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)
        let hint = SmartCubeDiscoveryClassifier.protocolHint(name: name, serviceIdentifiers: services)
        guard SmartCubeDiscoveryClassifier.isSupportedSmartCube(name: name, serviceIdentifiers: services, protocolHint: hint) else { return }
        let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let bytes = data.map { [UInt8]($0) } ?? []
        let payload = bytes.count >= 11 ? Array(bytes.dropFirst(2).prefix(9)) : bytes
        let salt: [UInt8]? = bytes.count >= 8 && payload.count >= 6 ? Array(payload.suffix(6)) : nil
        let mac = salt.map { $0.reversed().map { String(format: "%02X", $0) }.joined(separator: ":") }
        let hex = data.map { _ in bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
        let device = SmartCubeDiscoveredDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue,
            protocolHint: hint, advertisedServices: services.sorted(), manufacturerDataHex: hex, macAddress: mac)
        peripherals[device.id] = peripheral
        advertisementDates[device.id] = Date()
        if let salt { salts[device.id] = salt }
        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) { discoveredDevices[index] = device }
        else { discoveredDevices.append(device) }
        SavedSmartCubeDevices.shared.rememberTransport(id: device.id, salt: salt, manufacturerDataHex: hex, macAddress: mac)
        if (SavedSmartCubeDevices.shared.device(device.id)?.autoConnect == true || reconnectIDs.contains(device.id)),
           !manuallyDisconnectedIDs.contains(device.id) {
            _ = connect(to: device.id, automatically: true)
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier
        guard let session = sessions[id] else { return }
        session.centralManager(central, didConnect: peripheral)
        reconnectIDs.insert(id)
        if automaticallyApproved.remove(id) != nil, let attempt = session.connectionAttemptID {
            _ = session.resolveConnectionPolicy(for: attempt)
        }
        if let identity = session.identity {
            SavedSmartCubeDevices.shared.remember(id: id, identity: identity, fallbackName: peripheral.name)
        }
        let discovery = discovery(for: id, peripheral: peripheral)
        SavedSmartCubeDevices.shared.rememberTransport(id: id, salt: salts[id],
            manufacturerDataHex: discovery?.manufacturerDataHex, macAddress: discovery?.macAddress)
        reconcileActive()
        objectWillChange.send()
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        waitForRediscovery(peripheral.identifier)
        automaticallyApproved.remove(peripheral.identifier)
        sessions[peripheral.identifier]?.centralManager(central, didFailToConnect: peripheral, error: error)
        reconcileActive()
        // Discovery can retry a sleeping/out-of-range cube without a tight connect loop.
        if UIApplication.shared.applicationState == .active { startScanning() }
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        sessions[peripheral.identifier]?.centralManager(central, didDisconnectPeripheral: peripheral, error: error)
        reconcileActive()
        objectWillChange.send()
        resumeSavedDeviceDiscovery()
    }
}
#endif

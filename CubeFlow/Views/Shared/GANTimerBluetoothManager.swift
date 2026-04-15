#if os(iOS)
import Foundation
import CoreBluetooth
import Combine

struct GANTimerCompletedSolve: Equatable {
    let id = UUID()
    let seconds: Double
}

struct GANTimerDiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let hasGANService: Bool
}

enum GANTimerConnectionState: Equatable {
    case disconnected
    case bluetoothUnavailable
    case unauthorized
    case scanning
    case connecting
    case connected
    case handsOn
    case ready
    case running
    case finished
    case failed(String)
}

final class GANTimerBluetoothManager: NSObject, ObservableObject {
    static let shared = GANTimerBluetoothManager()

    @Published private(set) var connectionState: GANTimerConnectionState = .disconnected
    @Published private(set) var deviceName: String?
    @Published private(set) var displayedSeconds: Double = 0
    @Published private(set) var completedSolve: GANTimerCompletedSolve?
    @Published private(set) var discoveredDevices: [GANTimerDiscoveredDevice] = []
    @Published private(set) var clearButtonEventID: UUID?
    @Published private(set) var inspectionToggleEventID: UUID?
    @Published private(set) var isHandsOn: Bool = false
    private let ganServiceUUID = CBUUID(string: "FFF0")
    private let stateCharacteristicUUID = CBUUID(string: "FFF5")
    private let storedTimesCharacteristicUUID = CBUUID(string: "FFF2")
    private let lastPeripheralIdentifierKey = "ganSmartTimerPeripheralIdentifier"

    private lazy var centralManager = CBCentralManager(delegate: self, queue: nil)
    private var peripheral: CBPeripheral?
    private var stateCharacteristic: CBCharacteristic?
    private var storedTimesCharacteristic: CBCharacteristic?
    private var readableCharacteristics: [CBCharacteristic] = []
    private var pollingTimer: Timer?
    private var runningStartDate: Date?
    private var isPrepared = false
    private var discoveredPeripheralsByID: [UUID: CBPeripheral] = [:]
    private var ignoreNextZeroIdlePacket = false
    private var lastZeroIdlePacketDate: Date?
    private let clearButtonSignature: [UInt8] = [0xFE, 0x08, 0x01, 0x05, 0x00, 0x00, 0x00, 0x00]
    private override init() {
        super.init()
    }

    var isConnected: Bool {
        switch connectionState {
        case .connected, .handsOn, .ready, .running, .finished:
            return true
        default:
            return false
        }
    }

    var statusLocalizedKey: String {
        switch connectionState {
        case .disconnected:
            return "settings.gan_status_disconnected"
        case .bluetoothUnavailable:
            return "settings.gan_status_bluetooth_unavailable"
        case .unauthorized:
            return "settings.gan_status_unauthorized"
        case .scanning:
            return "settings.gan_status_scanning"
        case .connecting:
            return "settings.gan_status_connecting"
        case .connected:
            return "settings.gan_status_connected"
        case .handsOn:
            return "settings.gan_status_hands_on"
        case .ready:
            return "settings.gan_status_ready"
        case .running:
            return "settings.gan_status_running"
        case .finished:
            return "settings.gan_status_finished"
        case .failed:
            return "settings.gan_status_failed"
        }
    }

    var actionLocalizedKey: String {
        switch connectionState {
        case .disconnected, .bluetoothUnavailable, .unauthorized, .failed:
            return "settings.gan_action_choose_device"
        case .scanning:
            return "common.cancel"
        case .connecting, .connected, .handsOn, .ready, .running, .finished:
            return "settings.gan_action_disconnect"
        }
    }

    func prepareIfNeeded() {
        guard !isPrepared else { return }
        isPrepared = true
        _ = centralManager
    }

    func performPrimaryAction() {
        switch connectionState {
        case .scanning:
            stopScanning()
        case .connecting, .connected, .handsOn, .ready, .running, .finished:
            disconnect()
        default:
            startDeviceDiscovery()
        }
    }

    func startDeviceDiscovery() {
        prepareIfNeeded()

        switch centralManager.state {
        case .poweredOn:
            if let peripheral, peripheral.state == .connected {
                return
            }
            startScanning()
        case .unauthorized:
            connectionState = .unauthorized
        case .unsupported, .poweredOff, .resetting, .unknown:
            connectionState = .bluetoothUnavailable
        @unknown default:
            connectionState = .bluetoothUnavailable
        }
    }

    func disconnect() {
        stopScanning()
        if let peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        self.peripheral = nil
        runningStartDate = nil
        stateCharacteristic = nil
        storedTimesCharacteristic = nil
        readableCharacteristics = []
        stopPolling()
        ignoreNextZeroIdlePacket = false
        lastZeroIdlePacketDate = nil
        isHandsOn = false
        connectionState = .disconnected
    }

    func connect(to deviceID: UUID) {
        prepareIfNeeded()
        guard centralManager.state == .poweredOn else {
            connectionState = .bluetoothUnavailable
            return
        }
        guard let peripheral = discoveredPeripheralsByID[deviceID] else {
            connectionState = .failed("Selected device is no longer available")
            return
        }

        stopScanning()
        connectionState = .connecting
        self.peripheral = peripheral
        deviceName = discoveredDevices.first(where: { $0.id == deviceID })?.name ?? peripheral.name
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    var liveSeconds: Double {
        if connectionState == .running, let runningStartDate {
            return Date().timeIntervalSince(runningStartDate)
        }
        return displayedSeconds
    }

    private func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        discoveredDevices = []
        discoveredPeripheralsByID = [:]
        connectionState = .scanning
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func stopScanning() {
        centralManager.stopScan()
        if case .scanning = connectionState {
            connectionState = .disconnected
        }
    }

    private func storePeripheralIdentifier(_ identifier: UUID) {
        UserDefaults.standard.set(identifier.uuidString, forKey: lastPeripheralIdentifierKey)
    }

    private func isPotentialGANTimer(name: String, hasGANService: Bool) -> Bool {
        if hasGANService { return true }

        let lowered = name.lowercased()
        let timerKeywords = ["timer", "smart timer", "gan timer"]
        return lowered.contains("gan") && timerKeywords.contains { lowered.contains($0) }
    }

    private func updateDiscoveredDevice(_ discoveredDevice: GANTimerDiscoveredDevice, peripheral: CBPeripheral) {
        discoveredPeripheralsByID[discoveredDevice.id] = peripheral

        if let index = discoveredDevices.firstIndex(where: { $0.id == discoveredDevice.id }) {
            discoveredDevices[index] = discoveredDevice
        } else {
            discoveredDevices.append(discoveredDevice)
        }

        discoveredDevices.sort {
            if $0.hasGANService != $1.hasGANService {
                return $0.hasGANService && !$1.hasGANService
            }
            if $0.rssi != $1.rssi {
                return $0.rssi > $1.rssi
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func parseTimestamp(_ bytes: ArraySlice<UInt8>) -> Double? {
        guard bytes.count == 4 else { return nil }
        let values = Array(bytes)
        let minutes = Double(values[0])
        let seconds = Double(values[1])
        let milliseconds = Double(UInt16(values[2]) | (UInt16(values[3]) << 8))
        return (minutes * 60) + seconds + (milliseconds / 1000)
    }

    private func characteristicPropertiesDescription(_ properties: CBCharacteristicProperties) -> String {
        var labels: [String] = []
        if properties.contains(.read) { labels.append("read") }
        if properties.contains(.write) { labels.append("write") }
        if properties.contains(.writeWithoutResponse) { labels.append("writeNoResp") }
        if properties.contains(.notify) { labels.append("notify") }
        if properties.contains(.indicate) { labels.append("indicate") }
        if properties.contains(.broadcast) { labels.append("broadcast") }
        if properties.contains(.authenticatedSignedWrites) { labels.append("signedWrite") }
        if properties.contains(.extendedProperties) { labels.append("extended") }
        return labels.isEmpty ? "none" : labels.joined(separator: ",")
    }

    private func parseTimerStatePacket(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 5 else { return }

        let usesExtendedPrefix = bytes[0] == 0xFE && bytes.count >= 6 && bytes[2] == 0x01
        let usesCompactPrefix = bytes[0] != 0xFE && bytes.count >= 5 && bytes[1] == 0x01
        guard usesExtendedPrefix || usesCompactPrefix else { return }

        let stateIndex = usesExtendedPrefix ? 3 : 2
        let timeIndex = usesExtendedPrefix ? 4 : 3
        let state = bytes[stateIndex]
        let timeValue: Double?
        if (state == 0x04 || state == 0x05), bytes.count >= timeIndex + 4 {
            timeValue = parseTimestamp(bytes[timeIndex...(timeIndex + 3)])
        } else {
            timeValue = nil
        }

        switch state {
        case 0x01:
            runningStartDate = nil
            displayedSeconds = 0
            isHandsOn = true
            connectionState = .ready
        case 0x02:
            isHandsOn = false
            connectionState = .connected
        case 0x03:
            runningStartDate = Date()
            displayedSeconds = 0
            isHandsOn = false
            connectionState = .running
        case 0x04:
            runningStartDate = nil
            isHandsOn = true
            if let timeValue {
                displayedSeconds = timeValue
                completedSolve = GANTimerCompletedSolve(seconds: timeValue)
            }
            connectionState = .finished
        case 0x05:
            runningStartDate = nil
            let wasAlreadyCleared = displayedSeconds == 0
            if let timeValue {
                displayedSeconds = timeValue
                if isClearButtonPacket(bytes) {
                    handleZeroIdlePacket(wasAlreadyCleared: wasAlreadyCleared)
                }
            }
            connectionState = .connected
        case 0x06:
            runningStartDate = nil
            displayedSeconds = 0
            isHandsOn = true
            connectionState = .handsOn
        case 0x07:
            if let runningStartDate, displayedSeconds == 0 {
                displayedSeconds = Date().timeIntervalSince(runningStartDate)
            }
            runningStartDate = nil
            isHandsOn = false
            connectionState = .connected
        default:
            break
        }
    }

    private func isClearButtonPacket(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= clearButtonSignature.count else { return false }
        return Array(bytes.prefix(clearButtonSignature.count)) == clearButtonSignature
    }

    private func handleZeroIdlePacket(wasAlreadyCleared: Bool) {
        let now = Date()

        if ignoreNextZeroIdlePacket {
            ignoreNextZeroIdlePacket = false
            lastZeroIdlePacketDate = now
            return
        }

        if let lastZeroIdlePacketDate,
           now.timeIntervalSince(lastZeroIdlePacketDate) < 0.35 {
            return
        }

        lastZeroIdlePacketDate = now
        clearButtonEventID = UUID()
        if wasAlreadyCleared {
            inspectionToggleEventID = UUID()
        }
    }

    private func startPollingIfNeeded() {
        guard pollingTimer == nil else { return }
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self,
                  let peripheral = self.peripheral,
                  peripheral.state == .connected else { return }

            for characteristic in self.readableCharacteristics {
                peripheral.readValue(for: characteristic)
            }
        }
        if let pollingTimer {
            RunLoop.main.add(pollingTimer, forMode: .common)
        }
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
}

extension GANTimerBluetoothManager: CBCentralManagerDelegate {
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

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let hasGANService = advertisedServices.contains(ganServiceUUID)
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let looksLikeTimer = isPotentialGANTimer(name: name, hasGANService: hasGANService)

        guard hasGANService || looksLikeTimer else { return }

        let displayName = name.isEmpty ? "GAN Smart Timer" : name
        updateDiscoveredDevice(
            GANTimerDiscoveredDevice(
                id: peripheral.identifier,
                name: displayName,
                rssi: RSSI.intValue,
                hasGANService: hasGANService
            ),
            peripheral: peripheral
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        storePeripheralIdentifier(peripheral.identifier)
        deviceName = peripheral.name ?? deviceName
        connectionState = .connected
        ignoreNextZeroIdlePacket = true
        lastZeroIdlePacketDate = nil
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .failed(error?.localizedDescription ?? "Connection failed")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        runningStartDate = nil
        stateCharacteristic = nil
        storedTimesCharacteristic = nil
        readableCharacteristics = []
        stopPolling()
        self.peripheral = nil
        ignoreNextZeroIdlePacket = false
        lastZeroIdlePacketDate = nil
        isHandsOn = false
        if let error {
            connectionState = .failed(error.localizedDescription)
        } else {
            connectionState = .disconnected
        }
    }
}

extension GANTimerBluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            connectionState = .failed(error?.localizedDescription ?? "Service discovery failed")
            return
        }

        let services = peripheral.services ?? []
        services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            connectionState = .failed(error?.localizedDescription ?? "Characteristic discovery failed")
            return
        }

        let characteristics = service.characteristics ?? []

        characteristics.forEach { characteristic in
            switch characteristic.uuid {
            case stateCharacteristicUUID:
                stateCharacteristic = characteristic
            case storedTimesCharacteristicUUID:
                storedTimesCharacteristic = characteristic
            default:
                break
            }

            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }

            if characteristic.properties.contains(.read) {
                if !readableCharacteristics.contains(where: { $0.uuid == characteristic.uuid && $0.service?.uuid == characteristic.service?.uuid }) {
                    readableCharacteristics.append(characteristic)
                }
                peripheral.readValue(for: characteristic)
            }
        }
        startPollingIfNeeded()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            connectionState = .failed(error?.localizedDescription ?? "Notification subscription failed")
            return
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            connectionState = .failed(error?.localizedDescription ?? "Characteristic update failed")
            return
        }

        guard let data = characteristic.value else { return }

        if characteristic.uuid == stateCharacteristicUUID {
            parseTimerStatePacket(data)
            return
        }

        if characteristic.uuid == storedTimesCharacteristicUUID {
            let bytes = [UInt8](data)
            if bytes.count >= 4, let latest = parseTimestamp(bytes[0...3]) {
                displayedSeconds = latest
            }
        }
    }
}
#endif

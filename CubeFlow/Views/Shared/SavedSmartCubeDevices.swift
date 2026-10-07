#if os(iOS)
import Foundation
import Combine

nonisolated struct SavedSmartCubeDevice: Codable, Equatable, Identifiable {
    let id: UUID
    var originalName: String
    var modelName: String
    var protocolFamily: String
    var puzzleSize: Int
    var customName: String?
    var autoConnect: Bool
    var iconColor: StoredColorData? = nil
    var encryptionSalt: [UInt8]? = nil
    var manufacturerDataHex: String? = nil
    var macAddress: String? = nil

    var displayName: String {
        let alias = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return alias.isEmpty ? originalName : alias
    }
}

nonisolated enum SavedSmartCubeSelection {
    static func activeID(current: UUID?, remembered: UUID?, compatibleIDs: Set<UUID>) -> UUID? {
        if let current, compatibleIDs.contains(current) { return current }
        if let remembered, compatibleIDs.contains(remembered) { return remembered }
        return compatibleIDs.count == 1 ? compatibleIDs.first : nil
    }

    static func preferredAvailableID(
        devices: [SavedSmartCubeDevice],
        lastActiveID: UUID?,
        availableIDs: Set<UUID>
    ) -> UUID? {
        let eligible = devices.filter { $0.autoConnect && availableIDs.contains($0.id) }
        if let lastActiveID, eligible.contains(where: { $0.id == lastActiveID }) {
            return lastActiveID
        }
        return eligible.map(\.id).sorted { $0.uuidString < $1.uuidString }.first
    }
}

final class SavedSmartCubeDevices: ObservableObject {
    static let shared = SavedSmartCubeDevices()
    private static let storageKey = "savedSmartCubeDevices.v1"

    @Published private(set) var devices: [SavedSmartCubeDevice]
    @Published private(set) var lastActiveDeviceID: UUID?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        devices = (defaults.data(forKey: Self.storageKey))
            .flatMap { try? JSONDecoder().decode([SavedSmartCubeDevice].self, from: $0) } ?? []
        lastActiveDeviceID = defaults.string(forKey: "savedSmartCubeDevices.lastActive")
            .flatMap(UUID.init(uuidString:))
    }

    func device(_ id: UUID) -> SavedSmartCubeDevice? {
        devices.first { $0.id == id }
    }

    func remember(id: UUID, identity: SmartCubeIdentity, fallbackName: String?) {
        let name = [identity.advertisedName, fallbackName, device(id)?.originalName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? id.uuidString
        let model = identity.resolvedModel ?? identity.displayName
        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index].originalName = name
            devices[index].modelName = model
            devices[index].protocolFamily = identity.protocolFamily.rawValue
            devices[index].puzzleSize = identity.puzzleKind.size
        } else {
            devices.append(SavedSmartCubeDevice(
                id: id, originalName: name, modelName: model,
                protocolFamily: identity.protocolFamily.rawValue,
                puzzleSize: identity.puzzleKind.size,
                customName: nil, autoConnect: false
            ))
        }
        persist()
    }

    func rename(_ id: UUID, to name: String?) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        devices[index].customName = trimmed.isEmpty ? nil : trimmed
        persist()
    }

    func setAutoConnect(_ enabled: Bool, for id: UUID) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        devices[index].autoConnect = enabled
        persist()
    }

    func markActive(_ id: UUID) {
        lastActiveDeviceID = id
        defaults.set(id.uuidString, forKey: "savedSmartCubeDevices.lastActive")
        if let device = device(id) {
            defaults.set(id.uuidString, forKey: "savedSmartCubeDevices.lastActive.\(device.puzzleSize)")
        }
    }

    func lastActiveID(puzzleSize: Int) -> UUID? {
        if let value = defaults.string(forKey: "savedSmartCubeDevices.lastActive.\(puzzleSize)") {
            return UUID(uuidString: value)
        }
        // Migrate the previous single-device preference only to its own puzzle.
        return lastActiveDeviceID.flatMap { device($0)?.puzzleSize == puzzleSize ? $0 : nil }
    }

    func setIconColor(_ color: StoredColorData?, for id: UUID) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        devices[index].iconColor = color?.sanitized()
        persist()
    }

    func rememberTransport(id: UUID, salt: [UInt8]?, manufacturerDataHex: String?, macAddress: String?) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        if let salt { devices[index].encryptionSalt = salt }
        if let manufacturerDataHex { devices[index].manufacturerDataHex = manufacturerDataHex }
        if let macAddress { devices[index].macAddress = macAddress }
        persist()
    }

    func preferredAvailableID(_ ids: Set<UUID>) -> UUID? {
        SavedSmartCubeSelection.preferredAvailableID(
            devices: devices, lastActiveID: lastActiveDeviceID, availableIDs: ids
        )
    }

    private func persist() {
        devices.sort { $0.id.uuidString < $1.id.uuidString }
        if let data = try? JSONEncoder().encode(devices) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

nonisolated enum SmartCubeDeviceNamePresentation {
    static func showsModel(originalName: String, customName: String?, model: String) -> Bool {
        let alias = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let primary = alias.isEmpty ? originalName : alias
        // Factory suffixes identify the peripheral, never the consumer model.
        let base = alias.isEmpty ? String(primary.split(separator: "_").first ?? Substring(primary)) : primary
        let compact: (String) -> String = { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
        let identity = compact(model)
        guard !identity.isEmpty else { return false }
        if compact(primary) == identity { return false }
        let modelTokens = base.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        for start in modelTokens.indices {
            for end in start..<modelTokens.count {
                if modelTokens[start...end].joined() == identity { return false }
            }
        }
        let tokens = primary.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if !alias.isEmpty, identity == "gan16ui", tokens.count == 2,
           ["competition", "practice"].contains(tokens[0]), tokens[1] == "16" {
            return false
        }
        return true
    }
}
#endif

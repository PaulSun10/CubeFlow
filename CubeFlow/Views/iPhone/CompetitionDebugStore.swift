#if DEBUG
import SwiftUI
import Combine
import UIKit

/// One in-app runtime gate. Automated launch fixtures and compiler diagnostics
/// intentionally remain independent; enabling this gate never starts recording.
@MainActor final class CompetitionDebugStore: ObservableObject {
    static let key = "cubeFlowDebugMode"
    static let changed = Notification.Name("CubeFlowDebugCaptureChanged")
    static var shared = CompetitionDebugStore()
    enum Kind: String, CaseIterable { case filter, separator }
    struct Capture: Identifiable {
        let id: String
        let kind: Kind
        let date: Date
        let directory: URL
    }
    @Published private(set) var enabled: Bool
    @Published private(set) var filterRecording = false
    @Published private(set) var separatorRecording = false
    @Published private(set) var captures: [Capture] = []
    @Published var failure: String?
    private let defaults: UserDefaults
    let root: URL
    private var filterEvents: [[String: Any]] = []
    private var filterStarted: Date?
    private var droppedEvents = 0
    static let capacity = 4
    static let byteLimit = 64 * 1024 * 1024

    init(defaults: UserDefaults = .standard, root: URL? = nil) {
        self.defaults = defaults
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DebugCaptures", isDirectory: true)
        if defaults.object(forKey: Self.key) == nil {
            defaults.set(defaults.bool(forKey: "competitionTopCubersDebugBounds") || defaults.bool(forKey: "smartCubeDebugMode"), forKey: Self.key)
        }
        defaults.removeObject(forKey: "competitionTopCubersDebugBounds")
        defaults.removeObject(forKey: "smartCubeDebugMode")
        enabled = defaults.bool(forKey: Self.key)
        SmartCubeDiagnostics.shared.setEnabled(false)
        // Recording is deliberately not resumed after process termination.
        defaults.set(false, forKey: CompetitionScrollOwnerDiagnostics.enabledKey)
        reload()
    }
    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        if !value { stopFilter(reason: "debug-mode-off"); separatorRecording = false }
        enabled = value; defaults.set(value, forKey: Self.key)
        if !value { SmartCubeDiagnostics.shared.setEnabled(false) }
        if !value { defaults.set(false, forKey: CompetitionScrollOwnerDiagnostics.enabledKey) }
        NotificationCenter.default.post(name: Self.changed, object: self)
    }
    var binding: Binding<Bool> { Binding(get: { self.enabled }, set: { self.setEnabled($0) }) }
    func count(_ kind: Kind) -> Int { captures.filter { $0.kind == kind }.count }
    func start(_ kind: Kind) {
        guard enabled, count(kind) < Self.capacity else { failure = "Clear saved captures before starting another session."; return }
        switch kind {
        case .filter:
            guard !filterRecording else { return }
            filterEvents = []; droppedEvents = 0; filterStarted = Date(); filterRecording = true
            recordFilter(["event": "capture-start", "time": CACurrentMediaTime(), "wallTime": Date().timeIntervalSince1970])
        case .separator: separatorRecording = true
        }
        NotificationCenter.default.post(name: Self.changed, object: self)
    }
    func stop(_ kind: Kind) {
        if kind == .filter { stopFilter(reason: "user-stop") } else { separatorRecording = false }
        NotificationCenter.default.post(name: Self.changed, object: self)
    }
    func recordFilter(_ event: [String: Any]) {
        guard enabled, filterRecording else { return }
        filterEvents.append(event)
        if filterEvents.count > 512 { droppedEvents += filterEvents.count - 512; filterEvents.removeFirst(filterEvents.count - 512) }
    }
    private func stopFilter(reason: String) {
        guard filterRecording else { return }
        recordFilter(["event": "capture-stop", "reason": reason, "time": CACurrentMediaTime(), "wallTime": Date().timeIntervalSince1970])
        filterRecording = false
        do {
            _ = try save(kind: .filter, metadata: ["events": filterEvents, "droppedEvents": droppedEvents,
                "startedAt": (filterStarted ?? Date()).timeIntervalSince1970, "stopReason": reason])
            filterEvents = []; filterStarted = nil
        } catch { failure = error.localizedDescription }
    }
    @discardableResult func save(kind: Kind, metadata: [String: Any], image: Data? = nil) throws -> Capture {
        guard count(kind) < Self.capacity else { throw CaptureError.full }
        let id = UUID().uuidString
        let folder = root.appendingPathComponent(id, isDirectory: true)
        var envelope = metadata
        envelope["schema"] = 1; envelope["id"] = id; envelope["kind"] = kind.rawValue
        envelope["savedAt"] = Date().timeIntervalSince1970
        envelope["os"] = ProcessInfo.processInfo.operatingSystemVersionString
        let json = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
        guard diskBytes() + json.count + (image?.count ?? 0) < Self.byteLimit else { throw CaptureError.full }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var root = self.root
        var flags = URLResourceValues(); flags.isExcludedFromBackup = true
        try root.setResourceValues(flags)
        do {
            try json.write(to: folder.appendingPathComponent("metadata.json"), options: .atomic)
            if let image { try image.write(to: folder.appendingPathComponent("snapshot.png"), options: .atomic) }
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
        reload()
        return Capture(id: id, kind: kind, date: Date(), directory: folder)
    }
    func metadata(_ capture: Capture) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: capture.directory.appendingPathComponent("metadata.json"))) as? [String: Any] ?? [:]
    }
    func update(_ capture: Capture, metadata: [String: Any], image: Data? = nil) throws {
        let json = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        guard diskBytes() + json.count + (image?.count ?? 0) < Self.byteLimit else { throw CaptureError.full }
        if let image { try image.write(to: capture.directory.appendingPathComponent("system-screenshot.png"), options: .atomic) }
        try json.write(to: capture.directory.appendingPathComponent("metadata.json"), options: .atomic)
        objectWillChange.send()
    }
    func clear(_ kind: Kind) {
        guard !(kind == .filter ? filterRecording : separatorRecording) else { return }
        do {
            for capture in captures where capture.kind == kind {
                try FileManager.default.removeItem(at: capture.directory)
                let zip = root.appendingPathComponent("\(capture.id).zip")
                if FileManager.default.fileExists(atPath: zip.path) { try FileManager.default.removeItem(at: zip) }
            }
            reload()
        } catch { failure = error.localizedDescription; reload() }
    }
    /// A native coordinated upload representation produces a coherent ZIP without
    /// a library dependency. Only an explicit Share action invokes this operation.
    func export(_ capture: Capture) throws -> URL {
        let destination = root.appendingPathComponent("\(capture.id).zip")
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(readingItemAt: capture.directory, options: .forUploading, error: &coordinationError) { zip in
            result = Result {
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.copyItem(at: zip, to: destination)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CaptureError.export }
        try result.get()
        return destination
    }
    private func diskBytes() -> Int {
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey])
        return (files?.allObjects as? [URL] ?? []).reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
    private func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        captures = folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("metadata.json")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let kind = (json["kind"] as? String).flatMap(Kind.init), let id = json["id"] as? String,
                  let time = json["savedAt"] as? Double else { return nil }
            return Capture(id: id, kind: kind, date: Date(timeIntervalSince1970: time), directory: folder)
        }.sorted { $0.date > $1.date }
    }
    enum CaptureError: LocalizedError {
        case full, export
        var errorDescription: String? {
            self == .full ? "Capture storage is full. Clear saved captures to continue." : "Could not create the capture archive."
        }
    }
}
#endif

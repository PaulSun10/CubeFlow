import Foundation

/// Configured once, then read-only. DateFormatter is thread-safe on iOS 7+.
nonisolated final class SolveDisplayDateCache: @unchecked Sendable {
    static let shared = SolveDisplayDateCache()
    private let lock = NSLock()
    private var formatters: [String: DateFormatter] = [:]
    private var order: [String] = []
    private var observers: [NSObjectProtocol] = []
    init() {
        for name in [NSLocale.currentLocaleDidChangeNotification, .NSSystemTimeZoneDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.invalidate() })
        }
    }
    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        formatters = [:]; order = []
    }
    func string(_ date: Date, language: String) -> String {
        let locale = appLocale(for: language)
        let key = locale.identifier + "|" + TimeZone.current.identifier
        lock.lock()
        let formatter: DateFormatter
        if let cached = formatters[key] { formatter = cached }
        else {
            formatter = DateFormatter(); formatter.locale = locale
            formatter.dateStyle = .medium; formatter.timeStyle = .short
            if order.count == 8 { formatters[order.removeFirst()] = nil }
            formatters[key] = formatter; order.append(key)
        }
        lock.unlock()
        return formatter.string(from: date)
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

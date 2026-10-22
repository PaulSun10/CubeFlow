import Foundation
import QuartzCore

/// Cache only immutable semantic elements. Fonts, selection and UIKit layout stay on MainActor.
actor CompetitionRichDocumentStore {
    nonisolated struct Key: Hashable, Sendable {
        let html: String
        let baseURL: URL?
        var leadingTitle: String? = nil
    }
    static let shared = CompetitionRichDocumentStore()
    private var entries: [Key: [CompetitionRichHTMLElement]] = [:]
    private var order: [Key] = []
    private var pending: [Key: Task<[CompetitionRichHTMLElement], Never>] = [:]

    func elements(html: String, baseURL: URL?) async -> [CompetitionRichHTMLElement] {
        let key = Key(html: html, baseURL: baseURL)
        if let result = entries[key] { return result }
        if let task = pending[key] { return await task.value }
        let task = Task.detached(priority: .userInitiated) {
            let start = CACurrentMediaTime()
            let result = CompetitionRichHTMLElement.parse(Self.resolvingURLs(html, baseURL: baseURL))
            CompetitionLoadingTrace.record("rich-document-worker", since: start, detail: "bytes=\(html.utf8.count)")
            return result
        }
        pending[key] = task
        let result = await task.value
        pending[key] = nil
        entries[key] = result; order.append(key)
        if order.count > 32 { entries[order.removeFirst()] = nil }
        return result
    }

    nonisolated private static func resolvingURLs(_ html: String, baseURL: URL?) -> String {
        guard let baseURL, let scheme = baseURL.scheme, let host = baseURL.host else { return html }
        let origin = "\(scheme)://\(host)"
        let pattern = #"(?i)(\b(?:href|src)\s*=\s*['"])(/[^'"]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        let source = html as NSString
        let resolved = NSMutableString(string: html)
        for match in regex.matches(in: html, range: NSRange(location: 0, length: source.length)).reversed() {
            let path = source.substring(with: match.range(at: 2))
            if !path.hasPrefix("//") { resolved.replaceCharacters(in: match.range(at: 2), with: origin + path) }
        }
        return resolved as String
    }
}

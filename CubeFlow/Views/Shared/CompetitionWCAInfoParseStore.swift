import Foundation

nonisolated struct CompetitionWCAParsedInfo: Sendable {
    let blocks: [CompetitionDetailTextBlock]
    let events: [CompetitionWCAEvent]
    let championshipTitles: [String]
}

/// Reuse parsing, never HTTP freshness. A changed document/locale/time zone is a new key.
actor CompetitionWCAInfoParseStore {
    static let shared = CompetitionWCAInfoParseStore()
    private struct Key: Hashable {
        let html: String
        let language: String
        let timeZone: String
    }
    private var entries: [Key: CompetitionWCAParsedInfo] = [:]
    private var order: [Key] = []
    private var pending: [Key: Task<CompetitionWCAParsedInfo, Never>] = [:]
    private var generation = 0
    private let parse: @Sendable (String, String) -> CompetitionWCAParsedInfo

    init(parse: @escaping @Sendable (String, String) -> CompetitionWCAParsedInfo = {
        CompetitionService.parseWCAInfo(html: $0, languageCode: $1)
    }) {
        self.parse = parse
    }

    func info(html: String, language: String) async -> CompetitionWCAParsedInfo {
        let key = Key(html: html, language: language, timeZone: TimeZone.current.identifier)
        if let cached = entries[key] { return cached }
        if let task = pending[key] { return await task.value }
        let run = generation
        let parse = self.parse
        let task = Task.detached(priority: .userInitiated) { parse(html, language) }
        pending[key] = task
        let result = await task.value
        guard run == generation else { return result }
        pending[key] = nil
        entries[key] = result
        order.append(key)
        if order.count > 4 { entries[order.removeFirst()] = nil }
        return result
    }

    func clear() {
        generation += 1
        pending.values.forEach { $0.cancel() }
        pending.removeAll(); entries.removeAll(); order.removeAll()
    }
}

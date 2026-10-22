import Foundation

/// Shared network work outlives an individual section, but not its last interested screen.
actor CompetitionRequestPool<Value: Sendable> {
    private struct Work {
        let id: UUID
        let task: Task<Value, Error>
        var consumers: Set<UUID>
    }
    private var pending: [String: Work] = [:]

    func value(key: String, loader: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let consumer = UUID()
        if pending[key] == nil { pending[key] = Work(id: UUID(), task: Task { try await loader() }, consumers: []) }
        pending[key]!.consumers.insert(consumer)
        let work = pending[key]!
        return try await withTaskCancellationHandler {
            defer { if pending[key]?.id == work.id { pending[key] = nil } }
            let result = try await work.task.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            Task { await self.release(key: key, id: work.id, consumer: consumer) }
        }
    }

    private func release(key: String, id: UUID, consumer: UUID) {
        guard pending[key]?.id == id else { return }
        pending[key]?.consumers.remove(consumer)
        if pending[key]?.consumers.isEmpty == true { pending.removeValue(forKey: key)?.task.cancel() }
    }

    func cancelAll() {
        pending.values.forEach { $0.task.cancel() }
        pending.removeAll()
    }
}

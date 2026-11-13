import CoreData
import Foundation

/// The context never escapes its own perform queue; only immutable samples do.
nonisolated final class SessionSolveSnapshotReader: @unchecked Sendable {
    private let context: NSManagedObjectContext
    @MainActor init(viewContext: NSManagedObjectContext) {
        context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        var owner = viewContext
        while let parent = owner.parent { owner = parent }
        context.persistentStoreCoordinator = owner.persistentStoreCoordinator
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    func load(sessionID: UUID) async throws -> [SessionSolveSample] {
        try Task.checkCancellation()
        return try await context.perform {
            self.context.reset()
            return try self.context.fetchSolves(forSessionID: sessionID, ascending: false).map {
                SessionSolveSample(id: $0.id, date: $0.date, time: $0.time, resultRaw: $0.resultRaw,
                    scramble: $0.scramble, comment: $0.comment, eventRawValue: $0.event, inputSourceRaw: $0.inputSourceRaw)
            }
        }
    }

    func counts(sessionIDs: [UUID]) async throws -> [UUID: Int] {
        try Task.checkCancellation()
        return try await context.perform {
            self.context.reset()
            return try Dictionary(uniqueKeysWithValues: sessionIDs.map { id in
                let request = NSFetchRequest<NSFetchRequestResult>(entityName: Solve.entityName)
                request.predicate = NSPredicate(format: "session.id == %@", id as CVarArg)
                return (id, try self.context.count(for: request))
            })
        }
    }
}

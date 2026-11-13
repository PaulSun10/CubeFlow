import CoreData
import Foundation

enum SolveSessionMembership {
    enum MoveError: Error, Equatable { case invalidDestination, staleSelection }

    @discardableResult
    static func move(ids: Set<UUID>, from sourceID: UUID, to destination: Session, context: NSManagedObjectContext) throws -> Int {
        guard destination.id != sourceID, destination.managedObjectContext === context else { throw MoveError.invalidDestination }
        guard !ids.isEmpty else { return 0 }
        let solves = try context.fetchSolves(with: ids, in: sourceID)
        guard solves.count == ids.count else { throw MoveError.staleSelection }
        let originalSessions = solves.map(\.session)
        for solve in solves { solve.session = destination }
        do { try context.save() }
        catch {
            // Revert only this operation, not unrelated pending context changes.
            for (solve, original) in zip(solves, originalSessions) { solve.session = original }
            throw error
        }
        return solves.count
    }
}

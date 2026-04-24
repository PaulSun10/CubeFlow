import CoreData
import Foundation

enum SolveResult: String, CaseIterable {
    case solved
    case plusTwo
    case dnf
}

final class Solve: NSManagedObject, Identifiable {
    static let entityName = "Solve"

    @NSManaged var id: UUID
    @NSManaged var time: Double
    @NSManaged var date: Date
    @NSManaged var scramble: String
    @NSManaged var event: String
    @NSManaged var resultRaw: String
    @NSManaged var session: Session?

    var result: SolveResult {
        get { SolveResult(rawValue: resultRaw) ?? .solved }
        set { resultRaw = newValue.rawValue }
    }

    convenience init(
        time: Double,
        date: Date = .now,
        scramble: String = "",
        event: String,
        result: SolveResult = .solved,
        session: Session?,
        context: NSManagedObjectContext? = nil
    ) {
        self.init(context: context ?? session?.managedObjectContext ?? PersistenceController.shared.container.viewContext)
        self.id = UUID()
        self.time = time
        self.date = date
        self.scramble = scramble
        self.event = event
        self.resultRaw = result.rawValue
        self.session = session
    }
}

extension Solve {
    @nonobjc nonisolated class func fetchRequest() -> NSFetchRequest<Solve> {
        NSFetchRequest<Solve>(entityName: entityName)
    }
}

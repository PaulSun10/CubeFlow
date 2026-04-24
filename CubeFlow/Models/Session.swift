import CoreData
import Foundation

final class Session: NSManagedObject, Identifiable {
    static let entityName = "Session"

    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var createdAt: Date
    @NSManaged var selectedEventRawValue: String
    @NSManaged var solves: Set<Solve>?

    convenience init(
        name: String,
        createdAt: Date = .now,
        selectedEventRawValue: String = "3x3",
        context: NSManagedObjectContext = PersistenceController.shared.container.viewContext
    ) {
        self.init(context: context)
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
        self.selectedEventRawValue = selectedEventRawValue
        self.solves = []
    }

    var solveList: [Solve] {
        (solves ?? []).sorted { $0.date > $1.date }
    }

    var solveCount: Int {
        solves?.count ?? 0
    }
}

extension Session {
    @nonobjc nonisolated class func fetchRequest() -> NSFetchRequest<Session> {
        NSFetchRequest<Session>(entityName: entityName)
    }
}

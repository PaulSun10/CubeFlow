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

    var comment: String {
        get { SolveCommentStore.shared.comment(for: id) }
        set { SolveCommentStore.shared.setComment(newValue, for: id) }
    }

    convenience init(
        time: Double,
        date: Date = .now,
        scramble: String = "",
        comment: String = "",
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
        if !comment.isEmpty {
            self.comment = comment
        }
        self.event = event
        self.resultRaw = result.rawValue
        self.session = session
    }
}

private final class SolveCommentStore: @unchecked Sendable {
    static let shared = SolveCommentStore()

    private let lock = NSLock()
    private let defaultsKey = "solveCommentsByID"
    private var comments: [String: String]

    private init() {
        comments = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    func comment(for id: UUID) -> String {
        lock.lock()
        defer { lock.unlock() }
        return comments[id.uuidString] ?? ""
    }

    func setComment(_ comment: String, for id: UUID) {
        lock.lock()
        let key = id.uuidString
        guard comments[key] != comment, !(comment.isEmpty && comments[key] == nil) else {
            lock.unlock()
            return
        }
        if comment.isEmpty {
            comments.removeValue(forKey: key)
        } else {
            comments[key] = comment
        }
        UserDefaults.standard.set(comments, forKey: defaultsKey)
        lock.unlock()
    }
}

extension Solve {
    @nonobjc nonisolated class func fetchRequest() -> NSFetchRequest<Solve> {
        NSFetchRequest<Solve>(entityName: entityName)
    }
}

import CoreData
import Foundation

final class PersistenceController: @unchecked Sendable {
    nonisolated static let shared = PersistenceController()

    nonisolated let container: NSPersistentContainer

    nonisolated init(inMemory: Bool = false) {
        #if DEBUG && os(iOS)
        AppExperienceTrace.mark("persistence_begin")
        #endif
        container = NSPersistentContainer(name: "CubeFlow", managedObjectModel: Self.managedObjectModel)

        for description in container.persistentStoreDescriptions {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Could not load Core Data store: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        #if DEBUG && os(iOS)
        AppExperienceTrace.mark("persistence_ready")
        #endif
    }

    nonisolated func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    nonisolated private static let managedObjectModel: NSManagedObjectModel = {
        let model = NSManagedObjectModel()

        let sessionEntity = NSEntityDescription()
        sessionEntity.name = Session.entityName
        sessionEntity.managedObjectClassName = NSStringFromClass(Session.self)

        let solveEntity = NSEntityDescription()
        solveEntity.name = Solve.entityName
        solveEntity.managedObjectClassName = NSStringFromClass(Solve.self)

        let sessionID = attribute("id", type: .UUIDAttributeType)
        let sessionName = attribute("name", type: .stringAttributeType)
        let sessionCreatedAt = attribute("createdAt", type: .dateAttributeType)
        let sessionSelectedEvent = attribute("selectedEventRawValue", type: .stringAttributeType)
        let sessionSelectedTimingMethod = attribute(
            "selectedTimingMethodRawValue",
            type: .stringAttributeType,
            isOptional: true
        )

        let solveID = attribute("id", type: .UUIDAttributeType)
        let solveTime = attribute("time", type: .doubleAttributeType)
        let solveDate = attribute("date", type: .dateAttributeType)
        let solveScramble = attribute("scramble", type: .stringAttributeType)
        let solveEvent = attribute("event", type: .stringAttributeType)
        let solveResultRaw = attribute("resultRaw", type: .stringAttributeType)
        let solveInputSourceRaw = attribute("inputSourceRaw", type: .stringAttributeType, isOptional: true)
        let solveReconstructionData = attribute("reconstructionData", type: .binaryDataAttributeType, isOptional: true)
        solveReconstructionData.allowsExternalBinaryDataStorage = true

        let sessionSolves = NSRelationshipDescription()
        sessionSolves.name = "solves"
        sessionSolves.destinationEntity = solveEntity
        sessionSolves.minCount = 0
        sessionSolves.maxCount = 0
        sessionSolves.deleteRule = .cascadeDeleteRule
        sessionSolves.isOptional = true

        let solveSession = NSRelationshipDescription()
        solveSession.name = "session"
        solveSession.destinationEntity = sessionEntity
        solveSession.minCount = 0
        solveSession.maxCount = 1
        solveSession.deleteRule = .nullifyDeleteRule
        solveSession.isOptional = true

        sessionSolves.inverseRelationship = solveSession
        solveSession.inverseRelationship = sessionSolves

        sessionEntity.properties = [
            sessionID,
            sessionName,
            sessionCreatedAt,
            sessionSelectedEvent,
            sessionSelectedTimingMethod,
            sessionSolves
        ]
        solveEntity.properties = [
            solveID,
            solveTime,
            solveDate,
            solveScramble,
            solveEvent,
            solveResultRaw,
            solveInputSourceRaw,
            solveReconstructionData,
            solveSession
        ]

        model.entities = [sessionEntity, solveEntity]
        return model
    }()

    nonisolated private static func attribute(
        _ name: String,
        type: NSAttributeType,
        isOptional: Bool = false
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = isOptional
        return attribute
    }
}

extension NSManagedObjectContext {
    nonisolated func fetchSessionsSortedByCreationDate() throws -> [Session] {
        let request = Session.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Session.createdAt, ascending: true)]
        return try fetch(request)
    }

    nonisolated func fetchSolvesSortedByDateDescending() throws -> [Solve] {
        let request = Solve.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Solve.date, ascending: false)]
        return try fetch(request)
    }

    nonisolated func fetchSolve(with id: UUID) throws -> Solve? {
        let request = Solve.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try fetch(request).first
    }

    nonisolated func fetchSolves(with ids: Set<UUID>, in sessionID: UUID? = nil) throws -> [Solve] {
        guard !ids.isEmpty else { return [] }
        let ids = Array(ids)
        var solves: [Solve] = []
        solves.reserveCapacity(ids.count)
        // Bound each IN predicate rather than issuing one request per solve.
        for start in stride(from: 0, to: ids.count, by: 256) {
            let batch = ids[start..<min(start + 256, ids.count)].map { $0 as NSUUID }
            let request = Solve.fetchRequest()
            if let sessionID {
                request.predicate = NSPredicate(format: "id IN %@ AND session.id == %@", batch, sessionID as CVarArg)
            } else {
                request.predicate = NSPredicate(format: "id IN %@", batch)
            }
            solves.append(contentsOf: try fetch(request))
        }
        return solves
    }

    nonisolated func fetchSession(with id: UUID) throws -> Session? {
        let request = Session.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try fetch(request).first
    }

    nonisolated func fetchSolves(forSessionID sessionID: UUID, ascending: Bool = false) throws -> [Solve] {
        let request = Solve.fetchRequest()
        request.predicate = NSPredicate(format: "session.id == %@", sessionID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Solve.date, ascending: ascending)]
        return try fetch(request)
    }
}

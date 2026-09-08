import CoreData
import Foundation

final class Session: NSManagedObject, Identifiable {
    static let entityName = "Session"

    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var createdAt: Date
    @NSManaged var selectedEventRawValue: String
    @NSManaged var selectedTimingMethodRawValue: String?
    @NSManaged var solves: Set<Solve>?

    convenience init(
        name: String,
        createdAt: Date = .now,
        selectedEventRawValue: String = "3x3",
        selectedTimingMethodRawValue: String = SessionTimingMethod.timer.rawValue,
        context: NSManagedObjectContext = PersistenceController.shared.container.viewContext
    ) {
        self.init(context: context)
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
        self.selectedEventRawValue = selectedEventRawValue
        self.selectedTimingMethodRawValue = selectedTimingMethodRawValue
        self.solves = []
    }

    var solveList: [Solve] {
        (solves ?? []).sorted { $0.date > $1.date }
    }

    var solveCount: Int {
        solves?.count ?? 0
    }
}

enum SessionTimingMethod: String, CaseIterable, Identifiable, Sendable {
    case timer
    case typing
    case gan
    case smartCube

    var id: String { rawValue }
}

struct SessionTimerConfiguration: Equatable, Sendable {
    static let defaultEventRawValue = "3x3"

    let eventRawValue: String
    let timingMethod: SessionTimingMethod

    static func resolved(
        eventRawValue: String?,
        timingMethodRawValue: String?,
        legacyTimingMethodRawValue: String
    ) -> Self {
        let event = eventRawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let timingMethod = timingMethodRawValue.flatMap(SessionTimingMethod.init(rawValue:))
            ?? SessionTimingMethod(rawValue: legacyTimingMethodRawValue)
            ?? .timer
        return Self(
            eventRawValue: event ?? defaultEventRawValue,
            timingMethod: timingMethod
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension Session {
    @discardableResult
    func restoreTimerConfiguration(legacyTimingMethodRawValue: String) -> SessionTimerConfiguration {
        let configuration = SessionTimerConfiguration.resolved(
            eventRawValue: selectedEventRawValue,
            timingMethodRawValue: selectedTimingMethodRawValue,
            legacyTimingMethodRawValue: legacyTimingMethodRawValue
        )
        if selectedEventRawValue != configuration.eventRawValue {
            selectedEventRawValue = configuration.eventRawValue
        }
        if selectedTimingMethodRawValue != configuration.timingMethod.rawValue {
            selectedTimingMethodRawValue = configuration.timingMethod.rawValue
        }
        return configuration
    }

    func persistTimerConfiguration(
        eventRawValue: String? = nil,
        timingMethodRawValue: String? = nil
    ) {
        if let eventRawValue, selectedEventRawValue != eventRawValue {
            selectedEventRawValue = eventRawValue
        }
        if let timingMethodRawValue,
           let timingMethod = SessionTimingMethod(rawValue: timingMethodRawValue),
           selectedTimingMethodRawValue != timingMethod.rawValue {
            selectedTimingMethodRawValue = timingMethod.rawValue
        }
    }
}

extension Session {
    @nonobjc nonisolated class func fetchRequest() -> NSFetchRequest<Session> {
        NSFetchRequest<Session>(entityName: entityName)
    }
}

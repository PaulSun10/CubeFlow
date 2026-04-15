import Foundation
import SwiftData

@Model
final class Session {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    var selectedEventRawValue: String = "3x3"
    @Relationship(deleteRule: .cascade, inverse: \Solve.session) var solves: [Solve]? = []

    init(name: String, createdAt: Date = .now, selectedEventRawValue: String = "3x3") {
        self.name = name
        self.createdAt = createdAt
        self.selectedEventRawValue = selectedEventRawValue
        self.solves = []
    }

    var solveList: [Solve] {
        solves ?? []
    }

    var solveCount: Int {
        solveList.count
    }
}

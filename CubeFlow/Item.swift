import Foundation

struct Item: Identifiable {
    let id = UUID()
    var timestamp: Date = .now
}

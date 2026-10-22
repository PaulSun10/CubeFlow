import Foundation

nonisolated struct CubingChinaTicket: Hashable, Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let description: String?
    let feeCents: Int
    let validDates: [String]
    let saleStart: String?
    let saleEnd: String?
    let purchaseLimit: Int?
    let competitorsOnly: Bool
    let unavailableReason: String?
    var payableFeeCents: Int? = nil
    var stock: Int? = nil

    static func parse(html: String, language: String) -> [Self] {
        let rows = CubingChinaPageState(html: html)?.objects(containing: "validDates") ?? []
        var seen: Set<Int> = []
        return rows.compactMap { row in
            guard let id = row["id"] as? Int, seen.insert(id).inserted,
                  let fee = row["fee"] as? Int, fee >= 0 else { return nil }
            let chinese = language.hasPrefix("zh")
            guard let name = row[chinese ? "nameZh" : "name"] as? String ?? row["name"] as? String else { return nil }
            return Self(id: id, name: name,
                description: row[chinese ? "descriptionZh" : "description"] as? String,
                feeCents: fee, validDates: row["validDates"] as? [String] ?? [],
                saleStart: row["saleStartAt"] as? String, saleEnd: row["saleEndAt"] as? String,
                purchaseLimit: (row["purchaseLimit"] as? Int).flatMap { $0 > 0 ? $0 : nil },
                competitorsOnly: row["competitorsOnly"] as? Bool ?? false,
                unavailableReason: row["unavailableReason"] as? String,
                payableFeeCents: row["payableFee"] as? Int, stock: row["stock"] as? Int)
        }
    }

    static func isAvailable(competition: [String: Any]?) -> Bool {
        competition?["showTickets"] as? Bool == true
    }

    static func website(slug: String) -> URL? {
        guard !slug.isEmpty, !slug.contains("/"), !slug.contains(".."),
              let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://cubing.com/competition/\(encoded)/ticket")
    }
}

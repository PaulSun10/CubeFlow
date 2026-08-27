import Foundation

struct WCAOrganizationGroup: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let friendlyID: String
    let email: String?
    let preferredContactMode: WCAOrganizationContactMode
    let description: String?
}

enum WCAOrganizationContactMode: String, Hashable, Sendable, Decodable {
    case email
    case contactForm = "contact_form"
    case noContact = "no_contact"
}

struct WCAOrganizationMember: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let wcaID: String?
    let countryISO2: String?
    let countryName: String?
    let avatarURL: String?
    let status: String
}

enum WCATeamsCommitteesError: LocalizedError {
    case invalidURL
    case requestFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return currentAppLocalizedString(
                "wca.teams_committees.error",
                defaultValue: "WCA Teams and Committees is currently unavailable."
            )
        case .requestFailed:
            return currentAppLocalizedString(
                "wca.teams_committees.error",
                defaultValue: "WCA Teams and Committees is currently unavailable."
            )
        case .invalidResponse:
            return currentAppLocalizedString(
                "wca.teams_committees.invalid_response",
                defaultValue: "The WCA returned an unexpected response."
            )
        }
    }
}

actor WCATeamsCommitteesService {
    static let shared = WCATeamsCommitteesService()

    private struct APIGroup: Decodable {
        struct Metadata: Decodable {
            let email: String?
            let friendlyId: String?
            let preferredContactMode: WCAOrganizationContactMode?
        }

        let id: Int
        let name: String
        let metadata: Metadata?
    }

    private struct APIRole: Decodable {
        struct User: Decodable {
            struct Country: Decodable {
                let name: String?
                let iso2: String?
            }

            struct Avatar: Decodable {
                let url: String?
                let thumbUrl: String?
                let isDefault: Bool?
            }

            let id: Int
            let name: String
            let wcaId: String?
            let countryIso2: String?
            let country: Country?
            let avatar: Avatar?
        }

        struct Metadata: Decodable {
            let status: String?
        }

        let id: Int
        let user: User
        let metadata: Metadata?
    }

    private var cachedGroups: [WCAOrganizationGroup]?
    private var cachedMembers: [Int: [WCAOrganizationMember]] = [:]

    func groups(forceRefresh: Bool = false) async throws -> [WCAOrganizationGroup] {
        if !forceRefresh, let cachedGroups {
            return cachedGroups
        }

        var components = URLComponents(
            string: "https://www.worldcubeassociation.org/api/v0/user_groups"
        )
        components?.queryItems = [
            URLQueryItem(name: "groupType", value: "teams_committees"),
            URLQueryItem(name: "isActive", value: "true"),
            URLQueryItem(name: "isHidden", value: "false"),
            URLQueryItem(name: "sort", value: "name")
        ]
        guard let url = components?.url else {
            throw WCATeamsCommitteesError.invalidURL
        }

        let groups: [APIGroup] = try await fetch(url: url)
        let mappedGroups = groups.compactMap { group -> WCAOrganizationGroup? in
            guard let rawFriendlyID = group.metadata?.friendlyId else {
                return nil
            }
            let friendlyID = rawFriendlyID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !friendlyID.isEmpty else {
                return nil
            }

            return WCAOrganizationGroup(
                id: group.id,
                name: group.name,
                friendlyID: friendlyID,
                email: group.metadata?.email,
                preferredContactMode: group.metadata?.preferredContactMode ?? .email,
                description: WCATeamsCommitteesOfficialCopy.description(for: friendlyID)
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        cachedGroups = mappedGroups
        return mappedGroups
    }

    func members(groupID: Int, forceRefresh: Bool = false) async throws -> [WCAOrganizationMember] {
        if !forceRefresh, let cached = cachedMembers[groupID] {
            return cached
        }

        var page = 1
        var roles: [APIRole] = []

        while true {
            var components = URLComponents(
                string: "https://www.worldcubeassociation.org/api/v0/user_roles"
            )
            components?.queryItems = [
                URLQueryItem(name: "groupId", value: String(groupID)),
                URLQueryItem(name: "isActive", value: "true"),
                URLQueryItem(name: "sort", value: "status:desc,name"),
                URLQueryItem(name: "page", value: String(page))
            ]
            guard let url = components?.url else {
                throw WCATeamsCommitteesError.invalidURL
            }

            let response: ([APIRole], Int?) = try await fetchPage(url: url)
            roles.append(contentsOf: response.0)

            if response.0.isEmpty || roles.count >= (response.1 ?? roles.count) {
                break
            }
            page += 1
        }

        let members = roles.map { role in
            let avatar = role.user.avatar
            return WCAOrganizationMember(
                id: role.id,
                name: role.user.name,
                wcaID: role.user.wcaId,
                countryISO2: role.user.countryIso2 ?? role.user.country?.iso2,
                countryName: role.user.country?.name,
                avatarURL: avatar?.isDefault == true ? nil : (avatar?.url ?? avatar?.thumbUrl),
                status: role.metadata?.status ?? "member"
            )
        }

        cachedMembers[groupID] = members
        return members
    }

    private func fetch<Response: Decodable>(url: URL) async throws -> Response {
        let (data, _) = try await request(url: url)
        guard let decoded = try? decoder.decode(Response.self, from: data) else {
            throw WCATeamsCommitteesError.invalidResponse
        }
        return decoded
    }

    private func fetchPage<Response: Decodable>(url: URL) async throws -> (Response, Int?) {
        let (data, response) = try await request(url: url)
        guard let decoded = try? decoder.decode(Response.self, from: data) else {
            throw WCATeamsCommitteesError.invalidResponse
        }
        let total = response.value(forHTTPHeaderField: "Total").flatMap(Int.init)
        return (decoded, total)
    }

    private func request(url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WCATeamsCommitteesError.requestFailed
        }

        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            throw WCATeamsCommitteesError.requestFailed
        }
        return (data, httpResponse)
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

private enum WCATeamsCommitteesOfficialCopy {
    // The public API supplies groups and members but not responsibilities. These are the current
    // English descriptions from the WCA's production locale, keyed by its stable friendly ID.
    nonisolated static func description(for friendlyID: String) -> String? {
        descriptions[friendlyID.lowercased()]
    }

    nonisolated private static let descriptions: [String: String] = [
        "wat": "The WCA Archive Team (WAT) manages the development and maintenance of the WCA's historical archive. They document key speedcubing events and notable WCA milestones to be presented as part of a broader WCA timeline, to preserve the legacy of the WCA in speedcubing.",
        "wct": "The WCA Communication Team (WCT) oversees and supports communications of the WCA with the Community and the general public. The communication of the WCA should contribute to the Objectives of the WCA and support a general positive culture of friendliness, transparency, inclusiveness, openness, and responsiveness.",
        "wcat": "The WCA Competition Announcement Team (WCAT) approves and announces WCA Competitions submitted by WCA Delegates, and ensures such announcements adhere to WCA quality standards. This team is also responsible for maintaining proper competition submission protocol from documents such as the WCA Competition Requirements Policy. The WCAT is not responsible for the organization and delegation of individual competitions.",
        "wic": "The WCA Integrity Committee (WIC) performs independent investigations regarding WCA community members and incidents during WCA Competitions or on official, online WCA platforms. These incidents are alleged violations of the Values, Code of Conduct, Code of Ethics and/or Regulations of the WCA.",
        "weat": "The WCA Executive Assistants Team (WEAT) carries out the administrative tasks of the WCA Board of Directors.",
        "wfc": "The WCA Financial Committee (WFC) manages the overall finances of the WCA, including budgeting, reporting, analysis, bookkeeping, and tax filings. They also manage the WCA's largest source of income, the WCA Dues System, along with various funding programs that provide support to local communities at different stages of development, including Travel Funding, Equipment Funding, and Regional Organization Support.",
        "wmt": "The WCA Marketing Team (WMT) manages the WCA Brand, seeking sponsorships, and marketing WCA Merchandise.",
        "wmct": "The WCA Major Championships Team (WMCT) oversees the coordination and advancement of WCA Continental and World Championships by developing guidelines and strategic plans, managing host city selection, supporting organizing teams, and ensuring consistent championship experiences.",
        "wqac": "The WCA Quality Assurance Committee (WQAC) promotes continuous quality improvement within the WCA, as well as worldwide application of quality standards to ensure consistent high quality of processes, WCA Volunteers, Regional Organizations, Competition Organizers, and Competition Volunteers.",
        "wrc": "The WCA Regulations Committee (WRC) handles all issues which are related to the application, the improvement and the development of the WCA Regulations. They support WCA Delegates on any kind of procedural matters happening at competitions and decide on unresolved and uncovered incidents.",
        "wrt": "The WCA Results Team (WRT) manages all data in the databases of the WCA, including competition results and persons data.",
        "wst": "The WCA Software Team (WST) manages the WCA's software, including the website, scramblers, workbooks, and admin tools.",
        "wsot": "The WCA Sports Organization Team (WSOT) oversees and supports the recognition of the WCA as an international sports organization.",
        "wapc": "The WCA Appeals Committee reviews and resolves appeals regarding decisions made by other WCA Volunteers. It provides an independent and impartial review process to ensure that decisions are fair, reasonable, and in accordance with WCA policies and regulations."
    ]
}

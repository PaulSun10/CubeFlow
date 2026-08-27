import Foundation

struct WCADelegateRegion: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let parentRegionID: Int?
    let friendlyID: String?
    let email: String?
}

struct WCADelegateMember: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let wcaID: String?
    let countryISO2: String?
    let countryName: String?
    let email: String?
    let avatarURL: String?
    let status: String
    let location: String?
    let firstDelegated: String?
    let lastDelegated: String?
    let totalDelegated: Int?
    let leadDelegated: Int?
}

enum WCADelegatesError: LocalizedError {
    case invalidURL
    case requestFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return currentAppLocalizedString(
                "wca.delegates.invalid_response",
                defaultValue: "The WCA returned an unexpected response."
            )
        case .invalidURL, .requestFailed:
            return currentAppLocalizedString(
                "wca.delegates.error",
                defaultValue: "WCA Delegates is currently unavailable."
            )
        }
    }
}

actor WCADelegatesService {
    static let shared = WCADelegatesService()

    private struct APIGroup: Decodable {
        struct Metadata: Decodable {
            let email: String?
            let friendlyId: String?
        }

        let id: Int
        let name: String
        let parentGroupId: Int?
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
                let isDefault: Bool?
            }

            let id: Int
            let name: String
            let wcaId: String?
            let countryIso2: String?
            let country: Country?
            let email: String?
            let avatar: Avatar?
        }

        struct Metadata: Decodable {
            let status: String?
            let location: String?
            let firstDelegated: String?
            let lastDelegated: String?
            let totalDelegated: Int?
            let leadDelegated: Int?
        }

        let id: Int
        let user: User
        let metadata: Metadata?
    }

    private var cachedRegions: [WCADelegateRegion]?
    private var cachedMembers: [Int: [WCADelegateMember]] = [:]

    func regions(forceRefresh: Bool = false) async throws -> [WCADelegateRegion] {
        if !forceRefresh, let cachedRegions {
            return cachedRegions
        }

        var components = URLComponents(
            string: "https://www.worldcubeassociation.org/api/v0/user_groups"
        )
        components?.queryItems = [
            URLQueryItem(name: "groupType", value: "delegate_regions"),
            URLQueryItem(name: "isActive", value: "true"),
            URLQueryItem(name: "isHidden", value: "false"),
            URLQueryItem(name: "sort", value: "name")
        ]
        guard let url = components?.url else { throw WCADelegatesError.invalidURL }

        let groups: [APIGroup] = try await fetch(url: url)
        let regions = groups.map { group in
            WCADelegateRegion(
                id: group.id,
                name: group.name,
                parentRegionID: group.parentGroupId,
                friendlyID: group.metadata?.friendlyId?.nilIfBlank,
                email: group.metadata?.email?.nilIfBlank
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        cachedRegions = regions
        return regions
    }

    func members(regionID: Int, forceRefresh: Bool = false) async throws -> [WCADelegateMember] {
        if !forceRefresh, let cached = cachedMembers[regionID] {
            return cached
        }

        var page = 1
        var roles: [APIRole] = []
        while true {
            var components = URLComponents(
                string: "https://www.worldcubeassociation.org/api/v0/user_roles"
            )
            components?.queryItems = [
                URLQueryItem(name: "groupId", value: String(regionID)),
                URLQueryItem(name: "isActive", value: "true"),
                URLQueryItem(name: "sort", value: "location,name"),
                URLQueryItem(name: "page", value: String(page))
            ]
            guard let url = components?.url else { throw WCADelegatesError.invalidURL }

            let response: ([APIRole], Int?) = try await fetchPage(url: url)
            roles.append(contentsOf: response.0)
            if response.0.isEmpty || roles.count >= (response.1 ?? roles.count) {
                break
            }
            page += 1
        }

        // The production public page filters trainees; they are only visible in delegate admin mode.
        let members = roles.compactMap { role -> WCADelegateMember? in
            guard role.metadata?.status != "trainee_delegate" else { return nil }
            return WCADelegateMember(
                id: role.id,
                name: role.user.name,
                wcaID: role.user.wcaId,
                countryISO2: role.user.countryIso2 ?? role.user.country?.iso2,
                countryName: role.user.country?.name,
                email: role.user.email?.nilIfBlank,
                avatarURL: role.user.avatar?.isDefault == true ? nil : role.user.avatar?.url,
                status: role.metadata?.status ?? "delegate",
                location: role.metadata?.location?.nilIfBlank,
                firstDelegated: role.metadata?.firstDelegated,
                lastDelegated: role.metadata?.lastDelegated,
                totalDelegated: role.metadata?.totalDelegated,
                leadDelegated: role.metadata?.leadDelegated
            )
        }

        cachedMembers[regionID] = members
        return members
    }

    private func fetch<Response: Decodable>(url: URL) async throws -> Response {
        let (data, _) = try await request(url: url)
        guard let decoded = try? decoder.decode(Response.self, from: data) else {
            throw WCADelegatesError.invalidResponse
        }
        return decoded
    }

    private func fetchPage<Response: Decodable>(url: URL) async throws -> (Response, Int?) {
        let (data, response) = try await request(url: url)
        guard let decoded = try? decoder.decode(Response.self, from: data) else {
            throw WCADelegatesError.invalidResponse
        }
        return (decoded, response.value(forHTTPHeaderField: "Total").flatMap(Int.init))
    }

    private func request(url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WCADelegatesError.requestFailed
        }

        guard let response = response as? HTTPURLResponse,
              200 ..< 300 ~= response.statusCode else {
            throw WCADelegatesError.requestFailed
        }
        return (data, response)
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

private extension String {
    nonisolated var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

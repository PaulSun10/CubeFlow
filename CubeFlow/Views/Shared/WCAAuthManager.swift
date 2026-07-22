import Foundation
import AuthenticationServices
import Security
import UIKit
import Combine

@MainActor
final class WCAAuthManager: NSObject, ObservableObject {
    static let shared = WCAAuthManager()

    static let callbackScheme = "cubeflow-wca"
    static let redirectURI = "cubeflow-wca://oauth/callback"
    static let clientID = "v6M011TdLh8WjePMUYMTNjOfzAKeCWkD1egQzb4_JxE"
    static let clientSecret = "AqSiHhNwmNJGE2gPNo_9zTxZ-4Hl4--RXiZlEEr3--w"

    @Published private(set) var profile: WCAUserProfile?
    @Published private(set) var isSigningIn = false

    var isSignedIn: Bool {
        authSession != nil && profile != nil
    }

    private var authSession: WCAStoredAuthSession?
    private var webAuthenticationSession: ASWebAuthenticationSession?
    private var refreshTask: Task<WCAStoredAuthSession, Error>?

    private override init() {
        super.init()
        authSession = Self.loadAuthSession()
        profile = Self.loadProfile()
    }

    func signIn() async throws {
        isSigningIn = true
        defer { isSigningIn = false }

        let authorizationCode = try await requestAuthorizationCode(clientID: Self.clientID)
        let session = try await exchangeAuthorizationCode(
            authorizationCode,
            clientID: Self.clientID,
            clientSecret: Self.clientSecret
        )
        let fetchedProfile = try await fetchProfile(using: session.accessToken)

        authSession = session
        profile = fetchedProfile

        try Self.storeAuthSession(session)
        Self.storeProfile(fetchedProfile)
    }

    func refreshProfile() async throws {
        let authSession = try await validAuthSession()

        let fetchedProfile = try await fetchProfile(using: authSession.accessToken)
        profile = fetchedProfile
        Self.storeProfile(fetchedProfile)
    }

    func authorizedRequest(for url: URL) async throws -> URLRequest {
        let authSession = try await validAuthSession()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    func signOut() {
        authSession = nil
        profile = nil
        Self.deleteAuthSession()
        Self.deleteProfile()
    }
    private func requestAuthorizationCode(clientID: String) async throws -> String {
        var components = URLComponents(string: "https://www.worldcubeassociation.org/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "public")
        ]

        guard let authorizationURL = components?.url else {
            throw WCAAuthError.invalidAuthorizationURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: Self.callbackScheme
            ) { callbackURL, error in
                if let authError = error as? ASWebAuthenticationSessionError,
                   authError.code == .canceledLogin {
                    continuation.resume(throwing: WCAAuthError.cancelled)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard
                    let callbackURL,
                    let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                    let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                    !code.isEmpty
                else {
                    continuation.resume(throwing: WCAAuthError.missingAuthorizationCode)
                    return
                }

                continuation.resume(returning: code)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webAuthenticationSession = session
            session.start()
        }
    }

    private func exchangeAuthorizationCode(
        _ authorizationCode: String,
        clientID: String,
        clientSecret: String
    ) async throws -> WCAStoredAuthSession {
        guard let tokenURL = URL(string: "https://www.worldcubeassociation.org/oauth/token") else {
            throw WCAAuthError.invalidTokenURL
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: authorizationCode),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret)
        ]

        request.httpBody = Self.formEncodedBody(for: queryItems)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw Self.tokenExchangeError(from: data, response: response, invalidatesSession: false)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let tokenResponse = try decoder.decode(WCATokenResponse.self, from: data)
        let expirationDate = tokenResponse.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        return WCAStoredAuthSession(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: expirationDate
        )
    }

    private func validAuthSession() async throws -> WCAStoredAuthSession {
        guard var authSession else {
            throw WCAAuthError.notSignedIn
        }

        if let expiresAt = authSession.expiresAt,
           expiresAt <= Date().addingTimeInterval(60),
           let refreshToken = authSession.refreshToken,
           !refreshToken.isEmpty {
            do {
                authSession = try await coalescedRefresh(
                    refreshToken,
                    fallbackRefreshToken: authSession.refreshToken
                )
                self.authSession = authSession
                try Self.storeAuthSession(authSession)
            } catch let error as WCAAuthError where error.invalidatesStoredSession {
                signOut()
                throw error
            }
        }

        return authSession
    }

    private func coalescedRefresh(
        _ refreshToken: String,
        fallbackRefreshToken: String?
    ) async throws -> WCAStoredAuthSession {
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task { @MainActor in
            try await refreshAuthSession(
                refreshToken,
                fallbackRefreshToken: fallbackRefreshToken
            )
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func refreshAuthSession(
        _ refreshToken: String,
        fallbackRefreshToken: String?
    ) async throws -> WCAStoredAuthSession {
        guard let tokenURL = URL(string: "https://www.worldcubeassociation.org/oauth/token") else {
            throw WCAAuthError.invalidTokenURL
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "client_secret", value: Self.clientSecret)
        ]

        request.httpBody = Self.formEncodedBody(for: queryItems)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw Self.tokenExchangeError(from: data, response: response, invalidatesSession: true)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let tokenResponse = try decoder.decode(WCATokenResponse.self, from: data)
        let expirationDate = tokenResponse.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        return WCAStoredAuthSession(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? fallbackRefreshToken,
            expiresAt: expirationDate
        )
    }

    private func fetchProfile(using accessToken: String) async throws -> WCAUserProfile {
        guard let profileURL = URL(string: "https://www.worldcubeassociation.org/api/v0/me") else {
            throw WCAAuthError.invalidProfileURL
        }

        var request = URLRequest(url: profileURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw WCAAuthError.profileFetchFailed
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(WCAProfileEnvelope.self, from: data)
        guard let payload = envelope.me ?? envelope.user else {
            throw WCAAuthError.invalidProfileResponse
        }

        return WCAUserProfile(
            id: payload.id,
            name: payload.name,
            wcaId: payload.wcaId,
            email: payload.email,
            avatarURL: payload.avatar?.thumbUrl ?? payload.avatar?.url
        )
    }

    private static func loadAuthSession() -> WCAStoredAuthSession? {
        guard let data = try? WCAKeychainStore.data(for: .authSession) else {
            return nil
        }
        return try? JSONDecoder().decode(WCAStoredAuthSession.self, from: data)
    }

    private static func storeAuthSession(_ session: WCAStoredAuthSession) throws {
        let data = try JSONEncoder().encode(session)
        try WCAKeychainStore.set(data, for: .authSession)
    }

    private static func deleteAuthSession() {
        try? WCAKeychainStore.delete(.authSession)
    }

    private static func loadProfile() -> WCAUserProfile? {
        guard let data = UserDefaults.standard.data(forKey: WCAStorageKey.profile.rawValue) else {
            return nil
        }
        return try? JSONDecoder().decode(WCAUserProfile.self, from: data)
    }

    private static func storeProfile(_ profile: WCAUserProfile) {
        UserDefaults.standard.set(try? JSONEncoder().encode(profile), forKey: WCAStorageKey.profile.rawValue)
    }

    private static func deleteProfile() {
        UserDefaults.standard.removeObject(forKey: WCAStorageKey.profile.rawValue)
    }

    private static func formEncodedBody(for queryItems: [URLQueryItem]) -> Data? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")

        return queryItems
            .compactMap { item in
                guard
                    let encodedName = item.name.addingPercentEncoding(withAllowedCharacters: allowed),
                    let encodedValue = item.value?.addingPercentEncoding(withAllowedCharacters: allowed)
                else {
                    return nil
                }
                return "\(encodedName)=\(encodedValue)"
            }
            .joined(separator: "&")
            .data(using: .utf8)
    }

    private static func tokenExchangeError(
        from data: Data,
        response: URLResponse,
        invalidatesSession: Bool
    ) -> WCAAuthError {
        let httpStatus = (response as? HTTPURLResponse)?.statusCode
        let payload = try? JSONDecoder().decode(WCAOAuthErrorResponse.self, from: data)
        let serverMessage = [payload?.error, payload?.errorDescription]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ": ")

        let detail = serverMessage.isEmpty
            ? httpStatus.map { "HTTP \($0)" }
            : serverMessage

        if invalidatesSession,
           let errorCode = payload?.error,
           ["invalid_grant", "invalid_client"].contains(errorCode) {
            return .sessionExpired(detail)
        }
        return .tokenExchangeFailed(detail)
    }
}

extension WCAAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            return window
        }

        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            return ASPresentationAnchor(windowScene: windowScene)
        }

        fatalError("No active window scene available for WCA sign-in.")
    }
}

struct WCAUserProfile: Codable {
    let id: Int?
    let name: String
    let wcaId: String?
    let email: String?
    let avatarURL: String?

    var displayName: String {
        name.isEmpty ? "WCA" : name
    }

    var secondaryText: String {
        if let wcaId, !wcaId.isEmpty {
            return wcaId
        }
        if let email, !email.isEmpty {
            return email
        }
        return currentAppLocalizedString("settings.wca_title")
    }
}

private struct WCAStoredAuthSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
}

private struct WCATokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
}

private struct WCAOAuthErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private struct WCAProfileEnvelope: Decodable {
    let me: WCAProfilePayload?
    let user: WCAProfilePayload?
}

private struct WCAProfilePayload: Decodable {
    let id: Int?
    let name: String
    let wcaId: String?
    let email: String?
    let avatar: WCAAvatarPayload?
}

private struct WCAAvatarPayload: Decodable {
    let url: String?
    let thumbUrl: String?
}

enum WCAAuthError: LocalizedError {
    case missingClientConfiguration
    case invalidAuthorizationURL
    case invalidTokenURL
    case invalidProfileURL
    case missingAuthorizationCode
    case tokenExchangeFailed(String?)
    case sessionExpired(String?)
    case profileFetchFailed
    case invalidProfileResponse
    case cancelled
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .missingClientConfiguration:
            return currentAppLocalizedString("settings.wca_error_missing_configuration")
        case .invalidAuthorizationURL, .invalidTokenURL, .invalidProfileURL:
            return currentAppLocalizedString("settings.wca_error_invalid_request")
        case .missingAuthorizationCode:
            return currentAppLocalizedString("settings.wca_error_missing_code")
        case .tokenExchangeFailed(let detail):
            return Self.message(
                currentAppLocalizedString("settings.wca_error_token_exchange"),
                detail: detail
            )
        case .sessionExpired(let detail):
            return Self.message(
                currentAppLocalizedString("settings.wca_error_session_expired"),
                detail: detail
            )
        case .profileFetchFailed:
            return currentAppLocalizedString("settings.wca_error_profile")
        case .invalidProfileResponse:
            return currentAppLocalizedString("settings.wca_error_profile_response")
        case .cancelled:
            return currentAppLocalizedString("settings.wca_error_cancelled")
        case .notSignedIn:
            return currentAppLocalizedString("settings.wca_error_not_signed_in")
        }
    }

    var invalidatesStoredSession: Bool {
        if case .sessionExpired = self { return true }
        return false
    }

    private static func message(_ message: String, detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return message }
        return "\(message)\n\nWCA: \(detail)"
    }
}

private enum WCAKeychainKey: String {
    case authSession = "wca_auth_session"
}

private enum WCAStorageKey: String {
    case profile = "wca_profile"
}

private enum WCAKeychainStore {
    static func set(_ string: String, for key: WCAKeychainKey) throws {
        guard let data = string.data(using: .utf8) else { return }
        try set(data, for: key)
    }

    static func string(for key: WCAKeychainKey) throws -> String? {
        guard let data = try data(for: key) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ data: Data, for key: WCAKeychainKey) throws {
        let query = baseQuery(for: key)
        let attributes = [kSecValueData: data] as CFDictionary
        let updateStatus = SecItemUpdate(query, attributes)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
        }

        var addQuery = query as! [CFString: Any]
        addQuery[kSecValueData] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
        }
    }

    static func data(for key: WCAKeychainKey) throws -> Data? {
        var query = baseQuery(for: key) as! [CFString: Any]
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return result as? Data
    }

    static func delete(_ key: WCAKeychainKey) throws {
        let status = SecItemDelete(baseQuery(for: key))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private static func baseQuery(for key: WCAKeychainKey) -> CFDictionary {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.paulsun.CubeFlow",
            kSecAttrAccount: key.rawValue
        ] as CFDictionary
    }
}

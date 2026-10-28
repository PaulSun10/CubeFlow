import Foundation

nonisolated protocol WCAOAuthBrokerTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

nonisolated private protocol WCAOAuthBrokerRedacted: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {}

extension WCAOAuthBrokerRedacted {
    nonisolated var description: String { "<redacted OAuth value>" }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: EmptyCollection<(label: String?, value: Any)>()) }
}

/// HTTP only. Attempt ownership, persistence, retries and session decisions belong to the coordinator.
nonisolated struct WCAOAuthBrokerClient: Sendable {
    private let transport: any WCAOAuthBrokerTransport

    // No default/shared client: wiring a real transport must be an explicit later integration step.
    init(transport: any WCAOAuthBrokerTransport) { self.transport = transport }

    nonisolated enum RequestField: String, Sendable {
        case codeChallenge, appState, ticket, codeVerifier, brokerSessionToken, requestBody, destination
    }

    nonisolated enum ErrorCode: String, Decodable, Sendable {
        case invalidRequest = "invalid_request"
        case invalidVerifier = "invalid_verifier"
        case sessionInvalid = "session_invalid"
        case sessionExpired = "session_expired"
        case sessionRevoked = "session_revoked"
        case ticketUsed = "ticket_used"
        case transactionExpired = "transaction_expired"
        case ticketExpired = "ticket_expired"
        case rateLimited = "rate_limited"
        case providerUnavailable = "provider_unavailable"
        case temporarilyUnavailable = "temporarily_unavailable"

        fileprivate func permits(status: Int) -> Bool {
            switch self {
            case .invalidRequest: return [400, 404, 405].contains(status)
            case .invalidVerifier: return status == 400
            case .sessionInvalid, .sessionExpired, .sessionRevoked: return status == 401
            case .ticketUsed: return status == 409
            case .transactionExpired, .ticketExpired: return status == 410
            case .rateLimited: return status == 429
            case .providerUnavailable: return status == 502
            case .temporarilyUnavailable: return status == 503
            }
        }
    }

    nonisolated enum TransportFailure: Equatable, Sendable {
        case timedOut, connectionFailure, cancelled, unexpected
        case urlError(Int)
    }

    nonisolated enum Failure: Error, Equatable, Sendable, LocalizedError {
        case invalidRequest(RequestField)
        case broker(status: Int, code: ErrorCode, requestID: String, retryAfterSeconds: Int?)
        case http(status: Int, retryAfterSeconds: Int?)
        case transport(TransportFailure)
        case malformedResponse
        case redirectRejected(status: Int)

        var errorDescription: String? {
            switch self {
            case .invalidRequest: return "Invalid OAuth Broker request."
            case .broker(let status, let code, _, _): return "OAuth Broker: HTTP \(status), \(code.rawValue)."
            case .http(let status, _): return "OAuth Broker: HTTP \(status)."
            case .transport: return "OAuth Broker transport failed."
            case .malformedResponse: return "Invalid OAuth Broker response."
            case .redirectRejected: return "OAuth Broker redirect rejected."
            }
        }
    }

    nonisolated struct BrokerSessionToken: Sendable, Decodable, WCAOAuthBrokerRedacted {
        let rawValue: String

        init(rawValue: String) throws {
            guard Self.isValid(rawValue) else { throw Failure.invalidRequest(.brokerSessionToken) }
            self.rawValue = rawValue
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard Self.isValid(value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Broker credential.")
            }
            rawValue = value
        }

        private static func isValid(_ value: String) -> Bool { Validation.opaque(value) }
    }

    nonisolated struct WCAAccessToken: Sendable, Decodable, WCAOAuthBrokerRedacted {
        let rawValue: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard !value.isEmpty, value.utf8.count <= 8192,
                  value.utf8.allSatisfy({ (33...126).contains($0) }) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid WCA credential.")
            }
            rawValue = value
        }
    }

    nonisolated struct StartRequest: Encodable, Sendable, WCAOAuthBrokerRedacted {
        let codeChallenge: String
        let codeChallengeMethod = "S256"
        let appState: String

        nonisolated enum CodingKeys: String, CodingKey {
            case codeChallenge = "code_challenge", codeChallengeMethod = "code_challenge_method", appState = "app_state"
        }

        init(codeChallenge: String, appState: String) throws {
            guard Validation.challenge(codeChallenge) else { throw Failure.invalidRequest(.codeChallenge) }
            guard Validation.unreserved(appState, count: 16...256) else { throw Failure.invalidRequest(.appState) }
            self.codeChallenge = codeChallenge
            self.appState = appState
        }
    }

    nonisolated struct StartResponse: Decodable, Sendable, WCAOAuthBrokerRedacted {
        let authorizationURL: URL
        let transactionExpiresAt: Int64

        nonisolated enum CodingKeys: String, CodingKey {
            case authorizationURL = "authorization_url", transactionExpiresAt = "transaction_expires_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let text = try container.decode(String.self, forKey: .authorizationURL)
            guard let url = Validation.authorizationURL(text) else {
                throw DecodingError.dataCorruptedError(forKey: .authorizationURL, in: container,
                                                      debugDescription: "Invalid authorization URL.")
            }
            authorizationURL = url
            transactionExpiresAt = try container.decode(Int64.self, forKey: .transactionExpiresAt)
        }
    }

    nonisolated struct CompleteRequest: Encodable, Sendable, WCAOAuthBrokerRedacted {
        let ticket: String
        let codeVerifier: String

        nonisolated enum CodingKeys: String, CodingKey { case ticket, codeVerifier = "code_verifier" }

        init(ticket: String, codeVerifier: String) throws {
            guard Validation.opaque(ticket) else { throw Failure.invalidRequest(.ticket) }
            guard Validation.unreserved(codeVerifier, count: 43...128) else { throw Failure.invalidRequest(.codeVerifier) }
            self.ticket = ticket
            self.codeVerifier = codeVerifier
        }
    }

    nonisolated struct CompleteResponse: Decodable, Sendable, WCAOAuthBrokerRedacted {
        let sessionID: String
        let brokerSessionToken: BrokerSessionToken
        let brokerSessionExpiresAt: Int64
        let wcaAccessToken: WCAAccessToken
        let wcaAccessTokenExpiresAt: Int64
        let serverTime: Int64
        let tokenGeneration: Int64

        nonisolated enum CodingKeys: String, CodingKey {
            case sessionID = "session_id", brokerSessionToken = "broker_session_token"
            case brokerSessionExpiresAt = "broker_session_expires_at", wcaAccessToken = "wca_access_token"
            case wcaAccessTokenExpiresAt = "wca_access_token_expires_at", serverTime = "server_time"
            case tokenGeneration = "token_generation"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sessionID = try c.decode(String.self, forKey: .sessionID)
            brokerSessionToken = try c.decode(BrokerSessionToken.self, forKey: .brokerSessionToken)
            brokerSessionExpiresAt = try c.decode(Int64.self, forKey: .brokerSessionExpiresAt)
            wcaAccessToken = try c.decode(WCAAccessToken.self, forKey: .wcaAccessToken)
            wcaAccessTokenExpiresAt = try c.decode(Int64.self, forKey: .wcaAccessTokenExpiresAt)
            serverTime = try c.decode(Int64.self, forKey: .serverTime)
            tokenGeneration = try c.decode(Int64.self, forKey: .tokenGeneration)
            guard Validation.opaque(sessionID), tokenGeneration == 1 else { throw Failure.malformedResponse }
        }
    }

    nonisolated struct RefreshResponse: Decodable, Sendable, WCAOAuthBrokerRedacted {
        let sessionID: String
        let wcaAccessToken: WCAAccessToken
        let wcaAccessTokenExpiresAt: Int64
        let serverTime: Int64
        let tokenGeneration: Int64

        nonisolated enum CodingKeys: String, CodingKey {
            case sessionID = "session_id", wcaAccessToken = "wca_access_token"
            case wcaAccessTokenExpiresAt = "wca_access_token_expires_at", serverTime = "server_time"
            case tokenGeneration = "token_generation"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sessionID = try c.decode(String.self, forKey: .sessionID)
            wcaAccessToken = try c.decode(WCAAccessToken.self, forKey: .wcaAccessToken)
            wcaAccessTokenExpiresAt = try c.decode(Int64.self, forKey: .wcaAccessTokenExpiresAt)
            serverTime = try c.decode(Int64.self, forKey: .serverTime)
            tokenGeneration = try c.decode(Int64.self, forKey: .tokenGeneration)
            guard Validation.opaque(sessionID), tokenGeneration >= 2 else { throw Failure.malformedResponse }
        }
    }

    func start(_ input: StartRequest) async throws -> StartResponse {
        try await decode(StartResponse.self, from: send(.start, body: JSONEncoder().encode(input)))
    }

    func complete(_ input: CompleteRequest) async throws -> CompleteResponse {
        try await decode(CompleteResponse.self, from: send(.complete, body: JSONEncoder().encode(input)))
    }

    func refresh(sessionToken: BrokerSessionToken, idempotencyKey: UUID) async throws -> RefreshResponse {
        // Old/expired replays remain valid DTOs. The later coordinator owns ordering and expiry decisions.
        return try await decode(RefreshResponse.self, from: send(.refresh, body: Data("{}".utf8),
            token: sessionToken, idempotencyKey: idempotencyKey))
    }

    func logout(sessionToken: BrokerSessionToken) async throws {
        let data = try await send(.logout, body: Data("{}".utf8), token: sessionToken)
        guard data.isEmpty else { throw Failure.malformedResponse }
    }

    nonisolated private enum Endpoint: String {
        case start = "/v1/oauth/wca/start", complete = "/v1/oauth/wca/complete"
        case refresh = "/v1/oauth/wca/refresh", logout = "/v1/oauth/wca/logout"
    }

    fileprivate static func permitsNetworkRequest(_ request: URLRequest) -> Bool {
        guard request.httpMethod == "POST", let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              Endpoint(rawValue: components.percentEncodedPath) != nil else { return false }
        return Validation.brokerURL(url, path: components.percentEncodedPath)
    }

    private func send(_ endpoint: Endpoint, body: Data, token: BrokerSessionToken? = nil,
                      idempotencyKey: UUID? = nil) async throws -> Data {
        guard body.count <= 4096,
              let url = URL(string: "https://api.cubeflow.com.cn" + endpoint.rawValue),
              Validation.brokerURL(url, path: endpoint.rawValue) else { throw Failure.invalidRequest(.requestBody) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer " + token.rawValue, forHTTPHeaderField: "Authorization") }
        if let idempotencyKey { request.setValue(idempotencyKey.uuidString.lowercased(), forHTTPHeaderField: "Idempotency-Key") }

        let result: (Data, URLResponse)
        do { result = try await transport.data(for: request) }
        catch {
            if error is CancellationError { throw Failure.transport(.cancelled) }
            guard let urlError = error as? URLError else { throw Failure.transport(.unexpected) }
            switch urlError.code {
            case .cancelled: throw Failure.transport(.cancelled)
            case .timedOut: throw Failure.transport(.timedOut)
            case .cannotFindHost, .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost, .dnsLookupFailed:
                throw Failure.transport(.connectionFailure)
            default: throw Failure.transport(.urlError(urlError.code.rawValue))
            }
        }
        guard let response = result.1 as? HTTPURLResponse, let responseURL = response.url,
              Validation.brokerURL(responseURL, path: endpoint.rawValue) else { throw Failure.malformedResponse }
        let status = response.statusCode
        if (300..<400).contains(status) { throw Failure.redirectRejected(status: status) }
        let isJSON = response.value(forHTTPHeaderField: "Content-Type")?
            .split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json"
        if !(200..<300).contains(status) {
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init).flatMap { $0 >= 0 ? $0 : nil }
            if isJSON, let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: result.0),
               envelope.error.message == envelope.error.code.rawValue,
               Validation.opaque(envelope.error.requestID), envelope.error.code.permits(status: status) {
                throw Failure.broker(status: status, code: envelope.error.code,
                                     requestID: envelope.error.requestID, retryAfterSeconds: retryAfter)
            }
            throw Failure.http(status: status, retryAfterSeconds: retryAfter)
        }
        guard status == (endpoint == .logout ? 204 : 200), endpoint == .logout || isJSON else {
            throw Failure.malformedResponse
        }
        return result.0
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw Failure.malformedResponse }
    }

    nonisolated private struct ErrorEnvelope: Decodable {
        let error: Detail
        nonisolated enum CodingKeys: String, CodingKey { case error }
        nonisolated struct Detail: Decodable {
            let code: ErrorCode
            let message: String
            let requestID: String
            nonisolated enum CodingKeys: String, CodingKey { case code, message, requestID = "request_id" }
        }
    }

    nonisolated private enum Validation {
        static func opaque(_ value: String) -> Bool {
            value.utf8.count == 43 && value.utf8.allSatisfy { alphanumeric($0) || $0 == 45 || $0 == 95 }
        }
        static func unreserved(_ value: String, count: ClosedRange<Int>) -> Bool {
            count.contains(value.utf8.count) && value.utf8.allSatisfy { alphanumeric($0) || [45, 46, 95, 126].contains($0) }
        }
        static func alphanumeric(_ byte: UInt8) -> Bool {
            (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
        }
        static func challenge(_ value: String) -> Bool {
            guard opaque(value), let data = Data(base64Encoded: value.replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/") + "="), data.count == 32 else { return false }
            return data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") == value
        }
        static func brokerURL(_ url: URL, path: String) -> Bool {
            guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
            return c.scheme?.lowercased() == "https" && c.host?.lowercased() == "api.cubeflow.com.cn"
                && (c.port == nil || c.port == 443) && c.user == nil && c.password == nil
                && c.percentEncodedPath == path && c.query == nil && c.fragment == nil
        }
        static func authorizationURL(_ value: String) -> URL? {
            guard let url = URL(string: value), let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  c.scheme?.lowercased() == "https", c.host?.lowercased() == "www.worldcubeassociation.org",
                  c.port == nil || c.port == 443, c.user == nil, c.password == nil, c.fragment == nil,
                  c.percentEncodedPath == "/oauth/authorize", let items = c.queryItems,
                  items.count == 5 else { return nil }
            var fields: [String: String] = [:]
            for item in items {
                guard fields[item.name] == nil, let value = item.value else { return nil }
                fields[item.name] = value
            }
            guard fields["client_id"]?.isEmpty == false, fields["response_type"] == "code",
                  fields["scope"] == "public", fields["state"].map(opaque) == true,
                  fields["redirect_uri"] == "https://api.cubeflow.com.cn/v1/oauth/wca/callback" else { return nil }
            return url
        }
    }
}

nonisolated final class WCAOAuthBrokerRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

nonisolated final class WCAOAuthBrokerURLSessionTransport: WCAOAuthBrokerTransport, @unchecked Sendable {
    private let session: URLSession

    init() {
        session = URLSession(configuration: Self.configuration(), delegate: WCAOAuthBrokerRedirectDelegate(), delegateQueue: nil)
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Bound the coordinator's explicit operations, including best-effort logout, even under a trickling response.
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return configuration
    }

    static func permits(_ request: URLRequest) -> Bool { WCAOAuthBrokerClient.permitsNetworkRequest(request) }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard Self.permits(request) else { throw WCAOAuthBrokerClient.Failure.invalidRequest(.destination) }
        return try await session.data(for: request)
    }
    deinit { session.invalidateAndCancel() }
}

import CryptoKit
import Foundation
import Security

nonisolated protocol WCABrokerRandomSource: Sendable {
    func bytes(count: Int) throws -> Data
}

nonisolated struct WCABrokerSecureRandom: WCABrokerRandomSource {
    func bytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw WCABrokerOAuthAttempt.Failure.randomUnavailable
        }
        return Data(bytes)
    }
}

nonisolated protocol WCABrokerAttemptClock: Sendable {
    func read() -> WCABrokerAttemptTime
}

nonisolated struct WCABrokerAttemptTime: Sendable {
    let wall: TimeInterval
    let uptime: TimeInterval
}

nonisolated struct WCABrokerSystemAttemptClock: WCABrokerAttemptClock {
    func read() -> WCABrokerAttemptTime {
        .init(wall: Date().timeIntervalSince1970, uptime: ProcessInfo.processInfo.systemUptime)
    }
}

nonisolated private protocol WCABrokerAttemptRedacted: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {}

extension WCABrokerAttemptRedacted {
    nonisolated var description: String { "<redacted OAuth attempt>" }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: EmptyCollection<(label: String?, value: Any)>()) }
}

/// Memory-only ownership, not browser/network orchestration. All transitions are synchronous on MainActor.
@MainActor
final class WCABrokerOAuthAttempt: WCABrokerAttemptRedacted {
    nonisolated enum State: Sendable {
        case prepared, awaitingStart, authorizing, ticketReceived, completionClaimed
        case completionConfirmed, completionOutcomeUnknown, denied, rejected, cancelled, expired
    }

    nonisolated enum Failure: Error, Equatable, Sendable {
        case randomUnavailable, invalidVerifier, invalidState, invalidAuthorizationURL
        case invalidCallback, stateMismatch, invalidClock, invalidTransaction, expired, invalidClaim
    }

    /// Trusted integration configuration only; never derive expectations from a Broker response.
    nonisolated struct URLExpectations: Sendable {
        var authorizationHost = "www.worldcubeassociation.org"
        var authorizationPath = "/oauth/authorize"
        var brokerRedirect = "https://api.cubeflow.com.cn/v1/oauth/wca/callback"
        var callbackScheme = "cubeflow-wca"
        var callbackHost = "oauth"
        var callbackPath = "/callback"
    }

    nonisolated struct Authorization: Sendable, WCABrokerAttemptRedacted {
        let url: URL
        let transactionExpiresAt: Int64
    }

    nonisolated struct CompletionClaim: Sendable, WCABrokerAttemptRedacted {
        let id: UUID
        let request: WCAOAuthBrokerClient.CompleteRequest
    }

    private struct Deadline {
        let wall: TimeInterval
        let startUptime: TimeInterval
        let duration: TimeInterval

        func permits(_ now: WCABrokerAttemptTime) -> Bool {
            now.wall < wall && now.uptime >= startUptime && now.uptime - startUptime < duration
        }
    }

    let id = UUID()
    private(set) var state: State = .prepared
    private let clock: any WCABrokerAttemptClock
    private let expectations: URLExpectations
    private var verifier: String?
    private var appState: String?
    private var ticket: String?
    private var transaction: Deadline?
    private var ticketUse: Deadline?
    private var claimID: UUID?
    private let margin: TimeInterval = 5

    init(random: any WCABrokerRandomSource = WCABrokerSecureRandom(),
         clock: any WCABrokerAttemptClock = WCABrokerSystemAttemptClock(),
         expectations: URLExpectations = .init()) throws {
        self.clock = clock
        self.expectations = expectations
        do {
            let verifierBytes = try random.bytes(count: 32)
            let stateBytes = try random.bytes(count: 32)
            guard verifierBytes.count == 32, stateBytes.count == 32 else { throw Failure.randomUnavailable }
            verifier = Self.base64URL(verifierBytes)
            appState = Self.base64URL(stateBytes)
        } catch { throw Failure.randomUnavailable }
    }

    /// Accept the RFC's full verifier grammar, independently of our 32-byte production generator.
    nonisolated static func s256Challenge(for verifier: String) throws -> String {
        guard (43...128).contains(verifier.utf8.count), verifier.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95, 126].contains($0)
        }) else { throw Failure.invalidVerifier }
        return base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    func makeStartRequest() throws -> WCAOAuthBrokerClient.StartRequest {
        guard state == .prepared, let verifier, let appState else { throw Failure.invalidState }
        let request = try WCAOAuthBrokerClient.StartRequest(codeChallenge: Self.s256Challenge(for: verifier), appState: appState)
        state = .awaitingStart
        return request
    }

    func prepareAuthorization(url: URL, transactionExpiresAt: Int64) throws -> Authorization {
        guard state == .awaitingStart else { throw Failure.invalidState }
        guard validAuthorizationURL(url) else { invalidate(.rejected); throw Failure.invalidAuthorizationURL }
        let now = try time()
        let end = TimeInterval(transactionExpiresAt) - margin
        let remaining = end - now.wall
        guard remaining > 0 else { invalidate(.expired); throw Failure.expired }
        // Start has no server_time: large skew cannot be calibrated safely. Fail closed, never invent now+600.
        guard remaining <= 600 else { invalidate(.rejected); throw Failure.invalidTransaction }
        transaction = .init(wall: end, startUptime: now.uptime, duration: remaining)
        state = .authorizing
        return .init(url: url, transactionExpiresAt: transactionExpiresAt)
    }

    /// Call immediately before presentation too, if authorization preparation and browser launch are separated.
    func validateBeforeBrowserLaunch() throws {
        guard state == .authorizing else { throw Failure.invalidState }
        try checkTransaction(at: time())
    }

    func receiveCallback(_ url: URL) throws {
        guard state == .authorizing else { throw Failure.invalidState }
        let now = try time()
        try checkTransaction(at: now)
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme?.lowercased() == expectations.callbackScheme.lowercased(),
              c.host?.lowercased() == expectations.callbackHost.lowercased(),
              c.percentEncodedPath == expectations.callbackPath, c.port == nil,
              c.user == nil, c.password == nil, c.fragment == nil,
              let values = Self.uniqueQuery(c), values.count == 2,
              Set(values.keys) == ["ticket", "state"] || Set(values.keys) == ["error", "state"] else {
            invalidate(.rejected); throw Failure.invalidCallback
        }
        guard let expected = appState, let received = values["state"], Self.equalState(expected, received) else {
            invalidate(.rejected); throw Failure.stateMismatch
        }
        if let error = values["error"] {
            guard error == "access_denied" else { invalidate(.rejected); throw Failure.invalidCallback }
            invalidate(.denied)
            return
        }
        guard let value = values["ticket"], Self.opaque(value), let transaction else {
            invalidate(.rejected); throw Failure.invalidCallback
        }
        // Receipt is NOT issuance. This is only a conservative local use bound; the server remains authoritative.
        let end = min(transaction.wall, now.wall + 60 - margin)
        let remaining = min(end - now.wall, transaction.duration - (now.uptime - transaction.startUptime))
        ticketUse = .init(wall: end, startUptime: now.uptime, duration: remaining)
        ticket = value
        state = .ticketReceived
    }

    func claimCompletion() throws -> CompletionClaim {
        guard state == .ticketReceived, let ticket, let verifier else { throw Failure.invalidState }
        let now = try time()
        try checkTransaction(at: now)
        guard ticketUse?.permits(now) == true else { invalidate(.expired); throw Failure.expired }
        let request = try WCAOAuthBrokerClient.CompleteRequest(ticket: ticket, codeVerifier: verifier)
        let identifier = UUID()
        // Irreversible BEFORE returning the credential. No await, reset, retry or reentrant reclaim path.
        claimID = identifier
        state = .completionClaimed
        clearCredentials()
        return .init(id: identifier, request: request)
    }

    func confirmCompletion(claimID: UUID) throws {
        try finishClaim(claimID, as: .completionConfirmed)
    }

    func markCompletionOutcomeUnknown(claimID: UUID) throws {
        try finishClaim(claimID, as: .completionOutcomeUnknown)
    }

    func cancel() {
        switch state {
        case .completionClaimed: invalidate(.completionOutcomeUnknown)
        case .prepared, .awaitingStart, .authorizing, .ticketReceived: invalidate(.cancelled)
        default: break
        }
    }

    private func finishClaim(_ identifier: UUID, as result: State) throws {
        guard state == .completionClaimed, claimID == identifier else { throw Failure.invalidClaim }
        invalidate(result)
    }

    private func time() throws -> WCABrokerAttemptTime {
        let now = clock.read()
        guard now.wall.isFinite, now.uptime.isFinite, now.uptime >= 0 else {
            invalidate(.rejected); throw Failure.invalidClock
        }
        return now
    }

    private func checkTransaction(at now: WCABrokerAttemptTime) throws {
        guard transaction?.permits(now) == true else { invalidate(.expired); throw Failure.expired }
    }

    private func invalidate(_ result: State) {
        state = result
        clearCredentials()
        transaction = nil
        ticketUse = nil
        claimID = nil
    }

    private func clearCredentials() { verifier = nil; appState = nil; ticket = nil }

    private func validAuthorizationURL(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme?.lowercased() == "https",
              c.host?.lowercased() == expectations.authorizationHost.lowercased(),
              c.percentEncodedPath == expectations.authorizationPath, (c.port == nil || c.port == 443),
              c.user == nil, c.password == nil, c.fragment == nil,
              let q = Self.uniqueQuery(c), Set(q.keys) == ["client_id", "redirect_uri", "response_type", "scope", "state"],
              q["client_id"]?.isEmpty == false, q["redirect_uri"] == expectations.brokerRedirect,
              q["response_type"] == "code", q["scope"] == "public", let state = q["state"], Self.opaque(state) else { return false }
        return true
    }

    private static func uniqueQuery(_ components: URLComponents) -> [String: String]? {
        guard let items = components.queryItems else { return nil }
        var values: [String: String] = [:]
        for item in items {
            guard let value = item.value, values[item.name] == nil else { return nil }
            values[item.name] = value
        }
        return values
    }

    nonisolated private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    nonisolated private static func opaque(_ value: String) -> Bool {
        value.utf8.count == 43 && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }

    nonisolated private static func equalState(_ lhs: String, _ rhs: String) -> Bool {
        // Length is public; compare all bytes for equal-length input without early exit.
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

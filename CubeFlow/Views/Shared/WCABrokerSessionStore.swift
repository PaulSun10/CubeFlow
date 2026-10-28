import Foundation
import Security

/// Synchronous operations: a store never suspends between the steps of one persistence operation.
nonisolated protocol WCABrokerKeychainOperations: Sendable {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Any?)
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func add(_ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

nonisolated struct WCABrokerSystemKeychain: WCABrokerKeychainOperations {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Any?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
    func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}

nonisolated private protocol WCABrokerStoreRedacted: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {}

extension WCABrokerStoreRedacted {
    nonisolated var description: String { "<redacted Broker session>" }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: EmptyCollection<(label: String?, value: Any)>()) }
}

/// This is a persistence schema, NOT the Broker wire schema or an authentication state publisher.
nonisolated struct WCABrokerStoredSession: Codable, Sendable, WCABrokerStoreRedacted {
    static let schemaVersion = 2
    static let provider = "wca-broker-v1"

    nonisolated enum RecoveryState: String, Codable, Sendable { case pending, recoveryPending, uncertain }

    nonisolated struct PendingRefresh: Codable, Sendable, WCABrokerStoreRedacted {
        let sessionID: String
        let id: UUID
        let recoveryState: RecoveryState
        let dispatchCount: Int
        let retryNotBefore: Int64?

        init(sessionID: String, id: UUID, recoveryState: RecoveryState,
             dispatchCount: Int = 0, retryNotBefore: Int64? = nil) {
            self.sessionID = sessionID
            self.id = id
            self.recoveryState = recoveryState
            self.dispatchCount = dispatchCount
            self.retryNotBefore = retryNotBefore
        }

        nonisolated private enum CodingKeys: String, CodingKey {
            case sessionID, id, recoveryState, dispatchCount, retryNotBefore
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sessionID = try c.decode(String.self, forKey: .sessionID)
            id = try c.decode(UUID.self, forKey: .id)
            recoveryState = try c.decode(RecoveryState.self, forKey: .recoveryState)
            // Old v2 pending records have no known retry budget. Never grant a new budget on restart.
            dispatchCount = try c.decodeIfPresent(Int.self, forKey: .dispatchCount) ?? 2
            retryNotBefore = try c.decodeIfPresent(Int64.self, forKey: .retryNotBefore)
        }
    }

    let sessionID: String
    let brokerSessionToken: WCAOAuthBrokerClient.BrokerSessionToken
    let brokerSessionExpiresAt: Int64
    let wcaAccessToken: WCAOAuthBrokerClient.WCAAccessToken
    let wcaAccessTokenExpiresAt: Int64
    let tokenGeneration: Int64
    let pendingRefresh: PendingRefresh?

    init(sessionID: String, brokerSessionToken: WCAOAuthBrokerClient.BrokerSessionToken,
         brokerSessionExpiresAt: Int64, wcaAccessToken: WCAOAuthBrokerClient.WCAAccessToken,
         wcaAccessTokenExpiresAt: Int64, tokenGeneration: Int64, pendingRefresh: PendingRefresh? = nil) throws {
        self.sessionID = sessionID
        self.brokerSessionToken = brokerSessionToken
        self.brokerSessionExpiresAt = brokerSessionExpiresAt
        self.wcaAccessToken = wcaAccessToken
        self.wcaAccessTokenExpiresAt = wcaAccessTokenExpiresAt
        self.tokenGeneration = tokenGeneration
        self.pendingRefresh = pendingRefresh
        try validate()
    }

    nonisolated private enum CodingKeys: String, CodingKey {
        case schemaVersion, provider, recordKind, sessionID, brokerSessionToken, brokerSessionExpiresAt
        case wcaAccessToken, wcaAccessTokenExpiresAt, tokenGeneration, pendingRefresh
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw WCABrokerSessionStore.Failure.unsupportedSchema
        }
        guard try c.decode(String.self, forKey: .provider) == Self.provider else {
            throw WCABrokerSessionStore.Failure.unsupportedProvider
        }
        guard try c.decode(String.self, forKey: .recordKind) == "session" else {
            throw WCABrokerSessionStore.Failure.corruptedData
        }
        sessionID = try c.decode(String.self, forKey: .sessionID)
        brokerSessionToken = try c.decode(WCAOAuthBrokerClient.BrokerSessionToken.self, forKey: .brokerSessionToken)
        brokerSessionExpiresAt = try c.decode(Int64.self, forKey: .brokerSessionExpiresAt)
        wcaAccessToken = try c.decode(WCAOAuthBrokerClient.WCAAccessToken.self, forKey: .wcaAccessToken)
        wcaAccessTokenExpiresAt = try c.decode(Int64.self, forKey: .wcaAccessTokenExpiresAt)
        tokenGeneration = try c.decode(Int64.self, forKey: .tokenGeneration)
        pendingRefresh = try c.decodeIfPresent(PendingRefresh.self, forKey: .pendingRefresh)
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.schemaVersion, forKey: .schemaVersion)
        try c.encode(Self.provider, forKey: .provider)
        try c.encode("session", forKey: .recordKind)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(brokerSessionToken.rawValue, forKey: .brokerSessionToken)
        try c.encode(brokerSessionExpiresAt, forKey: .brokerSessionExpiresAt)
        try c.encode(wcaAccessToken.rawValue, forKey: .wcaAccessToken)
        try c.encode(wcaAccessTokenExpiresAt, forKey: .wcaAccessTokenExpiresAt)
        try c.encode(tokenGeneration, forKey: .tokenGeneration)
        try c.encodeIfPresent(pendingRefresh, forKey: .pendingRefresh)
    }

    private func validate() throws {
        // Format checks only. Expiry decisions and cross-response generation ordering belong to Phase 4.
        guard (try? WCAOAuthBrokerClient.BrokerSessionToken(rawValue: sessionID)) != nil,
              tokenGeneration >= 1, pendingRefresh.map({
                  $0.sessionID == sessionID && (0...2).contains($0.dispatchCount)
              }) ?? true else {
            throw WCABrokerSessionStore.Failure.invalidSession
        }
    }
}

/// Per-instance actor serialization, with no internal await/reentrancy during load/save/clear.
/// One SecItem update replaces the entire blob, but there is NO cross-instance/process CAS or crash transaction.
/// Separate load + save calls are NOT read-modify-write atomic. Future coordinators must own stale-writer protection.
actor WCABrokerSessionStore {
    nonisolated enum Operation: String, Sendable { case read, write, delete }

    nonisolated enum Failure: Error, Equatable, Sendable {
        case unsupportedSchema, unsupportedProvider, corruptedData, invalidSession, encodingFailed
        case temporarilyInaccessible(Operation, OSStatus)
        case keychainFailure(Operation, OSStatus)
    }

    nonisolated enum LoadResult: Sendable, WCABrokerStoreRedacted {
        case absent
        case session(WCABrokerStoredSession)
        case logoutPending
    }

    nonisolated private struct Header: Codable {
        let schemaVersion: Int
        let provider: String
        let recordKind: String
    }

    private let keychain: any WCABrokerKeychainOperations

    // Explicit construction: no implicit shared store, legacy fallback or side effects at module initialization.
    init(keychain: any WCABrokerKeychainOperations) { self.keychain = keychain }

    func load() throws -> LoadResult {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, value) = keychain.copyMatching(query)
        if status == errSecItemNotFound { return .absent }
        try check(status, operation: .read)
        guard let data = value as? Data else { throw Failure.corruptedData }
        do {
            let decoder = JSONDecoder()
            let header = try decoder.decode(Header.self, from: data)
            guard header.schemaVersion == WCABrokerStoredSession.schemaVersion else { throw Failure.unsupportedSchema }
            guard header.provider == WCABrokerStoredSession.provider else { throw Failure.unsupportedProvider }
            switch header.recordKind {
            case "logout_intent": return .logoutPending
            case "session": return .session(try decoder.decode(WCABrokerStoredSession.self, from: data))
            default: throw Failure.corruptedData
            }
        } catch let failure as Failure { throw failure }
        catch { throw Failure.corruptedData }
    }

    func save(_ session: WCABrokerStoredSession) throws {
        let data: Data
        do { data = try JSONEncoder().encode(session) }
        catch { throw Failure.encodingFailed }
        try replace(data)
    }

    func clear() throws {
        let marker = Header(schemaVersion: WCABrokerStoredSession.schemaVersion,
                            provider: WCABrokerStoredSession.provider, recordKind: "logout_intent")
        let data: Data
        do { data = try JSONEncoder().encode(marker) }
        catch { throw Failure.encodingFailed }
        // Credentials are replaced by a non-sensitive marker BEFORE deletion. Failed deletion remains recoverable.
        // Failed marker persistence is reported; it cannot guarantee durable logout. No network logout here.
        try replace(data)
        let status = keychain.delete(baseQuery)
        if status != errSecItemNotFound { try check(status, operation: .delete) }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.paulsun.CubeFlow",
         kSecAttrAccount as String: "wca_auth_session_v2",
         kSecAttrSynchronizable as String: false]
    }

    private func replace(_ data: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: data,
                                       kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = keychain.update(baseQuery, attributes: attributes)
        if status == errSecItemNotFound {
            let addition = baseQuery.merging(attributes) { _, new in new }
            try check(keychain.add(addition), operation: .write)
        } else { try check(status, operation: .write) }
    }

    private func check(_ status: OSStatus, operation: Operation) throws {
        guard status != errSecSuccess else { return }
        if status == errSecInteractionNotAllowed || status == errSecNotAvailable {
            throw Failure.temporarilyInaccessible(operation, status)
        }
        throw Failure.keychainFailure(operation, status)
    }
}

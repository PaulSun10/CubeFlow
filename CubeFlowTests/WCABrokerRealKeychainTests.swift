import Foundation
import Security
import LocalAuthentication
import XCTest
@testable import CubeFlow

/// Actual Security.framework, but NEVER the live v2/legacy accounts. All credentials below are synthetic fixtures.
@MainActor final class WCABrokerRealKeychainTests: XCTestCase {
    private func fixture() throws -> WCABrokerStoredSession {
        let token = try JSONDecoder().decode(WCAOAuthBrokerClient.WCAAccessToken.self, from: Data("\"fixture-only-access\"".utf8))
        return try .init(sessionID: String(repeating: "A", count: 43), brokerSessionToken: .init(rawValue: String(repeating: "B", count: 43)),
            brokerSessionExpiresAt: 4_297_559_296, wcaAccessToken: token, wcaAccessTokenExpiresAt: 4_294_974_496,
            tokenGeneration: 3, pendingRefresh: .init(sessionID: String(repeating: "A", count: 43), id: UUID(),
                recoveryState: .recoveryPending, dispatchCount: 1, retryNotBefore: 4_294_970_000))
    }

    private func prepared() async throws -> (WCABrokerSessionStore, IsolatedOAuthKeychain) {
        let adapter = IsolatedOAuthKeychain()
        let store = WCABrokerSessionStore(keychain: adapter)
        do { try await store.save(fixture()) }
        catch let error as WCABrokerSessionStore.Failure {
            adapter.cleanup()
            switch error {
            case .temporarilyInaccessible(_, let status), .keychainFailure(_, let status):
                if [-34018, -25308, -25291, -25294, -25293, -128].contains(Int(status)) {
                    throw XCTSkip("Host Security.framework unavailable without interaction/entitlement (OSStatus \(status)); device validation remains pending")
                }
                throw error
            default: throw error
            }
        }
        return (store, adapter)
    }

    func testRealSecuritySaveLoadReplaceClearAndMissing() async throws {
        let (store, adapter) = try await prepared(); defer { adapter.cleanup() }
        guard case .session(let original) = try await store.load() else { return XCTFail("Missing real fixture") }
        XCTAssertEqual(original.tokenGeneration, 3)
        let replacement = try WCABrokerStoredSession(sessionID: original.sessionID, brokerSessionToken: original.brokerSessionToken,
            brokerSessionExpiresAt: original.brokerSessionExpiresAt, wcaAccessToken: original.wcaAccessToken,
            wcaAccessTokenExpiresAt: original.wcaAccessTokenExpiresAt, tokenGeneration: 4)
        try await store.save(replacement)
        guard case .session(let updated) = try await store.load() else { return XCTFail("Missing update") }
        XCTAssertEqual(updated.tokenGeneration, 4)
        try await store.clear()
        guard case .absent = try await store.load() else { return XCTFail("Clear failed") }
    }

    func testRealSecurityPendingBudgetRetryAfterSurviveStoreRecreation() async throws {
        let (store, adapter) = try await prepared(); defer { adapter.cleanup() }
        guard case .session(let before) = try await store.load(),
              case .session(let after) = try await WCABrokerSessionStore(keychain: adapter).load() else { return XCTFail("Missing real fixture") }
        XCTAssertTrue(before.pendingRefresh?.id == after.pendingRefresh?.id)
        XCTAssertEqual(after.pendingRefresh?.dispatchCount, 1)
        XCTAssertEqual(after.pendingRefresh?.recoveryState, .recoveryPending)
        XCTAssertEqual(after.pendingRefresh?.retryNotBefore, 4_294_970_000)
        XCTAssertEqual(after.brokerSessionExpiresAt, 4_297_559_296)
    }

    func testRealSecurityCorruptionAndUnsupportedSchemaAreNotSignedOut() async throws {
        let (store, adapter) = try await prepared(); defer { adapter.cleanup() }
        for (data, expected) in [(Data("invalid-json".utf8), WCABrokerSessionStore.Failure.corruptedData),
            (Data("{\"schemaVersion\":99,\"provider\":\"wca-broker-v1\",\"recordKind\":\"session\"}".utf8), .unsupportedSchema)] {
            try adapter.replaceRaw(data)
            do { _ = try await store.load(); XCTFail("Invalid fixture accepted") }
            catch let error as WCABrokerSessionStore.Failure { XCTAssertEqual(error, expected) }
        }
    }

    func testRealSecurityLogoutMarkerSurvivesInjectedDeletionFailure() async throws {
        let (store, adapter) = try await prepared(); defer { adapter.cleanup() }
        adapter.setFailDeletion(true)
        do { try await store.clear(); XCTFail("Injected failure not reported") }
        catch let failure as WCABrokerSessionStore.Failure {
            XCTAssertEqual(failure, .temporarilyInaccessible(.delete, errSecInteractionNotAllowed))
        }
        guard case .logoutPending = try await WCABrokerSessionStore(keychain: adapter).load() else { return XCTFail("Marker was not durable") }
        adapter.setFailDeletion(false)
        try await store.clear()
    }

    func testRealSecurityProtectionAttributesWhereSupportedByHost() async throws {
        let (_, adapter) = try await prepared(); defer { adapter.cleanup() }
        let attributes = try adapter.attributes()
        guard let protection = attributes[kSecAttrAccessible as String] as? String else {
            throw XCTSkip("Host Keychain does not expose iOS data-protection attributes; verify on iPhone")
        }
        XCTAssertTrue(protection == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertFalse(attributes[kSecAttrSynchronizable as String] as? Bool ?? false)
    }
}

nonisolated private final class IsolatedOAuthKeychain: WCABrokerKeychainOperations, @unchecked Sendable {
    // Each test gets a fresh namespace. Remapping is unconditional, so even erroneous caller queries cannot touch live accounts.
    private let service = "com.paulsun.CubeFlow.oauth-isolated-tests." + UUID().uuidString
    private let account = "synthetic_session"
    private let system = WCABrokerSystemKeychain()
    private let lock = NSLock()
    private var failDeletion = false

    private func isolated(_ input: [String: Any]) -> [String: Any] {
        var result = input
        result[kSecAttrService as String] = service
        result[kSecAttrAccount as String] = account
        return result
    }
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Any?) {
        var query = isolated(query)
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        return system.copyMatching(query)
    }
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus { system.update(isolated(query), attributes: attributes) }
    func add(_ attributes: [String: Any]) -> OSStatus { system.add(isolated(attributes)) }
    func delete(_ query: [String: Any]) -> OSStatus {
        lock.lock(); let fail = failDeletion; lock.unlock()
        return fail ? errSecInteractionNotAllowed : system.delete(isolated(query))
    }
    func setFailDeletion(_ value: Bool) { lock.lock(); failDeletion = value; lock.unlock() }
    func cleanup() {
        let status = system.delete(isolated([kSecClass as String: kSecClassGenericPassword, kSecAttrSynchronizable as String: false]))
        // This namespace contains only disposable fixtures, never user credentials.
        if status != errSecSuccess && status != errSecItemNotFound && status != errSecMissingEntitlement && status != errSecNotAvailable {
            XCTFail("Isolated test cleanup failed (OSStatus \(status))")
        }
    }
    func replaceRaw(_ data: Data) throws {
        let status = update([kSecClass as String: kSecClassGenericPassword, kSecAttrSynchronizable as String: false],
                            attributes: [kSecValueData as String: data])
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    func attributes() throws -> [String: Any] {
        let (status, result) = copyMatching([kSecClass as String: kSecClassGenericPassword,
            kSecAttrSynchronizable as String: false, kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitOne])
        guard status == errSecSuccess, let attributes = result as? [String: Any] else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return attributes
    }
}

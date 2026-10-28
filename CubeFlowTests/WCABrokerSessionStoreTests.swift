import Foundation
import Security
import XCTest
@testable import CubeFlow

@MainActor
final class WCABrokerSessionStoreTests: XCTestCase {
    private typealias Store = WCABrokerSessionStore
    private typealias Session = WCABrokerStoredSession
    private let sessionID = String(repeating: "A", count: 43)
    private let broker = String(repeating: "B", count: 43)
    private let access = "fixture-access-token"
    private let pendingID = UUID(uuidString: "01234567-1234-1234-1234-0123456789AB")!

    private func session(generation: Int64 = 1, recovery: Session.RecoveryState? = nil,
                         expiry: Int64 = 4_297_559_296) throws -> Session {
        let accessData = try JSONEncoder().encode(access)
        let token = try JSONDecoder().decode(WCAOAuthBrokerClient.WCAAccessToken.self, from: accessData)
        let pending = recovery.map { Session.PendingRefresh(sessionID: sessionID, id: pendingID, recoveryState: $0) }
        return try Session(sessionID: sessionID, brokerSessionToken: .init(rawValue: broker),
                           brokerSessionExpiresAt: expiry, wcaAccessToken: token,
                           wcaAccessTokenExpiresAt: 4_294_974_496, tokenGeneration: generation, pendingRefresh: pending)
    }

    private func loaded(_ store: Store, file: StaticString = #filePath, line: UInt = #line) async throws -> Session {
        guard case .session(let value) = try await store.load() else {
            XCTFail("Expected session record", file: file, line: line)
            throw Store.Failure.corruptedData
        }
        return value
    }

    private func expect(_ failure: Store.Failure, _ operation: () async throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected explicit storage failure", file: file, line: line) }
        catch let actual as Store.Failure { XCTAssertTrue(actual == failure, "Wrong sanitized storage failure", file: file, line: line) }
        catch { XCTFail("Unexpected error type", file: file, line: line) }
    }

    func testAbsentIsDistinctFromStorageFailure() async throws {
        let store = Store(keychain: SessionTestKeychain())
        guard case .absent = try await store.load() else { return XCTFail("Expected absent record") }
    }

    func testSaveLoadAndReplaceCompleteBlob() async throws {
        let keychain = SessionTestKeychain()
        let store = Store(keychain: keychain)
        try await store.save(session())
        let first = try await loaded(store)
        XCTAssertTrue(first.sessionID == sessionID && first.brokerSessionToken.rawValue == broker && first.wcaAccessToken.rawValue == access)
        XCTAssertEqual(first.tokenGeneration, 1)
        XCTAssertNil(first.pendingRefresh)
        try await store.save(session(generation: 3, recovery: .recoveryPending))
        let replaced = try await loaded(store)
        XCTAssertEqual(replaced.tokenGeneration, 3)
        XCTAssertTrue(replaced.pendingRefresh?.id == pendingID)
        XCTAssertEqual(replaced.pendingRefresh?.recoveryState, .recoveryPending)
        XCTAssertEqual(keychain.snapshot().events.map(\.operation), ["update", "add", "read", "update", "read"])
    }

    func testQueriesAreV2DeviceLocalAndUseCorrectProtection() async throws {
        let keychain = SessionTestKeychain()
        let store = Store(keychain: keychain)
        try await store.save(session())
        _ = try await store.load()
        try await store.clear()
        for event in keychain.snapshot().events {
            XCTAssertEqual(event.query[kSecAttrService as String] as? String, "com.paulsun.CubeFlow")
            XCTAssertEqual(event.query[kSecAttrAccount as String] as? String, "wca_auth_session_v2")
            XCTAssertEqual(event.query[kSecAttrSynchronizable as String] as? Bool, false)
            XCTAssertTrue(event.query[kSecClass as String] as? String == kSecClassGenericPassword as String)
            XCTAssertNil(event.query[kSecAttrAccessGroup as String])
            XCTAssertNil(event.query[kSecAttrAccessControl as String])
            if event.operation == "add" || event.operation == "update" {
                XCTAssertTrue(event.attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
            }
        }
    }

    func testSchemaContainsOnlySessionCredentialsNotWCARefreshOrOAuthAttempt() async throws {
        let keychain = SessionTestKeychain()
        try await Store(keychain: keychain).save(session(recovery: .pending))
        let data = try XCTUnwrap(keychain.snapshot().data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 2)
        XCTAssertEqual(object["provider"] as? String, "wca-broker-v1")
        XCTAssertEqual(object["recordKind"] as? String, "session")
        XCTAssertTrue(Set(object.keys) == ["schemaVersion", "provider", "recordKind", "sessionID", "brokerSessionToken",
            "brokerSessionExpiresAt", "wcaAccessToken", "wcaAccessTokenExpiresAt", "tokenGeneration", "pendingRefresh"])
        for field in ["wcaRefreshToken", "refresh_token", "code_verifier", "ticket", "state", "server_time"] {
            XCTAssertNil(object[field])
        }
    }

    func testUnsupportedFutureAndOldSchemasNeverBecomeAbsent() async throws {
        for version in [1, 3, 999] {
            let keychain = SessionTestKeychain()
            keychain.seed(try JSONSerialization.data(withJSONObject: [
                "schemaVersion": version, "provider": Session.provider, "recordKind": "session"]))
            await expect(.unsupportedSchema) { _ = try await Store(keychain: keychain).load() }
            XCTAssertNotNil(keychain.snapshot().data)
        }
    }

    func testUnsupportedProviderIsNotInterpretedAsBrokerSession() async throws {
        let keychain = SessionTestKeychain()
        keychain.seed(try JSONSerialization.data(withJSONObject: ["schemaVersion": 2, "provider": "other", "recordKind": "session"]))
        await expect(.unsupportedProvider) { _ = try await Store(keychain: keychain).load() }
    }

    func testCorruptedAndLegacyBlobsAreNotSignedOutOrMigrated() async throws {
        for data in [Data(), Data("invalid-json".utf8), Data("{\"access_token\":\"legacy-fixture\"}".utf8),
                     Data("{\"schemaVersion\":2,\"provider\":\"wca-broker-v1\",\"recordKind\":\"unknown\"}".utf8)] {
            let keychain = SessionTestKeychain()
            keychain.seed(data)
            await expect(.corruptedData) { _ = try await Store(keychain: keychain).load() }
            XCTAssertTrue(keychain.snapshot().data == data, "Read must not delete invalid data")
        }
    }

    func testInvalidSessionAndPendingOperationIdentityAreRejected() async throws {
        let valid = try session()
        for id in ["short", String(repeating: "?", count: 43)] {
            XCTAssertThrowsError(try Session(sessionID: id, brokerSessionToken: valid.brokerSessionToken,
                brokerSessionExpiresAt: 100, wcaAccessToken: valid.wcaAccessToken,
                wcaAccessTokenExpiresAt: 200, tokenGeneration: 1))
        }
        XCTAssertThrowsError(try Session(sessionID: sessionID, brokerSessionToken: valid.brokerSessionToken,
            brokerSessionExpiresAt: 100, wcaAccessToken: valid.wcaAccessToken, wcaAccessTokenExpiresAt: 200,
            tokenGeneration: 0))
        XCTAssertThrowsError(try Session(sessionID: sessionID, brokerSessionToken: valid.brokerSessionToken,
            brokerSessionExpiresAt: 100, wcaAccessToken: valid.wcaAccessToken, wcaAccessTokenExpiresAt: 200,
            tokenGeneration: 1, pendingRefresh: .init(sessionID: String(repeating: "C", count: 43), id: pendingID, recoveryState: .pending)))
    }

    func testCorruptCredentialAndRecoveryPayloadsAreSanitized() async throws {
        let valid = try JSONEncoder().encode(session(recovery: .pending))
        for (key, value): (String, Any) in [("brokerSessionToken", "invalid"), ("wcaAccessToken", "has whitespace"),
                                           ("tokenGeneration", 0), ("pendingRefresh", ["id": "bad-uuid"])] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
            object[key] = value
            let keychain = SessionTestKeychain()
            keychain.seed(try JSONSerialization.data(withJSONObject: object))
            do { _ = try await Store(keychain: keychain).load(); XCTFail("Invalid session accepted") }
            catch let error as Store.Failure {
                XCTAssertTrue(error == .corruptedData || error == .invalidSession)
                XCTAssertFalse(String(reflecting: error).contains(broker) || String(reflecting: error).contains(access))
            }
        }
    }

    func testLockedOrUnavailableKeychainIsExplicitOnReadAndWrite() async throws {
        for status in [errSecInteractionNotAllowed, errSecNotAvailable] {
            let keychain = SessionTestKeychain()
            keychain.setFailure("read", status)
            await expect(.temporarilyInaccessible(.read, status)) { _ = try await Store(keychain: keychain).load() }
            keychain.setFailure("update", status)
            await expect(.temporarilyInaccessible(.write, status)) { try await Store(keychain: keychain).save(self.session()) }
        }
    }

    func testReadFailureIsNotMissingSession() async throws {
        let keychain = SessionTestKeychain()
        keychain.setFailure("read", errSecDecode)
        await expect(.keychainFailure(.read, errSecDecode)) { _ = try await Store(keychain: keychain).load() }
    }

    func testAddFailureAndDuplicateRaceAreExplicit() async throws {
        for status in [errSecAllocate, errSecDuplicateItem] {
            let keychain = SessionTestKeychain()
            keychain.setFailure("add", status)
            await expect(.keychainFailure(.write, status)) { try await Store(keychain: keychain).save(self.session()) }
            XCTAssertNil(keychain.snapshot().data)
        }
    }

    func testFailedReplacementLeavesEntirePreviousSessionIntact() async throws {
        let keychain = SessionTestKeychain()
        let store = Store(keychain: keychain)
        try await store.save(session(generation: 2, recovery: .pending))
        let before = keychain.snapshot().data
        keychain.setFailure("update", errSecAllocate)
        await expect(.keychainFailure(.write, errSecAllocate)) { try await store.save(self.session(generation: 3, recovery: .uncertain)) }
        XCTAssertTrue(before == keychain.snapshot().data, "Failed update partially persisted data")
        keychain.setFailure("update", nil)
        let value = try await loaded(store)
        XCTAssertEqual(value.tokenGeneration, 2)
        XCTAssertEqual(value.pendingRefresh?.recoveryState, .pending)
    }

    func testPendingUUIDAndEveryRecoveryStateSurviveStoreRecreation() async throws {
        for state in [Session.RecoveryState.pending, .recoveryPending, .uncertain] {
            let keychain = SessionTestKeychain()
            try await Store(keychain: keychain).save(session(generation: 5, recovery: state))
            let restored = try await loaded(Store(keychain: keychain))
            XCTAssertTrue(restored.pendingRefresh?.id == pendingID && restored.pendingRefresh?.sessionID == sessionID)
            XCTAssertEqual(restored.pendingRefresh?.recoveryState, state)
        }
    }

    func testInt64ExpiriesAndGenerationArePreservedWithoutLifetimeOrOrderingPolicy() async throws {
        let keychain = SessionTestKeychain()
        let store = Store(keychain: keychain)
        for generation in [Int64(10), 2, 1] {
            try await store.save(session(generation: generation, expiry: 1))
            let value = try await loaded(store)
            XCTAssertEqual(value.brokerSessionExpiresAt, 1, "Store must not extend even an expired session")
            XCTAssertEqual(value.wcaAccessTokenExpiresAt, 4_294_974_496)
            XCTAssertEqual(value.tokenGeneration, generation, "Business ordering belongs to Phase 4")
        }
    }

    func testClearRemovesOnlyV2AndIsRepeatable() async throws {
        let keychain = SessionTestKeychain()
        let store = Store(keychain: keychain)
        try await store.save(session())
        try await store.clear()
        guard case .absent = try await store.load() else { return XCTFail("Clear did not remove v2") }
        try await store.clear()
        XCTAssertNil(keychain.snapshot().data)
        XCTAssertTrue(keychain.snapshot().events.allSatisfy { $0.query[kSecAttrAccount as String] as? String == "wca_auth_session_v2" })
    }

    func testFailedDeletionLeavesNonSensitiveLogoutMarkerAcrossRestart() async throws {
        let keychain = SessionTestKeychain()
        let store = Store(keychain: keychain)
        try await store.save(session(recovery: .pending))
        keychain.setFailure("delete", errSecInteractionNotAllowed)
        await expect(.temporarilyInaccessible(.delete, errSecInteractionNotAllowed)) { try await store.clear() }
        let data = try XCTUnwrap(keychain.snapshot().data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(Set(object.keys) == ["schemaVersion", "provider", "recordKind"])
        let output = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(output.contains(access) || output.contains(broker) || output.contains(sessionID))
        guard case .logoutPending = try await Store(keychain: keychain).load() else {
            return XCTFail("Interrupted clear resurrected credentials")
        }
        keychain.setFailure("delete", nil)
        try await Store(keychain: keychain).clear()
        XCTAssertNil(keychain.snapshot().data)
    }

    func testMarkerPersistenceFailureIsReportedAndCannotPromiseLogout() async throws {
        let keychain = SessionTestKeychain()
        let store = Store(keychain: keychain)
        try await store.save(session())
        let before = keychain.snapshot().data
        keychain.setFailure("update", errSecAllocate)
        await expect(.keychainFailure(.write, errSecAllocate)) { try await store.clear() }
        XCTAssertTrue(before == keychain.snapshot().data)
        XCTAssertFalse(keychain.snapshot().events.contains { $0.operation == "delete" })
    }

    func testOrdinaryDeleteFailureIsNotSuccess() async throws {
        let keychain = SessionTestKeychain()
        keychain.setFailure("delete", errSecAllocate)
        await expect(.keychainFailure(.delete, errSecAllocate)) { try await Store(keychain: keychain).clear() }
        guard case .logoutPending = try await Store(keychain: keychain).load() else { return XCTFail("Expected logout marker") }
    }

    func testConcurrentLoadSaveClearAreSerializedWithinOneStore() async throws {
        let keychain = SessionTestKeychain()
        let store = Store(keychain: keychain)
        let value = try session(generation: 9, recovery: .uncertain)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<120 {
                group.addTask {
                    switch index % 3 {
                    case 0: try await store.save(value)
                    case 1: try await store.clear()
                    default:
                        if case .session(let loaded) = try await store.load() {
                            guard loaded.tokenGeneration == 9, loaded.pendingRefresh?.recoveryState == .uncertain else {
                                throw Store.Failure.corruptedData
                            }
                        }
                    }
                }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(keychain.snapshot().maximumInFlight, 1)
        // Marker write + delete cannot be interleaved by another call on this actor.
        let events = keychain.snapshot().events
        for (index, event) in events.enumerated() where event.operation == "delete" {
            let prior = events[index - 1]
            XCTAssertTrue(prior.operation == "update" || prior.operation == "add")
            let data = try XCTUnwrap(prior.attributes[kSecValueData as String] as? Data)
            let marker = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(marker["recordKind"] as? String, "logout_intent")
        }
    }

    func testIndependentStoresDoNotClaimCASOrStaleWriterProtection() async throws {
        let keychain = SessionTestKeychain()
        let first = Store(keychain: keychain), second = Store(keychain: keychain)
        try await first.save(session(generation: 1))
        let stale = try await loaded(second)
        try await first.save(session(generation: 2))
        try await second.save(stale)
        let final = try await loaded(first)
        XCTAssertEqual(final.tokenGeneration, 1, "This layer must not silently introduce Phase 4 ordering/CAS")
    }

    func testValuesAndErrorsHaveRedactedDescriptionsAndReflection() async throws {
        let value = try session(recovery: .pending)
        let objects: [Any] = [value, value.pendingRefresh!, Store.LoadResult.session(value)]
        for object in objects {
            let description = String(describing: object) + String(reflecting: object)
            XCTAssertFalse(description.contains(broker) || description.contains(access) || description.contains(sessionID))
            XCTAssertEqual(Mirror(reflecting: object).children.count, 0)
        }
        let error = Store.Failure.keychainFailure(.write, errSecAllocate)
        XCTAssertFalse(String(reflecting: error).contains(broker))
    }
}

nonisolated private final class SessionTestKeychain: WCABrokerKeychainOperations, @unchecked Sendable {
    struct Event {
        let operation: String
        let query: [String: Any]
        let attributes: [String: Any]
    }
    struct Snapshot {
        let data: Data?
        let events: [Event]
        let maximumInFlight: Int
    }
    private let lock = NSLock()
    private var data: Data?
    private var events: [Event] = []
    private var failures: [String: OSStatus] = [:]
    private var inFlight = 0
    private var maximumInFlight = 0

    func seed(_ data: Data) { lock.lock(); defer { lock.unlock() }; self.data = data }
    func setFailure(_ operation: String, _ status: OSStatus?) {
        lock.lock(); defer { lock.unlock() }; failures[operation] = status
    }
    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return .init(data: data, events: events, maximumInFlight: maximumInFlight)
    }
    private func perform<T>(_ body: () -> T) -> T {
        lock.lock(); inFlight += 1; maximumInFlight = max(maximumInFlight, inFlight); lock.unlock()
        defer { lock.lock(); inFlight -= 1; lock.unlock() }
        lock.lock(); defer { lock.unlock() }
        return body()
    }
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Any?) {
        perform {
            events.append(.init(operation: "read", query: query, attributes: [:]))
            if let failure = failures["read"] { return (failure, nil) }
            return data.map { (errSecSuccess, $0 as Any) } ?? (errSecItemNotFound, nil)
        }
    }
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        perform {
            events.append(.init(operation: "update", query: query, attributes: attributes))
            if let failure = failures["update"] { return failure }
            guard data != nil else { return errSecItemNotFound }
            data = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }
    func add(_ attributes: [String: Any]) -> OSStatus {
        perform {
            events.append(.init(operation: "add", query: attributes, attributes: attributes))
            if let failure = failures["add"] { return failure }
            guard data == nil else { return errSecDuplicateItem }
            data = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }
    func delete(_ query: [String: Any]) -> OSStatus {
        perform {
            events.append(.init(operation: "delete", query: query, attributes: [:]))
            if let failure = failures["delete"] { return failure }
            guard data != nil else { return errSecItemNotFound }
            data = nil
            return errSecSuccess
        }
    }
}

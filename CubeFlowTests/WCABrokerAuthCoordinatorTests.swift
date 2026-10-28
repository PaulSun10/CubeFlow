import Foundation
import XCTest
@testable import CubeFlow

@MainActor
final class WCABrokerAuthCoordinatorTests: XCTestCase {
    private typealias Owner = WCABrokerAuthCoordinator
    private typealias Session = WCABrokerStoredSession

    private func until(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<1000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Controlled operation did not reach expected boundary", file: file, line: line)
        throw Owner.Failure.staleOperation
    }

    private func expect(_ expected: Owner.Failure, _ work: () async throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) async {
        do { try await work(); XCTFail("Expected sanitized coordinator failure", file: file, line: line) }
        catch let actual as Owner.Failure { XCTAssertTrue(actual == expected, "Unexpected safe failure category", file: file, line: line) }
        catch { XCTFail("Unexpected error type", file: file, line: line) }
    }

    private func browserLogin(_ h: CoordinatorHarness) async throws -> Task<Void, Error> {
        let count = h.browser.sessions.count
        let task = Task { try await h.owner.login() }
        try await until { h.browser.sessions.count > count }
        return task
    }

    private func finishLogin(_ h: CoordinatorHarness, id: String = CoordinatorFixture.id) async throws {
        h.client.completeValue = try CoordinatorFixture.complete(id: id)
        let task = try await browserLogin(h)
        h.deliver()
        try await task.value
    }

    private func restored(_ value: Session? = nil, profile: CoordinatorProfile? = nil) async throws -> CoordinatorHarness {
        let h = try CoordinatorHarness(session: value ?? CoordinatorFixture.session(), profile: profile)
        try await h.owner.restore()
        return h
    }

    func testConstructionHasNoNetworkBrowserOrStorageSideEffects() async throws {
        let h = try CoordinatorHarness()
        XCTAssertEqual(h.owner.state, .signedOut)
        XCTAssertEqual(h.client.starts.count + h.client.completeCalls + h.client.refreshKeys.count + h.client.logoutCalls, 0)
        XCTAssertEqual(h.store.operations.count, 0)
        XCTAssertEqual(h.browser.sessions.count, 0)
    }

    func testSuccessfulLoginPersistsBeforePublishingReady() async throws {
        let h = try CoordinatorHarness()
        h.store.saveBody = { _ in XCTAssertEqual(h.owner.state, .persistingCredentials) }
        try await finishLogin(h)
        XCTAssertEqual(h.owner.state, .ready)
        XCTAssertEqual(h.client.starts.count, 1)
        XCTAssertEqual(h.client.completeCalls, 1)
        XCTAssertEqual(try h.store.saved()?.tokenGeneration, 1)
        XCTAssertEqual(h.browser.sessions[0].scheme, "cubeflow-wca")
    }

    func testUserBrowserCancellationDoesNotComplete() async throws {
        let h = try CoordinatorHarness()
        let task = try await browserLogin(h)
        h.browser.sessions.last!.deliver(.failure(.cancelled))
        await expect(.cancelled) { try await task.value }
        XCTAssertEqual(h.owner.state, .signedOut)
        XCTAssertEqual(h.client.completeCalls, 0)
    }

    func testAccessDeniedDoesNotComplete() async throws {
        let h = try CoordinatorHarness()
        let task = try await browserLogin(h)
        h.deliver(error: "access_denied")
        await expect(.denied) { try await task.value }
        XCTAssertEqual(h.client.completeCalls, 0)
    }

    func testInvalidCallbackDoesNotComplete() async throws {
        let h = try CoordinatorHarness()
        let task = try await browserLogin(h)
        h.browser.sessions.last!.deliver(.success(URL(string: "cubeflow-wca://other/callback?state=bad&ticket=bad")!))
        await expect(.invalidCallback) { try await task.value }
        XCTAssertEqual(h.client.completeCalls, 0)
    }

    func testExpiredTransactionNeverPresentsBrowser() async throws {
        let h = try CoordinatorHarness()
        h.client.startBody = { _ in try CoordinatorFixture.start(expires: 10_000) }
        await expect(.expired) { try await h.owner.login() }
        XCTAssertTrue(h.browser.sessions.isEmpty)
    }

    func testBrowserDeadlineEndsAnOtherwiseUnansweredAuthorization() async throws {
        let h = try CoordinatorHarness()
        let task = try await browserLogin(h)
        try await until { !h.clock.sleepers.isEmpty }
        h.clock.advance(600)
        await expect(.expired) { try await task.value }
        XCTAssertEqual(h.browser.sessions.last?.cancelCalls, 1)
    }

    func testRepeatedBrowserCallbackCompletesOnlyOnce() async throws {
        let h = try CoordinatorHarness()
        let gate = CoordinatorGate<WCAOAuthBrokerClient.CompleteResponse>()
        h.client.completeBody = { _ in try await gate.wait() }
        let task = try await browserLogin(h)
        h.deliver(); h.deliver()
        try await until { gate.waiting }
        XCTAssertEqual(h.client.completeCalls, 1)
        gate.succeed(try CoordinatorFixture.complete())
        try await task.value
        XCTAssertEqual(h.client.completeCalls, 1)
    }

    func testCompleteTimeoutRequiresFreshAuthorizationWithoutReplay() async throws {
        let h = try CoordinatorHarness()
        h.client.completeBody = { _ in throw WCAOAuthBrokerClient.Failure.transport(.timedOut) }
        let task = try await browserLogin(h); h.deliver()
        await expect(.completionUnknown) { try await task.value }
        XCTAssertEqual(h.client.completeCalls, 1)
        XCTAssertEqual(h.owner.state, .needsLogin)
        XCTAssertNil(h.store.raw)
    }

    func testAmbiguousComplete502And503AreNotRetried() async throws {
        for code in [502, 503] {
            let h = try CoordinatorHarness()
            h.client.completeBody = { _ in throw WCAOAuthBrokerClient.Failure.http(status: code, retryAfterSeconds: nil) }
            let task = try await browserLogin(h); h.deliver()
            await expect(.completionUnknown) { try await task.value }
            XCTAssertEqual(h.client.completeCalls, 1)
        }
    }

    func testCompletePersistenceFailureAllowsLocalRetryOnly() async throws {
        let h = try CoordinatorHarness()
        h.store.saveBody = { _ in throw CoordinatorFixture.storageError }
        let task = try await browserLogin(h); h.deliver()
        await expect(.storage) { try await task.value }
        XCTAssertEqual(h.owner.state, .storageBlocked)
        XCTAssertNil(h.store.raw)
        h.store.saveBody = nil
        try await h.owner.retryPersistence()
        XCTAssertEqual(h.owner.state, .ready)
        XCTAssertEqual(h.client.completeCalls, 1)
        XCTAssertNotNil(h.store.raw)
    }

    func testLostInMemoryCompletionAfterRestartRequiresNewLogin() async throws {
        let h = try CoordinatorHarness()
        h.store.saveBody = { _ in throw CoordinatorFixture.storageError }
        let task = try await browserLogin(h); h.deliver()
        await expect(.storage) { try await task.value }
        let second = h.newOwner()
        try await second.restore()
        XCTAssertEqual(second.state, .signedOut)
        XCTAssertEqual(h.client.completeCalls, 1)
    }

    func testProfileFailureKeepsDurableSessionAndDoesNotReexchangeTicket() async throws {
        let profile = CoordinatorProfile()
        profile.body = { _ in throw CoordinatorFixture.testError }
        let h = try CoordinatorHarness(profile: profile)
        let task = try await browserLogin(h); h.deliver()
        await expect(.profileUnavailable) { try await task.value }
        XCTAssertEqual(h.owner.state, .profilePending)
        XCTAssertNotNil(h.store.raw)
        profile.body = nil
        try await h.owner.retryProfile()
        XCTAssertEqual(h.owner.state, .ready)
        XCTAssertEqual(h.client.completeCalls, 1)
    }

    func testRestoreValidSessionWithoutAnyNetwork() async throws {
        let h = try await restored()
        XCTAssertEqual(h.owner.state, .ready)
        XCTAssertEqual(h.client.refreshKeys.count, 0)
        XCTAssertEqual(h.client.starts.count, 0)
    }

    func testRestoreAbsentSession() async throws {
        let h = try CoordinatorHarness()
        try await h.owner.restore()
        XCTAssertEqual(h.owner.state, .signedOut)
    }

    func testUnsupportedCorruptedAndLockedStorageAreBlockedNotSignedOut() async throws {
        for failure in [WCABrokerSessionStore.Failure.unsupportedSchema, .corruptedData,
                        .temporarilyInaccessible(.read, -25308)] {
            let h = try CoordinatorHarness()
            h.store.loadBody = { throw failure }
            await expect(.storage) { try await h.owner.restore() }
            XCTAssertEqual(h.owner.state, .storageBlocked)
            XCTAssertTrue(h.client.starts.isEmpty)
        }
    }

    func testExpiredBrokerSessionNeedsLoginWithoutDeletingRecord() async throws {
        let h = try await restored(CoordinatorFixture.session(brokerExpiry: 9_999))
        XCTAssertEqual(h.owner.state, .needsLogin)
        await expect(.expired) { _ = try await h.owner.accessCredential() }
        XCTAssertNotNil(h.store.raw)
        XCTAssertEqual(h.client.refreshKeys.count, 0)
    }

    func testExpiredAccessTokenCanRefreshUsableBrokerSession() async throws {
        let h = try await restored(CoordinatorFixture.session(accessExpiry: 9_999))
        XCTAssertEqual(h.owner.state, .needsLogin)
        _ = try await h.owner.accessCredential()
        XCTAssertEqual(h.client.refreshKeys.count, 1)
        XCTAssertEqual(h.owner.state, .ready)
    }

    func testPendingUUIDRestoresAsRecoveryPendingWithSameKey() async throws {
        let pending = CoordinatorFixture.pending(.pending, count: 1)
        let h = try await restored(CoordinatorFixture.session(pending: pending))
        XCTAssertEqual(h.owner.refreshStatus, .recoveryPending)
        try await h.owner.refresh()
        XCTAssertTrue(h.client.refreshKeys == [pending.id])
        XCTAssertEqual(h.store.saves.first?.pendingRefresh?.dispatchCount, 2)
    }

    func testRecoveryPendingRestoresWithoutAutomaticNetwork() async throws {
        let h = try await restored(CoordinatorFixture.session(pending: CoordinatorFixture.pending(.recoveryPending, count: 1)))
        XCTAssertEqual(h.owner.refreshStatus, .recoveryPending)
        XCTAssertTrue(h.client.refreshKeys.isEmpty)
    }

    func testUncertainRestorationRetainsValidAccessButCannotRefresh() async throws {
        let h = try await restored(CoordinatorFixture.session(pending: CoordinatorFixture.pending(.uncertain, count: 1)))
        XCTAssertEqual(h.owner.state, .ready)
        XCTAssertEqual(h.owner.refreshStatus, .uncertain)
        _ = try await h.owner.accessCredential()
        await expect(.uncertain) { try await h.owner.refresh() }
        XCTAssertTrue(h.client.refreshKeys.isEmpty)
    }

    func testUncertainWithExpiredAccessNeedsLogin() async throws {
        let h = try await restored(CoordinatorFixture.session(accessExpiry: 9_999,
            pending: CoordinatorFixture.pending(.uncertain, count: 1)))
        XCTAssertEqual(h.owner.state, .needsLogin)
        await expect(.uncertain) { _ = try await h.owner.accessCredential() }
    }

    func testLogoutIntentRestorationDeletesMarkerWithoutRestoringCredentials() async throws {
        let h = try CoordinatorHarness()
        h.store.raw = try CoordinatorFixture.marker()
        try await h.owner.restore()
        XCTAssertEqual(h.owner.state, .signedOut)
        XCTAssertEqual(h.store.clearCalls, 1)
        XCTAssertNil(h.store.raw)
    }

    func testRefreshPersistsUUIDAndDispatchCountBeforeRequest() async throws {
        let h = try await restored()
        h.client.refreshBody = { _, key in
            let saved = try XCTUnwrap(h.store.saved())
            XCTAssertTrue(saved.pendingRefresh?.id == key)
            XCTAssertEqual(saved.pendingRefresh?.dispatchCount, 1)
            XCTAssertEqual(h.owner.state, .ready)
            return try CoordinatorFixture.refresh()
        }
        try await h.owner.refresh()
        let saved = try XCTUnwrap(h.store.saved())
        XCTAssertNil(saved.pendingRefresh)
        XCTAssertEqual(saved.tokenGeneration, 2)
        XCTAssertEqual(saved.brokerSessionExpiresAt, 20_000)
        XCTAssertTrue(saved.brokerSessionToken.rawValue == CoordinatorFixture.broker)
    }

    func testPendingPersistenceFailurePreventsRefreshDispatch() async throws {
        let h = try await restored()
        h.store.saveBody = { _ in throw CoordinatorFixture.storageError }
        await expect(.storage) { try await h.owner.refresh() }
        XCTAssertTrue(h.client.refreshKeys.isEmpty)
        XCTAssertEqual(h.owner.state, .storageBlocked)
        XCTAssertNil(try h.store.saved()?.pendingRefresh)
    }

    func testConcurrentRefreshCallersShareOneFlight() async throws {
        let h = try await restored()
        let gate = CoordinatorGate<WCAOAuthBrokerClient.RefreshResponse>()
        h.client.refreshBody = { _, _ in try await gate.wait() }
        let tasks = (0..<20).map { _ in Task { try await h.owner.refresh() } }
        try await until { gate.waiting }
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(h.client.refreshKeys.count, 1)
        gate.succeed(try CoordinatorFixture.refresh())
        for task in tasks { try await task.value }
        XCTAssertEqual(h.client.refreshKeys.count, 1)
    }

    func testLostRefreshResponseRetriesOnceWithSameUUIDAndToken() async throws {
        let h = try await restored()
        h.client.refreshBody = { _, _ in
            if h.client.refreshKeys.count == 1 { throw WCAOAuthBrokerClient.Failure.transport(.timedOut) }
            return try CoordinatorFixture.refresh()
        }
        try await h.owner.refresh()
        XCTAssertEqual(h.client.refreshKeys.count, 2)
        XCTAssertTrue(h.client.refreshKeys[0] == h.client.refreshKeys[1])
        XCTAssertTrue(h.client.refreshTokens.allSatisfy { $0 == CoordinatorFixture.broker })
        XCTAssertEqual(h.store.saves.filter { $0.pendingRefresh?.recoveryState == .pending }.map { $0.pendingRefresh!.dispatchCount }, [1, 2])
    }

    func testExhaustedRetryBudgetSurvivesRestartAndCannotMintNewUUID() async throws {
        let h = try await restored()
        h.client.refreshBody = { _, _ in throw WCAOAuthBrokerClient.Failure.transport(.connectionFailure) }
        await expect(.recoveryRequired) { try await h.owner.refresh() }
        XCTAssertEqual(h.client.refreshKeys.count, 2)
        XCTAssertEqual(try h.store.saved()?.pendingRefresh?.dispatchCount, 2)
        let second = h.newOwner()
        try await second.restore()
        await expect(.recoveryRequired) { try await second.refresh() }
        XCTAssertEqual(h.client.refreshKeys.count, 2)
    }

    func testLegacyV2PendingRecordWithoutBudgetFailsClosedOnRestart() async throws {
        let h = try CoordinatorHarness(session: CoordinatorFixture.session(pending: CoordinatorFixture.pending(.pending, count: 0)))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(h.store.raw)) as? [String: Any])
        var pending = try XCTUnwrap(json["pendingRefresh"] as? [String: Any])
        pending.removeValue(forKey: "dispatchCount")
        json["pendingRefresh"] = pending
        h.store.raw = try JSONSerialization.data(withJSONObject: json)
        try await h.owner.restore()
        await expect(.recoveryRequired) { try await h.owner.refresh() }
        XCTAssertTrue(h.client.refreshKeys.isEmpty)
    }

    func testHigherGenerationAcceptedAndServerTimeDoesNotExtendBrokerExpiry() async throws {
        let h = try await restored()
        h.client.refreshBody = { _, _ in try CoordinatorFixture.refresh(generation: 8, serverTime: Int64.max) }
        try await h.owner.refresh()
        XCTAssertEqual(try h.store.saved()?.tokenGeneration, 8)
        XCTAssertEqual(try h.store.saved()?.brokerSessionExpiresAt, 20_000)
    }

    func testEqualGenerationRequiresIdenticalCredentialAndExpiry() async throws {
        let h = try await restored(CoordinatorFixture.session(generation: 2, access: "fixture-new-access", accessExpiry: 12_000,
            pending: CoordinatorFixture.pending(.recoveryPending, count: 1)))
        try await h.owner.refresh()
        XCTAssertEqual(try h.store.saved()?.tokenGeneration, 2)
        XCTAssertNil(try h.store.saved()?.pendingRefresh)
    }

    func testEqualGenerationConflictBecomesUncertainWithoutReplacingCredential() async throws {
        let h = try await restored(CoordinatorFixture.session(generation: 2))
        await expect(.conflictingGeneration) { try await h.owner.refresh() }
        XCTAssertEqual(h.owner.refreshStatus, .uncertain)
        XCTAssertEqual(try h.store.saved()?.tokenGeneration, 2)
        XCTAssertTrue(try h.store.saved()?.wcaAccessToken.rawValue == "fixture-access")
    }

    func testOldSuccessfulReplayNeverOverwritesNewerGeneration() async throws {
        let h = try await restored(CoordinatorFixture.session(generation: 5,
            pending: CoordinatorFixture.pending(.recoveryPending, count: 1)))
        await expect(.recoveryRequired) { try await h.owner.refresh() }
        XCTAssertEqual(try h.store.saved()?.tokenGeneration, 5)
        XCTAssertNotNil(try h.store.saved()?.pendingRefresh)
        XCTAssertTrue(try h.store.saved()?.pendingRefresh?.id == CoordinatorFixture.key)
    }

    func testExpiredCached200DoesNotClearPendingOrUseOldServerTime() async throws {
        let h = try await restored()
        h.client.refreshBody = { _, _ in try CoordinatorFixture.refresh(accessExpiry: 9_999, serverTime: 1) }
        await expect(.recoveryRequired) { try await h.owner.refresh() }
        XCTAssertNotNil(try h.store.saved()?.pendingRefresh)
        XCTAssertEqual(try h.store.saved()?.tokenGeneration, 1)
    }

    func testOld200CannotRepairConfirmedUncertainty() async throws {
        let h = try await restored()
        h.client.refreshBody = { _, _ in throw CoordinatorFixture.providerFailure }
        await expect(.uncertain) { try await h.owner.refresh() }
        h.client.refreshBody = { _, _ in try CoordinatorFixture.refresh(generation: 50) }
        await expect(.uncertain) { try await h.owner.refresh() }
        let restoredOwner = h.newOwner()
        try await restoredOwner.restore()
        await expect(.uncertain) { try await restoredOwner.refresh() }
        XCTAssertEqual(h.client.refreshKeys.count, 1)
        XCTAssertEqual(try h.store.saved()?.tokenGeneration, 1)
    }

    func testStructuredProvider502IsConfirmedUncertainAndNotRetried() async throws {
        let h = try await restored()
        h.client.refreshBody = { _, _ in throw CoordinatorFixture.providerFailure }
        await expect(.uncertain) { try await h.owner.refresh() }
        XCTAssertEqual(h.client.refreshKeys.count, 1)
        XCTAssertEqual(h.owner.refreshStatus, .uncertain)
        XCTAssertEqual(try h.store.saved()?.pendingRefresh?.recoveryState, .uncertain)
    }

    func testGeneric502And503PreserveSessionWithBoundedRecoveryNotConfirmedUncertain() async throws {
        for code in [502, 503] {
            let h = try await restored()
            h.client.refreshBody = { _, _ in throw WCAOAuthBrokerClient.Failure.http(status: code, retryAfterSeconds: nil) }
            await expect(.recoveryRequired) { try await h.owner.refresh() }
            XCTAssertEqual(h.client.refreshKeys.count, 2)
            XCTAssertEqual(h.owner.refreshStatus, .recoveryPending)
            XCTAssertEqual(h.owner.state, .ready)
            XCTAssertNotNil(h.store.raw)
        }
    }

    func testBroker401StopsRefreshAndRequiresLoginWithoutDeletingSession() async throws {
        for code in [WCAOAuthBrokerClient.ErrorCode.sessionInvalid, .sessionExpired, .sessionRevoked] {
            let h = try await restored()
            h.client.refreshBody = { _, _ in
                throw WCAOAuthBrokerClient.Failure.broker(status: 401, code: code, requestID: CoordinatorFixture.id, retryAfterSeconds: nil)
            }
            await expect(.sessionInvalid) { try await h.owner.refresh() }
            XCTAssertEqual(h.client.refreshKeys.count, 1)
            XCTAssertEqual(h.owner.state, .needsLogin)
            XCTAssertNotNil(h.store.raw)
        }
    }

    func test429PersistsRetryAfterAndDoesNotWaitOrRetryEarlyAfterRestart() async throws {
        let h = try await restored()
        h.client.refreshBody = { _, _ in throw WCAOAuthBrokerClient.Failure.http(status: 429, retryAfterSeconds: 60) }
        await expect(.recoveryRequired) { try await h.owner.refresh() }
        XCTAssertEqual(h.client.refreshKeys.count, 1)
        XCTAssertEqual(try h.store.saved()?.pendingRefresh?.retryNotBefore, 10_060)
        let second = h.newOwner(); try await second.restore()
        await expect(.recoveryRequired) { try await second.refresh() }
        XCTAssertEqual(h.client.refreshKeys.count, 1)
        h.clock.advance(60)
        h.client.refreshBody = nil
        try await second.refresh()
        XCTAssertTrue(h.client.refreshKeys[0] == h.client.refreshKeys[1])
    }

    func testMalformed200UsesSameKeyRecoveryBudget() async throws {
        let h = try await restored()
        h.client.refreshBody = { _, _ in throw WCAOAuthBrokerClient.Failure.malformedResponse }
        await expect(.recoveryRequired) { try await h.owner.refresh() }
        XCTAssertEqual(h.client.refreshKeys.count, 2)
        XCTAssertTrue(h.client.refreshKeys[0] == h.client.refreshKeys[1])
    }

    func testCancelledRefreshDoesNotAutomaticallyRetryOrDiscardUUID() async throws {
        let h = try await restored()
        h.client.refreshBody = { _, _ in throw WCAOAuthBrokerClient.Failure.transport(.cancelled) }
        await expect(.recoveryRequired) { try await h.owner.refresh() }
        XCTAssertEqual(h.client.refreshKeys.count, 1)
        XCTAssertEqual(try h.store.saved()?.pendingRefresh?.dispatchCount, 1)
        XCTAssertEqual(h.owner.refreshStatus, .recoveryPending)
    }

    func testRefreshResultPersistenceFailureCanRetryLocallyWithoutNewNetwork() async throws {
        let h = try await restored()
        h.store.saveBody = { record in if record.pendingRefresh == nil { throw CoordinatorFixture.storageError } }
        await expect(.storage) { try await h.owner.refresh() }
        XCTAssertEqual(h.owner.state, .storageBlocked)
        XCTAssertEqual(try h.store.saved()?.tokenGeneration, 1)
        h.store.saveBody = nil
        try await h.owner.retryPersistence()
        XCTAssertEqual(try h.store.saved()?.tokenGeneration, 2)
        XCTAssertNil(try h.store.saved()?.pendingRefresh)
        XCTAssertEqual(h.client.refreshKeys.count, 1)
    }

    func testUncertaintyPersistenceFailureCannotBeBypassedByRestore() async throws {
        let h = try await restored()
        h.client.refreshBody = { _, _ in throw CoordinatorFixture.providerFailure }
        h.store.saveBody = { record in if record.pendingRefresh?.recoveryState == .uncertain { throw CoordinatorFixture.storageError } }
        await expect(.storage) { try await h.owner.refresh() }
        await expect(.storage) { try await h.owner.restore() }
        XCTAssertEqual(h.owner.refreshStatus, .uncertain)
        h.store.saveBody = nil
        try await h.owner.retryPersistence()
        await expect(.uncertain) { try await h.owner.refresh() }
    }

    func testLogoutDuringRefreshRejectsDelayedResponse() async throws {
        let h = try await restored()
        let gate = CoordinatorGate<WCAOAuthBrokerClient.RefreshResponse>()
        h.client.refreshBody = { _, _ in try await gate.wait() }
        let task = Task { try await h.owner.refresh() }
        try await until { gate.waiting }
        try await h.owner.logout()
        gate.succeed(try CoordinatorFixture.refresh())
        await expect(.staleOperation) { try await task.value }
        XCTAssertEqual(h.owner.state, .signedOut)
        XCTAssertNil(h.store.raw)
    }

    func testLogoutDuringCompletionCannotPersistDelayedCredentials() async throws {
        let h = try CoordinatorHarness()
        let gate = CoordinatorGate<WCAOAuthBrokerClient.CompleteResponse>()
        h.client.completeBody = { _ in try await gate.wait() }
        let task = try await browserLogin(h); h.deliver()
        try await until { gate.waiting }
        try await h.owner.logout()
        gate.succeed(try CoordinatorFixture.complete())
        await expect(.staleOperation) { try await task.value }
        XCTAssertNil(h.store.raw)
        XCTAssertEqual(h.owner.state, .signedOut)
    }

    func testLogoutDuringBrowserRejectsLateCallback() async throws {
        let h = try CoordinatorHarness()
        let task = try await browserLogin(h)
        try await h.owner.logout()
        h.deliver()
        await expect(.staleOperation) { try await task.value }
        XCTAssertEqual(h.client.completeCalls, 0)
        XCTAssertEqual(h.browser.sessions.last?.cancelCalls, 1)
    }

    func testLogoutDuringStorageLoadRejectsLateSessionRestoration() async throws {
        let h = try CoordinatorHarness()
        let gate = CoordinatorGate<WCABrokerSessionStore.LoadResult>()
        h.store.loadBody = { try await gate.wait() }
        let task = Task { try await h.owner.restore() }
        try await until { gate.waiting }
        try await h.owner.logout()
        gate.succeed(.session(try CoordinatorFixture.session()))
        await expect(.staleOperation) { try await task.value }
        XCTAssertEqual(h.owner.state, .signedOut)
        XCTAssertNil(h.store.raw)
    }

    func testAlreadyDispatchedCredentialWriteFinishesBeforeLogoutClear() async throws {
        let h = try CoordinatorHarness()
        let gate = CoordinatorGate<Void>()
        h.store.saveBody = { _ in try await gate.wait() }
        let login = try await browserLogin(h); h.deliver()
        try await until { gate.waiting }
        let logout = Task { try await h.owner.logout() }
        try await until { h.owner.sessionRevision == 2 }
        XCTAssertEqual(h.store.clearCalls, 0, "Clear must queue behind the dispatched save")
        gate.succeed(())
        try await logout.value
        await expect(.staleOperation) { try await login.value }
        XCTAssertNil(h.store.raw, "Late save resurrected a logged-out session")
        XCTAssertEqual(h.store.operations.suffix(2), ["save", "clear"])
        XCTAssertEqual(h.store.maximumWrites, 1)
    }

    func testAlreadyDispatchedRefreshResultWriteCannotSurviveLogout() async throws {
        let h = try await restored()
        let gate = CoordinatorGate<Void>()
        h.store.saveBody = { record in if record.pendingRefresh == nil { try await gate.wait() } }
        let refresh = Task { try await h.owner.refresh() }
        try await until { gate.waiting }
        let logout = Task { try await h.owner.logout() }
        try await until { h.owner.sessionRevision == 2 }
        gate.succeed(())
        try await logout.value
        await expect(.staleOperation) { try await refresh.value }
        XCTAssertNil(h.store.raw)
        XCTAssertEqual(h.owner.state, .signedOut)
    }

    func testLogoutDeleteFailureReportsBlockedAndMarkerPreventsRestoration() async throws {
        let h = try await restored()
        h.store.clearBody = {
            h.store.raw = try CoordinatorFixture.marker()
            throw CoordinatorFixture.storageError
        }
        await expect(.storage) { try await h.owner.logout() }
        XCTAssertEqual(h.owner.state, .storageBlocked)
        XCTAssertEqual(h.client.logoutCalls, 1)
        let second = h.newOwner()
        await expect(.storage) { try await second.restore() }
        XCTAssertEqual(second.state, .storageBlocked)
        h.store.clearBody = nil
        try await second.restore()
        XCTAssertEqual(second.state, .signedOut)
    }

    func testLogoutIntentPersistenceFailureCannotClaimDurableSignOut() async throws {
        let h = try await restored()
        let original = h.store.raw
        h.store.clearBody = { throw CoordinatorFixture.storageError }
        await expect(.storage) { try await h.owner.logout() }
        XCTAssertEqual(h.owner.state, .storageBlocked)
        XCTAssertTrue(h.store.raw == original)
    }

    func testServerLogoutFailureNeverRestoresLocalAuthentication() async throws {
        let h = try await restored()
        h.client.logoutBody = { _ in throw WCAOAuthBrokerClient.Failure.transport(.timedOut) }
        try await h.owner.logout()
        XCTAssertEqual(h.owner.state, .signedOut)
        XCTAssertEqual(h.owner.lastFailure, .brokerUnavailable)
        XCTAssertNil(h.store.raw)
    }

    func testSessionReplacementRejectsOldRefresh() async throws {
        let h = try await restored()
        let gate = CoordinatorGate<WCAOAuthBrokerClient.RefreshResponse>()
        h.client.refreshBody = { _, _ in try await gate.wait() }
        let refresh = Task { try await h.owner.refresh() }
        try await until { gate.waiting }
        let newID = String(repeating: "C", count: 43)
        try await finishLogin(h, id: newID)
        gate.succeed(try CoordinatorFixture.refresh())
        await expect(.staleOperation) { try await refresh.value }
        XCTAssertTrue(try h.store.saved()?.sessionID == newID)
        XCTAssertEqual(h.owner.state, .ready)
    }

    func testSessionReplacementRejectsDelayedProfileResult() async throws {
        let profile = CoordinatorProfile(), gate = CoordinatorGate<Void>()
        profile.body = { _ in try await gate.wait() }
        let h = try CoordinatorHarness(profile: profile)
        let first = try await browserLogin(h); h.deliver()
        try await until { gate.waiting }
        profile.body = nil
        let newID = String(repeating: "C", count: 43)
        try await finishLogin(h, id: newID)
        gate.succeed(())
        await expect(.staleOperation) { try await first.value }
        XCTAssertTrue(try h.store.saved()?.sessionID == newID)
        XCTAssertEqual(h.owner.state, .ready)
    }

    func testStartCancellationRejectsLateStartWithoutLaunchingBrowser() async throws {
        let h = try CoordinatorHarness(), gate = CoordinatorGate<WCAOAuthBrokerClient.StartResponse>()
        h.client.startBody = { _ in try await gate.wait() }
        let task = Task { try await h.owner.login() }
        try await until { gate.waiting }
        try await h.owner.cancelAuthorization()
        gate.succeed(try CoordinatorFixture.start())
        await expect(.staleOperation) { try await task.value }
        XCTAssertTrue(h.browser.sessions.isEmpty)
    }

    func testIndependentSessionsDoNotShareKeysTokensOrState() async throws {
        let one = try await restored(), two = try await restored(CoordinatorFixture.session(id: String(repeating: "C", count: 43)))
        two.client.refreshBody = { _, _ in try CoordinatorFixture.refresh(id: String(repeating: "C", count: 43)) }
        try await one.owner.refresh(); try await two.owner.refresh()
        try await one.owner.logout()
        XCTAssertEqual(two.owner.state, .ready)
        XCTAssertNotNil(two.store.raw)
        XCTAssertEqual(two.client.logoutCalls, 0)
    }

    func testWCAAPIReceivesAccessTokenOnly() async throws {
        let h = try await restored(), probe = CoordinatorRequestProbe()
        _ = try await h.owner.performAuthorized { try await probe.call($0) }
        let tokens = await probe.tokens
        XCTAssertTrue(tokens == ["fixture-access"])
        XCTAssertFalse(tokens.contains(CoordinatorFixture.broker))
        XCTAssertTrue(h.client.refreshKeys.isEmpty)
    }

    func testOldGenerationWCA401UsesAlreadyAvailableNewerToken() async throws {
        let h = try await restored(), probe = CoordinatorRequestProbe()
        let gate = CoordinatorGate<Void>()
        let operation = Task {
            try await h.owner.performAuthorized { token in
                if token.rawValue == "fixture-access" {
                    try await gate.wait()
                    throw Owner.WCARequestFailure.unauthorized
                }
                return try await probe.call(token)
            }
        }
        try await until { gate.waiting }
        try await h.owner.refresh()
        gate.succeed(())
        _ = try await operation.value
        XCTAssertEqual(h.client.refreshKeys.count, 1)
        let tokens = await probe.tokens
        XCTAssertTrue(tokens == ["fixture-new-access"])
    }

    func testConcurrentWCA401RequestsShareRefresh() async throws {
        let h = try await restored(), gate = CoordinatorGate<WCAOAuthBrokerClient.RefreshResponse>()
        h.client.refreshBody = { _, _ in try await gate.wait() }
        let tasks = (0..<8).map { _ in Task {
            try await h.owner.performAuthorized { token in
                if token.rawValue == "fixture-access" { throw Owner.WCARequestFailure.unauthorized }
                return "ok"
            }
        } }
        try await until { gate.waiting }
        for _ in 0..<30 { await Task.yield() }
        gate.succeed(try CoordinatorFixture.refresh())
        for task in tasks { let result = try await task.value; XCTAssertEqual(result, "ok") }
        XCTAssertEqual(h.client.refreshKeys.count, 1)
    }

    func testWCARequestRetriesOnlyOnceAndNeverUsesLegacyRefresh() async throws {
        let h = try await restored(), probe = CoordinatorRequestProbe(alwaysUnauthorized: true)
        await expect(.apiUnauthorized) { _ = try await h.owner.performAuthorized { try await probe.call($0) } }
        let tokens = await probe.tokens
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(h.client.refreshKeys.count, 1)
        XCTAssertEqual(h.client.starts.count, 0)
        XCTAssertTrue(h.client.refreshTokens.allSatisfy { $0 == CoordinatorFixture.broker })
    }

    func testMismatchedRefreshSessionCannotBeCommitted() async throws {
        let h = try await restored()
        h.client.refreshBody = { _, _ in try CoordinatorFixture.refresh(id: String(repeating: "C", count: 43)) }
        await expect(.staleOperation) { try await h.owner.refresh() }
        XCTAssertTrue(try h.store.saved()?.sessionID == CoordinatorFixture.id)
        XCTAssertEqual(try h.store.saved()?.tokenGeneration, 1)
    }

    func testSafeDescriptionsAndErrorsNeverExposeCredentialsOrURLs() async throws {
        let h = try await restored()
        let credential = try await h.owner.accessCredential()
        for value: Any in [h.owner, credential, Owner.Failure.completionUnknown] {
            let text = String(describing: value) + String(reflecting: value)
            XCTAssertFalse(text.contains(CoordinatorFixture.broker) || text.contains("fixture-access") || text.contains("https://"))
        }
        XCTAssertEqual(Mirror(reflecting: h.owner).children.count, 0)
        XCTAssertEqual(Mirror(reflecting: credential).children.count, 0)
    }

    func testOnlyOneBrowserAttemptMayBeActive() async throws {
        let h = try CoordinatorHarness()
        let task = try await browserLogin(h)
        await expect(.busy) { try await h.owner.login() }
        XCTAssertEqual(h.client.starts.count, 1)
        h.deliver(); try await task.value
    }

    func testNativeBrowserStartFailureIsCleanedUp() async throws {
        let h = try CoordinatorHarness()
        h.browser.startResult = false
        await expect(.browserUnavailable) { try await h.owner.login() }
        XCTAssertEqual(h.client.completeCalls, 0)
        XCTAssertTrue(h.clock.sleepers.isEmpty)
    }

    func testSynchronousCallbackDoesNotLeaveDeadlineTaskAlive() async throws {
        let h = try CoordinatorHarness()
        h.browser.onStart = { h.deliver() }
        try await h.owner.login()
        XCTAssertEqual(h.owner.state, .ready)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(h.clock.sleepers.isEmpty)
    }

    func testTaskCancellationRejectsUncooperativeLateStart() async throws {
        let h = try CoordinatorHarness(), gate = CoordinatorGate<WCAOAuthBrokerClient.StartResponse>()
        h.client.startBody = { _ in try await gate.wait() }
        let task = Task { try await h.owner.login() }
        try await until { gate.waiting }
        task.cancel()
        try await until { h.owner.sessionRevision == 2 }
        gate.succeed(try CoordinatorFixture.start())
        await expect(.staleOperation) { try await task.value }
        XCTAssertTrue(h.browser.sessions.isEmpty)
    }

    func testCancellationDuringCredentialWriteReconcilesDurableStorage() async throws {
        let h = try CoordinatorHarness(), gate = CoordinatorGate<Void>()
        h.store.saveBody = { _ in try await gate.wait() }
        let login = try await browserLogin(h); h.deliver()
        try await until { gate.waiting }
        let cancel = Task { try await h.owner.cancelAuthorization() }
        try await until { h.owner.sessionRevision == 2 }
        gate.succeed(())
        try await cancel.value
        await expect(.staleOperation) { try await login.value }
        XCTAssertNil(h.store.raw)
        XCTAssertEqual(h.owner.state, .signedOut)
    }

    func testReservedSecondDispatchCannotGainAnotherRetryAfterRestart() async throws {
        let h = try await restored(CoordinatorFixture.session(pending: CoordinatorFixture.pending(.pending, count: 2)))
        await expect(.recoveryRequired) { try await h.owner.refresh() }
        XCTAssertTrue(h.client.refreshKeys.isEmpty)
        XCTAssertEqual(h.owner.refreshStatus, .recoveryPending)
    }

    func testOldInFlight200CannotClearRestoredUncertaintyForSameSession() async throws {
        let h = try await restored(), gate = CoordinatorGate<WCAOAuthBrokerClient.RefreshResponse>()
        h.client.refreshBody = { _, _ in try await gate.wait() }
        let old = Task { try await h.owner.refresh() }
        try await until { gate.waiting }
        h.store.raw = try JSONEncoder().encode(CoordinatorFixture.session(pending: CoordinatorFixture.pending(.uncertain, count: 1)))
        try await h.owner.restore()
        gate.succeed(try CoordinatorFixture.refresh(generation: 20))
        await expect(.staleOperation) { try await old.value }
        XCTAssertEqual(h.owner.refreshStatus, .uncertain)
        XCTAssertEqual(try h.store.saved()?.tokenGeneration, 1)
    }

    func testOldFlightCleanupCannotRemoveNewRevisionFlightWithSameInjectedUUID() async throws {
        let h = try await restored(), oldGate = CoordinatorGate<WCAOAuthBrokerClient.RefreshResponse>()
        h.client.refreshBody = { _, _ in try await oldGate.wait() }
        let old = Task { try await h.owner.refresh() }
        try await until { oldGate.waiting }
        let newID = String(repeating: "C", count: 43)
        try await finishLogin(h, id: newID)
        let newGate = CoordinatorGate<WCAOAuthBrokerClient.RefreshResponse>()
        h.client.refreshBody = { _, _ in try await newGate.wait() }
        let fresh = Task { try await h.owner.refresh() }
        try await until { newGate.waiting }
        oldGate.succeed(try CoordinatorFixture.refresh())
        await expect(.staleOperation) { try await old.value }
        let shared = Task { try await h.owner.refresh() }
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(h.client.refreshKeys.count, 2)
        newGate.succeed(try CoordinatorFixture.refresh(id: newID))
        try await fresh.value; try await shared.value
    }

    func testProfileRequestsCoalesceAndLogoutRejectsLateProfile() async throws {
        let profile = CoordinatorProfile(), gate = CoordinatorGate<Void>()
        var requests = 0
        profile.body = { _ in requests += 1; try await gate.wait() }
        let h = try CoordinatorHarness(profile: profile)
        let login = try await browserLogin(h); h.deliver()
        try await until { gate.waiting }
        let shared = Task { try await h.owner.retryProfile() }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(requests, 1)
        try await h.owner.logout()
        gate.succeed(())
        await expect(.staleOperation) { try await login.value }
        await expect(.staleOperation) { try await shared.value }
        XCTAssertEqual(h.owner.state, .signedOut)
    }

    func testLateServerLogoutFailureDoesNotChangeReplacementSession() async throws {
        let h = try await restored(), gate = CoordinatorGate<Void>()
        h.client.logoutBody = { _ in try await gate.wait(); throw CoordinatorFixture.testError }
        let logout = Task { try await h.owner.logout() }
        try await until { gate.waiting }
        try await finishLogin(h, id: String(repeating: "C", count: 43))
        gate.succeed(())
        await expect(.staleOperation) { try await logout.value }
        XCTAssertEqual(h.owner.state, .ready)
        XCTAssertNil(h.owner.lastFailure)
    }

    func testCompleteDefinitiveExpiryIsReportedWithoutAnyRetry() async throws {
        let h = try CoordinatorHarness()
        h.client.completeBody = { _ in
            throw WCAOAuthBrokerClient.Failure.broker(status: 410, code: .ticketExpired, requestID: CoordinatorFixture.id, retryAfterSeconds: nil)
        }
        let login = try await browserLogin(h); h.deliver()
        await expect(.expired) { try await login.value }
        XCTAssertEqual(h.client.completeCalls, 1)
    }

    func testExpiryDuringPendingWritePreventsRefreshNetworkDispatch() async throws {
        let h = try await restored(CoordinatorFixture.session(brokerExpiry: 10_010))
        h.store.saveBody = { _ in h.clock.advance(10) }
        await expect(.expired) { try await h.owner.refresh() }
        XCTAssertTrue(h.client.refreshKeys.isEmpty)
        XCTAssertEqual(h.owner.state, .needsLogin)
    }

    func testProductionTransportHasBoundedTimeoutWithoutStartingNetwork() async throws {
        let configuration = WCAOAuthBrokerURLSessionTransport.configuration()
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 15)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 30)
        XCTAssertFalse(configuration.waitsForConnectivity)
    }

    func testShortRetryAfterIsWaitedAndPersistedBeforeSameKeyRetry() async throws {
        let h = try await restored()
        h.client.refreshBody = { _, _ in
            if h.client.refreshKeys.count == 1 { throw WCAOAuthBrokerClient.Failure.http(status: 429, retryAfterSeconds: 1) }
            return try CoordinatorFixture.refresh()
        }
        let task = Task { try await h.owner.refresh() }
        try await until { !h.clock.sleepers.isEmpty }
        XCTAssertEqual(h.client.refreshKeys.count, 1)
        XCTAssertEqual(try h.store.saved()?.pendingRefresh?.retryNotBefore, 10_001)
        h.clock.advance(1)
        try await task.value
        XCTAssertTrue(h.client.refreshKeys[0] == h.client.refreshKeys[1])
    }

    func test429WithoutUsableRetryAfterDoesNotRetryImmediately() async throws {
        let h = try await restored()
        h.client.refreshBody = { _, _ in throw WCAOAuthBrokerClient.Failure.http(status: 429, retryAfterSeconds: nil) }
        await expect(.recoveryRequired) { try await h.owner.refresh() }
        XCTAssertEqual(h.client.refreshKeys.count, 1)
    }

    func testDifferentLogicalRefreshesGenerateDifferentOperationKeys() async throws {
        let h = try CoordinatorHarness(session: CoordinatorFixture.session())
        var next = 0
        let owner = WCABrokerAuthCoordinator(client: h.client, store: h.store, browserFactory: h.browser, clock: h.clock,
            makeAttempt: { try WCABrokerOAuthAttempt(random: CoordinatorRandom(), clock: h.clock.time) }, makeUUID: {
                next += 1
                return UUID(uuidString: String(format: "01234567-1234-1234-1234-%012d", next))!
            })
        try await owner.restore()
        h.client.refreshBody = { _, _ in try CoordinatorFixture.refresh(generation: Int64(1 + h.client.refreshKeys.count)) }
        try await owner.refresh(); try await owner.refresh()
        XCTAssertEqual(h.client.refreshKeys.count, 2)
        XCTAssertTrue(h.client.refreshKeys[0] != h.client.refreshKeys[1])
    }

    func testOutOfRangePersistedDispatchBudgetIsRejectedAsStorageBlocked() async throws {
        let h = try CoordinatorHarness(session: CoordinatorFixture.session(pending: CoordinatorFixture.pending(.pending, count: 0)))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(h.store.raw)) as? [String: Any])
        var pending = try XCTUnwrap(json["pendingRefresh"] as? [String: Any])
        pending["dispatchCount"] = 3
        json["pendingRefresh"] = pending
        h.store.raw = try JSONSerialization.data(withJSONObject: json)
        await expect(.storage) { try await h.owner.restore() }
        XCTAssertEqual(h.owner.state, .storageBlocked)
        XCTAssertTrue(h.client.refreshKeys.isEmpty)
    }
}

nonisolated private enum CoordinatorFixture {
    static let id = String(repeating: "A", count: 43)
    static let broker = String(repeating: "B", count: 43)
    static let key = UUID(uuidString: "01234567-1234-1234-1234-0123456789AB")!
    static let storageError = WCABrokerSessionStore.Failure.keychainFailure(.write, -50)
    static let testError = NSError(domain: "fixture-sensitive-error-not-to-be-forwarded", code: 1)
    static let providerFailure = WCAOAuthBrokerClient.Failure.broker(status: 502, code: .providerUnavailable, requestID: id, retryAfterSeconds: nil)
    static func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
    static func start(expires: Int64 = 10_600) throws -> WCAOAuthBrokerClient.StartResponse {
        var url = URLComponents(string: "https://www.worldcubeassociation.org/oauth/authorize")!
        url.queryItems = [.init(name: "client_id", value: "fixture-client"), .init(name: "scope", value: "public"),
            .init(name: "response_type", value: "code"), .init(name: "state", value: id),
            .init(name: "redirect_uri", value: "https://api.cubeflow.com.cn/v1/oauth/wca/callback")]
        return try decode(WCAOAuthBrokerClient.StartResponse.self, ["authorization_url": url.string!, "transaction_expires_at": expires])
    }
    static func complete(id: String = id) throws -> WCAOAuthBrokerClient.CompleteResponse {
        try decode(WCAOAuthBrokerClient.CompleteResponse.self, ["session_id": id, "broker_session_token": broker,
            "broker_session_expires_at": 20_000, "wca_access_token": "fixture-access", "wca_access_token_expires_at": 11_000,
            "server_time": 10_000, "token_generation": 1])
    }
    static func refresh(id: String = id, generation: Int64 = 2, accessExpiry: Int64 = 12_000,
                        serverTime: Int64 = 10_000) throws -> WCAOAuthBrokerClient.RefreshResponse {
        try decode(WCAOAuthBrokerClient.RefreshResponse.self, ["session_id": id, "wca_access_token": "fixture-new-access",
            "wca_access_token_expires_at": accessExpiry, "server_time": serverTime, "token_generation": generation])
    }
    static func pending(_ state: WCABrokerStoredSession.RecoveryState, count: Int) -> WCABrokerStoredSession.PendingRefresh {
        .init(sessionID: id, id: key, recoveryState: state, dispatchCount: count)
    }
    static func session(id: String = id, generation: Int64 = 1, access: String = "fixture-access",
                        accessExpiry: Int64 = 11_000, brokerExpiry: Int64 = 20_000,
                        pending: WCABrokerStoredSession.PendingRefresh? = nil) throws -> WCABrokerStoredSession {
        let token = try JSONDecoder().decode(WCAOAuthBrokerClient.WCAAccessToken.self, from: JSONEncoder().encode(access))
        return try .init(sessionID: id, brokerSessionToken: .init(rawValue: broker), brokerSessionExpiresAt: brokerExpiry,
                         wcaAccessToken: token, wcaAccessTokenExpiresAt: accessExpiry, tokenGeneration: generation, pendingRefresh: pending)
    }
    static func marker() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 2, "provider": "wca-broker-v1", "recordKind": "logout_intent"])
    }
}

@MainActor private final class CoordinatorHarness {
    let client = CoordinatorClient()
    let store = CoordinatorStore()
    let browser = CoordinatorBrowserFactory()
    let clock = CoordinatorClock()
    let profile: CoordinatorProfile?
    lazy var owner = newOwner()
    init(session: WCABrokerStoredSession? = nil, profile: CoordinatorProfile? = nil) throws {
        self.profile = profile
        if let session { store.raw = try JSONEncoder().encode(session) }
    }
    func newOwner() -> WCABrokerAuthCoordinator {
        WCABrokerAuthCoordinator(client: client, store: store, browserFactory: browser, clock: clock,
            makeAttempt: { try WCABrokerOAuthAttempt(random: CoordinatorRandom(), clock: self.clock.time) },
            makeUUID: { CoordinatorFixture.key }, profile: profile)
    }
    func deliver(error: String? = nil) {
        let state = client.starts.last!.appState
        var url = URLComponents(string: "cubeflow-wca://oauth/callback")!
        url.queryItems = [.init(name: "state", value: state),
            .init(name: error == nil ? "ticket" : "error", value: error ?? String(repeating: "T", count: 43))]
        browser.sessions.last!.deliver(.success(url.url!))
    }
}

@MainActor private final class CoordinatorClient: WCABrokerClientOperations {
    var starts: [WCAOAuthBrokerClient.StartRequest] = []
    var completeCalls = 0, logoutCalls = 0
    var refreshKeys: [UUID] = [], refreshTokens: [String] = []
    var completeValue: WCAOAuthBrokerClient.CompleteResponse?
    var startBody: ((WCAOAuthBrokerClient.StartRequest) async throws -> WCAOAuthBrokerClient.StartResponse)?
    var completeBody: ((WCAOAuthBrokerClient.CompleteRequest) async throws -> WCAOAuthBrokerClient.CompleteResponse)?
    var refreshBody: ((WCAOAuthBrokerClient.BrokerSessionToken, UUID) async throws -> WCAOAuthBrokerClient.RefreshResponse)?
    var logoutBody: ((WCAOAuthBrokerClient.BrokerSessionToken) async throws -> Void)?
    @MainActor func start(_ request: WCAOAuthBrokerClient.StartRequest) async throws -> WCAOAuthBrokerClient.StartResponse {
        starts.append(request)
        if let startBody { return try await startBody(request) }
        return try CoordinatorFixture.start()
    }
    @MainActor func complete(_ request: WCAOAuthBrokerClient.CompleteRequest) async throws -> WCAOAuthBrokerClient.CompleteResponse {
        completeCalls += 1
        if let completeBody { return try await completeBody(request) }
        return try completeValue ?? CoordinatorFixture.complete()
    }
    @MainActor func refresh(sessionToken: WCAOAuthBrokerClient.BrokerSessionToken, idempotencyKey: UUID) async throws -> WCAOAuthBrokerClient.RefreshResponse {
        refreshKeys.append(idempotencyKey); refreshTokens.append(sessionToken.rawValue)
        if let refreshBody { return try await refreshBody(sessionToken, idempotencyKey) }
        return try CoordinatorFixture.refresh()
    }
    @MainActor func logout(sessionToken: WCAOAuthBrokerClient.BrokerSessionToken) async throws {
        logoutCalls += 1
        try await logoutBody?(sessionToken)
    }
}

@MainActor private final class CoordinatorStore: WCABrokerSessionPersistence {
    var raw: Data?
    var operations: [String] = []
    var saves: [WCABrokerStoredSession] = []
    var clearCalls = 0, activeWrites = 0, maximumWrites = 0
    var loadBody: (() async throws -> WCABrokerSessionStore.LoadResult)?
    var saveBody: ((WCABrokerStoredSession) async throws -> Void)?
    var clearBody: (() async throws -> Void)?
    func saved() throws -> WCABrokerStoredSession? {
        try raw.map { try JSONDecoder().decode(WCABrokerStoredSession.self, from: $0) }
    }
    @MainActor func load() async throws -> WCABrokerSessionStore.LoadResult {
        operations.append("load")
        if let loadBody { return try await loadBody() }
        guard let raw else { return .absent }
        if let object = try JSONSerialization.jsonObject(with: raw) as? [String: Any], object["recordKind"] as? String == "logout_intent" {
            return .logoutPending
        }
        return .session(try JSONDecoder().decode(WCABrokerStoredSession.self, from: raw))
    }
    @MainActor func save(_ value: WCABrokerStoredSession) async throws {
        activeWrites += 1; maximumWrites = max(maximumWrites, activeWrites)
        defer { activeWrites -= 1 }
        saves.append(value)
        try await saveBody?(value)
        raw = try JSONEncoder().encode(value)
        operations.append("save")
    }
    @MainActor func clear() async throws {
        activeWrites += 1; maximumWrites = max(maximumWrites, activeWrites)
        defer { activeWrites -= 1 }
        clearCalls += 1
        try await clearBody?()
        raw = nil; operations.append("clear")
    }
}

@MainActor private final class CoordinatorBrowserFactory: WCABrokerBrowserFactory {
    var sessions: [CoordinatorBrowser] = []
    var startResult = true
    var onStart: (() -> Void)?
    func make(url: URL, callbackScheme: String,
              completion: @escaping @MainActor (Result<URL, WCABrokerBrowserFailure>) -> Void) -> any WCABrokerBrowserSession {
        let session = CoordinatorBrowser(scheme: callbackScheme, completion: completion)
        session.startResult = startResult; session.onStart = onStart
        sessions.append(session)
        return session
    }
}
@MainActor private final class CoordinatorBrowser: WCABrokerBrowserSession {
    let scheme: String
    let completion: @MainActor (Result<URL, WCABrokerBrowserFailure>) -> Void
    var cancelCalls = 0
    var startResult = true
    var onStart: (() -> Void)?
    init(scheme: String, completion: @escaping @MainActor (Result<URL, WCABrokerBrowserFailure>) -> Void) {
        self.scheme = scheme; self.completion = completion
    }
    func start() -> Bool { onStart?(); return startResult }
    func cancel() { cancelCalls += 1 }
    func deliver(_ result: Result<URL, WCABrokerBrowserFailure>) { completion(result) }
}

@MainActor private final class CoordinatorProfile: WCABrokerProfileProvider {
    var body: ((WCAOAuthBrokerClient.WCAAccessToken) async throws -> Void)?
    func fetchProfile(accessToken: WCAOAuthBrokerClient.WCAAccessToken) async throws { try await body?(accessToken) }
}

/// Deliberately ignores cancellation, to prove revision checks rather than cooperative cancellation provide safety.
@MainActor private final class CoordinatorGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Error>?
    var waiting: Bool { continuation != nil }
    func wait() async throws -> Value { try await withCheckedThrowingContinuation { continuation = $0 } }
    func succeed(_ value: Value) { let old = continuation; continuation = nil; old?.resume(returning: value) }
}

nonisolated private final class CoordinatorTime: WCABrokerAttemptClock, @unchecked Sendable {
    private let lock = NSLock()
    private var wall: TimeInterval = 10_000, uptime: TimeInterval = 100
    func read() -> WCABrokerAttemptTime { lock.lock(); defer { lock.unlock() }; return .init(wall: wall, uptime: uptime) }
    func advance(_ value: TimeInterval) { lock.lock(); defer { lock.unlock() }; wall += value; uptime += value }
}
@MainActor private final class CoordinatorClock: WCABrokerCoordinatorClock {
    let time = CoordinatorTime()
    var sleepers: [UUID: (TimeInterval, CheckedContinuation<Void, Error>)] = [:]
    func now() -> TimeInterval { time.read().wall }
    func wait(until deadline: TimeInterval) async throws {
        if deadline <= now() { return }
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { sleepers[id] = (deadline, $0) }
        }, onCancel: { Task { @MainActor in self.sleepers.removeValue(forKey: id)?.1.resume(throwing: CancellationError()) } })
    }
    func advance(_ value: TimeInterval) {
        time.advance(value)
        for (id, sleeper) in sleepers where sleeper.0 <= now() {
            sleepers.removeValue(forKey: id)?.1.resume()
        }
    }
}
nonisolated private struct CoordinatorRandom: WCABrokerRandomSource {
    func bytes(count: Int) throws -> Data { Data(repeating: 7, count: count) }
}
private actor CoordinatorRequestProbe {
    var tokens: [String] = []
    let alwaysUnauthorized: Bool
    init(alwaysUnauthorized: Bool = false) { self.alwaysUnauthorized = alwaysUnauthorized }
    func call(_ token: WCAOAuthBrokerClient.WCAAccessToken) throws -> String {
        tokens.append(token.rawValue)
        if alwaysUnauthorized { throw WCABrokerAuthCoordinator.WCARequestFailure.unauthorized }
        return "ok"
    }
}

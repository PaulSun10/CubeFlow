import Foundation
import XCTest
@testable import CubeFlow

#if DEBUG
@MainActor final class WCABrokerAppGateTests: XCTestCase {
    func testDefaultSelectionIsBrokerOrExplicitDebugMockWithoutPersistence() async throws {
        var constructions = 0
        WCABrokerMockEnvironment.makeIntegration = { constructions += 1; preconditionFailure("Unexpected fixture construction") }
        defer { WCABrokerMockEnvironment.makeIntegration = nil }
        #if CUBEFLOW_WCA_BROKER_MOCK
        WCABrokerMockEnvironment.makeIntegration = nil
        let manager = WCAAuthManager.debugDefaultManagerWithoutPersistence()
        XCTAssertTrue(WCAAuthenticationConfiguration.mode == .mock)
        XCTAssertTrue(manager.usesBrokerIntegration)
        XCTAssertEqual(manager.brokerPresentation?.phase, .storageBlocked)
        #else
        let manager = WCAAuthManager.debugDefaultManagerWithoutPersistence()
        XCTAssertTrue(WCAAuthenticationConfiguration.mode == .broker)
        XCTAssertTrue(manager.usesBrokerIntegration)
        XCTAssertEqual(manager.brokerPresentation?.phase, .restoring)
        XCTAssertEqual(constructions, 0)
        #endif
    }
}

#if CUBEFLOW_WCA_BROKER_MOCK
@MainActor final class WCABrokerAppIntegrationTests: XCTestCase {
    private func until(_ predicate: () -> Bool) async throws {
        for _ in 0..<1000 { if predicate() { return }; await Task.yield() }
        XCTFail("Mock boundary not reached")
        throw WCABrokerAuthCoordinator.Failure.staleOperation
    }
    private func login(_ h: AppHarness) async throws {
        let task = Task { try await h.manager.signIn() }
        try await until { h.browser.callback != nil }
        h.callback()
        try await task.value
    }
    private func expectFailure(_ action: () async throws -> Void) async {
        do { try await action(); XCTFail("Expected safe failure") }
        catch { XCTAssertFalse(String(reflecting: error).contains(AppFixture.broker)) }
    }

    func testLoginUsesCoordinatorAndExistingProfileModel() async throws {
        let h = AppHarness()
        try await login(h)
        XCTAssertEqual(h.client.completeCount, 1)
        XCTAssertTrue(h.manager.isSignedIn)
        XCTAssertEqual(h.manager.profile?.name, "Mock Cuber")
        XCTAssertEqual(h.manager.profile?.wcaId, "2000TEST01")
        XCTAssertEqual(h.manager.brokerPresentation?.phase, .ready)
    }

    func testLogoutUsesCoordinatorAndClearsInMemoryProfile() async throws {
        let h = AppHarness(); try await login(h)
        try await h.manager.brokerSignOut()
        XCTAssertEqual(h.client.logoutCount, 1)
        XCTAssertEqual(h.store.clears, 1)
        XCTAssertNil(h.manager.profile)
        XCTAssertFalse(h.manager.isSignedIn)
    }

    func testRestoreUsesV2OwnerWithoutFetchingProfileOrOpeningBrowser() async throws {
        let h = AppHarness(); h.store.record = try AppFixture.session()
        await h.manager.restoreBrokerSessionIfNeeded()
        XCTAssertEqual(h.store.loads, 1)
        XCTAssertEqual(h.manager.brokerPresentation?.phase, .profilePending)
        XCTAssertTrue(h.manager.isSignedIn)
        XCTAssertNil(h.manager.profile)
        XCTAssertTrue(h.http.requests.isEmpty)
        XCTAssertNil(h.browser.callback)
    }

    func testViewRecreationDoesNotDuplicateRestoration() async throws {
        let h = AppHarness(); h.store.record = try AppFixture.session()
        async let first: Void = h.manager.restoreBrokerSessionIfNeeded()
        async let second: Void = h.manager.restoreBrokerSessionIfNeeded()
        _ = await (first, second)
        await h.manager.restoreBrokerSessionIfNeeded()
        XCTAssertEqual(h.store.loads, 1)
    }

    func testLaunchAndSettingsShareRestorationAndCannotReloadAfterLogout() async throws {
        let h = AppHarness(restoreProfile: true)
        h.store.record = try AppFixture.session()
        let gate = AppGate(); h.store.loadGate = gate
        let launch = Task { await h.manager.restoreBrokerSessionIfNeeded() }
        try await until { gate.waiting }
        let settings = Task { await h.manager.restoreBrokerSessionIfNeeded() }
        gate.release()
        await launch.value; await settings.value
        XCTAssertEqual(h.store.loads, 1)
        XCTAssertEqual(h.http.requests.count, 1)
        XCTAssertTrue(h.manager.isSignedIn)
        XCTAssertEqual(h.browser.starts, 0)

        try await h.manager.brokerSignOut()
        await h.manager.restoreBrokerSessionIfNeeded()
        XCTAssertEqual(h.store.loads, 1)
        XCTAssertEqual(h.http.requests.count, 1)
        XCTAssertNil(h.manager.profile)
        XCTAssertFalse(h.manager.isSignedIn)
        XCTAssertEqual(h.manager.brokerPresentation?.phase, .signedOut)
    }

    func testSharedManagerCreatesOneStableOwner() async throws {
        let h = AppHarness()
        var made = 0
        WCABrokerMockEnvironment.makeIntegration = { made += 1; return h.integration }
        defer { WCABrokerMockEnvironment.makeIntegration = nil }
        let first = WCAAuthManager.shared, second = WCAAuthManager.shared
        XCTAssertTrue(first === second)
        XCTAssertEqual(made, 1)
        XCTAssertTrue(h.http.requests.isEmpty)
        XCTAssertEqual(h.store.loads, 0)
    }

    func testConcurrentLoginsDoNotCreateDuplicateBrowserSessions() async throws {
        let h = AppHarness()
        let first = Task { try await h.manager.signIn() }
        try await until { h.browser.callback != nil }
        await expectFailure { try await h.manager.signIn() }
        XCTAssertEqual(h.browser.starts, 1)
        h.callback(); try await first.value
    }

    func testForegroundKeyAnchorSelectedWithoutDependingOnArrayOrder() async throws {
        let candidates = [candidate("background", active: false), candidate("active")]
        XCTAssertEqual(WCABrokerAnchorSelection.choose(candidates), "active")
        XCTAssertEqual(WCABrokerAnchorSelection.choose(candidates.reversed()), "active")
    }

    func testMissingHiddenAndAmbiguousAnchorsAreRejected() async throws {
        XCTAssertNil(WCABrokerAnchorSelection.choose([]))
        XCTAssertNil(WCABrokerAnchorSelection.choose([candidate("hidden", visible: false)]))
        XCTAssertNil(WCABrokerAnchorSelection.choose([candidate("one"), candidate("two")]))
        XCTAssertNil(WCABrokerAnchorSelection.choose([candidate("not-key", key: false)]))
    }

    func testProfileFailureDoesNotDestroyPersistedSessionOrRepeatComplete() async throws {
        let h = AppHarness(); h.http.failProfile = true
        await expectFailure { try await self.login(h) }
        XCTAssertEqual(h.manager.brokerPresentation?.phase, .profilePending)
        XCTAssertTrue(h.manager.isSignedIn)
        XCTAssertNotNil(h.store.record)
        h.http.failProfile = false
        try await h.manager.refreshProfile()
        XCTAssertEqual(h.manager.profile?.name, "Mock Cuber")
        XCTAssertEqual(h.client.completeCount, 1)
    }

    func testLateProfileAfterLogoutIsRejected() async throws {
        let h = AppHarness(); let gate = AppGate()
        h.http.profileGate = gate
        let task = Task { try await h.manager.signIn() }
        try await until { h.browser.callback != nil }; h.callback()
        try await until { gate.waiting }
        try await h.manager.brokerSignOut()
        gate.release()
        await expectFailure { try await task.value }
        XCTAssertNil(h.manager.profile)
        XCTAssertFalse(h.manager.isSignedIn)
    }

    func testLateProfileAfterSessionReplacementIsRejected() async throws {
        let h = AppHarness(), gate = AppGate()
        h.http.profileGate = gate
        let first = Task { try await h.manager.signIn() }
        try await until { h.browser.callback != nil }; h.callback()
        try await until { gate.waiting }
        h.http.profileGate = nil
        h.http.profileName = "Replacement"
        h.client.sessionID = String(repeating: "C", count: 43)
        try await login(h)
        gate.release()
        await expectFailure { try await first.value }
        XCTAssertEqual(h.manager.profile?.name, "Replacement")
    }

    func testProfileAndRequestsUseOnlyBrokerSession() async throws {
        let h = AppHarness()
        XCTAssertNil(h.manager.profile)
        try await login(h)
        _ = try await h.manager.authenticatedData(for: AppFixture.mine)
        XCTAssertEqual(h.client.refreshCount, 0)
        XCTAssertEqual(h.manager.profile?.name, "Mock Cuber")
    }

    func testWCARequestsUseAccessTokenNotBrokerToken() async throws {
        let h = AppHarness(); try await login(h)
        _ = try await h.manager.authenticatedData(for: AppFixture.mine)
        XCTAssertTrue(h.http.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access" })
        XCTAssertFalse(h.http.requests.contains { $0.value(forHTTPHeaderField: "Authorization")?.contains(AppFixture.broker) == true })
        XCTAssertEqual(h.http.requests.last?.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func test401UsesCoordinatorRefreshAndOneRequestRetry() async throws {
        let h = AppHarness(); try await login(h)
        h.http.rejectOld = true
        _ = try await h.manager.authenticatedData(for: AppFixture.mine)
        XCTAssertEqual(h.client.refreshCount, 1)
        XCTAssertEqual(h.http.requests.filter { $0.url == AppFixture.mine }.count, 2)
        XCTAssertEqual(h.http.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-new-access")
    }

    func testConcurrent401SharesRefresh() async throws {
        let h = AppHarness(); try await login(h)
        h.http.rejectOld = true
        let gate = AppGate(); h.client.refreshGate = gate
        let requests = (0..<6).map { _ in Task { try await h.manager.authenticatedData(for: AppFixture.mine) } }
        try await until { gate.waiting }
        for _ in 0..<20 { await Task.yield() }
        gate.release()
        for task in requests { _ = try await task.value }
        XCTAssertEqual(h.client.refreshCount, 1)
    }

    func testRepeated401StopsAfterSecondWCARequest() async throws {
        let h = AppHarness(); try await login(h)
        h.http.always401 = true
        await expectFailure { _ = try await h.manager.authenticatedData(for: AppFixture.mine) }
        XCTAssertEqual(h.client.refreshCount, 1)
        XCTAssertEqual(h.http.requests.filter { $0.url == AppFixture.mine }.count, 2)
    }

    func testNewerTokenIsPreferredAfterDelayed401() async throws {
        let h = AppHarness(); try await login(h)
        let gate = AppGate(); h.http.oldRequestGate = gate; h.http.rejectOld = true
        let request = Task { try await h.manager.authenticatedData(for: AppFixture.mine) }
        try await until { gate.waiting }
        try await h.integration.coordinator.refresh()
        gate.release()
        _ = try await request.value
        XCTAssertEqual(h.client.refreshCount, 1)
    }

    func testBrokerLogoutClearsActiveSession() async throws {
        let h = AppHarness(); try await login(h)
        try await h.manager.brokerSignOut()
        XCTAssertEqual(h.store.clears, 1)
        XCTAssertEqual(h.client.logoutCount, 1)
        XCTAssertNil(h.store.record)
    }

    func testStorageBlockedIsNotPresentedAsSignedOut() async throws {
        let h = AppHarness(); h.store.failLoad = true
        await h.manager.restoreBrokerSessionIfNeeded()
        XCTAssertEqual(h.manager.brokerPresentation?.phase, .storageBlocked)
        XCTAssertTrue(h.manager.isSignedIn)
        XCTAssertFalse(h.manager.brokerPresentation?.message == "Not signed in")
    }

    func testRecoveryAndUncertainMessagesAreDistinctAndCredentialFree() async throws {
        let recovery = WCABrokerAccountPresentation(phase: .ready, refresh: .recoveryPending, hasSession: true)
        let uncertain = WCABrokerAccountPresentation(phase: .ready, refresh: .uncertain, hasSession: true)
        XCTAssertTrue(recovery.message.contains("Recovery"))
        XCTAssertTrue(uncertain.message.contains("sign in again"))
        for message in [recovery.message, uncertain.message] {
            XCTAssertFalse(message.contains(AppFixture.broker) || message.contains(AppFixture.id) || message.contains("UUID"))
        }
    }

    func testInitializationAndRestorationNeverCreateNetworkOrBrowserActivity() async throws {
        let h = AppHarness()
        XCTAssertTrue(h.http.requests.isEmpty)
        XCTAssertEqual(h.store.loads, 0)
        await h.manager.restoreBrokerSessionIfNeeded()
        XCTAssertTrue(h.http.requests.isEmpty)
        XCTAssertEqual(h.browser.starts, 0)
        XCTAssertEqual(h.client.starts.count, 0)
    }

    func testInvalidWCAOriginRejectedBeforeTransport() async throws {
        let h = AppHarness(); try await login(h)
        let count = h.http.requests.count
        await expectFailure { _ = try await h.manager.authenticatedData(for: URL(string: "https://attacker.invalid/api/v0/me")!) }
        XCTAssertEqual(h.http.requests.count, count)
    }

    func testLogoutFailureDoesNotPublishSuccessfulSignOut() async throws {
        let h = AppHarness(); try await login(h)
        h.store.failClear = true
        await expectFailure { try await h.manager.brokerSignOut() }
        XCTAssertEqual(h.manager.brokerPresentation?.phase, .storageBlocked)
        XCTAssertTrue(h.manager.isSignedIn)
        XCTAssertNil(h.manager.profile)
    }

    func testLateAPIResultCannotPublishAfterLogout() async throws {
        let h = AppHarness(); try await login(h)
        let revision = h.manager.brokerPublicationRevision
        let gate = AppGate(); h.http.oldRequestGate = gate
        let request = Task { try await h.manager.authenticatedData(for: AppFixture.mine) }
        try await until { gate.waiting }
        try await h.manager.brokerSignOut()
        gate.release()
        await expectFailure { _ = try await request.value }
        XCTAssertTrue(revision != h.manager.brokerPublicationRevision)
        XCTAssertNil(h.manager.profile)
    }

    func testLateAPIResultCannotPublishAfterSessionReplacement() async throws {
        let h = AppHarness(); try await login(h)
        let gate = AppGate(); h.http.oldRequestGate = gate
        let request = Task { try await h.manager.authenticatedData(for: AppFixture.mine) }
        try await until { gate.waiting }
        h.client.sessionID = String(repeating: "C", count: 43)
        h.http.profileName = "New Owner"
        try await login(h)
        gate.release()
        await expectFailure { _ = try await request.value }
        XCTAssertEqual(h.manager.profile?.name, "New Owner")
    }

    func testRecoveryPendingRestorationReachesSettingsWithoutNetwork() async throws {
        let h = AppHarness(); h.store.record = try AppFixture.session(recovery: .recoveryPending)
        await h.manager.restoreBrokerSessionIfNeeded()
        XCTAssertEqual(h.manager.brokerPresentation?.refresh, .recoveryPending)
        XCTAssertTrue(h.manager.brokerPresentation?.message.contains("Recovery") == true)
        XCTAssertTrue(h.http.requests.isEmpty)
        XCTAssertEqual(h.client.refreshCount, 0)
    }

    func testUncertainRestorationKeepsValidAccessWithoutImplyingRepair() async throws {
        let h = AppHarness(); h.store.record = try AppFixture.session(recovery: .uncertain)
        await h.manager.restoreBrokerSessionIfNeeded()
        _ = try await h.manager.authenticatedData(for: AppFixture.mine)
        XCTAssertEqual(h.manager.brokerPresentation?.refresh, .uncertain)
        XCTAssertEqual(h.client.refreshCount, 0)
        XCTAssertEqual(h.browser.starts, 0)
    }

    func testUnconfiguredMockFailsClosedWithoutAnotherProvider() async throws {
        WCABrokerMockEnvironment.makeIntegration = nil
        let manager = WCAAuthManager.debugDefaultManagerWithoutPersistence()
        await expectFailure { try await manager.signIn() }
        await manager.restoreBrokerSessionIfNeeded()
        XCTAssertTrue(manager.usesBrokerIntegration)
        XCTAssertEqual(manager.brokerPresentation?.phase, .storageBlocked)
        XCTAssertNil(manager.profile)
    }

    func testQueuedAutomaticRestoreCannotSupersedeLogout() async throws {
        let h = AppHarness(); h.store.record = try AppFixture.session()
        let pending = Task { await h.manager.restoreBrokerSessionIfNeeded() }
        try await h.manager.brokerSignOut()
        await pending.value
        XCTAssertNil(h.store.record)
        XCTAssertEqual(h.manager.brokerPresentation?.phase, .signedOut)
        XCTAssertNil(h.manager.profile)
    }

    func testFailedLogoutRetryDoesNotReloadOldCredentials() async throws {
        let h = AppHarness(); try await login(h)
        h.store.failClear = true
        await expectFailure { try await h.manager.brokerSignOut() }
        h.store.failClear = false
        try await h.manager.performBrokerAccountAction()
        XCTAssertEqual(h.store.loads, 0)
        XCTAssertNil(h.store.record)
        XCTAssertEqual(h.manager.brokerPresentation?.phase, .signedOut)
    }

    func testRealRestorePolicyLoadsProfileWithoutLaunchingAuthorization() async throws {
        let h = AppHarness(restoreProfile: true)
        h.store.record = try AppFixture.session()
        await h.manager.restoreBrokerSessionIfNeeded()
        await h.manager.restoreBrokerSessionIfNeeded()
        XCTAssertEqual(h.manager.profile?.name, "Mock Cuber")
        XCTAssertEqual(h.http.requests.count, 1)
        XCTAssertEqual(h.store.loads, 1)
        XCTAssertEqual(h.browser.starts, 0)
        XCTAssertEqual(h.client.completeCount, 0)
    }

    func testRealRestorePolicyProfileFailurePreservesSession() async throws {
        let h = AppHarness(restoreProfile: true)
        h.store.record = try AppFixture.session(); h.http.failProfile = true
        await h.manager.restoreBrokerSessionIfNeeded()
        XCTAssertEqual(h.manager.brokerPresentation?.phase, .profilePending)
        XCTAssertNotNil(h.store.record)
        XCTAssertEqual(h.browser.starts, 0)
    }

    private func cacheFixture() -> (UserDefaults, WCABrokerProfileCache, () -> Void) {
        let name = "CubeFlow.BrokerProfile.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, WCABrokerProfileCache(defaults: defaults), { defaults.removePersistentDomain(forName: name) })
    }

    func testColdLaunchHydratesPersistentCacheBeforeNetworkCompletes() async throws {
        let (defaults, cache, cleanup) = cacheFixture(); defer { cleanup() }
        let first = AppHarness(profileCache: cache)
        try await login(first)
        // A new cache and integration, rather than the previous in-memory profile.
        let h = AppHarness(restoreProfile: true, profileCache: WCABrokerProfileCache(defaults: defaults))
        h.store.record = first.store.record
        let gate = AppGate(); h.http.profileGate = gate
        let restore = Task { await h.manager.restoreBrokerSessionIfNeeded() }
        try await until { gate.waiting }
        XCTAssertEqual(h.manager.profile?.name, "Mock Cuber")
        XCTAssertEqual(h.manager.profile?.wcaId, "2000TEST01")
        XCTAssertNil(h.manager.brokerPresentation?.notice)
        XCTAssertTrue(h.manager.brokerPresentation?.loadingProfile == true)
        h.http.profileName = "Refreshed" // Current pending response retains its original snapshot.
        gate.release(); await restore.value
        h.http.profileGate = nil
        try await h.manager.refreshProfile()
        XCTAssertEqual(h.manager.profile?.name, "Refreshed")
        XCTAssertEqual(cache.load(sessionID: AppFixture.id)?.name, "Refreshed")
        XCTAssertEqual(h.client.completeCount, 0)
        XCTAssertEqual(h.browser.starts, 0)
    }

    func testImmediateSettingsDuringKeychainRestorationHasNoUnavailableMessageOrUnvalidatedProfile() async throws {
        let (_, cache, cleanup) = cacheFixture(); defer { cleanup() }
        cache.save(.init(id: 1, name: "Cached", wcaId: "2000TEST01", email: nil, avatarURL: nil, avatarIsDefault: nil), sessionID: AppFixture.id)
        let h = AppHarness(restoreProfile: true, profileCache: cache)
        h.store.record = try AppFixture.session()
        let gate = AppGate(); h.store.loadGate = gate
        XCTAssertEqual(h.manager.brokerPresentation?.phase, .restoring)
        XCTAssertTrue(h.manager.brokerPresentation?.showsAccountRow == true)
        XCTAssertTrue(h.manager.brokerPresentation?.showsProfileLoading == true)
        XCTAssertFalse(h.manager.isSignedIn)
        XCTAssertNil(h.manager.brokerPresentation?.notice)
        let restore = Task { await h.manager.restoreBrokerSessionIfNeeded() }
        try await until { gate.waiting }
        XCTAssertEqual(h.manager.brokerPresentation?.phase, .restoring)
        XCTAssertTrue(h.manager.brokerPresentation?.showsAccountRow == true)
        XCTAssertTrue(h.manager.brokerPresentation?.showsProfileLoading == true)
        XCTAssertNil(h.manager.profile) // Defaults cannot establish authentication before Keychain validation.
        XCTAssertNil(h.manager.brokerPresentation?.notice)
        gate.release(); await restore.value
        XCTAssertNotNil(h.manager.profile)
    }

    func testNoCacheShowsLoadingThenProfileWithoutTransientFailureNotice() async throws {
        let h = AppHarness(restoreProfile: true)
        h.store.record = try AppFixture.session()
        let gate = AppGate(); h.http.profileGate = gate
        let restore = Task { await h.manager.restoreBrokerSessionIfNeeded() }
        try await until { gate.waiting }
        XCTAssertNil(h.manager.profile)
        XCTAssertTrue(h.manager.brokerPresentation?.loadingProfile == true)
        XCTAssertTrue(h.manager.brokerPresentation?.showsAccountRow == true)
        XCTAssertTrue(h.manager.brokerPresentation?.showsProfileLoading == true)
        XCTAssertNil(h.manager.brokerPresentation?.notice)
        gate.release(); await restore.value
        XCTAssertNotNil(h.manager.profile)
        XCTAssertFalse(h.manager.brokerPresentation?.loadingProfile == true)
        XCTAssertNil(h.manager.brokerPresentation?.notice)
    }

    func testFailureWithCachePreservesIdentityAndExposesRecoverableNotice() async throws {
        let (_, cache, cleanup) = cacheFixture(); defer { cleanup() }
        cache.save(.init(id: 1, name: "Cached", wcaId: nil, email: nil, avatarURL: nil, avatarIsDefault: nil), sessionID: AppFixture.id)
        let h = AppHarness(restoreProfile: true, profileCache: cache)
        h.store.record = try AppFixture.session(); h.http.failProfile = true
        await h.manager.restoreBrokerSessionIfNeeded()
        XCTAssertEqual(h.manager.profile?.name, "Cached")
        XCTAssertFalse(h.manager.brokerPresentation?.loadingProfile == true)
        XCTAssertTrue(h.manager.brokerPresentation?.notice?.contains("unavailable") == true)
        h.http.failProfile = false
        try await h.manager.performBrokerAccountAction()
        XCTAssertEqual(h.manager.profile?.name, "Mock Cuber")
        XCTAssertNil(h.manager.brokerPresentation?.notice)
    }

    func testFailureWithoutCacheStopsSpinnerAndRetryResumesLoading() async throws {
        let h = AppHarness(restoreProfile: true)
        h.store.record = try AppFixture.session(); h.http.failProfile = true
        await h.manager.restoreBrokerSessionIfNeeded()
        XCTAssertNil(h.manager.profile)
        XCTAssertFalse(h.manager.brokerPresentation?.loadingProfile == true)
        XCTAssertTrue(h.manager.brokerPresentation?.notice?.contains("unavailable") == true)
        h.http.failProfile = false
        let gate = AppGate(); h.http.profileGate = gate
        let retry = Task { try await h.manager.performBrokerAccountAction() }
        try await until { gate.waiting }
        XCTAssertTrue(h.manager.brokerPresentation?.loadingProfile == true)
        XCTAssertNil(h.manager.brokerPresentation?.notice)
        gate.release(); try await retry.value
        XCTAssertNotNil(h.manager.profile)
    }

    func testCacheCannotAuthenticateWithoutSessionOrWithDifferentSession() async throws {
        let (_, cache, cleanup) = cacheFixture(); defer { cleanup() }
        cache.save(.init(id: 1, name: "Other Account", wcaId: nil, email: nil, avatarURL: nil, avatarIsDefault: nil), sessionID: String(repeating: "C", count: 43))
        let absent = AppHarness(restoreProfile: true, profileCache: cache)
        await absent.manager.restoreBrokerSessionIfNeeded()
        XCTAssertNil(absent.manager.profile)
        XCTAssertFalse(absent.manager.isSignedIn)
        let h = AppHarness(restoreProfile: true, profileCache: cache)
        h.store.record = try AppFixture.session()
        let gate = AppGate(); h.http.profileGate = gate
        let restore = Task { await h.manager.restoreBrokerSessionIfNeeded() }
        try await until { gate.waiting }
        XCTAssertNil(h.manager.profile)
        gate.release(); await restore.value
        XCTAssertEqual(h.manager.profile?.name, "Mock Cuber")
    }

    func testLogoutClearsCacheAndRelaunchDoesNotRestoreAccount() async throws {
        let (defaults, cache, cleanup) = cacheFixture(); defer { cleanup() }
        let h = AppHarness(profileCache: cache); try await login(h)
        XCTAssertNotNil(cache.load(sessionID: AppFixture.id))
        try await h.manager.brokerSignOut()
        XCTAssertNil(cache.load(sessionID: AppFixture.id))
        let relaunched = AppHarness(restoreProfile: true, profileCache: WCABrokerProfileCache(defaults: defaults))
        relaunched.store.record = h.store.record
        await relaunched.manager.restoreBrokerSessionIfNeeded()
        XCTAssertNil(relaunched.manager.profile)
        XCTAssertFalse(relaunched.manager.isSignedIn)
        XCTAssertTrue(relaunched.http.requests.isEmpty)
    }

    func testDelayedProfileCannotRepopulateCacheAfterLogout() async throws {
        let (_, cache, cleanup) = cacheFixture(); defer { cleanup() }
        let h = AppHarness(profileCache: cache); try await login(h)
        let gate = AppGate(); h.http.profileGate = gate
        let refresh = Task { try await h.manager.refreshProfile() }
        try await until { gate.waiting }
        try await h.manager.brokerSignOut()
        gate.release(); await expectFailure { try await refresh.value }
        XCTAssertNil(cache.load(sessionID: AppFixture.id))
        XCTAssertNil(h.manager.profile)
    }

    func testAccountReplacementCannotShowOrCacheOldProfile() async throws {
        let (_, cache, cleanup) = cacheFixture(); defer { cleanup() }
        let h = AppHarness(profileCache: cache); try await login(h)
        h.client.sessionID = String(repeating: "C", count: 43)
        h.http.profileName = "Different Account"
        let gate = AppGate(); h.http.profileGate = gate
        let loginTask = Task { try await h.manager.signIn() }
        try await until { h.browser.callback != nil }; h.callback()
        try await until { gate.waiting }
        XCTAssertNil(h.manager.profile)
        gate.release(); try await loginTask.value
        XCTAssertEqual(h.manager.profile?.name, "Different Account")
        XCTAssertNil(cache.load(sessionID: AppFixture.id))
        XCTAssertEqual(cache.load(sessionID: h.client.sessionID)?.name, "Different Account")
    }

    func testProfileCacheIgnoresRetiredProfileDefaults() async throws {
        let (defaults, cache, cleanup) = cacheFixture(); defer { cleanup() }
        let sentinel = Data("legacy-private-fixture".utf8)
        defaults.set(sentinel, forKey: "wca_profile")
        XCTAssertNil(cache.load(sessionID: AppFixture.id))
        let h = AppHarness(profileCache: cache); try await login(h)
        try await h.manager.brokerSignOut()
        XCTAssertEqual(defaults.data(forKey: "wca_profile"), sentinel)
    }

    func testUnsupportedOrCorruptProfileCacheFallsBackToInitialLoading() async throws {
        let (defaults, cache, cleanup) = cacheFixture(); defer { cleanup() }
        defaults.set(Data("not json".utf8), forKey: "wca_broker_profile_v1")
        XCTAssertNil(cache.load(sessionID: AppFixture.id))
        cache.save(.init(id: 1, name: "Cached", wcaId: nil, email: nil, avatarURL: nil, avatarIsDefault: nil), sessionID: AppFixture.id)
        var json = try JSONSerialization.jsonObject(with: defaults.data(forKey: "wca_broker_profile_v1")!) as! [String: Any]
        json["version"] = 99
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: "wca_broker_profile_v1")
        XCTAssertNil(cache.load(sessionID: AppFixture.id))
    }

    func testKeychainFailureDoesNotExposeDefaultsIdentity() async throws {
        let (_, cache, cleanup) = cacheFixture(); defer { cleanup() }
        cache.save(.init(id: 1, name: "Cached", wcaId: nil, email: nil, avatarURL: nil, avatarIsDefault: nil), sessionID: AppFixture.id)
        let h = AppHarness(restoreProfile: true, profileCache: cache)
        h.store.record = try AppFixture.session(); h.store.failLoad = true
        await h.manager.restoreBrokerSessionIfNeeded()
        XCTAssertEqual(h.manager.brokerPresentation?.phase, .storageBlocked)
        XCTAssertNil(h.manager.profile)
        XCTAssertFalse(h.manager.brokerPresentation?.loadingProfile == true)
        XCTAssertTrue(h.http.requests.isEmpty)
    }

    func testBackgroundRefreshKeepsCachedIdentityWhilePending() async throws {
        let (_, cache, cleanup) = cacheFixture(); defer { cleanup() }
        let h = AppHarness(profileCache: cache); try await login(h)
        let gate = AppGate(); h.http.profileGate = gate; h.http.profileName = "Updated"
        let refresh = Task { try await h.manager.refreshProfile() }
        try await until { gate.waiting }
        XCTAssertEqual(h.manager.profile?.name, "Mock Cuber")
        XCTAssertEqual(cache.load(sessionID: AppFixture.id)?.name, "Mock Cuber")
        XCTAssertNil(h.manager.brokerPresentation?.notice)
        gate.release(); try await refresh.value
        XCTAssertEqual(h.manager.profile?.name, "Updated")
        XCTAssertEqual(cache.load(sessionID: AppFixture.id)?.name, "Updated")
    }

    func testBothSettingsSurfacesOmitStandaloneSignedInNotice() async throws {
        let h = AppHarness(); try await login(h)
        XCTAssertEqual(h.manager.brokerPresentation?.phase, .ready)
        // Both Settings surfaces use this shared notice policy, not the unconditional status message.
        XCTAssertNil(h.manager.brokerPresentation?.notice)
        // Hostless harness source is symlinked: resolve before deriving the repository path.
        let resolved = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("CubeFlow/Views/iPhone/SettingsTabView.swift")
        let source = try String(contentsOf: resolved, encoding: .utf8)
        XCTAssertEqual(source.components(separatedBy: "let notice = wcaAuth.brokerPresentation?.notice").count - 1, 2)
        XCTAssertFalse(source.contains("Text(presentation.message)"))
    }

    func testNoSessionShowsNeutralRowUntilRestorationDefinitivelyFinishes() async throws {
        let h = AppHarness(restoreProfile: true), gate = AppGate()
        h.store.loadGate = gate
        XCTAssertTrue(h.manager.brokerPresentation?.showsAccountRow == true)
        let restore = Task { await h.manager.restoreBrokerSessionIfNeeded() }
        try await until { gate.waiting }
        XCTAssertTrue(h.manager.brokerPresentation?.showsAccountRow == true)
        XCTAssertTrue(h.manager.brokerPresentation?.showsProfileLoading == true)
        XCTAssertFalse(h.manager.isSignedIn)
        gate.release(); await restore.value
        XCTAssertEqual(h.manager.brokerPresentation?.phase, .signedOut)
        XCTAssertFalse(h.manager.brokerPresentation?.showsAccountRow == true)
        XCTAssertFalse(h.manager.brokerPresentation?.showsProfileLoading == true)
        XCTAssertTrue(h.http.requests.isEmpty)
        XCTAssertEqual(h.browser.starts, 0)
    }

    func testDelayedSessionRestorationCannotReplaceLoggedOutCard() async throws {
        let (_, cache, cleanup) = cacheFixture(); defer { cleanup() }
        let h = AppHarness(restoreProfile: true, profileCache: cache), gate = AppGate()
        h.store.record = try AppFixture.session(); h.store.loadGate = gate
        cache.save(.init(id: 1, name: "Old Account", wcaId: nil, email: nil, avatarURL: nil, avatarIsDefault: nil), sessionID: AppFixture.id)
        let restore = Task { await h.manager.restoreBrokerSessionIfNeeded() }
        try await until { gate.waiting }
        try await h.manager.brokerSignOut()
        XCTAssertFalse(h.manager.brokerPresentation?.showsAccountRow == true)
        gate.release(); await restore.value // Store deliberately returns its pre-logout snapshot.
        await h.manager.restoreBrokerSessionIfNeeded()
        XCTAssertEqual(h.manager.brokerPresentation?.phase, .signedOut)
        XCTAssertFalse(h.manager.brokerPresentation?.showsAccountRow == true)
        XCTAssertFalse(h.manager.brokerPresentation?.showsProfileLoading == true)
        XCTAssertNil(h.manager.profile)
        XCTAssertNil(cache.load(sessionID: AppFixture.id))
        XCTAssertTrue(h.http.requests.isEmpty)
    }

    func testExplicitLogoutAndRelaunchReturnToSignedOutCardAfterRestoration() async throws {
        let h = AppHarness(); try await login(h)
        try await h.manager.brokerSignOut()
        XCTAssertFalse(h.manager.brokerPresentation?.showsAccountRow == true)
        let next = AppHarness(restoreProfile: true)
        next.store.record = h.store.record
        XCTAssertTrue(next.manager.brokerPresentation?.showsAccountRow == true)
        await next.manager.restoreBrokerSessionIfNeeded()
        XCTAssertFalse(next.manager.brokerPresentation?.showsAccountRow == true)
        XCTAssertNil(next.manager.profile)
    }

    func testLoadingWordingIsLocalizedAndSharedByExistingStatusCard() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("CubeFlow")
        for (language, expected) in [("en", "Loading WCA Profile…"), ("zh-Hant", "正在載入 WCA 個人資料…"),
                                     ("zh-Hans", "正在加载 WCA 个人资料…")] {
            let data = try Data(contentsOf: root.appendingPathComponent("\(language).lproj/Localizable.strings"))
            let strings = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            XCTAssertEqual(strings["settings.wca_loading_profile"], expected)
        }
        let source = try String(contentsOf: root.appendingPathComponent("Views/iPhone/SettingsTabView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("if showsWCAAccountRow {"))
        XCTAssertTrue(source.contains("wcaAuth.brokerPresentation?.showsAccountRow == true"))
        XCTAssertTrue(source.contains("appLocalizedString(\"settings.wca_loading_profile\", languageCode: appLanguage)"))
        XCTAssertTrue(source.contains("Text(wcaStatusTitle)"))
        XCTAssertTrue(source.contains("wcaStatusCard(showsDisclosure: true)"))
        XCTAssertTrue(source.contains("wcaStatusCard(showsDisclosure: false)"))
    }

    func testRealRestorePolicyRefreshesExpiredAccessWithoutNewAuthorization() async throws {
        let h = AppHarness(restoreProfile: true)
        let value = try AppFixture.session()
        h.store.record = try .init(sessionID: value.sessionID, brokerSessionToken: value.brokerSessionToken,
            brokerSessionExpiresAt: value.brokerSessionExpiresAt, wcaAccessToken: value.wcaAccessToken,
            wcaAccessTokenExpiresAt: 9_999, tokenGeneration: 1)
        await h.manager.restoreBrokerSessionIfNeeded()
        XCTAssertEqual(h.manager.profile?.name, "Mock Cuber")
        XCTAssertEqual(h.client.refreshCount, 1)
        XCTAssertEqual(h.browser.starts, 0)
        XCTAssertEqual(h.client.completeCount, 0)
    }

    func testSafeDiagnosticsFollowLoginAndLogoutWithoutCredentialValues() async throws {
        var events: [WCABrokerAuthCoordinator.DiagnosticEvent] = []
        let h = AppHarness(diagnostics: { events.append($0) })
        try await login(h)
        try await h.manager.brokerSignOut()
        for required: WCABrokerAuthCoordinator.DiagnosticEvent in [.startInitiated, .startSucceeded, .callbackValidated,
            .completeInitiated, .completeSucceeded, .sessionPersisted, .profileLoaded, .logoutLocalCleared, .logoutRemoteConfirmed] {
            XCTAssertTrue(events.contains(required))
        }
        XCTAssertTrue(events.allSatisfy { !$0.rawValue.contains(AppFixture.broker) && !$0.rawValue.contains("http") })
    }

    private func candidate(_ id: String, active: Bool = true, key: Bool = true, visible: Bool = true) -> WCABrokerAnchorSelection.Candidate {
        .init(id: id, active: active, key: key, visible: visible, normalLevel: true)
    }
}

nonisolated private enum AppFixture {
    static let id = String(repeating: "A", count: 43), broker = String(repeating: "B", count: 43)
    static let mine = URL(string: "https://www.worldcubeassociation.org/api/v0/competitions/mine")!
    static func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
    static func complete(_ sessionID: String = id) throws -> WCAOAuthBrokerClient.CompleteResponse {
        try decode(WCAOAuthBrokerClient.CompleteResponse.self, ["session_id": sessionID, "broker_session_token": broker,
            "broker_session_expires_at": 20_000, "wca_access_token": "fixture-access", "wca_access_token_expires_at": 11_000,
            "server_time": 10_000, "token_generation": 1])
    }
    static func session(recovery: WCABrokerStoredSession.RecoveryState? = nil) throws -> WCABrokerStoredSession {
        let value = try complete()
        return try .init(sessionID: id, brokerSessionToken: value.brokerSessionToken, brokerSessionExpiresAt: value.brokerSessionExpiresAt,
            wcaAccessToken: value.wcaAccessToken, wcaAccessTokenExpiresAt: value.wcaAccessTokenExpiresAt, tokenGeneration: 1,
            pendingRefresh: recovery.map { .init(sessionID: id, id: UUID(), recoveryState: $0, dispatchCount: 1) })
    }
}
@MainActor private final class AppHarness {
    let client = AppClient(), store = AppStore(), browser = AppBrowserFactory(), http = AppHTTP()
    let integration: WCABrokerAppIntegration
    let manager: WCAAuthManager
    init(restoreProfile: Bool = false, diagnostics: (@MainActor (WCABrokerAuthCoordinator.DiagnosticEvent) -> Void)? = nil,
         profileCache: WCABrokerProfileCache? = nil) {
        let clock = AppClock()
        integration = WCABrokerAppIntegration(.init(client: client, store: store, browser: browser, clock: clock,
            attempt: { try WCABrokerOAuthAttempt(random: AppRandom(), clock: AppAttemptClock()) },
            request: { [http] request in try await http.data(request) }, diagnostics: diagnostics, restoreProfile: restoreProfile,
            profileCache: profileCache))
        manager = WCAAuthManager.debugBrokerManager(integration)
    }
    func callback() {
        let state = client.starts.last!.appState
        browser.callback?(.success(URL(string: "cubeflow-wca://oauth/callback?state=\(state)&ticket=\(String(repeating: "T", count: 43))")!))
        browser.callback = nil
    }
}
@MainActor private final class AppClient: WCABrokerClientOperations {
    var starts: [WCAOAuthBrokerClient.StartRequest] = []
    var completeCount = 0, refreshCount = 0, logoutCount = 0
    var sessionID = AppFixture.id
    var refreshGate: AppGate?
    @MainActor func start(_ request: WCAOAuthBrokerClient.StartRequest) async throws -> WCAOAuthBrokerClient.StartResponse {
        starts.append(request)
        var c = URLComponents(string: "https://www.worldcubeassociation.org/oauth/authorize")!
        c.queryItems = [.init(name: "client_id", value: "fixture"), .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "public"), .init(name: "state", value: AppFixture.id),
            .init(name: "redirect_uri", value: "https://api.cubeflow.com.cn/v1/oauth/wca/callback")]
        return try AppFixture.decode(WCAOAuthBrokerClient.StartResponse.self, ["authorization_url": c.string!, "transaction_expires_at": 10_600])
    }
    @MainActor func complete(_ request: WCAOAuthBrokerClient.CompleteRequest) async throws -> WCAOAuthBrokerClient.CompleteResponse {
        completeCount += 1; return try AppFixture.complete(sessionID)
    }
    @MainActor func refresh(sessionToken: WCAOAuthBrokerClient.BrokerSessionToken, idempotencyKey: UUID) async throws -> WCAOAuthBrokerClient.RefreshResponse {
        refreshCount += 1
        try await refreshGate?.wait()
        return try AppFixture.decode(WCAOAuthBrokerClient.RefreshResponse.self, ["session_id": sessionID,
            "wca_access_token": "fixture-new-access", "wca_access_token_expires_at": 12_000, "server_time": 10_000, "token_generation": 2])
    }
    @MainActor func logout(sessionToken: WCAOAuthBrokerClient.BrokerSessionToken) async throws { logoutCount += 1 }
}
@MainActor private final class AppStore: WCABrokerSessionPersistence {
    var record: WCABrokerStoredSession?
    var loads = 0, clears = 0
    var failLoad = false, failClear = false
    var loadGate: AppGate?
    @MainActor func load() async throws -> WCABrokerSessionStore.LoadResult {
        loads += 1
        let snapshot = record
        try await loadGate?.wait()
        if failLoad { throw WCABrokerSessionStore.Failure.temporarilyInaccessible(.read, -25308) }
        return snapshot.map { .session($0) } ?? .absent
    }
    @MainActor func save(_ session: WCABrokerStoredSession) async throws { record = session }
    @MainActor func clear() async throws {
        if failClear { throw WCABrokerSessionStore.Failure.keychainFailure(.delete, -50) }
        clears += 1; record = nil
    }
}
@MainActor private final class AppBrowserFactory: WCABrokerBrowserFactory {
    var starts = 0
    var callback: (@MainActor (Result<URL, WCABrokerBrowserFailure>) -> Void)?
    func make(url: URL, callbackScheme: String, completion: @escaping @MainActor (Result<URL, WCABrokerBrowserFailure>) -> Void) -> any WCABrokerBrowserSession {
        callback = completion; return AppBrowser { self.starts += 1 }
    }
}
@MainActor private final class AppBrowser: WCABrokerBrowserSession {
    let onStart: () -> Void
    init(_ onStart: @escaping () -> Void) { self.onStart = onStart }
    func start() -> Bool { onStart(); return true }
    func cancel() {}
}
@MainActor private final class AppHTTP {
    var requests: [URLRequest] = []
    var failProfile = false, rejectOld = false, always401 = false
    var profileName = "Mock Cuber"
    var profileGate: AppGate?, oldRequestGate: AppGate?
    func data(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let isProfile = request.url!.path.hasSuffix("/me")
        let name = profileName
        if isProfile { try await profileGate?.wait() }
        if !isProfile && request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access" { try await oldRequestGate?.wait() }
        let status = (isProfile && failProfile) ? 503 : (always401 || (rejectOld && request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access") ? 401 : 200)
        let data = try JSONSerialization.data(withJSONObject: isProfile ? ["me": ["name": name, "wca_id": "2000TEST01"]] : ["competitions": []])
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
@MainActor private final class AppGate {
    var continuation: CheckedContinuation<Void, Error>?
    var waiting: Bool { continuation != nil }
    func wait() async throws { try await withCheckedThrowingContinuation { continuation = $0 } }
    func release() { let old = continuation; continuation = nil; old?.resume() }
}
@MainActor private struct AppClock: WCABrokerCoordinatorClock {
    func now() -> TimeInterval { 10_000 }
    func wait(until deadline: TimeInterval) async throws { try await Task.sleep(nanoseconds: 600_000_000_000) }
}
nonisolated private struct AppAttemptClock: WCABrokerAttemptClock {
    func read() -> WCABrokerAttemptTime { .init(wall: 10_000, uptime: 100) }
}
nonisolated private struct AppRandom: WCABrokerRandomSource {
    func bytes(count: Int) throws -> Data { Data(repeating: 9, count: count) }
}
#endif
#endif

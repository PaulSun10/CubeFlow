import Combine
import Foundation
#if canImport(UIKit)
import AuthenticationServices
import UIKit
#endif

nonisolated protocol WCABrokerClientOperations: Sendable {
    func start(_ request: WCAOAuthBrokerClient.StartRequest) async throws -> WCAOAuthBrokerClient.StartResponse
    func complete(_ request: WCAOAuthBrokerClient.CompleteRequest) async throws -> WCAOAuthBrokerClient.CompleteResponse
    func refresh(sessionToken: WCAOAuthBrokerClient.BrokerSessionToken, idempotencyKey: UUID) async throws -> WCAOAuthBrokerClient.RefreshResponse
    func logout(sessionToken: WCAOAuthBrokerClient.BrokerSessionToken) async throws
}
extension WCAOAuthBrokerClient: WCABrokerClientOperations {}

nonisolated protocol WCABrokerSessionPersistence: Sendable {
    func load() async throws -> WCABrokerSessionStore.LoadResult
    func save(_ session: WCABrokerStoredSession) async throws
    func clear() async throws
}
extension WCABrokerSessionStore: WCABrokerSessionPersistence {}

@MainActor protocol WCABrokerCoordinatorClock {
    func now() -> TimeInterval
    func wait(until deadline: TimeInterval) async throws
}

@MainActor struct WCABrokerCoordinatorSystemClock: WCABrokerCoordinatorClock {
    func now() -> TimeInterval { Date().timeIntervalSince1970 }
    func wait(until deadline: TimeInterval) async throws {
        let delay = max(0, deadline - now())
        guard delay.isFinite, delay <= 600 else { throw WCABrokerAuthCoordinator.Failure.expired }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}

nonisolated enum WCABrokerBrowserFailure: Error, Sendable { case cancelled, unavailable, expired }
@MainActor protocol WCABrokerBrowserSession: AnyObject {
    func start() -> Bool
    func cancel()
}
@MainActor protocol WCABrokerBrowserFactory {
    func make(url: URL, callbackScheme: String,
              completion: @escaping @MainActor (Result<URL, WCABrokerBrowserFailure>) -> Void) -> any WCABrokerBrowserSession
}

/// Acquisition hook only; it must not publish authentication/profile state before owner validation.
/// Phase 5 must stage actual profile data until its revision is validated; no WCA wire schema is invented here.
@MainActor protocol WCABrokerProfileProvider {
    func fetchProfile(accessToken: WCAOAuthBrokerClient.WCAAccessToken) async throws
}

nonisolated private protocol WCABrokerCoordinatorRedacted: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {}
extension WCABrokerCoordinatorRedacted {
    nonisolated var description: String { "<redacted Broker authentication>" }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: EmptyCollection<(label: String?, value: Any)>()) }
}

/// One logical writer per v2 account. Phase 5 must retain ONE owner; separate instances/processes are not a CAS domain.
/// Explicit operations only: construction does not restore, launch a browser, or create a network transport.
@MainActor
final class WCABrokerAuthCoordinator: ObservableObject, WCABrokerCoordinatorRedacted {
    nonisolated enum DiagnosticEvent: String, Sendable {
        #if DEBUG
        case realTestMode
        #endif
        case startInitiated, startSucceeded, startFailed, browserOpened, browserCompleted, browserCancelled, browserExpired, browserUnavailable
        case callbackValidated, callbackRejected, completeInitiated, completeSucceeded, completeFailed, completeOutcomeUnknown, authorizationFailed
        case sessionRestored, sessionPersisted, storageFailed, profileLoaded, profileFailed
        case refreshStarted, refreshRecovered, refreshFailed, refreshUncertain, wca401Handled
        case logoutLocalCleared, logoutStorageFailed, logoutRemoteConfirmed, logoutRemoteFailed
    }
    nonisolated enum State: Sendable {
        case restoring, signedOut, starting, authorizing, completing, persistingCredentials
        case profilePending, ready, needsLogin, storageBlocked
    }
    nonisolated enum RefreshStatus: Sendable { case idle, pending, recoveryPending, uncertain }
    nonisolated enum Failure: Error, Equatable, Sendable {
        case busy, cancelled, staleOperation, denied, expired, invalidCallback, browserUnavailable
        case brokerUnavailable, completionUnknown, storage, noSession, sessionInvalid
        case recoveryRequired, uncertain, conflictingGeneration, profileUnavailable, apiUnauthorized, apiFailure
    }
    nonisolated enum WCARequestFailure: Error, Sendable { case unauthorized }
    nonisolated struct AccessCredential: Sendable, WCABrokerCoordinatorRedacted {
        let token: WCAOAuthBrokerClient.WCAAccessToken
        let sessionID: String
        let generation: Int64
        let revision: UInt64
    }

    @Published private(set) var state: State = .signedOut
    @Published private(set) var refreshStatus: RefreshStatus = .idle
    @Published private(set) var lastFailure: Failure?
    @Published private(set) var isLoadingProfile = false
    var hasPersistedSession: Bool { session != nil }
    /// Cache lookup is permitted only after session restoration/creation, never from a defaults-only identity.
    var profileCacheSessionID: String? {
        guard let session, valid(session.brokerSessionExpiresAt) else { return nil }
        return session.sessionID
    }
    var canRetryPersistence: Bool { persistenceCandidate != nil }
    private(set) var sessionRevision: UInt64 = 0
    private let client: any WCABrokerClientOperations
    private let store: any WCABrokerSessionPersistence
    private let browserFactory: any WCABrokerBrowserFactory
    private let clock: any WCABrokerCoordinatorClock
    private let makeAttempt: @MainActor () throws -> WCABrokerOAuthAttempt
    private let makeUUID: @MainActor () -> UUID
    private let profile: (any WCABrokerProfileProvider)?
    private let diagnostics: (@MainActor (DiagnosticEvent) -> Void)?
    private var session: WCABrokerStoredSession?
    private var profileReady = false
    private var attempt: WCABrokerOAuthAttempt?
    private var browser: (any WCABrokerBrowserSession)?
    private var browserContinuation: CheckedContinuation<URL, Error>?
    private var browserDeadline: Task<Void, Never>?
    private var refreshFlight: (id: UUID, task: Task<Void, Error>)?
    private var profileFlight: (revision: UInt64, task: Task<Void, Error>)?
    private var writeTail: Task<Void, Never>?
    private var persistenceCandidate: (revision: UInt64, value: WCABrokerStoredSession, login: Bool)?
    private let expiryMargin: TimeInterval = 5

    init(client: any WCABrokerClientOperations, store: any WCABrokerSessionPersistence,
         browserFactory: any WCABrokerBrowserFactory, clock: any WCABrokerCoordinatorClock,
         makeAttempt: @escaping @MainActor () throws -> WCABrokerOAuthAttempt,
         makeUUID: @escaping @MainActor () -> UUID = { UUID() }, profile: (any WCABrokerProfileProvider)? = nil,
         diagnostics: (@MainActor (DiagnosticEvent) -> Void)? = nil) {
        self.client = client; self.store = store; self.browserFactory = browserFactory
        self.clock = clock; self.makeAttempt = makeAttempt; self.makeUUID = makeUUID; self.profile = profile
        self.diagnostics = diagnostics
    }

    func restore() async throws {
        guard persistenceCandidate == nil else { throw Failure.storage }
        let revision = invalidate(discardSession: true)
        state = .restoring
        await writeTail?.value
        try owns(revision)
        let result: WCABrokerSessionStore.LoadResult
        do { result = try await store.load() }
        catch { try owns(revision); fail(.storage, state: .storageBlocked); throw Failure.storage }
        try owns(revision)
        switch result {
        case .absent: state = .signedOut
        case .logoutPending:
            // A durable marker prevents restoration, but deletion still has to succeed before reporting SignedOut.
            do { try await write(nil, revision: revision); try owns(revision); state = .signedOut }
            catch { try owns(revision); fail(.storage, state: .storageBlocked); throw Failure.storage }
        case .session(let value):
            emit(.sessionRestored)
            if let pending = value.pendingRefresh, pending.recoveryState == .pending {
                session = try replacing(value, pending: .init(sessionID: pending.sessionID, id: pending.id,
                    recoveryState: .recoveryPending, dispatchCount: pending.dispatchCount, retryNotBefore: pending.retryNotBefore))
            } else { session = value }
            presentSession()
        }
    }

    func login() async throws {
        guard attempt == nil, state != .restoring, state != .persistingCredentials, state != .storageBlocked else { throw Failure.busy }
        let revision = invalidate(discardSession: false)
        state = .starting
        try await withTaskCancellationHandler(operation: { try await login(revision: revision) }, onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.sessionRevision == revision else { return }
                try? await self.cancelAuthorization()
            }
        })
    }

    private func login(revision: UInt64) async throws {
        do {
            try Task.checkCancellation()
            let fresh = try makeAttempt()
            attempt = fresh
            emit(.startInitiated)
            let start = try await client.start(fresh.makeStartRequest())
            try owns(revision)
            emit(.startSucceeded)
            try Task.checkCancellation()
            let authorization = try fresh.prepareAuthorization(url: start.authorizationURL, transactionExpiresAt: start.transactionExpiresAt)
            try fresh.validateBeforeBrowserLaunch()
            state = .authorizing
            let callback = try await authorize(authorization, attempt: fresh, revision: revision)
            try owns(revision)
            try Task.checkCancellation()
            do { try fresh.receiveCallback(callback) }
            catch { emit(.callbackRejected); throw error }
            emit(.callbackValidated)
            if fresh.state == .denied { throw Failure.denied }
            let claim = try fresh.claimCompletion()
            state = .completing
            emit(.completeInitiated)
            let complete: WCAOAuthBrokerClient.CompleteResponse
            do { complete = try await client.complete(claim.request) }
            catch {
                try owns(revision)
                try? fresh.markCompletionOutcomeUnknown(claimID: claim.id)
                if case WCAOAuthBrokerClient.Failure.broker(let status, _, _, _) = error, (400..<500).contains(status) {
                    emit(.completeFailed)
                } else { emit(.completeOutcomeUnknown) }
                if case WCAOAuthBrokerClient.Failure.broker(410, _, _, _) = error { throw Failure.expired }
                throw Failure.completionUnknown
            }
            try owns(revision)
            try Task.checkCancellation()
            try fresh.confirmCompletion(claimID: claim.id)
            emit(.completeSucceeded)
            guard complete.tokenGeneration == 1, valid(complete.brokerSessionExpiresAt), valid(complete.wcaAccessTokenExpiresAt) else {
                throw Failure.expired
            }
            let value = try WCABrokerStoredSession(sessionID: complete.sessionID, brokerSessionToken: complete.brokerSessionToken,
                brokerSessionExpiresAt: complete.brokerSessionExpiresAt, wcaAccessToken: complete.wcaAccessToken,
                wcaAccessTokenExpiresAt: complete.wcaAccessTokenExpiresAt, tokenGeneration: complete.tokenGeneration)
            attempt = nil
            try await persistCredentials(value, login: true, revision: revision)
        } catch {
            try owns(revision)
            emit(state == .starting ? .startFailed : .authorizationFailed)
            attempt?.cancel(); attempt = nil
            cleanupBrowser(throwing: .cancelled)
            if state == .storageBlocked || state == .profilePending { throw sanitize(error) }
            let failure = sanitize(error)
            if failure == .cancelled || failure == .denied { presentSession() }
            else { state = .needsLogin }
            lastFailure = failure
            throw failure
        }
    }

    func cancelAuthorization() async throws {
        guard attempt != nil || (persistenceCandidate?.login == true) else { return }
        let oldSession = session
        let mayHaveWritten = persistenceCandidate != nil
        let revision = invalidate(discardSession: false)
        if mayHaveWritten {
            // An in-flight save may already have committed. Reconcile behind it, not with offsetting stale writes.
            do { try await write(oldSession, revision: revision) }
            catch { try owns(revision); fail(.storage, state: .storageBlocked); throw Failure.storage }
        }
        try owns(revision)
        presentSession()
        lastFailure = .cancelled
    }

    func retryPersistence() async throws {
        guard state == .storageBlocked, let candidate = persistenceCandidate else { throw Failure.noSession }
        try owns(candidate.revision)
        try await persistCredentials(candidate.value, login: candidate.login, revision: candidate.revision)
    }

    func retryProfile() async throws {
        guard let session else { throw Failure.noSession }
        try await acquireProfile(revision: sessionRevision, sessionID: session.sessionID)
    }

    func refresh() async throws {
        guard state == .ready || state == .profilePending || state == .needsLogin else { throw Failure.busy }
        guard let value = session else { throw Failure.noSession }
        guard valid(value.brokerSessionExpiresAt) else { fail(.expired, state: .needsLogin); throw Failure.expired }
        if value.pendingRefresh?.recoveryState == .uncertain { throw Failure.uncertain }
        if let flight = refreshFlight { return try await flight.task.value }
        let revision = sessionRevision, flightID = makeUUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { throw Failure.staleOperation }
            try await self.runRefresh(revision: revision, sessionID: value.sessionID)
        }
        refreshFlight = (flightID, task)
        defer { if sessionRevision == revision, refreshFlight?.id == flightID { refreshFlight = nil } }
        try await task.value
    }

    func accessCredential() async throws -> AccessCredential {
        guard state == .ready || state == .profilePending || state == .needsLogin else { throw Failure.busy }
        guard let current = session else { throw Failure.noSession }
        let revision = sessionRevision
        guard valid(current.brokerSessionExpiresAt) else { fail(.expired, state: .needsLogin); throw Failure.expired }
        if !valid(current.wcaAccessTokenExpiresAt) { try await refresh() }
        try owns(revision, sessionID: current.sessionID)
        guard let value = session, valid(value.wcaAccessTokenExpiresAt) else { throw Failure.recoveryRequired }
        return .init(token: value.wcaAccessToken, sessionID: value.sessionID, generation: value.tokenGeneration, revision: revision)
    }

    /// Phase 5 callers must retain their WCA-origin allowlist. Only a typed WCA token is exposed to this closure.
    func performAuthorized<Value: Sendable>(_ request: @escaping @Sendable (WCAOAuthBrokerClient.WCAAccessToken) async throws -> Value) async throws -> Value {
        let credential = try await accessCredential()
        do {
            let result = try await request(credential.token)
            try owns(credential.revision, sessionID: credential.sessionID)
            return result
        } catch WCARequestFailure.unauthorized {
            try owns(credential.revision, sessionID: credential.sessionID)
            emit(.wca401Handled)
            if !(session.map { $0.tokenGeneration > credential.generation && valid($0.wcaAccessTokenExpiresAt) } ?? false) {
                try await refresh()
            }
            try owns(credential.revision, sessionID: credential.sessionID)
            let newer = try await accessCredential()
            do {
                let result = try await request(newer.token)
                try owns(credential.revision, sessionID: credential.sessionID)
                return result
            } catch WCARequestFailure.unauthorized {
                try owns(credential.revision, sessionID: credential.sessionID)
                throw Failure.apiUnauthorized
            }
            catch { try owns(credential.revision, sessionID: credential.sessionID); throw Failure.apiFailure }
        } catch { try owns(credential.revision, sessionID: credential.sessionID); throw Failure.apiFailure }
    }

    func logout() async throws {
        let token = session?.brokerSessionToken ?? persistenceCandidate?.value.brokerSessionToken
        let revision = invalidate(discardSession: true)
        state = .persistingCredentials
        var localFailure = false
        do { try await write(nil, revision: revision); try owns(revision); state = .signedOut; emit(.logoutLocalCleared) }
        catch { try owns(revision); emit(.logoutStorageFailed); fail(.storage, state: .storageBlocked); localFailure = true }
        // The transport owns its request timeout. No retries, persistent revoke queue or WCA revocation claim.
        if let token {
            do { try await client.logout(sessionToken: token); try owns(revision); emit(.logoutRemoteConfirmed) }
            catch { try owns(revision); emit(.logoutRemoteFailed); if !localFailure { lastFailure = .brokerUnavailable } }
            try owns(revision)
        }
        if localFailure { throw Failure.storage }
    }

    private func runRefresh(revision: UInt64, sessionID: String) async throws {
        try owns(revision, sessionID: sessionID)
        guard let original = session else { throw Failure.noSession }
        var pending = original.pendingRefresh ?? .init(sessionID: sessionID, id: makeUUID(), recoveryState: .pending)
        if pending.recoveryState == .uncertain { throw Failure.uncertain }
        if pending.dispatchCount >= 2 { lastFailure = .recoveryRequired; throw Failure.recoveryRequired }
        if let deadline = pending.retryNotBefore, TimeInterval(deadline) > clock.now() {
            throw Failure.recoveryRequired
        }
        while pending.dispatchCount < 2 {
            try owns(revision, sessionID: sessionID)
            guard let current = session, valid(current.brokerSessionExpiresAt) else { throw Failure.expired }
            pending = .init(sessionID: sessionID, id: pending.id, recoveryState: .pending, dispatchCount: pending.dispatchCount + 1)
            let dispatchRecord = try replacing(current, pending: pending)
            do { try await write(dispatchRecord, revision: revision) }
            catch { try owns(revision, sessionID: sessionID); fail(.storage, state: .storageBlocked); throw Failure.storage }
            try owns(revision, sessionID: sessionID)
            guard valid(dispatchRecord.brokerSessionExpiresAt) else {
                fail(.expired, state: .needsLogin); throw Failure.expired
            }
            session = dispatchRecord; refreshStatus = .pending
            emit(.refreshStarted)
            let response: WCAOAuthBrokerClient.RefreshResponse
            do { response = try await client.refresh(sessionToken: current.brokerSessionToken, idempotencyKey: pending.id) }
            catch {
                try owns(revision, sessionID: sessionID)
                let policy = refreshFailure(error)
                let retryAt = policy.retryAfter.map { Int64(exactly: ceil(clock.now() + Double($0))) ?? Int64.max }
                pending = .init(sessionID: sessionID, id: pending.id,
                    recoveryState: policy.uncertain ? .uncertain : .recoveryPending,
                    dispatchCount: pending.dispatchCount, retryNotBefore: retryAt)
                let recovery = try replacing(dispatchRecord, pending: pending)
                session = recovery; refreshStatus = status(pending)
                do { try await write(recovery, revision: revision) }
                catch {
                    try owns(revision, sessionID: sessionID)
                    persistenceCandidate = (revision, recovery, false)
                    fail(.storage, state: .storageBlocked); throw Failure.storage
                }
                try owns(revision, sessionID: sessionID)
                session = recovery; refreshStatus = status(pending); lastFailure = policy.failure
                emit(policy.uncertain ? .refreshUncertain : .refreshFailed)
                if policy.uncertain || policy.terminal { state = .needsLogin; throw policy.failure }
                // At most ONE retry. Long Retry-After (contract: 60s) is retained, never waited out in a loop.
                guard policy.retry, pending.dispatchCount < 2, (policy.retryAfter ?? 0) <= 2 else { throw policy.failure }
                if let retryAt {
                    do { try await clock.wait(until: TimeInterval(retryAt)) }
                    catch { try owns(revision, sessionID: sessionID); throw Failure.recoveryRequired }
                }
                continue
            }
            try owns(revision, sessionID: sessionID)
            guard let latest = session, latest.pendingRefresh?.id == pending.id,
                  latest.pendingRefresh?.recoveryState != .uncertain, response.sessionID == sessionID else {
                throw Failure.staleOperation
            }
            if response.tokenGeneration < latest.tokenGeneration {
                try await retainRecovery(latest, pending: pending, revision: revision)
                throw Failure.recoveryRequired
            }
            if response.tokenGeneration == latest.tokenGeneration {
                guard response.wcaAccessToken.rawValue == latest.wcaAccessToken.rawValue,
                      response.wcaAccessTokenExpiresAt == latest.wcaAccessTokenExpiresAt else {
                    try await retainRecovery(latest, pending: pending, revision: revision, uncertain: true)
                    throw Failure.conflictingGeneration
                }
            }
            guard valid(response.wcaAccessTokenExpiresAt), valid(latest.brokerSessionExpiresAt) else {
                try await retainRecovery(latest, pending: pending, revision: revision)
                throw Failure.recoveryRequired
            }
            let updated = try WCABrokerStoredSession(sessionID: latest.sessionID, brokerSessionToken: latest.brokerSessionToken,
                brokerSessionExpiresAt: latest.brokerSessionExpiresAt, wcaAccessToken: response.wcaAccessToken,
                wcaAccessTokenExpiresAt: response.wcaAccessTokenExpiresAt, tokenGeneration: response.tokenGeneration)
            try await persistCredentials(updated, login: false, revision: revision)
            emit(.refreshRecovered)
            return
        }
    }

    private func retainRecovery(_ value: WCABrokerStoredSession, pending: WCABrokerStoredSession.PendingRefresh,
                                revision: UInt64, uncertain: Bool = false) async throws {
        let record = try replacing(value, pending: .init(sessionID: value.sessionID, id: pending.id,
            recoveryState: uncertain ? .uncertain : .recoveryPending, dispatchCount: pending.dispatchCount))
        session = record; refreshStatus = status(record.pendingRefresh)
        do { try await write(record, revision: revision) }
        catch {
            try owns(revision)
            persistenceCandidate = (revision, record, false)
            fail(.storage, state: .storageBlocked); throw Failure.storage
        }
        try owns(revision, sessionID: value.sessionID)
        session = record; refreshStatus = status(record.pendingRefresh)
        if uncertain { fail(.uncertain, state: .needsLogin) }
    }

    private func persistCredentials(_ value: WCABrokerStoredSession, login: Bool, revision: UInt64) async throws {
        try owns(revision)
        persistenceCandidate = (revision, value, login)
        if login { state = .persistingCredentials }
        do { try await write(value, revision: revision) }
        catch { try owns(revision); emit(.storageFailed); fail(.storage, state: .storageBlocked); throw Failure.storage }
        try owns(revision)
        session = value; persistenceCandidate = nil; refreshStatus = status(value.pendingRefresh); lastFailure = nil
        emit(.sessionPersisted)
        if login { profileReady = false }
        presentSession()
        if login { try await acquireProfile(revision: revision, sessionID: value.sessionID) }
    }

    private func acquireProfile(revision: UInt64, sessionID: String) async throws {
        try owns(revision, sessionID: sessionID)
        guard let profile else { profileReady = true; presentSession(); return }
        if let flight = profileFlight, flight.revision == revision { return try await flight.task.value }
        let task = Task { @MainActor [weak self] in
            guard let self else { throw Failure.staleOperation }
            try await self.runProfile(profile, revision: revision, sessionID: sessionID)
        }
        profileFlight = (revision, task)
        defer { if profileFlight?.revision == revision { profileFlight = nil } }
        try await task.value
    }

    private func runProfile(_ profile: any WCABrokerProfileProvider, revision: UInt64, sessionID: String) async throws {
        try owns(revision, sessionID: sessionID)
        isLoadingProfile = true
        defer { if sessionRevision == revision { isLoadingProfile = false } }
        state = .profilePending
        do {
            let credential = try await accessCredential()
            try await profile.fetchProfile(accessToken: credential.token)
            try owns(revision, sessionID: sessionID)
            emit(.profileLoaded)
            profileReady = true; presentSession(); lastFailure = nil
        } catch {
            try owns(revision, sessionID: sessionID)
            emit(.profileFailed)
            if state != .storageBlocked && state != .needsLogin { fail(.profileUnavailable, state: .profilePending) }
            throw state == .storageBlocked ? Failure.storage : Failure.profileUnavailable
        }
    }

    /// Serialize write ORDER in addition to store actor isolation. Logout clear follows any already-dispatched save.
    private func write(_ value: WCABrokerStoredSession?, revision: UInt64) async throws {
        let previous = writeTail, store = self.store
        let operation = Task { @MainActor [weak self] () -> Result<Void, Failure> in
            await previous?.value
            guard let self, self.sessionRevision == revision else { return .failure(.staleOperation) }
            do {
                if let value { try await store.save(value) } else { try await store.clear() }
            } catch { return .failure(.storage) }
            guard self.sessionRevision == revision else { return .failure(.staleOperation) }
            return .success(())
        }
        writeTail = Task { _ = await operation.value }
        try await operation.value.get()
    }

    private func authorize(_ value: WCABrokerOAuthAttempt.Authorization, attempt: WCABrokerOAuthAttempt,
                           revision: UInt64) async throws -> URL {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                browserContinuation = continuation
                let newBrowser = browserFactory.make(url: value.url, callbackScheme: "cubeflow-wca") { [weak self] result in
                    guard let self, self.sessionRevision == revision, self.attempt?.id == attempt.id else { return }
                    self.finishBrowser(result)
                }
                browser = newBrowser
                guard newBrowser.start() else { cleanupBrowser(throwing: .browserUnavailable); return }
                emit(.browserOpened)
                guard browserContinuation != nil else { return }
                browserDeadline = Task { @MainActor [weak self] in
                    guard let self else { return }
                    do { try await self.clock.wait(until: Double(value.transactionExpiresAt) - self.expiryMargin) }
                    catch { return }
                    guard self.sessionRevision == revision, self.attempt?.id == attempt.id else { return }
                    self.cleanupBrowser(throwing: .expired)
                }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.sessionRevision == revision else { return }
                self.cleanupBrowser(throwing: .cancelled)
            }
        })
    }

    private func finishBrowser(_ result: Result<URL, WCABrokerBrowserFailure>) {
        guard let continuation = browserContinuation else { return }
        browserContinuation = nil
        browserDeadline?.cancel(); browserDeadline = nil
        browser = nil
        switch result {
        case .success(let url): emit(.browserCompleted); continuation.resume(returning: url)
        case .failure(let failure):
            let error: Failure = failure == .cancelled ? .cancelled : (failure == .expired ? .expired : .browserUnavailable)
            emit(error == .cancelled ? .browserCancelled : (error == .expired ? .browserExpired : .browserUnavailable))
            continuation.resume(throwing: error)
        }
    }

    private func cleanupBrowser(throwing failure: Failure) {
        let continuation = browserContinuation; browserContinuation = nil
        if continuation != nil {
            emit(failure == .expired ? .browserExpired : (failure == .browserUnavailable ? .browserUnavailable : .browserCancelled))
        }
        browserDeadline?.cancel(); browserDeadline = nil
        let old = browser; browser = nil
        old?.cancel()
        continuation?.resume(throwing: failure)
    }

    @discardableResult private func invalidate(discardSession: Bool) -> UInt64 {
        sessionRevision += 1
        isLoadingProfile = false
        attempt?.cancel(); attempt = nil
        cleanupBrowser(throwing: .cancelled)
        refreshFlight?.task.cancel(); refreshFlight = nil
        profileFlight?.task.cancel(); profileFlight = nil
        if let current = session, let pending = current.pendingRefresh, pending.recoveryState == .pending {
            if let recovery = try? replacing(current, pending: .init(sessionID: pending.sessionID, id: pending.id,
                recoveryState: .recoveryPending, dispatchCount: pending.dispatchCount, retryNotBefore: pending.retryNotBefore)) {
                session = recovery
            }
        }
        persistenceCandidate = nil; lastFailure = nil
        if discardSession { session = nil; profileReady = false; refreshStatus = .idle }
        return sessionRevision
    }

    private func owns(_ revision: UInt64, sessionID: String? = nil) throws {
        guard revision == sessionRevision, sessionID == nil || session?.sessionID == sessionID else { throw Failure.staleOperation }
    }

    private func valid(_ expiry: Int64) -> Bool {
        let now = clock.now()
        return now.isFinite && Double(expiry) > now + expiryMargin
    }

    private func presentSession() {
        guard let session else { state = .signedOut; refreshStatus = .idle; return }
        refreshStatus = status(session.pendingRefresh)
        if !valid(session.brokerSessionExpiresAt) || !valid(session.wcaAccessTokenExpiresAt) { state = .needsLogin }
        else { state = profile == nil || profileReady ? .ready : .profilePending }
    }

    private func status(_ pending: WCABrokerStoredSession.PendingRefresh?) -> RefreshStatus {
        switch pending?.recoveryState {
        case nil: return .idle
        case .pending: return .pending
        case .recoveryPending: return .recoveryPending
        case .uncertain: return .uncertain
        }
    }

    private func replacing(_ value: WCABrokerStoredSession, pending: WCABrokerStoredSession.PendingRefresh?) throws -> WCABrokerStoredSession {
        try .init(sessionID: value.sessionID, brokerSessionToken: value.brokerSessionToken,
                  brokerSessionExpiresAt: value.brokerSessionExpiresAt, wcaAccessToken: value.wcaAccessToken,
                  wcaAccessTokenExpiresAt: value.wcaAccessTokenExpiresAt, tokenGeneration: value.tokenGeneration, pendingRefresh: pending)
    }

    private func fail(_ failure: Failure, state: State) { lastFailure = failure; self.state = state }

    private func emit(_ event: DiagnosticEvent) {
        #if DEBUG
        diagnostics?(event)
        #endif
    }

    private func sanitize(_ error: Error) -> Failure {
        if let failure = error as? Failure { return failure }
        if error is CancellationError { return .cancelled }
        if let failure = error as? WCABrokerOAuthAttempt.Failure {
            return failure == .expired || failure == .invalidClock || failure == .invalidTransaction ? .expired : .invalidCallback
        }
        return .brokerUnavailable
    }

    private func refreshFailure(_ error: Error) -> (failure: Failure, uncertain: Bool, terminal: Bool, retry: Bool, retryAfter: Int?) {
        guard let failure = error as? WCAOAuthBrokerClient.Failure else {
            return (.recoveryRequired, false, false, !(error is CancellationError), nil)
        }
        switch failure {
        case .broker(502, .providerUnavailable, _, _): return (.uncertain, true, true, false, nil)
        case .broker(401, _, _, _): return (.sessionInvalid, true, true, false, nil)
        case .broker(let status, _, _, let retry), .http(let status, let retry):
            return (.recoveryRequired, false, false, status == 429 ? retry != nil : [502, 503].contains(status), retry)
        case .transport(.cancelled): return (.recoveryRequired, false, false, false, nil)
        case .transport, .malformedResponse, .redirectRejected: return (.recoveryRequired, false, false, true, nil)
        case .invalidRequest: return (.recoveryRequired, false, false, false, nil)
        }
    }
}

#if canImport(UIKit)
/// Isolated Phase 5 adapter. The caller must supply a live, retained presentation-context provider.
@MainActor final class WCABrokerSystemBrowserFactory: WCABrokerBrowserFactory {
    private let provider: any ASWebAuthenticationPresentationContextProviding
    init(provider: any ASWebAuthenticationPresentationContextProviding) { self.provider = provider }
    func make(url: URL, callbackScheme: String,
              completion: @escaping @MainActor (Result<URL, WCABrokerBrowserFailure>) -> Void) -> any WCABrokerBrowserSession {
        WCABrokerSystemBrowser(url: url, scheme: callbackScheme, provider: provider, completion: completion)
    }
}

@MainActor private final class WCABrokerSystemBrowser: WCABrokerBrowserSession {
    private let provider: any ASWebAuthenticationPresentationContextProviding
    private let session: ASWebAuthenticationSession
    init(url: URL, scheme: String, provider: any ASWebAuthenticationPresentationContextProviding,
         completion: @escaping @MainActor (Result<URL, WCABrokerBrowserFailure>) -> Void) {
        self.provider = provider
        session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { url, error in
            let result: Result<URL, WCABrokerBrowserFailure>
            if let url, error == nil { result = .success(url) }
            else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { result = .failure(.cancelled) }
            else { result = .failure(.unavailable) }
            Task { @MainActor in completion(result) }
        }
        session.presentationContextProvider = provider
    }
    func start() -> Bool { session.start() }
    func cancel() { session.cancel() }
}
#endif

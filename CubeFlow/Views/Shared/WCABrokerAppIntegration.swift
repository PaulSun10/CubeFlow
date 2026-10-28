import Foundation

nonisolated enum WCAAuthenticationMode { case mock, broker }

/// Broker is the sole shipping provider. Mock injection is available only to DEBUG tests.
nonisolated enum WCAAuthenticationConfiguration {
    static var mode: WCAAuthenticationMode {
        #if DEBUG && CUBEFLOW_WCA_BROKER_MOCK
        return .mock
        #else
        return .broker
        #endif
    }
}

import Combine
#if canImport(UIKit)
import AuthenticationServices
import UIKit
#endif

/// No implicit defaults: Mock injection and explicit real-mode assembly remain distinct call sites.
@MainActor struct WCABrokerAppDependencies {
    let client: any WCABrokerClientOperations
    let store: any WCABrokerSessionPersistence
    let browser: any WCABrokerBrowserFactory
    let clock: any WCABrokerCoordinatorClock
    let attempt: @MainActor () throws -> WCABrokerOAuthAttempt
    let request: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    var diagnostics: (@MainActor (WCABrokerAuthCoordinator.DiagnosticEvent) -> Void)? = nil
    var restoreProfile = false
    var profileCache: WCABrokerProfileCache? = nil
}
#if DEBUG
typealias WCABrokerMockDependencies = WCABrokerAppDependencies
#endif

/// Public profile data only, bound to the Keychain-restored Broker session, never the legacy cache.
/// One replaceable entry bounds storage; a new authorization cannot inherit another session's profile.
@MainActor final class WCABrokerProfileCache {
    private struct Entry: Codable {
        let version: Int
        let sessionID: String
        let profile: WCAUserProfile
    }
    private let defaults: UserDefaults
    private let key = "wca_broker_profile_v1"
    init(defaults: UserDefaults) { self.defaults = defaults }
    func load(sessionID: String) -> WCAUserProfile? {
        guard let data = defaults.data(forKey: key),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.version == 1, entry.sessionID == sessionID else { return nil }
        return entry.profile
    }
    func save(_ profile: WCAUserProfile, sessionID: String) {
        guard let data = try? JSONEncoder().encode(Entry(version: 1, sessionID: sessionID, profile: profile)) else { return }
        defaults.set(data, forKey: key)
    }
    func clear() { defaults.removeObject(forKey: key) }
}

#if DEBUG
@MainActor enum WCABrokerMockEnvironment {
    // Must be explicitly supplied by a controlled development harness before shared-manager creation.
    // Missing configuration fails closed; it never selects a real transport or the legacy provider.
    static var makeIntegration: (() -> WCABrokerAppIntegration)?
}
#endif

nonisolated struct WCABrokerAccountPresentation: Equatable {
    let phase: WCABrokerAuthCoordinator.State
    let refresh: WCABrokerAuthCoordinator.RefreshStatus
    let hasSession: Bool
    var loadingProfile = false

    var busy: Bool {
        loadingProfile || [.restoring, .starting, .authorizing, .completing, .persistingCredentials].contains(phase)
    }
    /// No redundant signed-in row, and no failure notice while initial acquisition is pending.
    var notice: String? {
        if (phase == .ready && refresh == .idle) || loadingProfile || phase == .restoring { return nil }
        return message
    }
    var accountVisible: Bool { hasSession || phase == .storageBlocked || phase == .profilePending }
    // Restoration is not a signed-out verdict, nor evidence of an authenticated account.
    var showsAccountRow: Bool { accountVisible || phase == .restoring }
    var showsProfileLoading: Bool { loadingProfile || phase == .restoring }
    var message: String {
        if phase == .storageBlocked { return "Sign-in storage is unavailable or could not be updated. Please try again." }
        if phase == .needsLogin || refresh == .uncertain { return "Please sign in again to continue." }
        if refresh == .recoveryPending { return "The connection is unavailable. Recovery is pending." }
        switch phase {
        case .signedOut: return "Not signed in"
        case .restoring: return "Restoring sign-in…"
        case .starting, .authorizing: return "Signing in…"
        case .completing, .persistingCredentials: return "Finishing sign-in…"
        case .profilePending: return "Signed in. Profile information is unavailable; please retry."
        case .ready: return "Signed in"
        case .needsLogin, .storageBlocked: return "Sign-in is unavailable."
        }
    }
}

@MainActor private final class WCABrokerAppProfileProvider: WCABrokerProfileProvider {
    var acquire: (() async throws -> Void)?
    func fetchProfile(accessToken: WCAOAuthBrokerClient.WCAAccessToken) async throws {
        guard let acquire else { throw WCABrokerAuthCoordinator.Failure.profileUnavailable }
        try await acquire()
    }
}

/// Not a second ObservableObject: WCAAuthManager remains the only UI-facing authentication owner.
@MainActor final class WCABrokerAppIntegration {
    let coordinator: WCABrokerAuthCoordinator
    private let request: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let restoreProfile: Bool
    private let profileCache: WCABrokerProfileCache?
    private var subscriptions: Set<AnyCancellable> = []
    private var phase: WCABrokerAuthCoordinator.State = .signedOut
    private var refresh: WCABrokerAuthCoordinator.RefreshStatus = .idle
    private var profileLoading = false
    private var profileFailure: WCABrokerAuthCoordinator.Failure?
    private var stagedProfile: (revision: UInt64, profile: WCAUserProfile)?
    private var restoreFlight: Task<Void, Error>?
    private var restored = false
    private var lifecycleEpoch: UInt64 = 0
    private var logoutPending = false
    var onChange: (() -> Void)?

    init(_ dependencies: WCABrokerAppDependencies) {
        let provider = WCABrokerAppProfileProvider()
        coordinator = WCABrokerAuthCoordinator(client: dependencies.client, store: dependencies.store,
            browserFactory: dependencies.browser, clock: dependencies.clock, makeAttempt: dependencies.attempt,
            profile: provider, diagnostics: dependencies.diagnostics)
        request = dependencies.request
        restoreProfile = dependencies.restoreProfile
        profileCache = dependencies.profileCache
        provider.acquire = { [weak self] in
            guard let self else { throw WCABrokerAuthCoordinator.Failure.staleOperation }
            try await self.acquireProfile()
        }
        coordinator.$state.sink { [weak self] value in
            guard let self else { return }
            self.phase = value
            if self.stagedProfile?.revision != self.coordinator.sessionRevision { self.stagedProfile = nil }
            if value == .ready || value == .profilePending, let id = self.coordinator.profileCacheSessionID {
                if let staged = self.stagedProfile {
                    if value == .ready { self.profileCache?.save(staged.profile, sessionID: id) }
                } else if let cached = self.profileCache?.load(sessionID: id) {
                    self.stagedProfile = (self.coordinator.sessionRevision, cached)
                }
            }
            self.onChange?()
        }.store(in: &subscriptions)
        coordinator.$isLoadingProfile.sink { [weak self] value in
            self?.profileLoading = value
            self?.onChange?()
        }.store(in: &subscriptions)
        coordinator.$lastFailure.sink { [weak self] value in
            self?.profileFailure = value
            self?.onChange?()
        }.store(in: &subscriptions)
        if restoreProfile { phase = .restoring }
        coordinator.$refreshStatus.sink { [weak self] value in
            self?.refresh = value
            self?.onChange?()
        }.store(in: &subscriptions)
    }

    var presentation: WCABrokerAccountPresentation {
        .init(phase: phase, refresh: refresh, hasSession: coordinator.hasPersistedSession,
              loadingProfile: profileLoading || (restoreProfile && restoreFlight != nil && phase == .profilePending && profileFailure == nil))
    }
    var profile: WCAUserProfile? {
        guard stagedProfile?.revision == coordinator.sessionRevision, phase == .ready || phase == .profilePending else { return nil }
        return stagedProfile?.profile
    }

    func restoreOnce(force: Bool = false) async throws {
        if let restoreFlight { return try await restoreFlight.value }
        if restored && !force { return }
        let epoch = lifecycleEpoch
        let task = Task { @MainActor in
            guard lifecycleEpoch == epoch, !Task.isCancelled else { throw WCABrokerAuthCoordinator.Failure.staleOperation }
            try await coordinator.restore()
            // Cached identity is hydrated by the session publication before any network acquisition.
            if restoreProfile, coordinator.hasPersistedSession, coordinator.state != .storageBlocked {
                try await coordinator.retryProfile()
            }
        }
        restoreFlight = task
        defer { if lifecycleEpoch == epoch { restoreFlight = nil; restored = true } }
        try await task.value
    }

    private func supersedeRestoration() {
        lifecycleEpoch += 1
        restoreFlight?.cancel(); restoreFlight = nil
        restored = true
    }
    func signIn() async throws {
        guard [.signedOut, .ready, .profilePending, .needsLogin].contains(phase) else { throw WCABrokerAuthCoordinator.Failure.busy }
        supersedeRestoration()
        logoutPending = false
        try await coordinator.login()
    }
    func refreshProfile() async throws { try await coordinator.retryProfile() }
    func accountAction() async throws {
        if phase == .storageBlocked {
            if logoutPending { try await logout() }
            else if coordinator.canRetryPersistence { try await coordinator.retryPersistence() }
            else { try await restoreOnce(force: true) }
        } else if phase == .signedOut || phase == .needsLogin || refresh == .uncertain { try await signIn() }
        else { try await refreshProfile() }
    }

    func logout() async throws {
        supersedeRestoration()
        let epoch = lifecycleEpoch
        logoutPending = true
        stagedProfile = nil
        profileCache?.clear()
        onChange?()
        try await coordinator.logout()
        guard lifecycleEpoch == epoch else { throw WCABrokerAuthCoordinator.Failure.staleOperation }
        logoutPending = false
    }

    func authorizedRequest(for url: URL) async throws -> URLRequest {
        guard Self.permits(url) else { throw WCABrokerAuthCoordinator.Failure.apiFailure }
        let credential = try await coordinator.accessCredential()
        return Self.authorized(url, token: credential.token)
    }

    func data(for url: URL) async throws -> (Data, URLResponse) {
        guard Self.permits(url) else { throw WCABrokerAuthCoordinator.Failure.apiFailure }
        let transport = request
        return try await coordinator.performAuthorized { token in
            let result = try await transport(Self.authorized(url, token: token))
            guard let response = result.1 as? HTTPURLResponse, let finalURL = response.url,
                  Self.permits(finalURL), finalURL == url else { throw WCABrokerAuthCoordinator.Failure.apiFailure }
            if response.statusCode == 401 { throw WCABrokerAuthCoordinator.WCARequestFailure.unauthorized }
            guard (200..<300).contains(response.statusCode) else { throw WCABrokerAuthCoordinator.Failure.apiFailure }
            return result
        }
    }

    private func acquireProfile() async throws {
        let credential = try await coordinator.accessCredential()
        let result = try await data(for: URL(string: "https://www.worldcubeassociation.org/api/v0/me")!)
        let decoded = try WCAAuthManager.decodeProfileData(result.0)
        guard credential.revision == coordinator.sessionRevision else { throw WCABrokerAuthCoordinator.Failure.staleOperation }
        // Stage only. The owner publishes Ready after its own revision validation before the manager exposes this data.
        stagedProfile = (credential.revision, decoded)
    }

    nonisolated private static func permits(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return c.scheme == "https" && c.host?.lowercased() == "www.worldcubeassociation.org"
            && (c.port == nil || c.port == 443) && c.user == nil && c.password == nil
            && c.fragment == nil && c.percentEncodedPath.hasPrefix("/api/v0/")
    }
    nonisolated private static func authorized(_ url: URL, token: WCAOAuthBrokerClient.WCAAccessToken) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer " + token.rawValue, forHTTPHeaderField: "Authorization")
        return request
    }
}

/// Pure selection policy shared by native selection and Mock tests; ambiguity is rejected, not resolved by array order.
nonisolated enum WCABrokerAnchorSelection {
    struct Candidate {
        let id: String
        let active: Bool
        let key: Bool
        let visible: Bool
        let normalLevel: Bool
    }
    static func choose(_ candidates: [Candidate]) -> String? {
        let eligible = candidates.filter { $0.active && $0.key && $0.visible && $0.normalLevel }
        return eligible.count == 1 ? eligible[0].id : nil
    }
}

#if canImport(UIKit)
/// Prepared only on an explicit sign-in. No empty window, arbitrary first scene, or fatalError fallback.
@MainActor final class WCABrokerSceneBrowserFactory: WCABrokerBrowserFactory {
    func make(url: URL, callbackScheme: String,
              completion: @escaping @MainActor (Result<URL, WCABrokerBrowserFailure>) -> Void) -> any WCABrokerBrowserSession {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        let candidates = windows.map { window in WCABrokerAnchorSelection.Candidate(
            id: String(describing: ObjectIdentifier(window)), active: window.windowScene?.activationState == .foregroundActive,
            key: window.isKeyWindow, visible: !window.isHidden && window.alpha > 0, normalLevel: window.windowLevel == .normal) }
        guard let id = WCABrokerAnchorSelection.choose(candidates),
              let window = windows.first(where: { String(describing: ObjectIdentifier($0)) == id }) else {
            return WCABrokerUnavailableBrowser()
        }
        let provider = WCABrokerWindowAnchor(window)
        let native = WCABrokerSystemBrowserFactory(provider: provider).make(url: url, callbackScheme: callbackScheme, completion: completion)
        return WCABrokerAnchoredBrowser(window: window, native: native)
    }
}
@MainActor private final class WCABrokerWindowAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    let window: UIWindow
    init(_ window: UIWindow) { self.window = window }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }
}
@MainActor private final class WCABrokerAnchoredBrowser: WCABrokerBrowserSession {
    let window: UIWindow
    let native: any WCABrokerBrowserSession
    init(window: UIWindow, native: any WCABrokerBrowserSession) { self.window = window; self.native = native }
    func start() -> Bool {
        guard window.windowScene?.activationState == .foregroundActive, window.isKeyWindow, !window.isHidden else { return false }
        return native.start()
    }
    func cancel() { native.cancel() }
}
@MainActor private final class WCABrokerUnavailableBrowser: WCABrokerBrowserSession {
    func start() -> Bool { false }
    func cancel() {}
}
#endif

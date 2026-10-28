import Foundation

/// Production Broker assembly. Constructors perform no requests or Keychain reads.
@MainActor enum WCABrokerRealEnvironment {
    static func dependencies() -> WCABrokerAppDependencies {
        let api = WCABrokerWCAAPITransport()
        #if canImport(UIKit)
        let browser: any WCABrokerBrowserFactory = WCABrokerSceneBrowserFactory()
        #else
        let browser: any WCABrokerBrowserFactory = WCABrokerNoNativeBrowserFactory()
        #endif
        #if DEBUG
        let diagnostics: (@MainActor (WCABrokerAuthCoordinator.DiagnosticEvent) -> Void)? = { event in
            // Only fixed events, never URLs, errors, headers, bodies or IDs.
            print("[CubeFlow WCA Broker] \(event.rawValue)")
        }
        #else
        let diagnostics: (@MainActor (WCABrokerAuthCoordinator.DiagnosticEvent) -> Void)? = nil
        #endif
        return .init(client: WCAOAuthBrokerClient(transport: WCAOAuthBrokerURLSessionTransport()),
            store: WCABrokerSessionStore(keychain: WCABrokerSystemKeychain()), browser: browser,
            clock: WCABrokerCoordinatorSystemClock(), attempt: { try WCABrokerOAuthAttempt() },
            request: { try await api.data(for: $0) }, diagnostics: diagnostics,
            restoreProfile: true, profileCache: WCABrokerProfileCache(defaults: .standard))
    }
    static func makeIntegration() -> WCABrokerAppIntegration {
        let values = dependencies()
        #if DEBUG
        values.diagnostics?(.realTestMode)
        #endif
        return WCABrokerAppIntegration(values)
    }
}

/// WCA bearer transport is intentionally separate from Broker bearer transport; every redirect is rejected.
nonisolated final class WCABrokerWCAAPITransport: @unchecked Sendable {
    private let session: URLSession
    init() {
        session = URLSession(configuration: WCAOAuthBrokerURLSessionTransport.configuration(),
                             delegate: WCAOAuthBrokerRedirectDelegate(), delegateQueue: nil)
    }
    static func permits(_ request: URLRequest) -> Bool {
        guard request.httpMethod == "GET", request.httpBody == nil,
              let url = request.url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return c.scheme == "https" && c.host?.lowercased() == "www.worldcubeassociation.org"
            && (c.port == nil || c.port == 443) && c.user == nil && c.password == nil
            && c.fragment == nil && c.percentEncodedPath.hasPrefix("/api/v0/")
    }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard Self.permits(request) else { throw WCABrokerAuthCoordinator.Failure.apiFailure }
        let result: (Data, URLResponse)
        do { result = try await session.data(for: request) }
        catch { throw WCABrokerAuthCoordinator.Failure.apiFailure }
        guard let response = result.1 as? HTTPURLResponse, response.url == request.url,
              !(300..<400).contains(response.statusCode) else { throw WCABrokerAuthCoordinator.Failure.apiFailure }
        // Keep 401 intact for the Coordinator's bounded recovery, never refresh WCA directly here.
        return result
    }
    deinit { session.invalidateAndCancel() }
}

#if !canImport(UIKit)
@MainActor private final class WCABrokerNoNativeBrowserFactory: WCABrokerBrowserFactory {
    func make(url: URL, callbackScheme: String,
              completion: @escaping @MainActor (Result<URL, WCABrokerBrowserFailure>) -> Void) -> any WCABrokerBrowserSession {
        WCABrokerNoNativeBrowser()
    }
}
@MainActor private final class WCABrokerNoNativeBrowser: WCABrokerBrowserSession {
    func start() -> Bool { false }
    func cancel() {}
}
#endif

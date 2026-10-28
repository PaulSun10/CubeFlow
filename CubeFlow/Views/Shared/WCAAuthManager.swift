import Foundation
import Combine

/// The Broker is the sole WCA authentication owner. Construction never reads persistence or starts OAuth.
@MainActor
final class WCAAuthManager: NSObject, ObservableObject {
    static let shared = WCAAuthManager()

    @Published private(set) var profile: WCAUserProfile?
    @Published private(set) var isSigningIn = false
    @Published private(set) var brokerPresentation: WCABrokerAccountPresentation?
    private let brokerIntegration: WCABrokerAppIntegration?

    var usesBrokerIntegration: Bool { true }
    var brokerPublicationRevision: UInt64? { brokerIntegration?.coordinator.sessionRevision }
    var isSignedIn: Bool { brokerPresentation?.accountVisible == true }

    private override init() {
        #if DEBUG && CUBEFLOW_WCA_BROKER_MOCK
        brokerIntegration = WCABrokerMockEnvironment.makeIntegration?()
        #else
        brokerIntegration = WCABrokerRealEnvironment.makeIntegration()
        #endif
        super.init()
        bindBrokerIntegration()
    }

    func signIn() async throws { try await requiredBroker().signIn() }
    func refreshProfile() async throws { try await requiredBroker().refreshProfile() }
    func authorizedRequest(for url: URL) async throws -> URLRequest {
        try await requiredBroker().authorizedRequest(for: url)
    }
    func authenticatedData(for url: URL) async throws -> (Data, URLResponse) {
        try await requiredBroker().data(for: url)
    }
    func signOut() {
        Task { @MainActor [weak self] in try? await self?.brokerSignOut() }
    }

    private func requiredBroker() throws -> WCABrokerAppIntegration {
        guard let brokerIntegration else { throw WCABrokerAuthCoordinator.Failure.storage }
        return brokerIntegration
    }
    private func bindBrokerIntegration() {
        brokerIntegration?.onChange = { [weak self] in self?.applyBrokerPresentation() }
        applyBrokerPresentation()
    }
    private func applyBrokerPresentation() {
        brokerPresentation = brokerIntegration?.presentation ?? .init(phase: .storageBlocked, refresh: .idle, hasSession: false)
        profile = brokerIntegration?.profile
        isSigningIn = brokerPresentation?.busy == true
    }
    func restoreBrokerSessionIfNeeded() async {
        try? await brokerIntegration?.restoreOnce()
    }
    func performBrokerAccountAction() async throws { try await requiredBroker().accountAction() }
    @discardableResult func brokerSignOut() async throws -> UInt64 {
        let integration = try requiredBroker()
        let expected = integration.coordinator.sessionRevision + 1
        try await integration.logout()
        guard integration.coordinator.sessionRevision == expected else { throw WCABrokerAuthCoordinator.Failure.staleOperation }
        return expected
    }

    #if DEBUG
    static func debugDefaultManagerWithoutPersistence() -> WCAAuthManager { WCAAuthManager() }
    #if CUBEFLOW_WCA_BROKER_MOCK
    static func debugBrokerManager(_ integration: WCABrokerAppIntegration) -> WCAAuthManager {
        WCAAuthManager(mockBroker: integration)
    }
    private init(mockBroker: WCABrokerAppIntegration) {
        brokerIntegration = mockBroker
        super.init()
        bindBrokerIntegration()
    }
    #endif
    #endif

    static func decodeProfileData(_ data: Data) throws -> WCAUserProfile {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(WCAProfileEnvelope.self, from: data)
        guard let payload = envelope.me ?? envelope.user else {
            throw WCAAuthError.invalidProfileResponse
        }

        return WCAUserProfile(
            id: payload.id,
            name: payload.name,
            wcaId: payload.wcaId,
            email: payload.email,
            avatarURL: payload.avatar?.thumbUrl ?? payload.avatar?.url,
            avatarIsDefault: payload.avatar?.isDefault
        )
    }

}

struct WCAUserProfile: Codable {
    let id: Int?
    let name: String
    let wcaId: String?
    let email: String?
    let avatarURL: String?
    let avatarIsDefault: Bool?

    var displayName: String {
        name.isEmpty ? "WCA" : name
    }

    var secondaryText: String {
        if let wcaId, !wcaId.isEmpty {
            return wcaId
        }
        if let email, !email.isEmpty {
            return email
        }
        return currentAppLocalizedString("settings.wca_title")
    }
}

private struct WCAProfileEnvelope: Decodable {
    let me: WCAProfilePayload?
    let user: WCAProfilePayload?
}

private struct WCAProfilePayload: Decodable {
    let id: Int?
    let name: String
    let wcaId: String?
    let email: String?
    let avatar: WCAAvatarPayload?
}

private struct WCAAvatarPayload: Decodable {
    let url: String?
    let thumbUrl: String?
    let isDefault: Bool?
}

/// Shared profile decoding failure; independent of OAuth grant/token exchange errors.
enum WCAAuthError: LocalizedError {
    case invalidProfileResponse
    var errorDescription: String? { currentAppLocalizedString("settings.wca_error_profile_response") }
}

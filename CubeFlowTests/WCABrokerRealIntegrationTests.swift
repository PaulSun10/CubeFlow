import Foundation
import XCTest
@testable import CubeFlow

@MainActor final class WCABrokerRealIntegrationTests: XCTestCase {
    #if !DEBUG
    func testShippingManagerStartsWithBrokerRestoration() async throws {
        // Construction is inert: do not restore, read Keychain or send any request.
        let manager = WCAAuthManager.shared
        XCTAssertTrue(manager.usesBrokerIntegration)
        XCTAssertEqual(manager.brokerPresentation?.phase, .restoring)
        XCTAssertEqual(manager.brokerPresentation?.showsAccountRow, true)
        XCTAssertEqual(manager.brokerPresentation?.showsProfileLoading, true)
        XCTAssertFalse(manager.isSignedIn)
        XCTAssertNil(manager.profile)
    }
    #endif

    func testGateHasExactlyOneSelectedMode() async throws {
        #if DEBUG && CUBEFLOW_WCA_BROKER_MOCK
        XCTAssertTrue(WCAAuthenticationConfiguration.mode == .mock)
        #else
        XCTAssertTrue(WCAAuthenticationConfiguration.mode == .broker)
        #endif
    }

    func testRealAssemblyUsesConcreteClientStoreAndSecureAttemptWithoutIO() async throws {
        let dependencies = WCABrokerRealEnvironment.dependencies()
        XCTAssertTrue(dependencies.client is WCAOAuthBrokerClient)
        XCTAssertTrue(dependencies.store is WCABrokerSessionStore)
        XCTAssertTrue(dependencies.restoreProfile)
        #if DEBUG
        XCTAssertNotNil(dependencies.diagnostics)
        #else
        XCTAssertNil(dependencies.diagnostics)
        #endif
        let attempt = try dependencies.attempt()
        XCTAssertEqual(attempt.state, .prepared)
        // Do not call start/restore/request on these real dependencies during automated tests.
        #if canImport(UIKit)
        XCTAssertTrue(dependencies.browser is WCABrokerSceneBrowserFactory)
        #endif
    }

    func testWCAOnlyTransportRejectsBrokerOriginsUnsafePathsAndWrites() async throws {
        for url in ["https://api.cubeflow.com.cn/v1/oauth/wca/refresh", "https://attacker.invalid/api/v0/me",
                    "http://www.worldcubeassociation.org/api/v0/me", "https://www.worldcubeassociation.org/oauth/token",
                    "https://user@www.worldcubeassociation.org/api/v0/me", "https://www.worldcubeassociation.org:444/api/v0/me"] {
            XCTAssertFalse(WCABrokerWCAAPITransport.permits(URLRequest(url: URL(string: url)!)))
        }
        var request = URLRequest(url: URL(string: "https://www.worldcubeassociation.org/api/v0/me")!)
        XCTAssertTrue(WCABrokerWCAAPITransport.permits(request))
        request.httpMethod = "POST"
        XCTAssertFalse(WCABrokerWCAAPITransport.permits(request))
    }

    func testActualWCAOnlyTransportRejectsUnsafeDestinationBeforeNetworking() async throws {
        let transport = WCABrokerWCAAPITransport()
        do {
            _ = try await transport.data(for: URLRequest(url: URL(string: "https://invalid.example/api/v0/me")!))
            XCTFail("Unsafe destination accepted")
        } catch let failure as WCABrokerAuthCoordinator.Failure { XCTAssertEqual(failure, .apiFailure) }
    }

    func testCallbackRegistrationAndAttemptContractAgree() async throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Config/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let types = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertEqual(schemes.filter { $0 == "cubeflow-wca" }.count, 1)
        let expected = WCABrokerOAuthAttempt.URLExpectations()
        XCTAssertEqual(expected.callbackScheme, "cubeflow-wca")
        XCTAssertEqual(expected.callbackHost, "oauth")
        XCTAssertEqual(expected.callbackPath, "/callback")
    }

    func testSharedRedirectDelegateRejectsRedirectWithoutResumingAnyTask() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://www.worldcubeassociation.org/api/v0/me")!
        let task = session.dataTask(with: url) // Never resumed.
        let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let redirect = URLRequest(url: URL(string: "https://invalid.example/")!)
        let next: URLRequest? = await withCheckedContinuation { continuation in
            WCAOAuthBrokerRedirectDelegate().urlSession(session, task: task, willPerformHTTPRedirection: response,
                newRequest: redirect) { continuation.resume(returning: $0) }
        }
        XCTAssertNil(next)
    }
}

import XCTest
@testable import CubeFlow

final class WCAOAuthSecurityTests: XCTestCase {
    private let redirect = "cubeflow-wca://oauth/callback"
    private func callback(_ attempt: WCAOAuthAttempt, prefix: String = "cubeflow-wca://oauth/callback",
                          extra: String = "&code=fixture-code") throws -> URL {
        try XCTUnwrap(URL(string: prefix + "?state=" + attempt.state + extra))
    }
    func testSecureStateIsFreshAndURLSafe() throws {
        let states = try (0..<100).map { _ in try WCAOAuthAttempt().state }
        XCTAssertEqual(Set(states).count, 100)
        XCTAssertTrue(states.allSatisfy { $0.count == 43 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") } })
    }
    func testValidBoundCallbackIsSingleUse() throws {
        var attempt = try WCAOAuthAttempt()
        let url = try callback(attempt)
        XCTAssertEqual(try attempt.consume(url, redirectURI: redirect), "fixture-code")
        XCTAssertThrowsError(try attempt.consume(url, redirectURI: redirect)) {
            XCTAssertEqual($0 as? WCAOAuthAttempt.Failure, .consumed)
        }
    }
    func testRejectsUnexpectedRedirectAndConsumesFailedAttempt() throws {
        for prefix in ["other://oauth/callback", "cubeflow-wca://other/callback", "cubeflow-wca://oauth/callback/",
                       "cubeflow-wca://oauth:12/callback", "cubeflow-wca://user@oauth/callback", "cubeflow-wca://oauth/%63allback"] {
            var attempt = try WCAOAuthAttempt()
            XCTAssertThrowsError(try attempt.consume(callback(attempt, prefix: prefix), redirectURI: redirect)) {
                XCTAssertEqual($0 as? WCAOAuthAttempt.Failure, .redirect)
            }
            XCTAssertTrue(attempt.isConsumed)
        }
        var attempt = try WCAOAuthAttempt()
        XCTAssertThrowsError(try attempt.consume(callback(attempt, extra: "&code=x#fragment"), redirectURI: redirect))
    }
    func testRejectsMissingDuplicateWrongStateAndAmbiguousResponses() throws {
        let other = try WCAOAuthAttempt()
        for suffix in ["?code=x", "?state=wrong&code=x", "?state=\(other.state)&code=x"] {
            var attempt = try WCAOAuthAttempt()
            XCTAssertThrowsError(try attempt.consume(XCTUnwrap(URL(string: redirect + suffix)), redirectURI: redirect))
        }
        for extra in ["&state=duplicate&code=x", "&code=x&code=y", "&code=", "", "&error=access_denied&code=x", "&error=unknown"] {
            var attempt = try WCAOAuthAttempt()
            XCTAssertThrowsError(try attempt.consume(callback(attempt, extra: extra), redirectURI: redirect))
        }
    }
    func testAccessDeniedStillRequiresBoundState() throws {
        var attempt = try WCAOAuthAttempt()
        XCTAssertThrowsError(try attempt.consume(callback(attempt, extra: "&error=access_denied"), redirectURI: redirect)) {
            XCTAssertEqual($0 as? WCAOAuthAttempt.Failure, .denied)
        }
    }
    func testBearerRequestsCannotLeakToOtherOrigins() throws {
        for text in ["https://www.worldcubeassociation.org/api/v0/me", "https://www.worldcubeassociation.org:443/api/v0/me"] {
            XCTAssertTrue(WCAOAuthAttempt.permitsBearerToken(to: try XCTUnwrap(URL(string: text))))
        }
        for text in ["http://www.worldcubeassociation.org/api/v0/me", "https://www.worldcubeassociation.org.evil.test/",
                     "https://evil.test/", "https://user@www.worldcubeassociation.org/", "https://www.worldcubeassociation.org:444/"] {
            XCTAssertFalse(WCAOAuthAttempt.permitsBearerToken(to: try XCTUnwrap(URL(string: text))))
        }
    }
    @MainActor func testProductionCallbackDispatcherIgnoresStaleAndDuplicateDelivery() async throws {
        let manager = WCAAuthManager.debugAuthorizationManager()
        let attempt = try WCAOAuthAttempt()
        let task = Task { try await manager.debugWaitForAuthorization(attempt) }
        for _ in 0..<100 where manager.debugPendingAuthorizationID == nil { await Task.yield() }
        XCTAssertEqual(manager.debugPendingAuthorizationID, attempt.id)
        manager.debugDeliverAuthorization(UUID(), callback: try callback(attempt))
        XCTAssertEqual(manager.debugPendingAuthorizationID, attempt.id)
        manager.debugDeliverAuthorization(attempt.id, callback: try callback(attempt))
        manager.debugDeliverAuthorization(attempt.id, callback: try callback(attempt))
        let result = try await task.value
        XCTAssertEqual(result, "fixture-code")
        XCTAssertNil(manager.debugPendingAuthorizationID)
    }
    @MainActor func testInFlightRefreshCannotRestoreAnInvalidatedSession() async throws {
        let manager = WCAAuthManager.debugAuthorizationManager()
        manager.debugUseExpiredFixtureSession()
        var release: CheckedContinuation<Void, Never>?
        manager.debugRefreshBarrier = { await withCheckedContinuation { release = $0 } }
        let task = Task { try await manager.authorizedRequest(for: XCTUnwrap(URL(string: "https://www.worldcubeassociation.org/api/v0/me"))) }
        for _ in 0..<100 where release == nil { await Task.yield() }
        let continuation = try XCTUnwrap(release)
        manager.debugCancelAuthorizationWork()
        continuation.resume()
        do { _ = try await task.value; XCTFail("Invalidated work must not publish/store fresh tokens") }
        catch WCAAuthError.cancelled { }
    }
}

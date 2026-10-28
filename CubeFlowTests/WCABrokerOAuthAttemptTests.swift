import CryptoKit
import Foundation
import XCTest
@testable import CubeFlow

@MainActor
final class WCABrokerOAuthAttemptTests: XCTestCase {
    private typealias Attempt = WCABrokerOAuthAttempt
    private let ticket = String(repeating: "T", count: 43)

    private func authURL(_ mutate: (inout URLComponents) -> Void = { _ in }) -> URL {
        var c = URLComponents(string: "https://www.worldcubeassociation.org/oauth/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: "fixture-client"),
            .init(name: "redirect_uri", value: "https://api.cubeflow.com.cn/v1/oauth/wca/callback"),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: "public"),
            .init(name: "state", value: String(repeating: "S", count: 43))
        ]
        mutate(&c)
        return c.url!
    }

    private func prepared(clock: AttemptTestClock = .init(), expires: Int64 = 10_600) throws -> (Attempt, String) {
        let attempt = try Attempt(random: AttemptTestRandom(), clock: clock)
        let request = try attempt.makeStartRequest()
        _ = try attempt.prepareAuthorization(url: authURL(), transactionExpiresAt: expires)
        return (attempt, request.appState)
    }

    private func callback(_ state: String, ticket: String? = nil) -> URL {
        var c = URLComponents(string: "cubeflow-wca://oauth/callback")!
        c.queryItems = [.init(name: "state", value: state), .init(name: "ticket", value: ticket ?? self.ticket)]
        return c.url!
    }

    private func expect(_ failure: Attempt.Failure, _ operation: () throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) {
        do { try operation(); XCTFail("Expected sanitized attempt failure", file: file, line: line) }
        catch let actual as Attempt.Failure { XCTAssertTrue(actual == failure, "Wrong failure category", file: file, line: line) }
        catch { XCTFail("Unexpected error type", file: file, line: line) }
    }

    func testRFC7636AppendixBIndependentlyOfRandomGenerator() async throws {
        // Official verifier/challenge, unchanged; no attempt or random source is constructed in this test.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        XCTAssertTrue(try Attempt.s256Challenge(for: verifier) == expected, "RFC 7636 Appendix B mismatch")
    }

    func testProductionUsesTwoIndependent32ByteDrawsAndUTF8Hash() async throws {
        let random = AttemptTestRandom()
        let attempt = try Attempt(random: random, clock: AttemptTestClock())
        let start = try attempt.makeStartRequest()
        XCTAssertEqual(random.counts, [32, 32])
        let verifier = encode(Data(repeating: 0xFB, count: 32))
        let state = encode(Data(repeating: 0xFF, count: 32))
        XCTAssertTrue(start.appState == state && state != verifier)
        XCTAssertEqual(start.appState.utf8.count, 43)
        XCTAssertEqual(start.codeChallenge.utf8.count, 43)
        XCTAssertFalse((state + verifier + start.codeChallenge).contains("="))
        XCTAssertFalse((state + verifier + start.codeChallenge).contains("+"))
        XCTAssertFalse((state + verifier + start.codeChallenge).contains("/"))
        XCTAssertTrue(start.codeChallenge == encode(Data(SHA256.hash(data: Data(verifier.utf8)))))
        XCTAssertTrue(start.codeChallenge != encode(Data(SHA256.hash(data: Data(repeating: 0xFB, count: 32)))))
        XCTAssertEqual(start.codeChallengeMethod, "S256")
        _ = try attempt.prepareAuthorization(url: authURL(), transactionExpiresAt: 10_600)
        try attempt.receiveCallback(callback(state))
        let claim = try attempt.claimCompletion()
        XCTAssertTrue(claim.request.codeVerifier == verifier, "Original verifier was not retained")
    }

    func testSecureRandomFailuresAreSanitizedIncludingWrongByteCounts() async throws {
        for source in [AttemptTestRandom(failAt: 1), AttemptTestRandom(failAt: 2), AttemptTestRandom(length: 31)] {
            expect(.randomUnavailable) { _ = try Attempt(random: source) }
        }
    }

    func testVerifierGrammarSupportsRFCNotOnlyProductionLength() async throws {
        for size in [43, 64, 128] { _ = try Attempt.s256Challenge(for: String(repeating: "~", count: size)) }
        for verifier in ["", String(repeating: "a", count: 42), String(repeating: "a", count: 129),
                         String(repeating: "=", count: 43), String(repeating: "文", count: 43)] {
            expect(.invalidVerifier) { _ = try Attempt.s256Challenge(for: verifier) }
        }
    }

    func testValidAuthorizationAndIndependentBrokerState() async throws {
        let (attempt, state) = try prepared()
        XCTAssertTrue(state != String(repeating: "S", count: 43))
        XCTAssertEqual(attempt.state, .authorizing)
        try attempt.validateBeforeBrowserLaunch()
        try attempt.receiveCallback(callback(state))
        XCTAssertEqual(attempt.state, .ticketReceived)
    }

    func testAuthorizationRejectsWrongOriginPathAndURLStructure() async throws {
        let mutations: [(inout URLComponents) -> Void] = [
            { $0.scheme = "http" }, { $0.host = "www.worldcubeassociation.org.attacker.invalid" },
            { $0.path = "/oauth/authorize/" }, { $0.percentEncodedPath = "/oauth/%61uthorize" },
            { $0.user = "user" }, { $0.password = "password" }, { $0.port = 8443 }, { $0.fragment = "" }
        ]
        for mutation in mutations {
            let attempt = try Attempt(random: AttemptTestRandom())
            _ = try attempt.makeStartRequest()
            expect(.invalidAuthorizationURL) {
                _ = try attempt.prepareAuthorization(url: authURL(mutation), transactionExpiresAt: 10_600)
            }
            XCTAssertEqual(attempt.state, .rejected)
        }
    }

    func testAuthorizationRequiresExactUniqueContractParameters() async throws {
        let invalid: [(String, String?)] = [("client_id", ""), ("scope", nil), ("scope", "public email"),
            ("redirect_uri", "cubeflow-wca://oauth/callback"), ("response_type", "token"), ("state", "short")]
        for (key, value) in invalid {
            let attempt = try Attempt(random: AttemptTestRandom())
            _ = try attempt.makeStartRequest()
            let url = authURL { c in
                c.queryItems?.removeAll { $0.name == key }
                if let value { c.queryItems?.append(.init(name: key, value: value)) }
            }
            expect(.invalidAuthorizationURL) { _ = try attempt.prepareAuthorization(url: url, transactionExpiresAt: 10_600) }
        }
        for key in ["client_id", "redirect_uri", "scope", "response_type", "state", "extra"] {
            let attempt = try Attempt(random: AttemptTestRandom())
            _ = try attempt.makeStartRequest()
            let url = authURL { $0.queryItems?.append(.init(name: key, value: "duplicate")) }
            expect(.invalidAuthorizationURL) { _ = try attempt.prepareAuthorization(url: url, transactionExpiresAt: 10_600) }
        }
    }

    func testTrustedURLExpectationsAreInjectableNotResponseDerived() async throws {
        var config = Attempt.URLExpectations()
        config.authorizationHost = "fixture.invalid"
        let attempt = try Attempt(random: AttemptTestRandom(), clock: AttemptTestClock(), expectations: config)
        _ = try attempt.makeStartRequest()
        _ = try attempt.prepareAuthorization(url: authURL { $0.host = "fixture.invalid" }, transactionExpiresAt: 10_600)
        XCTAssertEqual(attempt.state, .authorizing)
    }

    func testAuthorizationAcceptsQueryReorderingAndExplicitDefaultHTTPSPort() async throws {
        let attempt = try Attempt(random: AttemptTestRandom(), clock: AttemptTestClock())
        _ = try attempt.makeStartRequest()
        let url = authURL { $0.port = 443; $0.queryItems = $0.queryItems?.reversed() }
        _ = try attempt.prepareAuthorization(url: url, transactionExpiresAt: 10_600)
        XCTAssertEqual(attempt.state, .authorizing)
    }

    func testValidDenialIsTerminalAndDoesNotReturnTicket() async throws {
        let (attempt, state) = try prepared()
        try attempt.receiveCallback(URL(string: "cubeflow-wca://oauth/callback?error=access_denied&state=\(state)")!)
        XCTAssertEqual(attempt.state, .denied)
        expect(.invalidState) { _ = try attempt.claimCompletion() }
    }

    func testCallbackRejectsSchemeHostPathFragmentUserAndPort() async throws {
        let mutations: [(inout URLComponents) -> Void] = [
            { $0.scheme = "other" }, { $0.host = "other" }, { $0.path = "/callback/" },
            { $0.percentEncodedPath = "/%63allback" }, { $0.fragment = "" },
            { $0.user = "user" }, { $0.password = "pw" }, { $0.port = 123 }
        ]
        for mutation in mutations {
            let (attempt, state) = try prepared()
            var c = URLComponents(url: callback(state), resolvingAgainstBaseURL: false)!
            mutation(&c)
            expect(.invalidCallback) { try attempt.receiveCallback(c.url!) }
            XCTAssertEqual(attempt.state, .rejected)
        }
    }

    func testCallbackRejectsMissingEmptyDuplicateMixedAndUnknownFields() async throws {
        let changes: [([URLQueryItem]) -> [URLQueryItem]] = [
            { $0.filter { $0.name != "state" } }, { $0.filter { $0.name != "ticket" } },
            { $0.filter { $0.name != "ticket" } + [.init(name: "ticket", value: "")] },
            { $0 + [.init(name: "ticket", value: "duplicate")] },
            { $0 + [.init(name: "state", value: "duplicate")] },
            { $0 + [.init(name: "error", value: "access_denied")] },
            { $0 + [.init(name: "extra", value: "unexpected")] },
            { $0.filter { $0.name != "ticket" } + [.init(name: "error", value: "server_error")] },
            { $0.filter { $0.name != "ticket" } + [.init(name: "ticket", value: nil)] },
            { $0.filter { $0.name != "ticket" } + [.init(name: "ticket", value: "bad=token")] }
        ]
        for change in changes {
            let (attempt, state) = try prepared()
            var c = URLComponents(url: callback(state), resolvingAgainstBaseURL: false)!
            c.queryItems = change(c.queryItems!)
            expect(.invalidCallback) { try attempt.receiveCallback(c.url!) }
            XCTAssertEqual(attempt.state, .rejected)
        }
    }

    func testStateMismatchRejectsBothSameAndDifferentLengthAndBrokerState() async throws {
        for value in [String(repeating: "X", count: 43), "", "short", String(repeating: "S", count: 43)] {
            let (attempt, _) = try prepared()
            expect(.stateMismatch) { try attempt.receiveCallback(callback(value)) }
            XCTAssertEqual(attempt.state, .rejected)
        }
    }

    func testReturnedShortTransactionExpiryIsNotReplacedWith600Seconds() async throws {
        let clock = AttemptTestClock()
        let (attempt, _) = try prepared(clock: clock, expires: 10_020)
        clock.advance(15)
        expect(.expired) { try attempt.validateBeforeBrowserLaunch() }
        XCTAssertEqual(attempt.state, .expired)
    }

    func testAlreadyExpiredStartAndExcessiveClockSkewFailClosed() async throws {
        for (expiry, error) in [(Int64(10_005), Attempt.Failure.expired), (Int64(20_000), .invalidTransaction)] {
            let attempt = try Attempt(random: AttemptTestRandom(), clock: AttemptTestClock())
            _ = try attempt.makeStartRequest()
            expect(error) { _ = try attempt.prepareAuthorization(url: authURL(), transactionExpiresAt: expiry) }
        }
    }

    func testCallbackExpirationAndMonotonicClockPreventsRollbackExtension() async throws {
        for rollback in [false, true] {
            let clock = AttemptTestClock()
            let (attempt, state) = try prepared(clock: clock)
            clock.advance(595)
            if rollback { clock.moveWall(-1000) }
            expect(.expired) { try attempt.receiveCallback(callback(state)) }
        }
    }

    func testForwardClockJumpAndInvalidClockFailClosed() async throws {
        let clock = AttemptTestClock()
        let (attempt, _) = try prepared(clock: clock)
        clock.moveWall(600)
        expect(.expired) { try attempt.validateBeforeBrowserLaunch() }
        let badClock = AttemptTestClock(wall: .nan)
        let bad = try Attempt(random: AttemptTestRandom(), clock: badClock)
        _ = try bad.makeStartRequest()
        expect(.invalidClock) { _ = try bad.prepareAuthorization(url: authURL(), transactionExpiresAt: 10_600) }
    }

    func testTicketLocalUseBoundExpiresWithoutInventingServerExpiry() async throws {
        let clock = AttemptTestClock()
        let (attempt, state) = try prepared(clock: clock)
        try attempt.receiveCallback(callback(state))
        clock.advance(55)
        expect(.expired) { _ = try attempt.claimCompletion() }
        XCTAssertEqual(attempt.state, .expired)
    }

    func testTicketBoundCappedByTransactionExpiry() async throws {
        let clock = AttemptTestClock()
        let (attempt, state) = try prepared(clock: clock, expires: 10_030)
        try attempt.receiveCallback(callback(state))
        clock.advance(25)
        expect(.expired) { _ = try attempt.claimCompletion() }
    }

    func testTicketUseBeforeLocalDeadlineAndExpiryAfterWallRollback() async throws {
        let clock = AttemptTestClock()
        let (attempt, state) = try prepared(clock: clock)
        try attempt.receiveCallback(callback(state))
        clock.advance(54)
        _ = try attempt.claimCompletion()
        XCTAssertEqual(attempt.state, .completionClaimed)
        let secondClock = AttemptTestClock()
        let (second, secondState) = try prepared(clock: secondClock)
        try second.receiveCallback(callback(secondState))
        secondClock.advance(55)
        secondClock.moveWall(-500)
        expect(.expired) { _ = try second.claimCompletion() }
    }

    func testPreparedAndAwaitingStartCancellationCannotCreateNewAttempt() async throws {
        for requestStarted in [false, true] {
            let attempt = try Attempt(random: AttemptTestRandom(), clock: AttemptTestClock())
            if requestStarted { _ = try attempt.makeStartRequest() }
            attempt.cancel()
            XCTAssertEqual(attempt.state, .cancelled)
            expect(.invalidState) { _ = try attempt.makeStartRequest() }
        }
    }

    func testCallbackReplayAndReentrantClaimNeverConsumeTwice() async throws {
        let (attempt, state) = try prepared()
        try attempt.receiveCallback(callback(state))
        expect(.invalidState) { try attempt.receiveCallback(callback(state)) }
        XCTAssertEqual(attempt.state, .ticketReceived)
        let claim = try attempt.claimCompletion()
        XCTAssertEqual(attempt.state, .completionClaimed)
        XCTAssertTrue(claim.request.ticket == ticket)
        expect(.invalidState) { _ = try attempt.claimCompletion() }
        expect(.invalidState) { try attempt.receiveCallback(callback(state)) }
        try attempt.confirmCompletion(claimID: claim.id)
        XCTAssertEqual(attempt.state, .completionConfirmed)
        expect(.invalidClaim) { try attempt.confirmCompletion(claimID: claim.id) }
    }

    func testConcurrentConsumptionReturnsExactlyOneClaim() async throws {
        let (attempt, state) = try prepared()
        try attempt.receiveCallback(callback(state))
        let count = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<32 { group.addTask { @MainActor in (try? attempt.claimCompletion()) != nil } }
            var successes = 0
            for await success in group { if success { successes += 1 } }
            return successes
        }
        XCTAssertEqual(count, 1)
        XCTAssertEqual(attempt.state, .completionClaimed)
    }

    func testTimeoutConnectionFailureAndAmbiguousOutcomeCannotRearmTicket() async throws {
        // Transport handling is deliberately absent: the future coordinator explicitly records an unknown outcome.
        for _ in ["timeout", "connection failure", "ambiguous 502", "ambiguous 503"] {
            let (attempt, state) = try prepared()
            try attempt.receiveCallback(callback(state))
            let claim = try attempt.claimCompletion()
            try attempt.markCompletionOutcomeUnknown(claimID: claim.id)
            XCTAssertEqual(attempt.state, .completionOutcomeUnknown)
            expect(.invalidState) { _ = try attempt.claimCompletion() }
            expect(.invalidState) { _ = try attempt.makeStartRequest() }
            expect(.invalidClaim) { try attempt.confirmCompletion(claimID: claim.id) }
        }
    }

    func testCancellationBeforeAndAfterClaimIsTerminal() async throws {
        for receive in [false, true] {
            let (attempt, state) = try prepared()
            if receive { try attempt.receiveCallback(callback(state)) }
            attempt.cancel()
            XCTAssertEqual(attempt.state, .cancelled)
            expect(.invalidState) { _ = try attempt.claimCompletion() }
        }
        let (attempt, state) = try prepared()
        try attempt.receiveCallback(callback(state))
        let claim = try attempt.claimCompletion()
        attempt.cancel()
        XCTAssertEqual(attempt.state, .completionOutcomeUnknown)
        expect(.invalidState) { _ = try attempt.claimCompletion() }
        expect(.invalidClaim) { try attempt.confirmCompletion(claimID: claim.id) }
    }

    func testWrongClaimCannotFinishAnotherAttempt() async throws {
        let (attempt, state) = try prepared()
        try attempt.receiveCallback(callback(state))
        let claim = try attempt.claimCompletion()
        expect(.invalidClaim) { try attempt.confirmCompletion(claimID: UUID()) }
        XCTAssertEqual(attempt.state, .completionClaimed)
        try attempt.confirmCompletion(claimID: claim.id)
        attempt.cancel()
        XCTAssertEqual(attempt.state, .completionConfirmed)
    }

    func testDescriptionsReflectionAndErrorsRedactSensitiveValues() async throws {
        let (attempt, state) = try prepared()
        try attempt.receiveCallback(callback(state))
        let claim = try attempt.claimCompletion()
        for object: Any in [attempt, claim, claim.request] {
            let output = String(describing: object) + String(reflecting: object)
            XCTAssertFalse(output.contains(state) || output.contains(ticket) || output.contains(claim.request.codeVerifier))
            XCTAssertEqual(Mirror(reflecting: object).children.count, 0)
        }
        expect(.invalidState) { _ = try attempt.claimCompletion() }
        XCTAssertFalse(String(reflecting: Attempt.Failure.invalidCallback).contains(state))
    }

    private func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

nonisolated private final class AttemptTestRandom: WCABrokerRandomSource, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [Int] = []
    private let failAt: Int?
    private let length: Int
    var counts: [Int] { lock.lock(); defer { lock.unlock() }; return calls }

    init(failAt: Int? = nil, length: Int = 32) { self.failAt = failAt; self.length = length }

    func bytes(count: Int) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        calls.append(count)
        if calls.count == failAt { throw NSError(domain: "sensitive random diagnostic", code: -1) }
        return Data(repeating: calls.count == 1 ? 0xFB : 0xFF, count: length)
    }
}

nonisolated private final class AttemptTestClock: WCABrokerAttemptClock, @unchecked Sendable {
    private let lock = NSLock()
    private var wall: TimeInterval
    private var uptime: TimeInterval = 100
    init(wall: TimeInterval = 10_000) { self.wall = wall }
    func read() -> WCABrokerAttemptTime {
        lock.lock(); defer { lock.unlock() }
        return .init(wall: wall, uptime: uptime)
    }
    func advance(_ delta: TimeInterval) { lock.lock(); defer { lock.unlock() }; wall += delta; uptime += delta }
    func moveWall(_ delta: TimeInterval) { lock.lock(); defer { lock.unlock() }; wall += delta }
}

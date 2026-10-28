import Foundation
import XCTest
@testable import CubeFlow

@MainActor
final class WCAOAuthBrokerTests: XCTestCase {
    private typealias Client = WCAOAuthBrokerClient
    private let origin = "https://api.cubeflow.com.cn"
    private let opaque = String(repeating: "A", count: 43)
    private let broker = String(repeating: "B", count: 43)
    private let access = "fixture-wca-access"
    private let key = UUID(uuidString: "ABCDEF00-1234-0000-0000-123456789ABC")!

    override nonisolated class func setUp() {
        super.setUp()
        XCTAssertTrue(URLProtocol.registerClass(BrokerNoNetworkProtocol.self), "Could not install the no-network guard")
    }

    override nonisolated class func tearDown() {
        XCTAssertEqual(BrokerNoNetworkProtocol.startedCount, 0, "An unexpected URLSession request was blocked")
        URLProtocol.unregisterClass(BrokerNoNetworkProtocol.self)
        super.tearDown()
    }

    private func authorizationURL() -> String {
        var c = URLComponents(string: "https://www.worldcubeassociation.org/oauth/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: "fixture-public-client"),
            .init(name: "redirect_uri", value: origin + "/v1/oauth/wca/callback"),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: "public"),
            .init(name: "state", value: String(repeating: "S", count: 43))
        ]
        // There are five protocol parameters, including the independent Broker state.
        return c.string!
    }

    private func startJSON() -> [String: Any] {
        ["authorization_url": authorizationURL(), "transaction_expires_at": Int64(4_294_967_296)]
    }
    private func completeJSON() -> [String: Any] {
        ["session_id": opaque, "broker_session_token": broker,
         "broker_session_expires_at": Int64(4_297_559_296), "wca_access_token": access,
         "wca_access_token_expires_at": Int64(4_294_974_496), "server_time": Int64(4_294_967_296), "token_generation": 1]
    }
    private func refreshJSON(generation: Int64 = 2, expires: Int64 = 1) -> [String: Any] {
        ["session_id": opaque, "wca_access_token": access, "wca_access_token_expires_at": expires,
         "server_time": Int64(0), "token_generation": generation]
    }
    private func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]) }
    private func fixture(_ object: Any, path: String, status: Int = 200,
                         headers: [String: String] = ["Content-Type": "application/json"]) throws -> BrokerMockTransport.Reply {
        .success((try json(object), HTTPURLResponse(url: URL(string: origin + path)!, statusCode: status,
                                                  httpVersion: "HTTP/1.1", headerFields: headers)!))
    }
    private func startRequest() throws -> Client.StartRequest {
        try .init(codeChallenge: opaque, appState: String(repeating: "p", count: 43))
    }
    private func completeRequest() throws -> Client.CompleteRequest { try .init(ticket: opaque, codeVerifier: opaque) }
    private func token() throws -> Client.BrokerSessionToken { try .init(rawValue: broker) }

    private func expect(_ expected: Client.Failure, _ work: () async throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) async {
        do { try await work(); XCTFail("Expected a sanitized Broker failure", file: file, line: line) }
        catch let error as Client.Failure {
            XCTAssertTrue(error == expected, "Unexpected sanitized failure category", file: file, line: line)
        } catch { XCTFail("Unexpected unsanitized error type", file: file, line: line) }
    }
    private func assertRequest(_ request: URLRequest, path: String, authenticated: Bool,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(request.url?.absoluteString == origin + path, "Unexpected Broker destination", file: file, line: line)
        XCTAssertEqual(request.httpMethod, "POST", file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json", file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json", file: file, line: line)
        let bearer = request.value(forHTTPHeaderField: "Authorization")
        XCTAssertTrue(authenticated ? bearer == "Bearer " + broker : bearer == nil,
                      "Incorrect credential isolation", file: file, line: line)
        XCTAssertTrue(request.httpBody.map { $0.count <= 4096 } == true, file: file, line: line)
    }

    func testStartRequestAndResponse() async throws {
        let mock = BrokerMockTransport([try fixture(startJSON(), path: "/v1/oauth/wca/start")])
        let result = try await Client(transport: mock).start(startRequest())
        XCTAssertTrue(result.authorizationURL.absoluteString == authorizationURL(), "Authorization URL mismatch")
        XCTAssertEqual(result.transactionExpiresAt, 4_294_967_296)
        let request = try XCTUnwrap(mock.requests.first)
        assertRequest(request, path: "/v1/oauth/wca/start", authenticated: false)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertTrue(Set(body.keys) == ["code_challenge", "code_challenge_method", "app_state"])
        XCTAssertTrue(body["code_challenge"] == opaque && body["code_challenge_method"] == "S256"
                      && body["app_state"] == String(repeating: "p", count: 43), "Start fields mismatch")
        XCTAssertNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
    }

    func testRequestValidationIsLocalAndDoesNotGeneratePKCEOrUUID() async throws {
        let mock = BrokerMockTransport([])
        _ = Client(transport: mock)
        for challenge in ["", opaque + "=", String(repeating: "B", count: 43), String(repeating: "+", count: 43)] {
            XCTAssertThrowsError(try Client.StartRequest(codeChallenge: challenge, appState: opaque))
        }
        for state in ["", String(repeating: "a", count: 15), String(repeating: "a", count: 257), opaque + " ", "含有非ASCII字符"] {
            XCTAssertThrowsError(try Client.StartRequest(codeChallenge: opaque, appState: state))
        }
        for ticket in ["", "short", String(repeating: "/", count: 43)] {
            XCTAssertThrowsError(try Client.CompleteRequest(ticket: ticket, codeVerifier: opaque))
        }
        for verifier in ["", String(repeating: "a", count: 42), String(repeating: "a", count: 129), opaque + "+"] {
            XCTAssertThrowsError(try Client.CompleteRequest(ticket: opaque, codeVerifier: verifier))
        }
        for value in ["", access, broker + "\r\n", "Bearer " + broker] {
            XCTAssertThrowsError(try Client.BrokerSessionToken(rawValue: value))
        }
        _ = try Client.StartRequest(codeChallenge: opaque, appState: String(repeating: ".", count: 16))
        _ = try Client.CompleteRequest(ticket: String(repeating: "-", count: 43), codeVerifier: String(repeating: "~", count: 128))
        XCTAssertTrue(mock.requests.isEmpty, "Construction must not perform network work")
    }

    func testStartRejectsMissingAndWrongTypedFields() async throws {
        for field in ["authorization_url", "transaction_expires_at"] {
            var missing = startJSON(); missing.removeValue(forKey: field)
            let mock = BrokerMockTransport([try fixture(missing, path: "/v1/oauth/wca/start")])
            await expect(.malformedResponse) { _ = try await Client(transport: mock).start(self.startRequest()) }
        }
        for value: Any in [NSNull(), "4294967296", true, 1.5] {
            var object = startJSON(); object["transaction_expires_at"] = value
            let mock = BrokerMockTransport([try fixture(object, path: "/v1/oauth/wca/start")])
            await expect(.malformedResponse) { _ = try await Client(transport: mock).start(self.startRequest()) }
        }
    }

    func testStartRejectsUnsafeAuthorizationURLs() async throws {
        var urls = ["", "/oauth/authorize", "https://evil.invalid/", "cubeflow-wca://oauth/callback"]
        for change in ["scheme", "host", "port", "user", "fragment", "path", "redirect_uri", "scope", "response_type", "state", "client_id"] {
            var c = URLComponents(string: authorizationURL())!
            switch change {
            case "scheme": c.scheme = "http"
            case "host": c.host = "www.worldcubeassociation.org.evil.invalid"
            case "port": c.port = 444
            case "user": c.user = "untrusted"
            case "fragment": c.fragment = "unexpected"
            case "path": c.percentEncodedPath = "/oauth/%61uthorize"
            default:
                c.queryItems = c.queryItems?.map { $0.name == change ? URLQueryItem(name: change, value: change == "client_id" ? "" : "unexpected") : $0 }
            }
            urls.append(c.string!)
        }
        var duplicate = URLComponents(string: authorizationURL())!
        duplicate.queryItems?.append(.init(name: "scope", value: "public")); urls.append(duplicate.string!)
        var missing = URLComponents(string: authorizationURL())!
        missing.queryItems?.removeAll { $0.name == "state" }; urls.append(missing.string!)
        for text in urls {
            var object = startJSON(); object["authorization_url"] = text
            let mock = BrokerMockTransport([try fixture(object, path: "/v1/oauth/wca/start")])
            await expect(.malformedResponse) { _ = try await Client(transport: mock).start(self.startRequest()) }
        }
    }

    func testCompleteUsesExactBodyAndRequiredResponseFields() async throws {
        let mock = BrokerMockTransport([try fixture(completeJSON(), path: "/v1/oauth/wca/complete")])
        let result = try await Client(transport: mock).complete(completeRequest())
        XCTAssertTrue(result.sessionID == opaque && result.brokerSessionToken.rawValue == broker
                      && result.wcaAccessToken.rawValue == access, "Decoded credential fields mismatch")
        XCTAssertEqual(result.brokerSessionExpiresAt, 4_297_559_296)
        XCTAssertEqual(result.wcaAccessTokenExpiresAt, 4_294_974_496)
        XCTAssertEqual(result.serverTime, 4_294_967_296)
        XCTAssertEqual(result.tokenGeneration, 1)
        let request = try XCTUnwrap(mock.requests.first)
        assertRequest(request, path: "/v1/oauth/wca/complete", authenticated: false)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertTrue(body == ["ticket": opaque, "code_verifier": opaque], "Complete body mismatch")
        XCTAssertNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
        for field in completeJSON().keys {
            var object = completeJSON(); object.removeValue(forKey: field)
            let missing = BrokerMockTransport([try fixture(object, path: "/v1/oauth/wca/complete")])
            await expect(.malformedResponse) { _ = try await Client(transport: missing).complete(self.completeRequest()) }
        }
    }

    func testCompleteRejectsMalformedCredentialsTypesAndGeneration() async throws {
        let invalid: [(String, Any)] = [
            ("session_id", ""), ("session_id", String(repeating: "/", count: 43)),
            ("broker_session_token", ""), ("broker_session_token", broker + " "),
            ("wca_access_token", ""), ("wca_access_token", "invalid\ncredential"),
            ("wca_access_token", "非ASCII"), ("wca_access_token", String(repeating: "x", count: 8193)),
            ("token_generation", 0), ("token_generation", 2), ("token_generation", "1"),
            ("broker_session_expires_at", "123"), ("wca_access_token_expires_at", 1.5), ("server_time", NSNull())
        ]
        for (field, value) in invalid {
            var object = completeJSON(); object[field] = value
            let mock = BrokerMockTransport([try fixture(object, path: "/v1/oauth/wca/complete")])
            await expect(.malformedResponse) { _ = try await Client(transport: mock).complete(self.completeRequest()) }
        }
    }

    func testRefreshUsesBrokerBearerCallerUUIDAndExactEmptyObject() async throws {
        let mock = BrokerMockTransport([try fixture(refreshJSON(), path: "/v1/oauth/wca/refresh")])
        let result = try await Client(transport: mock).refresh(sessionToken: token(), idempotencyKey: key)
        XCTAssertTrue(result.sessionID == opaque && result.wcaAccessToken.rawValue == access, "Refresh values mismatch")
        XCTAssertEqual(result.tokenGeneration, 2)
        XCTAssertEqual(result.wcaAccessTokenExpiresAt, 1, "Expired replay must remain a valid transport response")
        let request = try XCTUnwrap(mock.requests.first)
        assertRequest(request, path: "/v1/oauth/wca/refresh", authenticated: true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), key.uuidString.lowercased())
        XCTAssertTrue(request.httpBody == Data("{}".utf8), "Expected exact empty JSON object")
    }

    func testRefreshDoesNotOrderOrRetryOrAssumeBrokerRotation() async throws {
        var first = refreshJSON(generation: 7, expires: 100)
        first["broker_session_token"] = "ignored-additive-field"
        first["broker_session_expires_at"] = Int64.max
        let mock = BrokerMockTransport([
            try fixture(first, path: "/v1/oauth/wca/refresh"),
            try fixture(refreshJSON(generation: 2, expires: 1), path: "/v1/oauth/wca/refresh")
        ])
        let client = Client(transport: mock)
        let newer = try await client.refresh(sessionToken: token(), idempotencyKey: key)
        let older = try await client.refresh(sessionToken: token(), idempotencyKey: key)
        XCTAssertEqual(newer.tokenGeneration, 7)
        XCTAssertEqual(older.tokenGeneration, 2)
        XCTAssertEqual(older.serverTime, 0)
        XCTAssertEqual(mock.requests.count, 2, "Each client invocation must dispatch exactly once")
        for request in mock.requests { assertRequest(request, path: "/v1/oauth/wca/refresh", authenticated: true) }
    }

    func testRefreshRejectsMissingFieldsBadTypesAndInvalidValues() async throws {
        for field in refreshJSON().keys {
            var object = refreshJSON(); object.removeValue(forKey: field)
            let mock = BrokerMockTransport([try fixture(object, path: "/v1/oauth/wca/refresh")])
            await expect(.malformedResponse) { _ = try await Client(transport: mock).refresh(sessionToken: self.token(), idempotencyKey: self.key) }
        }
        for (field, value): (String, Any) in [("session_id", ""), ("token_generation", 1), ("token_generation", 2.5),
                                            ("wca_access_token", "bad token"), ("server_time", "0"), ("wca_access_token_expires_at", NSNull())] {
            var object = refreshJSON(); object[field] = value
            let mock = BrokerMockTransport([try fixture(object, path: "/v1/oauth/wca/refresh")])
            await expect(.malformedResponse) { _ = try await Client(transport: mock).refresh(sessionToken: self.token(), idempotencyKey: self.key) }
        }
    }

    func testLogoutAcceptsOnlyEmpty204AndUsesNoIdempotencyHeader() async throws {
        let response = HTTPURLResponse(url: URL(string: origin + "/v1/oauth/wca/logout")!, statusCode: 204, httpVersion: nil, headerFields: nil)!
        let mock = BrokerMockTransport([.success((Data(), response))])
        try await Client(transport: mock).logout(sessionToken: token())
        let request = try XCTUnwrap(mock.requests.first)
        assertRequest(request, path: "/v1/oauth/wca/logout", authenticated: true)
        XCTAssertTrue(request.httpBody == Data("{}".utf8))
        XCTAssertNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
        let nonempty = BrokerMockTransport([.success((Data("{}".utf8), response))])
        await expect(.malformedResponse) { try await Client(transport: nonempty).logout(sessionToken: self.token()) }
        let wrongStatus = BrokerMockTransport([try fixture([:], path: "/v1/oauth/wca/logout")])
        await expect(.malformedResponse) { try await Client(transport: wrongStatus).logout(sessionToken: self.token()) }
    }

    func testAllStructuredErrorCodesAreParsedWithoutSessionDecisionsOrRetries() async throws {
        let cases: [(Int, Client.ErrorCode)] = [
            (400, .invalidRequest), (400, .invalidVerifier), (401, .sessionInvalid), (401, .sessionExpired),
            (401, .sessionRevoked), (404, .invalidRequest), (405, .invalidRequest), (409, .ticketUsed),
            (410, .ticketExpired), (410, .transactionExpired), (429, .rateLimited),
            (502, .providerUnavailable), (503, .temporarilyUnavailable)
        ]
        for (status, code) in cases {
            let object: [String: Any] = ["error": ["code": code.rawValue, "message": code.rawValue, "request_id": opaque]]
            let headers = ["Content-Type": "application/json; charset=utf-8", "Retry-After": "60"]
            let mock = BrokerMockTransport([try fixture(object, path: "/v1/oauth/wca/refresh", status: status, headers: headers)])
            await expect(.broker(status: status, code: code, requestID: opaque, retryAfterSeconds: 60)) {
                _ = try await Client(transport: mock).refresh(sessionToken: self.token(), idempotencyKey: self.key)
            }
            XCTAssertEqual(mock.requests.count, 1, "HTTP errors must not trigger automatic retry")
        }
    }

    func testCompleteTicketAndLogoutErrors() async throws {
        for (status, code): (Int, Client.ErrorCode) in [(400, .invalidVerifier), (409, .ticketUsed), (410, .ticketExpired)] {
            let object: [String: Any] = ["error": ["code": code.rawValue, "message": code.rawValue, "request_id": opaque]]
            let mock = BrokerMockTransport([try fixture(object, path: "/v1/oauth/wca/complete", status: status)])
            await expect(.broker(status: status, code: code, requestID: opaque, retryAfterSeconds: nil)) {
                _ = try await Client(transport: mock).complete(self.completeRequest())
            }
        }
        let object: [String: Any] = ["error": ["code": "session_invalid", "message": "session_invalid", "request_id": opaque]]
        let mock = BrokerMockTransport([try fixture(object, path: "/v1/oauth/wca/logout", status: 401)])
        await expect(.broker(status: 401, code: .sessionInvalid, requestID: opaque, retryAfterSeconds: nil)) {
            try await Client(transport: mock).logout(sessionToken: self.token())
        }
    }

    func testMalformedAndProxyErrorsAreSafeHTTPFailures() async throws {
        let bodies = [Data("<html>fixture-sensitive-body</html>".utf8), Data("not JSON".utf8), try json([:]),
                      try json(["error": ["code": "temporarily_unavailable", "message": access, "request_id": opaque]]),
                      try json(["error": ["code": "unrecognized", "message": "unrecognized", "request_id": opaque]])]
        for data in bodies {
            let response = HTTPURLResponse(url: URL(string: origin + "/v1/oauth/wca/logout")!, statusCode: 503,
                                           httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            let mock = BrokerMockTransport([.success((data, response))])
            await expect(.http(status: 503, retryAfterSeconds: nil)) {
                try await Client(transport: mock).logout(sessionToken: self.token())
            }
            XCTAssertEqual(mock.requests.count, 1)
        }
        let html = BrokerMockTransport([try fixture(["error": ["code": "provider_unavailable", "message": "provider_unavailable", "request_id": opaque]],
            path: "/v1/oauth/wca/refresh", status: 502, headers: ["Content-Type": "text/html", "Retry-After": "not-an-integer"])])
        await expect(.http(status: 502, retryAfterSeconds: nil)) {
            _ = try await Client(transport: html).refresh(sessionToken: self.token(), idempotencyKey: self.key)
        }
    }

    func testMalformedSuccessAndUnexpectedResponseMetadata() async throws {
        let path = "/v1/oauth/wca/complete"
        let good = HTTPURLResponse(url: URL(string: origin + path)!, statusCode: 200, httpVersion: nil,
                                   headerFields: ["Content-Type": "application/json"])!
        for body in [Data(), Data("{".utf8), try json([]), try json(NSNull())] {
            let mock = BrokerMockTransport([.success((body, good))])
            await expect(.malformedResponse) { _ = try await Client(transport: mock).complete(self.completeRequest()) }
        }
        for text in ["https://evil.invalid" + path, "http://api.cubeflow.com.cn" + path,
                     origin + "/healthz", origin + path + "?unexpected=1"] {
            let response = HTTPURLResponse(url: URL(string: text)!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            let mock = BrokerMockTransport([.success((try json(completeJSON()), response))])
            await expect(.malformedResponse) { _ = try await Client(transport: mock).complete(self.completeRequest()) }
        }
        let nonHTTP = URLResponse(url: URL(string: origin + path)!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        let mock = BrokerMockTransport([.success((Data(), nonHTTP))])
        await expect(.malformedResponse) { _ = try await Client(transport: mock).complete(self.completeRequest()) }
        for (status, contentType) in [(201, "application/json"), (200, "text/html")] {
            let bad = BrokerMockTransport([try fixture(completeJSON(), path: path, status: status, headers: ["Content-Type": contentType])])
            await expect(.malformedResponse) { _ = try await Client(transport: bad).complete(self.completeRequest()) }
        }
    }

    func testAdditiveResponseFieldsAndMaximumValidAccessTokenAreAccepted() async throws {
        var object = completeJSON()
        object["future_metadata"] = ["flag": true]
        object["wca_access_token"] = String(repeating: "!", count: 8192)
        object["server_time"] = Int64.max
        let mock = BrokerMockTransport([try fixture(object, path: "/v1/oauth/wca/complete")])
        let value = try await Client(transport: mock).complete(completeRequest())
        XCTAssertEqual(value.serverTime, Int64.max)
        XCTAssertEqual(value.wcaAccessToken.rawValue.utf8.count, 8192)
    }

    func testTransportFailuresAreDistinguishedAndSanitized() async throws {
        let failures: [(Error, Client.TransportFailure)] = [
            (URLError(.timedOut, userInfo: [NSURLErrorFailingURLStringErrorKey: "https://fixture.invalid/?ticket=sensitive"]), .timedOut),
            (URLError(.cannotConnectToHost), .connectionFailure), (URLError(.notConnectedToInternet), .connectionFailure),
            (URLError(.cancelled), .cancelled), (CancellationError(), .cancelled),
            (URLError(.secureConnectionFailed), .urlError(URLError.Code.secureConnectionFailed.rawValue)),
            (NSError(domain: "fixture-sensitive-domain", code: 1, userInfo: [NSLocalizedDescriptionKey: "fixture-sensitive-message"]), .unexpected)
        ]
        for (error, category) in failures {
            let mock = BrokerMockTransport([.failure(error)])
            await expect(.transport(category)) { _ = try await Client(transport: mock).complete(self.completeRequest()) }
            XCTAssertEqual(mock.requests.count, 1)
        }
    }

    func testEveryRedirectStatusIsRejectedWithoutFollowupRequest() async throws {
        for status in [301, 302, 303, 307, 308] {
            for target in ["https://different.invalid/?ticket=fixture-sensitive", "http://api.cubeflow.com.cn/other", origin + "/other"] {
                let mock = BrokerMockTransport([try fixture([:], path: "/v1/oauth/wca/refresh", status: status,
                                                            headers: ["Location": target])])
                await expect(.redirectRejected(status: status)) {
                    _ = try await Client(transport: mock).refresh(sessionToken: self.token(), idempotencyKey: self.key)
                }
                XCTAssertEqual(mock.requests.count, 1)
            }
        }
    }

    func testProductionTransportPolicyRejectsArbitraryOriginsPathsAndMethods() async throws {
        for path in ["start", "complete", "refresh", "logout"] {
            var request = URLRequest(url: URL(string: origin + "/v1/oauth/wca/" + path)!)
            request.httpMethod = "POST"
            XCTAssertTrue(WCAOAuthBrokerURLSessionTransport.permits(request))
            request.httpMethod = "GET"
            XCTAssertFalse(WCAOAuthBrokerURLSessionTransport.permits(request))
        }
        for text in ["https://www.worldcubeassociation.org/api/v0/me", "https://cubeflow.com.cn/v1/oauth/wca/refresh",
                     "https://api.cubeflow.com.cn.evil.invalid/v1/oauth/wca/refresh", "http://api.cubeflow.com.cn/v1/oauth/wca/refresh",
                     "https://api.cubeflow.com.cn:444/v1/oauth/wca/refresh", "https://user@api.cubeflow.com.cn/v1/oauth/wca/refresh",
                     origin + "/v1/oauth/wca/callback", origin + "/healthz", origin + "/v1/oauth/wca/refresh/",
                     origin + "/v1/oauth/wca/%72efresh", origin + "/v1/oauth/wca/refresh?ticket=unexpected",
                     origin + "/v1/oauth/wca/refresh#unexpected"] {
            var request = URLRequest(url: URL(string: text)!)
            request.httpMethod = "POST"
            XCTAssertFalse(WCAOAuthBrokerURLSessionTransport.permits(request), "Unsafe Broker destination accepted")
        }
    }

    func testActualURLSessionDelegateRefusesEveryRedirectWithoutStartingNetwork() async throws {
        let configuration = WCAOAuthBrokerURLSessionTransport.configuration()
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        configuration.protocolClasses = [BrokerNoNetworkProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        // Never resume: only the actual production redirect delegate is exercised.
        let task = session.dataTask(with: URL(string: origin + "/v1/oauth/wca/refresh")!)
        defer { task.cancel() }
        let delegate = WCAOAuthBrokerRedirectDelegate()
        for status in [301, 302, 307, 308] {
            for text in ["https://elsewhere.invalid/", "http://api.cubeflow.com.cn/other"] {
                var request = URLRequest(url: URL(string: text)!)
                request.setValue("Bearer " + broker, forHTTPHeaderField: "Authorization")
                let response = HTTPURLResponse(url: URL(string: origin + "/v1/oauth/wca/refresh")!, statusCode: status,
                                               httpVersion: nil, headerFields: ["Location": text])!
                let observation = BrokerRedirectObservation()
                delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) {
                    observation.record($0)
                }
                XCTAssertTrue(observation.called)
                XCTAssertNil(observation.request)
            }
        }
        XCTAssertEqual(BrokerNoNetworkProtocol.startedCount, 0, "A URLSession task was unexpectedly started")
    }

    func testSensitiveDTOsAndErrorsHaveRedactedDescriptionsAndMirrors() async throws {
        let mock = BrokerMockTransport([try fixture(completeJSON(), path: "/v1/oauth/wca/complete"),
                                        try fixture(startJSON(), path: "/v1/oauth/wca/start")])
        let client = Client(transport: mock)
        let result = try await client.complete(completeRequest())
        let start = try await client.start(startRequest())
        let values: [Any] = [try startRequest(), try completeRequest(), result, start, result.brokerSessionToken, result.wcaAccessToken]
        for value in values {
            let text = String(describing: value) + String(reflecting: value)
            for secret in [opaque, broker, access, authorizationURL()] {
                XCTAssertFalse(text.contains(secret), "Sensitive DTO description was not redacted")
            }
            XCTAssertTrue(Mirror(reflecting: value).children.isEmpty, "Sensitive reflection must not expose fields")
        }
        let failure = Client.Failure.broker(status: 503, code: .temporarilyUnavailable, requestID: opaque, retryAfterSeconds: nil)
        XCTAssertFalse(failure.localizedDescription.contains(opaque), "Localized errors should omit request metadata")
    }
}

nonisolated private final class BrokerMockTransport: WCAOAuthBrokerTransport, @unchecked Sendable {
    typealias Reply = Result<(Data, URLResponse), Error>
    private let lock = NSLock()
    private var replies: [Reply]
    private var captured: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return captured }
    private func next(_ request: URLRequest) throws -> (Data, URLResponse) {
        lock.lock(); defer { lock.unlock() }
        captured.append(request)
        guard !replies.isEmpty else { throw CancellationError() }
        return try replies.removeFirst().get()
    }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) { try next(request) }
}

nonisolated private final class BrokerRedirectObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var result: URLRequest?
    private var didCall = false
    func record(_ request: URLRequest?) { lock.lock(); defer { lock.unlock() }; result = request; didCall = true }
    var called: Bool { lock.lock(); defer { lock.unlock() }; return didCall }
    var request: URLRequest? { lock.lock(); defer { lock.unlock() }; return result }
}

nonisolated private final class BrokerNoNetworkProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var count = 0
    static var startedCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.count += 1; Self.lock.unlock()
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
    override func stopLoading() {}
}

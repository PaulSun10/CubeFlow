import XCTest
@testable import CubeFlow

final class CubingChinaHTTPFixture: URLProtocol, @unchecked Sendable {
    nonisolated static let lock = NSLock()
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var mime = "application/json"
    nonisolated(unsafe) static var holdsOpen = false
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var stops = 0
    nonisolated static func configure(_ body: Data, status: Int = 200, mime: String = "application/json", holdsOpen: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        self.body = body; self.status = status; self.mime = mime; self.holdsOpen = holdsOpen
        requests = []; stops = 0
    }
    nonisolated static func recordedRequests() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    nonisolated static func stopCount() -> Int { lock.lock(); defer { lock.unlock() }; return stops }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let body = Self.body, status = Self.status, mime = Self.mime, holdsOpen = Self.holdsOpen
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        if !holdsOpen { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() { Self.lock.lock(); Self.stops += 1; Self.lock.unlock() }
}

@MainActor
final class CubingChinaLiveHTTPTests: XCTestCase {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CubingChinaHTTPFixture.self]
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }

    func testPublicGETPathIdentityAndNoCredentialsOrMutations() async throws {
        let client = CubingChinaLiveHTTPClient(session: session())
        CubingChinaHTTPFixture.configure(CubingChinaModernLiveFixtures.beijing)
        let value = try await client.results(slug: "Beijing-Autumn-Rivalry-2026", key: .init(eventID: "777", number: 2))
        XCTAssertEqual(value.round.revision, 45)
        let request = try XCTUnwrap(CubingChinaHTTPFixture.recordedRequests().first)
        XCTAssertEqual(request.url?.host, "api.cubing.com")
        XCTAssertEqual(request.url?.path, "/competitions/Beijing-Autumn-Rivalry-2026/live/results/777/2")
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        CubingChinaHTTPFixture.configure(Data("[]".utf8))
        let messages = try await client.messages(slug: "Beijing-Autumn-Rivalry-2026")
        XCTAssertTrue(messages.isEmpty)
        XCTAssertEqual(CubingChinaHTTPFixture.recordedRequests().first?.url?.query, "limit=50")
    }

    func testInvalidHTTPAndNonJSONCannotBecomeSuccessfulEmptyData() async {
        let client = CubingChinaLiveHTTPClient(session: session())
        for (status, mime) in [(403, "application/json"), (200, "text/html")] {
            CubingChinaHTTPFixture.configure(Data("[]".utf8), status: status, mime: mime)
            do { _ = try await client.rounds(slug: "Beijing-Autumn-Rivalry-2026"); XCTFail("Must reject error/HTML") }
            catch { XCTAssertNotNil(error as? CubingChinaLiveError) }
        }
    }

    func testMalformedEventAndSlugCannotEscapeEndpoint() async {
        let client = CubingChinaLiveHTTPClient(session: session())
        CubingChinaHTTPFixture.configure(Data("[]".utf8))
        do { _ = try await client.results(slug: "../other", key: .init(eventID: "777", number: 2)); XCTFail() } catch {}
        do { _ = try await client.results(slug: "Safe-2026", key: .init(eventID: "777/../../admin", number: 2)); XCTFail() } catch {}
        XCTAssertTrue(CubingChinaHTTPFixture.recordedRequests().isEmpty)
    }

    func testActualURLSessionSSEFramingAndUnderlyingTaskCancellation() async throws {
        let network = session()
        defer { network.invalidateAndCancel() }
        let client = CubingChinaLiveHTTPClient(session: network)
        CubingChinaHTTPFixture.configure(Data("event: heartbeat\r\ndata: {\"type\":\"heartbeat\",\"payload\":{},\"viewers\":3}\r\n\r\n".utf8),
            mime: "text/event-stream", holdsOpen: true)
        let connection = try await client.events(slug: "Beijing-Autumn-Rivalry-2026", viewerID: "fixture-viewer-2026")
        var iterator = connection.frames.makeAsyncIterator()
        let frame = try await iterator.next()
        XCTAssertEqual(frame?.event, "heartbeat")
        XCTAssertTrue(frame?.data.contains("viewers") ?? false)
        connection.cancel()
        for _ in 0..<100 where CubingChinaHTTPFixture.stopCount() == 0 { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertGreaterThan(CubingChinaHTTPFixture.stopCount(), 0)
        XCTAssertEqual(CubingChinaHTTPFixture.recordedRequests().first?.value(forHTTPHeaderField: "Accept"), "text/event-stream")
    }
}

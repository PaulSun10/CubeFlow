import XCTest
import SwiftUI
import WebKit
import Combine
@testable import CubeFlow

@MainActor final class DeepUIStabilityTests: XCTestCase {
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<500 { if condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTFail("Native view did not settle"); throw CancellationError()
    }
    private func window<Content: View>(_ content: Content) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 320, height: 700)
        window.rootViewController = UIHostingController(rootView: content)
        window.makeKeyAndVisible(); return window
    }
    func testUnvisitedTabsDoNotConstructAndVisitedNavigationIdentityIsRetained() async throws {
        let state = DeferredTabFixture.State()
        let host = try window(DeferredTabFixture(state: state))
        defer { host.isHidden = true; host.rootViewController = nil }
        host.layoutIfNeeded(); await Task.yield()
        XCTAssertEqual(state.factoryCalls, 0); XCTAssertNil(state.navigation)
        state.active = true
        try await wait { state.navigation != nil }
        let navigation = try XCTUnwrap(state.navigation)
        let child = UIViewController(); navigation.pushViewController(child, animated: false)
        state.active = false; await Task.yield(); host.layoutIfNeeded()
        state.active = true; await Task.yield(); host.layoutIfNeeded()
        XCTAssertTrue(state.navigation === navigation)
        XCTAssertTrue(navigation.topViewController === child)
        XCTAssertEqual(state.controllersCreated, 1)
    }

    func testSameHTMLWithNewBaseReloadsAndLateOldHeightCannotResizeNewDocument() async throws {
        let state = OrganizerFixture.State()
        let host = try window(OrganizerFixture(state: state))
        defer { host.isHidden = true; host.rootViewController = nil }
        func find(_ view: UIView) -> WKWebView? { (view as? WKWebView) ?? view.subviews.lazy.compactMap { find($0) }.first }
        try await wait { host.layoutIfNeeded(); return find(host)?.isLoading == false && (find(host)?.bounds.height ?? 0) > 40 }
        let web = try XCTUnwrap(find(host))
        let nonceValue = try await web.evaluateJavaScript("document.querySelector('script[nonce]').nonce") as? String
        let oldNonce = try XCTUnwrap(nonceValue)
        let firstLink = try await web.evaluateJavaScript("document.querySelector('a').href") as? String
        XCTAssertEqual(firstLink, "https://cubing.com/competition/A/relative.html")
        state.url = URL(string: "https://cubing.com/competition/B/travel")!
        try await wait { host.layoutIfNeeded(); return web.url?.path == "/competition/B/travel" && !web.isLoading }
        XCTAssertTrue(find(host) === web, "Changing source must not recreate the native renderer")
        let secondLink = try await web.evaluateJavaScript("document.querySelector('a').href") as? String
        XCTAssertEqual(secondLink, "https://cubing.com/competition/B/relative.html")
        _ = try await web.evaluateJavaScript("window.webkit.messageHandlers.documentHeight.postMessage({nonce:'\(oldNonce)',height:3000}); null")
        try await Task.sleep(nanoseconds: 20_000_000)
        host.layoutIfNeeded(); XCTAssertLessThan(web.bounds.height, 500)
        for index in 0..<8 {
            state.html = "<p>Latest \(index)</p><p>Organizer information</p>"
            await Task.yield()
        }
        for _ in 0..<100 {
            host.layoutIfNeeded()
            if !web.isLoading,
               let text = try? await web.evaluateJavaScript("document.querySelector('main').textContent") as? String,
               text.contains("Latest 7") { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let text = try await web.evaluateJavaScript("document.querySelector('main').textContent") as? String
        XCTAssertTrue(text?.contains("Latest 7") == true)
    }

    func testMissingArtworkFailsWithoutNetworkOrInvalidImagePublication() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MissingArtworkProtocol.self]; configuration.urlCache = nil
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        let loader = ContentImageLoader(session: session)
        do {
            _ = try await loader.image(for: URL(string: "https://fixture.invalid/missing.png")!)
            XCTFail("404 artwork must not be decoded as a valid image")
        } catch ContentImageActionError.unavailable {} catch { XCTFail("Unexpected error: \(error)") }
    }
}

@MainActor private struct DeferredTabFixture: View {
    final class State: ObservableObject {
        @Published var active = false
        var factoryCalls = 0
        var controllersCreated = 0
        weak var navigation: UINavigationController?
    }
    @ObservedObject var state: State
    var body: some View {
        RetainedTabContent(isActive: state.active) { makeContent() }
    }
    private func makeContent() -> Navigation {
        state.factoryCalls += 1
        return Navigation(state: state)
    }
    struct Navigation: UIViewControllerRepresentable {
        let state: State
        func makeUIViewController(context: Context) -> UINavigationController {
            let navigation = UINavigationController(rootViewController: UIViewController())
            state.controllersCreated += 1; state.navigation = navigation; return navigation
        }
        func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    }
}

@MainActor private struct OrganizerFixture: View {
    final class State: ObservableObject {
        @Published var url = URL(string: "https://cubing.com/competition/A/travel")!
        @Published var html = "<p>Organizer</p><p><a href='relative.html'>Travel details</a></p>"
    }
    @ObservedObject var state: State
    var body: some View { CompetitionOrganizerHTMLView(html: state.html, baseURL: state.url) }
}

nonisolated private final class MissingArtworkProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("missing".utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

import XCTest
import SwiftUI
@testable import CubeFlow

private struct ChatFooterFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { let next = nextValue(); if next.height > 0 { value = next } }
}
@MainActor private final class ChatFooterProbe { var frame: CGRect = .zero }

@MainActor final class CompetitionNativeChatLayoutTests: XCTestCase {
    func testRootSafeAreaChatClearsExpandedNativeTabBarAtCompactAndRegularWidths() async throws {
        for width in [CGFloat(320), 768] {
            let probe = ChatFooterProbe()
            let view = TabView {
                CompatibleNavigationContainer {
                    ScrollView {
                        LazyVStack { ForEach(0..<100, id: \.self) { Text("Result \($0)").frame(maxWidth: .infinity).frame(height: 40) } }
                    }.safeAreaInset(edge: .bottom, spacing: 0) {
                        CompetitionLiveChatAccessory(language: "en") {}
                            .background { GeometryReader { proxy in Color.clear.preference(key: ChatFooterFrameKey.self, value: proxy.frame(in: .global)) } }
                    }.navigationTitle("Live").navigationBarTitleDisplayMode(.inline)
                }.tabItem { Label("Explore", systemImage: "safari") }
                Text("Timer").tabItem { Label("Timer", systemImage: "clock") }
                Text("Data").tabItem { Label("Data", systemImage: "chart.bar") }
                Text("Algs").tabItem { Label("Algs", systemImage: "book") }
                Text("Settings").tabItem { Label("Settings", systemImage: "gear") }
            }.tabBarMinimizeBehavior(.onScrollDown)
                .onPreferenceChange(ChatFooterFrameKey.self) { probe.frame = $0 }
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: width, height: 960)
            window.windowLevel = .alert + 1
            let host = UIHostingController(rootView: view)
            host.traitOverrides.horizontalSizeClass = width < 600 ? .compact : .regular
            window.rootViewController = host; window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            try await Task.sleep(nanoseconds: 600_000_000)
            window.layoutIfNeeded()
            let tab = try XCTUnwrap(descendants(window).compactMap { $0 as? UITabBar }.first)
            let frame = tab.convert(tab.bounds, to: window)
            XCTAssertGreaterThan(probe.frame.height, 40)
            XCTAssertFalse(frame.intersects(probe.frame), "Root safe-area inset must not overlap the actual native tab bar: footer=\(probe.frame), tab=\(frame)")
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let directory = URL(fileURLWithPath: "/tmp/cubeflow-results-refinement-oct12/screenshots")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try image.pngData()?.write(to: directory.appendingPathComponent("chat-native-expanded-\(Int(width)).png"))
            let scroll = try XCTUnwrap(descendants(window).compactMap { $0 as? UIScrollView }.first { $0.contentSize.height > $0.bounds.height })
            scroll.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
            try await Task.sleep(nanoseconds: 400_000_000)
            XCTAssertFalse(tab.convert(tab.bounds, to: window).intersects(probe.frame))
            host.beginAppearanceTransition(false, animated: false); host.endAppearanceTransition()
        }
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
}

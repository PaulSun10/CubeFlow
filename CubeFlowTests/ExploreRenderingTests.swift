import XCTest
import SwiftUI
@testable import CubeFlow

final class ExploreRenderingTests: XCTestCase {
    @MainActor
    func testModuleVocabularyInLightDarkAndAccessibilitySizes() throws {
        for (name, style, size) in [("light", UIUserInterfaceStyle.light, DynamicTypeSize.large),
                                    ("dark", .dark, .large),
                                    ("large-text-hero", .light, .accessibility3),
                                    ("large-text-feature", .light, .accessibility3),
                                    ("large-text-carousel", .light, .accessibility3),
                                    ("large-text-compactList", .light, .accessibility3),
                                    ("chinese-carousel", .light, .large),
                                    ("chinese-large-carousel", .light, .accessibility3)] {
            let store = ExploreStore()
            let language = name.hasPrefix("chinese") ? "zh-Hans" : "en"
            // Split accessibility fixtures to stay within the simulator's render texture limit.
            let presentations = ExplorePresentation.allCases.filter {
                language == "zh-Hans" ? $0 == .carousel :
                    (!size.isAccessibilitySize || name.hasSuffix($0.rawValue))
            }
            let modules = presentations.map(ExplorePreviewFixtures.module)
            let content = VStack(alignment: .leading, spacing: 32) {
                ForEach(modules) { module in
                    ExploreModuleView(module: module, store: store, language: language)
                }
            }
            .padding(20)
            .environment(\.dynamicTypeSize, size)
            .environment(\.colorScheme, style == .dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: language))
            .background(ExploreStyle.page)
            let sizingHost = UIHostingController(rootView: content)
            let fitting = sizingHost.sizeThatFits(in: CGSize(width: 393, height: 10000))
            XCTAssertGreaterThan(fitting.height, 100)
            XCTAssertLessThanOrEqual(fitting.width, 394)
            let host = UIHostingController(rootView: CompatibleNavigationContainer {
                content.navigationTitle("tab.explore")
            })
            host.overrideUserInterfaceStyle = style
            host.view.frame = CGRect(origin: .zero, size: CGSize(width: 393, height: fitting.height + 180))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene: scene)
            window.frame = host.view.frame
            window.rootViewController = host
            window.isHidden = false
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
                XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Explore vocabulary \(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("explore-vocabulary-\(name).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            window.isHidden = true
        }
    }
}

#if DEBUG && os(iOS)
import SwiftUI
import Vision
import XCTest
@testable import CubeFlow

@MainActor final class FeatureBadgeGlassTests: XCTestCase {
    func testDeveloperPlacementControlsSpokenStatus() {
        let title = Text("settings.keep_screen_awake")
        XCTAssertEqual(KeepScreenAwakeSettingsToggle(isOn: .constant(true)).badge, .new)
        XCTAssertEqual(FeatureBadgeTitle(title: title, kind: nil).accessibilityTitle, title)
        XCTAssertEqual(FeatureBadgeTitle(title: title, kind: .new).accessibilityTitle,
                       Text("\(title), \(Text("feature_badge.accessibility.new"))"))
        XCTAssertEqual(FeatureBadgeTitle(title: title, kind: .beta).accessibilityTitle,
                       Text("\(title), \(Text("feature_badge.accessibility.beta"))"))
    }

    func testUniversalLabelsAndLocalizedAccessibilityDescriptions() throws {
        XCTAssertEqual(FeatureBadgeKind.allCases.map(\.title), ["NEW", "BETA"])
        XCTAssertEqual(appLanguageOptions().count, 19)
        for language in appLanguageOptions() {
            let bundle = try XCTUnwrap(appLocalizedBundle(for: language.id))
            for key in ["feature_badge.accessibility.new", "feature_badge.accessibility.beta"] {
                let description = bundle.localizedString(forKey: key, value: "", table: nil)
                XCTAssertNotEqual(description, key, language.id)
                XCTAssertFalse(description.isEmpty, language.id)
                XCTAssertFalse(["NEW", "BETA"].contains(description), language.id)
            }
        }
    }

    func testNativeGlassPreservesSoftFillIntrinsicSize() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Native Liquid Glass requires iOS 26") }
        for kind in FeatureBadgeKind.allCases {
            for size in [DynamicTypeSize.large, .accessibility2] {
                for scheme in [ColorScheme.light, .dark] {
                    func measured(_ glass: Bool) -> CGSize {
                        UIHostingController(rootView: FeatureBadge(kind: kind, usesNativeGlass: glass)
                            .environment(\.dynamicTypeSize, size).environment(\.colorScheme, scheme))
                            .sizeThatFits(in: CGSize(width: 400, height: 160))
                    }
                    let native = measured(true), soft = measured(false)
                    XCTAssertGreaterThan(native.width, 0)
                    XCTAssertGreaterThan(native.height, 0)
                    XCTAssertEqual(native.width, soft.width, accuracy: 0.5)
                    XCTAssertEqual(native.height, soft.height, accuracy: 0.5)
                }
            }
        }
    }

    func testRenderProductionBadgeRowsInNativeLists() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        defer { window.isHidden = true; window.rootViewController = nil }
        for (theme, style, scheme) in [("light", UIUserInterfaceStyle.light, ColorScheme.light), ("dark", .dark, .dark)] {
            window.overrideUserInterfaceStyle = style
            for (page, showDevices, removeNewPlacement, newCount, betaCount) in [
                ("settings", false, false, 1, 1),
                ("devices", true, false, 0, 2),
                ("settings-without-placement", false, true, 0, 1)
            ] {
                let content = Group {
                    if showDevices { ConnectedDevicesView() }
                    else {
                        List {
                            Section {
                                if removeNewPlacement {
                                    KeepScreenAwakeSettingsToggle(isOn: .constant(true), badge: nil)
                                } else {
                                    KeepScreenAwakeSettingsToggle(isOn: .constant(true))
                                }
                            } header: {
                                Text("settings.section.timer")
                            } footer: {
                                Text("settings.keep_screen_awake_description")
                            }
                            ConnectedDevicesSettingsLink()
                        }
                        .listStyle(.insetGrouped)
                        .navigationTitle("tab.settings")
                    }
                }
                let root = NavigationView { content }
                    .navigationViewStyle(.stack)
                    .preferredColorScheme(scheme)
                    .environment(\.locale, Locale(identifier: "en"))
                    .environment(\.dynamicTypeSize, .large)
                window.rootViewController = UIHostingController(rootView: root)
                window.makeKeyAndVisible()
                window.layoutIfNeeded()
                try await Task.sleep(nanoseconds: 150_000_000)
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(page)-\(theme)"
                attachment.lifetime = .keepAlways
                add(attachment)
                let request = VNRecognizeTextRequest()
                try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
                let words = request.results?.compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ").split(whereSeparator: \.isWhitespace) ?? []
                XCTAssertEqual(words.filter { $0 == "NEW" }.count, newCount, "\(page) \(theme): \(words)")
                XCTAssertEqual(words.filter { $0 == "BETA" }.count, betaCount, "\(page) \(theme): \(words)")
            }
        }
    }
}
#endif

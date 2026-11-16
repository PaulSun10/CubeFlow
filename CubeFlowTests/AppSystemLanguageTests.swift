#if DEBUG && os(iOS)
import SwiftUI
import XCTest
@testable import CubeFlow

@MainActor final class AppSystemLanguageTests: XCTestCase {
    func testAllSupportedLanguagesResolveAndHaveSystemDefaultTranslation() throws {
        let options = appLanguageOptions()
        XCTAssertEqual(options.count, 19)
        XCTAssertFalse(options.contains { $0.id == "system" || $0.id == "Base" })
        for option in options {
            XCTAssertEqual(systemAppLanguageCode(preferred: [option.id]), option.id)
            let bundle = try XCTUnwrap(appLocalizedBundle(for: option.id))
            XCTAssertNotEqual(bundle.localizedString(forKey: "settings.language_system", value: nil, table: nil),
                              "settings.language_system", option.id)
        }
    }

    func testRegionalMatchingPreferenceOrderAndFallback() {
        let cases = [
            (["en-GB"], "en"), (["es-MX"], "es"), (["fr-CA"], "fr"),
            (["zh-CN"], "zh-Hans"), (["zh-SG"], "zh-Hans"), (["zh-Hans-HK"], "zh-Hans"),
            (["zh-HK"], "zh-Hant"), (["zh-TW"], "zh-Hant"), (["zh-MO"], "zh-Hant"),
            (["zh-Hant-CN"], "zh-Hant"),
            (["pt-BR"], "pt-BR"), (["pt-PT"], "pt-PT"), (["pt-AO"], "pt-PT"),
            (["is-IS", "he-IL", "ar-SA", "en"], "ar"), (["is-IS", "fr-CA"], "fr"),
            (["is-IS", "he-IL"], "en"), ([], "en")
        ]
        for (preferred, expected) in cases {
            let actual = systemAppLanguageCode(preferred: preferred)
            XCTAssertEqual(actual, expected, preferred.joined(separator: ","))
        }
        XCTAssertTrue(appUsesRightToLeftLayout(for: systemAppLanguageCode(preferred: ["ar-SA"])))
        XCTAssertFalse(appUsesRightToLeftLayout(for: systemAppLanguageCode(preferred: ["zh-HK"])))
    }

    func testNativeBundleLanguageWinsAndInvalidBundleChoicesFallBack() {
        XCTAssertEqual(systemAppLanguageCode(preferred: ["zh-HK", "en"], bundlePreferred: ["pt-PT"]), "pt-PT")
        XCTAssertEqual(systemAppLanguageCode(preferred: ["fr"], bundlePreferred: ["en"]), "en")
        XCTAssertEqual(systemAppLanguageCode(preferred: ["ja"], bundlePreferred: ["Base"]), "ja")
    }

    func testSelectionPersistenceAndExistingEnglishOverride() throws {
        let domain = "AppSystemLanguage." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("arabicIndic", forKey: "appNumeralSystem")
        registerSystemAppLanguage(in: defaults, preferred: ["fr"])
        XCTAssertEqual(appLanguageSelectionID(in: defaults, domain: domain), "system")
        XCTAssertEqual(defaults.string(forKey: "appLanguage"), "fr")
        for explicit in ["en", "fr"] {
            selectAppLanguage(explicit, in: defaults)
            let relaunched = try XCTUnwrap(UserDefaults(suiteName: domain))
            registerSystemAppLanguage(in: relaunched, preferred: ["ar"])
            XCTAssertEqual(appLanguageSelectionID(in: relaunched, domain: domain), explicit)
            XCTAssertEqual(relaunched.string(forKey: "appLanguage"), explicit)
        }
        selectAppLanguage("system", in: defaults, preferred: ["fr"])
        XCTAssertNil(defaults.persistentDomain(forName: domain)?["appLanguage"])
        XCTAssertEqual(appLanguageSelectionID(in: defaults, domain: domain), "system")
        XCTAssertEqual(defaults.string(forKey: "appLanguage"), "fr", "Same effective language is still a mode change")
        registerSystemAppLanguage(in: defaults, preferred: ["ja"])
        XCTAssertEqual(defaults.string(forKey: "appLanguage"), "ja")
        XCTAssertEqual(defaults.string(forKey: "appNumeralSystem"), "arabicIndic")
    }

    func testMountedAppStorageReceivesSystemUpdatesWithoutRemount() async throws {
        let domain = "AppSystemLanguage." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        registerSystemAppLanguage(in: defaults, preferred: ["fr"])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        var updates: [String] = []
        var appearances = 0
        window.rootViewController = UIHostingController(rootView: LanguageObserver(
            receive: { updates.append($0) }, appeared: { appearances += 1 }).defaultAppStorage(defaults))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await wait { updates.last == "fr" }
        registerSystemAppLanguage(in: defaults, preferred: ["ar"])
        try await wait { updates.last == "ar" }
        selectAppLanguage("en", in: defaults)
        try await wait { updates.last == "en" }
        registerSystemAppLanguage(in: defaults, preferred: ["zh-TW"])
        selectAppLanguage("system", in: defaults, preferred: ["zh-TW"])
        try await wait { updates.last == "zh-Hant" }
        XCTAssertEqual(updates, ["fr", "ar", "en", "zh-Hant"])
        XCTAssertEqual(appearances, 1)
    }

    private func wait(_ predicate: () -> Bool, line: UInt = #line) async throws {
        for _ in 0..<150 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Mounted language did not update", line: line)
        throw CancellationError()
    }

    private struct LanguageObserver: View {
        @AppStorage("appLanguage") private var language = "en"
        let receive: (String) -> Void
        let appeared: () -> Void
        var body: some View {
            Text(language)
                .onAppear { appeared(); receive(language) }
                .onChange(of: language, perform: receive)
        }
    }
}
#endif

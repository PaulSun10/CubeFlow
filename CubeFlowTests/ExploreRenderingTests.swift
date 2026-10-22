import XCTest
import SwiftUI
@testable import CubeFlow

final class ExploreRenderingTests: XCTestCase {
    @MainActor
    func testComingUpPeruCanonicalGlyphsLightDarkAndLargeText() throws {
        let events = ["333", "222", "444", "555", "666", "777", "333bf", "333fm", "333oh",
                      "clock", "minx", "pyram", "skewb", "sq1", "444bf", "555bf", "333mbf"]
        let date = Date(timeIntervalSince1970: 1_791_504_000)
        let item = ExploreItem(id: "competition.PeruNationals2026", content: .competition(id: "PeruNationals2026"),
            title: "Peru Nationals 2026", subtitle: "Nuevo Chimbote, Peru", date: date,
            competition: ExploreCompetitionPresentation(start: date, end: date.addingTimeInterval(172800),
                eventCount: events.count, registrationOpen: false, eventIDs: events))
        let module = ExploreModule(id: "competition.upcoming", titleKey: "explore.upcoming", presentation: .carousel,
            items: [item], seeAll: .competitions, titleTable: "ExploreHome")
        for scheme in [ColorScheme.light, .dark] {
            try restorationSnapshot(ExploreModuleView(module: module, store: ExploreStore(), language: "en")
                .padding(20), name: "coming-up-peru-\(scheme)", scheme: scheme)
        }
        let normal = UIHostingController(rootView: ExploreCompetitionEvents(eventIDs: events, language: "en")
            .environment(\.dynamicTypeSize, .large))
        let large = UIHostingController(rootView: ExploreCompetitionEvents(eventIDs: events + ["custom-puzzle"], language: "en")
            .environment(\.dynamicTypeSize, .accessibility3))
        let normalSize = normal.sizeThatFits(in: CGSize(width: 248, height: 2000))
        let largeSize = large.sizeThatFits(in: CGSize(width: 248, height: 2000))
        XCTAssertGreaterThan(normalSize.height, 20, "All 17 glyphs wrap, rather than truncating after one row")
        XCTAssertGreaterThan(largeSize.height, normalSize.height)
        XCTAssertLessThanOrEqual(largeSize.width, 248)
        XCTAssertEqual(CompetitionEventPresentation.localizedFullName(for: "clock", languageCode: "en"), "Clock")
        XCTAssertEqual(CompetitionEventPresentation.localizedFullName(for: "custom-puzzle", languageCode: "en"), "custom-puzzle")
    }

    @MainActor
    func testRestoredReferenceRecordsAndBrowseLightDark() throws {
        let samples: [(String, String, String, String, String, String, ExploreResultPresentation.Level)] = [
            ("777", "7x7x7 Cube", "average", "1:36.80", "Timofei Tarasenko", "Russia", .world),
            ("777", "7x7x7 Cube", "single", "1:31.63", "Timofei Tarasenko", "Russia", .continental),
            ("clock", "Clock", "average", "2.89", "Dereck Samuel Marín Suárez", "Colombia", .continental),
            ("333", "3x3x3 Cube", "average", "7.03", "Sample competitor", "Sample country", .national)
        ]
        let items = samples.enumerated().map { index, sample in
            ExploreItem(id: "reference-\(index)", content: .record(id: "reference-\(index)"),
                title: "\(sample.1) \(sample.2) of \(sample.3)", subtitle: "\(sample.4) from \(sample.5)", date: nil,
                result: ExploreResultPresentation(value: sample.3, level: sample.6),
                recordContext: ExploreRecordContext(eventName: sample.1, resultType: sample.2,
                    personName: sample.4, countryName: sample.5, competitionName: "Context remains available in the record destination",
                    sourceLabel: "Fixture only, not a new record update"))
        }
        let module = ExploreModule(id: "records.recent", titleKey: "explore.public.recent_records", presentation: .compactList,
            items: items, seeAll: .records, titleTable: "ExplorePublicData")
        let row = UIHostingController(rootView: ExploreRecordRow(item: items[0]).environment(\.dynamicTypeSize, .large))
        let rowSize = row.sizeThatFits(in: CGSize(width: 362, height: 1000))
        XCTAssertEqual(rowSize.height, 68, accuracy: 0.5,
            "Home preview retains two lines and the reference row height, allowing pixel rounding")
        let detailed = UIHostingController(rootView: ExploreRecordRow(item: items[0], showsContext: true))
        XCTAssertGreaterThan(detailed.sizeThatFits(in: CGSize(width: 362, height: 1000)).height, rowSize.height)
        for scheme in [ColorScheme.light, .dark] {
            try restorationSnapshot(ExploreModuleView(module: module, store: ExploreStore(), language: "en")
                .padding(.horizontal, 20).padding(.vertical, 16).environment(\.colorScheme, scheme),
                name: "restored-records-\(scheme)", scheme: scheme)
            try restorationSnapshot(ExploreBrowseSection(language: "en") { _ in }
                .padding(16).environment(\.colorScheme, scheme), name: "restored-browse-\(scheme)", scheme: scheme)
        }
    }

    @MainActor private func restorationSnapshot<V: View>(_ content: V, name: String, scheme: ColorScheme) throws {
        let root = content.environment(\.dynamicTypeSize, .large).background(ExploreStyle.page)
        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        let size = host.sizeThatFits(in: CGSize(width: 402, height: 2000))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: size.height)
        host.view.frame = window.bounds
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        window.isHidden = true
    }

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

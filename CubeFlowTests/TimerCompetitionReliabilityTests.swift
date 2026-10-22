import CoreData
import SwiftUI
import UIKit
import XCTest
@testable import CubeFlow

private final class DetailLoadingProtocol: URLProtocol, @unchecked Sendable {
    nonisolated static let lock = NSLock()
    nonisolated(unsafe) static var paths: [String] = []
    nonisolated(unsafe) static var fail = false
    nonisolated static func reset(fail: Bool = false) {
        lock.lock(); defer { lock.unlock() }; paths = []; self.fail = fail
    }
    nonisolated static func requests() -> [String] {
        lock.lock(); defer { lock.unlock() }; return paths
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        Self.lock.lock(); Self.paths.append(path); let fail = Self.fail; Self.lock.unlock()
        let delay = path.hasSuffix("regulations") ? 1.1 : 0.03
        let html = "<section><h2>Organizer information</h2><p>Useful official provider content.</p></section>"
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: fail ? 503 : 200,
                httpVersion: nil, headerFields: ["Content-Type": "text/html"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(html.utf8)); client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

private final class ParseCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
    func value() -> Int { lock.lock(); defer { lock.unlock() }; return count }
}

@MainActor
final class TimerCompetitionReliabilityTests: XCTestCase {
    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }

    func testTimerHitRouting() async throws {
        let persistence = PersistenceController(inMemory: true)
        let defaults = UserDefaults.standard
        let keys = ["enteringTimesWith", "timerArrangement", "scrambleDisplayMode", "drawScramblePlacement"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        defaults.set("timer", forKey: "enteringTimesWith")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for arrangement in ["classic", "split", "cards"] {
            defaults.set(arrangement, forKey: "timerArrangement")
            defaults.set("shrinkFont", forKey: "scrambleDisplayMode")
            defaults.set("bottomRight", forKey: "drawScramblePlacement")
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.windowLevel = .alert + 1
            window.rootViewController = UIHostingController(rootView: TimerTabView()
                .environment(\.managedObjectContext, persistence.container.viewContext))
            window.makeKeyAndVisible()
            try await Task.sleep(nanoseconds: 700_000_000)
            for point in [CGPoint(x: 196, y: 430), CGPoint(x: 25, y: 430), CGPoint(x: 25, y: 530), CGPoint(x: 35, y: 714)] {
                let hit = try XCTUnwrap(window.hitTest(point, with: nil))
                var chain: [String] = [], view: UIView? = hit
                while let current = view {
                    chain.append("\(type(of: current)) gestures=\(current.gestureRecognizers?.map { String(describing: type(of: $0)) } ?? [])")
                    view = current.superview
                }
                print("[TimerHit] \(arrangement) point=\(point) \(chain.joined(separator: " -> "))")
            }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "timer-hit-\(arrangement)"; attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true
        }
    }

    private func competition(_ id: String, url: String, ended: Bool = false) -> CompetitionSummary {
        CompetitionSummary(id: id, name: "2026 WCA Beijing Autumn Rivalry", shortDisplayName: nil,
            startDate: .distantPast, endDate: ended ? .distantPast : .distantFuture,
            registrationOpen: nil, registrationClose: nil, competitorLimit: nil, venue: "", venueAddress: "",
            venueDetails: nil, city: "", countryISO2: url.contains("cubing.com") ? "CN" : "US", latitude: nil, longitude: nil,
            url: url, website: nil, dateRange: "", eventIDs: ["333"], championshipTypes: nil, wcaCompetitionID: id,
            localizedRegionLineOverride: nil, localizedAddressLineOverride: nil, localizedStatusOverride: nil,
            localizedRegistrationStartOverride: nil, localizedWaitlistStartOverride: nil)
    }

    func testProgressiveInfoCoalescingWarmReopenAndFailure() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DetailLoadingProtocol.self]
        let previous = CompetitionService.detailSession
        CompetitionService.detailSession = URLSession(configuration: configuration)
        defer { CompetitionService.detailSession.invalidateAndCancel(); CompetitionService.detailSession = previous }
        DetailLoadingProtocol.reset()
        let suffix = UUID().uuidString
        let a = competition("LoadingA2026", url: "https://cubing.com/competition/Loading-A-\(suffix)")
        let b = competition("LoadingB2026", url: "https://cubing.com/competition/Loading-B-\(suffix)")
        // Distinct locale keys avoid modifying the user's existing cache entries.
        let language = "en-\(suffix)"
        let start = CACurrentMediaTime()
        async let complete = CompetitionService.fetchCompetitionDetail(for: a, languageCode: language, includeLive: true)
        let overview = await CompetitionService.fetchCompetitionOverview(for: a, languageCode: language)
        let usefulMS = (CACurrentMediaTime() - start) * 1000
        XCTAssertFalse(overview.overviewBlocks.isEmpty)
        XCTAssertLessThan(usefulMS, 700)
        let final = await complete
        let completeMS = (CACurrentMediaTime() - start) * 1000
        XCTAssertFalse(final.regulationBlocks.isEmpty)
        XCTAssertGreaterThan(completeMS, 1000)
        XCTAssertEqual(DetailLoadingProtocol.requests().filter { $0 == URL(string: a.url)!.path }.count, 1)
        print("[CompetitionControlled] old-useful=complete=\(completeMS)ms progressive-useful=\(usefulMS)ms")
        let count = DetailLoadingProtocol.requests().count
        let warmStart = CACurrentMediaTime()
        _ = await CompetitionService.fetchCompetitionOverview(for: a, languageCode: language)
        _ = await CompetitionService.fetchCompetitionDetail(for: a, languageCode: language, includeLive: true)
        print("[CompetitionControlled] warm-reopen=\((CACurrentMediaTime() - warmStart) * 1000)ms")
        XCTAssertEqual(DetailLoadingProtocol.requests().count, count)
        _ = await CompetitionService.fetchCompetitionDetail(for: b, languageCode: language, includeLive: true)
        let afterOther = DetailLoadingProtocol.requests().count
        _ = await CompetitionService.fetchCompetitionOverview(for: a, languageCode: language)
        _ = await CompetitionService.fetchCompetitionDetail(for: a, languageCode: language, includeLive: true)
        XCTAssertEqual(DetailLoadingProtocol.requests().count, afterOther)

        DetailLoadingProtocol.reset(fail: true)
        let failing = competition("LoadingFailed2026", url: "https://cubing.com/competition/Loading-Failed-\(suffix)")
        async let failed = CompetitionService.fetchCompetitionDetail(for: failing, languageCode: language, includeLive: true)
        let failedOverview = await CompetitionService.fetchCompetitionOverview(for: failing, languageCode: language)
        XCTAssertEqual(failedOverview, .empty)
        let failedResult = await failed
        XCTAssertEqual(failedResult, .empty)
    }

    func testActualDetailRemainsResponsiveWhileOtherSectionsLoad() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [DetailLoadingProtocol.self]
        let previous = CompetitionService.detailSession
        CompetitionService.detailSession = URLSession(configuration: configuration)
        defer { CompetitionService.detailSession.invalidateAndCancel(); CompetitionService.detailSession = previous }
        DetailLoadingProtocol.reset()
        let suffix = UUID().uuidString
        let competition = competition("MountedLoading2026", url: "https://cubing.com/competition/Mounted-\(suffix)")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852); window.windowLevel = .alert + 1
        let start = CACurrentMediaTime()
        var visibleMS: Double?
        window.rootViewController = UIHostingController(rootView: CompatibleNavigationContainer {
            CompetitionDetailView(competition: competition, appLanguage: "en-\(suffix)")
                .onAppear { visibleMS = (CACurrentMediaTime() - start) * 1000 }
        })
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        var worstHeartbeat = 0.0, initialMountHeartbeat = 0.0, previousBeat = CACurrentMediaTime()
        for index in 0..<60 {
            try await Task.sleep(nanoseconds: 25_000_000)
            let now = CACurrentMediaTime()
            // First navigation/layout in a fresh host process is its own measured phase.
            // This assertion concerns responsiveness AFTER mounting, during the remote wait.
            if index == 0 { initialMountHeartbeat = now - previousBeat }
            else { worstHeartbeat = max(worstHeartbeat, now - previousBeat) }
            previousBeat = now
            if index == 10 || index == 59 {
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                let attachment = XCTAttachment(image: image); attachment.lifetime = .keepAlways
                attachment.name = index == 10 ? "progressive-info-while-loading" : "progressive-info-complete"; add(attachment)
                // Screenshot rasterization is synchronous test work, not a remote-loading stall.
                previousBeat = CACurrentMediaTime()
            }
        }
        print("[CompetitionControlled] first-visible=\(try XCTUnwrap(visibleMS))ms initial-mount-heartbeat=\(initialMountHeartbeat * 1000)ms remote-wait-heartbeat=\(worstHeartbeat * 1000)ms")
        XCTAssertLessThan(worstHeartbeat, 0.25)
        XCTAssertEqual(DetailLoadingProtocol.requests().filter { $0 == URL(string: competition.url)!.path }.count, 1)
    }

    func testOriginalAdaptiveLargeFontLeavesInlineNative() {
        let availableWidth = max(UIScreen.main.bounds.width - 56, 220)
        for title in ["Short 2026", "2026 WCA Beijing Autumn Rivalry", String(repeating: "Very long competition name ", count: 8)] {
            let size = CompetitionDetailNavigationBarConfiguratorController.fittedLargeTitleSize(for: title, baseSize: 34)
            XCTAssertGreaterThanOrEqual(size, 22)
            XCTAssertLessThanOrEqual(size, 30)
            XCTAssertEqual(size.rounded(), size, "Preserve the original one-point fitting steps")
            let font = UIFont.systemFont(ofSize: size, weight: .bold)
            if size > 22 {
                XCTAssertLessThanOrEqual((title as NSString).size(withAttributes: [.font: font]).width, availableWidth)
            }
        }
        let short = CompetitionDetailNavigationBarConfiguratorController.fittedLargeTitleSize(for: "Short 2026", baseSize: 34)
        XCTAssertEqual(short, 30)
        let long = CompetitionDetailNavigationBarConfiguratorController.fittedLargeTitleSize(
            for: String(repeating: "Very long competition name ", count: 8), baseSize: 34)
        XCTAssertEqual(long, 22)
        let native = CompetitionNativeDetailTitleController.nativeAppearance(UINavigationBarAppearance())
        XCTAssertEqual((native.titleTextAttributes[.font] as? UIFont)?.fontDescriptor,
            (UINavigationBarAppearance().titleTextAttributes[.font] as? UIFont)?.fontDescriptor)
    }

    func testWCAParsingRunsOffMainCoalescesAndInvalidatesByContent() async throws {
        let paragraph = "<p>Official provider information with a complete organizer document.</p>"
        let html = "<a href=\"#general-info\" data-toggle=\"tab\">General information</a><div id=\"general-info\" class=\"tab-pane\">"
            + String(repeating: paragraph, count: 8_000) + "</div>"
        let baselineStart = CACurrentMediaTime()
        let baseline = CompetitionService.parseWCAInfo(html: html, languageCode: "en")
        let baselineMS = (CACurrentMediaTime() - baselineStart) * 1000
        XCTAssertEqual(baseline.blocks.count, 1)
        let counter = ParseCounter()
        let store = CompetitionWCAInfoParseStore { html, language in
            XCTAssertFalse(Thread.isMainThread, "The real parsing worker must not run on MainActor")
            counter.increment()
            return CompetitionService.parseWCAInfo(html: html, languageCode: language)
        }
        let start = CACurrentMediaTime()
        async let first = store.info(html: html, language: "en")
        async let joined = store.info(html: html, language: "en")
        let (a, b) = await (first, joined)
        XCTAssertEqual(a.blocks, baseline.blocks); XCTAssertEqual(a.blocks, b.blocks)
        XCTAssertEqual(counter.value(), 1)
        let workerMS = (CACurrentMediaTime() - start) * 1000
        let cachedStart = CACurrentMediaTime()
        _ = await store.info(html: html, language: "en")
        let cachedMS = (CACurrentMediaTime() - cachedStart) * 1000
        XCTAssertEqual(counter.value(), 1)
        _ = await store.info(html: html + "<!-- changed document -->", language: "en")
        XCTAssertEqual(counter.value(), 2)
        _ = await store.info(html: html, language: "zh-Hans")
        XCTAssertEqual(counter.value(), 3)
        await store.clear()
        _ = await store.info(html: html, language: "en")
        XCTAssertEqual(counter.value(), 4)
        print("[CompetitionControlled] WCA parse main-baseline=\(baselineMS)ms off-main-worker=\(workerMS)ms parsed-cache=\(cachedMS)ms identical-content=true")
    }

    func testWCAScheduleWorkerPreservesTimeRoomRoundsAndExcludesChildGroups() async throws {
        let html = #"""
        <script data-component-name="EventsTable" type="application/json">
        {"wcifEvents":[{"id":"333","rounds":[{"id":"333-r1","format":"a",
          "timeLimit":{"centiseconds":60000,"cumulativeRoundIds":[]},
          "cutoff":{"numberOfAttempts":2,"attemptResult":2000},
          "advancementCondition":{"type":"ranking","level":5}}]}]}
        </script>
        <script data-component-name="Schedule" type="application/json">
        {"wcifSchedule":{"venues":[{"id":1,"name":"Convention Center","timezone":"Asia/Seoul",
          "rooms":[{"id":1,"name":"Main Venue","color":"#673b6d","activities":[
            {"id":100,"name":"3x3x3 Cube, Round 1","activityCode":"333-r1",
             "startTime":"2026-08-17T01:00:00Z","endTime":"2026-08-17T02:00:00Z",
             "childActivities":[{"id":101,"name":"Group 1","activityCode":"333-r1-g1",
               "startTime":"2026-08-17T01:00:00Z","endTime":"2026-08-17T01:30:00Z","childActivities":[]}]}]}]}]}}
        </script>
        """#
        let days = await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            return CompetitionService.decodeWCAScheduleDays(from: html, languageCode: "en")
        }.value
        XCTAssertEqual(days.count, 1)
        let day = try XCTUnwrap(days.first)
        XCTAssertEqual(day.entries.count, 1)
        let entry = try XCTUnwrap(day.entries.first)
        XCTAssertEqual(entry.roomID, "1"); XCTAssertEqual(entry.venueName, "Main Venue")
        XCTAssertEqual(entry.roomColorHex, "#673b6d"); XCTAssertNil(entry.group)
        XCTAssertEqual(entry.startMinuteOfDay, 600); XCTAssertEqual(entry.endMinuteOfDay, 660)
        XCTAssertEqual(entry.format, "Average of 5"); XCTAssertEqual(entry.timeLimit, "10:00")
        XCTAssertEqual(entry.cutoff, "20.00 in 2 attempts"); XCTAssertEqual(entry.advancingCount, "Top 5")
    }

    func testRealProviderLoadingProbe() async throws {
        guard ProcessInfo.processInfo.environment["CUBEFLOW_PROFILE_REAL_COMPETITIONS"] == "1" else {
            throw XCTSkip("Opt-in real-provider probe, not a routine network test")
        }
        for (id, url) in [("BeijingAutumnRivalry2026", "https://cubing.com/competition/Beijing-Autumn-Rivalry-2026"),
                          ("WC2025", "https://www.worldcubeassociation.org/competitions/WC2025")] {
            let competition = CompetitionSummary(id: id, name: id, shortDisplayName: nil, startDate: .distantPast, endDate: .distantPast,
                registrationOpen: nil, registrationClose: nil, competitorLimit: nil, venue: "", venueAddress: "",
                venueDetails: nil, city: "", countryISO2: id.hasPrefix("Beijing") ? "CN" : "CA", latitude: nil, longitude: nil,
                url: url, website: nil, dateRange: "", eventIDs: ["333"], championshipTypes: nil, wcaCompetitionID: id,
                localizedRegionLineOverride: nil, localizedAddressLineOverride: nil, localizedStatusOverride: nil,
                localizedRegistrationStartOverride: nil, localizedWaitlistStartOverride: nil)
            let language = "en-profile-\(UUID().uuidString)"
            for cold in [true, false] {
                let start = CACurrentMediaTime()
                async let full = CompetitionService.fetchCompetitionDetail(for: competition, languageCode: language, forceRefresh: cold, includeLive: id.hasPrefix("Beijing"))
                let overview = await CompetitionService.fetchCompetitionOverview(for: competition, languageCode: language)
                let usefulMS = (CACurrentMediaTime() - start) * 1000
                let result = await full
                print("[CompetitionProfile] \(id) cold=\(cold) usefulMS=\(usefulMS) overviewBlocks=\(overview.overviewBlocks.count + overview.noteBlocks.count)")
                print("[CompetitionBaseline] \(id) cold=\(cold) completeMS=\((CACurrentMediaTime() - start) * 1000) blocks=\(result.overviewBlocks.count + result.noteBlocks.count) scheduleDays=\(result.scheduleDays.count)")
            }
        }
    }
}

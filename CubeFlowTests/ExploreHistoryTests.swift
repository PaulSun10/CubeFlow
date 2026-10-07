import Foundation
import Testing
@testable import CubeFlow

@MainActor
struct ExploreHistoryTests {
    @Test func datedSummaryIsCompleteAndInternallyConsistent() throws {
        let history = try #require(ExploreHistory.bundled)
        #expect(history.sourceCommit.count == 40)
        #expect(history.countries.reduce(0) { $0 + $1.count } == history.completedCount)
        #expect(history.years.reduce(0) { $0 + $1.count } == history.completedCount)
        #expect(history.completedCount <= history.inputCount)
        #expect(history.locatedCount <= history.completedCount)
        #expect(history.locatedCount > 0)
        #expect(history.events.allSatisfy { $0.count > 0 && $0.count <= history.completedCount })
        #expect(history.northernmost.allSatisfy { $0.latitude == history.northernmost.first?.latitude })
        #expect(history.southernmost.allSatisfy { $0.latitude == history.southernmost.first?.latitude })
        #expect((history.northernmost.first?.latitude ?? 0) > (history.southernmost.first?.latitude ?? 0))
        #expect((history.northernmost + history.southernmost + history.earliest + history.eventRich)
            .allSatisfy { $0.end < history.exportDate })
    }

    @Test func achievementAndStandingAreIndependent() {
        let original = ExploreResultPresentation(value: "2.74", level: .world, currentRank: 1)
        var superseded = original
        superseded.currentRank = 2
        #expect(superseded.level == .world)
        #expect(superseded.currentRank == 2)
        #expect(original.currentRank == 1)
        #expect(ExploreResultPresentation(value: "2.51", level: .world).currentRank == nil)
        #expect(ExploreContent.statistic(id: "history").destination == .stats)
    }

    @Test func upstreamHTTPFailureIsNotAJSONDecodingFailure() throws {
        let url = try #require(URL(string: "https://www.worldcubeassociation.org/api/v0/results/records"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil))
        do {
            try WCAExplorePublicDataService.validateResponse(response)
            Issue.record("403 was accepted")
        } catch WCAExplorePublicDataError.httpStatus(let code) { #expect(code == 403) }
        let ok = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        try WCAExplorePublicDataService.validateResponse(ok)
    }
}

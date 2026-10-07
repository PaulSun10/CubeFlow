import Foundation
import Testing
import UIKit
@testable import CubeFlow

@Suite("Depth correction", .serialized)
@MainActor struct DepthCorrectionTests {
    @Test func identityIsSharedOnlyForProvenCases() {
        #expect(AlgCanonicalCases.identity(setID: "sq1ep", caseID: "z_z") == AlgCanonicalCases.identity(setID: "sq1pbl", caseID: "z_z"))
        #expect(AlgCanonicalCases.identity(setID: "ZBLL", caseID: "zbll_u_1") == AlgCanonicalCases.identity(setID: "1LLL", caseID: "zbll_u_1"))
        #expect(AlgCanonicalCases.identity(setID: "pll", caseID: "aa") != AlgCanonicalCases.identity(setID: "megaminxpll", caseID: "aa"))
        #expect(AlgCanonicalCases.memberships(setID: "sq1ep", caseID: "z_z").count >= 2)
    }

    @Test func legacyProgressIsReadWithoutMigrationAndUnlearnClearsAliases() {
        let legacy = "{\"sq1ep\":[\"z_z\"],\"future-set\":[\"preserve\"]}"
        #expect(isAlgCaseLearned(setID: "sq1pbl", caseID: "z_z", storage: legacy))
        let updated = updatedLearnedCaseStorage(storage: legacy, setID: "sq1pbl", caseID: "z_z", learned: false)
        #expect(!isAlgCaseLearned(setID: "sq1ep", caseID: "z_z", storage: updated))
        #expect(learnedCaseMap(from: updated)["future-set"] == ["preserve"])
        let learned = updatedLearnedCaseStorage(storage: updated, setID: "sq1ep", caseID: "z_z", learned: true)
        #expect(learnedCaseMap(from: learned)["sq1pbl", default: []].contains("z_z"))
        #expect(learnedCaseCount(setID: "sq1pbl", caseIDs: ["z_z", "z_z"], storage: learned) == 1)
        #expect(!isAlgCaseLearned(setID: "unknown", caseID: "z_z", storage: "invalid"))
    }

    @Test func algorithmsDeduplicateOnlyExactNotationRetainingProvenance() {
        let a = AlgFormula(id: "a", notation: "R U R'", isPrimary: true, source: "A", tags: ["speed"])
        let b = AlgFormula(id: "b", notation: "R  U R'", isPrimary: false, source: "B", tags: ["reference"])
        let other = AlgFormula(id: "c", notation: "y R U R'", isPrimary: false, source: "C", tags: [])
        let merged = AlgCanonicalCases.merge([(context: "pll", algorithms: [a]), (context: "1lll", algorithms: [b, other])])
        #expect(merged.count == 2)
        #expect(merged[0].source == "A; B")
        #expect(merged[0].tags.contains("context:1lll") && merged[0].tags.contains("context:pll"))
        #expect(merged[0].isPrimary)
    }

    @Test func mergedPoolsKeepDifferentSetupContexts() throws {
        let ep = try #require(AlgLibraryLoader.load(.sq1EP)?.cases.first { $0.id == "z_z" })
        let groups = try #require(ep.algorithmGroups)
        #expect(groups.contains { $0.id.hasPrefix("sq1ep:") && $0.setup == ep.setup })
        #expect(groups.contains { $0.id.hasPrefix("sq1pbl:") })
        let pll = try #require(AlgLibraryLoader.load(.pll)?.cases.first { $0.id == "aa" })
        let pool = pll.algorithmGroups?.flatMap(\.algorithms) ?? pll.algorithms
        #expect(pool.contains { $0.tags.contains("context:1lll") })
        #expect(Set(pll.algorithms.map(\.id)).count == pll.algorithms.count)
    }

    @Test func squareOneHierarchyAndCompleteReferenceFamilies() throws {
        let pbl = try #require(AlgLibraryLoader.load(.sq1PBL))
        let groups = orderedCaseGroups(setID: pbl.set, cases: pbl.cases)
        #expect(groups.map(\.title) == ["Non-parity", "Parity"])
        #expect(groups.map { $0.cases.count } == [967, 968])
        #expect(AlgLibraryLoader.load(.sq1EP)?.cases.count == 99)
        #expect(AlgLibraryLoader.load(.sq1OBL)?.cases.count == 186)
        for set in [AlgLibrarySet.sq1PBLParity, .sq1EPParity, .sq1OBL] {
            for item in try #require(AlgLibraryLoader.loadRaw(set)).cases {
                var state = SquareOneState()
                let setupApplied = state.apply(try #require(item.setup))
                #expect(setupApplied, Comment(rawValue: item.id))
                if let formula = item.algorithms.first {
                    let inverseApplied = state.apply(formula.notation)
                    #expect(inverseApplied, Comment(rawValue: item.id))
                }
                #expect(state == SquareOneState(), Comment(rawValue: item.id))
            }
        }
    }

    @Test func probabilityUsesMultiplicityAndSortIsStable() throws {
        let pbl = try #require(AlgLibraryLoader.load(.sq1PBL))
        let total = pbl.cases.compactMap(\.probability).reduce(0, +)
        #expect(abs(total - 1) < 0.0000001)
        let aa = try #require(pbl.cases.first { $0.id == "aa_aa" }?.probability)
        let hh = try #require(pbl.cases.first { $0.id == "h_h" }?.probability)
        #expect(abs(aa / hh - 16) < 0.00001)
        let high = AlgCaseOrdering.sorted(pbl.cases, by: "likely")
        #expect(high.first?.probability == pbl.cases.compactMap(\.probability).max())
        #expect(AlgCaseOrdering.sorted(pbl.cases, by: "default") == pbl.cases)
        let obl = try #require(AlgLibraryLoader.load(.sq1OBL))
        #expect(abs(obl.cases.compactMap(\.probability).reduce(0, +) - 1) < 0.00001)
        #expect(AlgLibraryLoader.load(.pll)?.cases.allSatisfy { $0.probability == nil } == true)
    }

    @Test func cspTraceAndBothSolutionsAreDeterministic() throws {
        let payload = try #require(AlgLibraryLoader.load(.sq1CSP))
        #expect(payload.cases.count == 340)
        #expect(Set(payload.cases.compactMap { $0.csp?.shapeID }).count == 170)
        #expect(abs(payload.cases.compactMap(\.probability).reduce(0, +) - 1) < 0.000001)
        for item in payload.cases {
            let metadata = try #require(item.csp)
            let reference = SquareOneState(top: metadata.referenceTop, bottom: metadata.referenceBottom)
            var state = SquareOneState()
            let applied = state.apply(try #require(item.setup))
            #expect(applied)
            let count = try #require(SquareOneCSP.swapCount(state: state, reference: reference))
            #expect(count == metadata.swapCount && count % 2 == metadata.traceParity)
            let opposite = try #require(payload.cases.first { $0.csp?.shapeID == metadata.shapeID && $0.csp?.traceParity != metadata.traceParity })
            var wrong = state
            let wrongApplied = wrong.apply(opposite.algorithms.first?.notation ?? "")
            #expect(wrongApplied)
            #expect(SquareOneCSP.swapCount(state: wrong, reference: SquareOneState()).map { $0 % 2 } == 1)
            let solved = state.apply(item.algorithms.first?.notation ?? "")
            #expect(solved && state == SquareOneState())
            #expect(AlgCanonicalCases.identity(setID: "sq1csp", caseID: item.id) != AlgCanonicalCases.identity(setID: "sq1cs", caseID: item.id))
        }
        #expect(SquareOneCSP.swapCount(state: SquareOneState(top: [], bottom: []), reference: SquareOneState()) == nil)
    }

    @Test func reserveIsBoundedAndEachEntryConsumedOnce() {
        var reserve = ScrambleReserve(capacity: 4)
        for value in ["U", "F", "R", "L", "B"] { reserve.append(value) }
        #expect(reserve.entries.count == 4)
        #expect((0..<4).compactMap { _ in reserve.take() } == ["U", "F", "R", "L"])
        #expect(reserve.take() == nil && reserve.needsRefill)
        reserve.append("D")
        #expect(reserve.take() == "D" && reserve.take() == nil)
    }

    @Test func ftoPrewarmProvidesFourImmediateDistinctScrambles() async throws {
        FTOScrambler.prewarm()
        for _ in 0..<900 where FTOScrambler.debugReserveCount < 4 {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(FTOScrambler.debugReserveCount == 4)
        let start = ProcessInfo.processInfo.systemUptime
        let scrambles = try (0..<4).map { _ in try #require(FTOScrambler.scramble()) }
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000
        print(String(format: "[ScramblePerf] four warm deliveries_ms=%.3f", elapsed))
        #expect(Set(scrambles).count == 4 && scrambles.allSatisfy(FTOScrambler.isValidNotation))
        #expect(elapsed < 250)
        for value in scrambles { #expect(FTOScrambler.facelets(after: value)?.count == 72) }
    }

    @Test func scrollViewportCannotExtendIntoMeasuredTimerReserve() {
        #expect(TimerArrangementLayout.scrambleAvailableHeight(containerHeight: 600, timerVerticalOffset: 0, timerReservedHeight: 160, topControlsHeight: 44) == 164)
        #expect(TimerArrangementLayout.scrambleAvailableHeight(containerHeight: 100, timerVerticalOffset: -100, timerReservedHeight: 160, topControlsHeight: 44) == 0)
        #expect(TimerArrangementLayout.scrambleAvailableHeight(containerHeight: .nan, timerVerticalOffset: .nan, timerReservedHeight: .infinity, topControlsHeight: 44) == 0)
        #expect(DiagramStrokeStyle.thin.scale == 1 && DiagramStrokeStyle.medium.scale == 1.6)
        #expect(TimerArrangementLayout.measuredScrambleAvailableHeight(timerTop: 245, scrambleTop: 94) == 139)
        #expect(TimerArrangementLayout.measuredScrambleAvailableHeight(timerTop: 80, scrambleTop: 94) == 0)
        #expect(TimerArrangementLayout.measuredScrambleAvailableHeight(timerTop: .nan, scrambleTop: 94) == 0)
        #expect(TimerArrangementLayout.scrollViewportHeight(availableHeight: 139, topOffset: 39) == 100)
        #expect(TimerArrangementLayout.scrollViewportHeight(availableHeight: 10, topOffset: 39) == 0)
    }

    @Test func storedColorsHaveNonisolatedValueSemantics() async throws {
        let color = StoredColorData(r: 0.2, g: 0.3, b: 0.4)
        let equal = await Task.detached { color == StoredColorData(r: 0.2, g: 0.3, b: 0.4) }.value
        #expect(equal)
        let encoded = try JSONEncoder().encode(color)
        #expect(try JSONDecoder().decode(StoredColorData.self, from: encoded) == color)
        #expect(StoredColorData(r: .nan, g: 2, b: -1).sanitized() == StoredColorData(r: 0, g: 1, b: 0))
    }

    @Test func defaultRainUsesOriginalAssetsAndCancelsEmitters() {
        let view = SwiftConfettiView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.applyPreset(.rain)
        #expect(view.intensity == 0.75 && view.density == 1.5 && view.colors.count == 5)
        #expect(!view.playSound && !view.hapticFeedback && !view.addDepth)
        for _ in 0..<4 {
            view.startConfetti()
            let layers = view.layer.sublayers?.compactMap { $0 as? CAEmitterLayer } ?? []
            #expect(layers.count == 1)
            #expect(layers.first?.emitterCells?.allSatisfy { $0.contents != nil } == true)
            view.cancelConfetti()
            #expect(!view.isActive && (view.layer.sublayers ?? []).isEmpty)
        }
    }

    @Test func stateImagesRespondToPaletteWithoutChangingGeometry() throws {
        let setup = try #require(AlgLibraryLoader.loadRaw(.sq1EP)?.cases.first?.setup)
        let first = try #require(SquareOneCaseDiagram.image(setup: setup))
        var colors = ScrambleColorConfiguration.default.squareOne
        colors[0] = "#00ffff"
        let second = try #require(SquareOneCaseDiagram.image(setup: setup, colors: colors))
        #expect(first.size == second.size && first.pngData() != second.pngData())
        let stickers = try #require(AlgLibraryLoader.loadRaw(.pll)?.cases.first?.stickers)
        let image = try #require(AlgLastLayerDiagram.image(stickers: stickers, colors: ScrambleColorConfiguration.default.cube))
        #expect(image.size == CGSize(width: 224, height: 224))
    }
}

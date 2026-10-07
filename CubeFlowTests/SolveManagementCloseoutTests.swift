import CoreData
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import CubeFlow

@Suite("Solve management closeout")
struct SolveManagementCloseoutTests {
    @Test func automaticConnectionNeedsFreshPresenceNotRememberedIdentityOrExpiredBackoff() {
        let start = Date(timeIntervalSince1970: 100)
        #expect(!SmartCubeAutoConnectionPolicy.canAttempt(now: start, advertisementAt: nil, retryAfter: nil))
        #expect(SmartCubeAutoConnectionPolicy.canAttempt(now: start, advertisementAt: start, retryAfter: nil))
        let expiry = start.addingTimeInterval(12)
        let retry = expiry.addingTimeInterval(30)
        #expect(!SmartCubeAutoConnectionPolicy.canAttempt(now: expiry, advertisementAt: start, retryAfter: retry))
        #expect(!SmartCubeAutoConnectionPolicy.canAttempt(now: retry, advertisementAt: start, retryAfter: retry))
        // Repeated foreground/resume with only a cached UUID cannot start another attempt.
        for seconds in [42.0, 90.0, 300.0] {
            #expect(!SmartCubeAutoConnectionPolicy.canAttempt(now: start.addingTimeInterval(seconds), advertisementAt: start, retryAfter: retry))
        }
        #expect(SmartCubeAutoConnectionPolicy.canAttempt(now: retry, advertisementAt: retry, retryAfter: retry))
        #expect(!SmartCubeAutoConnectionPolicy.canAttempt(now: expiry, advertisementAt: expiry, retryAfter: retry))
    }

    @Test @MainActor func provenancePersistsIndependentlyOfSessionAndLegacyMethodStaysUnknown() throws {
        let storage = PersistenceController(inMemory: true)
        let context = storage.container.viewContext
        let session = Session(name: "Square-1", selectedEventRawValue: "square-1", selectedTimingMethodRawValue: "smartCube", context: context)
        let sessionID = session.id
        let legacy = Solve(time: 12, event: "3x3", session: session, context: context)
        let legacyID = legacy.id
        for source in SolveInputSource.allCases {
            _ = Solve(time: 10, event: "3x3", inputSource: source, session: session, context: context)
        }
        try context.save()
        context.reset()
        let restored = try context.fetchSolves(forSessionID: sessionID)
        #expect(restored.count == 6)
        #expect(restored.allSatisfy { $0.event == "3x3" })
        #expect(Set(restored.compactMap(\.inputSourceRaw)) == Set(SolveInputSource.allCases.map(\.rawValue)))
        let old = try #require(restored.first { $0.id == legacyID })
        #expect(old.inputSource == nil)
        let snapshot = SessionSolveSample(id: old.id, date: old.date, time: old.time, resultRaw: old.resultRaw,
            scramble: old.scramble, comment: old.comment, eventRawValue: old.event, inputSourceRaw: old.inputSourceRaw)
        #expect(snapshot.inputSource == nil && snapshot.eventRawValue == "3x3")
        #expect(SolveInputSource.allCases.map(\.localizationKey) == ["solve.method.touch", "solve.method.typing", "solve.method.smart_timer", "solve.method.smart_cube", "solve.method.combined"])
    }

    @Test @MainActor func moveOnlyChangesMembershipAndPreservesEverySolveOwnedField() throws {
        let storage = PersistenceController(inMemory: true)
        let context = storage.container.viewContext
        let source = Session(name: "Mixed", selectedEventRawValue: "square-1", context: context)
        let destination = Session(name: "Practice", context: context)
        let sourceID = source.id, destinationID = destination.id
        let a = Solve(time: 10.18, date: Date(timeIntervalSince1970: 100), scramble: "R U F", comment: "Keep me",
            event: "3x3", result: .plusTwo, inputSource: .smartCube, session: source, context: context)
        let b = Solve(time: 42, date: Date(timeIntervalSince1970: 200), scramble: "(1,0)/", event: "square-1",
            result: .dnf, inputSource: .appTimer, session: source, context: context)
        a.reconstructionData = Data([1, 2, 3, 4, 255])
        let untouched = Solve(time: 99, event: "2x2", session: source, context: context)
        let ids: Set<UUID> = [a.id, b.id], untouchedID = untouched.id
        let before = [a, b].map { ($0.id, $0.time, $0.date, $0.scramble, $0.event, $0.resultRaw, $0.inputSourceRaw, $0.reconstructionData, $0.comment) }
        defer { a.comment = "" }
        try context.save()
        let moved = try SolveSessionMembership.move(ids: ids, from: sourceID, to: destination, context: context)
        #expect(moved == 2)
        let checkContext = storage.newBackgroundContext()
        try checkContext.performAndWait {
            for original in before {
                let fetched = try checkContext.fetchSolve(with: original.0)
                let restored = try #require(fetched)
                #expect(restored.session?.id == destinationID)
                #expect(restored.time == original.1 && restored.date == original.2 && restored.scramble == original.3)
                #expect(restored.event == original.4 && restored.resultRaw == original.5 && restored.inputSourceRaw == original.6)
                #expect(restored.reconstructionData == original.7 && restored.comment == original.8)
            }
            #expect(try checkContext.fetchSolve(with: untouchedID)?.session?.id == sourceID)
        }
        #expect(throws: SolveSessionMembership.MoveError.invalidDestination) {
            try SolveSessionMembership.move(ids: [untouchedID], from: sourceID, to: source, context: context)
        }
        #expect(throws: SolveSessionMembership.MoveError.staleSelection) {
            try SolveSessionMembership.move(ids: [UUID()], from: sourceID, to: destination, context: context)
        }
    }

    @Test func rangesStopAtTheVisibleBoundaryAndFollowDisplayOrder() {
        let ids = (0..<10).map { _ in UUID() }
        let down = SolveSelectionRange.boundary(anchor: ids[1], visibleIDs: Set(ids[5...7]), orderedIDs: ids)
        #expect(down == .init(id: ids[7], anchorIsAbove: true))
        #expect(SolveSelectionRange.ids(from: ids[1], through: ids[7], orderedIDs: ids) == Set(ids[1...7]))
        let up = SolveSelectionRange.boundary(anchor: ids[8], visibleIDs: Set(ids[1...3]), orderedIDs: ids)
        #expect(up == .init(id: ids[1], anchorIsAbove: false))
        #expect(SolveSelectionRange.ids(from: ids[8], through: ids[1], orderedIDs: ids) == Set(ids[1...8]))
        #expect(SolveSelectionRange.boundary(anchor: ids[2], visibleIDs: Set(ids[1...3]), orderedIDs: ids) == nil)
        #expect(SolveSelectionRange.boundary(anchor: UUID(), visibleIDs: Set(ids), orderedIDs: ids) == nil)
        #expect(SolveSelectionRange.ids(from: ids[4], through: ids[4], orderedIDs: ids) == [ids[4]])
        let displayOrder = [ids[0], ids[8], ids[3], ids[6]]
        #expect(SolveSelectionRange.ids(from: ids[8], through: ids[6], orderedIDs: displayOrder) == [ids[8], ids[3], ids[6]])
    }

    @Test func anchorIsTheLatestDirectSelectionNotAnArbitrarySelectedID() {
        let a = UUID(), b = UUID()
        #expect(SolveSelectionRange.anchorAfterDirectToggle(id: a, selected: true, previous: nil) == a)
        #expect(SolveSelectionRange.anchorAfterDirectToggle(id: b, selected: true, previous: a) == b)
        #expect(SolveSelectionRange.anchorAfterDirectToggle(id: a, selected: false, previous: b) == b)
        #expect(SolveSelectionRange.anchorAfterDirectToggle(id: b, selected: false, previous: b) == nil)
    }

    @Test func persistentResultPBOutlivesAnimationButNotTheNextTimedSolve() {
        let id = UUID()
        let records = TimerPersonalBestState(solveID: id, metrics: ["best", "ao5"])
        var current = TimerCurrentResultPBState()
        current.completed(id, records: records)
        current.reconcile(records: records)
        #expect(current.isVisible && current.solveID == id)
        var celebration = TimerPBCelebrationGate()
        let first = celebration.accept(completedSolveID: id, state: records)
        let repeated = celebration.accept(completedSolveID: id, state: records)
        #expect(first && !repeated && current.isVisible)
        current.timingDidBegin()
        #expect(!current.isVisible)
        current.completed(id, records: records)
        current.reconcile(records: .init(solveID: UUID(), metrics: []))
        #expect(!current.isVisible)
    }

    @Test @MainActor func sharedPBColorUsesTheOriginalMyResultsAdaptivePalette() {
        let color = UIColor(WCAResultEmphasis.personalBest.color)
        let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(light != dark)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        light.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 252.0 / 255) < 0.001 && abs(g - 74.0 / 255) < 0.001 && abs(b - 10.0 / 255) < 0.001)
        let item = TimerStatisticDisplayItem(metric: .ao100, title: "Ao100", value: "10.18", isPersonalBest: true)
        #expect(item.isPersonalBest)
    }

    @Test func controlEdgeIncludesPartiallyVisibleEndpointRows() {
        let ids = (0..<5).map { _ in UUID() }
        let frames = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, CGRect(x: 0, y: $0.offset * 50, width: 300, height: 50)) })
        let viewport = CGRect(x: 0, y: 25, width: 300, height: 200)
        let lower = CGRect(x: 80, y: 190, width: 140, height: 35)
        let down = SolveSelectionRange.visuallyVisibleIDs(rowFrames: frames, viewport: viewport, control: lower, anchorIsAbove: true)
        #expect(down.contains(ids[3]))
        #expect(!down.contains(ids[4]))
        let upper = CGRect(x: 80, y: 25, width: 140, height: 35)
        let up = SolveSelectionRange.visuallyVisibleIDs(rowFrames: frames, viewport: viewport, control: upper, anchorIsAbove: false)
        #expect(up.contains(ids[1]))
        #expect(!up.contains(ids[0]))
    }
    
    @Test func localizedMoveCountsUseNativePluralRulesForTheChosenAppLanguage() {
        #expect(solveMoveLabel(count: 0, languageCode: "en") == "Move")
        #expect(solveMoveLabel(count: 1, languageCode: "en") == "Move 1 Solve")
        #expect(solveMoveLabel(count: 23, languageCode: "en") == "Move 23 Solves")
        #expect(solveMoveLabel(count: 21, languageCode: "ru").contains("сборку"))
        #expect(solveMoveLabel(count: 23, languageCode: "ru").contains("сборки"))
        #expect(solveMoveLabel(count: 25, languageCode: "ru").contains("сборок"))
        #expect(solveMoveLabel(count: 22, languageCode: "pl").contains("ułożenia"))
        #expect(solveMoveLabel(count: 25, languageCode: "pl").contains("ułożeń"))
        #expect(solveMoveLabel(count: 23, languageCode: "zh-Hans") == "移动 23 次成绩")
    }
}

import CoreData
import Foundation
import Testing
import UIKit
@testable import CubeFlow

@Suite("1.0 depth pass")
struct DepthPassTests {
    @Test func ftoMatchesIndependentPuzzleGeometryFixtures() throws {
        let url = try #require(Bundle.main.url(forResource: "fto_protocol_vectors", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let fixture = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let vectors = try #require(fixture["vectors"] as? [[String: Any]])
        #expect(vectors.count == 18)
        for vector in vectors {
            let notation = try #require(vector["alg"] as? String)
            let expected = try #require(vector["facelets"] as? [Int])
            #expect(FTOScrambler.facelets(after: notation) == expected, Comment(rawValue: notation))
        }
    }

    @Test func ftoNotationAndTurnOrders() throws {
        let solved = try #require(FTOScrambler.facelets(after: ""))
        #expect(solved == (0..<72).map { $0 / 9 })
        for face in ["U", "F", "BR", "BL", "D", "B", "R", "L"] {
            #expect(FTOScrambler.facelets(after: "\(face) \(face) \(face)") == solved)
            #expect(FTOScrambler.facelets(after: "\(face) \(face)'") == solved)
            #expect(FTOScrambler.facelets(after: "\(face)2") == FTOScrambler.facelets(after: "\(face)'"))
        }
        #expect(!FTOScrambler.isValidNotation("Rw M x"))
        #expect(FTOScrambler.facelets(after: "Rgarbage") == nil)
        #expect(FTOScrambler.facelets(after: "U D") == FTOScrambler.facelets(after: "D U"))
    }

    @Test func ftoRandomStateGeneratorIsAvailableAndConservesStickers() throws {
        let scramble = try #require(FTOScrambler.scramble())
        #expect(!scramble.isEmpty && FTOScrambler.isValidNotation(scramble))
        let state = try #require(FTOScrambler.facelets(after: scramble))
        for color in 0..<8 { #expect(state.filter { $0 == color }.count == 9) }
        #expect(state != FTOScrambler.facelets(after: ""))
    }

    @Test func ftoPrefetchCannotLeakAcrossEventsOrSessions() {
        let a = TimerScrambleGenerationContext(sessionID: UUID(), event: .fto, multiBlindCount: 8, unavailableMessage: "Unavailable")
        let b = TimerScrambleGenerationContext(sessionID: a.sessionID, event: .threeByThree, multiBlindCount: 1, unavailableMessage: "Unavailable")
        var slot = TimerScramblePrefetchSlot()
        let old = slot.begin(for: a)
        _ = slot.begin(for: b)
        let accepted = slot.complete(.init(context: a, scrambles: ["U R'"]), for: old)
        #expect(!accepted && slot.consume(for: b) == nil)
        #expect(a.multiBlindCount == 1)
    }

    @Test func squareOneInverseUsesSlicesNotCubeTokenInversion() throws {
        let setup = "(1,0) / (0,-1) /"
        let inverse = try #require(SquareOneNotation.inverse(setup))
        #expect(inverse == "/ (0,1) / (-1,0)")
        #expect(SquareOneNotation.normalized("1,0/0,-1/") == setup)
        #expect(SquareOneNotation.steps("R U") == nil)
        #expect(SquareOneNotation.steps("(7,0)") == nil)
        var state = SquareOneState()
        let before = state
        let legal = state.apply("(-1,0) /")
        #expect(!legal && state == before)
    }

    @Test @MainActor func everyImportedPBLSetupIsLegalAndReturnsExactlyToBaseline() throws {
        let payload = try #require(AlgLibraryLoader.loadRaw(.sq1PBL))
        #expect(payload.cases.count == 967 && Set(payload.cases.map(\.id)).count == 967)
        for item in payload.cases {
            var state = SquareOneState()
            let setup = try #require(item.setup)
            let legal = state.apply(setup)
            #expect(legal, Comment(rawValue: item.id))
            let inverseLegal = state.apply(try #require(item.algorithms.first).notation)
            #expect(inverseLegal && state == SquareOneState(), Comment(rawValue: item.id))
            #expect(item.algorithms.first?.tags.contains("reference") == true)
        }
    }

    @Test @MainActor func everyFTOReferenceSetupAndSolutionMatch() throws {
        let payload = try #require(AlgLibraryLoader.load(.ftoEdges))
        #expect(payload.cases.count == 16 && Set(payload.cases.map(\.id)).count == 16)
        for item in payload.cases {
            let setup = try #require(item.setup)
            let alg = try #require(item.algorithms.first)
            #expect(FTOScrambler.facelets(after: setup + " " + alg.notation) == FTOScrambler.facelets(after: ""))
            #expect(AlgCaseImageProvider.image(named: item.imageKey) != nil)
            #expect(alg.tags.contains("reference"))
        }
        #expect(AlgSectionData.sections(for: .fto).first?.items.first?.algorithmCount == 16)
    }

    @Test @MainActor func squareOneEPImagesContainBothCompleteLayers() throws {
        let payload = try #require(AlgLibraryLoader.load(.sq1EP))
        #expect(payload.cases.count == 99)
        for item in payload.cases {
            let setup = try #require(item.setup)
            let image = try #require(SquareOneCaseDiagram.image(setup: setup))
            #expect(image.size == SquareOneCaseDiagram.canvasSize)
            let cg = try #require(image.cgImage)
            let bytes = try #require(cg.dataProvider?.data) as Data
            let pixels = [UInt8](bytes), width = cg.width, height = cg.height, stride = cg.bytesPerRow
            var lowest = 0, highest = height, clipped = false
            for y in 0..<height {
                for x in 0..<width where pixels[y * stride + x * 4 + 3] > 0 {
                    lowest = max(lowest, y); highest = min(highest, y)
                    if x == 0 || x == width - 1 || y == 0 || y == height - 1 { clipped = true }
                }
            }
            #expect(!clipped && highest < height / 3 && lowest > height * 5 / 6)
        }
    }

    @Test @MainActor func oldCustomColorConfigurationSurvivesAddingFTO() throws {
        var existing = ScrambleColorConfiguration.default
        existing.cube[0] = "#123456"
        let encoded = try #require(existing.encodedData())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "fto")
        let decoded = ScrambleColorConfiguration.decode(from: try JSONSerialization.data(withJSONObject: object))
        #expect(decoded.cube[0] == "#123456")
        #expect(decoded.fto == ScrambleColorConfiguration.default.fto)
        #expect(decoded.schemeString(for: "fto").split(separator: "#").count == 8)
    }

    @Test @MainActor func nativeBackupPreservesSolveOwnedMetadataAndFTOIdentity() throws {
        let storage = PersistenceController(inMemory: true), context = storage.container.viewContext
        let session = Session(name: "FTO", context: context)
        session.selectedEventRawValue = "FTO"
        let solve = Solve(time: 22.5, scramble: "U R' BR", event: "FTO", result: .plusTwo, session: session, context: context)
        solve.inputSourceRaw = "future-device"
        solve.reconstructionData = Data([0, 1, 127, 255])
        let export = try DataTransferManager.prepareExport(format: .cubeFlow, sessions: [session], solves: [solve])
        let plan = try DataTransferManager.prepareImport(export.document.data, existingSessions: [DataTransferExistingSessionReference]())
        guard case .cubeFlow(let backup) = plan.plan else { Issue.record("Wrong backup type"); return }
        let row = try #require(backup.payload.solves.first)
        #expect(row.inputSourceRaw == "future-device" && row.reconstructionData == solve.reconstructionData)
        #expect(row.event == "FTO" && row.resultRaw == solve.resultRaw && row.sessionID == session.id)
        #expect(backup.payload.sessions.first?.selectedEventRawValue == "FTO")
    }

    @Test func legacyBackupDoesNotInventInputOrReconstruction() throws {
        let row = SolveBackupItem(id: UUID(), time: 12, date: Date(), scramble: "R", comment: "", event: "3x3 oh", resultRaw: "solved", sessionID: nil)
        let decoded = try JSONDecoder().decode(SolveBackupItem.self, from: JSONEncoder().encode(row))
        #expect(decoded.inputSourceRaw == nil && decoded.reconstructionData == nil && decoded.event == "3x3 oh")
    }

    @Test @MainActor func metadataRestoreKeepsLegacyValuesAndAcceptsUnknownSources() {
        let storage = PersistenceController(inMemory: true), context = storage.container.viewContext
        let solve = Solve(time: 10, event: "3x3", inputSource: .smartCube, session: nil, context: context)
        let original = Data([1, 2, 255])
        solve.reconstructionData = original
        let legacy = SolveBackupItem(id: solve.id, time: 10, date: solve.date, scramble: "", comment: "", event: "3x3", resultRaw: "solved", sessionID: nil)
        legacy.restoreMetadata(to: solve)
        #expect(solve.inputSource == .smartCube && solve.reconstructionData == original)
        let incoming = SolveBackupItem(id: solve.id, time: 10, date: solve.date, scramble: "", comment: "", event: "3x3", resultRaw: "solved", sessionID: nil, inputSourceRaw: "future-device", reconstructionData: Data([3, 4, 255]))
        incoming.restoreMetadata(to: solve)
        #expect(solve.inputSourceRaw == "future-device" && solve.inputSource == nil)
        #expect(solve.reconstructionData == incoming.reconstructionData)
    }

    @Test @MainActor func nativeBackupRetainsReplayTimestampsCompletenessAndCombinedAnchors() throws {
        let storage = PersistenceController(inMemory: true), context = storage.container.viewContext
        let session = Session(name: "Combined", context: context)
        let trace = SolveReconstruction(puzzleSize: 3,
            initialFacelets: "URFDLB".map { String(repeating: String($0), count: 9) }.joined(),
            moves: [
                .init(canonicalMove: "R", relativeTimestamp: 0.25, timestampSource: "deviceClock", deviceTimestampMilliseconds: 1200, canonicalSequence: 9),
                .init(canonicalMove: "R'", relativeTimestamp: 0.75, timestampSource: "deviceClock", deviceTimestampMilliseconds: 1700, canonicalSequence: 10)
            ], completeness: .complete,
            combinedTimingAnchors: .init(timerStopRelativeTimestamp: 1, firstMoveBoundaryTrusted: true, finalMoveBoundaryTrusted: true))
        let solve = Solve(time: 1, event: "3x3", result: .dnf, inputSource: .smartCubeAndBluetoothTimer, session: session, context: context)
        solve.reconstructionData = try JSONEncoder().encode(trace)
        let export = try DataTransferManager.prepareExport(format: .cubeFlow, sessions: [session], solves: [solve])
        let prepared = try DataTransferManager.prepareImport(export.document.data, existingSessions: [DataTransferExistingSessionReference]())
        guard case .cubeFlow(let plan) = prepared.plan else { Issue.record("Wrong native backup plan"); return }
        let row = try #require(plan.payload.solves.first)
        let restored = Solve(time: row.time, event: row.event, result: SolveResult(rawValue: row.resultRaw) ?? .solved, session: nil, context: context)
        row.restoreMetadata(to: restored)
        let encoded = try #require(restored.reconstructionData)
        let restoredTrace = try JSONDecoder().decode(SolveReconstruction.self, from: encoded)
        #expect(restoredTrace == trace && restoredTrace.isReplayable)
        #expect(restoredTrace.combinedTimingMetrics == SolveReconstruction.CombinedTimingMetrics(startDelay: 0.25, stopDelay: 0.25))
        #expect(restored.inputSource == .smartCubeAndBluetoothTimer && restored.result == .dnf)
    }

    @Test func csTimerTypedEventOverridesSessionNameAndPreservesBlindIdentity() throws {
        for (type, event) in [("fto", "FTO"), ("ftoso", "FTO"), ("333ni", "3x3 bld"), ("333oh0", "3x3 oh"), ("444bld", "4x4 bld"), ("555bld", "5x5 bld"), ("r3ni", "3x3 mbld")] {
            let metadata: [String: Any] = ["1": ["name": "3x3 OH misleading name", "opt": ["scrType": type]]]
            let root: [String: Any] = ["properties": ["sessionData": String(data: try JSONSerialization.data(withJSONObject: metadata), encoding: .utf8)!], "session1": [[[0, 12000], "U R'", "", 1000]]]
            let prepared = try DataTransferManager.prepareImport(try JSONSerialization.data(withJSONObject: root), existingSessions: [DataTransferExistingSessionReference]())
            guard case .csTimer(let imported) = prepared.plan else { Issue.record("Wrong csTimer plan"); return }
            #expect(imported.sessions.first?.solves.first?.event == event)
        }
    }

    @Test @MainActor func csTimerMixedSessionExportPreservesDistinctEventsWithoutMovingLocalSolves() throws {
        let storage = PersistenceController(inMemory: true), context = storage.container.viewContext
        let session = Session(name: "Mixed", context: context)
        let events = ["FTO", "3x3 oh", "3x3 bld", "4x4 bld", "5x5 bld"]
        let solves = events.map { Solve(time: 22.5, scramble: "R U", event: $0, session: session, context: context) }
        let package = try DataTransferManager.prepareExport(format: .csTimer, sessions: [session], solves: solves)
        let prepared = try DataTransferManager.prepareImport(package.document.data, existingSessions: [DataTransferExistingSessionReference]())
        guard case .csTimer(let plan) = prepared.plan else { Issue.record("Wrong export format"); return }
        #expect(plan.sessions.count == 5 && plan.solveCount == 5)
        #expect(Set(plan.sessions.flatMap(\.solves).map(\.event)) == Set(events))
        #expect(solves.allSatisfy { $0.session?.id == session.id })
    }

    @Test @MainActor func csTimerFastFourByFourRemainsFourByFour() throws {
        let storage = PersistenceController(inMemory: true), context = storage.container.viewContext
        let session = Session(name: "Fast", context: context)
        let solve = Solve(time: 22.5, scramble: "Rw U", event: "4x4 fast", session: session, context: context)
        let export = try DataTransferManager.prepareExport(format: .csTimer, sessions: [session], solves: [solve])
        let prepared = try DataTransferManager.prepareImport(export.document.data, existingSessions: [DataTransferExistingSessionReference]())
        guard case .csTimer(let plan) = prepared.plan else { Issue.record("Wrong csTimer plan"); return }
        #expect(plan.sessions.first?.solves.first?.event == "4x4")
        #expect(solve.event == "4x4 fast")
    }

    @Test func sharedGeometryNeverCollapsesEventIdentity() {
        #expect(PuzzleEvent.threeByThree.scrambleDiagramPuzzleKey == PuzzleEvent.threeByThreeOH.scrambleDiagramPuzzleKey)
        #expect(PuzzleEvent.threeByThree.cubingEventID != PuzzleEvent.threeByThreeOH.cubingEventID)
        #expect(PuzzleEvent.threeByThreeBLD.cubingEventID == "333bf")
        #expect(PuzzleEvent.fto.scrambleDiagramPuzzleKey == "fto" && PuzzleEvent.fromSolveEvent("fto") == .fto)
    }
}

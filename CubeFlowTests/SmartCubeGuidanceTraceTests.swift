#if DEBUG
import XCTest
import SwiftUI
import Combine
@testable import CubeFlow

@MainActor final class SmartCubeGuidanceTraceTests: XCTestCase {
    func testPathEvidenceIsBoundedNotationAndDoesNotEchoArbitraryText() {
        let evidence = SmartCubeGuidanceTrace.path(Array(repeating: "R2", count: 1000) + ["private device name"])
        XCTAssertLessThan(evidence.count, 220)
        XCTAssertTrue(evidence.hasSuffix("/1001"))
        XCTAssertEqual(SmartCubeGuidanceTrace.path(["private device name"]), "[?]/1")
        XCTAssertEqual(SmartCubeGuidanceTrace.path(nil), "none")
    }
    func testAssignmentEvidenceUsesOnlyBoundedDigestsAndShortenedIdentity() {
        let id = UUID(), scramble = "R U' F2 L D2"
        let detail = SmartCubeGuidanceTrace.assignment(scramble: scramble, requestID: id)
        XCTAssertTrue(detail.contains("scramble=" + SmartCubeGuidanceTrace.digest(scramble)))
        XCTAssertTrue(detail.contains("request=" + id.uuidString.prefix(8)))
        XCTAssertFalse(detail.contains(scramble))
        XCTAssertFalse(detail.contains(id.uuidString))
        XCTAssertLessThan(detail.count, 60)
    }
    func testMountedGuidanceViewReportsNewContextNotPreviousRenderCapture() async throws {
        let diagnostics = SmartCubeDiagnostics.shared
        diagnostics.setEnabled(true); defer { diagnostics.setEnabled(false) }
        let fixture = GuidanceRenderContextFixture()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: GuidanceRenderContextView(fixture: fixture))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(nanoseconds: 100_000_000)
        diagnostics.clearGuidance()
        fixture.context = "epoch=render-new source=bbb target=ccc generation=6 count=19"
        try await Task.sleep(nanoseconds: 100_000_000)
        let rows = diagnostics.guidanceExport().split(separator: "\n").filter { $0.contains("\tguidance.swiftui-update\t") }
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows.last?.contains("epoch=render-new") ?? false)
        XCTAssertTrue(rows.last?.contains("generation=6 count=19") ?? false)
    }
    func testGuidanceAndMoveEvidenceSurvivePacketFloodUntilCopied() {
        let diagnostics = SmartCubeDiagnostics.shared
        diagnostics.setEnabled(true); defer { diagnostics.setEnabled(false) }
        let identity = SmartCubeRecoveryPlanIdentity(scrambleEpochID: UUID(), stateVersion: 1)
        let source = CubeSurface.solved(size: 3), target = String(source.reversed()), moveID = UUID()
        diagnostics.mark("protocol.move", id: moveID)
        diagnostics.mark("canonical.publish", id: moveID)
        diagnostics.mark("timer.consume", id: moveID)
        SmartCubeGuidanceTrace.record("canonical-receipt", identity: identity, source: source, target: target)
        for _ in 0..<4096 { diagnostics.mark("parser.begin", id: UUID()) }
        let copied = diagnostics.guidanceExport()
        XCTAssertTrue(copied.contains(String(identity.scrambleEpochID.uuidString.prefix(8))))
        for stage in ["protocol.move", "canonical.publish", "timer.consume"] {
            XCTAssertTrue(copied.contains(stage))
        }
        XCTAssertTrue(copied.contains(String(moveID.uuidString.prefix(8))))
        XCTAssertFalse(copied.contains(moveID.uuidString))
        XCTAssertFalse(copied.contains(source)); XCTAssertFalse(copied.contains(target))
        XCTAssertFalse(copied.contains("\tparser.begin\t"), "Only scalar transport counts, not packet flood rows, are retained")
        XCTAssertLessThanOrEqual(copied.split(separator: "\n").count, 2048)
    }
    func testBoundedTraceUsesPrivateDigestsAndContainsActualNativeStages() async throws {
        let diagnostics = SmartCubeDiagnostics.shared
        diagnostics.setEnabled(true)
        defer { diagnostics.setEnabled(false) }
        let identity = SmartCubeRecoveryPlanIdentity(scrambleEpochID: UUID(), stateVersion: 4)
        let target = try XCTUnwrap(SmartCubeBluetoothManager.facelets(afterApplying: "R U F L D B"))
        let source = try ["R", "U", "F", "L"].reduce(target) { try XCTUnwrap(SmartCubeBluetoothManager.facelets($0, applying: $1)) }
        let decision = await SmartCubeReplacementPlanner.currentStateDecision(identity: identity,
            sourceFacelets: source, targetFacelets: target, currentGeneration: 0, knownPath: ["L'", "F'", "U'", "R'"])
        XCTAssertNotNil(decision.replacement)
        let trace = diagnostics.guidanceExport()
        for name in ["snapshot-normalized", "native-enter", "native-primary", "native-improvement", "verified", "normalizationMS=", "waitMS="] {
            XCTAssertTrue(trace.contains(name), name)
        }
        XCTAssertTrue(trace.contains("raw=["), "Raw native notation must not be mislabeled after normalization")
        XCTAssertFalse(trace.contains(source)); XCTAssertFalse(trace.contains(target))
        XCTAssertFalse(trace.contains(identity.scrambleEpochID.uuidString))
        for _ in 0..<2100 { SmartCubeGuidanceTrace.record("bounded-fixture", identity: identity, source: source, target: target) }
        XCTAssertLessThanOrEqual(diagnostics.guidanceExport().split(separator: "\n").count, 2048)
    }
    private func view(updating: Bool, unavailable: Bool) -> some View {
        SmartCubeScrambleProgressView(scramble: "R U F", tokens: ["R", "U", "F"], completedTokenIndices: [],
            highlightedTokenIndex: 0, recoveryPlan: nil, recoveryDisplay: .separate,
            highlightAnimation: .instant, behavior: .collapse, transition: .instant,
            fontDesign: .default, fontStyle: .system(weight: .regular, isItalic: false), fontSize: 20,
            foregroundStyle: AnyShapeStyle(Color.primary), highlightBackgroundStyle: AnyShapeStyle(Color.blue),
            highlightForegroundStyle: AnyShapeStyle(Color.white), isUpdatingGuidance: updating, isGuidanceUnavailable: unavailable)
    }
    func testActualGuidanceViewNeverAddsLoadingOrUnavailablePlaceholderGeometry() {
        let limit = CGSize(width: 320, height: 1000)
        let normal = UIHostingController(rootView: view(updating: false, unavailable: false)).sizeThatFits(in: limit)
        for (updating, unavailable) in [(true, false), (false, true), (true, true)] {
            let size = UIHostingController(rootView: view(updating: updating, unavailable: unavailable)).sizeThatFits(in: limit)
            XCTAssertEqual(size.height, normal.height, accuracy: 0.01)
            XCTAssertEqual(size.width, normal.width, accuracy: 0.01)
        }
    }
    func testExportCorrelatesReceiptCandidateAndRebasedSwiftUIWithoutCrossingTargetOrDeviceEpoch() {
        let diagnostics = SmartCubeDiagnostics.shared
        diagnostics.setEnabled(true); defer { diagnostics.setEnabled(false) }
        let identity = SmartCubeRecoveryPlanIdentity(scrambleEpochID: UUID(), stateVersion: 9)
        let source = CubeSurface.solved(size: 3), target = String(source.reversed())
        SmartCubeGuidanceTrace.record("canonical-receipt", identity: identity, source: source, target: target)
        SmartCubeGuidanceTrace.record("candidate-arrived", identity: identity, source: source, target: target)
        let epoch = String(identity.scrambleEpochID.uuidString.prefix(8))
        diagnostics.mark("guidance.swiftui-update", detail: "epoch=\(epoch) revision=10 source=\(SmartCubeGuidanceTrace.digest(source)) target=\(SmartCubeGuidanceTrace.digest(target))")
        let lines = diagnostics.guidanceExport().split(separator: "\n").filter { $0.contains(epoch) }
        XCTAssertEqual(lines.filter { $0.contains("receiptElapsedMS=") }.count, 2)
        let unrelated = SmartCubeRecoveryPlanIdentity(scrambleEpochID: UUID(), stateVersion: 9)
        SmartCubeGuidanceTrace.record("candidate-arrived", identity: unrelated, source: source, target: target)
        let other = diagnostics.guidanceExport().split(separator: "\n").last
        XCTAssertFalse(other?.contains("receiptElapsedMS=") ?? true)
    }
}

@MainActor private final class GuidanceRenderContextFixture: ObservableObject {
    @Published var context = "epoch=render-old source=aaa target=ccc generation=5 count=20"
}
private struct GuidanceRenderContextView: View {
    @ObservedObject var fixture: GuidanceRenderContextFixture
    var body: some View {
        SmartCubeScrambleProgressView(scramble: "R U", tokens: ["R", "U"], completedTokenIndices: [],
            highlightedTokenIndex: 0, recoveryPlan: nil, recoveryDisplay: .inline,
            highlightAnimation: .instant, behavior: .collapse, transition: .instant,
            fontDesign: .default, fontStyle: .system(weight: .regular, isItalic: false), fontSize: 20,
            foregroundStyle: AnyShapeStyle(Color.primary), highlightBackgroundStyle: AnyShapeStyle(Color.blue),
            highlightForegroundStyle: AnyShapeStyle(Color.white), diagnosticContext: fixture.context)
    }
}
#endif

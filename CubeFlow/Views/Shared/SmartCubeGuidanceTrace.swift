#if os(iOS) && DEBUG
import Foundation

/// Scalar-only DEBUG evidence in the existing 2,048-entry ring. Facelets,
/// scramble text, names, and persistent device identifiers are not recorded.
nonisolated enum SmartCubeGuidanceTrace {
    static func digest(_ value: String) -> String {
        String(value.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }, radix: 16)
    }
    static func assignment(scramble: String, requestID: UUID) -> String {
        "scramble=\(digest(scramble)) request=\(requestID.uuidString.prefix(8))"
    }
    static func path(_ moves: [String]?) -> String {
        guard let moves else { return "none" }
        let bounded = moves.prefix(64).map { CubeLayerTurn($0)?.notation ?? "?" }.joined(separator: ",")
        return "[\(bounded)]/\(moves.count)"
    }
    static func record(_ stage: String, identity: SmartCubeRecoveryPlanIdentity, source: String,
                       target: String, detail: String = "") {
        guard SmartCubeDiagnostics.shared.enabled else { return }
        SmartCubeDiagnostics.shared.mark("guidance." + stage, id: identity.scrambleEpochID,
            detail: "revision=\(identity.stateVersion) source=\(digest(source)) target=\(digest(target)) \(detail)")
    }
    static func native(_ stage: String, identity: SmartCubeRecoveryPlanIdentity, source: String, target: String) {
        guard SmartCubeDiagnostics.shared.enabled else { return }
        // Read immediately after the synchronous call, on the same native actor
        // thread. These three scalars are thread-local, not a cross-task cache.
        let values = Min2PhaseBridge.debugSearchTiming()
        record(stage, identity: identity, source: source, target: target,
            detail: "tablesMS=\(values[0]) normalizationMS=\(values[1]) nativeMS=\(values[2])")
    }
}
#endif

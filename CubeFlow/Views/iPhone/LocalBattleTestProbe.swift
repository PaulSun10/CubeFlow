#if DEBUG && os(iOS)
import SwiftUI

@MainActor final class LocalBattleTestProbe {
    var appearanceCount = 0
    var disappearanceCount = 0
    var mode: ((LocalBattleMode) -> Void)?
    var press: ((LocalBattlePlayer) -> Void)?
    var release: ((LocalBattlePlayer) -> Void)?
    var cancel: ((LocalBattlePlayer) -> Void)?
    var snapshot: (() -> Snapshot)?
    var configure: ((LocalBattlePlayer, LocalBattleConfiguration) -> Void)?
    var manual: ((LocalBattlePlayer, String) -> Bool)?
    var selectorOpen: ((LocalBattlePlayer) -> Void)?
    var selectorDismiss: (() -> Void)?
    var selectorChoose: ((PuzzleEvent) -> Void)?
    var selectorSnapshot: (() -> LocalBattlePlayer?)?
    var selectorCanOpen: ((LocalBattlePlayer) -> Bool)?
    var overrideReduceMotion: Bool?
    struct Snapshot {
        let scrambles: LocalBattleScrambleState
        let firstStart: Date?
        let secondStart: Date?
        let firstPressing: Bool
        let secondPressing: Bool
        let ready: Set<LocalBattlePlayer>
    }
}
private struct LocalBattleTestProbeKey: EnvironmentKey {
    static let defaultValue: LocalBattleTestProbe? = nil
}
extension EnvironmentValues {
    var localBattleTestProbe: LocalBattleTestProbe? {
        get { self[LocalBattleTestProbeKey.self] }
        set { self[LocalBattleTestProbeKey.self] = newValue }
    }
}
#endif

import SwiftUI

#if os(iOS)
enum LocalBattleMode: String, CaseIterable, Identifiable {
    case solo
    case headToHead
    case sideBySide
    case nearby

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .solo:
            return "timer.battle.mode.solo"
        case .headToHead:
            return "timer.battle.mode.head_to_head"
        case .sideBySide:
            return "timer.battle.mode.side_by_side"
        case .nearby:
            return "timer.battle.mode.nearby"
        }
    }

    var iconName: String {
        switch self {
        case .solo:
            return "person.fill"
        case .headToHead:
            return "person.2.fill"
        case .sideBySide:
            return "rectangle.split.2x1.fill"
        case .nearby:
            return "person.2.wave.2.fill"
        }
    }
}

enum LocalBattlePlayer: CaseIterable, Hashable {
    case first
    case second

    var titleKey: LocalizedStringKey {
        switch self {
        case .first:
            return "timer.battle.player_one"
        case .second:
            return "timer.battle.player_two"
        }
    }
}

struct LocalBattleModeMenu: View {
    let mode: LocalBattleMode
    let onSelectMode: (LocalBattleMode) -> Void

    var body: some View {
        Menu {
            Picker("", selection: Binding(
                get: { mode },
                set: { onSelectMode($0) }
            )) {
                ForEach(LocalBattleMode.allCases) { menuMode in
                    Label(menuMode.titleKey, systemImage: menuMode.iconName)
                        .tag(menuMode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 15, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .compatibleGlassFromIOS16(in: Capsule())
        }
        .tint(.primary)
        .buttonStyle(.plain)
    }
}

struct LocalBattleContent: View {
    let mode: LocalBattleMode
    let firstEvent: PuzzleEvent
    let secondEvent: PuzzleEvent
    let firstScramble: String
    let secondScramble: String
    let firstElapsed: Double
    let secondElapsed: Double
    let isFirstRunning: Bool
    let isSecondRunning: Bool
    let isFirstPressing: Bool
    let isSecondPressing: Bool
    let firstScore: Int
    let secondScore: Int
    let firstHandicapSeconds: Int
    let secondHandicapSeconds: Int
    let firstFinishedTime: Double?
    let secondFinishedTime: Double?
    let timerTextStyle: AnyShapeStyle
    let scrambleTextStyle: AnyShapeStyle
    let formatDisplayedTime: (Double) -> String
    let onExit: () -> Void
    let onSelectEvent: (LocalBattlePlayer, PuzzleEvent) -> Void
    let onSelectHandicap: (LocalBattlePlayer, Int) -> Void
    let onPressPlayer: (LocalBattlePlayer) -> Void
    let onReleasePlayer: (LocalBattlePlayer) -> Void

    @State private var activePressPlayers: Set<LocalBattlePlayer> = []

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Group {
                    switch mode {
                    case .solo:
                        EmptyView()
                    case .nearby:
                        EmptyView()
                    case .headToHead:
                        VStack(spacing: 1) {
                            panel(for: .second)
                                .rotationEffect(.degrees(180))
                            divider
                            panel(for: .first, reservesExitZone: true)
                        }
                    case .sideBySide:
                        HStack(spacing: 1) {
                            panel(for: .first, reservesExitZone: true)
                            divider
                            panel(for: .second)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)

                exitButton
            }
        }
    }

    private var exitButton: some View {
        Button(action: onExit) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .padding(13)
                .compatibleGlassFromIOS16(in: Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 92, height: 92, alignment: .center)
        .contentShape(Rectangle())
        .zIndex(20)
    }

    private var divider: some View {
        Rectangle()
            .fill(.secondary.opacity(0.22))
            .frame(maxWidth: mode == .sideBySide ? 1 : .infinity, maxHeight: mode == .headToHead ? 1 : .infinity)
    }

    private func panel(for player: LocalBattlePlayer, reservesExitZone: Bool = false) -> some View {
        let scramble = scramble(for: player)
        let event = event(for: player)
        let handicap = handicapSeconds(for: player)
        let opponentHandicap = handicapSeconds(for: opponent(of: player))
        let playerElapsed = elapsed(for: player)
        let playerIsRunning = isRunning(player)
        let playerIsPressing = isPressing(player)
        let opponentPlayer = opponent(of: player)
        let opponentElapsed = elapsed(for: opponentPlayer)
        let opponentIsRunning = isRunning(opponentPlayer)
        let shouldShowOpponentTime = firstFinishedTime != nil || secondFinishedTime != nil
        let canChangeEvent = !playerIsRunning && !playerIsPressing

        return GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 18) {
                    ZStack {
                        localBattleEventPicker(
                            event: event,
                            isEnabled: canChangeEvent,
                            onSelect: { onSelectEvent(player, $0) }
                        )

                        HStack {
                            Text(player.titleKey)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Spacer(minLength: 84)

                            Text(scoreText(for: player))
                                .font(.system(size: 28, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }

                    Text(scramble)
                        .font(.system(size: 18, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(scrambleTextStyle)
                        .lineLimit(4)
                        .minimumScaleFactor(0.58)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 0)

                    Text(formatDisplayedTime(playerElapsed))
                        .font(.system(size: 58, weight: playerIsRunning ? .bold : .semibold))
                        .monospacedDigit()
                        .foregroundStyle((playerIsRunning || playerIsPressing) ? AnyShapeStyle(Color.green) : timerTextStyle)
                        .minimumScaleFactor(0.48)
                        .lineLimit(1)

                    if shouldShowOpponentTime {
                        Text(opponentTimeText(seconds: opponentElapsed))
                            .font(.system(size: 14, weight: opponentIsRunning ? .semibold : .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(opponentIsRunning ? AnyShapeStyle(Color.green.opacity(0.85)) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                localBattleHandicapPicker(
                    seconds: handicap,
                    opponentSeconds: opponentHandicap,
                    isEnabled: canChangeEvent,
                    onSelect: { onSelectHandicap(player, $0) }
                )
                .padding(.trailing, 22)
                .padding(.bottom, -2)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let isInExitZone = reservesExitZone
                            && value.location.x <= 92
                            && value.location.y >= proxy.size.height - 92
                        guard !isInExitZone else { return }
                        guard !activePressPlayers.contains(player) else { return }
                        activePressPlayers.insert(player)
                        onPressPlayer(player)
                    }
                    .onEnded { value in
                        let isInExitZone = reservesExitZone
                            && value.location.x <= 92
                            && value.location.y >= proxy.size.height - 92
                        activePressPlayers.remove(player)
                        guard !isInExitZone else { return }
                        onReleasePlayer(player)
                    }
            )
        }
    }

    private func scramble(for player: LocalBattlePlayer) -> String {
        switch player {
        case .first:
            return firstScramble
        case .second:
            return secondScramble
        }
    }

    private func event(for player: LocalBattlePlayer) -> PuzzleEvent {
        switch player {
        case .first:
            return firstEvent
        case .second:
            return secondEvent
        }
    }

    private func elapsed(for player: LocalBattlePlayer) -> Double {
        switch player {
        case .first:
            return firstElapsed
        case .second:
            return secondElapsed
        }
    }

    private func isRunning(_ player: LocalBattlePlayer) -> Bool {
        switch player {
        case .first:
            return isFirstRunning
        case .second:
            return isSecondRunning
        }
    }

    private func isPressing(_ player: LocalBattlePlayer) -> Bool {
        switch player {
        case .first:
            return isFirstPressing
        case .second:
            return isSecondPressing
        }
    }

    private func score(for player: LocalBattlePlayer) -> Int {
        switch player {
        case .first:
            return firstScore
        case .second:
            return secondScore
        }
    }

    private func handicapSeconds(for player: LocalBattlePlayer) -> Int {
        switch player {
        case .first:
            return firstHandicapSeconds
        case .second:
            return secondHandicapSeconds
        }
    }

    private func scoreText(for player: LocalBattlePlayer) -> String {
        let currentScore = score(for: player)
        let opponentScore = score(for: opponent(of: player))
        let prefix = currentScore > opponentScore ? "🏆" : ""
        return "\(prefix)\(currentScore)"
    }

    private func roundTime(for player: LocalBattlePlayer) -> Double? {
        switch player {
        case .first:
            return firstFinishedTime
        case .second:
            return secondFinishedTime
        }
    }

    private func opponent(of player: LocalBattlePlayer) -> LocalBattlePlayer {
        switch player {
        case .first:
            return .second
        case .second:
            return .first
        }
    }

    private func opponentTimeText(seconds: Double) -> String {
        "⚔️ \(formatDisplayedTime(seconds))"
    }

    private func handicapText(_ seconds: Int) -> String {
        seconds == 0 ? "让秒" : "让\(seconds)秒"
    }

    private func localBattleEventPicker(event: PuzzleEvent, isEnabled: Bool, onSelect: @escaping (PuzzleEvent) -> Void) -> some View {
        Menu {
            ForEach(PuzzleEvent.regularCases, id: \.self) { event in
                Button(LocalizedStringKey(event.localizationKey)) {
                    onSelect(event)
                }
            }

            Menu("timer.menu.bld") {
                ForEach(PuzzleEvent.blindfoldedCases, id: \.self) { event in
                    Button(LocalizedStringKey(event.localizationKey)) {
                        onSelect(event)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(LocalizedStringKey(event.localizationKey))
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .compatibleGlassFromIOS16(in: Capsule())
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .tint(.primary)
        .buttonStyle(.plain)
    }

    private func localBattleHandicapPicker(seconds: Int, opponentSeconds: Int, isEnabled: Bool, onSelect: @escaping (Int) -> Void) -> some View {
        Menu {
            ForEach(0...10, id: \.self) { seconds in
                Button(handicapText(seconds)) {
                    onSelect(seconds)
                }
            }
        } label: {
            Text(handicapDisplayText(seconds: seconds, opponentSeconds: opponentSeconds))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .compatibleGlassFromIOS16(in: Capsule())
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .tint(.primary)
        .buttonStyle(.plain)
    }

    private func handicapDisplayText(seconds: Int, opponentSeconds: Int) -> String {
        if seconds > 0 {
            return handicapText(seconds)
        }
        if opponentSeconds > 0 {
            return "对方让你\(opponentSeconds)秒"
        }
        return handicapText(seconds)
    }
}
#endif

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

enum LocalBattlePlayer: CaseIterable, Hashable, Identifiable {
    case first
    case second
    var id: Self { self }

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
    let canSelectEvent: (LocalBattlePlayer) -> Bool
    let onExit: () -> Void
    let onSelectEvent: (LocalBattlePlayer, PuzzleEvent) -> Void
    let onSelectHandicap: (LocalBattlePlayer, Int) -> Void
    let onPressPlayer: (LocalBattlePlayer) -> Void
    let onReleasePlayer: (LocalBattlePlayer) -> Void
    let onCancelPlayer: (LocalBattlePlayer) -> Void
    @ObservedObject var devices = LocalBattleDevices()
    var onConfigure: ((LocalBattlePlayer, LocalBattleConfiguration) -> Void)? = nil
    var onManual: ((LocalBattlePlayer, String) -> Bool)? = nil
    var isRoundComplete = false
    var canEditHandicap = true

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var selectingEventFor: LocalBattlePlayer?
    @State private var configuringPlayers: Set<LocalBattlePlayer> = []
    @State private var manualEntries: [LocalBattlePlayer: String] = [:]
    @State private var connectingPlayer: LocalBattlePlayer?
    @State private var showingSmartTimer = false
    #if DEBUG
    @Environment(\.localBattleTestProbe) private var selectorProbe
    #endif

    @State private var activePressPlayers: Set<LocalBattlePlayer> = []

    private var reduceMotion: Bool {
        #if DEBUG
        if let value = selectorProbe?.overrideReduceMotion { return value }
        #endif
        return systemReduceMotion
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                playerLayout(size: proxy.size, showsDivider: true, content: panel(for:))

                playerDimming(size: proxy.size, safeArea: proxy.safeAreaInsets)

                playerLayout(size: proxy.size, showsDivider: false) { player in
                    GeometryReader { panel in
                        configurationControl(player, size: panel.size,
                            selectorY: panel.size.width < 280 ? 80 : 34, expanded: configuringPlayers.contains(player))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }

                if configuringPlayers.isEmpty { exitButton(safeArea: proxy.safeAreaInsets) }
            }
        }
        .onChange(of: mode) { _ in selectingEventFor = nil; configuringPlayers = [] }
        .onChange(of: [isFirstRunning, isSecondRunning, isFirstPressing, isSecondPressing]) { _ in
            #if DEBUG
            configureSelectorProbe()
            #endif
        }
        #if DEBUG
        .onAppear(perform: configureSelectorProbe)
        .onChange(of: mode) { _ in configureSelectorProbe() }
        #endif
        .sheet(item: $connectingPlayer) { player in
            SmartCubeDevicePickerView(manager: .shared, onConnectionApproved: { attempt in
                guard let id = SmartCubeBluetoothManager.shared.session(attemptID: attempt)?.connectionDeviceID else { return }
                var configuration = devices.configuration(player); configuration.deviceID = id
                onConfigure?(player, configuration); connectingPlayer = nil
            })
        }
        .sheet(isPresented: $showingSmartTimer) {
            CompatibleNavigationContainer {
                SmartTimerDeviceView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("common.done") { showingSmartTimer = false }
                        }
                    }
            }
        }
    }

    private func playerDimming(size: CGSize, safeArea: EdgeInsets) -> some View {
        Group {
            if mode == .headToHead {
                VStack(spacing: 0) {
                    playerBackdrop(.second).frame(height: safeArea.top + size.height / 2)
                    playerBackdrop(.first).frame(maxHeight: .infinity)
                }
            } else if mode == .sideBySide {
                HStack(spacing: 0) {
                    playerBackdrop(.first).frame(width: safeArea.leading + size.width / 2)
                    playerBackdrop(.second).frame(maxWidth: .infinity)
                }
            }
        }
        .ignoresSafeArea(.container)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func playerBackdrop(_ player: LocalBattlePlayer) -> some View {
        Color.clear.overlay {
            if configuringPlayers.contains(player) {
                CompetitionResultBackdrop().transition(reduceMotion ? .identity : .opacity)
            }
        }
    }

    @ViewBuilder
    private func playerLayout<Content: View>(size: CGSize, showsDivider: Bool,
        @ViewBuilder content: (LocalBattlePlayer) -> Content) -> some View {
        switch mode {
        case .solo, .nearby: EmptyView()
        case .headToHead:
            VStack(spacing: 0) {
                content(.second).rotationEffect(.degrees(BattleEventSelectorPolicy.rotation(player: .second, mode: mode)))
                    .frame(height: max(0, (size.height - 1) / 2))
                divider.opacity(showsDivider ? 1 : 0).allowsHitTesting(false)
                content(.first).frame(height: max(0, (size.height - 1) / 2))
            }
            .frame(width: size.width, height: size.height)
        case .sideBySide:
            HStack(spacing: 0) {
                content(.first).frame(width: max(0, (size.width - 1) / 2))
                divider.opacity(showsDivider ? 1 : 0).allowsHitTesting(false)
                content(.second).frame(width: max(0, (size.width - 1) / 2))
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private func openEventSelector(for player: LocalBattlePlayer) {
        guard canSelectEvent(player) else { return }
        selectingEventFor = player
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { _ = configuringPlayers.insert(player) }
    }

    private func chooseEvent(_ event: PuzzleEvent, for player: LocalBattlePlayer) {
        guard configuringPlayers.contains(player), canSelectEvent(player),
              BattleEventSelectorPolicy.events.contains(event) else { return }
        onSelectEvent(player, event)
    }

    private func closeConfiguration(_ player: LocalBattlePlayer) {
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.16)) { _ = configuringPlayers.remove(player) }
        if selectingEventFor == player { selectingEventFor = nil }
    }

    #if DEBUG
    private func configureSelectorProbe() {
        selectorProbe?.selectorOpen = openEventSelector
        selectorProbe?.selectorDismiss = { if let player = selectingEventFor { closeConfiguration(player) } }
        selectorProbe?.selectorChoose = { event in
            if let player = selectingEventFor { chooseEvent(event, for: player) }
        }
        selectorProbe?.selectorSnapshot = { selectingEventFor }
        selectorProbe?.selectorCanOpen = canSelectEvent
    }
    #endif

    private func exitButton(safeArea: EdgeInsets) -> some View {
        // UIKit does not expose the physical display corner radius. Equal
        // distances from the two screen edges keep the circle on the diagonal.
        // The 48 pt control's center remains well inside the safe area.
        let inset = max(6, max(safeArea.leading, safeArea.bottom) - 3)
        return CompetitionResultCardCloseButton(label: String(localized: "common.done"), action: onExit,
            glassDiameter: 48, glyphSize: 22)
            .padding(.leading, inset - safeArea.leading)
            .padding(.bottom, inset - safeArea.bottom)
            .zIndex(20)
    }

    private var divider: some View {
        Rectangle()
            .fill(.secondary.opacity(0.22))
            .frame(maxWidth: mode == .sideBySide ? 1 : .infinity, maxHeight: mode == .headToHead ? 1 : .infinity)
    }

    private func panel(for player: LocalBattlePlayer) -> some View {
        GeometryReader { proxy in
            let configuration = devices.configuration(player)
            let expanded = configuringPlayers.contains(player)
            let timerY = proxy.size.height * 0.58
            let narrow = proxy.size.width < 280
            let scrambleTop: CGFloat = narrow ? 112 : 68
            let scrambleBottom = max(scrambleTop, timerY - 58)
            ZStack {
                if configuration.input == .touch {
                    BattleContactSurface { down, cancelled in
                        var transaction = Transaction(); transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            if down { activePressPlayers.insert(player); onPressPlayer(player) }
                            else {
                                activePressPlayers.remove(player)
                                if cancelled { onCancelPlayer(player) } else { onReleasePlayer(player) }
                            }
                        }
                    }
                }
                ZStack {
                    HStack {
                        Text(player.titleKey).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Spacer(minLength: narrow ? 4 : 84)
                        Text(scoreText(for: player)).font(.system(size: 28, weight: .bold)).monospacedDigit()
                            .fixedSize()
                    }.allowsHitTesting(false)
                }
                .frame(width: max(0, proxy.size.width - 44), height: 44)
                .position(x: proxy.size.width / 2, y: 34)

                TimerFittingScrambleText(text: scramble(for: player), maximumFontSize: 19,
                    design: .default, style: .system(weight: .regular, isItalic: false)) { fontSize in
                    Text(scramble(for: player)).font(.system(size: fontSize, weight: .medium))
                        .foregroundStyle(scrambleTextStyle).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: max(0, proxy.size.width - 32), height: max(0, scrambleBottom - scrambleTop))
                .position(x: proxy.size.width / 2, y: (scrambleTop + scrambleBottom) / 2)
                .allowsHitTesting(false)

                Group {
                    if configuration.input == .manual {
                        HStack(spacing: 8) {
                            TextField("manual.enter_time", text: Binding(get: { manualEntries[player] ?? "" },
                                set: { manualEntries[player] = $0 }))
                                .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.center)
                                .font(.system(size: 32, weight: .medium, design: .rounded).monospacedDigit())
                                .submitLabel(.done).onSubmit { saveManual(player) }
                            Button("timer.typing_save") { saveManual(player) }.frame(minWidth: 44, minHeight: 44)
                                .disabled(roundTime(for: player) != nil && !isRoundComplete)
                        }.padding(.horizontal, 16)
                    } else {
                        Text(formatDisplayedTime(displayedTime(for: player)))
                            .font(.system(size: 58, weight: isRunning(player) ? .bold : .semibold))
                            .monospacedDigit().foregroundStyle(activePressPlayers.contains(player) ? AnyShapeStyle(Color.green) : timerTextStyle)
                            .minimumScaleFactor(0.4).lineLimit(1).allowsHitTesting(false)
                    }
                }
                .frame(width: max(0, proxy.size.width - 32), height: 92)
                .position(x: proxy.size.width / 2, y: timerY)
                .accessibilityIdentifier("battle-timer-\(player == .first ? "first" : "second")")

                if let session = devices.session(for: player) {
                    let side = min(120, proxy.size.width * 0.45, proxy.size.height * 0.23)
                    LocalBattleCubeModel(session: session, player: player)
                        .frame(width: side, height: side)
                        .position(x: proxy.size.width / 2, y: min(proxy.size.height - 70, timerY + 105))
                }
                VStack(spacing: 4) {
                    if configuration.input == .smartCube {
                        if devices.ready.contains(player) {
                            Label("battle.ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else if devices.session(for: player) == nil {
                            Image(systemName: "bolt.horizontal.circle")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(Text("smart_cube.status.disconnected"))
                        }
                    } else if configuration.input != .touch {
                        Text(LocalizedStringKey(configuration.input.key))
                            .foregroundStyle(.secondary)
                    }
                    if firstFinishedTime != nil || secondFinishedTime != nil {
                        Text(opponentTimeText(seconds: displayedTime(for: opponent(of: player)))).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .font(.caption).frame(width: max(0, proxy.size.width - 32), height: 44)
                .position(x: proxy.size.width / 2, y: configuration.input == .smartCube ? proxy.size.height - 24 : min(proxy.size.height - 24, timerY + 76))
                .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .allowsHitTesting(!expanded)
            .accessibilityHidden(expanded)
        }
    }

    private func saveManual(_ player: LocalBattlePlayer) {
        if onManual?(player, manualEntries[player] ?? "") == true { manualEntries[player] = "" }
    }

    @ViewBuilder
    private func configurationControl(_ player: LocalBattlePlayer, size: CGSize, selectorY: CGFloat, expanded: Bool) -> some View {
        let control = localBattleEventPicker(player: player, event: event(for: player), isEnabled: canSelectEvent(player))
        if expanded {
            configurationPanel(player, size: size)
                .competitionResultCardSurface()
                .competitionResultCardShadow()
                .transition(reduceMotion ? .identity : .scale(scale: 0.97).combined(with: .opacity))
            .frame(width: size.width, height: size.height)
        } else if #available(iOS 26.0, *) {
            control.glassEffect(.regular.interactive(), in: Capsule())
                .padding(.top, selectorY - 16)
        } else {
            control.compatibleGlassFromIOS16(in: Capsule())
                .padding(.top, selectorY - 16)
        }
    }

    private func configurationPanel(_ player: LocalBattlePlayer, size: CGSize) -> some View {
        let inset = CompetitionResultCardTitleStyle.contentInset
        let width = max(0, min(CompetitionResultCardGeometry.width(in: size), size.width - 24))
        let height = max(0, min(CompetitionResultCardGeometry.maximumHeight(in: size), size.height - 24))
        return Group {
            if #available(iOS 16.0, *) {
                ViewThatFits(in: .vertical) {
                    configurationBody(player, scrolls: false).fixedSize(horizontal: false, vertical: true)
                    configurationBody(player, scrolls: true)
                }
            } else {
                configurationBody(player, scrolls: true)
            }
        }
        .padding(inset)
        .frame(width: width, alignment: .topLeading)
        .frame(maxHeight: height)
        .overlay(alignment: .topTrailing) {
            CompetitionResultCardCloseButton(label: String(localized: "common.done")) { closeConfiguration(player) }
                .accessibilityIdentifier(player == .first ? "battle-settings-close-first" : "battle-settings-close-second")
                .padding(CompetitionResultShareActionLayout.inset)
        }
    }

    private func configurationBody(_ player: LocalBattlePlayer, scrolls: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(player.titleKey)
                .modifier(CompetitionResultCardTitleStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
            if scrolls {
                ScrollView { configurationOptions(player) }
            } else {
                configurationOptions(player)
            }
        }
    }

    private func configurationOptions(_ player: LocalBattlePlayer) -> some View {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("battle.input").foregroundStyle(.primary)
                            Spacer(minLength: 4)
                        Menu {
                            Picker("battle.input", selection: Binding(get: { devices.configuration(player).input }, set: { input in
                                guard availableInputs(for: player).contains(input) else { return }
                                var value = devices.configuration(player); value.input = input; onConfigure?(player, value)
                            })) {
                                ForEach(availableInputs(for: player)) { input in
                                    Text(LocalizedStringKey(input.key)).tag(input)
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(LocalizedStringKey(devices.configuration(player).input.key)).foregroundStyle(.secondary)
                                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .font(.subheadline)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .tint(.primary)
                        .accessibilityHint(Text("battle.input"))
                        .disabled(!canSelectEvent(player))
                        }
                        .font(.subheadline)
                        .overlay(alignment: .bottom) { Divider() }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 38), spacing: 4)], spacing: 4) {
                            ForEach(BattleEventSelectorPolicy.events, id: \.self) { event in
                                Button { chooseEvent(event, for: player) } label: {
                                    Group {
                                        if let glyph = CompetitionEventIconFont.glyph(for: event.cubingEventID) {
                                            CompetitionEventInkGlyph(glyph: glyph)
                                        } else { Text(event.rawValue).font(.caption2) }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                                    .background(event == self.event(for: player) ? Color.primary.opacity(0.10) : .clear,
                                        in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringKey(event.localizationKey)))
                                    .accessibilityAddTraits(event == self.event(for: player) ? .isSelected : [])
                                    .accessibilityIdentifier("battle-event-\(event.rawValue)")
                            }
                        }
                        .disabled(!canSelectEvent(player))
                        if devices.configuration(player).input == .smartCube {
                            Menu {
                                ForEach(devices.devices(for: event(for: player), player: player), id: \.self) { id in
                                    Button(devices.deviceName(id)) {
                                        var value = devices.configuration(player); value.deviceID = id; onConfigure?(player, value)
                                    }
                                }
                                Button("smart_cube.devices") { connectingPlayer = player }
                            } label: {
                                Label(devices.configuration(player).deviceID.map(devices.deviceName) ?? String(localized: "smart_cube.devices"), systemImage: "cube")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                        }
                        if devices.configuration(player).input == .manual {
                            Picker("manual.fixed_format", selection: Binding(get: { devices.configuration(player).format }, set: { format in
                                var value = devices.configuration(player); value.format = format; onConfigure?(player, value)
                            })) { ForEach(ManualTimeFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        }
                        if devices.configuration(player).input == .smartTimer {
                            Button { showingSmartTimer = true } label: {
                                Label("connected_devices.smart_timer", systemImage: "stopwatch")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                        }
                        Stepper(value: Binding(get: { handicapSeconds(for: player) },
                                               set: { onSelectHandicap(player, $0) }), in: -10...10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("battle.handicap").font(.caption).foregroundStyle(.secondary)
                                Text(handicapSeconds(for: player).formatted(.number.sign(strategy: .always(includingZero: false))) + " s")
                                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                            }
                        }.frame(minHeight: 44)
                        .disabled(!canEditHandicap)
                    }
    }

    private func availableInputs(for player: LocalBattlePlayer) -> [LocalBattleInput] {
        LocalBattleInput.allCases.filter { input in
            switch input {
            case .smartCube: devices.canUseSmartCube(event(for: player))
            case .smartTimer: devices.canUseSmartTimer(for: player)
            case .touch, .manual: true
            }
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

    private func displayedTime(for player: LocalBattlePlayer) -> Double {
        isRunning(player) ? elapsed(for: player) : roundTime(for: player) ?? elapsed(for: player)
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

    private func localBattleEventPicker(player: LocalBattlePlayer, event: PuzzleEvent, isEnabled: Bool) -> some View {
        Button { openEventSelector(for: player) } label: {
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
        }
        .disabled(!isEnabled)
        .accessibilityIdentifier("battle-event-trigger-\(player == .first ? "first" : "second")")
        .opacity(isEnabled ? 1 : 0.55)
        .tint(.primary)
        .buttonStyle(.plain)
    }

}

private struct LocalBattleCubeModel: View {
    @ObservedObject var session: SmartCubePeripheralSession
    let player: LocalBattlePlayer
    @AppStorage("smartCubeFixedView") private var fixedView = SmartCubeFixedView.urf.rawValue
    var body: some View {
        SmartCube3DView(facelets: session.weiPo2VisualFacelets ?? session.facelets,
            stateRevision: session.cubeStateRevision,
            fixedView: SmartCubeFixedView(rawValue: fixedView) ?? .urf, cubeSize: session.puzzleSize,
            events: session.canonicalEvents, connectionAttemptID: session.connectionAttemptID,
            isStateTrusted: session.hasTrustedCanonicalState, diagnosticOwner: "battle-\(player)",
            canonicalSequence: session.canonicalSequence)
            .accessibilityIdentifier("battle-cube-\(player == .first ? "first" : "second")")
    }
}

#endif

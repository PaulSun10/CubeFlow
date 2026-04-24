import SwiftUI
import MultipeerConnectivity

#if os(iOS)
struct NearbyBattleView: View {
    @ObservedObject var manager: NearbyBattleManager

    let selectedEvent: PuzzleEvent
    let timerTextStyle: AnyShapeStyle
    let scrambleTextStyle: AnyShapeStyle
    let formatDisplayedTime: (Double) -> String
    let generateScramble: () -> String
    let onExit: () -> Void

    @State private var roundID: String?
    @State private var scramble = ""
    @State private var localElapsed: Double = 0
    @State private var localStartDate: Date?
    @State private var isLocalRunning = false
    @State private var isLocalPressing = false
    @State private var isRemotePressing = false
    @State private var localFinishedTime: Double?
    @State private var remoteLiveTime: Double?
    @State private var isRemoteRunning = false
    @State private var remoteFinishedTime: Double?
    @State private var hostScore = 0
    @State private var guestScore = 0
    @State private var didScoreRound = false
    @State private var displayTimer: Timer?
    @State private var lastLiveTimeSentAt: Date?
    @State private var isTouchActive = false

    private var isHost: Bool {
        manager.role == .host
    }

    private var myScore: Int {
        isHost ? hostScore : guestScore
    }

    private var opponentScore: Int {
        isHost ? guestScore : hostScore
    }

    private var displayedScramble: String {
        scramble.isEmpty ? "…" : scramble
    }

    private var opponentDisplayedTime: Double? {
        guard localFinishedTime != nil || remoteFinishedTime != nil else { return nil }
        return remoteFinishedTime ?? remoteLiveTime
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            exitButton
        }
        .onDisappear {
            invalidateTimer()
        }
        .onChange(of: manager.phase) { phase in
            if phase == .connected, isHost, roundID == nil {
                startNewHostRound()
            }
        }
        .onChange(of: manager.receivedMessage) { received in
            guard let received else { return }
            handle(received.message)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch manager.phase {
        case .idle:
            connectionSetup
        case .hosting, .browsing, .connecting:
            connectionProgress
        case .connected:
            battleContent
                .onAppear {
                    if isHost, roundID == nil {
                        startNewHostRound()
                    }
                }
        case .failed(let message):
            connectionError(message)
        }
    }

    private var connectionSetup: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("timer.battle.nearby.title")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text("timer.battle.nearby.subtitle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button {
                    resetRoundState()
                    manager.startHosting()
                } label: {
                    Label("timer.battle.nearby.host", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .compatibleProminentButtonFromIOS16(tint: .blue)

                Button {
                    resetRoundState()
                    manager.startBrowsing()
                } label: {
                    Label("timer.battle.nearby.join", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: 320)
        }
        .padding(28)
    }

    private var connectionProgress: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)

            Text(connectionStatusTitle)
                .font(.system(size: 24, weight: .bold, design: .rounded))

            if manager.phase == .browsing {
                peerList
            } else {
                Text(connectionStatusSubtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("common.cancel") {
                manager.stop()
            }
            .buttonStyle(.bordered)
        }
        .padding(28)
    }

    private var peerList: some View {
        VStack(spacing: 10) {
            if manager.availablePeers.isEmpty {
                Text("timer.battle.nearby.searching")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            } else {
                ForEach(manager.availablePeers) { peer in
                    Button {
                        manager.invite(peer)
                    } label: {
                        HStack {
                            Image(systemName: "iphone")
                            Text(peer.displayName)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 340)
    }

    private func connectionError(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.orange)

            Text("timer.battle.nearby.failed")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("timer.battle.nearby.host") {
                    resetRoundState()
                    manager.startHosting()
                }
                .buttonStyle(.bordered)

                Button("timer.battle.nearby.join") {
                    resetRoundState()
                    manager.startBrowsing()
                }
                .compatibleProminentButtonFromIOS16(tint: .blue)
            }
        }
        .padding(28)
    }

    private var battleContent: some View {
        GeometryReader { proxy in
            VStack(spacing: 18) {
                header

                Text(displayedScramble)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(scrambleTextStyle)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 0)

                Text(formatDisplayedTime(localElapsed))
                    .font(.system(size: 64, weight: isLocalRunning ? .bold : .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle((isLocalRunning || isLocalPressing) ? AnyShapeStyle(Color.green) : timerTextStyle)
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)

                if let localFinishedTime {
                    Text(String(format: "timer.battle.nearby.your_time_format".localized, formatDisplayedTime(localFinishedTime)))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if let remoteFinishedTime {
                    Text(String(format: "timer.battle.nearby.opponent_time_format".localized, formatDisplayedTime(remoteFinishedTime)))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else if let opponentDisplayedTime {
                    Text(String(format: "timer.battle.nearby.opponent_time_format".localized, formatDisplayedTime(opponentDisplayedTime)))
                        .font(.system(size: 14, weight: isRemoteRunning ? .semibold : .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isRemoteRunning ? AnyShapeStyle(Color.green.opacity(0.85)) : AnyShapeStyle(.secondary))
                }

                if isHost, didScoreRound {
                    Button {
                        startNewHostRound()
                    } label: {
                        Label("timer.battle.nearby.next_round", systemImage: "arrow.clockwise")
                    }
                    .compatibleProminentButtonFromIOS16(tint: .blue)
                } else if !isHost, didScoreRound {
                    Text("timer.battle.nearby.waiting_next")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let isInExitZone = value.location.x <= 92 && value.location.y >= proxy.size.height - 92
                        guard !isInExitZone else { return }
                        guard !isTouchActive else { return }
                        isTouchActive = true
                        pressLocalTimer()
                    }
                    .onEnded { value in
                        let isInExitZone = value.location.x <= 92 && value.location.y >= proxy.size.height - 92
                        isTouchActive = false
                        guard !isInExitZone else { return }
                        releaseLocalTimer()
                    }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            scoreColumn(title: "timer.battle.nearby.you", score: myScore)

            VStack(spacing: 2) {
                Text("timer.battle.nearby.vs")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)

                if let connectedPeerName = manager.connectedPeerName {
                    Text(connectedPeerName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            scoreColumn(title: "timer.battle.nearby.opponent", score: opponentScore)
        }
    }

    private func scoreColumn(title: LocalizedStringKey, score: Int) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("\(score)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private var exitButton: some View {
        Button {
            manager.stop()
            onExit()
        } label: {
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

    private var connectionStatusTitle: LocalizedStringKey {
        switch manager.phase {
        case .hosting:
            return "timer.battle.nearby.hosting"
        case .browsing:
            return "timer.battle.nearby.devices"
        case .connecting:
            return "timer.battle.nearby.connecting"
        default:
            return "timer.battle.nearby.title"
        }
    }

    private var connectionStatusSubtitle: LocalizedStringKey {
        switch manager.phase {
        case .hosting:
            return "timer.battle.nearby.hosting_subtitle"
        case .connecting:
            return "timer.battle.nearby.connecting_subtitle"
        default:
            return "timer.battle.nearby.subtitle"
        }
    }

    private var remoteHasStartedOrFinished: Bool {
        isRemoteRunning || remoteLiveTime != nil || remoteFinishedTime != nil
    }

    private func pressLocalTimer() {
        guard manager.phase == .connected, roundID != nil, !didScoreRound else { return }
        guard !isLocalRunning, localFinishedTime == nil, !isLocalPressing else { return }
        isLocalPressing = true
        sendReadyState(isReady: true)
    }

    private func releaseLocalTimer() {
        guard manager.phase == .connected, roundID != nil, !didScoreRound else { return }
        if isLocalRunning {
            stopLocalTimer()
            return
        }

        guard isLocalPressing, localFinishedTime == nil else { return }
        let canStart = isRemotePressing || remoteHasStartedOrFinished
        isLocalPressing = false
        sendReadyState(isReady: false)
        guard canStart else { return }
        startLocalTimer()
    }

    private func startLocalTimer() {
        localElapsed = 0
        localStartDate = .now
        isLocalRunning = true
        sendLiveTimeIfNeeded(force: true)
        startDisplayTimerIfNeeded()
    }

    private func stopLocalTimer() {
        guard isLocalRunning else { return }
        if let localStartDate {
            localElapsed = Date().timeIntervalSince(localStartDate)
        }
        isLocalRunning = false
        isLocalPressing = false
        self.localStartDate = nil
        localFinishedTime = localElapsed
        invalidateTimer()

        if let roundID {
            manager.send(.liveTime(roundID: roundID, seconds: localElapsed), mode: .unreliable)
            manager.send(.solveFinished(roundID: roundID, seconds: localElapsed))
        }
        scoreRoundIfNeeded()
    }

    private func startDisplayTimerIfNeeded() {
        guard displayTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
            if let localStartDate, isLocalRunning {
                localElapsed = Date().timeIntervalSince(localStartDate)
                sendLiveTimeIfNeeded()
            }
            if !isLocalRunning {
                displayTimer?.invalidate()
                displayTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func invalidateTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
        localStartDate = nil
        isLocalRunning = false
        isLocalPressing = false
        isTouchActive = false
        lastLiveTimeSentAt = nil
    }

    private func startNewHostRound() {
        guard isHost else { return }
        let newRoundID = UUID().uuidString
        roundID = newRoundID
        scramble = generateScramble()
        resetRoundTimes()
        manager.send(.roundState(
            roundID: newRoundID,
            eventRawValue: selectedEvent.rawValue,
            scramble: scramble,
            hostScore: hostScore,
            guestScore: guestScore
        ))
    }

    private func resetRoundState() {
        roundID = nil
        scramble = ""
        hostScore = 0
        guestScore = 0
        resetRoundTimes()
    }

    private func resetRoundTimes() {
        invalidateTimer()
        localElapsed = 0
        isLocalPressing = false
        isRemotePressing = false
        localFinishedTime = nil
        remoteLiveTime = nil
        isRemoteRunning = false
        remoteFinishedTime = nil
        didScoreRound = false
        lastLiveTimeSentAt = nil
    }

    private func handle(_ message: NearbyBattleMessage) {
        switch message.type {
        case .roundState:
            guard let newRoundID = message.roundID,
                  let newScramble = message.scramble
            else { return }
            roundID = newRoundID
            scramble = newScramble
            hostScore = message.hostScore ?? hostScore
            guestScore = message.guestScore ?? guestScore
            resetRoundTimes()
        case .readyState:
            guard message.roundID == roundID, remoteFinishedTime == nil else { return }
            isRemotePressing = message.isReady ?? false
        case .liveTime:
            guard message.roundID == roundID, let seconds = message.seconds, remoteFinishedTime == nil else { return }
            remoteLiveTime = seconds
            isRemoteRunning = true
            isRemotePressing = false
        case .solveFinished:
            guard message.roundID == roundID, let seconds = message.seconds else { return }
            remoteFinishedTime = seconds
            remoteLiveTime = seconds
            isRemoteRunning = false
            isRemotePressing = false
            scoreRoundIfNeeded()
        case .scoreUpdate:
            guard message.roundID == roundID else { return }
            hostScore = message.hostScore ?? hostScore
            guestScore = message.guestScore ?? guestScore
            didScoreRound = true
        }
    }

    private func scoreRoundIfNeeded() {
        guard isHost,
              !didScoreRound,
              let localFinishedTime,
              let remoteFinishedTime,
              let roundID
        else { return }

        if localFinishedTime < remoteFinishedTime {
            hostScore += 1
        } else if remoteFinishedTime < localFinishedTime {
            guestScore += 1
        }
        didScoreRound = true
        manager.send(.scoreUpdate(roundID: roundID, hostScore: hostScore, guestScore: guestScore))
    }

    private func sendLiveTimeIfNeeded(force: Bool = false) {
        guard let roundID, manager.phase == .connected else { return }

        let now = Date()
        if !force,
           let lastLiveTimeSentAt,
           now.timeIntervalSince(lastLiveTimeSentAt) < 0.12 {
            return
        }

        lastLiveTimeSentAt = now
        manager.send(.liveTime(roundID: roundID, seconds: localElapsed), mode: .unreliable)
    }

    private func sendReadyState(isReady: Bool) {
        guard let roundID, manager.phase == .connected else { return }
        manager.send(.readyState(roundID: roundID, isReady: isReady), mode: .unreliable)
    }
}

private extension String {
    var localized: String {
        NSLocalizedString(self, comment: "")
    }
}
#endif

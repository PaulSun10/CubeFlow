import Combine
import Foundation
import Network

enum CompetitionWCALiveRealtimeState: Equatable {
    case idle
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case pollingFallback
    case offline
}

enum CompetitionWCALiveRoundContentState: Equatable {
    case loading
    case loaded
    case failed
}

@MainActor
final class CompetitionWCALiveRealtimeManager: ObservableObject {
    @Published private(set) var round: CompetitionWCALiveRound
    @Published private(set) var state: CompetitionWCALiveRealtimeState = .idle
    @Published private(set) var roundContentState: CompetitionWCALiveRoundContentState

    private static let socketURL = URL(
        string: "wss://live.worldcubeassociation.org/socket/websocket?vsn=2.0.0"
    )!
    private static let controlTopic = "__absinthe__:control"
    private static let pollingIntervalNanoseconds: UInt64 = 45_000_000_000
    private static let heartbeatIntervalNanoseconds: UInt64 = 30_000_000_000
    private static let handshakeTimeoutNanoseconds: UInt64 = 20_000_000_000
    private static let fallbackFailureThreshold = 3

    private var languageCode: String
    private var isRunning = false
    private var isForeground = true
    private var isNetworkAvailable = true
    private var reconnectFailureCount = 0
    private var updateRevision = 0
    private var nextReference = 1
    private var joinReference: String?
    private var subscriptionID: String?
    private var pendingHeartbeatReference: String?
    private var runID = UUID()
    private var snapshotRequestID = UUID()

    private var connectionTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var resyncTask: Task<Void, Never>?
    private var handshakeTimeoutTask: Task<Void, Never>?
    private var webSocketTask: URLSessionWebSocketTask?

    private var pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "com.cubeflow.wca-live-network")

    init(round: CompetitionWCALiveRound, languageCode: String) {
        self.round = round
        self.languageCode = languageCode
        roundContentState = round.results.isEmpty ? .loading : .loaded
    }

    deinit {
        connectionTask?.cancel()
        heartbeatTask?.cancel()
        pollingTask?.cancel()
        resyncTask?.cancel()
        handshakeTimeoutTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        pathMonitor?.cancel()
    }

    func configure(round: CompetitionWCALiveRound, languageCode: String) {
        let changedRound = self.round.id != round.id
        self.languageCode = languageCode

        if changedRound {
            stopTransport(resetState: false)
            self.round = round
            roundContentState = round.results.isEmpty ? .loading : .loaded
            reconnectFailureCount = 0
            updateRevision = 0
            if isRunning, isForeground {
                loadCurrentRoundSnapshot()
                if shouldSubscribe {
                    launchConnectionLoop()
                }
            }
        } else if self.round.results.isEmpty, !round.results.isEmpty {
            self.round = round
            roundContentState = .loaded
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startPathMonitor()
        loadCurrentRoundSnapshot()

        guard shouldSubscribe else {
            state = .idle
            return
        }
        launchConnectionLoop()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopTransport(resetState: true)
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    func suspend() {
        guard isForeground else { return }
        isForeground = false
        stopTransport(resetState: true)
    }

    func resume() {
        guard !isForeground else { return }
        isForeground = true
        guard isRunning else { return }
        loadCurrentRoundSnapshot()
        if shouldSubscribe {
            launchConnectionLoop()
        }
    }

    nonisolated static func retryDelayNanoseconds(after failureCount: Int) -> UInt64 {
        let seconds: UInt64
        switch max(failureCount, 1) {
        case 1: seconds = 1
        case 2: seconds = 2
        case 3: seconds = 4
        case 4: seconds = 8
        case 5: seconds = 15
        case 6: seconds = 30
        default: seconds = 60
        }
        return seconds * 1_000_000_000
    }

    private var shouldSubscribe: Bool {
        round.isFinished != true || round.isActive
    }

    private func startPathMonitor() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.networkAvailabilityChanged(path.status == .satisfied)
            }
        }
        monitor.start(queue: pathMonitorQueue)
    }

    private func networkAvailabilityChanged(_ isAvailable: Bool) {
        guard isNetworkAvailable != isAvailable else { return }
        isNetworkAvailable = isAvailable

        guard isRunning, isForeground else { return }
        if isAvailable {
            loadCurrentRoundSnapshot()
            if shouldSubscribe {
                launchConnectionLoop()
            } else {
                state = .idle
            }
        } else {
            state = .offline
            closeSocket()
            connectionTask?.cancel()
            connectionTask = nil
            pollingTask?.cancel()
            pollingTask = nil
            resyncTask?.cancel()
            resyncTask = nil
        }
    }

    private func launchConnectionLoop() {
        guard isRunning, isForeground, shouldSubscribe else { return }
        connectionTask?.cancel()
        closeSocket()

        let currentRunID = UUID()
        runID = currentRunID
        connectionTask = Task { [weak self] in
            await self?.runConnectionLoop(runID: currentRunID)
        }
    }

    private func runConnectionLoop(runID: UUID) async {
        while isCurrentRun(runID) {
            guard isNetworkAvailable else {
                state = .offline
                return
            }

            if pollingTask == nil {
                state = reconnectFailureCount == 0
                    ? .connecting
                    : .reconnecting(attempt: reconnectFailureCount)
            }

            do {
                try await connectAndListen(runID: runID)
                guard isCurrentRun(runID) else { return }
                throw RealtimeError.connectionClosed
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentRun(runID) else { return }
                closeSocket()
                reconnectFailureCount += 1

                if reconnectFailureCount >= Self.fallbackFailureThreshold {
                    startPollingFallback(runID: runID)
                } else {
                    state = .reconnecting(attempt: reconnectFailureCount)
                }

                let delay = Self.retryDelayNanoseconds(after: reconnectFailureCount)
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
            }
        }
    }

    private func connectAndListen(runID: UUID) async throws {
        var request = URLRequest(url: Self.socketURL)
        request.setValue(
            "https://live.worldcubeassociation.org",
            forHTTPHeaderField: "Origin"
        )
        let socket = URLSession.shared.webSocketTask(with: request)
        webSocketTask = socket
        nextReference = 1
        joinReference = nil
        subscriptionID = nil
        pendingHeartbeatReference = nil
        socket.resume()

        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = Task { [weak self, weak socket] in
            try? await Task.sleep(nanoseconds: Self.handshakeTimeoutNanoseconds)
            guard let self, self.isCurrentRun(runID), self.state != .connected else { return }
            socket?.cancel(with: .goingAway, reason: nil)
        }

        let joinRef = makeReference()
        try await send(
            PhoenixMessage(
                joinReference: nil,
                reference: joinRef,
                topic: Self.controlTopic,
                event: "phx_join",
                payload: [:]
            ),
            over: socket
        )
        _ = try await waitForSuccessfulReply(reference: joinRef, socket: socket, runID: runID)
        joinReference = joinRef

        let documentRef = makeReference()
        try await send(
            PhoenixMessage(
                joinReference: joinRef,
                reference: documentRef,
                topic: Self.controlTopic,
                event: "doc",
                payload: [
                    "query": Self.roundUpdatedSubscription,
                    "variables": ["id": round.id]
                ]
            ),
            over: socket
        )
        let response = try await waitForSuccessfulReply(
            reference: documentRef,
            socket: socket,
            runID: runID
        )
        guard let subscriptionID = response["subscriptionId"] as? String,
              !subscriptionID.isEmpty else {
            throw RealtimeError.missingSubscriptionID
        }
        self.subscriptionID = subscriptionID

        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        reconnectFailureCount = 0
        state = .connected
        stopPollingFallback()
        startHeartbeat(socket: socket, runID: runID)
        loadCurrentRoundSnapshot(runID: runID)

        while isCurrentRun(runID) {
            let message = try await receive(over: socket)
            try handle(message, runID: runID)
        }
    }

    private func waitForSuccessfulReply(
        reference: String,
        socket: URLSessionWebSocketTask,
        runID: UUID
    ) async throws -> [String: Any] {
        while isCurrentRun(runID) {
            let message = try await receive(over: socket)
            if message.event == "phx_reply", message.reference == reference {
                guard message.payload["status"] as? String == "ok" else {
                    throw RealtimeError.serverRejectedRequest
                }
                return message.payload["response"] as? [String: Any] ?? [:]
            }
            try handle(message, runID: runID)
        }
        throw CancellationError()
    }

    private func handle(_ message: PhoenixMessage, runID: UUID) throws {
        if message.topic == "phoenix",
           message.event == "phx_reply",
           message.reference == pendingHeartbeatReference {
            pendingHeartbeatReference = nil
            return
        }

        if message.event == "subscription:data" {
            guard message.payload["subscriptionId"] as? String == subscriptionID,
                  let result = message.payload["result"] as? [String: Any],
                  let resultData = try? JSONSerialization.data(withJSONObject: result),
                  let updatedRound = CompetitionService.decodeWCALiveRoundSubscriptionResult(
                    resultData,
                    fallback: round
                  ) else {
                return
            }
            apply(updatedRound)
            return
        }

        if message.event == "phx_error" || message.event == "phx_close" {
            throw RealtimeError.connectionClosed
        }
    }

    private func startHeartbeat(socket: URLSessionWebSocketTask, runID: UUID) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self, weak socket] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: Self.heartbeatIntervalNanoseconds)
                } catch {
                    return
                }
                guard let self, let socket, self.isCurrentRun(runID) else { return }
                if self.pendingHeartbeatReference != nil {
                    socket.cancel(with: .goingAway, reason: nil)
                    return
                }

                let reference = self.makeReference()
                self.pendingHeartbeatReference = reference
                do {
                    try await self.send(
                        PhoenixMessage(
                            joinReference: nil,
                            reference: reference,
                            topic: "phoenix",
                            event: "heartbeat",
                            payload: [:]
                        ),
                        over: socket
                    )
                } catch {
                    socket.cancel(with: .goingAway, reason: nil)
                    return
                }
            }
        }
    }

    private func loadCurrentRoundSnapshot(runID requiredRunID: UUID? = nil) {
        resyncTask?.cancel()
        let revisionBeforeRequest = updateRevision
        let currentRound = round
        let currentLanguageCode = languageCode
        let requestID = UUID()
        snapshotRequestID = requestID
        if currentRound.results.isEmpty {
            roundContentState = .loading
        }
        resyncTask = Task { [weak self] in
            let snapshot = await CompetitionService.fetchCompetitionWCALiveRoundSnapshot(
                round: currentRound,
                languageCode: currentLanguageCode
            )
            guard let self,
                  self.isRunning,
                  self.isForeground,
                  self.snapshotRequestID == requestID,
                  self.round.id == currentRound.id else {
                return
            }
            if let requiredRunID, !self.isCurrentRun(requiredRunID) {
                return
            }
            guard self.updateRevision == revisionBeforeRequest else { return }
            guard let snapshot else {
                if self.round.results.isEmpty {
                    self.roundContentState = .failed
                }
                return
            }
            self.apply(snapshot)
        }
    }

    private func startPollingFallback(runID: UUID) {
        guard pollingTask == nil else { return }
        state = isNetworkAvailable ? .pollingFallback : .offline
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isCurrentRun(runID) else { return }
                if self.isNetworkAvailable {
                    let currentRound = self.round
                    let currentLanguageCode = self.languageCode
                    if let snapshot = await CompetitionService.fetchCompetitionWCALiveRoundSnapshot(
                        round: currentRound,
                        languageCode: currentLanguageCode
                    ), self.isCurrentRun(runID), self.state != .connected {
                        self.apply(snapshot)
                        self.state = .pollingFallback
                    }
                } else {
                    self.state = .offline
                }

                do {
                    try await Task.sleep(nanoseconds: Self.pollingIntervalNanoseconds)
                } catch {
                    return
                }
            }
        }
    }

    private func stopPollingFallback() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func apply(_ updatedRound: CompetitionWCALiveRound) {
        guard updatedRound.id == round.id else { return }
        roundContentState = .loaded
        guard updatedRound != round else { return }
        round = updatedRound
        updateRevision += 1
        if !shouldSubscribe {
            stopTransport(resetState: true)
        }
    }

    private func stopTransport(resetState: Bool) {
        runID = UUID()
        connectionTask?.cancel()
        connectionTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        pollingTask?.cancel()
        pollingTask = nil
        resyncTask?.cancel()
        resyncTask = nil
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        closeSocket()
        if resetState {
            state = .idle
        }
    }

    private func closeSocket() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        joinReference = nil
        subscriptionID = nil
        pendingHeartbeatReference = nil
    }

    private func isCurrentRun(_ candidate: UUID) -> Bool {
        isRunning && isForeground && candidate == runID && shouldSubscribe
    }

    private func makeReference() -> String {
        defer { nextReference += 1 }
        return String(nextReference)
    }

    private func send(
        _ message: PhoenixMessage,
        over socket: URLSessionWebSocketTask
    ) async throws {
        let data = try message.encoded()
        guard let text = String(data: data, encoding: .utf8) else {
            throw RealtimeError.invalidMessage
        }
        try await socket.send(.string(text))
    }

    private func receive(over socket: URLSessionWebSocketTask) async throws -> PhoenixMessage {
        let message = try await socket.receive()
        let data: Data
        switch message {
        case let .string(text):
            guard let stringData = text.data(using: .utf8) else {
                throw RealtimeError.invalidMessage
            }
            data = stringData
        case let .data(binaryData):
            data = binaryData
        @unknown default:
            throw RealtimeError.invalidMessage
        }
        return try PhoenixMessage.decode(data)
    }

    private enum RealtimeError: Error {
        case invalidMessage
        case serverRejectedRequest
        case missingSubscriptionID
        case connectionClosed
    }

    private struct PhoenixMessage {
        let joinReference: String?
        let reference: String?
        let topic: String
        let event: String
        let payload: [String: Any]

        func encoded() throws -> Data {
            let values: [Any] = [
                joinReference as Any? ?? NSNull(),
                reference as Any? ?? NSNull(),
                topic,
                event,
                payload
            ]
            return try JSONSerialization.data(
                withJSONObject: values
            )
        }

        static func decode(_ data: Data) throws -> PhoenixMessage {
            guard let values = try JSONSerialization.jsonObject(with: data) as? [Any],
                  values.count == 5,
                  let topic = values[2] as? String,
                  let event = values[3] as? String,
                  let payload = values[4] as? [String: Any] else {
                throw RealtimeError.invalidMessage
            }
            return PhoenixMessage(
                joinReference: values[0] as? String,
                reference: values[1] as? String,
                topic: topic,
                event: event,
                payload: payload
            )
        }
    }

    private static let roundUpdatedSubscription = """
    subscription RoundUpdated($id: ID!) {
      roundUpdated(id: $id) {
        id
        results {
          id
          ranking
          advancing
          advancingQuestionable
          attempts { result }
          best
          average
          person {
            id
            name
            country { iso2 name }
          }
          singleRecordTag
          averageRecordTag
        }
      }
    }
    """
}

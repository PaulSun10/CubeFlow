import Foundation
import Combine
import MultipeerConnectivity
import UIKit

#if os(iOS)
enum NearbyBattleRole: String {
    case host
    case guest
}

enum NearbyBattleConnectionPhase: Equatable {
    case idle
    case hosting
    case browsing
    case connecting
    case connected
    case failed(String)
}

struct NearbyBattlePeer: Identifiable, Equatable {
    let id: String
    let displayName: String
}

enum NearbyBattleMessageType: String, Codable {
    case roundState
    case readyState
    case liveTime
    case solveFinished
    case scoreUpdate
}

struct NearbyBattleMessage: Codable, Equatable {
    var type: NearbyBattleMessageType
    var roundID: String?
    var eventRawValue: String?
    var scramble: String?
    var seconds: Double?
    var hostScore: Int?
    var guestScore: Int?
    var isReady: Bool?

    static func roundState(roundID: String, eventRawValue: String, scramble: String, hostScore: Int, guestScore: Int) -> NearbyBattleMessage {
        NearbyBattleMessage(
            type: .roundState,
            roundID: roundID,
            eventRawValue: eventRawValue,
            scramble: scramble,
            seconds: nil,
            hostScore: hostScore,
            guestScore: guestScore,
            isReady: nil
        )
    }

    static func readyState(roundID: String, isReady: Bool) -> NearbyBattleMessage {
        NearbyBattleMessage(
            type: .readyState,
            roundID: roundID,
            eventRawValue: nil,
            scramble: nil,
            seconds: nil,
            hostScore: nil,
            guestScore: nil,
            isReady: isReady
        )
    }

    static func solveFinished(roundID: String, seconds: Double) -> NearbyBattleMessage {
        NearbyBattleMessage(
            type: .solveFinished,
            roundID: roundID,
            eventRawValue: nil,
            scramble: nil,
            seconds: seconds,
            hostScore: nil,
            guestScore: nil,
            isReady: nil
        )
    }

    static func liveTime(roundID: String, seconds: Double) -> NearbyBattleMessage {
        NearbyBattleMessage(
            type: .liveTime,
            roundID: roundID,
            eventRawValue: nil,
            scramble: nil,
            seconds: seconds,
            hostScore: nil,
            guestScore: nil,
            isReady: nil
        )
    }

    static func scoreUpdate(roundID: String, hostScore: Int, guestScore: Int) -> NearbyBattleMessage {
        NearbyBattleMessage(
            type: .scoreUpdate,
            roundID: roundID,
            eventRawValue: nil,
            scramble: nil,
            seconds: nil,
            hostScore: hostScore,
            guestScore: guestScore,
            isReady: nil
        )
    }
}

struct NearbyBattleReceivedMessage: Identifiable, Equatable {
    let id = UUID()
    let message: NearbyBattleMessage
}

final class NearbyBattleManager: NSObject, ObservableObject {
    private static let serviceType = "cubeflow"

    @Published private(set) var role: NearbyBattleRole?
    @Published private(set) var phase: NearbyBattleConnectionPhase = .idle
    @Published private(set) var availablePeers: [NearbyBattlePeer] = []
    @Published private(set) var connectedPeerName: String?
    @Published var receivedMessage: NearbyBattleReceivedMessage?

    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    private lazy var session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var peersByID: [String: MCPeerID] = [:]

    override init() {
        super.init()
        session.delegate = self
    }

    func startHosting() {
        stopDiscoveryOnly()
        role = .host
        phase = .hosting
        connectedPeerName = nil
        availablePeers = []

        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
    }

    func startBrowsing() {
        stopDiscoveryOnly()
        role = .guest
        phase = .browsing
        connectedPeerName = nil
        availablePeers = []
        peersByID = [:]

        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    func invite(_ peer: NearbyBattlePeer) {
        guard let peerID = peersByID[peer.id], let browser else { return }
        phase = .connecting
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
    }

    func send(_ message: NearbyBattleMessage, mode: MCSessionSendDataMode = .reliable) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: session.connectedPeers, with: mode)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func stop() {
        stopDiscoveryOnly()
        session.disconnect()
        role = nil
        phase = .idle
        availablePeers = []
        connectedPeerName = nil
        peersByID = [:]
        receivedMessage = nil
    }

    private func stopDiscoveryOnly() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
    }
}

extension NearbyBattleManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
        DispatchQueue.main.async {
            self.phase = .connecting
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            self.phase = .failed(error.localizedDescription)
        }
    }
}

extension NearbyBattleManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        DispatchQueue.main.async {
            let peer = NearbyBattlePeer(id: peerID.displayName, displayName: peerID.displayName)
            self.peersByID[peer.id] = peerID
            if !self.availablePeers.contains(peer) {
                self.availablePeers.append(peer)
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.availablePeers.removeAll { $0.id == peerID.displayName }
            self.peersByID[peerID.displayName] = nil
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            self.phase = .failed(error.localizedDescription)
        }
    }
}

extension NearbyBattleManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.stopDiscoveryOnly()
                self.connectedPeerName = peerID.displayName
                self.phase = .connected
            case .connecting:
                self.phase = .connecting
            case .notConnected:
                if case .idle = self.phase {
                    return
                }
                self.connectedPeerName = nil
                self.phase = .failed("Disconnected")
            @unknown default:
                self.phase = .failed("Unknown connection state")
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(NearbyBattleMessage.self, from: data) else { return }
        DispatchQueue.main.async {
            self.receivedMessage = NearbyBattleReceivedMessage(message: message)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
#endif

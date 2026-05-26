import Foundation
import MultipeerConnectivity
import CloudKit
import WidgetKit
import CryptoKit

@Observable
final class PeerSyncService: NSObject {
    static let shared = PeerSyncService()

    var connectedPeers: [String] = []

    private let serviceType = "jira-timer"
    private let peerID: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var onTimerUpdate: ((SharedTimerData?) -> Void)?
    private var accountHash: String?

    private override init() {
        #if os(macOS)
        peerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
        #else
        peerID = MCPeerID(displayName: UIDevice.current.name)
        #endif
        super.init()
    }

    func start(onTimerUpdate: @escaping (SharedTimerData?) -> Void) {
        self.onTimerUpdate = onTimerUpdate

        Task {
            let hash = await fetchAccountHash()
            await MainActor.run {
                self.accountHash = hash
                self.startSession()
            }
        }
    }

    private func fetchAccountHash() async -> String? {
        do {
            let id = try await CKContainer.default().userRecordID()
            let hash = SHA256.hash(data: Data(id.recordName.utf8))
            return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
        } catch {
            return nil
        }
    }

    private func startSession() {
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let discoveryInfo = accountHash.map { ["acct": $0] }
        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: discoveryInfo, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        connectedPeers = []
    }

    func broadcastTimerState(_ timer: SharedTimerData?) {
        guard let session, !session.connectedPeers.isEmpty else { return }
        let payload = PeerTimerPayload(timer: timer)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    var isConnected: Bool {
        !(session?.connectedPeers.isEmpty ?? true)
    }
}

extension PeerSyncService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            connectedPeers = session.connectedPeers.map(\.displayName)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let payload = try? JSONDecoder().decode(PeerTimerPayload.self, from: data) else { return }
        SharedData.saveTimerState(payload.timer)
        WidgetCenter.shared.reloadAllTimelines()
        Task { @MainActor in
            onTimerUpdate?(payload.timer)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension PeerSyncService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        if let context, let peerHash = String(data: context, encoding: .utf8),
           let myHash = accountHash, peerHash == myHash {
            invitationHandler(true, session)
        } else if accountHash == nil {
            invitationHandler(true, session)
        } else {
            invitationHandler(false, nil)
        }
    }
}

extension PeerSyncService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let session else { return }
        let peerAcct = info?["acct"]
        if let myHash = accountHash, let peerAcct, myHash != peerAcct {
            return
        }
        let context = accountHash?.data(using: .utf8)
        browser.invitePeer(peerID, to: session, withContext: context, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}

private struct PeerTimerPayload: Codable {
    let timer: SharedTimerData?
}

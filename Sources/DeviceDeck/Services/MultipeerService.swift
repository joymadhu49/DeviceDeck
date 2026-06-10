import Foundation
import MultipeerConnectivity
import AppKit
import UserNotifications

@MainActor
final class MultipeerService: NSObject, ObservableObject {

    static let serviceType = "devicedeck-fs"

    // MARK: - Published state

    @Published private(set) var peers: [PeerDevice] = []
    @Published private(set) var transfers: [FileTransfer] = []
    @Published private(set) var isRunning: Bool = false
    @Published var lastError: String? = nil

    let localInfo: DeviceInfo
    let receivedFilesDirectory: URL   // ~/Downloads/DeviceDeck

    // MARK: - Private MC machinery

    private let myPeerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser

    /// displayName -> MCPeerID for peers we currently know about.
    private var peerIDsByName: [String: MCPeerID] = [:]

    /// Keep KVO observations of transfer Progress objects alive.
    private var progressObservations: [UUID: NSKeyValueObservation] = [:]

    private static let peerIDDefaultsKey = "DeviceDeck.MCPeerID"

    // MARK: - Init

    init(localInfo: DeviceInfo) {
        self.localInfo = localInfo

        // Received-files directory: ~/Downloads/DeviceDeck
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let dir = downloads.appendingPathComponent("DeviceDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.receivedFilesDirectory = dir

        // Stable MCPeerID, persisted across launches.
        self.myPeerID = Self.loadOrCreatePeerID()

        self.session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        self.advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: nil,
            serviceType: Self.serviceType
        )
        self.browser = MCNearbyServiceBrowser(
            peer: myPeerID,
            serviceType: Self.serviceType
        )

        super.init()

        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    private static func loadOrCreatePeerID() -> MCPeerID {
        let displayName = Host.current().localizedName ?? "Mac"
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: peerIDDefaultsKey),
           let saved = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data),
           saved.displayName == displayName {
            return saved
        }

        let peerID = MCPeerID(displayName: displayName)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: peerID, requiringSecureCoding: true) {
            defaults.set(data, forKey: peerIDDefaultsKey)
        }
        return peerID
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        isRunning = false
        for index in peers.indices {
            peers[index].state = .disconnected
        }
    }

    // MARK: - Connecting

    func invite(_ peer: PeerDevice) {
        guard let peerID = peerIDsByName[peer.displayName] else {
            lastError = "Peer \(peer.displayName) is no longer available."
            return
        }
        updatePeer(named: peer.displayName) { $0.state = .connecting }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }

    // MARK: - Sending files

    func sendFile(_ url: URL, to peer: PeerDevice) {
        guard let peerID = connectedPeerID(for: peer) else { return }

        let fileName = url.lastPathComponent
        let byteSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil

        var transfer = FileTransfer(
            id: UUID(),
            fileName: fileName,
            peerName: peer.displayName,
            direction: .outgoing,
            progress: 0,
            status: .inProgress,
            byteSize: byteSize,
            localURL: url,
            startedAt: Date()
        )

        let transferID = transfer.id
        let progress = session.sendResource(at: url, withName: fileName, toPeer: peerID) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.progressObservations[transferID] = nil
                if let error {
                    self.updateTransfer(id: transferID) { $0.status = .failed(error.localizedDescription) }
                    self.lastError = "Failed to send \(fileName): \(error.localizedDescription)"
                } else {
                    self.updateTransfer(id: transferID) {
                        $0.progress = 1
                        $0.status = .completed
                    }
                }
            }
        }

        if let progress {
            observe(progress, forTransfer: transferID)
        } else {
            transfer.status = .failed("Could not start transfer.")
        }
        transfers.append(transfer)
    }

    func sendFiles(_ urls: [URL], to peer: PeerDevice) {
        for url in urls {
            sendFile(url, to: peer)
        }
    }

    // MARK: - Messages

    func sendClipboard(_ text: String, to peer: PeerDevice) {
        send(.clipboard(text), to: peer)
    }

    func requestInfo(from peer: PeerDevice) {
        send(.requestInfo, to: peer)
    }

    private func send(_ message: PeerMessage, to peer: PeerDevice) {
        guard let peerID = connectedPeerID(for: peer) else { return }
        send(message, toPeerIDs: [peerID])
    }

    private func send(_ message: PeerMessage, toPeerIDs peerIDs: [MCPeerID]) {
        guard !peerIDs.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: peerIDs, with: .reliable)
        } catch {
            lastError = "Failed to send message: \(error.localizedDescription)"
        }
    }

    private func connectedPeerID(for peer: PeerDevice) -> MCPeerID? {
        guard let peerID = peerIDsByName[peer.displayName],
              session.connectedPeers.contains(peerID) else {
            lastError = "\(peer.displayName) is not connected."
            return nil
        }
        return peerID
    }

    // MARK: - State helpers

    private func updatePeer(named displayName: String, _ mutate: (inout PeerDevice) -> Void) {
        guard let index = peers.firstIndex(where: { $0.displayName == displayName }) else { return }
        mutate(&peers[index])
    }

    private func updateTransfer(id: UUID, _ mutate: (inout FileTransfer) -> Void) {
        guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        mutate(&transfers[index])
    }

    private func observe(_ progress: Progress, forTransfer transferID: UUID) {
        progressObservations[transferID] = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor [weak self] in
                self?.updateTransfer(id: transferID) { transfer in
                    if transfer.status == .inProgress {
                        transfer.progress = fraction
                    }
                }
            }
        }
    }

    private func upsertDiscoveredPeer(_ peerID: MCPeerID) {
        peerIDsByName[peerID.displayName] = peerID
        if let index = peers.firstIndex(where: { $0.displayName == peerID.displayName }) {
            peers[index].lastSeen = Date()
            if peers[index].state == .disconnected {
                peers[index].state = .discovered
            }
        } else {
            peers.append(PeerDevice(
                id: peerID.displayName,
                displayName: peerID.displayName,
                info: nil,
                state: .discovered,
                lastSeen: Date()
            ))
        }
    }

    private func handleSessionState(_ state: MCSessionState, for peerID: MCPeerID) {
        peerIDsByName[peerID.displayName] = peerID
        switch state {
        case .connecting:
            upsertDiscoveredPeer(peerID)
            updatePeer(named: peerID.displayName) {
                $0.state = .connecting
                $0.lastSeen = Date()
            }
        case .connected:
            upsertDiscoveredPeer(peerID)
            updatePeer(named: peerID.displayName) {
                $0.state = .connected
                $0.lastSeen = Date()
            }
            // Handshake: send our device info immediately.
            send(.deviceInfo(localInfo), toPeerIDs: [peerID])
        case .notConnected:
            updatePeer(named: peerID.displayName) {
                $0.state = .disconnected
                $0.lastSeen = Date()
            }
        @unknown default:
            break
        }
    }

    private func handleMessage(_ data: Data, from peerID: MCPeerID) {
        let message: PeerMessage
        do {
            message = try JSONDecoder().decode(PeerMessage.self, from: data)
        } catch {
            lastError = "Received undecodable message from \(peerID.displayName)."
            return
        }

        updatePeer(named: peerID.displayName) { $0.lastSeen = Date() }

        switch message {
        case .deviceInfo(let info):
            updatePeer(named: peerID.displayName) { $0.info = info }
        case .requestInfo:
            send(.deviceInfo(localInfo), toPeerIDs: [peerID])
        case .clipboard(let text):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            postNotification(
                title: "Clipboard received",
                body: "\(peerID.displayName) shared clipboard text."
            )
        case .ping:
            send(.pong, toPeerIDs: [peerID])
        case .pong:
            break
        }
    }

    private func postNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(request, withCompletionHandler: nil)
        }
    }

    // MARK: - Incoming resources

    private func beginIncomingTransfer(name: String, from peerID: MCPeerID, progress: Progress) -> UUID {
        let transfer = FileTransfer(
            id: UUID(),
            fileName: name,
            peerName: peerID.displayName,
            direction: .incoming,
            progress: 0,
            status: .inProgress,
            byteSize: progress.totalUnitCount > 0 ? progress.totalUnitCount : nil,
            localURL: nil,
            startedAt: Date()
        )
        transfers.append(transfer)
        observe(progress, forTransfer: transfer.id)
        return transfer.id
    }

    private func finishIncomingTransfer(name: String, from peerID: MCPeerID, tempURL: URL?, error: Error?) {
        // Match the most recent in-progress incoming transfer for this name/peer.
        let index = transfers.lastIndex {
            $0.direction == .incoming
                && $0.fileName == name
                && $0.peerName == peerID.displayName
                && $0.status == .inProgress
        }
        let transferID = index.map { transfers[$0].id }
        if let transferID {
            progressObservations[transferID] = nil
        }

        if let error {
            if let transferID {
                updateTransfer(id: transferID) { $0.status = .failed(error.localizedDescription) }
            }
            lastError = "Failed to receive \(name): \(error.localizedDescription)"
            return
        }

        guard let tempURL else {
            if let transferID {
                updateTransfer(id: transferID) { $0.status = .failed("Received file is missing.") }
            }
            return
        }

        do {
            let destination = uniqueDestinationURL(forFileName: name)
            try FileManager.default.createDirectory(
                at: receivedFilesDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: tempURL, to: destination)
            if let transferID {
                updateTransfer(id: transferID) {
                    $0.progress = 1
                    $0.status = .completed
                    $0.localURL = destination
                }
            }
        } catch {
            if let transferID {
                updateTransfer(id: transferID) { $0.status = .failed(error.localizedDescription) }
            }
            lastError = "Failed to save \(name): \(error.localizedDescription)"
        }
    }

    /// Returns a URL in `receivedFilesDirectory` that doesn't collide with an
    /// existing file, appending " 2", " 3", … to the base name as needed.
    private func uniqueDestinationURL(forFileName name: String) -> URL {
        let baseURL = receivedFilesDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: baseURL.path) else { return baseURL }

        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var counter = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
            let candidate = receivedFilesDirectory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerService: MCSessionDelegate {

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            self.handleSessionState(state, for: peerID)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.handleMessage(data, from: peerID)
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {
        // Streams are not used by DeviceDeck.
    }

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {
        Task { @MainActor in
            _ = self.beginIncomingTransfer(name: resourceName, from: peerID, progress: progress)
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
        // The temp file is deleted when this delegate method returns; move it
        // somewhere stable synchronously before hopping to the main actor.
        var stashedURL: URL? = nil
        if let localURL {
            let stash = FileManager.default.temporaryDirectory
                .appendingPathComponent("DeviceDeck-\(UUID().uuidString)-\(resourceName)")
            do {
                try FileManager.default.moveItem(at: localURL, to: stash)
                stashedURL = stash
            } catch {
                stashedURL = nil
            }
        }
        let movedURL = stashedURL
        Task { @MainActor in
            self.finishIncomingTransfer(name: resourceName, from: peerID, tempURL: movedURL, error: error)
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerService: MCNearbyServiceAdvertiserDelegate {

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // Personal-devices app: auto-accept all invitations.
        Task { @MainActor in
            self.upsertDiscoveredPeer(peerID)
            self.updatePeer(named: peerID.displayName) { $0.state = .connecting }
            invitationHandler(true, self.session)
        }
    }

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        Task { @MainActor in
            self.lastError = "Failed to start advertising: \(error.localizedDescription)"
            self.isRunning = false
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerService: MCNearbyServiceBrowserDelegate {

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        Task { @MainActor in
            self.upsertDiscoveredPeer(peerID)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.updatePeer(named: peerID.displayName) {
                $0.state = .disconnected
                $0.lastSeen = Date()
            }
        }
    }

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {
        Task { @MainActor in
            self.lastError = "Failed to start browsing: \(error.localizedDescription)"
            self.isRunning = false
        }
    }
}

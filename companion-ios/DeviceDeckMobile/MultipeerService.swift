import Foundation
import MultipeerConnectivity
import UIKit

// MARK: - Local device info collection (iOS)

enum LocalDeviceInfo {

    @MainActor
    static func collect() -> DeviceInfo {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        // Battery: batteryLevel is -1 when unknown (e.g. Simulator).
        let rawLevel = device.batteryLevel
        let batteryLevel: Double? = rawLevel >= 0 ? Double(rawLevel) : nil
        let isCharging: Bool?
        switch device.batteryState {
        case .charging, .full:
            isCharging = true
        case .unplugged:
            isCharging = false
        default:
            isCharging = nil
        }

        // Disk capacity for the data volume.
        var freeDisk: Int64? = nil
        var totalDisk: Int64? = nil
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? homeURL.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ]) {
            freeDisk = values.volumeAvailableCapacityForImportantUsage
            if let total = values.volumeTotalCapacity {
                totalDisk = Int64(total)
            }
        }

        let kind: DeviceKind = device.userInterfaceIdiom == .pad ? .iPad : .iPhone

        return DeviceInfo(
            id: stableIdentifier(),
            name: device.name,
            kind: kind,
            model: machineModel(),
            osVersion: "\(device.systemName) \(device.systemVersion)",
            cpuBrand: nil,
            memoryBytes: Int64(ProcessInfo.processInfo.physicalMemory),
            freeDiskBytes: freeDisk,
            totalDiskBytes: totalDisk,
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            localIP: localIPAddress(),
            uptimeSeconds: ProcessInfo.processInfo.systemUptime
        )
    }

    /// identifierForVendor when available, otherwise a UUID persisted in UserDefaults.
    private static func stableIdentifier() -> String {
        if let vendorID = UIDevice.current.identifierForVendor?.uuidString {
            return vendorID
        }
        let key = "DeviceDeck.LocalDeviceID"
        if let saved = UserDefaults.standard.string(forKey: key) {
            return saved
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    /// Hardware model string from utsname, e.g. "iPhone16,1".
    private static func machineModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: systemInfo.machine) { buffer -> String in
            let bytes = buffer.prefix(while: { $0 != 0 })
            return String(decoding: bytes, as: UTF8.self)
        }
        return machine.isEmpty ? "iPhone" : machine
    }

    /// IPv4 address of the Wi-Fi interface (en0), if any.
    private static func localIPAddress() -> String? {
        var address: String? = nil
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else {
            return nil
        }
        defer { freeifaddrs(ifaddrPointer) }

        for pointer in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let addrPointer = interface.ifa_addr else { continue }
            guard addrPointer.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            guard String(cString: interface.ifa_name) == "en0" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addrPointer,
                socklen_t(addrPointer.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                address = String(cString: hostname)
            }
        }
        return address
    }
}

// MARK: - MultipeerService (iOS)

@MainActor
final class MultipeerService: NSObject, ObservableObject {

    static let serviceType = "devicedeck-fs"

    // MARK: - Published state

    @Published private(set) var peers: [PeerDevice] = []
    @Published private(set) var transfers: [FileTransfer] = []
    @Published private(set) var receivedFiles: [URL] = []
    @Published private(set) var isRunning: Bool = false
    @Published var lastError: String? = nil
    @Published var lastEvent: String? = nil

    let localInfo: DeviceInfo
    let receivedFilesDirectory: URL   // Documents/DeviceDeck (visible in the Files app)

    // MARK: - Private MC machinery

    private let myPeerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser

    /// displayName -> MCPeerID for peers we currently know about.
    private var peerIDsByName: [String: MCPeerID] = [:]

    /// Keep KVO observations of transfer Progress objects alive.
    private var progressObservations: [UUID: NSKeyValueObservation] = [:]

    /// Outgoing temp copies (security-scoped picks copied to tmp) to delete when done.
    private var outgoingTempURLs: [UUID: URL] = [:]

    private static let peerIDDefaultsKey = "DeviceDeck.MCPeerID"

    // MARK: - Init

    override init() {
        self.localInfo = LocalDeviceInfo.collect()

        // Received-files directory: Documents/DeviceDeck (exposed in the Files
        // app when UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace are set).
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        let dir = documents.appendingPathComponent("DeviceDeck", isDirectory: true)
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

        refreshReceivedFiles()
    }

    private static func loadOrCreatePeerID() -> MCPeerID {
        let displayName = UIDevice.current.name
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

    /// Sends a file the app already has direct access to (e.g. a temp copy).
    /// If `deletingWhenDone` is true the file is removed after the transfer ends.
    func sendFile(_ url: URL, to peer: PeerDevice, deletingWhenDone: Bool = false) {
        guard let peerID = connectedPeerID(for: peer) else {
            if deletingWhenDone { try? FileManager.default.removeItem(at: url) }
            return
        }

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
        if deletingWhenDone {
            outgoingTempURLs[transferID] = url
        }

        let progress = session.sendResource(at: url, withName: fileName, toPeer: peerID) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.progressObservations[transferID] = nil
                if let tempURL = self.outgoingTempURLs.removeValue(forKey: transferID) {
                    try? FileManager.default.removeItem(at: tempURL)
                }
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
            if let tempURL = outgoingTempURLs.removeValue(forKey: transferID) {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
        transfers.append(transfer)
    }

    /// Sends security-scoped URLs from the document picker. Each file is copied
    /// to a temp location first (the security scope ends when this returns),
    /// and the copy is deleted once the transfer finishes.
    func sendPickedFiles(_ urls: [URL], to peer: PeerDevice) {
        for url in urls {
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess { url.stopAccessingSecurityScopedResource() }
            }

            let stagingDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("DeviceDeck-Outgoing-\(UUID().uuidString)", isDirectory: true)
            let tempCopy = stagingDir.appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: url, to: tempCopy)
            } catch {
                lastError = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
                continue
            }
            sendFile(tempCopy, to: peer, deletingWhenDone: true)
        }
    }

    // MARK: - Messages

    func sendClipboard(to peer: PeerDevice) {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            lastError = "Clipboard has no text to send."
            return
        }
        send(.clipboard(text), to: peer)
        lastEvent = "Clipboard sent to \(peer.displayName)."
    }

    func requestInfo(from peer: PeerDevice) {
        send(.requestInfo, to: peer)
    }

    func ping(_ peer: PeerDevice) {
        send(.ping, to: peer)
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

    // MARK: - Received files

    func refreshReceivedFiles() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: receivedFilesDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        receivedFiles = contents.sorted { a, b in
            let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return dateA > dateB
        }
    }

    func deleteReceivedFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        refreshReceivedFiles()
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
            UIPasteboard.general.string = text
            lastEvent = "Clipboard received from \(peerID.displayName)."
        case .ping:
            send(.pong, toPeerIDs: [peerID])
        case .pong:
            lastEvent = "Pong from \(peerID.displayName)."
        }
    }

    // MARK: - Incoming resources

    private func beginIncomingTransfer(name: String, from peerID: MCPeerID, progress: Progress) {
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
            lastEvent = "Received \(name) from \(peerID.displayName)."
            refreshReceivedFiles()
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
            self.beginIncomingTransfer(name: resourceName, from: peerID, progress: progress)
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

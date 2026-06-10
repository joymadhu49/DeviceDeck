import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root view

struct ContentView: View {
    @EnvironmentObject private var service: MultipeerService

    var body: some View {
        NavigationStack {
            List {
                peersSection
                receivedFilesSection
                if let event = service.lastEvent {
                    Section {
                        Label(event, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("DeviceDeck")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: service.isRunning ? "dot.radiowaves.left.and.right" : "wifi.slash")
                        .foregroundStyle(service.isRunning ? .green : .secondary)
                }
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { service.lastError != nil },
                    set: { if !$0 { service.lastError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(service.lastError ?? "")
            }
            .onAppear {
                service.start()
                service.refreshReceivedFiles()
            }
        }
    }

    // MARK: Peers

    @ViewBuilder
    private var peersSection: some View {
        Section("Nearby Devices") {
            if service.peers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Looking for devices…")
                        .foregroundStyle(.secondary)
                    Text("Make sure the Mac app is running and both devices are on the same Wi-Fi network.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(service.peers) { peer in
                    peerRow(peer)
                }
            }
        }
    }

    @ViewBuilder
    private func peerRow(_ peer: PeerDevice) -> some View {
        if peer.state == .connected {
            NavigationLink {
                PeerDetailView(peerID: peer.id)
            } label: {
                PeerRowLabel(peer: peer)
            }
        } else {
            Button {
                service.invite(peer)
            } label: {
                PeerRowLabel(peer: peer)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Received files

    @ViewBuilder
    private var receivedFilesSection: some View {
        Section {
            if service.receivedFiles.isEmpty {
                Text("No files received yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(service.receivedFiles, id: \.self) { url in
                    HStack {
                        Image(systemName: "doc")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            if let size = fileSize(of: url) {
                                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            service.deleteReceivedFile(url)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text("Received Files")
        } footer: {
            Text("Received files are also available in the Files app under On My iPhone › DeviceDeckMobile › DeviceDeck.")
        }
    }

    private func fileSize(of url: URL) -> Int64? {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 else {
            return nil
        }
        return size
    }
}

// MARK: - Peer row label

struct PeerRowLabel: View {
    let peer: PeerDevice

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Image(systemName: peer.info?.kind.symbolName ?? "desktopcomputer")
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.displayName)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if peer.state == .connecting {
                ProgressView()
            }
        }
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        switch peer.state {
        case .connected: return .green
        case .connecting: return .yellow
        case .discovered: return .blue
        case .disconnected: return .gray
        }
    }

    private var statusText: String {
        switch peer.state {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .discovered: return "Tap to connect"
        case .disconnected: return "Not connected"
        }
    }
}

// MARK: - Peer detail

struct PeerDetailView: View {
    @EnvironmentObject private var service: MultipeerService
    let peerID: String

    @State private var showingFileImporter = false

    private var peer: PeerDevice? {
        service.peers.first { $0.id == peerID }
    }

    private var peerTransfers: [FileTransfer] {
        guard let peer else { return [] }
        return service.transfers
            .filter { $0.peerName == peer.displayName }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        List {
            if let peer {
                deviceInfoSection(peer)
                actionsSection(peer)
                transfersSection
            } else {
                Text("This device is no longer available.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(peer?.displayName ?? "Device")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard let peer else { return }
            switch result {
            case .success(let urls):
                service.sendPickedFiles(urls, to: peer)
            case .failure(let error):
                service.lastError = "File selection failed: \(error.localizedDescription)"
            }
        }
        .onAppear {
            if let peer, peer.state == .connected, peer.info == nil {
                service.requestInfo(from: peer)
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func deviceInfoSection(_ peer: PeerDevice) -> some View {
        Section("Device Info") {
            if let info = peer.info {
                LabeledContent("Name", value: info.name)
                LabeledContent("Kind", value: info.kind.rawValue)
                LabeledContent("Model", value: info.model)
                LabeledContent("OS", value: info.osVersion)
                if let cpu = info.cpuBrand {
                    LabeledContent("CPU", value: cpu)
                }
                if let memory = info.memoryBytes {
                    LabeledContent("Memory", value: ByteCountFormatter.string(fromByteCount: memory, countStyle: .memory))
                }
                if let free = info.freeDiskBytes, let total = info.totalDiskBytes {
                    LabeledContent(
                        "Disk",
                        value: "\(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) free of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
                    )
                }
                if let battery = info.batteryLevel {
                    let charging = (info.isCharging ?? false) ? " (charging)" : ""
                    LabeledContent("Battery", value: "\(Int(battery * 100))%\(charging)")
                }
                if let ip = info.localIP {
                    LabeledContent("IP Address", value: ip)
                }
            } else if peer.state == .connected {
                HStack {
                    Text("Waiting for device info…")
                        .foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                }
            } else {
                Text("Connect to see device details.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func actionsSection(_ peer: PeerDevice) -> some View {
        Section("Actions") {
            if peer.state == .connected {
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Send Files", systemImage: "doc.badge.arrow.up")
                }
                Button {
                    service.sendClipboard(to: peer)
                } label: {
                    Label("Send Clipboard", systemImage: "doc.on.clipboard")
                }
                Button {
                    service.ping(peer)
                } label: {
                    Label("Ping", systemImage: "antenna.radiowaves.left.and.right")
                }
            } else {
                Button {
                    service.invite(peer)
                } label: {
                    Label(
                        peer.state == .connecting ? "Connecting…" : "Connect",
                        systemImage: "link"
                    )
                }
                .disabled(peer.state == .connecting)
            }
        }
    }

    @ViewBuilder
    private var transfersSection: some View {
        if !peerTransfers.isEmpty {
            Section("Transfers") {
                ForEach(peerTransfers) { transfer in
                    TransferRow(transfer: transfer)
                }
            }
        }
    }
}

// MARK: - Transfer row

struct TransferRow: View {
    let transfer: FileTransfer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: transfer.direction == .incoming ? "arrow.down.circle" : "arrow.up.circle")
                    .foregroundStyle(transfer.direction == .incoming ? .blue : .orange)
                Text(transfer.fileName)
                    .lineLimit(1)
                Spacer()
                statusBadge
            }
            if transfer.status == .inProgress {
                ProgressView(value: transfer.progress)
            }
            if let size = transfer.byteSize {
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch transfer.status {
        case .waiting:
            Text("Waiting")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .inProgress:
            Text("\(Int(transfer.progress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let reason):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help(reason)
        }
    }
}

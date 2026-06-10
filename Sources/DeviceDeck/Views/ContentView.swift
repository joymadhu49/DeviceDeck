import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var service: MultipeerService
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selection: String?
    @State private var showTransfers = false
    @State private var dropTargetedPeerID: String?

    // MARK: Derived state

    private var selectedPeer: PeerDevice? {
        guard let selection else { return nil }
        return service.peers.first { $0.id == selection }
    }

    private var isLocalSelected: Bool {
        selection == service.localInfo.id
    }

    private var connectedCount: Int {
        service.peers.filter { $0.state == .connected }.count
    }

    private var activeTransferCount: Int {
        service.transfers.filter { $0.status == .inProgress }.count
    }

    /// Progress of an in-flight transfer to/from the given peer, if any.
    private func activeOutgoingProgress(for peer: PeerDevice) -> Double? {
        service.transfers.first {
            $0.peerName == peer.displayName && $0.status == .inProgress
        }?.progress
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("DeviceDeck")
        .navigationSubtitle(subtitleText)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    rescan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .help("Restart device discovery")

                Button {
                    withAnimation(.default) { showTransfers.toggle() }
                } label: {
                    Label("Transfers", systemImage: "arrow.up.arrow.down.circle")
                        .overlay(alignment: .topTrailing) {
                            if activeTransferCount > 0 {
                                Text("\(activeTransferCount)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .background(.red, in: Capsule())
                                    .offset(x: 8, y: -8)
                            }
                        }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .help(showTransfers ? "Hide the transfers panel" : "Show the transfers panel")
            }
        }
        // While the onboarding cover is up, toolbar buttons remain physically
        // reachable above the overlay — keep them inert so Rescan can't start
        // the service before the user taps Get Started.
        .disabled(!hasCompletedOnboarding)
        .transferCompletionEffects()
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { service.lastError != nil },
                set: { if !$0 { service.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { service.lastError = nil }
        } message: {
            Text(service.lastError ?? "")
        }
        .onAppear {
            if selection == nil {
                selection = service.localInfo.id
            }
        }
        .onChange(of: activeTransferCount) { _, newCount in
            if newCount > 0 && !showTransfers {
                withAnimation(.default) { showTransfers = true }
            }
        }
    }

    private var subtitleText: String {
        connectedCount > 0
            ? (connectedCount == 1 ? "1 device connected" : "\(connectedCount) devices connected")
            : "Searching…"
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("This Mac") {
                localRow
                    .tag(service.localInfo.id)
            }

            Section {
                if service.peers.isEmpty {
                    sidebarEmptyHint
                } else {
                    ForEach(service.peers) { peer in
                        peerRow(peer)
                            .tag(peer.id)
                    }
                }
            } header: {
                Text("Devices")
                    .badge(connectedCount > 0 ? connectedCount : 0)
            }
        }
        .listStyle(.sidebar)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: service.peers.count)
        .animation(.default, value: selection)
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
    }

    private var localRow: some View {
        HStack(spacing: 8) {
            DeviceAvatar(kind: service.localInfo.kind, state: nil, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(service.localInfo.name)
                    .lineLimit(1)
                Text(service.localInfo.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .hoverHighlight()
        .help("This Mac — \(service.localInfo.model)")
    }

    private func peerRow(_ peer: PeerDevice) -> some View {
        let isTargeted = dropTargetedPeerID == peer.id
        return HStack(spacing: 8) {
            DeviceAvatar(
                kind: peer.info?.kind ?? .unknown,
                state: peer.state,
                progress: activeOutgoingProgress(for: peer),
                size: 32
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(peer.displayName)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(peer.state.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if peer.state == .connected, let info = peer.info {
                        if let battery = info.batteryLevel {
                            Text("\(Int(battery * 100))%")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .background(.quaternary, in: Capsule())
                                .help((info.isCharging == true) ? "Battery (charging)" : "Battery")
                        }
                        if let free = info.freeDiskBytes {
                            Text("· \(formattedBytes(free)) free")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .hoverHighlight()
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .help(peerHelpText(peer))
        .contextMenu {
            if peer.state != .connected {
                Button {
                    service.invite(peer)
                } label: {
                    Label("Connect", systemImage: "link")
                }
            }
            Button {
                promptAndSendFiles(to: peer)
            } label: {
                Label("Send Files…", systemImage: "paperplane")
            }
            Button {
                sendClipboard(to: peer)
            } label: {
                Label("Send Clipboard", systemImage: "doc.on.clipboard")
            }
            if peer.state == .connected {
                Button {
                    service.requestInfo(from: peer)
                } label: {
                    Label("Request Info", systemImage: "info.circle")
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls, on: peer)
        } isTargeted: { targeted in
            dropTargetedPeerID = targeted ? peer.id : (dropTargetedPeerID == peer.id ? nil : dropTargetedPeerID)
        }
    }

    private func peerHelpText(_ peer: PeerDevice) -> String {
        var text = "\(peer.displayName) — \(peer.state.displayText)"
        if let model = peer.info?.model {
            text += " — \(model)"
        }
        return text
    }

    private var sidebarEmptyHint: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Looking for devices…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .listRowSeparator(.hidden)
    }

    // MARK: Detail

    private var detail: some View {
        VSplitView {
            Group {
                if isLocalSelected {
                    DeviceDetailView(content: .local(service.localInfo))
                } else if let peer = selectedPeer {
                    DeviceDetailView(content: .peer(peer))
                } else {
                    noSelectionView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

            if showTransfers {
                TransfersView()
                    .frame(minHeight: 130, idealHeight: 190)
            }
        }
        .animation(.default, value: selection)
    }

    private var noSelectionView: some View {
        Group {
            if service.peers.isEmpty {
                searchingView
            } else {
                ContentUnavailableView(
                    "Select a device",
                    systemImage: "macbook.and.iphone",
                    description: Text("Choose a device from the sidebar to see its dashboard.")
                )
            }
        }
    }

    private var searchingView: some View {
        VStack(spacing: 16) {
            RadarView(size: 140)
            Text("Looking for your devices…")
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                Label("Same Wi-Fi network", systemImage: "wifi")
                Label("DeviceDeck open on the other device", systemImage: "macwindow")
                Label("Local Network permission allowed", systemImage: "checkmark.shield")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Button("Rescan") {
                rescan()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func rescan() {
        service.stop()
        service.start()
    }

    private func handleDrop(_ urls: [URL], on peer: PeerDevice) -> Bool {
        guard !urls.isEmpty else { return false }
        if peer.state == .connected {
            service.sendFiles(urls, to: peer)
            ToastCenter.shared.show(
                "Sending \(urls.count) file(s) to \(peer.displayName)",
                symbol: "paperplane.fill"
            )
        } else {
            service.invite(peer)
            ToastCenter.shared.show(
                "Connecting to \(peer.displayName)…",
                symbol: "link"
            )
        }
        return true
    }

    private func promptAndSendFiles(to peer: PeerDevice) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Send"
        panel.message = "Choose files to send to \(peer.displayName)"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            if peer.state == .connected {
                service.sendFiles(panel.urls, to: peer)
                ToastCenter.shared.show(
                    "Sending \(panel.urls.count) file(s) to \(peer.displayName)",
                    symbol: "paperplane.fill"
                )
            } else {
                service.invite(peer)
                ToastCenter.shared.show(
                    "Connecting to \(peer.displayName)…",
                    symbol: "link"
                )
            }
        }
    }

    private func sendClipboard(to peer: PeerDevice) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            ToastCenter.shared.show("Clipboard has no text", symbol: "doc.on.clipboard")
            return
        }
        service.sendClipboard(text, to: peer)
        ToastCenter.shared.show(
            "Clipboard sent to \(peer.displayName)",
            symbol: "doc.on.clipboard.fill"
        )
    }
}

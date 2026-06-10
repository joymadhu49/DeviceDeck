import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var service: MultipeerService
    @State private var selection: String?
    @State private var showTransfers = true

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

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("DeviceDeck")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    service.stop()
                    service.start()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .help("Restart device discovery")
            }
            ToolbarItem {
                Button {
                    withAnimation(.default) { showTransfers.toggle() }
                } label: {
                    Label("Transfers", systemImage: "arrow.up.arrow.down.circle")
                }
                .help(showTransfers ? "Hide the transfers panel" : "Show the transfers panel")
            }
        }
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
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("This Mac") {
                    localRow
                        .tag(service.localInfo.id)
                }

                Section {
                    if service.peers.isEmpty {
                        emptyDevicesPlaceholder
                    } else {
                        ForEach(service.peers) { peer in
                            peerRow(peer)
                                .tag(peer.id)
                        }
                    }
                } header: {
                    HStack {
                        Text("Devices")
                        Spacer()
                        if connectedCount > 0 {
                            Text("\(connectedCount)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(.green, in: Capsule())
                                .help("\(connectedCount) connected")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .animation(.default, value: service.peers)

            Divider()
            statusBar
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 340)
    }

    private var localRow: some View {
        HStack(spacing: 10) {
            IconChip(systemImage: service.localInfo.kind.symbolName, tint: .blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(service.localInfo.name)
                    .lineLimit(1)
                Text(service.localInfo.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func peerRow(_ peer: PeerDevice) -> some View {
        HStack(spacing: 10) {
            IconChip(
                systemImage: (peer.info?.kind ?? .unknown).symbolName,
                tint: peer.state == .connected ? .green : .secondary
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(peer.displayName)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(peer.state.tint)
                        .frame(width: 6, height: 6)
                    Text(peer.state.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var emptyDevicesPlaceholder: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Searching for nearby devices…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .listRowSeparator(.hidden)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if service.isRunning {
                ProgressView()
                    .controlSize(.small)
                Text("Browsing for devices…")
            } else {
                Image(systemName: "pause.circle")
                Text("Discovery paused")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
    }

    private var noSelectionView: some View {
        Group {
            if service.peers.isEmpty {
                ContentUnavailableView {
                    Label("Looking for Devices", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text("Open DeviceDeck on another Mac, iPhone, or iPad on the same network, and it will appear in the sidebar.")
                } actions: {
                    ProgressView()
                        .controlSize(.small)
                }
            } else {
                ContentUnavailableView(
                    "Select a Device",
                    systemImage: "macbook.and.iphone",
                    description: Text("Choose a device from the sidebar to see its dashboard.")
                )
            }
        }
    }
}

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DeviceDetailView: View {
    enum Content {
        case local(DeviceInfo)
        case peer(PeerDevice)
    }

    let content: Content

    @EnvironmentObject private var service: MultipeerService
    @State private var showFileImporter = false
    @State private var showAirDropImporter = false
    @State private var isDropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch content {
                case .local(let info):
                    DeviceHeader(
                        symbol: info.kind.symbolName,
                        name: info.name,
                        subtitle: "\(info.model) · \(info.osVersion)",
                        state: nil
                    )
                    localActions
                    InfoDashboard(info: info)

                case .peer(let peer):
                    DeviceHeader(
                        symbol: (peer.info?.kind ?? .unknown).symbolName,
                        name: peer.displayName,
                        subtitle: peerSubtitle(peer),
                        state: peer.state
                    )
                    peerActions(peer)

                    if peer.state == .connected {
                        dropZone(for: peer)
                        if let info = peer.info {
                            InfoDashboard(info: info)
                        } else {
                            waitingForInfo(peer)
                        }
                    } else {
                        notConnectedView(peer)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.default, value: dropZoneVisible)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .peer(let peer) = content,
                  case .success(let urls) = result else { return }
            service.sendFiles(urls, to: peer)
        }
        .fileImporter(
            isPresented: $showAirDropImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            AirDropService.share(urls: urls)
        }
    }

    private var dropZoneVisible: Bool {
        if case .peer(let peer) = content { return peer.state == .connected }
        return false
    }

    private func peerSubtitle(_ peer: PeerDevice) -> String {
        if let info = peer.info {
            return "\(info.model) · \(info.osVersion)"
        }
        return "Nearby device"
    }

    // MARK: Actions

    private var localActions: some View {
        HStack(spacing: 10) {
            Button {
                showAirDropImporter = true
            } label: {
                Label("AirDrop…", systemImage: "square.and.arrow.up")
            }
            .help("Share files with nearby devices using AirDrop")
            Spacer()
        }
        .controlSize(.large)
    }

    private func peerActions(_ peer: PeerDevice) -> some View {
        HStack(spacing: 10) {
            if peer.state == .connected {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Send Files…", systemImage: "doc.badge.arrow.up")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                        service.sendClipboard(text, to: peer)
                    }
                } label: {
                    Label("Send Clipboard", systemImage: "doc.on.clipboard")
                }

                Button {
                    showAirDropImporter = true
                } label: {
                    Label("AirDrop…", systemImage: "square.and.arrow.up")
                }

                Button {
                    service.requestInfo(from: peer)
                } label: {
                    Label("Refresh Info", systemImage: "arrow.clockwise")
                }
            } else if peer.state == .connecting {
                Button {
                } label: {
                    Label("Connecting…", systemImage: "link")
                }
                .disabled(true)

                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    service.invite(peer)
                } label: {
                    Label("Connect", systemImage: "link")
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .controlSize(.large)
    }

    // MARK: Connection states

    private func notConnectedView(_ peer: PeerDevice) -> some View {
        ContentUnavailableView {
            Label("Not Connected", systemImage: "link.badge.plus")
        } description: {
            Text("Connect to \(peer.displayName) to view its dashboard and share files.")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private func waitingForInfo(_ peer: PeerDevice) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Waiting for device info…")
                .foregroundStyle(.secondary)
            Button("Request Again") {
                service.requestInfo(from: peer)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    // MARK: Drop zone

    private func dropZone(for peer: PeerDevice) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
            VStack(spacing: 2) {
                Text("Drop files to send")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : .primary)
                Text("Files go straight to \(peer.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.10) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .scaleEffect(isDropTargeted ? 1.015 : 1)
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            service.sendFiles(urls, to: peer)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
    }
}

// MARK: - Header

private struct DeviceHeader: View {
    let symbol: String
    let name: String
    let subtitle: String
    let state: PeerConnectionState?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.brandGradient)
                )
                .shadow(color: .blue.opacity(0.25), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 5) {
                Text(name)
                    .font(.title.bold())
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let state {
                StatusCapsule(state: state)
            } else {
                HStack(spacing: 5) {
                    Circle()
                        .fill(.blue)
                        .frame(width: 7, height: 7)
                    Text("This Mac")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.blue.opacity(0.14), in: Capsule())
            }
        }
    }
}

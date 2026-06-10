import SwiftUI
import AppKit
import Foundation
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
    @State private var lastInfoUpdate: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch content {
                case .local(let info):
                    localHeader(info)
                    InfoDashboard(info: info)

                case .peer(let peer):
                    peerHeader(peer)

                    if peer.state == .connected {
                        dropZone(for: peer)
                        if let info = peer.info {
                            InfoDashboard(info: info)
                            updatedFooter(peer)
                        } else {
                            waitingForInfo(peer)
                        }
                    } else {
                        notConnectedHint(peer)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.default, value: dropZoneVisible)
        .onPasteCommand(of: [.fileURL]) { _ in
            pasteFilesToConnectedPeer()
        }
        .onAppear {
            if peerInfo != nil { lastInfoUpdate = Date() }
        }
        .onChange(of: peerInfo) { _, newValue in
            if newValue != nil { lastInfoUpdate = Date() }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .peer(let peer) = content,
                  case .success(let urls) = result else { return }
            sendFiles(urls, to: peer)
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

    // MARK: Derived state

    private var peerInfo: DeviceInfo? {
        if case .peer(let peer) = content { return peer.info }
        return nil
    }

    private var dropZoneVisible: Bool {
        if case .peer(let peer) = content { return peer.state == .connected }
        return false
    }

    // MARK: Header

    private func localHeader(_ info: DeviceInfo) -> some View {
        HStack(alignment: .center, spacing: 16) {
            DeviceAvatar(kind: info.kind, state: nil, size: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(info.name)
                    .font(.title2.bold())
                    .lineLimit(1)
                Text("This Mac · \(info.model) · \(info.osVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            Button {
                showAirDropImporter = true
            } label: {
                Label("AirDrop…", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .help("Share files with nearby devices using AirDrop")
        }
    }

    private func peerHeader(_ peer: PeerDevice) -> some View {
        HStack(alignment: .center, spacing: 16) {
            DeviceAvatar(kind: peer.info?.kind ?? .unknown, state: peer.state, size: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(peer.displayName)
                    .font(.title2.bold())
                    .lineLimit(1)
                Text(peerSubtitle(peer))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                StatusCapsule(state: peer.state)
            }

            Spacer(minLength: 16)

            peerActions(peer)
        }
    }

    private func peerSubtitle(_ peer: PeerDevice) -> String {
        if let info = peer.info {
            return "\(info.model) · \(info.osVersion)"
        }
        return "Nearby device"
    }

    // MARK: Actions

    /// Exactly one `.borderedProminent` button is visible at a time:
    /// "Connect" while not connected, "Send Files…" once connected.
    @ViewBuilder
    private func peerActions(_ peer: PeerDevice) -> some View {
        HStack(spacing: 8) {
            switch peer.state {
            case .connected:
                Button {
                    sendClipboard(to: peer)
                } label: {
                    Label("Send Clipboard", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .help("Send your current clipboard text to \(peer.displayName)")

                Button {
                    showAirDropImporter = true
                } label: {
                    Label("AirDrop…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .help("Share files with nearby devices using AirDrop")

                Button {
                    service.requestInfo(from: peer)
                } label: {
                    Label("Refresh Info", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Request fresh device info from \(peer.displayName)")

                Button {
                    showFileImporter = true
                } label: {
                    Label("Send Files…", systemImage: "doc.badge.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("Choose files to send to \(peer.displayName)")

            case .connecting:
                ProgressView()
                    .controlSize(.small)
                Button {
                } label: {
                    Label("Connecting…", systemImage: "link")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(true)
                .help("Connecting to \(peer.displayName)…")

            case .discovered, .disconnected:
                Button {
                    service.invite(peer)
                } label: {
                    Label("Connect", systemImage: "link")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("Connect to \(peer.displayName)")
            }
        }
    }

    // MARK: Connection states

    private func notConnectedHint(_ peer: PeerDevice) -> some View {
        ContentUnavailableView {
            Label("Not Connected", systemImage: "personalhotspot")
        } description: {
            Text("Connect to see live info and send files.")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private func waitingForInfo(_ peer: PeerDevice) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Waiting for device info…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Request Again") {
                service.requestInfo(from: peer)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    // MARK: Last updated

    private func updatedFooter(_ peer: PeerDevice) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(updatedText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Refresh Info") {
                service.requestInfo(from: peer)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Request fresh device info from \(peer.displayName)")
        }
    }

    private var updatedText: String {
        guard let date = lastInfoUpdate else { return "Updated just now" }
        if Date().timeIntervalSince(date) < 60 {
            return "Updated just now"
        }
        return "Updated \(date.formatted(.relative(presentation: .named)))"
    }

    // MARK: Drop zone

    private func dropZone(for peer: PeerDevice) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.largeTitle.weight(.light))
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: isDropTargeted)
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)

            VStack(spacing: 4) {
                Text("Drop files to send to \(peer.displayName)")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.primary)
                Text("or paste with ⌘V")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(isDropTargeted ? 0.08 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    Color.accentColor.opacity(isDropTargeted ? 1 : 0.45),
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
        )
        .scaleEffect(isDropTargeted ? 1.01 : 1)
        .animation(.spring(duration: 0.3), value: isDropTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            sendFiles(urls, to: peer)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .accessibilityLabel("Drop files to send to \(peer.displayName)")
    }

    // MARK: Sending helpers

    private func sendFiles(_ urls: [URL], to peer: PeerDevice) {
        guard !urls.isEmpty else { return }
        service.sendFiles(urls, to: peer)
        let what = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        ToastCenter.shared.show("Sending \(what) to \(peer.displayName)", symbol: "paperplane.fill")
    }

    private func sendClipboard(to peer: PeerDevice) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            ToastCenter.shared.show("Clipboard has no text to send", symbol: "doc.on.clipboard")
            return
        }
        service.sendClipboard(text, to: peer)
        ToastCenter.shared.show("Clipboard sent to \(peer.displayName)", symbol: "doc.on.clipboard")
    }

    /// ⌘V — read file URLs off the general pasteboard and send them.
    private func pasteFilesToConnectedPeer() {
        guard case .peer(let peer) = content, peer.state == .connected else { return }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else { return }
        sendFiles(urls, to: peer)
    }
}

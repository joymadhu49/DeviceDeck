import SwiftUI
import AppKit

struct TransfersView: View {
    @EnvironmentObject private var service: MultipeerService

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if service.transfers.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(.background)
        .animation(.default, value: service.transfers.count)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Transfers", systemImage: "arrow.up.arrow.down")
                .font(.headline)
            if !service.transfers.isEmpty {
                Text("\(service.transfers.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([service.receivedFilesDirectory])
            } label: {
                Label("Received Files", systemImage: "folder")
            }
            .controlSize(.small)
            .help("Open the received files folder in Finder")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text("No transfers yet")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(service.transfers.reversed()) { transfer in
                    TransferRow(transfer: transfer)
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
    }
}

private struct TransferRow: View {
    let transfer: FileTransfer

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: directionSymbol)
                .font(.title2)
                .foregroundStyle(transfer.direction == .incoming ? Color.green : Color.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(transfer.fileName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if transfer.status == .inProgress {
                    ProgressView(value: transfer.progress)
                        .controlSize(.small)
                        .frame(maxWidth: 260)
                }
            }

            Spacer()

            statusView

            if let url = revealableURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Show in Finder", systemImage: "magnifyingglass")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
                .opacity(isHovering ? 1 : 0.35)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var revealableURL: URL? {
        guard transfer.direction == .incoming, transfer.status == .completed else { return nil }
        return transfer.localURL
    }

    private var subtitle: String {
        var parts: [String] = [
            transfer.direction == .incoming
                ? "From \(transfer.peerName)"
                : "To \(transfer.peerName)"
        ]
        if let size = transfer.byteSize {
            parts.append(formattedBytes(size))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var statusView: some View {
        switch transfer.status {
        case .waiting:
            Text("Waiting")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        case .inProgress:
            Text("\(Int(transfer.progress * 100))%")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.blue)
        case .completed:
            Label("Done", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        case .failed(let reason):
            Label("Failed", systemImage: "xmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.red)
                .help(reason)
        }
    }

    private var directionSymbol: String {
        transfer.direction == .incoming ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
    }
}

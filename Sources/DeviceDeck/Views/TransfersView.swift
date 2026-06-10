import SwiftUI
import AppKit
import UserNotifications

// MARK: - Transfers panel

/// Bottom panel: "Active & recent transfers" list + "Received files" shelf.
/// Shows live rate/ETA per transfer and surfaces failure reasons inline.
/// Completion side-effects (toast/sound/notification) live in
/// `TransferCompletionEffects`, attached to the always-mounted ContentView,
/// so they fire even while this panel is collapsed.
struct TransfersView: View {
    @EnvironmentObject private var service: MultipeerService

    /// Per-transfer rate sampling state (exponentially smoothed).
    @State private var rateSamples: [UUID: RateSample] = [:]

    var body: some View {
        VStack(spacing: 0) {
            transfersSection
            Divider()
            ReceivedFilesShelf()
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator)
                .frame(height: 1)
        }
        .onChange(of: finishedIDs) { _, newValue in
            // Prune sampling state for transfers that reached a terminal state
            // so the dictionary doesn't grow unbounded.
            for id in newValue {
                rateSamples[id] = nil
            }
        }
        .animation(.default, value: service.transfers.count)
    }

    // MARK: Transfers section

    private var transfersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            Divider()
            if service.transfers.isEmpty {
                Text("No transfers yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                transferList
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Label("Active & recent transfers", systemImage: "arrow.up.arrow.down")
                .font(.headline)
            if !service.transfers.isEmpty {
                Text("\(service.transfers.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var transferList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(service.transfers.reversed()) { transfer in
                    TransferRow(
                        transfer: transfer,
                        rateText: rateText(for: transfer)
                    )
                    .onChange(of: transfer.progress) { _, newProgress in
                        sampleRate(for: transfer, progress: newProgress)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 240)
    }

    // MARK: Rate sampling

    private struct RateSample: Equatable {
        var lastProgress: Double
        var lastDate: Date
        var smoothedRate: Double   // bytes per second; 0 when unknown
    }

    private func sampleRate(for transfer: FileTransfer, progress: Double) {
        let now = Date()
        guard let previous = rateSamples[transfer.id] else {
            rateSamples[transfer.id] = RateSample(
                lastProgress: progress, lastDate: now, smoothedRate: 0
            )
            return
        }
        let dt = now.timeIntervalSince(previous.lastDate)
        guard dt > 0.01 else { return }

        // Without a byte size we can't convert progress deltas to bytes.
        guard let total = transfer.byteSize, total > 0 else {
            rateSamples[transfer.id] = RateSample(
                lastProgress: progress, lastDate: now, smoothedRate: 0
            )
            return
        }
        let deltaBytes = max(0, progress - previous.lastProgress) * Double(total)
        let instant = deltaBytes / dt
        // Exponential smoothing: 30% new sample, 70% history.
        let smoothed = previous.smoothedRate > 0
            ? 0.3 * instant + 0.7 * previous.smoothedRate
            : instant
        rateSamples[transfer.id] = RateSample(
            lastProgress: progress, lastDate: now, smoothedRate: smoothed
        )
    }

    /// "<rate> · <eta>" for in-progress transfers (rate-only when size unknown).
    private func rateText(for transfer: FileTransfer) -> String? {
        guard transfer.status == .inProgress,
              let sample = rateSamples[transfer.id],
              sample.smoothedRate > 0 else { return nil }
        let rate = formattedRate(sample.smoothedRate)
        guard let total = transfer.byteSize, total > 0 else { return rate }
        let remainingBytes = max(0, 1 - transfer.progress) * Double(total)
        return "\(rate) · \(formattedETA(remainingBytes / sample.smoothedRate))"
    }

    /// IDs of transfers in a terminal state, used to prune rate samples.
    private var finishedIDs: [UUID] {
        service.transfers.compactMap { transfer in
            switch transfer.status {
            case .completed, .failed: return transfer.id
            case .waiting, .inProgress: return nil
            }
        }
    }
}

// MARK: - Completion side-effects (always-mounted observer)

/// Fires exactly one toast + sound + user notification per finished transfer.
/// Attach to a view that stays mounted for the life of the window (ContentView)
/// so side-effects still fire while the transfers panel is collapsed.
private struct TransferCompletionEffects: ViewModifier {
    @EnvironmentObject private var service: MultipeerService

    /// Transfers whose terminal state (completed/failed) has already fired side-effects.
    @State private var notifiedIDs: Set<UUID> = []
    /// Avoid firing side-effects for transfers that finished before this view appeared.
    @State private var didSeedNotified = false

    func body(content: Content) -> some View {
        content
            .onAppear(perform: seedNotifiedIDs)
            .onChange(of: finishedIDs) { _, newValue in
                handleFinished(newValue)
            }
    }

    /// IDs of transfers in a terminal state, used to detect newly finished ones.
    private var finishedIDs: [UUID] {
        service.transfers.compactMap { transfer in
            switch transfer.status {
            case .completed, .failed: return transfer.id
            case .waiting, .inProgress: return nil
            }
        }
    }

    private func seedNotifiedIDs() {
        guard !didSeedNotified else { return }
        didSeedNotified = true
        notifiedIDs.formUnion(finishedIDs)
    }

    private func handleFinished(_ ids: [UUID]) {
        for transfer in service.transfers where ids.contains(transfer.id) {
            guard !notifiedIDs.contains(transfer.id) else { continue }
            notifiedIDs.insert(transfer.id)

            switch transfer.status {
            case .completed:
                Sounds.transferComplete()
                let message = transfer.direction == .incoming
                    ? "Received \(transfer.fileName) from \(transfer.peerName)"
                    : "Sent \(transfer.fileName)"
                ToastCenter.shared.show(message, symbol: "checkmark.circle.fill")
                postUserNotification(
                    title: transfer.direction == .incoming ? "File received" : "File sent",
                    body: message
                )
            case .failed(let reason):
                Sounds.error()
                ToastCenter.shared.show(
                    "Failed: \(transfer.fileName) — \(reason)",
                    symbol: "xmark.octagon.fill"
                )
            case .waiting, .inProgress:
                break
            }
        }
    }

    /// Best-effort local user notification (skipped when not running in a bundle).
    private func postUserNotification(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil
            )
            try? await center.add(request)
        }
    }
}

extension View {
    /// One-toast/sound/notification-per-finished-transfer observer.
    /// Attach once, on an always-mounted view.
    func transferCompletionEffects() -> some View {
        modifier(TransferCompletionEffects())
    }
}

// MARK: - Transfer row

private struct TransferRow: View {
    let transfer: FileTransfer
    let rateText: String?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: directionSymbol)
                .font(.title2)
                .foregroundStyle(transfer.direction == .incoming ? Color.green : Color.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(transfer.fileName)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if transfer.status == .inProgress {
                    ProgressView(value: transfer.progress)
                        .controlSize(.small)
                        .frame(maxWidth: 280)
                    if let rateText {
                        Text(rateText)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                if case .failed(let reason) = transfer.status {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            statusBadge

            if let url = revealableURL, isHovering {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .hoverHighlight(cornerRadius: 8)
        .onHover { isHovering = $0 }
    }

    private var directionSymbol: String {
        transfer.direction == .incoming ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
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
    private var statusBadge: some View {
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
        case .failed:
            Label("Failed", systemImage: "xmark.octagon.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.red)
        }
    }
}

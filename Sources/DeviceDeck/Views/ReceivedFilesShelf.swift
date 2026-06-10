import SwiftUI
import AppKit
import Foundation
import QuickLook
import UniformTypeIdentifiers

// MARK: - Received files shelf

/// Horizontal shelf of files in `service.receivedFilesDirectory`.
/// Tiles support click-to-select, spacebar / context-menu Quick Look,
/// drag-out to Finder, and Open / Reveal / Copy actions.
struct ReceivedFilesShelf: View {
    @EnvironmentObject private var service: MultipeerService

    @State private var files: [URL] = []
    @State private var selectedURL: URL?
    @State private var previewURL: URL?
    @FocusState private var shelfFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if files.isEmpty {
                Text("Files you receive appear here")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                tiles
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear(perform: refresh)
        .onChange(of: completedIncomingCount) { _, _ in
            refresh()
        }
        .quickLookPreview($previewURL, in: files)
    }

    /// Refresh trigger: a newly completed incoming transfer means a new file on disk.
    private var completedIncomingCount: Int {
        service.transfers.filter {
            $0.direction == .incoming && $0.status == .completed
        }.count
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Received Files")
                .font(.headline)
            Spacer()
            Button {
                refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            Button {
                NSWorkspace.shared.open(service.receivedFilesDirectory)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Open received files folder")
        }
    }

    // MARK: Tiles

    private var tiles: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(files, id: \.self) { url in
                    ReceivedFileTile(
                        url: url,
                        isSelected: selectedURL == url,
                        onSelect: {
                            selectedURL = url
                            // Move keyboard focus to the shelf so spacebar
                            // Quick Look works right after clicking a tile.
                            shelfFocused = true
                        },
                        onQuickLook: { previewURL = url }
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .focusable()
        .focused($shelfFocused)
        .onKeyPress(.space) {
            guard let selectedURL else { return .ignored }
            previewURL = selectedURL
            return .handled
        }
    }

    // MARK: Loading

    private func refresh() {
        let directory = service.receivedFilesDirectory
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey, .isRegularFileKey]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        files = contents
            .filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            }
            .sorted { lhs, rhs in
                fileDate(lhs) > fileDate(rhs)   // newest first
            }

        if let selectedURL, !files.contains(selectedURL) {
            self.selectedURL = nil
        }
    }

    private func fileDate(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return values?.contentModificationDate ?? values?.creationDate ?? .distantPast
    }
}

// MARK: - File tile

private struct ReceivedFileTile: View {
    let url: URL
    let isSelected: Bool
    let onSelect: () -> Void
    let onQuickLook: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)

            Text(url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(sizeText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(width: 96)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .hoverHighlight(cornerRadius: 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        // NOTE: Transferable/FileRepresentation drag is broken on macOS 14 — use onDrag.
        .onDrag {
            NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Open") {
                NSWorkspace.shared.open(url)
            }
            Button("Quick Look", action: onQuickLook)
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
            }
        }
        .help(url.lastPathComponent)
    }

    private var sizeText: String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0
        return formattedBytes(Int64(bytes))
    }
}

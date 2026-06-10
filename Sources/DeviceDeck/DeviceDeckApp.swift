import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct DeviceDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var service = MultipeerService(localInfo: LocalDeviceInfo.collect())
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private var menuBarSymbol: String {
        if NSImage(systemSymbolName: "laptopcomputer.and.iphone", accessibilityDescription: nil) != nil {
            return "laptopcomputer.and.iphone"
        }
        return "display"
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(service)
                .frame(minWidth: 980, minHeight: 640)
                .overlay {
                    if !hasCompletedOnboarding {
                        OnboardingView(onContinue: {
                            hasCompletedOnboarding = true
                            service.start()
                        })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .toastOverlay()
                .onAppear {
                    if hasCompletedOnboarding {
                        service.start()
                    }
                }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About DeviceDeck") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .credits: NSAttributedString(
                            string: "Manage your Apple devices — discovery, dashboards, and file sharing.",
                            attributes: [
                                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                                .foregroundColor: NSColor.secondaryLabelColor
                            ]
                        )
                    ])
                }
            }
            CommandGroup(after: .newItem) {
                Button("Open Received Files") {
                    NSWorkspace.shared.open(service.receivedFilesDirectory)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("DeviceDeck", systemImage: menuBarSymbol) {
            MenuBarPanel()
                .environmentObject(service)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu bar panel

private struct MenuBarPanel: View {
    @EnvironmentObject private var service: MultipeerService
    @Environment(\.openWindow) private var openWindow

    private var connectedPeers: [PeerDevice] {
        service.peers.filter { $0.state == .connected }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Local device row
            HStack(spacing: 8) {
                DeviceAvatar(kind: service.localInfo.kind, state: nil, size: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.localInfo.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text("This Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // Peers
            if service.peers.isEmpty {
                HStack {
                    Spacer()
                    Text("No devices nearby")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(service.peers) { peer in
                        HStack(spacing: 8) {
                            DeviceAvatar(
                                kind: peer.info?.kind ?? .unknown,
                                state: peer.state,
                                size: 28
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(peer.displayName)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                Text(peer.state.displayText)
                                    .font(.caption)
                                    .foregroundStyle(peer.state.tint)
                            }
                            Spacer()
                        }
                        .padding(4)
                        .hoverHighlight()
                    }
                }
            }

            // Send clipboard to connected peers
            if !connectedPeers.isEmpty {
                Divider()
                Text("Send Clipboard")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(connectedPeers) { peer in
                    Button {
                        if let text = NSPasteboard.general.string(forType: .string) {
                            service.sendClipboard(text, to: peer)
                            ToastCenter.shared.show(
                                "Clipboard sent to \(peer.displayName)",
                                symbol: "doc.on.clipboard"
                            )
                        }
                    } label: {
                        Label("To \(peer.displayName)", systemImage: "doc.on.clipboard")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .hoverHighlight()
                }
            }

            Divider()

            HStack {
                Button("Open DeviceDeck") {
                    // Re-key the main window if it still exists; otherwise ask
                    // SwiftUI to (re)open the "main" WindowGroup window.
                    // (SwiftUI tags WindowGroup windows "<id>-AppWindow-N".)
                    let mainWindow = NSApp.windows.first {
                        $0.identifier?.rawValue.hasPrefix("main") == true
                    }
                    if let mainWindow {
                        mainWindow.makeKeyAndOrderFront(nil)
                    } else {
                        openWindow(id: "main")
                    }
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Received Files") {
                    NSWorkspace.shared.open(service.receivedFilesDirectory)
                }
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}

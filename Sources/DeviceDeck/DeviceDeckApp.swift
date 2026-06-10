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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(service)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    service.start()
                }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
    }
}

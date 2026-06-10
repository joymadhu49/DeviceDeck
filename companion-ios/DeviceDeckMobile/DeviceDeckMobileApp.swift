import SwiftUI

@main
struct DeviceDeckMobileApp: App {
    @StateObject private var service = MultipeerService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(service)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                service.start()
                service.refreshReceivedFiles()
            case .background:
                // MultipeerConnectivity sessions don't survive backgrounding;
                // stop cleanly so peers see a disconnect instead of a timeout.
                service.stop()
            default:
                break
            }
        }
    }
}

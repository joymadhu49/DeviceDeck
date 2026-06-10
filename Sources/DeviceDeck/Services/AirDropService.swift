import AppKit

/// Hands files off to the system AirDrop sharing service.
@MainActor
enum AirDropService {

    /// Opens the AirDrop sharing UI for the given file URLs.
    /// - Returns: `true` if the share was initiated, `false` if AirDrop is
    ///   unavailable or cannot share the given items.
    @discardableResult
    static func share(urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return false }
        guard service.canPerform(withItems: urls) else { return false }
        service.perform(withItems: urls)
        return true
    }
}

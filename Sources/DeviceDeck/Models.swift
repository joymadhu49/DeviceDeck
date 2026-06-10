import Foundation

// MARK: - Device identity

enum DeviceKind: String, Codable, Hashable {
    case macMini = "Mac mini"
    case macBook = "MacBook"
    case macDesktop = "Mac"
    case iPhone = "iPhone"
    case iPad = "iPad"
    case unknown = "Device"

    var symbolName: String {
        switch self {
        case .macMini: return "macmini"
        case .macBook: return "laptopcomputer"
        case .macDesktop: return "desktopcomputer"
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// System info describing one device (the local machine or a remote peer).
struct DeviceInfo: Codable, Hashable, Identifiable {
    var id: String                 // stable identifier (hardware UUID or similar)
    var name: String               // user-visible device name
    var kind: DeviceKind
    var model: String              // e.g. "Mac mini (2024)" / "iPhone 16 Pro"
    var osVersion: String          // e.g. "macOS 26.5.1"
    var cpuBrand: String?
    var memoryBytes: Int64?
    var freeDiskBytes: Int64?
    var totalDiskBytes: Int64?
    var batteryLevel: Double?      // 0...1, nil if no battery
    var isCharging: Bool?
    var localIP: String?
    var uptimeSeconds: Double?
}

// MARK: - Peers

enum PeerConnectionState: String, Hashable {
    case discovered, connecting, connected, disconnected
}

struct PeerDevice: Identifiable, Hashable {
    let id: String                 // MCPeerID.displayName-derived key
    var displayName: String
    var info: DeviceInfo?          // populated after handshake
    var state: PeerConnectionState
    var lastSeen: Date
}

// MARK: - File transfers

enum TransferDirection: String { case incoming, outgoing }

enum TransferStatus: Equatable {
    case waiting, inProgress, completed
    case failed(String)
}

struct FileTransfer: Identifiable {
    let id: UUID
    let fileName: String
    let peerName: String
    let direction: TransferDirection
    var progress: Double           // 0...1
    var status: TransferStatus
    var byteSize: Int64?
    var localURL: URL?             // destination (incoming) or source (outgoing)
    let startedAt: Date
}

// MARK: - Wire protocol (messages exchanged between peers)

enum PeerMessage: Codable {
    case deviceInfo(DeviceInfo)    // sent on connect and on request
    case requestInfo
    case clipboard(String)         // share clipboard text to peer
    case ping
    case pong
}

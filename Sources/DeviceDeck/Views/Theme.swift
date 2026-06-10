import SwiftUI

// MARK: - Shared design tokens & helpers

enum Theme {
    /// Brand gradient used for the header glyph chip (matches the app icon).
    static let brandGradient = LinearGradient(
        colors: [.indigo, .blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardCornerRadius: CGFloat = 12
}

extension PeerConnectionState {
    var displayText: String {
        switch self {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .discovered: return "Discovered"
        case .disconnected: return "Disconnected"
        }
    }

    var tint: Color {
        switch self {
        case .connected: return .green
        case .connecting: return .orange
        case .discovered, .disconnected: return .gray
        }
    }
}

func formattedBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

// MARK: - Small reusable pieces

/// SF Symbol in a small rounded-square tinted background (sidebar rows, card titles).
struct IconChip: View {
    let systemImage: String
    var tint: Color = .accentColor
    var side: CGFloat = 26
    var cornerRadius: CGFloat = 6

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: side * 0.52, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(0.16))
            )
    }
}

/// Connection status shown as a tinted capsule (dot + label).
struct StatusCapsule: View {
    let state: PeerConnectionState

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(state.tint)
                .frame(width: 7, height: 7)
            Text(state.displayText)
                .font(.caption.weight(.medium))
                .foregroundStyle(state.tint)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(state.tint.opacity(0.14), in: Capsule())
    }
}

import SwiftUI
import AppKit

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
        HStack(spacing: 4) {
            Circle()
                .fill(state.tint)
                .frame(width: 7, height: 7)
            Text(state.displayText)
                .font(.caption.weight(.medium))
                .foregroundStyle(state.tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(state.tint.opacity(0.14), in: Capsule())
    }
}

// MARK: - Device avatar

/// Circular device avatar with status ring (AirDrop-style).
/// Ring: green = connected, orange = connecting, gray = discovered/disconnected,
/// blue = local device (`state == nil`). When `progress != nil` an accent-colored
/// progress ring replaces the status ring.
struct DeviceAvatar: View {
    let kind: DeviceKind
    let state: PeerConnectionState?   // nil = local device (blue ring)
    var progress: Double? = nil       // 0...1 active transfer ring
    var size: CGFloat = 40

    private var ringColor: Color {
        guard let state else { return .blue }
        return state.tint
    }

    var body: some View {
        ZStack {
            // Inner circle: brand gradient fill with the device glyph.
            Circle()
                .fill(Theme.brandGradient.opacity(0.9))
                .frame(width: size, height: size)

            Image(systemName: kind.symbolName)
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)

            // Outer ring, inset just outside the circle.
            if let progress {
                Circle()
                    .trim(from: 0, to: max(0, min(1, progress)))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size + 7, height: size + 7)
                    .animation(.snappy, value: progress)
            } else {
                Circle()
                    .stroke(ringColor, lineWidth: 2.5)
                    .frame(width: size + 7, height: size + 7)
            }
        }
        .frame(width: size + 10, height: size + 10)
    }
}

// MARK: - Toasts

/// App-wide transient toast system.
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    struct Toast: Identifiable, Equatable {
        let id: UUID
        let symbol: String
        let message: String
    }

    @Published private(set) var current: Toast?

    private var dismissTask: Task<Void, Never>?

    /// Replaces the current toast and auto-dismisses it after 2.5 seconds.
    func show(_ message: String, symbol: String) {
        dismissTask?.cancel()
        let toast = Toast(id: UUID(), symbol: symbol, message: message)
        current = toast
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            if self?.current?.id == toast.id {
                self?.current = nil
            }
        }
    }
}

private struct ToastOverlayModifier: ViewModifier {
    @ObservedObject private var center = ToastCenter.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = center.current {
                HStack(spacing: 8) {
                    Image(systemName: toast.symbol)
                        .foregroundStyle(Color.accentColor)
                    Text(toast.message)
                        .font(.callout.weight(.medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 8)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: center.current)
    }
}

extension View {
    /// Attaches the app-wide toast overlay (top-center capsule).
    func toastOverlay() -> some View {
        modifier(ToastOverlayModifier())
    }
}

// MARK: - Sounds

/// System sounds (respect UserDefaults bool "soundsEnabled", default true).
enum Sounds {
    private static var enabled: Bool {
        if UserDefaults.standard.object(forKey: "soundsEnabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "soundsEnabled")
    }

    static func transferComplete() {
        guard enabled else { return }
        NSSound(named: "Glass")?.play()
    }

    static func error() {
        guard enabled else { return }
        NSSound(named: "Funk")?.play()
    }
}

// MARK: - Hover highlight

private struct HoverHighlightModifier: ViewModifier {
    let cornerRadius: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
    }
}

extension View {
    /// macOS hover row highlight.
    func hoverHighlight(cornerRadius: CGFloat = 6) -> some View {
        modifier(HoverHighlightModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Radar

/// Animated radar/pulse view for "searching" states: concentric circles
/// expanding and fading from a center dot, accent tinted, loops forever.
struct RadarView: View {
    var size: CGFloat = 120

    private let ringCount = 3
    private let period: Double = 2.4

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<ringCount, id: \.self) { index in
                    let phase = (time / period + Double(index) / Double(ringCount))
                        .truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(Color.accentColor.opacity(1 - phase), lineWidth: 2)
                        .frame(width: size * phase, height: size * phase)
                }
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: size * 0.08, height: size * 0.08)
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Rate / ETA formatting

/// "4.2 MB/s"
func formattedRate(_ bytesPerSecond: Double) -> String {
    guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return "—" }
    let formatted = ByteCountFormatter.string(
        fromByteCount: Int64(bytesPerSecond),
        countStyle: .file
    )
    return "\(formatted)/s"
}

/// "12s" / "2m 30s" / "—" if not finite.
func formattedETA(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "—" }
    let total = Int(seconds.rounded())
    if total < 60 {
        return "\(total)s"
    }
    let minutes = total / 60
    let remainder = total % 60
    if minutes < 60 {
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }
    let hours = minutes / 60
    let remMinutes = minutes % 60
    return remMinutes == 0 ? "\(hours)h" : "\(hours)h \(remMinutes)m"
}

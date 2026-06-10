import SwiftUI
import AppKit
import Foundation

// MARK: - Onboarding (first-run welcome + Local Network permission priming)

/// Full-window first-run cover. Welcomes the user, explains what DeviceDeck
/// does, and — most importantly — primes the one-shot macOS Local Network
/// permission prompt before it appears, so the user knows to choose Allow.
struct OnboardingView: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                hero
                    .staged(0, revealed: revealed, reduceMotion: reduceMotion)

                featureRows
                    .staged(1, revealed: revealed, reduceMotion: reduceMotion)

                VStack(spacing: 12) {
                    permissionCard
                    sameWiFiHint
                }
                .staged(2, revealed: revealed, reduceMotion: reduceMotion)

                callToAction
                    .staged(3, revealed: revealed, reduceMotion: reduceMotion)
            }
            .frame(maxWidth: 520)
            .padding(24)
        }
        .onAppear {
            guard !revealed else { return }
            if reduceMotion {
                revealed = true
            } else {
                withAnimation { revealed = true }
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 16) {
            ZStack {
                if !reduceMotion {
                    RadarView(size: 168)
                        .opacity(0.18)
                }

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.brandGradient)
                    .frame(width: 96, height: 96)
                    .shadow(color: .indigo.opacity(0.3), radius: 12, y: 4)

                Image(systemName: "macbook.and.iphone")
                    .font(.system(size: 44, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
            .frame(width: 168, height: 168)

            VStack(spacing: 8) {
                Text("Welcome to DeviceDeck")
                    .font(.largeTitle.bold())

                Text("See, manage, and share files between your Macs and iPhones — entirely on your own Wi-Fi.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: Features

    private var featureRows: some View {
        VStack(alignment: .leading, spacing: 16) {
            FeatureRow(
                symbol: "dot.radiowaves.left.and.right",
                tint: .blue,
                title: "Find your devices",
                detail: "Automatic discovery on your network — no setup, no accounts."
            )
            FeatureRow(
                symbol: "gauge.with.dots.needle.67percent",
                tint: .green,
                title: "Live device dashboards",
                detail: "Storage, battery, and system info at a glance."
            )
            FeatureRow(
                symbol: "square.and.arrow.up.on.square",
                tint: .orange,
                title: "Drag-and-drop sharing",
                detail: "Files and clipboard fly between devices — nothing leaves your network."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    // MARK: Permission priming

    private var permissionCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.indigo)

            VStack(alignment: .leading, spacing: 4) {
                Text("Local Network access")
                    .font(.footnote.weight(.semibold))
                Text("Next, macOS will ask for Local Network access. DeviceDeck needs it to find your devices — your files never leave your Wi-Fi. Choose Allow when prompted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(.quinary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }

    private var sameWiFiHint: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Install DeviceDeck on your other devices, keep them on the same Wi-Fi, and they'll appear automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    // MARK: CTA

    private var callToAction: some View {
        VStack(spacing: 8) {
            Button(action: onContinue) {
                Text("Get Started")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Text("You can change this later in System Settings → Privacy & Security → Local Network.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Feature row

private struct FeatureRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconChip(systemImage: symbol, tint: tint, side: 32, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Staged entrance

/// Gentle staggered entrance: fade + small upward slide, spring-timed.
/// When Reduce Motion is on the content simply appears in place.
private struct StagedAppearModifier: ViewModifier {
    let index: Int
    let revealed: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 16)
                .animation(
                    .spring(response: 0.55, dampingFraction: 0.85)
                        .delay(Double(index) * 0.12),
                    value: revealed
                )
        }
    }
}

private extension View {
    func staged(_ index: Int, revealed: Bool, reduceMotion: Bool) -> some View {
        modifier(StagedAppearModifier(index: index, revealed: revealed, reduceMotion: reduceMotion))
    }
}

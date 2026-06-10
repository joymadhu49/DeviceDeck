import SwiftUI
import AppKit

// MARK: - Dashboard grid

struct InfoDashboard: View {
    let info: DeviceInfo

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            if info.totalDiskBytes != nil {
                StorageCard(info: info)
            }
            if info.batteryLevel != nil {
                BatteryCard(info: info)
            }
            if info.memoryBytes != nil {
                MemoryCard(info: info)
            }
            SystemCard(info: info)
            NetworkCard(info: info)
        }
    }
}

// MARK: - Card chrome

private struct InfoCard<Content: View>: View {
    let title: String
    let symbol: String
    var tint: Color = .blue
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IconChip(systemImage: symbol, tint: tint, side: 24, cornerRadius: 6)
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.6)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }
}

// MARK: - Storage

struct StorageCard: View {
    let info: DeviceInfo

    private var total: Int64 { info.totalDiskBytes ?? 0 }
    private var free: Int64 { info.freeDiskBytes ?? 0 }
    private var used: Int64 { max(total - free, 0) }
    private var usedFraction: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }

    var body: some View {
        InfoCard(title: "Storage", symbol: "internaldrive", tint: .purple) {
            HStack(spacing: 12) {
                Gauge(value: usedFraction) {
                    EmptyView()
                } currentValueLabel: {
                    Text(usedFraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption2)
                        .monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Gradient(colors: [.green, .yellow, .orange, .red]))

                VStack(alignment: .leading, spacing: 4) {
                    Text(formattedBytes(free))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text("free of \(formattedBytes(total))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Battery

struct BatteryCard: View {
    let info: DeviceInfo

    private var level: Double { info.batteryLevel ?? 0 }
    private var charging: Bool { info.isCharging ?? false }

    private var levelTint: Color {
        if level < 0.2 { return .red }
        if level < 0.4 { return .orange }
        return .green
    }

    var body: some View {
        InfoCard(
            title: "Battery",
            symbol: charging ? "battery.100percent.bolt" : "battery.75percent",
            tint: levelTint
        ) {
            HStack(spacing: 12) {
                Gauge(value: level) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: charging ? "bolt.fill" : "battery.100percent")
                        .font(.caption2)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(levelTint)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(level.formatted(.percent.precision(.fractionLength(0))))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        if charging {
                            Image(systemName: "bolt.fill")
                                .font(.callout)
                                .foregroundStyle(.yellow)
                        }
                    }
                    Text(charging ? "Charging" : "On Battery")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .animation(.snappy, value: level)
        }
    }
}

// MARK: - Memory

struct MemoryCard: View {
    let info: DeviceInfo

    var body: some View {
        InfoCard(title: "Memory", symbol: "memorychip", tint: .teal) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedBytes(info.memoryBytes ?? 0))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text("Installed RAM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - System

struct SystemCard: View {
    let info: DeviceInfo

    private var uptimeText: String? {
        guard let seconds = info.uptimeSeconds else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds)
    }

    var body: some View {
        InfoCard(title: "System", symbol: "cpu", tint: .blue) {
            VStack(alignment: .leading, spacing: 4) {
                Text(info.cpuBrand ?? info.model)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(info.osVersion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let uptime = uptimeText {
                    Text("Up \(uptime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Network

struct NetworkCard: View {
    let info: DeviceInfo

    var body: some View {
        InfoCard(title: "Network", symbol: "network", tint: .indigo) {
            VStack(alignment: .leading, spacing: 4) {
                Text(info.localIP ?? "No IP address")
                    .font(.title3.weight(.semibold))
                    .monospaced()
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text("ID \(info.id)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }
}

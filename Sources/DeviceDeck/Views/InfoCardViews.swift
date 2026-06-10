import SwiftUI

// MARK: - Dashboard grid

struct InfoDashboard: View {
    let info: DeviceInfo

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            SystemCard(info: info)
            if info.totalDiskBytes != nil {
                StorageCard(info: info)
            }
            if info.memoryBytes != nil {
                MemoryCard(info: info)
            }
            if info.batteryLevel != nil {
                BatteryCard(info: info)
            }
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.6)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(.quinary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
        )
    }
}

// MARK: - Storage

struct StorageCard: View {
    let info: DeviceInfo

    private var total: Int64 { info.totalDiskBytes ?? 0 }
    private var free: Int64 { info.freeDiskBytes ?? 0 }
    private var used: Int64 { max(total - free, 0) }
    private var fraction: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }

    private var fullnessTint: Color {
        if fraction > 0.9 { return .red }
        if fraction > 0.75 { return .orange }
        return .green
    }

    var body: some View {
        InfoCard(title: "Storage", symbol: "internaldrive", tint: .purple) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(fraction.formatted(.percent.precision(.fractionLength(0)))) used")
                    .font(.system(.title3, design: .rounded).weight(.semibold))

                Gauge(value: fraction) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(fullnessTint)

                HStack {
                    Text("\(formattedBytes(used)) used")
                    Spacer()
                    Text("\(formattedBytes(free)) free")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("\(formattedBytes(total)) total")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Memory

struct MemoryCard: View {
    let info: DeviceInfo

    var body: some View {
        InfoCard(title: "Memory", symbol: "memorychip", tint: .teal) {
            VStack(alignment: .leading, spacing: 6) {
                Text(formattedBytes(info.memoryBytes ?? 0))
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                Text("Installed RAM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        if charging { return .green }
        if level < 0.2 { return .red }
        if level < 0.4 { return .orange }
        return .green
    }

    var body: some View {
        InfoCard(title: "Battery", symbol: charging ? "battery.100percent.bolt" : "battery.75percent", tint: levelTint) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(level.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                    if charging {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.yellow)
                    }
                }
                Gauge(value: level) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(levelTint)

                Text(charging ? "Charging" : "On Battery")
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
            VStack(alignment: .leading, spacing: 6) {
                row(label: "Model", value: info.model)
                row(label: "OS", value: info.osVersion)
                if let chip = info.cpuBrand {
                    row(label: "Chip", value: chip)
                }
                if let ip = info.localIP {
                    row(label: "IP", value: ip)
                }
                if let uptime = uptimeText {
                    row(label: "Uptime", value: uptime)
                }
            }
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

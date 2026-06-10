import Foundation
import IOKit
import IOKit.ps

/// Collects real system information about the local Mac.
enum LocalDeviceInfo {

    static func collect() -> DeviceInfo {
        let modelIdentifier = sysctlString("hw.model") ?? "Mac"
        let kind = deviceKind(forModelIdentifier: modelIdentifier)
        let battery = batteryStatus()
        let disk = diskCapacity()

        return DeviceInfo(
            id: hardwareUUID() ?? persistedFallbackUUID(),
            name: Host.current().localizedName ?? "Mac",
            kind: kind,
            model: friendlyModelName(forModelIdentifier: modelIdentifier, kind: kind),
            osVersion: osVersionString(),
            cpuBrand: sysctlString("machdep.cpu.brand_string"),
            memoryBytes: Int64(clamping: ProcessInfo.processInfo.physicalMemory),
            freeDiskBytes: disk.free,
            totalDiskBytes: disk.total,
            batteryLevel: battery?.level,
            isCharging: battery?.isCharging,
            localIP: primaryIPv4Address(),
            uptimeSeconds: ProcessInfo.processInfo.systemUptime
        )
    }

    // MARK: - Identity

    /// Hardware UUID (IOPlatformUUID) from IOPlatformExpertDevice.
    private static func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }

        return property.takeRetainedValue() as? String
    }

    private static func persistedFallbackUUID() -> String {
        let key = "DeviceDeck.localDeviceUUID"
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key) {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: key)
        return fresh
    }

    // MARK: - Model

    private static func deviceKind(forModelIdentifier identifier: String) -> DeviceKind {
        if identifier.contains("Macmini") { return .macMini }
        if identifier.contains("MacBook") { return .macBook }
        return .macDesktop
    }

    private static func friendlyModelName(forModelIdentifier identifier: String, kind: DeviceKind) -> String {
        // Best effort: map common identifier families to friendly names,
        // keeping the raw identifier for precision.
        let family: String
        if identifier.contains("Macmini") {
            family = "Mac mini"
        } else if identifier.contains("MacBookPro") {
            family = "MacBook Pro"
        } else if identifier.contains("MacBookAir") {
            family = "MacBook Air"
        } else if identifier.contains("MacBook") {
            family = "MacBook"
        } else if identifier.contains("iMac") {
            family = "iMac"
        } else if identifier.contains("MacPro") {
            family = "Mac Pro"
        } else if identifier.contains("MacStudio") {
            family = "Mac Studio"
        } else if identifier.hasPrefix("Mac") {
            family = kind.rawValue
        } else {
            return identifier
        }
        return "\(family) (\(identifier))"
    }

    // MARK: - OS version

    private static func osVersionString() -> String {
        // operatingSystemVersionString looks like "Version 15.5 (Build 24F74)"
        var version = ProcessInfo.processInfo.operatingSystemVersionString
        if version.hasPrefix("Version ") {
            version.removeFirst("Version ".count)
        }
        return "macOS " + version
    }

    // MARK: - sysctl

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: - Disk

    private static func diskCapacity() -> (free: Int64?, total: Int64?) {
        let rootURL = URL(fileURLWithPath: "/")
        guard let values = try? rootURL.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ]) else {
            return (nil, nil)
        }
        let free = values.volumeAvailableCapacityForImportantUsage
        let total = values.volumeTotalCapacity.map(Int64.init)
        return (free, total)
    }

    // MARK: - Battery

    private static func batteryStatus() -> (level: Double, isCharging: Bool)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            // Only consider internal batteries.
            if let type = description[kIOPSTypeKey] as? String,
               type != kIOPSInternalBatteryType {
                continue
            }
            guard let capacity = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int,
                  max > 0
            else { continue }

            let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            return (Double(capacity) / Double(max), isCharging)
        }
        return nil // No battery (e.g. Mac mini / desktop)
    }

    // MARK: - Network

    private static func primaryIPv4Address() -> String? {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let first = firstAddress else { return nil }
        defer { freeifaddrs(firstAddress) }

        var candidates: [(name: String, address: String)] = []

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = pointer?.pointee {
            defer { pointer = interface.ifa_next }

            guard let addr = interface.ifa_addr,
                  addr.pointee.sa_family == sa_family_t(AF_INET)
            else { continue }

            let flags = Int32(interface.ifa_flags)
            // Skip loopback and down interfaces.
            guard (flags & IFF_LOOPBACK) == 0, (flags & IFF_UP) != 0 else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                              &hostname, socklen_t(hostname.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }

            let name = String(cString: interface.ifa_name)
            let address = String(cString: hostname)
            candidates.append((name, address))
        }

        // Prefer en0, then en1, then any other non-loopback IPv4.
        for preferred in ["en0", "en1"] {
            if let match = candidates.first(where: { $0.name == preferred }) {
                return match.address
            }
        }
        return candidates.first?.address
    }
}

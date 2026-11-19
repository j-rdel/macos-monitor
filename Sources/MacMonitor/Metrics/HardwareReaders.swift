import Darwin
import Foundation
import IOKit

// MARK: - GPU

enum GPUReader {
    static func utilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                  let value = (stats["Device Utilization %"] as? NSNumber)?.doubleValue else { continue }
            best = max(best ?? 0, value / 100)
        }
        return best
    }
}

// MARK: - Disk

struct DiskSnapshot {
    var name: String
    var total: Int64
    var available: Int64
    var usedFraction: Double { total > 0 ? Double(total - available) / Double(total) : 0 }
}

enum DiskReader {
    static func read() -> DiskSnapshot? {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return nil }
        return DiskSnapshot(name: values.volumeName ?? "Disco",
                            total: Int64(total),
                            available: values.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

// MARK: - Network

struct NetworkSnapshot {
    var download: Double = 0 // bytes/s
    var upload: Double = 0
}

final class NetworkReader {
    private var last: (rx: UInt64, tx: UInt64, time: Date)?

    func read() -> NetworkSnapshot {
        let now = Date()
        let (rx, tx) = Self.totals()
        defer { last = (rx, tx, now) }
        guard let last else { return NetworkSnapshot() }
        let elapsed = now.timeIntervalSince(last.time)
        guard elapsed > 0 else { return NetworkSnapshot() }
        return NetworkSnapshot(download: Double(rx &- last.rx) / elapsed,
                               upload: Double(tx &- last.tx) / elapsed)
    }

    /// Soma bytes (64 bits) das interfaces físicas "en*" via NET_RT_IFLIST2.
    private static func totals() -> (UInt64, UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return (0, 0) }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return (0, 0) }

        var rx: UInt64 = 0, tx: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(info.ifm_index), &nameBuffer) != nil,
                       String(cString: nameBuffer).hasPrefix("en") {
                        rx += info.ifm_data.ifi_ibytes
                        tx += info.ifm_data.ifi_obytes
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return (rx, tx)
    }
}

// MARK: - Battery

struct BatterySnapshot {
    enum State { case charging, charged, onAC, discharging }
    var percent: Double
    var state: State
    var minutesRemaining: Int?
    var cycles: Int?
    var health: Double?
    var temperature: Double?
    var watts: Double?
}

enum BatteryReader {
    static func read() -> BatterySnapshot? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any] else { return nil }

        func number(_ key: String) -> NSNumber? { dict[key] as? NSNumber }

        guard let current = number("CurrentCapacity")?.doubleValue,
              let max = number("MaxCapacity")?.doubleValue, max > 0 else { return nil }

        let external = (dict["ExternalConnected"] as? Bool) ?? false
        let charging = (dict["IsCharging"] as? Bool) ?? false
        let full = (dict["FullyCharged"] as? Bool) ?? false

        let state: BatterySnapshot.State
        if charging { state = .charging }
        else if external { state = full ? .charged : .onAC }
        else { state = .discharging }

        var minutes: Int?
        let timeKey = charging ? "AvgTimeToFull" : "AvgTimeToEmpty"
        if state == .charging || state == .discharging,
           let value = number(timeKey)?.intValue, value > 0, value < 65535 {
            minutes = value
        }

        var health: Double?
        if let rawMax = number("AppleRawMaxCapacity")?.doubleValue,
           let design = number("DesignCapacity")?.doubleValue, design > 0 {
            health = min(rawMax / design, 1)
        }

        var watts: Double?
        if let mV = number("Voltage")?.doubleValue, let mA = number("Amperage")?.int64Value {
            watts = abs(mV * Double(mA)) / 1_000_000
        }

        return BatterySnapshot(percent: current / max,
                               state: state,
                               minutesRemaining: minutes,
                               cycles: number("CycleCount")?.intValue,
                               health: health,
                               temperature: number("Temperature").map { $0.doubleValue / 100 },
                               watts: watts)
    }
}

import Darwin
import Foundation

enum MemoryPressure {
    case normal, warning, critical
}

struct MemorySnapshot {
    var total: UInt64 = ProcessInfo.processInfo.physicalMemory
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var pressure: MemoryPressure = .normal

    var used: UInt64 { app + wired + compressed }
    var usedFraction: Double { total > 0 ? min(Double(used) / Double(total), 1) : 0 }
}

enum MemoryReader {
    static func read() -> MemorySnapshot {
        var snapshot = MemorySnapshot()

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let internalPages = UInt64(stats.internal_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            snapshot.app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
            snapshot.wired = UInt64(stats.wire_count) * page
            snapshot.compressed = UInt64(stats.compressor_page_count) * page
            snapshot.cached = (UInt64(stats.external_page_count) + purgeable) * page
        }

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            snapshot.swapUsed = swap.xsu_used
        }

        switch Sysctl.int32("kern.memorystatus_vm_pressure_level") ?? 1 {
        case 4: snapshot.pressure = .critical
        case 2: snapshot.pressure = .warning
        default: snapshot.pressure = .normal
        }
        return snapshot
    }
}

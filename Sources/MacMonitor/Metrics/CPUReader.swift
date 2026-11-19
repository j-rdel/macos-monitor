import Darwin
import Foundation

struct CPUSnapshot {
    var total: Double = 0
    var user: Double = 0
    var system: Double = 0
    /// Uso por núcleo (0...1), na ordem do kernel.
    var cores: [Double] = []
    /// Quantos dos primeiros núcleos são de eficiência.
    var efficiencyCores: Int = 0
}

final class CPUReader {
    private var previous: [[UInt32]] = []
    private let efficiencyCores = Int(Sysctl.int32("hw.perflevel1.logicalcpu") ?? 0)

    func read() -> CPUSnapshot {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return CPUSnapshot() }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        var current: [[UInt32]] = []
        current.reserveCapacity(Int(cpuCount))
        for core in 0..<Int(cpuCount) {
            current.append((0..<states).map { UInt32(bitPattern: info[core * states + $0]) })
        }

        var snapshot = CPUSnapshot(efficiencyCores: efficiencyCores)
        var sumUser: UInt64 = 0, sumSystem: UInt64 = 0, sumAll: UInt64 = 0

        for (index, ticks) in current.enumerated() {
            let prev = index < previous.count ? previous[index] : [0, 0, 0, 0]
            let user = UInt64(ticks[Int(CPU_STATE_USER)] &- prev[Int(CPU_STATE_USER)])
            let system = UInt64(ticks[Int(CPU_STATE_SYSTEM)] &- prev[Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(ticks[Int(CPU_STATE_IDLE)] &- prev[Int(CPU_STATE_IDLE)])
            let nice = UInt64(ticks[Int(CPU_STATE_NICE)] &- prev[Int(CPU_STATE_NICE)])
            let all = user + system + idle + nice

            snapshot.cores.append(all > 0 ? Double(user + system + nice) / Double(all) : 0)
            sumUser += user + nice
            sumSystem += system
            sumAll += all
        }
        previous = current

        if sumAll > 0 {
            snapshot.user = Double(sumUser) / Double(sumAll)
            snapshot.system = Double(sumSystem) / Double(sumAll)
            snapshot.total = snapshot.user + snapshot.system
        }
        return snapshot
    }

    static func loadAverage() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) > 0 ? loads[0] : 0
    }
}

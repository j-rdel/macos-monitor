import Foundation
import Observation

@MainActor
@Observable
final class SystemMonitor {
    static let historyLength = 60

    private(set) var cpu = CPUSnapshot()
    private(set) var cpuHistory = [Double](repeating: 0, count: historyLength)
    private(set) var loadAverage: Double = 0
    private(set) var memory = MemorySnapshot()
    private(set) var temperatures = TemperatureSnapshot()
    private(set) var gpu: Double?
    private(set) var disk: DiskSnapshot?
    private(set) var network = NetworkSnapshot()
    private(set) var battery: BatterySnapshot?
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    let chipName = Sysctl.string("machdep.cpu.brand_string") ?? "Mac"
    let bootTime = Sysctl.bootTime

    @ObservationIgnored private let cpuReader = CPUReader()
    @ObservationIgnored private let temperatureReader = TemperatureReader()
    @ObservationIgnored private let networkReader = NetworkReader()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var tick = 0

    init() {
        refresh()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        cpu = cpuReader.read()
        cpuHistory.append(cpu.total)
        cpuHistory.removeFirst(max(0, cpuHistory.count - Self.historyLength))
        loadAverage = CPUReader.loadAverage()
        memory = MemoryReader.read()
        temperatures = temperatureReader.read()
        gpu = GPUReader.utilization()
        network = networkReader.read()
        thermalState = ProcessInfo.processInfo.thermalState

        // Coisas que mudam devagar: a cada ~10 s.
        if tick % 5 == 0 {
            disk = DiskReader.read()
            battery = BatteryReader.read()
        }
        tick += 1
    }

    var uptime: TimeInterval {
        bootTime.map { Date().timeIntervalSince($0) } ?? ProcessInfo.processInfo.systemUptime
    }
}

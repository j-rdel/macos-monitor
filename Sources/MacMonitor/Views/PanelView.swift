import ServiceManagement
import SwiftUI

struct PanelView: View {
    nonisolated(unsafe) static var isSnapshot = false
    let monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderSection(monitor: monitor)
            PanelDivider()
            CPUSection(cpu: monitor.cpu, history: monitor.cpuHistory, load: monitor.loadAverage, gpu: monitor.gpu)
            PanelDivider()
            MemorySection(memory: monitor.memory)
            PanelDivider()
            TemperatureSection(temps: monitor.temperatures, thermal: monitor.thermalState)
            PanelDivider()
            StorageNetworkSection(disk: monitor.disk, network: monitor.network)
            if let battery = monitor.battery {
                PanelDivider()
                BatterySection(battery: battery)
            }
            PanelDivider()
            FooterSection()
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
        .frame(width: 300)
    }
}

// MARK: - Cabeçalho

private struct HeaderSection: View {
    let monitor: SystemMonitor

    @AppStorage(Settings.barCPU) private var showCPU = true
    @AppStorage(Settings.barMemory) private var showMemory = true
    @AppStorage(Settings.barTemperature) private var showTemperature = true
    @AppStorage(Settings.barNetwork) private var showNetwork = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.chipName)
                    .font(.system(size: 13, weight: .bold))
                Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString.split(separator: " ").dropFirst().first ?? "") · ligado há \(Fmt.duration(monitor.uptime))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if PanelView.isSnapshot {
                // ImageRenderer não desenha Menu; mostra só o ícone nas capturas.
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                settingsMenu
            }
        }
        .padding(.horizontal, 14)
    }

    private var settingsMenu: some View {
            Menu {
                Section("Mostrar na barra de menus") {
                    Toggle("CPU", isOn: $showCPU)
                    Toggle("Memória", isOn: $showMemory)
                    Toggle("Temperatura", isOn: $showTemperature)
                    Toggle("Rede (download)", isOn: $showNetwork)
                }
                Divider()
                Toggle("Abrir ao iniciar sessão", isOn: $launchAtLogin)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .onChange(of: launchAtLogin) { _, enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
    }
}

// MARK: - CPU

private struct CPUSection: View {
    let cpu: CPUSnapshot
    let history: [Double]
    let load: Double
    let gpu: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "CPU", trailing: Fmt.percent(cpu.total))
            Sparkline(values: history, tint: .level(cpu.total))
                .frame(height: 40)

            HStack(alignment: .bottom, spacing: 12) {
                CoreBars(cores: cpu.cores, efficiency: cpu.efficiencyCores)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    detail("Usuário", Fmt.percent(cpu.user))
                    detail("Sistema", Fmt.percent(cpu.system))
                    detail("Carga", load.formatted(.number.precision(.fractionLength(2))))
                }
            }

            if let gpu {
                HStack(spacing: 10) {
                    Text("GPU").font(.system(size: 12)).frame(width: 30, alignment: .leading)
                    UsageBar(value: gpu, tint: .level(gpu))
                    Text(Fmt.percent(gpu))
                        .font(.system(size: 12)).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit().frame(minWidth: 32, alignment: .trailing)
        }
        .font(.system(size: 11))
    }
}

private struct CoreBars: View {
    let cores: [Double]
    let efficiency: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(cores.enumerated()), id: \.offset) { index, value in
                    let isEfficiency = index < efficiency
                    ZStack(alignment: .bottom) {
                        Capsule().fill(Color.primary.opacity(0.1))
                        Capsule()
                            .fill(isEfficiency ? Color.teal : Color.level(value))
                            .frame(height: max(3, 30 * value))
                    }
                    .frame(width: 7, height: 30)
                    .animation(.easeOut(duration: 0.35), value: value)
                }
            }
            if efficiency > 0 {
                HStack(spacing: 8) {
                    LegendDot(color: .teal, label: "\(efficiency) E")
                    LegendDot(color: .accentColor, label: "\(cores.count - efficiency) P")
                }
            }
        }
    }
}

// MARK: - Memória

private struct MemorySection: View {
    let memory: MemorySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Memória",
                          trailing: "\(Fmt.gigabytes(memory.used)) de \(Fmt.gigabytes(memory.total))")

            SegmentedBar(segments: [
                (fraction(memory.app), .accentColor),
                (fraction(memory.wired), .orange),
                (fraction(memory.compressed), .purple),
            ])

            HStack(spacing: 10) {
                LegendDot(color: .accentColor, label: "Apps")
                LegendDot(color: .orange, label: "Fixa")
                LegendDot(color: .purple, label: "Comprimida")
            }

            HStack {
                HStack(spacing: 5) {
                    Circle().fill(pressureColor).frame(width: 7, height: 7)
                    Text("Pressão \(pressureLabel)")
                }
                Spacer()
                Text("Swap \(Fmt.gigabytes(memory.swapUsed))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.system(size: 12))
        }
        .padding(.horizontal, 14)
    }

    private func fraction(_ bytes: UInt64) -> Double {
        memory.total > 0 ? Double(bytes) / Double(memory.total) : 0
    }

    private var pressureLabel: String {
        switch memory.pressure {
        case .normal: "normal"
        case .warning: "alta"
        case .critical: "crítica"
        }
    }

    private var pressureColor: Color {
        switch memory.pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

// MARK: - Temperatura

private struct TemperatureSection: View {
    let temps: TemperatureSnapshot
    let thermal: ProcessInfo.ThermalState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Temperatura", trailing: thermalLabel)
            HStack {
                tile(temps.cpu, "CPU")
                tile(temps.cpuMax, "CPU máx.")
                tile(temps.ssd, "SSD")
                if temps.battery != nil { tile(temps.battery, "Bateria") }
            }
        }
        .padding(.horizontal, 14)
    }

    private func tile(_ value: Double?, _ label: String) -> some View {
        StatTile(value: value.map(Fmt.temperature) ?? "—",
                 label: label,
                 tint: value.map(Color.temperature) ?? .secondary)
    }

    private var thermalLabel: String {
        switch thermal {
        case .nominal: "Térmico normal"
        case .fair: "Térmico moderado"
        case .serious: "Térmico alto"
        case .critical: "Térmico crítico"
        @unknown default: ""
        }
    }
}

// MARK: - Disco e rede

private struct StorageNetworkSection: View {
    let disk: DiskSnapshot?
    let network: NetworkSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let disk {
                SectionHeader(title: disk.name, trailing: "\(Fmt.storage(disk.available)) livres")
                UsageBar(value: disk.usedFraction, tint: .level(disk.usedFraction, warn: 0.85, critical: 0.95))
                    .padding(.bottom, 6)
            }
            SectionHeader(title: "Rede")
            HStack {
                StatTile(value: Fmt.rate(network.download), label: "↓ Download")
                StatTile(value: Fmt.rate(network.upload), label: "↑ Upload")
            }
        }
        .padding(.horizontal, 14)
    }
}

// MARK: - Bateria

private struct BatterySection: View {
    let battery: BatterySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Bateria", trailing: Fmt.percent(battery.percent))
            UsageBar(value: battery.percent, tint: batteryTint)
            Text(statusLine)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack {
                StatTile(value: battery.health.map(Fmt.percent) ?? "—", label: "Saúde")
                StatTile(value: battery.cycles.map(String.init) ?? "—", label: "Ciclos")
                StatTile(value: battery.watts.map { "\($0.formatted(.number.precision(.fractionLength(1)))) W" } ?? "—",
                         label: "Potência")
            }
        }
        .padding(.horizontal, 14)
    }

    private var batteryTint: Color {
        if battery.state == .charging || battery.state == .charged { return .green }
        if battery.percent <= 0.1 { return .red }
        if battery.percent <= 0.2 { return .orange }
        return .accentColor
    }

    private var statusLine: String {
        switch battery.state {
        case .charging:
            battery.minutesRemaining.map { "Carregando · cheia em \(Fmt.minutes($0))" } ?? "Carregando"
        case .charged: "Carregada · no adaptador"
        case .onAC: "No adaptador · sem carregar"
        case .discharging:
            battery.minutesRemaining.map { "Na bateria · \(Fmt.minutes($0)) restantes" } ?? "Na bateria"
        }
    }
}

// MARK: - Rodapé

private struct FooterSection: View {
    var body: some View {
        VStack(spacing: 0) {
            MenuRow(title: "Abrir Monitor de Atividade…") {
                let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
            MenuRow(title: "Sair do MacMonitor", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

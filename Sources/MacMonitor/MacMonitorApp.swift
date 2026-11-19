import SwiftUI

@main
struct MacMonitorApp: App {
    @State private var monitor = SystemMonitor()

    init() {
        if CommandLine.arguments.contains("--dump") {
            Self.dump()
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
           index + 1 < CommandLine.arguments.count {
            Self.snapshot(to: CommandLine.arguments[index + 1])
            exit(0)
        }
    }

    /// Renderiza o painel num PNG (para pré-visualização): MacMonitor --snapshot painel.png
    @MainActor private static func snapshot(to path: String) {
        PanelView.isSnapshot = true
        let monitor = SystemMonitor()
        // Enche o histórico de CPU para o gráfico não sair vazio.
        for _ in 0..<SystemMonitor.historyLength {
            Thread.sleep(forTimeInterval: 0.25)
            monitor.refresh()
        }
        for scheme in [ColorScheme.light, .dark] {
            let view = PanelView(monitor: monitor)
                .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.94))
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            let url = URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-\(scheme == .dark ? "dark" : "light").png"))
            try? png.write(to: url)
            print(url.path)
        }

        // Prévia do item da barra de menus.
        let items = [
            BarItem(symbol: "cpu", value: Fmt.percent(monitor.cpu.total), sample: "100%"),
            BarItem(symbol: "memorychip", value: Fmt.percent(monitor.memory.usedFraction), sample: "100%"),
            BarItem(symbol: "thermometer.medium", value: monitor.temperatures.cpu.map(Fmt.temperature) ?? "—", sample: "100°"),
        ]
        let bar = BarContent(items: items, color: .white)
            .padding(.horizontal, 12)
            .background(Color(red: 0.16, green: 0.18, blue: 0.55))
        let renderer = ImageRenderer(content: bar)
        renderer.scale = 2
        if let tiff = renderer.nsImage?.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-menubar.png"))
            try? png.write(to: url)
            print(url.path)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(monitor: monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }

    /// Imprime as leituras no terminal (útil para diagnóstico): MacMonitor --dump
    private static func dump() {
        let cpu = CPUReader()
        _ = cpu.read()
        let net = NetworkReader()
        _ = net.read()
        Thread.sleep(forTimeInterval: 1)
        let c = cpu.read()
        let m = MemoryReader.read()
        let t = TemperatureReader().read()
        print("CPU  total \(Fmt.percent(c.total))  cores \(c.cores.map { Fmt.percent($0) })  E-cores \(c.efficiencyCores)")
        print("RAM  \(Fmt.gigabytes(m.used)) / \(Fmt.gigabytes(m.total))  pressure \(m.pressure)  swap \(Fmt.gigabytes(m.swapUsed))")
        print("TEMP cpu \(t.cpu.map(Fmt.temperature) ?? "-") max \(t.cpuMax.map(Fmt.temperature) ?? "-") ssd \(t.ssd.map(Fmt.temperature) ?? "-") bat \(t.battery.map(Fmt.temperature) ?? "-")")
        for s in t.sensors { print("     \(s.name): \(String(format: "%.1f", s.value))") }
        print("GPU  \(GPUReader.utilization().map(Fmt.percent) ?? "-")")
        print("DISK \(String(describing: DiskReader.read()))")
        print("NET  \(net.read())")
        print("BAT  \(String(describing: BatteryReader.read()))")
    }
}

struct MenuBarLabel: View {
    let monitor: SystemMonitor
    @AppStorage(Settings.barCPU) private var showCPU = true
    @AppStorage(Settings.barMemory) private var showMemory = true
    @AppStorage(Settings.barTemperature) private var showTemperature = true
    @AppStorage(Settings.barNetwork) private var showNetwork = false

    var body: some View {
        let parts = items
        if parts.isEmpty {
            Image(systemName: "gauge.with.dots.needle.50percent")
        } else if let image = Self.render(parts) {
            Image(nsImage: image)
        }
    }

    private var items: [BarItem] {
        var parts: [BarItem] = []
        if showCPU {
            parts.append(BarItem(symbol: "cpu", value: Fmt.percent(monitor.cpu.total), sample: "100%"))
        }
        if showMemory {
            parts.append(BarItem(symbol: "memorychip", value: Fmt.percent(monitor.memory.usedFraction), sample: "100%"))
        }
        if showTemperature, let temp = monitor.temperatures.cpu {
            parts.append(BarItem(symbol: "thermometer.medium", value: Fmt.temperature(temp), sample: "100°"))
        }
        if showNetwork {
            parts.append(BarItem(symbol: "arrow.down.circle", value: Fmt.rate(monitor.network.download), sample: "999 KB/s"))
        }
        return parts
    }

    /// A barra de menus só aceita um Image + Text no rótulo, então desenhamos tudo numa
    /// imagem "template": o macOS a pinta de branco/preto conforme o fundo, como os ícones do sistema.
    @MainActor
    private static func render(_ parts: [BarItem]) -> NSImage? {
        let renderer = ImageRenderer(content: BarContent(items: parts))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        return image
    }
}

struct BarItem {
    let symbol: String
    let value: String
    /// Texto mais largo possível, para reservar espaço e o item não "pular" ao mudar o valor.
    let sample: String
}

private struct BarContent: View {
    let items: [BarItem]
    var color: Color = .black

    var body: some View {
        HStack(spacing: 9) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 3) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 12, weight: .regular))
                    ZStack(alignment: .leading) {
                        Text(item.sample).hidden()
                        Text(item.value)
                    }
                    .font(.system(size: 13, weight: .regular))
                    .monospacedDigit()
                }
            }
        }
        .foregroundStyle(color)
        .frame(height: 22)
    }
}

enum Settings {
    static let barCPU = "bar.cpu"
    static let barMemory = "bar.memory"
    static let barTemperature = "bar.temperature"
    static let barNetwork = "bar.network"
}

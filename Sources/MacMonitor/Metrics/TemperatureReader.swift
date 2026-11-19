import Foundation

struct TemperatureSnapshot {
    var cpu: Double?
    var cpuMax: Double?
    var ssd: Double?
    var battery: Double?
    var sensors: [(name: String, value: Double)] = []
}

/// Lê os sensores de temperatura do Apple Silicon via IOHIDEventSystem (API privada do IOKit,
/// a mesma usada por ferramentas como `powermetrics`). Carregada dinamicamente para falhar
/// de forma segura caso não exista.
final class TemperatureReader {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    private typealias SetMatchingFn = @convention(c) (UnsafeMutableRawPointer, CFDictionary) -> Int32
    private typealias CopyServicesFn = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (UnsafeRawPointer, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (UnsafeRawPointer, Int64, Int32, Int64) -> UnsafeMutableRawPointer?
    private typealias GetFloatFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Double

    private static let temperatureEventType: Int64 = 15 // kIOHIDEventTypeTemperature
    private static let temperatureField: Int32 = 15 << 16

    private var copyEvent: CopyEventFn?
    private var getFloat: GetFloatFn?
    private var services: [(name: String, ref: AnyObject)] = []

    init() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return }
        func load<T>(_ name: String, as _: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let create = load("IOHIDEventSystemClientCreate", as: CreateFn.self),
              let setMatching = load("IOHIDEventSystemClientSetMatching", as: SetMatchingFn.self),
              let copyServices = load("IOHIDEventSystemClientCopyServices", as: CopyServicesFn.self),
              let copyProperty = load("IOHIDServiceClientCopyProperty", as: CopyPropertyFn.self),
              let copyEvent = load("IOHIDServiceClientCopyEvent", as: CopyEventFn.self),
              let getFloat = load("IOHIDEventGetFloatValue", as: GetFloatFn.self),
              let client = create(kCFAllocatorDefault) else { return }

        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = setMatching(client, matching)

        guard let array = copyServices(client)?.takeRetainedValue() as? [AnyObject] else { return }
        for service in array {
            let pointer = Unmanaged.passUnretained(service).toOpaque()
            let name = copyProperty(pointer, "Product" as CFString)?.takeRetainedValue() as? String
            if let name { services.append((name, service)) }
        }
        self.copyEvent = copyEvent
        self.getFloat = getFloat
    }

    func read() -> TemperatureSnapshot {
        guard let copyEvent, let getFloat else { return TemperatureSnapshot() }
        var snapshot = TemperatureSnapshot()
        var cpu: [Double] = [], ssd: [Double] = [], battery: [Double] = []

        for service in services {
            let pointer = Unmanaged.passUnretained(service.ref).toOpaque()
            guard let event = copyEvent(pointer, Self.temperatureEventType, 0, 0) else { continue }
            let value = getFloat(event, Self.temperatureField)
            Unmanaged<AnyObject>.fromOpaque(event).release()
            guard value > 0, value < 130 else { continue }

            snapshot.sensors.append((service.name, value))
            let name = service.name.lowercased()
            if name.contains("tdie") || name.contains("acc mtr") || name.contains("soc mtr") {
                cpu.append(value)
            } else if name.contains("nand") {
                ssd.append(value)
            } else if name.contains("battery") {
                battery.append(value)
            }
        }

        if !cpu.isEmpty {
            snapshot.cpu = cpu.reduce(0, +) / Double(cpu.count)
            snapshot.cpuMax = cpu.max()
        }
        snapshot.ssd = ssd.max()
        snapshot.battery = battery.max()
        return snapshot
    }
}

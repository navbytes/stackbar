#if os(macOS)
import Darwin
import Foundation
import IOKit
import StackbarHostCore
import StackbarProtocol

/// `Stackbar.sensors()`: temperatures from the HID event system (how Apple
/// Silicon reports them) and fan speeds from the SMC. Neither has a public
/// API; the HID calls are looked up at run time so a Mac that lacks them
/// answers no temperatures instead of crashing, and nothing is written.
extension MacSystem {
    func sensors() async throws -> [SensorReading] {
        await Task.detached(priority: .utility) {
            MacSensors.temperatures() + MacSensors.fans()
        }.value
    }
}

enum MacSensors {
    // MARK: Temperatures

    private typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatching = @convention(c) (CFTypeRef, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEvent = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias FloatValue = @convention(c) (CFTypeRef, Int32) -> Double

    private static let temperatureEvent: Int64 = 15
    private static let temperatureField = Int32(15 << 16)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    /// Every HID temperature sensor, grouped the way the user thinks of them.
    static func temperatures() -> [SensorReading] {
        guard let create = symbol("IOHIDEventSystemClientCreate", as: CreateClient.self),
              let setMatching = symbol("IOHIDEventSystemClientSetMatching", as: SetMatching.self),
              let copyServices = symbol("IOHIDEventSystemClientCopyServices", as: CopyServices.self),
              let copyProperty = symbol("IOHIDServiceClientCopyProperty", as: CopyProperty.self),
              let copyEvent = symbol("IOHIDServiceClientCopyEvent", as: CopyEvent.self),
              let floatValue = symbol("IOHIDEventGetFloatValue", as: FloatValue.self),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue()
        else { return [] }
        // Apple's vendor page and its temperature sensor usage.
        let matching = ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 5] as CFDictionary
        _ = setMatching(client, matching)
        guard let services = copyServices(client)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
        var groups: [String: [Double]] = [:]
        for service in services {
            guard let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  let event = copyEvent(service, temperatureEvent, 0, 0)?.takeRetainedValue()
            else { continue }
            let value = floatValue(event, temperatureField)
            // A sensor that isn't wired answers 0 or nonsense.
            guard value > 1, value < 130, let group = group(for: name) else { continue }
            groups[group, default: []].append(value)
        }
        return order.compactMap { id, title in
            guard let values = groups[id], !values.isEmpty else { return nil }
            let average = values.reduce(0, +) / Double(values.count)
            return SensorReading(id: id, name: title, kind: .temperature, value: (average * 10).rounded() / 10)
        }
    }

    private static let order: [(String, String)] = [("cpu", "CPU"), ("gpu", "GPU"), ("ssd", "SSD"), ("battery", "Battery")]

    /// "PMU tdie3" is a CPU die, "PMU tdev" and the like are elsewhere on
    /// the chip; Intel Macs' sensors aren't on this page at all.
    static func group(for name: String) -> String? {
        let lower = name.lowercased()
        if lower.contains("tdie") || lower.contains("cpu") { return "cpu" }
        if lower.contains("gpu") { return "gpu" }
        if lower.contains("nand") || lower.contains("ssd") { return "ssd" }
        if lower.contains("battery") || lower.contains("gas gauge") { return "battery" }
        return nil
    }

    // MARK: Fans

    /// The SMC's call structure, laid out as `SMCKeyData_t` in C (80 bytes).
    private struct KeyData {
        typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
        struct PowerLimits { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, memory: UInt32 = 0 }
        // Padded to C's 12 bytes: Swift would put the next field right after the 9th.
        struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0, padding: (UInt8, UInt8, UInt8) = (0, 0, 0) }

        var key: UInt32 = 0
        var version = Version()
        var limits = PowerLimits()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let readKey: UInt8 = 5
    private static let readKeyInfo: UInt8 = 9
    private static let handleEvent: UInt32 = 2

    static func fans() -> [SensorReading] {
        guard MemoryLayout<KeyData>.size == 80 else { return [] }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return [] }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return [] }
        defer { IOServiceClose(connection) }
        guard let count = read("FNum", connection).map(Int.init), count > 0 else { return [] }
        return (0..<min(count, 4)).compactMap { index in
            guard let speed = read("F\(index)Ac", connection) else { return nil }
            let maximum = read("F\(index)Mx", connection)
            return SensorReading(id: "fan-\(index)", name: count == 1 ? "Fan" : "Fan \(index + 1)", kind: .fan,
                                 value: max(0, speed.rounded()), maximum: maximum.flatMap { $0 > 0 ? $0.rounded() : nil })
        }
    }

    private static func fourCC(_ text: String) -> UInt32 {
        text.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func call(_ input: inout KeyData, _ connection: io_connect_t) -> KeyData? {
        var output = KeyData()
        var size = MemoryLayout<KeyData>.stride
        let result = IOConnectCallStructMethod(connection, handleEvent, &input, MemoryLayout<KeyData>.stride, &output, &size)
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    /// A key's value as a number, for the types fans use.
    private static func read(_ key: String, _ connection: io_connect_t) -> Double? {
        var input = KeyData()
        input.key = fourCC(key)
        input.data8 = readKeyInfo
        guard let info = call(&input, connection) else { return nil }
        input.keyInfo.dataSize = info.keyInfo.dataSize
        input.data8 = readKey
        guard let output = call(&input, connection) else { return nil }
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(min(info.keyInfo.dataSize, 32)))) }
        return value(bytes, type: info.keyInfo.dataType)
    }

    static func value(_ bytes: [UInt8], type: UInt32) -> Double? {
        switch type {
        case fourCC("ui8 ") where bytes.count >= 1:
            return Double(bytes[0])
        case fourCC("ui16") where bytes.count >= 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case fourCC("fpe2") where bytes.count >= 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case fourCC("flt ") where bytes.count >= 4:
            // Apple Silicon answers floats little-endian.
            let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let number = Double(Float(bitPattern: raw))
            return number.isFinite ? number : nil
        default:
            return nil
        }
    }
}
#endif

import Foundation
import IOKit
import IOKit.ps

/// Ein Schnappschuss aller Werte, auf die die Schutzabschaltung achtet.
struct SensorReading: Equatable {
    /// Akkustand in Prozent. `nil`, wenn kein Akku gefunden wurde.
    var batteryPercent: Int?
    var onACPower = true
    /// Anzahl der Lüfter. 0 bei lüfterlosen Macs (z. B. MacBook Air).
    var fanCount = 0
    /// Drehzahl des schnellsten Lüfters in U/min.
    var fanRPM: Int?
    /// Ob der Lüfter aktiv kühlt (nicht nur im Leerlauf mitdreht).
    var fanIsRunning = false
    var thermalState: ProcessInfo.ThermalState = .nominal
    var lidClosed = false
}

/// Liest Akku, Lüfter, Temperaturzustand und Deckel aus.
final class Sensors {
    private let smc = SMC()

    func read() -> SensorReading {
        var reading = SensorReading()
        readBattery(into: &reading)
        readFans(into: &reading)
        reading.thermalState = ProcessInfo.processInfo.thermalState
        reading.lidClosed = Self.isLidClosed()
        return reading
    }

    // MARK: Akku

    private func readBattery(into reading: inout SensorReading) {
        guard let snapshotRef = IOPSCopyPowerSourcesInfo() else { return }
        let snapshot = snapshotRef.takeRetainedValue()
        guard let listRef = IOPSCopyPowerSourcesList(snapshot) else { return }
        let sources = listRef.takeRetainedValue() as NSArray

        for source in sources {
            guard let descriptionRef = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef) else { continue }
            guard let info = (descriptionRef.takeUnretainedValue() as NSDictionary) as? [String: Any] else { continue }
            guard info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            if let current = info[kIOPSCurrentCapacityKey] as? Int,
               let maximum = info[kIOPSMaxCapacityKey] as? Int, maximum > 0 {
                reading.batteryPercent = Int((Double(current) / Double(maximum) * 100).rounded())
            }
            reading.onACPower = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return
        }
    }

    // MARK: Lüfter

    private func readFans(into reading: inout SensorReading) {
        guard let smc, let count = smc.number("FNum"), count >= 1 else { return }
        let fanCount = min(Int(count), 8)
        reading.fanCount = fanCount

        var fastest: Double?
        var running = false
        for index in 0..<fanCount {
            guard let rpm = smc.number("F\(index)Ac") else { continue }
            fastest = max(fastest ?? 0, rpm)
            if Self.isActivelyCooling(rpm: rpm, minimum: smc.number("F\(index)Mn")) {
                running = true
            }
        }
        reading.fanRPM = fastest.map { Int($0.rounded()) }
        reading.fanIsRunning = running
    }

    /// Auf Apple Silicon steht der Lüfter im Leerlauf still, dort zählt jede Drehung.
    /// Intel-Macs drehen immer mit Mindestdrehzahl, dort zählt erst spürbar mehr.
    static func isActivelyCooling(rpm: Double, minimum: Double?) -> Bool {
        #if arch(arm64)
        return rpm >= 100
        #else
        let idle = minimum.flatMap { $0 > 0 ? $0 : nil } ?? 1300
        return rpm > idle * 1.3
        #endif
    }

    // MARK: Deckel

    static func isLidClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? Bool) ?? false
    }
}

/// Minimaler Lesezugriff auf den System Management Controller (für die Lüfterdrehzahl).
///
/// Die Anfrage ist ein 80 Byte großer Block (`SMCKeyData_t`). Statt das C-Struct in Swift
/// nachzubauen, werden die Felder an ihren festen Positionen gelesen und geschrieben.
final class SMC {
    private enum Offset {
        static let key = 0
        static let dataSize = 28
        static let dataType = 32
        static let result = 40
        static let command = 42
        static let bytes = 48
    }
    private enum Command {
        static let readBytes: UInt8 = 5
        static let readKeyInfo: UInt8 = 9
    }
    private static let structSize = 80
    private static let handleYPCEvent: UInt32 = 2

    private var connection: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit {
        IOServiceClose(connection)
    }

    /// Liest einen SMC-Schlüssel wie `F0Ac` und gibt ihn als Zahl zurück.
    func number(_ key: String) -> Double? {
        guard let (type, bytes) = read(key) else { return nil }
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            return Double(Float(bitPattern: Self.littleEndian32(bytes, at: 0)))
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double((UInt16(bytes[0]) << 8) | UInt16(bytes[1])) / 4
        case "ui8 ":
            return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double((UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
        default:
            return nil
        }
    }

    private func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        let scalars = Array(key.utf8)
        guard scalars.count == 4 else { return nil }
        let code = scalars.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }

        var request = [UInt8](repeating: 0, count: Self.structSize)
        Self.putLittleEndian32(code, into: &request, at: Offset.key)
        request[Offset.command] = Command.readKeyInfo
        guard let info = call(request) else { return nil }

        let size = Self.littleEndian32(info, at: Offset.dataSize)
        let typeCode = Self.littleEndian32(info, at: Offset.dataType)
        guard size > 0, size <= 32 else { return nil }

        request = [UInt8](repeating: 0, count: Self.structSize)
        Self.putLittleEndian32(code, into: &request, at: Offset.key)
        Self.putLittleEndian32(size, into: &request, at: Offset.dataSize)
        request[Offset.command] = Command.readBytes
        guard let response = call(request) else { return nil }

        let typeBytes = [24, 16, 8, 0].map { UInt8((typeCode >> UInt32($0)) & 0xFF) }
        let type = String(decoding: typeBytes, as: UTF8.self)
        return (type, Array(response[Offset.bytes..<(Offset.bytes + Int(size))]))
    }

    private func call(_ request: [UInt8]) -> [UInt8]? {
        var response = [UInt8](repeating: 0, count: Self.structSize)
        var responseSize = Self.structSize
        let status = request.withUnsafeBytes { input in
            response.withUnsafeMutableBytes { output in
                IOConnectCallStructMethod(
                    connection, Self.handleYPCEvent,
                    input.baseAddress, Self.structSize,
                    output.baseAddress, &responseSize
                )
            }
        }
        guard status == kIOReturnSuccess, response[Offset.result] == 0 else { return nil }
        return response
    }

    private static func littleEndian32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func putLittleEndian32(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
}

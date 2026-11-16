import Foundation

/// `HolyMacBook --diagnose` gibt im Terminal aus, was die App von Akku, Lüfter und
/// Ruhezustand sieht. Praktisch, wenn die Schutzabschaltung sich seltsam verhält.
enum Diagnose {
    static func run() {
        let reading = Sensors().read()
        let pmset = Shell.runSync("/usr/bin/pmset", ["-g"])

        print("Einrichtung vorhanden: \(PowerControl.isSetUp ? "ja" : "nein")")
        print("Ruhezustand gesperrt:  \(PowerControl.parseSleepDisabled(pmset.output) ? "ja" : "nein")")
        print("Deckel geschlossen:    \(reading.lidClosed ? "ja" : "nein")")
        if let percent = reading.batteryPercent {
            print("Akku:                  \(percent) %, \(reading.onACPower ? "am Netzteil" : "im Akkubetrieb")")
        } else {
            print("Akku:                  nicht gefunden")
        }
        print("Lüfter:                \(reading.fanCount)")
        if let rpm = reading.fanRPM {
            print("Drehzahl:              \(rpm) U/min (\(reading.fanIsRunning ? "kühlt aktiv" : "Leerlauf oder aus"))")
        }
        print("Temperaturzustand:     \(describe(reading.thermalState))")
    }

    private static func describe(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "normal"
        case .fair: return "leicht erhöht"
        case .serious: return "hoch"
        case .critical: return "kritisch"
        @unknown default: return "unbekannt"
        }
    }
}

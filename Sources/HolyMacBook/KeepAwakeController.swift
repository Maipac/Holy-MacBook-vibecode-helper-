import Foundation

/// Der Zustand der App: ob das Wachhalten an ist, und wann es sich selbst abschaltet.
@MainActor
final class KeepAwakeController: ObservableObject {
    static let shared = KeepAwakeController()

    /// Unter diesem Akkustand (in Prozent, im Akkubetrieb) schaltet sich das Wachhalten ab.
    static let batteryLimit = 10
    /// So viele Messungen in Folge muss der Lüfter laufen, bevor abgeschaltet wird.
    private static let fanTicksBeforeStop = 2
    private static let pollInterval: TimeInterval = 5

    enum Notice: Equatable {
        /// Die Schutzabschaltung hat das Wachhalten beendet oder gar nicht erst zugelassen.
        case warning(String)
        case error(String)

        var text: String {
            switch self {
            case .warning(let text), .error(let text): return text
            }
        }
    }

    @Published private(set) var isActive = false
    @Published private(set) var isSetUp = PowerControl.isSetUp
    @Published private(set) var isBusy = false
    @Published private(set) var notice: Notice?
    @Published private(set) var reading = SensorReading()

    @Published var stopOnLowBattery: Bool {
        didSet { defaults.set(stopOnLowBattery, forKey: Keys.stopOnLowBattery) }
    }
    @Published var stopOnHeat: Bool {
        didSet { defaults.set(stopOnHeat, forKey: Keys.stopOnHeat) }
    }

    private enum Keys {
        static let stopOnLowBattery = "stopOnLowBattery"
        static let stopOnHeat = "stopOnHeat"
    }

    private let defaults = UserDefaults.standard
    private let sensors = Sensors()
    private var timer: Timer?
    private var fanTicks = 0
    /// Hält App Nap fern, solange das Wachhalten an ist. Sonst würde macOS die
    /// Schutzabschaltung bei geschlossenem Deckel ausbremsen.
    private var activity: NSObjectProtocol?

    private init() {
        let store = UserDefaults.standard
        store.register(defaults: [Keys.stopOnLowBattery: true, Keys.stopOnHeat: true])
        stopOnLowBattery = store.bool(forKey: Keys.stopOnLowBattery)
        stopOnHeat = store.bool(forKey: Keys.stopOnHeat)
        reading = sensors.read()

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        refresh()
    }

    // MARK: Bedienung

    func toggle() {
        setActive(!isActive)
    }

    func setActive(_ active: Bool) {
        guard !isBusy, isSetUp, active != isActive else { return }
        if active, let reason = stopReason(requireSteadyFan: false) {
            notice = .warning("Nicht eingeschaltet, weil \(reason).")
            return
        }
        isBusy = true
        Task {
            let accepted = await PowerControl.setSleepDisabled(active)
            let actual = await PowerControl.readSleepDisabled()
            apply(actual)
            if accepted && actual == active {
                notice = nil
            } else {
                isSetUp = PowerControl.isSetUp
                notice = .error(isSetUp
                    ? "Das Umschalten hat nicht geklappt. Entferne die Einrichtung über das Menü „Wachhalten“ und richte sie neu ein."
                    : "Die Einrichtung fehlt. Richte Holy MacBook neu ein.")
            }
            isBusy = false
        }
    }

    /// Gleicht die Anzeige mit dem echten Systemzustand ab.
    func refresh() {
        isSetUp = PowerControl.isSetUp
        guard !isBusy else { return }
        Task {
            let actual = await PowerControl.readSleepDisabled()
            if !isBusy { apply(actual) }
        }
    }

    func runSetup() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            let result = await PowerControl.install()
            isSetUp = PowerControl.isSetUp
            switch result {
            case .done, .cancelled: notice = nil
            case .failed(let message): notice = .error("Die Einrichtung hat nicht geklappt: \(message)")
            }
            isBusy = false
        }
    }

    func removeSetup() {
        guard !isBusy, isSetUp else { return }
        isBusy = true
        Task {
            if isActive {
                _ = await PowerControl.setSleepDisabled(false)
                apply(await PowerControl.readSleepDisabled())
            }
            let result = await PowerControl.uninstall()
            isSetUp = PowerControl.isSetUp
            if case .failed(let message) = result {
                notice = .error("Das Entfernen hat nicht geklappt: \(message)")
            } else {
                notice = nil
            }
            isBusy = false
        }
    }

    /// Beim Beenden der App: Ruhezustand wieder erlauben, sonst bliebe der Mac
    /// ohne Schutzabschaltung wach.
    func shutdown() {
        timer?.invalidate()
        if isActive {
            PowerControl.setSleepDisabledSync(false)
        }
    }

    // MARK: Schutzabschaltung

    private func tick() {
        let fresh = sensors.read()
        if fresh != reading { reading = fresh }
        fanTicks = fresh.fanIsRunning ? fanTicks + 1 : 0

        guard isActive, !isBusy, let reason = stopReason(requireSteadyFan: true) else { return }
        stopAutomatically(because: reason)
    }

    /// Der Grund als Nebensatz („… weil der Lüfter läuft“), oder `nil`, wenn alles in Ordnung ist.
    private func stopReason(requireSteadyFan: Bool) -> String? {
        if stopOnLowBattery, !reading.onACPower,
           let percent = reading.batteryPercent, percent < Self.batteryLimit {
            return "der Akku nur noch bei \(percent) % liegt"
        }
        if stopOnHeat {
            let fanCounts = requireSteadyFan ? fanTicks >= Self.fanTicksBeforeStop : true
            if reading.fanIsRunning, fanCounts {
                if let rpm = reading.fanRPM {
                    return "der Lüfter läuft (\(rpm) U/min)"
                }
                return "der Lüfter läuft"
            }
            if reading.thermalState == .serious || reading.thermalState == .critical {
                return "dein Mac zu warm ist"
            }
        }
        return nil
    }

    private func stopAutomatically(because reason: String) {
        isBusy = true
        let lidClosed = reading.lidClosed
        Task {
            let accepted = await PowerControl.setSleepDisabled(false)
            let actual = await PowerControl.readSleepDisabled()
            apply(actual)
            if accepted && !actual {
                let time = Date().formatted(date: .omitted, time: .shortened)
                notice = .warning("Um \(time) automatisch ausgeschaltet, weil \(reason).")
                if lidClosed {
                    await PowerControl.sleepNow()
                }
            }
            isBusy = false
        }
    }

    private func apply(_ active: Bool) {
        if active != isActive { isActive = active }
        if active, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiated,
                reason: "Holy MacBook hält den Mac wach und überwacht Akku und Lüfter."
            )
        } else if !active, let token = activity {
            ProcessInfo.processInfo.endActivity(token)
            activity = nil
        }
    }
}

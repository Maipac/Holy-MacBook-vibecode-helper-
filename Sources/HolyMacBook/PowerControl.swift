import Foundation

/// Startet Systemprogramme und sammelt deren Ausgabe.
enum Shell {
    struct Result {
        let status: Int32
        let output: String
        var succeeded: Bool { status == 0 }
    }

    static func runSync(_ path: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    static func run(_ path: String, _ arguments: [String]) async -> Result {
        await Task.detached(priority: .userInitiated) {
            runSync(path, arguments)
        }.value
    }
}

/// Schaltet den Ruhezustand von macOS ein und aus.
///
/// Zugeklappt wach bleibt ein MacBook nur mit `pmset -a disablesleep 1`, und das verlangt
/// Admin-Rechte. Die einmalige Einrichtung legt deshalb eine sudo-Regel an, die genau
/// diesen einen Befehl (mit 0 und 1) ohne Passwort erlaubt.
enum PowerControl {
    static let rulePath = "/private/etc/sudoers.d/holymacbook"
    private static let pmset = "/usr/bin/pmset"

    enum SetupResult: Equatable {
        case done
        case cancelled
        case failed(String)
    }

    static var isSetUp: Bool {
        FileManager.default.fileExists(atPath: rulePath)
    }

    // MARK: Zustand

    static func readSleepDisabled() async -> Bool {
        parseSleepDisabled(await Shell.run(pmset, ["-g"]).output)
    }

    static func parseSleepDisabled(_ pmsetOutput: String) -> Bool {
        for line in pmsetOutput.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if fields.first == "SleepDisabled" {
                return fields.last == "1"
            }
        }
        return false
    }

    static func setSleepDisabled(_ disabled: Bool) async -> Bool {
        await Shell.run("/usr/bin/sudo", toggleArguments(disabled)).succeeded
    }

    /// Blockierende Variante für den Moment, in dem die App beendet wird.
    @discardableResult
    static func setSleepDisabledSync(_ disabled: Bool) -> Bool {
        Shell.runSync("/usr/bin/sudo", toggleArguments(disabled)).succeeded
    }

    private static func toggleArguments(_ disabled: Bool) -> [String] {
        ["-n", pmset, "-a", "disablesleep", disabled ? "1" : "0"]
    }

    /// Schickt den Mac sofort schlafen (braucht keine Admin-Rechte).
    static func sleepNow() async {
        _ = await Shell.run(pmset, ["sleepnow"])
    }

    // MARK: Einrichtung

    static func install() async -> SetupResult {
        let rule = "\(sudoersUser()) ALL=(root) NOPASSWD: \(pmset) -a disablesleep 0, \(pmset) -a disablesleep 1"
        // Die Regel wird erst von visudo geprüft und nur bei Erfolg installiert,
        // damit eine fehlerhafte Datei sudo nicht lahmlegen kann.
        let command = [
            "f=$(/usr/bin/mktemp)",
            "&& /usr/bin/printf '%s\\n' '\(rule)' > \"$f\"",
            "&& /usr/sbin/visudo -cf \"$f\"",
            "&& /bin/mkdir -p /private/etc/sudoers.d",
            "&& /usr/bin/install -m 0440 -o root -g wheel \"$f\" \(rulePath);",
            "s=$?; /bin/rm -f \"$f\"; exit $s",
        ].joined(separator: " ")
        let result = await runAsAdmin(
            command,
            prompt: "Holy MacBook möchte das Wachhalten einrichten. Danach schaltet der Knopf ohne Passwort."
        )
        if result == .done, !isSetUp {
            return .failed("Die Regel wurde nicht angelegt.")
        }
        return result
    }

    static func uninstall() async -> SetupResult {
        await runAsAdmin(
            "/bin/rm -f \(rulePath)",
            prompt: "Holy MacBook möchte die Einrichtung entfernen."
        )
    }

    /// Der Benutzer für die sudo-Regel. Ungewöhnliche Namen werden über die Benutzer-ID angegeben.
    private static func sudoersUser() -> String {
        let name = NSUserName()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        let isPlain = !name.isEmpty && name.unicodeScalars.allSatisfy { allowed.contains($0) }
        return isPlain ? name : "#\(getuid())"
    }

    private static func runAsAdmin(_ command: String, prompt: String) async -> SetupResult {
        let script = "do shell script \"\(appleScriptEscaped(command))\" "
            + "with prompt \"\(appleScriptEscaped(prompt))\" with administrator privileges"
        let result = await Shell.run("/usr/bin/osascript", ["-e", script])
        if result.succeeded { return .done }
        if result.output.contains("-128") { return .cancelled }
        return .failed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func appleScriptEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

import AppKit
import SwiftUI

@main
enum Launcher {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            Diagnose.run()
            return
        }
        HolyMacBookApp.main()
    }
}

@MainActor
struct HolyMacBookApp: App {
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = KeepAwakeController.shared
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    var body: some Scene {
        Window("Holy MacBook", id: Self.mainWindowID) {
            ContentView()
                .environmentObject(controller)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandMenu("Wachhalten") {
                Button(controller.isActive ? "Ausschalten" : "Einschalten") {
                    controller.toggle()
                }
                .keyboardShortcut("k")
                .disabled(!controller.isSetUp || controller.isBusy)

                Divider()

                Button("Einrichtung entfernen…") {
                    controller.removeSetup()
                }
                .disabled(!controller.isSetUp || controller.isBusy)
            }
            CommandGroup(replacing: .help) {}
        }

        MenuBarExtra(
            "Holy MacBook",
            systemImage: controller.isActive ? "sun.max.fill" : "moon.zzz",
            isInserted: $showMenuBarExtra
        ) {
            MenuBarMenu()
                .environmentObject(controller)
        }

        Settings {
            SettingsView()
        }
    }
}

/// Das Menü hinter dem Symbol in der Menüleiste.
private struct MenuBarMenu: View {
    @EnvironmentObject private var controller: KeepAwakeController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Wachhalten", isOn: Binding(
            get: { controller.isActive },
            set: { controller.setActive($0) }
        ))
        .disabled(!controller.isSetUp || controller.isBusy)

        Divider()

        Button("Fenster öffnen") {
            openWindow(id: HolyMacBookApp.mainWindowID)
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Holy MacBook beenden") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

private struct SettingsView: View {
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    var body: some View {
        Form {
            Toggle("Symbol in der Menüleiste anzeigen", isOn: $showMenuBarExtra)
        }
        .padding(20)
        .frame(width: 360)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        KeepAwakeController.shared.shutdown()
    }
}

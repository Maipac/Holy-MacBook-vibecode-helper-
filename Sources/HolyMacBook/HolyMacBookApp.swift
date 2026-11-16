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
        if CommandLine.arguments.contains("--print-setup-command") {
            print(PowerControl.installCommand())
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

        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarMenu()
                .environmentObject(controller)
        } label: {
            Image(nsImage: Self.menuBarImage(isActive: controller.isActive))
        }

        Settings {
            SettingsView()
        }
    }
}

extension HolyMacBookApp {
    /// Das Symbol für die Menüleiste. Die Beschreibung ist wichtig: Ohne sie liest
    /// VoiceOver den Namen des Symbols vor („Helligkeit höher“) statt den der App.
    static func menuBarImage(isActive: Bool) -> NSImage {
        let image = NSImage(
            systemSymbolName: isActive ? "sun.max.fill" : "moon.zzz",
            accessibilityDescription: isActive ? "Holy MacBook, Wachhalten an" : "Holy MacBook, Wachhalten aus"
        ) ?? NSImage()
        image.isTemplate = true
        return image
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

        if let notice = controller.notice {
            // Nach einer automatischen Abschaltung steht der Grund auch hier.
            Text(notice.text)
        }

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

    /// Der Schalter ist auch über das Dock-Symbol erreichbar, falls das Symbol in der
    /// Menüleiste ausgeblendet ist.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let controller = KeepAwakeController.shared
        let menu = NSMenu()
        menu.autoenablesItems = false
        let item = NSMenuItem(title: "Wachhalten", action: #selector(toggleKeepAwake), keyEquivalent: "")
        item.target = self
        item.state = controller.isActive ? .on : .off
        item.isEnabled = controller.isSetUp && !controller.isBusy
        menu.addItem(item)
        return menu
    }

    @objc private func toggleKeepAwake() {
        KeepAwakeController.shared.toggle()
    }
}

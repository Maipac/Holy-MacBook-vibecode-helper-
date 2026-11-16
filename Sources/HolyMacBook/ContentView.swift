import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var controller: KeepAwakeController

    var body: some View {
        VStack(spacing: 0) {
            HaloButton(isOn: controller.isActive) {
                controller.toggle()
            }
            .disabled(!controller.isSetUp || controller.isBusy)
            .padding(.top, 20)
            .padding(.bottom, 14)

            VStack(spacing: 6) {
                Text(controller.isActive ? "Wachhalten ist an" : "Wachhalten ist aus")
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 20)

            if let notice = controller.notice {
                NoticeView(notice: notice)
                    .padding(.bottom, 16)
            }

            if controller.isSetUp {
                ProtectionBox()
            } else {
                SetupBox()
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refresh()
        }
    }

    private var subtitle: String {
        if !controller.isSetUp {
            return "Richte Holy MacBook einmal ein, dann schaltet der Knopf sofort."
        }
        return controller.isActive
            ? "Dein MacBook bleibt wach, auch wenn du es zuklappst."
            : "Dein MacBook schläft beim Zuklappen wie gewohnt."
    }
}

// MARK: Hinweis

private struct NoticeView: View {
    let notice: KeepAwakeController.Notice

    var body: some View {
        Label {
            Text(notice.text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isError ? Color.red : Color.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isError: Bool {
        if case .error = notice { return true }
        return false
    }
}

// MARK: Einrichtung

private struct SetupBox: View {
    @EnvironmentObject private var controller: KeepAwakeController

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Einmalige Einrichtung")
                    .font(.headline)
                Text("Damit dein MacBook zugeklappt wach bleibt, braucht macOS einmal dein Passwort. Holy MacBook darf danach genau eine Sache ohne Nachfrage: den Ruhezustand sperren und wieder freigeben.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Einrichten…") {
                    controller.runSetup()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(controller.isBusy)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

// MARK: Schutzabschaltung

private struct ProtectionBox: View {
    @EnvironmentObject private var controller: KeepAwakeController

    var body: some View {
        GroupBox {
            VStack(spacing: 10) {
                ProtectionRow(
                    title: "Wenn der Akku unter \(KeepAwakeController.batteryLimit) % fällt",
                    detail: batteryDetail,
                    isOn: $controller.stopOnLowBattery
                )
                Divider()
                ProtectionRow(
                    title: hasFan ? "Wenn der Lüfter anläuft" : "Wenn der Mac zu warm wird",
                    detail: heatDetail,
                    isOn: $controller.stopOnHeat
                )
            }
            .padding(8)
        } label: {
            Text("Automatisch ausschalten")
        }
    }

    private var hasFan: Bool {
        controller.reading.fanCount > 0
    }

    private var batteryDetail: String {
        guard let percent = controller.reading.batteryPercent else {
            return "Kein Akku gefunden"
        }
        return "Gerade \(percent) %, \(controller.reading.onACPower ? "am Netzteil" : "im Akkubetrieb")"
    }

    private var heatDetail: String {
        let reading = controller.reading
        guard hasFan else {
            return "Dieses MacBook hat keinen Lüfter, deshalb zählt die Temperatur."
        }
        guard let rpm = reading.fanRPM else {
            return "Drehzahl gerade nicht lesbar"
        }
        if reading.fanIsRunning {
            return "Läuft gerade mit \(rpm) U/min"
        }
        return rpm > 0 ? "Gerade im Leerlauf mit \(rpm) U/min" : "Steht gerade still"
    }
}

private struct ProtectionRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

import SwiftUI

/// Der große Knopf. An: warmes Licht mit Heiligenschein. Aus: ein ruhiger, grauer Knopf.
///
/// Der Zustand steckt nicht nur in der Farbe, sondern auch im Symbol (Sonne oder Mond)
/// und im Text darunter.
struct HaloButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EmptyView()
        }
        .buttonStyle(HaloButtonStyle(isOn: isOn))
        .accessibilityLabel("Wachhalten")
        .accessibilityValue(isOn ? "An" : "Aus")
        .accessibilityHint(isOn
            ? "Lässt dein MacBook beim Zuklappen wieder schlafen."
            : "Hält dein MacBook auch zugeklappt wach.")
        .help(isOn ? "Wachhalten ausschalten" : "Wachhalten einschalten")
    }
}

private struct HaloButtonStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        HaloFace(isOn: isOn, isPressed: configuration.isPressed)
    }
}

private struct HaloFace: View {
    let isOn: Bool
    let isPressed: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false

    private static let diameter: CGFloat = 168
    private static let haloGap: CGFloat = 14

    var body: some View {
        ZStack {
            // Heiligenschein
            Circle()
                .strokeBorder(Color.yellow.opacity(isOn ? 0.7 : 0), lineWidth: 2.5)
                .frame(width: Self.diameter + 2 * Self.haloGap, height: Self.diameter + 2 * Self.haloGap)

            Circle()
                .fill(isOn ? AnyShapeStyle(Self.light) : AnyShapeStyle(Color(nsColor: .controlColor)))
                .overlay {
                    Circle().strokeBorder(rim, lineWidth: contrast == .increased ? 2 : 1)
                }
                .shadow(color: isOn ? Color.orange.opacity(0.5) : Color.black.opacity(0.12),
                        radius: isOn ? 26 : 5, y: isOn ? 0 : 2)
                .frame(width: Self.diameter, height: Self.diameter)

            Image(systemName: isOn ? "sun.max.fill" : "moon.zzz.fill")
                .font(.system(size: 62, weight: .semibold))
                .foregroundStyle(isOn ? Color.black.opacity(0.82) : Color.primary.opacity(0.75))
                .accessibilityHidden(true)
        }
        .brightness(isPressed ? -0.08 : (isHovered && isEnabled ? 0.03 : 0))
        .scaleEffect(isPressed ? 0.96 : 1)
        .opacity(isEnabled ? 1 : 0.45)
        .padding(Self.haloGap)
        .contentShape(Circle())
        .contentShape(.focusEffect, Circle())
        .onHover { isHovered = $0 }
        .animation(stateAnimation, value: isOn)
        .animation(.easeOut(duration: 0.12), value: isPressed)
    }

    private var stateAnimation: Animation {
        reduceMotion ? Animation.easeInOut(duration: 0.15) : Animation.spring(response: 0.4, dampingFraction: 0.7)
    }

    private var rim: Color {
        if isOn { return Color.white.opacity(0.4) }
        return contrast == .increased ? Color.primary.opacity(0.6) : Color(nsColor: .separatorColor)
    }

    private static let light = LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
}

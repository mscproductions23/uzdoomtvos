import SwiftUI
import GameController

/// Controller settings saved by the launcher and passed to the engine on every start.
enum ControllerPrefs {
    static let gyroAim = "gyroAim"
    static let gyroSensitivity = "gyroSensitivity"
    static let gyroInvertX = "gyroInvertX"
    static let gyroInvertY = "gyroInvertY"
    static let touchpadAim = "touchpadAim"
    static let touchpadSensitivity = "touchpadSensitivity"

    static let sensitivities: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    /// Engine cvars (i_gcjoystick.mm) for the current settings.
    static func engineArgs() -> [String] {
        let d = UserDefaults.standard
        func flag(_ key: String) -> String { d.bool(forKey: key) ? "1" : "0" }
        func number(_ key: String) -> String {
            let v = d.object(forKey: key) as? Double ?? 1.0
            return String(format: "%.2f", v)
        }
        return [
            "+joy_gyro", flag(gyroAim),
            "+joy_gyro_sensitivity", number(gyroSensitivity),
            "+joy_gyro_invert_x", flag(gyroInvertX),
            "+joy_gyro_invert_y", flag(gyroInvertY),
            "+joy_touchpad_aim", flag(touchpadAim),
            "+joy_touchpad_sensitivity", number(touchpadSensitivity),
        ]
    }
}

/// What the connected controller can do, for the settings screen.
@MainActor
final class ControllerInfo: ObservableObject {
    @Published private(set) var name: String?
    @Published private(set) var hasGyro = false
    @Published private(set) var hasTouchpad = false
    private var observers: [NSObjectProtocol] = []

    init() {
        for note in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: note, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
        update()
    }

    private func update() {
        guard let controller = GCController.controllers().first(where: { $0.extendedGamepad != nil }) else {
            name = nil; hasGyro = false; hasTouchpad = false
            return
        }
        name = controller.vendorName ?? controller.productCategory
        hasGyro = controller.motion != nil
        let pad = controller.extendedGamepad
        hasTouchpad = pad is GCDualShockGamepad || pad is GCDualSenseGamepad
    }
}

/// The controller menu: gyro and touchpad aiming, the layout/tester, and resetting controls.
struct ControllerSettingsView: View {
    @StateObject private var info = ControllerInfo()
    @AppStorage(ControllerPrefs.gyroAim) private var gyroAim = false
    @AppStorage(ControllerPrefs.gyroSensitivity) private var gyroSensitivity = 1.0
    @AppStorage(ControllerPrefs.gyroInvertX) private var gyroInvertX = false
    @AppStorage(ControllerPrefs.gyroInvertY) private var gyroInvertY = false
    @AppStorage(ControllerPrefs.touchpadAim) private var touchpadAim = false
    @AppStorage(ControllerPrefs.touchpadSensitivity) private var touchpadSensitivity = 1.0
    @State private var showResetConfirm = false
    @State private var controlsMessage: String?

    var body: some View {
        HStack(alignment: .top, spacing: 70) {
            // Left: what's connected, and the layout tools.
            VStack(alignment: .leading, spacing: 22) {
                Text("Controller Settings").font(.title2).bold()

                VStack(alignment: .leading, spacing: 8) {
                    Label(info.name ?? "No game controller connected",
                          systemImage: info.name == nil ? "gamecontroller" : "gamecontroller.fill")
                        .font(.headline)
                    if info.name != nil {
                        capability("Gyro", info.hasGyro)
                        capability("Touchpad", info.hasTouchpad)
                    }
                }

                NavigationLink("Controls & Controller Test") {
                    ControlsView()
                }

                Button("Reset Controls to Default") {
                    showResetConfirm = true
                }
                .confirmationDialog("Reset all controls to the default layout?",
                                    isPresented: $showResetConfirm, titleVisibility: .visible) {
                    Button("Reset", role: .destructive) { resetControls() }
                    Button("Cancel", role: .cancel) {}
                }

                if let message = controlsMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Changes apply the next time you start a game. To change which button does what, start a game and open Options → Customize Controls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 620, alignment: .leading)

            // Right: aiming options. Scrolls if needed; tvOS follows focus.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Gyro Aim").font(.headline)
                    Text("Aim by tilting and turning the controller (DualShock 4, DualSense, Switch Pro). Works together with the right stick.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Gyro Aim", isOn: $gyroAim)
                    if gyroAim {
                        sensitivityPicker("Gyro Sensitivity", selection: $gyroSensitivity)
                        Toggle("Invert Left/Right", isOn: $gyroInvertX)
                        Toggle("Invert Up/Down", isOn: $gyroInvertY)
                    }

                    Text("Touchpad Aim").font(.headline).padding(.top, 14)
                    Text("Swipe the DualShock 4 or DualSense touchpad to aim. Clicking the touchpad opens the automap.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Touchpad Aim", isOn: $touchpadAim)
                    if touchpadAim {
                        sensitivityPicker("Touchpad Sensitivity", selection: $touchpadSensitivity)
                    }

                    Text("Mouse").font(.headline).padding(.top, 14)
                    Text("A mouse works when tvOS reports it as one: move to look, left click to fire. Whether a particular device (for example a Switch 2 Joy-Con in mouse mode) is reported as a mouse depends on tvOS.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 20)   // room for the focus lift effect at the ends
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 90)
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func capability(_ name: String, _ available: Bool) -> some View {
        Label("\(name): \(available ? "yes" : "not on this controller")",
              systemImage: available ? "checkmark.circle.fill" : "minus.circle")
            .font(.callout)
            .foregroundStyle(available ? .green : .secondary)
    }

    private func sensitivityPicker(_ title: String, selection: Binding<Double>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ControllerPrefs.sensitivities, id: \.self) { value in
                Text(String(format: "%g×", value)).tag(value)
            }
        }
    }

    private func resetControls() {
        do {
            controlsMessage = try ControlConfig.resetToDefaults()
                ? "Controls reset. The default layout applies next time you start a game."
                : "Controls are already at their defaults."
        } catch {
            controlsMessage = "Couldn't reset controls: \(error.localizedDescription)"
        }
    }
}

import SwiftUI
import GameController
import UIKit

struct ControlBinding: Identifiable {
    let id: String
    let control: String
    let symbol: String
    let action: String

    static let defaults: [ControlBinding] = [
        ControlBinding(id: "ls", control: "Left stick", symbol: "l.joystick", action: "Move and strafe"),
        ControlBinding(id: "rs", control: "Right stick", symbol: "r.joystick", action: "Turn and look up/down"),
        ControlBinding(id: "rt", control: "Right trigger", symbol: "rt.rectangle.roundedtop", action: "Fire"),
        ControlBinding(id: "lt", control: "Left trigger", symbol: "lt.rectangle.roundedtop", action: "Alternate fire (some mods)"),
        ControlBinding(id: "a", control: "A", symbol: "a.circle", action: "Use / open doors"),
        ControlBinding(id: "b", control: "B", symbol: "b.circle", action: "Not set"),
        ControlBinding(id: "x", control: "X", symbol: "x.circle", action: "Not set"),
        ControlBinding(id: "y", control: "Y", symbol: "y.circle", action: "Jump"),
        ControlBinding(id: "lb", control: "Left bumper", symbol: "lb.rectangle.roundedbottom", action: "Previous weapon"),
        ControlBinding(id: "rb", control: "Right bumper", symbol: "rb.rectangle.roundedbottom", action: "Next weapon"),
        ControlBinding(id: "up", control: "D-pad up", symbol: "dpad.up.filled", action: "Automap"),
        ControlBinding(id: "down", control: "D-pad down", symbol: "dpad.down.filled", action: "Use inventory item"),
        ControlBinding(id: "left", control: "D-pad left", symbol: "dpad.left.filled", action: "Previous inventory item"),
        ControlBinding(id: "right", control: "D-pad right", symbol: "dpad.right.filled", action: "Next inventory item"),
        ControlBinding(id: "l3", control: "Left stick click", symbol: "l.joystick.press.down", action: "Crouch"),
        ControlBinding(id: "menu", control: "Menu (≡)", symbol: "line.3.horizontal.circle", action: "Game menu"),
        ControlBinding(id: "options", control: "View / Options", symbol: "rectangle.on.rectangle.circle", action: "Pause"),
    ]
}

@MainActor final class GamepadTester: ObservableObject {
    @Published private(set) var active: Set<String> = []
    @Published private(set) var controllerName: String? = nil
    @Published private(set) var holdingExit = false
    var onExit: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var holdTask: Task<Void, Never>?

    func start() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.attach() }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.attach() }
            }
        )
        attach()
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        for controller in GCController.controllers() {
            controller.extendedGamepad?.valueChangedHandler = nil
            controller.microGamepad?.valueChangedHandler = nil
        }
        holdTask?.cancel()
        holdTask = nil
        holdingExit = false
        onExit = nil
        active = []
    }

    /// Called with whether an exit button (B/Menu, or the Siri Remote's Menu or Play/Pause) is held.
    private func handleExitHold(_ held: Bool) {
        if held && !holdingExit {
            holdingExit = true
            holdTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, !Task.isCancelled, self.holdingExit else { return }
                self.onExit?()
            }
        } else if !held && holdingExit {
            holdingExit = false
            holdTask?.cancel()
            holdTask = nil
        }
    }

    private func attach() {
        let controllers = GCController.controllers()
        if let controller = controllers.first(where: { $0.extendedGamepad != nil }),
           let pad = controller.extendedGamepad {
            controllerName = controller.vendorName ?? "Game controller"
            pad.valueChangedHandler = { [weak self] pad, _ in
                MainActor.assumeIsolated { self?.update(pad) }
            }
            update(pad)
        } else {
            controllerName = nil
            active = []
        }

        for controller in controllers {
            if controller.extendedGamepad == nil, let micro = controller.microGamepad {
                micro.valueChangedHandler = { [weak self] micro, _ in
                    MainActor.assumeIsolated {
                        self?.handleExitHold(micro.buttonMenu.isPressed || micro.buttonX.isPressed)
                    }
                }
            }
        }
    }

    private func update(_ pad: GCExtendedGamepad) {
        var activeSet = Set<String>()

        if abs(pad.leftThumbstick.xAxis.value) > 0.25 || abs(pad.leftThumbstick.yAxis.value) > 0.25 {
            activeSet.insert("ls")
        }
        if abs(pad.rightThumbstick.xAxis.value) > 0.25 || abs(pad.rightThumbstick.yAxis.value) > 0.25 {
            activeSet.insert("rs")
        }
        if pad.rightTrigger.value > 0.12 {
            activeSet.insert("rt")
        }
        if pad.leftTrigger.value > 0.12 {
            activeSet.insert("lt")
        }
        if pad.buttonA.isPressed {
            activeSet.insert("a")
        }
        if pad.buttonB.isPressed {
            activeSet.insert("b")
        }
        if pad.buttonX.isPressed {
            activeSet.insert("x")
        }
        if pad.buttonY.isPressed {
            activeSet.insert("y")
        }
        if pad.leftShoulder.isPressed {
            activeSet.insert("lb")
        }
        if pad.rightShoulder.isPressed {
            activeSet.insert("rb")
        }
        if pad.dpad.up.isPressed {
            activeSet.insert("up")
        }
        if pad.dpad.down.isPressed {
            activeSet.insert("down")
        }
        if pad.dpad.left.isPressed {
            activeSet.insert("left")
        }
        if pad.dpad.right.isPressed {
            activeSet.insert("right")
        }
        if pad.leftThumbstickButton?.isPressed == true {
            activeSet.insert("l3")
        }
        if pad.buttonMenu.isPressed {
            activeSet.insert("menu")
        }
        if pad.buttonOptions?.isPressed == true {
            activeSet.insert("options")
        }

        active = activeSet
        handleExitHold(pad.buttonB.isPressed || pad.buttonMenu.isPressed)
    }
}

/// Pushed from the launcher. Controller input is captured, so B/Menu can't navigate back;
/// holding B or Menu calls dismiss instead.
struct ControlsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ControllerCaptureView(content: AnyView(ControlsTesterContent(onExit: { dismiss() })))
            .ignoresSafeArea()
    }
}

struct ControlsTesterContent: View {
    let onExit: () -> Void
    @StateObject private var tester = GamepadTester()

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text("Controls")
                .font(.largeTitle)
                .bold()
            Text(tester.controllerName.map { "Testing: \($0) — press buttons and move the sticks; each one lights up." } ?? "Connect a game controller to test it.")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 40), GridItem(.flexible(), spacing: 40)], alignment: .leading, spacing: 16) {
                ForEach(ControlBinding.defaults) { row in
                    HStack(spacing: 20) {
                        Image(systemName: row.symbol)
                            .font(.title2)
                            .frame(width: 60)
                        VStack(alignment: .leading) {
                            Text(row.control)
                                .font(.headline)
                            Text(row.action)
                                .font(.callout)
                                .foregroundStyle(row.action == "Not set" ? .secondary : .primary)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(
                        tester.active.contains(row.id) ? Color.green.opacity(0.45) : Color.white.opacity(0.06)
                    ))
                    .animation(.easeOut(duration: 0.1), value: tester.active)
                }
            }
            Text(tester.holdingExit ? "Keep holding to leave…" : "Hold B or Menu to leave. To change a button, start a game and open Options → Customize Controls.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            tester.onExit = onExit
            tester.start()
        }
        .onDisappear {
            tester.stop()
        }
    }
}

/// Hosts SwiftUI content inside a GCEventViewController so game-controller (and Siri Remote)
/// input is delivered only to GameController, not to UIKit focus/navigation.
struct ControllerCaptureView: UIViewControllerRepresentable {
    let content: AnyView

    func makeUIViewController(context: Context) -> ControllerCaptureViewController {
        ControllerCaptureViewController(rootView: content)
    }

    // The content never changes; replacing rootView would rebuild it and lose the tester's state.
    func updateUIViewController(_ controller: ControllerCaptureViewController, context: Context) {}
}

final class ControllerCaptureViewController: GCEventViewController {
    let host: UIHostingController<AnyView>

    init(rootView: AnyView) {
        host = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = FocusableView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        controllerUserInteractionEnabled = false
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    // Keep focus (and so the responder chain) inside this controller.
    override var preferredFocusEnvironments: [UIFocusEnvironment] { [view] }
}

/// A plain view that can hold focus, so this controller stays first in the responder chain.
final class FocusableView: UIView {
    override var canBecomeFocused: Bool { true }
}

enum ControlConfig {
    static var configURL: URL {
        return DoomCloudStore.localSaveDirectory.deletingLastPathComponent().appendingPathComponent("uzdoom.ini")
    }

    static func resetToDefaults() throws -> Bool {
        let fileURL = configURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return false
        }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        var insideDroppedSection = false
        var linesToKeep: [Substring] = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.hasPrefix("[") && trimmedLine.hasSuffix("]") {
                let sectionName = String(trimmedLine.dropFirst().dropLast())
                if sectionName.hasSuffix(".Bindings") ||
                    sectionName.hasSuffix(".DoubleBindings") ||
                    sectionName.hasSuffix(".AutomapBindings") ||
                    sectionName.hasPrefix("Joy:") {
                    insideDroppedSection = true
                } else {
                    insideDroppedSection = false
                }
            }

            if !insideDroppedSection {
                linesToKeep.append(line)
            }
        }

        if linesToKeep.count == lines.count {
            return false
        }

        let newContent = linesToKeep.joined(separator: "\n")
        try newContent.write(to: fileURL, atomically: true, encoding: .utf8)
        return true
    }
}

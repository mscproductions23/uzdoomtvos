import SwiftUI
import GameController

struct LauncherView: View {
    @ObservedObject var library: WadLibrary
    @StateObject private var controllers = ControllerMonitor()
    @State private var showResetConfirm = false
    @State private var controlsMessage: String?

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 60) {

                // Game list — tvOS focus engine handles remote/controller navigation for free.
                VStack(alignment: .leading, spacing: 24) {
                    Text("UZDoom").font(.largeTitle).bold()

                    if !controllers.hasGamepad {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Connect a game controller to play", systemImage: "gamecontroller")
                                .font(.headline)
                            Text("The Siri Remote doesn't have enough buttons for Doom. Pair an Xbox, PlayStation or MFi controller in Settings → Remotes and Devices → Bluetooth.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: 700, alignment: .leading)
                    }

                    if library.games.isEmpty {
                        Text("No games found yet.").foregroundStyle(.secondary)
                    }

                    ForEach(library.games) { game in
                        Button {
                            Task { await library.play(game) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(game.displayName).font(.headline)
                                    Text(game.source.rawValue)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if game.source == .cloud {
                                    Image(systemName: "icloud.and.arrow.down")
                                }
                            }
                            .frame(maxWidth: 700, alignment: .leading)
                        }
                        .disabled(!controllers.hasGamepad)
                    }
                }

                // Side panel: transfer + fallback actions
                VStack(alignment: .leading, spacing: 24) {
                    Text("Add Games & Saves").font(.title2).bold()

                    Button(library.beamAddress == nil ? "Beam from iPhone…" : "Stop Receiving") {
                        library.toggleBeam()
                    }

                    if let address = library.beamAddress {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("On your iPhone (same Wi-Fi), open Safari and go to:")
                            Text(address)
                                .font(.system(.title3, design: .monospaced))
                                .bold()
                            Text("Then pick your .wad and save files.")
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .frame(maxWidth: 500, alignment: .leading)
                    }

                    Button("Install Freedoom (free)") {
                        Task { await library.installFreedoom() }
                    }

                    Text("Controller").font(.title2).bold()

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
                            .frame(maxWidth: 500, alignment: .leading)
                    }

                    if let busy = library.busyMessage {
                        ProgressView(busy)
                    }

                    if let error = library.lastError {
                        Text(error).foregroundStyle(.red).font(.callout)
                            .frame(maxWidth: 500, alignment: .leading)
                    }

                    Spacer()

                    Text("WADs and saves sync through your iCloud account.\nCommercial WADs must be your own copies.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(60)
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

/// Tracks whether a full game controller (not the Siri Remote) is connected.
@MainActor
final class ControllerMonitor: ObservableObject {
    @Published private(set) var hasGamepad = ControllerMonitor.gamepadConnected()

    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.hasGamepad = ControllerMonitor.gamepadConnected()
                }
            })
        }
    }

    /// The Siri Remote only has a microGamepad profile; real controllers have extendedGamepad.
    nonisolated static func gamepadConnected() -> Bool {
        GCController.controllers().contains { $0.extendedGamepad != nil }
    }
}

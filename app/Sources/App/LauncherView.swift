import SwiftUI
import GameController
import CoreImage.CIFilterBuiltins

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
                        // The link carries a one-time key, so it's shown as a QR code rather than text.
                        HStack(alignment: .top, spacing: 24) {
                            if let qr = QRCode.image(for: address) {
                                Image(uiImage: qr)
                                    .interpolation(.none)
                                    .resizable()
                                    .frame(width: 220, height: 220)
                                    .padding(12)
                                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Scan with your iPhone camera")
                                    .font(.headline)
                                Text("Your iPhone must be on the same Wi-Fi. Send games and saves, or back up your saves.")
                                    .foregroundStyle(.secondary)
                                Text("Receiving stops by itself after 15 minutes.")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                        .frame(maxWidth: 600, alignment: .leading)
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

                    Text("Saves stay on this Apple TV. Back them up with Beam from iPhone.\nCommercial WADs must be your own copies.")
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

/// Renders a string as a QR code image (scale it up with `.interpolation(.none)`).
enum QRCode {
    static func image(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

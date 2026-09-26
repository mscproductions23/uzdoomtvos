import SwiftUI
import GameController
import CloudKit
import CoreImage.CIFilterBuiltins

struct LauncherView: View {
    @ObservedObject var library: WadLibrary
    @StateObject private var controllers = ControllerMonitor()
    @State private var showResetConfirm = false
    @State private var controlsMessage: String?
    @AppStorage(DoomCloudStore.syncEnabledKey) private var iCloudSync = false
    @State private var iCloudState: DoomCloudStore.AccountState = .unknown
    @Environment(\.scenePhase) private var scenePhase

    /// A real game controller, or the iPhone controller page, is connected.
    private var canPlay: Bool { controllers.hasGamepad || library.phonePadConnected }

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 60) {

                // Game list — tvOS focus engine handles remote/controller navigation for free.
                VStack(alignment: .leading, spacing: 24) {
                    Text("UZDoom").font(.largeTitle).bold()

                    if !canPlay {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Connect a game controller to play", systemImage: "gamecontroller")
                                .font(.headline)
                            Text("The Siri Remote doesn't have enough buttons for Doom. Pair an Xbox, PlayStation or MFi controller in Settings → Remotes and Devices → Bluetooth, or use your iPhone: choose Connect iPhone… and tap Use this phone as a controller.")
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
                        .disabled(!canPlay)
                    }
                }

                // Side panel. It scrolls (tvOS follows focus), so nothing gets squeezed or cut off.
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("iPhone").font(.title2).bold()

                        Button(library.beamAddress == nil ? "Connect iPhone…" : "Disconnect iPhone") {
                            library.toggleBeam()
                        }

                        if let address = library.beamAddress {
                            // The link carries a one-time key, so it's shown as a QR code rather than text.
                            HStack(alignment: .top, spacing: 22) {
                                if let qr = QRCode.image(for: address) {
                                    Image(uiImage: qr)
                                        .interpolation(.none)
                                        .resizable()
                                        .frame(width: 200, height: 200)
                                        .padding(12)
                                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                                }
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Scan with your iPhone")
                                        .font(.headline)
                                    Text("Same Wi-Fi. Send games and saves, back up saves, or use the phone as a controller.")
                                        .foregroundStyle(.secondary)
                                    Text(library.phonePadConnected
                                         ? "iPhone controller connected."
                                         : "Turns off after 15 minutes, unless the phone is the controller.")
                                        .foregroundStyle(library.phonePadConnected ? .green : .secondary)
                                }
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Text("Games & Saves").font(.title2).bold()
                            .padding(.top, 8)

                        #if UZ_ICLOUD
                        Toggle("iCloud Sync", isOn: $iCloudSync)
                            .onChange(of: iCloudSync) { _, _ in
                                Task {
                                    await library.refresh()
                                    await updateICloudState()
                                }
                            }
                        iCloudStatus
                        #endif

                        Button("Install Freedoom (free)") {
                            Task { await library.installFreedoom() }
                        }

                        Text("Controller").font(.title2).bold()
                            .padding(.top, 8)

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

                        if let busy = library.busyMessage {
                            ProgressView(busy)
                        }

                        if let error = library.lastError {
                            Text(error).foregroundStyle(.red).font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text("Back up your saves with Connect iPhone. Commercial WADs must be your own copies.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                    .padding(.vertical, 20)   // room for the focus lift effect at the ends
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 640)
            }
            .padding(60)
        }
        #if UZ_ICLOUD
        .task { await updateICloudState() }
        // Signing in happens in the Apple TV's Settings, so check again on return...
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await updateICloudState() } }
        }
        // ...and when the device's iCloud account changes (another person's saves).
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            Task {
                await DoomCloudStore.shared.accountChanged()
                await updateICloudState()
                await library.refresh()
            }
        }
        #endif
    }

    /// iCloud status under the switch. tvOS apps can't sign in to iCloud themselves:
    /// the account signed in on the Apple TV is used, so point there when it's missing.
    @ViewBuilder
    private var iCloudStatus: some View {
        let (icon, color, text): (String, Color, String) = {
            switch iCloudState {
            case .available:
                return ("checkmark.icloud", .green,
                        "Syncing with the iCloud account signed in on this Apple TV. Only that account can see these saves.")
            case .noAccount:
                return ("exclamationmark.icloud", .orange,
                        "No iCloud account on this Apple TV. Sign in under Settings → Users and Accounts, then come back here.")
            case .restricted:
                return ("lock.icloud", .orange,
                        "iCloud is restricted on this Apple TV (for example by Screen Time).")
            case .temporarilyUnavailable:
                return ("exclamationmark.icloud", .orange,
                        "iCloud is temporarily unavailable. Check Settings → Users and Accounts → iCloud.")
            case .switchedOff, .notInThisBuild:
                return ("icloud.slash", .secondary, "Off: saves and WADs stay on this Apple TV.")
            case .unknown:
                return ("icloud", .secondary, "Checking iCloud…")
            }
        }()
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func updateICloudState() async {
        iCloudState = await DoomCloudStore.shared.accountState()
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

import SwiftUI

struct LauncherView: View {
    @ObservedObject var library: WadLibrary

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 60) {

                // Game list — tvOS focus engine handles remote/controller navigation for free.
                VStack(alignment: .leading, spacing: 24) {
                    Text("UZDoom").font(.largeTitle).bold()

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
}

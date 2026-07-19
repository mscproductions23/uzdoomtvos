import SwiftUI

@main
struct UZDoomTVApp: App {
    @StateObject private var library = WadLibrary()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LauncherView(library: library)
                .task { await library.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Push any new saves to CloudKit whenever the app leaves the foreground.
            if phase == .background || phase == .inactive {
                Task {
                    if let iwad = library.lastLaunchedIwad {
                        try? await DoomCloudStore.shared.syncSavesUp(iwadName: iwad)
                    }
                }
            }
        }
    }
}

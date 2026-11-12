import Sparkle
import SwiftUI

struct UpdateSettingsView: View {
    let updater: SPUUpdater
    @State private var canCheckForUpdates = false
    @State private var automaticallyChecksForUpdates = false
    @State private var automaticallyDownloadsUpdates = false

    var body: some View {
        Toggle("Automatically check for updates", isOn: Binding(
            get: { automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
        ))
        Toggle("Automatically download updates", isOn: Binding(
            get: { automaticallyDownloadsUpdates },
            set: { updater.automaticallyDownloadsUpdates = $0 }
        ))
        .disabled(!automaticallyChecksForUpdates)
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!canCheckForUpdates)
            .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheckForUpdates = $0 }
            .onReceive(updater.publisher(for: \.automaticallyChecksForUpdates)) { automaticallyChecksForUpdates = $0 }
            .onReceive(updater.publisher(for: \.automaticallyDownloadsUpdates)) { automaticallyDownloadsUpdates = $0 }
    }
}

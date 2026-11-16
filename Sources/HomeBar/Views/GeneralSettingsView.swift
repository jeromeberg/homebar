import AppKit
#if !APP_STORE
import Sparkle
#endif
import SwiftUI

struct GeneralSettingsView: View {
    #if !APP_STORE
    let updater: SPUUpdater
    #endif
    @AppStorage("menuMaxHeight") private var menuMaxHeight = 400.0

    var body: some View {
        Form {
            LaunchAtLoginView()
            Section("Dashboard") {
                LabeledContent("Maximum height", value: "\(Int(menuMaxHeight)) points")
                Slider(value: $menuMaxHeight, in: 200...800, step: 50) {
                    Text("Maximum height")
                }
                Text("The dashboard scrolls when it reaches this height.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #if !APP_STORE
            Section("Updates") {
                UpdateSettingsView(updater: updater)
            }
            #endif
            Section {
                Button("Quit HomeBar") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .formStyle(.grouped)
    }
}

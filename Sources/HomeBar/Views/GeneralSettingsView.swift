import ServiceManagement
import Sparkle
import SwiftUI

struct GeneralSettingsView: View {
    let updater: SPUUpdater
    @AppStorage("menuMaxHeight") private var menuMaxHeight = 400.0
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = SMAppService.mainApp.status
    @State private var error: String?

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { status == .enabled || status == .requiresApproval },
                set: { enabled in setLaunchAtLogin(enabled) }
            ))
            Text("Start HomeBar automatically when you log in to your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if status == .requiresApproval {
                Text("Allow HomeBar in System Settings to enable launch at login.")
                    .font(.callout)
                Button("Open Login Items Settings…") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Section("Dashboard") {
                LabeledContent("Maximum height", value: "\(Int(menuMaxHeight)) points")
                Slider(value: $menuMaxHeight, in: 200...800, step: 50) {
                    Text("Maximum height")
                }
                Text("The dashboard scrolls when it reaches this height.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Updates") {
                UpdateSettingsView(updater: updater)
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshStatus() }
        }
    }

    /** Refresh the login item status from macOS when settings become visible or active. */
    private func refreshStatus() {
        status = SMAppService.mainApp.status
    }

    /** Register or unregister HomeBar for login according to enabled, then show the system status or an error. */
    private func setLaunchAtLogin(_ enabled: Bool) {
        error = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            self.error = "Could not change launch at login. Try again or check Login Items in System Settings."
        }
        refreshStatus()
    }
}

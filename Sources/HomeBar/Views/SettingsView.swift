import HomeBarCore
import Sparkle
import SwiftUI

struct SettingsView: View {
    @Bindable var connection: ConnectionViewModel
    let updater: SPUUpdater

    var body: some View {
        TabView {
            EntityPickerView(store: connection.entities, connected: connection.state == .connected)
                .tabItem { Label("Entities", systemImage: "checklist") }
            CustomizeSettingsView(store: connection.entities)
                .tabItem { Label("Customize", systemImage: "slider.horizontal.3") }
            VStack(alignment: .leading, spacing: 16) {
                Text(connection.state.label).font(.headline)
                if let detail = connection.detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                ConnectionSettingsView(connection: connection)
                if connection.state == .connected || connection.state.isBusy {
                    Button("Disconnect", action: connection.disconnect)
                }
                Spacer()
            }
            .padding(24)
            .tabItem { Label("Connection", systemImage: "network") }
            GeneralSettingsView(updater: updater)
                .tabItem { Label("General", systemImage: "gearshape") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 540, idealWidth: 580, minHeight: 440, idealHeight: 540)
    }
}

import HomeBarCore
import Sparkle
import SwiftUI

enum SettingsTab: Hashable {
    case entities, customize, connection, general, about
}

struct SettingsView: View {
    @Bindable var connection: ConnectionViewModel
    let updater: SPUUpdater
    @Binding var selectedTab: SettingsTab

    var body: some View {
        TabView(selection: $selectedTab) {
            EntityPickerView(store: connection.entities, connected: connection.state == .connected)
                .tabItem { Label("Entities", systemImage: "checklist") }
                .tag(SettingsTab.entities)
            CustomizeSettingsView(store: connection.entities)
                .tabItem { Label("Customize", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.customize)
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
            .tag(SettingsTab.connection)
            GeneralSettingsView(updater: updater)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(minWidth: 540, idealWidth: 580, minHeight: 440, idealHeight: 540)
    }
}

import HomeBarCore
import Sparkle
import SwiftUI

enum SettingsTab: Hashable {
    case general, entities, customize, connection, about
}

struct SettingsView: View {
    @Bindable var connection: ConnectionViewModel
    let updater: SPUUpdater
    @Binding var selectedTab: SettingsTab

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(updater: updater)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            EntityPickerView(store: connection.entities, connected: connection.state == .connected)
                .tabItem { Label("Entities", systemImage: "checklist") }
                .tag(SettingsTab.entities)
            CustomizeSettingsView(store: connection.entities)
                .tabItem { Label("Customize", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.customize)
            VStack(alignment: .leading, spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Text(connection.state.label).font(.headline)
                            ConnectionStatusIndicator(state: connection.state)
                                .accessibilityHidden(true)
                        }
                        if let detail = connection.detail {
                            Text(detail).font(.callout).foregroundStyle(.secondary)
                        }
                        ConnectionSettingsView(connection: connection)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                HStack {
                    if connection.state == .connected {
                        Button("Disconnect", action: connection.disconnect)
                            .help("Disconnect until you reconnect or restart HomeBar.")
                    }
                    if connection.hasSavedToken && !connection.state.isBusy {
                        Button(connection.hasSavedRefreshToken ? "Sign Out" : "Forget Token", action: connection.signOut)
                            .help(connection.hasSavedRefreshToken
                                  ? "Remove saved credentials and revoke this Home Assistant session. Sign out to switch accounts or servers."
                                  : "Remove the saved token from HomeBar to switch accounts or servers. The token remains valid in Home Assistant.")
                    }
                }
            }
            .padding(24)
            .tabItem { Label("Server", systemImage: "network") }
            .tag(SettingsTab.connection)
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(minWidth: 540, idealWidth: 580, minHeight: 440, idealHeight: 540)
    }
}

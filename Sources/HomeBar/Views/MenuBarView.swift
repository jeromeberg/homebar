import AppKit
import HomeBarCore
import SwiftUI

struct MenuBarView: View {
    @Bindable var connection: ConnectionViewModel
    @Binding var settingsTab: SettingsTab
    @Environment(\.openSettings) private var showSettings
    @AppStorage("menuMaxHeight") private var menuMaxHeight = 400.0
    @State private var entityListHeight: CGFloat = 1

    private var connectionColor: Color {
        switch connection.state {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .disconnected: .gray
        case .failed: .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Label("HomeBar", systemImage: "house.fill").font(.headline)
                Spacer()
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)
                    .help([connection.state.label, connection.detail].compactMap { $0 }.joined(separator: "\n"))
                    .accessibilityLabel(connection.state.label)
                Menu {
                    Button("Settings…", action: openSettings)
                    Divider()
                    Button("Disconnect", action: connection.disconnect)
                        .disabled(connection.state != .connected && !connection.state.isBusy)
                    Button("Quit HomeBar") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Settings and actions")
                .accessibilityLabel("Settings and actions")
            }
            .padding(18)
            Divider()
            if connection.state == .connected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if connection.entities.isLoading {
                            ProgressView("Loading entities…").controlSize(.small)
                        }
                        if !connection.entities.errors.isEmpty {
                            Text(connection.entities.errors.joined(separator: "\n"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if connection.entities.selectedIDs.isEmpty {
                            Text("You're ready! You can now add entities to your dashboard.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("Choose entities…") {
                                settingsTab = .entities
                                openSettings()
                            }
                        } else {
                            ForEach(connection.entities.selectedEntities) { entity in
                                if entity.domain == "sensor" { EntityRowView(entity: entity) }
                                else if entity.domain == "climate" { ClimateControlView(entity: entity, connection: connection) }
                                else { DeviceControlView(entity: entity, connection: connection) }
                                Divider()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        entityListHeight = height
                    }
                }
                .frame(height: min(entityListHeight, CGFloat(menuMaxHeight)))
            } else {
                ConnectionSettingsView(connection: connection)
                    .padding(18)
            }
        }
        .frame(width: 340)
    }

    /** Bring the separate settings window forward from the menu bar popup. */
    private func openSettings() {
        showSettings()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

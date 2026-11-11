import AppKit
import HomeBarCore
import SwiftUI

struct MenuBarView: View {
    @Bindable var connection: ConnectionViewModel
    @Environment(\.openSettings) private var showSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("HomeBar", systemImage: "house.fill").font(.headline)
                Spacer()
                if connection.state == .connected {
                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                    .accessibilityLabel("Settings")
                }
            }
            Divider()
            HStack(spacing: 8) {
                if connection.state.isBusy { ProgressView().controlSize(.small) }
                else {
                    Image(systemName: connection.state == .connected ? "checkmark.circle.fill" : "circle.fill")
                        .foregroundStyle(connection.state == .connected ? Color.green : Color.secondary)
                        .font(.caption)
                }
                Text(connection.state.label).font(.subheadline.weight(.medium))
            }
            if let detail = connection.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if connection.state == .connected {
                if let version = connection.version {
                    Text("Home Assistant \(version)").font(.caption).foregroundStyle(.secondary)
                }
                if connection.entities.isLoading {
                    ProgressView("Loading entities…").controlSize(.small)
                }
                if !connection.entities.errors.isEmpty {
                    Text(connection.entities.errors.joined(separator: "\n"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if connection.entities.selectedIDs.isEmpty {
                    Text("Choose entities to display here.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Choose Entities…", action: openSettings)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(connection.entities.selectedEntities) { entity in
                                EntityRowView(entity: entity)
                            }
                        }
                    }
                    .frame(height: min(CGFloat(connection.entities.selectedEntities.count) * 48, 320))
                }
            } else {
                ConnectionSettingsView(connection: connection)
            }
            Divider()
            HStack {
                Button("Settings…", action: openSettings)
                if connection.state == .connected || connection.state.isBusy {
                    Button("Disconnect", action: connection.disconnect)
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }.controlSize(.small)
        }
        .padding(18)
        .frame(width: 340)
    }

    /** Bring the separate settings window forward from the menu bar popup. */
    private func openSettings() {
        showSettings()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

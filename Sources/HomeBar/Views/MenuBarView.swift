import AppKit
import HomeBarCore
import SwiftUI

struct MenuBarView: View {
    @Bindable var connection: ConnectionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("HomeBar", systemImage: "house.fill").font(.headline)
                Spacer()
                if connection.state == .connected {
                    Button { connection.showingSettings.toggle() } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)
                    .help("Connection settings")
                    .accessibilityLabel("Connection settings")
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
            if connection.state == .connected && !connection.showingSettings {
                if let version = connection.version {
                    Text("Home Assistant \(version)").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ready to control your home").font(.subheadline)
                    Text("Coming soon.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            } else {
                ConnectionSettingsView(connection: connection)
            }
            Divider()
            HStack {
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
}

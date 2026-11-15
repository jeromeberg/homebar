import AppKit
import HomeBarCore
import SwiftUI

struct OnboardingView: View {
    @Bindable var connection: ConnectionViewModel
    @Binding var settingsTab: SettingsTab
    @Environment(\.openSettings) private var openSettings
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Welcome to HomeBar", systemImage: "house.fill")
                .font(.title2.weight(.semibold))
            Text("Thanks for downloading and using HomeBar!")
                .foregroundStyle(.secondary)

            Divider()
            if connection.state != .connected {
                ConnectionSettingsView(connection: connection)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(connection.state.label).font(.subheadline.weight(.semibold))
                    ConnectionStatusIndicator(state: connection.state)
                        .accessibilityHidden(true)
                }
                if let detail = connection.detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                } else if connection.state == .connected {
                    Text("Click the house icon in your menu bar to open the dashboard.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            LaunchAtLoginView()
                .toggleStyle(.checkbox)
                .padding(.top, 8)

            HStack {
                Spacer()
                Button("Set Up Later", action: onFinish)
                if connection.state == .connected {
                    Button("Pick my entities") {
                        settingsTab = .entities
                        openSettings()
                        onFinish()
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

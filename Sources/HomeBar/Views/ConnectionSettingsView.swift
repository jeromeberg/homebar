import HomeBarCore
import SwiftUI

struct ConnectionSettingsView: View {
    @Bindable var connection: ConnectionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect to Home Assistant").font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 5) {
                Text("Server URL").font(.caption)
                TextField("http://192.168.1.10:8123", text: $connection.serverURL)
                    .textContentType(.URL)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Access Token").font(.caption)
                SecureField(connection.hasSavedToken ? "Saved in Keychain — leave blank to reuse" : "Long-Lived Access Token",
                            text: $connection.tokenInput)
                if connection.hasSavedToken {
                    Text("A saved token is reused only for its original server.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button(connection.state == .connected ? "Save and Connect" : "Connect", action: connection.connect)
                    .buttonStyle(.borderedProminent)
                    .disabled(connection.state.isBusy)
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}

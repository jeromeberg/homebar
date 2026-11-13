import HomeBarCore
import SwiftUI

struct ConnectionSettingsView: View {
    @Bindable var connection: ConnectionViewModel
    @State private var discovery = ServerDiscovery()
    @State private var showingTokenHelp = false
    @State private var showingTokenEntry = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect to Home Assistant").font(.subheadline.weight(.semibold))
            HStack {
                Menu("Discovered Servers") {
                    ForEach(discovery.servers) { server in
                        Button("\(server.name) — \(server.url)") {
                            connection.serverURL = server.url
                        }
                    }
                }
                .disabled(discovery.servers.isEmpty || connection.state.isBusy)
                if discovery.servers.isEmpty {
                    Text(discovery.error == nil ? "Searching the local network…" : "Discovery unavailable")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if discovery.error != nil {
                    Button("Retry", action: discovery.start)
                }
            }
            if let error = discovery.error {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Server URL").font(.caption)
                TextField("http://192.168.1.10:8123", text: $connection.serverURL)
                    .textContentType(.URL)
                    .disabled(connection.state.isBusy)
            }
            HStack {
                Button("Sign in with Home Assistant", action: connection.signIn)
                    .buttonStyle(.borderedProminent)
                    .disabled(connection.state.isBusy)
                if connection.state.isBusy {
                    Button("Cancel", action: connection.disconnect)
                } else if connection.hasSavedToken {
                    Button("Sign Out", action: connection.signOut)
                }
            }
            Text("Sign in securely in your browser.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup(isExpanded: $showingTokenEntry) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text("Access Token").font(.caption)
                        Button {
                            showingTokenHelp = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("How to get an access token")
                        .help("How to get an access token")
                        .popover(isPresented: $showingTokenHelp) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Create an Access Token").font(.headline)
                                Text("1. Open Home Assistant → your profile → Security.")
                                Text("2. Under Long-lived access tokens, create a new token.")
                                Text("3. Copy it and paste it here. The token is shown only once.")
                            }
                            .font(.callout)
                            .padding(16)
                            .frame(width: 300, alignment: .leading)
                        }
                    }
                    SecureField(connection.hasSavedToken ? "Saved in Keychain — leave blank to reuse" : "Long-Lived Access Token",
                                text: $connection.tokenInput)
                }
                HStack {
                    Spacer()
                    Button(connection.state == .connected ? "Save and Connect" : "Connect", action: connection.connect)
                        .buttonStyle(.borderedProminent)
                        .disabled(connection.state.isBusy)
                }
            } label: {
                Button("Use an access token") {
                    showingTokenEntry.toggle()
                }
                .buttonStyle(.plain)
            }
        }
        .textFieldStyle(.roundedBorder)
        .onAppear(perform: discovery.start)
        .onDisappear(perform: discovery.stop)
    }
}

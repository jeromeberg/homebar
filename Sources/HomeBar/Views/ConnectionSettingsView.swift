import HomeBarCore
import SwiftUI

struct ConnectionSettingsView: View {
    @Bindable var connection: ConnectionViewModel
    @State private var discovery = ServerDiscovery()
    @State private var showingTokenHelp = false
    @State private var showingTokenEntry = false
    @State private var manualURLSelected = false

    private var showingURLField: Bool {
        manualURLSelected || !discovery.servers.contains { $0.url == connection.serverURL }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect to Home Assistant").font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Choose a server").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if discovery.error != nil {
                        Button("Retry", action: discovery.start)
                            .controlSize(.small)
                    }
                }
                if discovery.servers.isEmpty {
                    Text(discovery.error ?? "Searching the local network…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(discovery.servers) { server in
                            ServerChoiceRow(title: server.name, subtitle: server.url,
                                            selected: !showingURLField && connection.serverURL == server.url) {
                                manualURLSelected = false
                                connection.serverURL = server.url
                            }
                            .help(server.url)
                        }
                        ServerChoiceRow(title: "Enter URL manually…", selected: showingURLField) {
                            manualURLSelected = true
                        }
                    }
                    .padding(4)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: CGFloat(min(discovery.servers.count + 1, 4)) * 60 + 4)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.primary.opacity(0.1))
                        .allowsHitTesting(false)
                }
                .disabled(connection.state.isBusy)
                .accessibilityLabel("Choose a server")
            }
            if showingURLField {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Server URL").font(.caption)
                    TextField("http://192.168.1.10:8123", text: $connection.serverURL)
                        .textContentType(.URL)
                        .disabled(connection.state.isBusy)
                }
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

private struct ServerChoiceRow: View {
    let title: String
    var subtitle: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.medium))
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 56)
            .background(selected ? Color.accentColor.opacity(0.1) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

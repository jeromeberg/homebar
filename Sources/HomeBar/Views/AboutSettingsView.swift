import AppKit
import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("HomeBar")
                .font(.title2.bold())
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("A lightweight menu bar dashboard for Home Assistant.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Link("homebar.jebrg.com", destination: URL(string: "https://homebar.jebrg.com/")!)
            Link("Privacy Policy", destination: URL(string: "https://homebar.jebrg.com/privacy.html")!)
                .font(.caption)
            Text("Copyright © 2026 Jerome Berg")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

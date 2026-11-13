import HomeBarCore
import SwiftUI

struct OnboardingView: View {
    @Bindable var connection: ConnectionViewModel
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

            VStack(alignment: .leading, spacing: 4) {
                Text(connection.state.label).font(.subheadline.weight(.semibold))
                if let detail = connection.detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                } else if connection.state == .connected {
                    Text("HomeBar now lives in your menu bar. Click the house icon at the top your screen to open it!")
                        .font(.body)
                }
            }

            HStack {
                Spacer()
                Button(connection.state == .connected ? "Done" : "Set Up Later", action: onFinish)
            }
        }
        .padding(28)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

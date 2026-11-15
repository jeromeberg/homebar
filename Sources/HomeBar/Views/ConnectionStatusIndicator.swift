import HomeBarCore
import SwiftUI

struct ConnectionStatusIndicator: View {
    let state: ConnectionState

    private var color: Color {
        switch state {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .disconnected: .gray
        case .failed: .red
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(state.label)
    }
}

import AppKit
import HomeBarCore
import SwiftUI

@main
struct HomeBarApp: App {
    @State private var connection: ConnectionViewModel

    /** Start the saved connection once for the process lifetime. */
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = ConnectionViewModel()
        _connection = State(initialValue: model)
        model.restore()
    }

    var body: some Scene {
        MenuBarExtra("HomeBar", systemImage: "house.fill") {
            MenuBarView(connection: connection)
        }
        .menuBarExtraStyle(.window)
    }
}

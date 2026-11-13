import AppKit
import HomeBarCore
import Sparkle
import SwiftUI

@main
struct HomeBarApp: App {
    @NSApplicationDelegateAdaptor(HomeBarAppDelegate.self) private var appDelegate
    @State private var connection: ConnectionViewModel
    @State private var settingsTab: SettingsTab = .entities
    private let updaterController: SPUStandardUpdaterController

    /** Start the saved connection and the configured updater for the process lifetime. */
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let model = ConnectionViewModel()
        _connection = State(initialValue: model)
        model.restore()
        appDelegate.connection = model
    }

    var body: some Scene {
        MenuBarExtra("HomeBar", systemImage: "house.fill") {
            MenuBarView(connection: connection, settingsTab: $settingsTab)
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView(connection: connection, updater: updaterController.updater, selectedTab: $settingsTab)
        }
        .defaultSize(width: 580, height: 540)
    }
}

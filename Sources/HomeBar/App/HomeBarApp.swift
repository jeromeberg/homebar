import AppKit
import HomeBarCore
#if !APP_STORE
import Sparkle
#endif
import SwiftUI

@main
struct HomeBarApp: App {
    @NSApplicationDelegateAdaptor(HomeBarAppDelegate.self) private var appDelegate
    @State private var connection: ConnectionViewModel
    #if !APP_STORE
    private let updaterController: SPUStandardUpdaterController
    #endif

    /** Restore the saved connection and start Sparkle in direct builds. */
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        #if !APP_STORE
        updaterController = SPUStandardUpdaterController(
            startingUpdater: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif
        let model = ConnectionViewModel()
        _connection = State(initialValue: model)
        model.restore()
        appDelegate.connection = model
    }

    var body: some Scene {
        @Bindable var appDelegate = appDelegate

        MenuBarExtra("HomeBar", systemImage: "house.fill") {
            MenuBarView(connection: connection, settingsTab: $appDelegate.settingsTab)
        }
        .menuBarExtraStyle(.window)
        Settings {
            #if APP_STORE
            SettingsView(connection: connection, selectedTab: $appDelegate.settingsTab)
            #else
            SettingsView(connection: connection, updater: updaterController.updater, selectedTab: $appDelegate.settingsTab)
            #endif
        }
        .defaultSize(width: 580, height: 540)
    }
}

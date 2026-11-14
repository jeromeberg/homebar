import AppKit
import HomeBarCore
import SwiftUI

@MainActor
final class HomeBarAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var connection: ConnectionViewModel?
    private var onboardingWindow: NSWindow?
    private let completedKey = "onboardingCompleted"

    /** Show setup on first launch or when --show-onboarding is supplied. */
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let connection else { return }
        if !ProcessInfo.processInfo.arguments.contains("--show-onboarding") {
            guard !UserDefaults.standard.bool(forKey: completedKey) else { return }
            guard !connection.hasSavedToken else {
                UserDefaults.standard.set(true, forKey: completedKey)
                return
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to HomeBar"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let contentView = NSHostingView(rootView: OnboardingView(connection: connection) { [weak self] in
            self?.onboardingWindow?.close()
        })
        window.contentView = contentView
        window.setContentSize(contentView.fittingSize)
        window.center()
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /** Remember dismissal and release the onboarding window after it closes. */
    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: completedKey)
        onboardingWindow = nil
    }
}

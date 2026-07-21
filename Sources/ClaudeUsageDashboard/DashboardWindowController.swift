import AppKit
import SwiftUI

extension Notification.Name {
    static let showSetupSheet = Notification.Name("com.ngoujon.claudeusagedashboard.showSetupSheet")
}

final class DashboardWindowController: NSWindowController, NSWindowDelegate {
    private let usageService: UsageService
    private let displaySleepBlocker = DisplaySleepBlocker()

    init(usageService: UsageService, gitWatcher: GitWatcher, urlMonitor: URLMonitor) {
        self.usageService = usageService

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        window.title = "Claude — Suivi de session"
        window.center()
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DashboardView(usageService: usageService, gitWatcher: gitWatcher, urlMonitor: urlMonitor))
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func presentSetupSheet() {
        NotificationCenter.default.post(name: .showSetupSheet, object: nil)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        displaySleepBlocker.start()
    }

    func windowWillClose(_ notification: Notification) {
        displaySleepBlocker.stop()
    }
}

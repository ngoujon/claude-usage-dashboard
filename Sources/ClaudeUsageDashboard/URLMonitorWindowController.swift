import AppKit
import SwiftUI

final class URLMonitorWindowController: NSWindowController {
    init(urlMonitor: URLMonitor) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        window.title = "URLs surveillées"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: URLMonitorSettingsView(urlMonitor: urlMonitor))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

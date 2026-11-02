import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let usageService = UsageService()
    private let urlMonitor = URLMonitor()
    private let tokenMonitor = TokenMonitor()
    private var dashboardWindowController: DashboardWindowController?
    private var urlMonitorWindowController: URLMonitorWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        usageService.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusTitle()
            }
            .store(in: &cancellables)

        usageService.start()
        urlMonitor.start()
        tokenMonitor.start()

        showDashboard()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "…"
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Ouvrir le tableau de bord", action: #selector(showDashboard), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Rafraîchir maintenant", action: #selector(manualRefresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Reconfigurer la session", action: #selector(reconfigure), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Gérer les URLs surveillées…", action: #selector(showURLMonitor), keyEquivalent: "u"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quitter", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }
        if let levels = usageService.menuBarLevels {
            button.title = ""
            button.image = Self.levelBarsImage(levels)
        } else {
            button.image = nil
            button.title = usageService.menuBarTitle
        }
    }

    /// Petites barres verticales façon histogramme, remplies selon chaque niveau.
    private static func levelBarsImage(_ levels: [Double]) -> NSImage {
        let barWidth: CGFloat = 4, gap: CGFloat = 2, height: CGFloat = 14
        let width = CGFloat(levels.count) * barWidth + CGFloat(levels.count - 1) * gap
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            for (i, level) in levels.enumerated() {
                let x = CGFloat(i) * (barWidth + gap)
                let frame = NSRect(x: x, y: 0, width: barWidth, height: height)
                NSColor.black.withAlphaComponent(0.3).setFill()
                NSBezierPath(roundedRect: frame, xRadius: 1, yRadius: 1).fill()
                let fillHeight = level > 0 ? max(1.5, height * CGFloat(level)) : 0
                NSColor.black.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: barWidth, height: fillHeight), xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func showDashboard() {
        if dashboardWindowController == nil {
            dashboardWindowController = DashboardWindowController(
                usageService: usageService,
                urlMonitor: urlMonitor,
                tokenMonitor: tokenMonitor
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindowController?.showWindow(nil)
        dashboardWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func manualRefresh() {
        Task {
            async let usage: Void = usageService.refresh()
            async let urls: Void = urlMonitor.checkAll()
            async let tokens: Void = tokenMonitor.refresh()
            _ = await (usage, urls, tokens)
        }
    }

    @objc private func showURLMonitor() {
        if urlMonitorWindowController == nil {
            urlMonitorWindowController = URLMonitorWindowController(urlMonitor: urlMonitor)
        }
        NSApp.activate(ignoringOtherApps: true)
        urlMonitorWindowController?.showWindow(nil)
        urlMonitorWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func reconfigure() {
        showDashboard()
        dashboardWindowController?.presentSetupSheet()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

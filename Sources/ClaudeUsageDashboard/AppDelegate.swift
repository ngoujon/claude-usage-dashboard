import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let usageService = UsageService()
    private var dashboardWindowController: DashboardWindowController?
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

        if usageService.config == nil {
            showDashboard()
        }
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
        menu.addItem(NSMenuItem(title: "Quitter", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func updateStatusTitle() {
        statusItem.button?.title = usageService.menuBarTitle
    }

    @objc private func showDashboard() {
        if dashboardWindowController == nil {
            dashboardWindowController = DashboardWindowController(usageService: usageService)
        }
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindowController?.showWindow(nil)
        dashboardWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func manualRefresh() {
        Task { await usageService.refresh() }
    }

    @objc private func reconfigure() {
        showDashboard()
        dashboardWindowController?.presentSetupSheet()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

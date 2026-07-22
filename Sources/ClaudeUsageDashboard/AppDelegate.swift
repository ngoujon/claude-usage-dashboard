import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let usageService = UsageService()
    private let gitWatcher = GitWatcher()
    private let urlMonitor = URLMonitor()
    private let updateRunner = UpdateRunner()
    private let dockerStatusMonitor = DockerStatusMonitor()
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

        updateRunner.onJobFinished = { [weak gitWatcher, weak dockerStatusMonitor] projectID, exitCode in
            dockerStatusMonitor?.checkNow()
            guard exitCode == 0 else { return }
            gitWatcher?.markDeployed(projectID)
        }

        usageService.start()
        gitWatcher.start()
        urlMonitor.start()

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
        statusItem.button?.title = usageService.menuBarTitle
    }

    @objc private func showDashboard() {
        if dashboardWindowController == nil {
            dashboardWindowController = DashboardWindowController(
                usageService: usageService,
                gitWatcher: gitWatcher,
                urlMonitor: urlMonitor,
                updateRunner: updateRunner,
                dockerStatusMonitor: dockerStatusMonitor
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
            async let git: Void = gitWatcher.check()
            _ = await (usage, urls, git)
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

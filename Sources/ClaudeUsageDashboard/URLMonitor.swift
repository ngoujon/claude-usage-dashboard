import Foundation

struct MonitoredURLStatus: Identifiable {
    let id: String
    var isDown: Bool
    var lastCheck: Date?
    var detail: String?
}

@MainActor
final class URLMonitor: ObservableObject {
    @Published private(set) var urls: [String]
    @Published private(set) var statuses: [String: MonitoredURLStatus] = [:]

    private let defaultsKey = "monitoredURLs"
    private let checkInterval: TimeInterval = 10 * 60
    private var timer: Timer?

    init() {
        urls = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
    }

    func start() {
        Task { await checkAll() }
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkAll() }
        }
    }

    func updateURLs(_ newURLs: [String]) {
        let cleaned = newURLs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        urls = cleaned
        UserDefaults.standard.set(cleaned, forKey: defaultsKey)
        statuses = statuses.filter { cleaned.contains($0.key) }
        Task { await checkAll() }
    }

    func checkAll() async {
        for urlString in urls {
            await check(urlString)
        }
    }

    private func check(_ urlString: String) async {
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let isServerError = statusCode >= 500

            statuses[urlString] = MonitoredURLStatus(
                id: urlString,
                isDown: isServerError,
                lastCheck: Date(),
                detail: isServerError ? "HTTP \(statusCode)" : nil
            )
        } catch {
            statuses[urlString] = MonitoredURLStatus(
                id: urlString,
                isDown: true,
                lastCheck: Date(),
                detail: error.localizedDescription
            )
        }
    }
}

import Foundation

struct MonitoredURLStatus: Identifiable {
    let id: String
    var isDown: Bool
    var lastCheck: Date?
    var detail: String?
    var title: String?
    var downSince: Date?
}

@MainActor
final class URLMonitor: ObservableObject {
    @Published private(set) var urls: [String]
    @Published private(set) var statuses: [String: MonitoredURLStatus] = [:]

    private let defaultsKey = "monitoredURLs"
    private let titlesDefaultsKey = "monitoredURLTitles"
    private let checkInterval: TimeInterval = 10 * 60
    private var timer: Timer?
    /// Page titles remembered across launches, so a project name shows before the first check.
    private var cachedTitles: [String: String]
    /// Health endpoints whose site title was already looked up during this launch.
    private var titleLookups: Set<String> = []

    /// Defaults domain used before the bundle identifier moved to com.ngoujon.
    private let legacyDefaultsDomain = "com.nicolasgoujon.claudeusagedashboard"

    init() {
        cachedTitles = UserDefaults.standard.dictionary(forKey: "monitoredURLTitles") as? [String: String] ?? [:]
        if let saved = UserDefaults.standard.stringArray(forKey: defaultsKey) {
            urls = saved
        } else if let legacy = UserDefaults(suiteName: legacyDefaultsDomain)?.stringArray(forKey: defaultsKey) {
            // One-time migration so the health checks survive the bundle identifier change.
            urls = legacy
            UserDefaults.standard.set(legacy, forKey: defaultsKey)
        } else {
            urls = []
        }
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

    /// Project name shown in the sidebar: the site's page title, or a name derived from the URL.
    /// When several sites share a title (two n8n instances), the URL-derived name tells them apart.
    func displayName(for urlString: String) -> String {
        let fallback = Self.fallbackName(for: urlString)
        guard let title = title(for: urlString) else { return fallback }
        let isShared = urls.contains { $0 != urlString && self.title(for: $0) == title }
        return isShared ? "\(title) · \(fallback)" : title
    }

    private func title(for urlString: String) -> String? {
        statuses[urlString]?.title ?? cachedTitles[urlString]
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
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let isServerError = statusCode >= 500
            let previous = statuses[urlString]
            let title = await resolveTitle(for: urlString, url: url, body: data)

            statuses[urlString] = MonitoredURLStatus(
                id: urlString,
                isDown: isServerError,
                lastCheck: Date(),
                detail: isServerError ? "HTTP \(statusCode)" : nil,
                title: title ?? previous?.title,
                downSince: isServerError ? (previous?.isDown == true ? previous?.downSince : Date()) : nil
            )
        } catch {
            let previous = statuses[urlString]
            statuses[urlString] = MonitoredURLStatus(
                id: urlString,
                isDown: true,
                lastCheck: Date(),
                detail: error.localizedDescription,
                title: previous?.title ?? cachedTitles[urlString],
                downSince: previous?.isDown == true ? previous?.downSince : Date()
            )
        }
    }

    /// Health endpoints answer JSON without a <title>, so the name comes from the site's home page,
    /// looked up once per launch and cached.
    private func resolveTitle(for urlString: String, url: URL, body: Data) async -> String? {
        if let title = Self.extractTitle(from: body) {
            storeTitle(title, for: urlString)
            return title
        }
        if titleLookups.contains(urlString) { return cachedTitles[urlString] }
        titleLookups.insert(urlString)

        guard let home = Self.siteHome(for: url) else { return cachedTitles[urlString] }
        let request = URLRequest(url: home, timeoutInterval: 15)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let title = Self.extractTitle(from: data)
        else {
            return cachedTitles[urlString]
        }
        storeTitle(title, for: urlString)
        return title
    }

    private func storeTitle(_ title: String, for urlString: String) {
        guard cachedTitles[urlString] != title else { return }
        cachedTitles[urlString] = title
        UserDefaults.standard.set(cachedTitles, forKey: titlesDefaultsKey)
    }

    nonisolated private static let healthPathComponents: Set<String> = ["health", "healthz", "up", "api"]

    /// Home page of the app behind a health URL: `/seo-monitor/health` → `/seo-monitor/`,
    /// `api.qwebty.com/health` → `qwebty.com/`.
    nonisolated static func siteHome(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host
        else { return nil }

        var segments = components.path.split(separator: "/").map(String.init)
        while let last = segments.last, healthPathComponents.contains(last.lowercased()) {
            segments.removeLast()
        }
        if host.hasPrefix("api.") { components.host = String(host.dropFirst(4)) }
        components.path = segments.isEmpty ? "/" : "/" + segments.joined(separator: "/") + "/"
        components.query = nil
        return components.url
    }

    /// Readable name when no page title is known: the domain, or the app path on a bare server hostname.
    nonisolated static func fallbackName(for urlString: String) -> String {
        guard let url = URL(string: urlString), let home = siteHome(for: url), var host = home.host else {
            return urlString
        }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        let path = home.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? host : path
    }

    nonisolated private static func extractTitle(from data: Data) -> String? {
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        guard let openRange = html.range(of: "<title", options: [.caseInsensitive]),
              let tagCloseRange = html.range(of: ">", range: openRange.upperBound..<html.endIndex),
              let closeRange = html.range(of: "</title>", options: [.caseInsensitive], range: tagCloseRange.upperBound..<html.endIndex)
        else {
            return nil
        }

        let raw = html[tagCloseRange.upperBound..<closeRange.lowerBound]
        let decoded = raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return decoded.isEmpty ? nil : decoded
    }
}

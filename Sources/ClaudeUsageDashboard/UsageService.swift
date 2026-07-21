import Foundation

@MainActor
final class UsageService: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot()
    @Published private(set) var config: KeychainStore.Config?

    private var timer: Timer?
    private let pollInterval: TimeInterval = 60
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    init() {
        config = KeychainStore.load() ?? Self.migrateLegacyConfigIfNeeded()
        if config == nil {
            snapshot.errorState = .needsConfig
        }
    }

    func start() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    func saveConfig(usageURL: String, cookie: String) {
        let cfg = KeychainStore.Config(usageURL: usageURL, cookie: cookie)
        KeychainStore.save(cfg)
        config = cfg
        Task { await refresh() }
    }

    func refresh() async {
        guard let config else {
            snapshot.errorState = .needsConfig
            return
        }
        guard let url = URL(string: config.usageURL) else {
            snapshot.errorState = .networkError
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(config.cookie, forHTTPHeaderField: "cookie")
        request.setValue(userAgent, forHTTPHeaderField: "user-agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
                snapshot.errorState = .unauthorized
                return
            }
            let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
            let built = Self.buildSnapshot(from: decoded.limits)
            snapshot.session = built.session
            snapshot.weekly = built.weekly
            snapshot.fable = built.fable
            snapshot.lastUpdated = built.lastUpdated
            snapshot.errorState = .none
        } catch {
            snapshot.errorState = .networkError
        }
    }

    var menuBarTitle: String {
        if snapshot.errorState == .needsConfig { return "⚙️" }
        if snapshot.errorState == .unauthorized { return "🔒" }
        if snapshot.errorState == .networkError { return "⚠️" }

        var parts: [String] = []
        if let s = snapshot.session {
            parts.append("S \(Int(s.percent.rounded()))%\(PaceCalculator.paceArrow(s.pace)) \(PaceCalculator.formatRemainingCompact(s.resetsAt))")
        }
        if let w = snapshot.weekly {
            parts.append("H \(Int(w.percent.rounded()))%\(PaceCalculator.paceArrow(w.pace)) \(PaceCalculator.formatRemainingCompact(w.resetsAt))")
        }
        if let f = snapshot.fable {
            parts.append("F \(Int(f.percent.rounded()))%\(PaceCalculator.paceArrow(f.pace)) \(PaceCalculator.formatRemainingCompact(f.resetsAt))")
        }
        return parts.isEmpty ? "…" : parts.joined(separator: " · ")
    }

    private static func buildSnapshot(from limits: [RawLimit]) -> UsageSnapshot {
        var snap = UsageSnapshot()
        snap.lastUpdated = Date()

        if let session = PaceCalculator.findLimit(limits, kind: "session") {
            let resetsAt = PaceCalculator.parseISODate(session.resetsAt)
            let pace = PaceCalculator.paceStatus(percent: session.percent, resetsAt: resetsAt, period: PaceCalculator.sessionPeriod)
            snap.session = LimitDisplay(percent: session.percent, resetsAt: resetsAt, pace: pace)
        }
        if let weekly = PaceCalculator.findLimit(limits, kind: "weekly_all") {
            let resetsAt = PaceCalculator.parseISODate(weekly.resetsAt)
            let pace = PaceCalculator.paceStatus(percent: weekly.percent, resetsAt: resetsAt, period: PaceCalculator.weeklyPeriod)
            snap.weekly = LimitDisplay(percent: weekly.percent, resetsAt: resetsAt, pace: pace)
        }
        if let fable = PaceCalculator.findLimit(limits, kind: "weekly_scoped", modelName: "Fable") {
            let resetsAt = PaceCalculator.parseISODate(fable.resetsAt)
            let pace = PaceCalculator.paceStatus(percent: fable.percent, resetsAt: resetsAt, period: PaceCalculator.weeklyPeriod)
            snap.fable = LimitDisplay(percent: fable.percent, resetsAt: resetsAt, pace: pace)
        }
        return snap
    }

    private static func migrateLegacyConfigIfNeeded() -> KeychainStore.Config? {
        let legacyPath = ("~/.claude_usage_widget/config.json" as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: legacyPath) else { return nil }

        struct LegacyConfig: Decodable {
            let usageURL: String
            let cookie: String
            enum CodingKeys: String, CodingKey {
                case usageURL = "usage_url"
                case cookie
            }
        }
        guard let legacy = try? JSONDecoder().decode(LegacyConfig.self, from: data) else { return nil }

        let cfg = KeychainStore.Config(usageURL: legacy.usageURL, cookie: legacy.cookie)
        KeychainStore.save(cfg)
        return cfg
    }
}

import Foundation

/// Live token throughput of one Claude Code session, read from its local transcript.
struct ActiveSessionTokens: Identifiable, Sendable {
    /// Transcript file path — stable for the lifetime of the session.
    let id: String
    let project: String
    /// Tokens sent per second over the rate window (context of each request: input + cache).
    let inputRate: Double
    /// Tokens generated per second over the rate window.
    let outputRate: Double
    /// Context currently loaded by the session: last request's input + cache read + cache creation.
    let contextTokens: Int
    /// Output tokens generated since the beginning of the session.
    let outputTokens: Int
    let lastActivity: Date
}

struct TokenUsageSnapshot: Sendable {
    var sessions: [ActiveSessionTokens] = []
    var lastUpdated: Date?

    var activeCount: Int { sessions.count }
    var inputRate: Double { sessions.reduce(0) { $0 + $1.inputRate } }
    var outputRate: Double { sessions.reduce(0) { $0 + $1.outputRate } }
    var contextTokens: Int { sessions.reduce(0) { $0 + $1.contextTokens } }
    var outputTokens: Int { sessions.reduce(0) { $0 + $1.outputTokens } }
    /// Session carrying the most traffic right now.
    var topSession: ActiveSessionTokens? { sessions.first }
}

/// Watches `~/.claude/projects/**/*.jsonl` and reports the token throughput of the sessions
/// that are still being written to. Transcripts are read incrementally: each pass only
/// parses the bytes appended since the previous one.
@MainActor
final class TokenMonitor: ObservableObject {
    @Published private(set) var snapshot = TokenUsageSnapshot()

    /// A transcript counts as active while it has been written to within this window.
    private let activeWindow: TimeInterval = 30 * 60
    /// Sliding window the tokens/second rates are averaged over.
    static let rateWindow: TimeInterval = 60
    /// Transcripts are read incrementally, so polling this often stays cheap.
    private let refreshInterval: TimeInterval = 0.5
    private let projectsDirectory: URL
    private var timer: Timer?
    private var cursors: [String: FileCursor] = [:]
    private var isScanning = false

    init(projectsDirectory: URL = URL(fileURLWithPath: ("~/.claude/projects" as NSString).expandingTildeInPath, isDirectory: true)) {
        self.projectsDirectory = projectsDirectory
    }

    func start() {
        Task { await refresh() }
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() async {
        // Cursors advance as files are read, so two overlapping scans would double-count.
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let directory = projectsDirectory
        let window = activeWindow
        let known = cursors

        let result = await Task.detached(priority: .utility) {
            Self.scan(directory: directory, activeWindow: window, cursors: known)
        }.value

        cursors = result.cursors
        snapshot = TokenUsageSnapshot(
            sessions: result.sessions.sorted {
                ($0.inputRate + $0.outputRate, $0.contextTokens) > ($1.inputRate + $1.outputRate, $1.contextTokens)
            },
            lastUpdated: Date()
        )
    }

    // MARK: - Transcript scanning

    /// One API turn, used to average throughput over the rate window.
    private struct TokenEvent: Sendable {
        let time: Date
        let input: Int
        let output: Int
    }

    private struct FileCursor: Sendable {
        var offset: UInt64 = 0
        var outputTokens: Int = 0
        var contextTokens: Int = 0
        var project: String?
        var events: [TokenEvent] = []
        /// Trailing bytes of an incomplete line, carried over to the next pass.
        var partial = Data()
    }

    private struct TranscriptEntry: Decodable {
        struct Message: Decodable {
            let usage: Usage?
        }
        struct Usage: Decodable {
            let inputTokens: Int?
            let cacheCreationInputTokens: Int?
            let cacheReadInputTokens: Int?
            let outputTokens: Int?
        }
        let message: Message?
        let cwd: String?
        let isSidechain: Bool?
        let timestamp: String?
    }

    /// Guards against an unterminated line growing without bound.
    nonisolated private static let maxPartialBytes = 8 * 1024 * 1024

    nonisolated private static func scan(
        directory: URL,
        activeWindow: TimeInterval,
        cursors: [String: FileCursor]
    ) -> (sessions: [ActiveSessionTokens], cursors: [String: FileCursor]) {
        var updated = cursors
        var sessions: [ActiveSessionTokens] = []
        let now = Date()

        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return ([], cursors)
        }

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) <= activeWindow
            else { continue }

            var cursor = updated[url.path] ?? FileCursor()
            let size = UInt64(values.fileSize ?? 0)
            // A shorter file means it was rewritten: start over.
            if size < cursor.offset { cursor = FileCursor() }
            if size > cursor.offset { consume(url: url, into: &cursor) }
            cursor.events.removeAll { now.timeIntervalSince($0.time) > rateWindow }
            updated[url.path] = cursor

            guard cursor.contextTokens > 0 || cursor.outputTokens > 0 else { continue }
            let inputInWindow = cursor.events.reduce(0) { $0 + $1.input }
            let outputInWindow = cursor.events.reduce(0) { $0 + $1.output }
            sessions.append(ActiveSessionTokens(
                id: url.path,
                project: cursor.project ?? url.deletingLastPathComponent().lastPathComponent,
                inputRate: Double(inputInWindow) / rateWindow,
                outputRate: Double(outputInWindow) / rateWindow,
                contextTokens: cursor.contextTokens,
                outputTokens: cursor.outputTokens,
                lastActivity: modified
            ))
        }

        return (sessions, updated)
    }

    nonisolated private static func consume(url: URL, into cursor: inout FileCursor) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: cursor.offset)) != nil,
              let appended = try? handle.readToEnd(), !appended.isEmpty
        else { return }

        cursor.offset += UInt64(appended.count)

        var buffer = cursor.partial
        buffer.append(appended)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let marker = Data("\"output_tokens\"".utf8)
        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()

        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer = Data(buffer[buffer.index(after: newline)...])

            guard line.range(of: marker) != nil,
                  let entry = try? decoder.decode(TranscriptEntry.self, from: line),
                  let usage = entry.message?.usage
            else { continue }

            if let cwd = entry.cwd, cursor.project == nil {
                cursor.project = URL(fileURLWithPath: cwd).lastPathComponent
            }
            cursor.outputTokens += usage.outputTokens ?? 0

            let sent = (usage.inputTokens ?? 0)
                + (usage.cacheReadInputTokens ?? 0)
                + (usage.cacheCreationInputTokens ?? 0)
            let time = entry.timestamp.flatMap { isoWithFraction.date(from: $0) ?? iso.date(from: $0) } ?? Date()
            cursor.events.append(TokenEvent(time: time, input: sent, output: usage.outputTokens ?? 0))

            // Subagent turns carry their own context, not the session's.
            guard entry.isSidechain != true else { continue }
            if sent > 0 { cursor.contextTokens = sent }
        }

        cursor.partial = buffer.count > maxPartialBytes ? Data() : buffer
    }

    // MARK: - Formatting

    /// Compact French token count: 940, 148 k, 4,2 M.
    static func formatTokens(_ value: Int) -> String {
        let absolute = abs(value)
        if absolute < 1_000 { return "\(value)" }
        if absolute < 1_000_000 {
            return "\(Int((Double(value) / 1_000).rounded())) k"
        }
        let millions = Double(value) / 1_000_000
        let text = millions < 10
            ? String(format: "%.1f", millions)
            : String(format: "%.0f", millions)
        return "\(text.replacingOccurrences(of: ".", with: ",")) M"
    }

    /// Compact French token rate: 0 /s, 84 /s, 1,2 k/s.
    static func formatRate(_ perSecond: Double) -> String {
        if perSecond < 1 { return perSecond > 0 ? "<1 /s" : "0 /s" }
        if perSecond < 1_000 { return "\(Int(perSecond.rounded())) /s" }
        let thousands = perSecond / 1_000
        let text = thousands < 10
            ? String(format: "%.1f", thousands)
            : String(format: "%.0f", thousands)
        return "\(text.replacingOccurrences(of: ".", with: ",")) k/s"
    }
}

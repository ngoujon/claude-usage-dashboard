import Foundation

struct DirtyRepo: Identifiable, Equatable {
    let id: String
    var hasUncommittedChanges: Bool
    var hasUnpushedCommits: Bool
}

@MainActor
final class GitWatcher: ObservableObject {
    @Published private(set) var dirtyRepos: [DirtyRepo] = []
    @Published private(set) var lastCheckedAt: Date?

    private let root = URL(fileURLWithPath: "~/Developer")
    private let checkInterval: TimeInterval = 60
    private var timer: Timer?

    func start() {
        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    func checkNow() {
        Task { await check() }
    }

    func check() async {
        dirtyRepos = await Self.scanRepos(root: root)
        lastCheckedAt = Date()
    }

    nonisolated private static func scanRepos(root: URL) async -> [DirtyRepo] {
        await Task.detached(priority: .utility) {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            var results: [DirtyRepo] = []
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                let gitDir = entry.appendingPathComponent(".git")
                guard FileManager.default.fileExists(atPath: gitDir.path) else { continue }
                if let repo = repoStatus(at: entry) {
                    results.append(repo)
                }
            }
            return results
        }.value
    }

    /// Runs `git status --porcelain --branch`: the first line carries ahead/behind
    /// tracking info (e.g. "## main...origin/main [ahead 2]"), remaining lines list
    /// any uncommitted changes.
    nonisolated private static func repoStatus(at repoURL: URL) -> DirtyRepo? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoURL.path, "status", "--porcelain", "--branch"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        var lines = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard !lines.isEmpty else { return nil }

        let branchLine = lines.removeFirst()
        let hasUncommittedChanges = !lines.isEmpty
        let hasUnpushedCommits = branchLine.contains("ahead")

        guard hasUncommittedChanges || hasUnpushedCommits else { return nil }

        return DirtyRepo(
            id: repoURL.lastPathComponent,
            hasUncommittedChanges: hasUncommittedChanges,
            hasUnpushedCommits: hasUnpushedCommits
        )
    }
}

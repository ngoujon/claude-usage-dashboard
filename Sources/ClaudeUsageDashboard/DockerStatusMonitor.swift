import Foundation

struct DockerProjectStatus: Equatable {
    var isUp: Bool = false
    var lastChecked: Date?
}

@MainActor
final class DockerStatusMonitor: ObservableObject {
    @Published private(set) var statuses: [String: DockerProjectStatus] = [:]

    private let checkInterval: TimeInterval = 15
    private var timer: Timer?
    private var projects: [UpdateProject] = []

    func start(projects: [UpdateProject]) {
        self.projects = projects
        timer?.invalidate()
        Task { await checkAll() }
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkAll() }
        }
    }

    func checkNow() {
        Task { await checkAll() }
    }

    private func checkAll() async {
        await withTaskGroup(of: (String, Bool).self) { group in
            for project in projects {
                group.addTask {
                    let isUp = await Self.isComposeUp(at: project.projectPath)
                    return (project.id, isUp)
                }
            }
            for await (id, isUp) in group {
                statuses[id] = DockerProjectStatus(isUp: isUp, lastChecked: Date())
            }
        }
    }

    nonisolated private static func isComposeUp(at path: String) async -> Bool {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "docker compose ps --status running --quiet"]
            process.currentDirectoryURL = URL(fileURLWithPath: path)

            var env = ProcessInfo.processInfo.environment
            let extraPaths = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin"]
            let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return false
            }

            guard process.terminationStatus == 0 else { return false }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !output.isEmpty
        }.value
    }
}

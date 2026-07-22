import Darwin
import Foundation

struct UpdateJobState: Equatable {
    var isRunning: Bool = false
    var output: String = ""
    var exitCode: Int32?
}

@MainActor
final class UpdateRunner: ObservableObject {
    @Published private(set) var jobs: [String: UpdateJobState] = [:]
    private var processes: [String: Process] = [:]
    /// Called on the main actor when a job finishes, with the project id and exit code.
    var onJobFinished: ((String, Int32) -> Void)?

    func state(for projectID: String) -> UpdateJobState {
        jobs[projectID] ?? UpdateJobState()
    }

    func clearOutput(for projectID: String) {
        var state = jobs[projectID] ?? UpdateJobState()
        state.output = ""
        jobs[projectID] = state
    }

    static let buildCommand = "docker compose down && docker compose build --no-cache && docker compose up -d"
    static let startCommand = "docker compose up -d"
    static let stopCommand = "docker compose down"

    func run(_ project: UpdateProject) {
        launch(
            projectID: project.id,
            projectPath: project.projectPath,
            executableURL: URL(fileURLWithPath: project.scriptPath),
            arguments: [],
            displayCommand: project.scriptPath
        )
    }

    func runBuild(_ project: UpdateProject) {
        launch(
            projectID: project.id,
            projectPath: project.projectPath,
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", Self.buildCommand],
            displayCommand: Self.buildCommand
        )
    }

    func runStart(_ project: UpdateProject) {
        launch(
            projectID: project.id,
            projectPath: project.projectPath,
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", Self.startCommand],
            displayCommand: Self.startCommand
        )
    }

    func runStop(_ project: UpdateProject) {
        launch(
            projectID: project.id,
            projectPath: project.projectPath,
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", Self.stopCommand],
            displayCommand: Self.stopCommand
        )
    }

    private func launch(projectID: String, projectPath: String, executableURL: URL, arguments: [String], displayCommand: String) {
        guard jobs[projectID]?.isRunning != true else { return }
        jobs[projectID] = UpdateJobState(isRunning: true, output: "$ \(displayCommand)\n\n", exitCode: nil)

        // Some update scripts run `ssh -t` (e.g. for sudo prompts on the remote host),
        // which refuses to proceed — "Pseudo-terminal will not be allocated because
        // stdin is not a terminal" — when the local process's stdin is a plain pipe or
        // /dev/null. Give the child a real pseudo-terminal on stdin/stdout/stderr so it
        // behaves exactly as it would when run by hand in Terminal.app.
        guard let pty = Self.openPTY() else {
            jobs[projectID] = UpdateJobState(
                isRunning: false,
                output: "Erreur : impossible d'allouer un pseudo-terminal.\n",
                exitCode: -1
            )
            return
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        process.environment = Self.buildEnvironment()
        process.standardInput = pty.slave
        process.standardOutput = pty.slave
        process.standardError = pty.slave

        pty.master.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            Task { @MainActor in
                self?.appendOutput(text, to: projectID)
            }
        }

        process.terminationHandler = { [weak self] proc in
            pty.master.readabilityHandler = nil
            try? pty.master.close()
            Task { @MainActor in
                self?.finish(projectID, exitCode: proc.terminationStatus)
            }
        }

        do {
            try process.run()
            // The child now holds the slave end; drop our copy so the master sees EOF
            // once the child (and anything it spawned) actually exits.
            try? pty.slave.close()
            processes[projectID] = process
        } catch {
            pty.master.readabilityHandler = nil
            try? pty.master.close()
            try? pty.slave.close()
            jobs[projectID] = UpdateJobState(
                isRunning: false,
                output: "Erreur au lancement : \(error.localizedDescription)\n",
                exitCode: -1
            )
        }
    }

    private struct PTY {
        let master: FileHandle
        let slave: FileHandle
    }

    private static func openPTY() -> PTY? {
        let masterFD = posix_openpt(O_RDWR | O_NOCTTY)
        guard masterFD >= 0 else { return nil }
        guard grantpt(masterFD) == 0, unlockpt(masterFD) == 0,
              let slaveNameCStr = ptsname(masterFD) else {
            close(masterFD)
            return nil
        }
        let slaveFD = open(slaveNameCStr, O_RDWR | O_NOCTTY)
        guard slaveFD >= 0 else {
            close(masterFD)
            return nil
        }
        return PTY(
            master: FileHandle(fileDescriptor: masterFD, closeOnDealloc: true),
            slave: FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
        )
    }

    private func appendOutput(_ text: String, to projectID: String) {
        var state = jobs[projectID] ?? UpdateJobState()
        state.output += text
        jobs[projectID] = state
    }

    private func finish(_ projectID: String, exitCode: Int32) {
        var state = jobs[projectID] ?? UpdateJobState()
        state.isRunning = false
        state.exitCode = exitCode
        state.output += "\n[terminé — code \(exitCode)]\n"
        jobs[projectID] = state
        processes[projectID] = nil
        onJobFinished?(projectID, exitCode)
    }

    private static func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        return env
    }
}

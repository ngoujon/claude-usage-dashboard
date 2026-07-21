import Foundation

struct UpdateProject: Identifiable, Equatable {
    let id: String
    let scriptPath: String
    let projectPath: String
}

enum UpdateScriptScanner {
    private static let subdirectories = ["scripts", "tools"]
    private static let scriptNames = ["update", "update.sh"]

    static func scan(root: URL) -> [UpdateProject] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [UpdateProject] = []

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

            search: for sub in subdirectories {
                for name in scriptNames {
                    let candidate = entry.appendingPathComponent(sub).appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: candidate.path) {
                        results.append(UpdateProject(
                            id: entry.lastPathComponent,
                            scriptPath: candidate.path,
                            projectPath: entry.path
                        ))
                        break search
                    }
                }
            }
        }

        return results
    }
}

import AppKit
import SwiftUI

struct UpdateCenterView: View {
    @ObservedObject var updateRunner: UpdateRunner
    @ObservedObject var gitWatcher: GitWatcher
    let projects: [UpdateProject]
    let onBack: () -> Void
    @State private var selectedProjectID: String?

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                sidebar
                    .frame(width: geo.size.width / 3)

                Divider().background(Color.white.opacity(0.1))

                terminalPane
                    .frame(width: geo.size.width * 2 / 3)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            if selectedProjectID == nil {
                selectedProjectID = projects.first?.id
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Tableau de bord")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Revenir au tableau de bord")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Text("Scripts de mise à jour")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

            legend
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.1))

            if projects.isEmpty {
                Text("Aucun projet avec scripts/update ou tools/update(.sh)")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(16)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(projects) { project in
                            sidebarRow(for: project)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.04))
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(color: .orange, label: "à déployer")
            legendItem(color: .green, label: "à jour")
            legendItem(color: .red, label: "échec")
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
        }
    }

    private func sidebarRow(for project: UpdateProject) -> some View {
        let state = updateRunner.state(for: project.id)
        let isSelected = selectedProjectID == project.id
        let pendingDeploy = gitWatcher.pendingDeployProjectIDs.contains(project.id)

        return Button {
            selectedProjectID = project.id
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    if state.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Circle()
                            .fill(statusColor(state, pendingDeploy: pendingDeploy))
                            .frame(width: 8, height: 8)
                    }
                }
                .frame(width: 14, height: 14)

                Text(project.id)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if pendingDeploy && !state.isRunning {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 6)
        .help(pendingDeploy ? "Nouveau push pas encore déployé" : "")
    }

    private func statusColor(_ state: UpdateJobState, pendingDeploy: Bool) -> Color {
        if pendingDeploy { return .orange }
        guard let exitCode = state.exitCode else { return .white.opacity(0.25) }
        return exitCode == 0 ? .green : .red
    }

    private var selectedProject: UpdateProject? {
        projects.first { $0.id == selectedProjectID }
    }

    private var terminalPane: some View {
        VStack(spacing: 0) {
            terminalHeader
            Divider().background(Color.white.opacity(0.1))
            terminalOutput
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var terminalHeader: some View {
        let state = selectedProjectID.map { updateRunner.state(for: $0) }

        return HStack(spacing: 12) {
            Text(selectedProjectID ?? "Sélectionne un projet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            if let id = selectedProjectID, let state, !state.output.isEmpty {
                Button {
                    copyLogs(state.output)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                        Text("Copier les logs")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Copier tout l'historique du terminal")

                Button {
                    updateRunner.clearOutput(for: id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Effacer")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Effacer le terminal")
            }

            if let project = selectedProject, let state {
                Button {
                    updateRunner.runBuild(project)
                } label: {
                    HStack(spacing: 6) {
                        if state.isRunning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "hammer")
                        }
                        Text(state.isRunning ? "En cours…" : "Build")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.25))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(state.isRunning)
                .help("docker compose down && docker compose build --no-cache && docker compose up -d")

                Button {
                    updateRunner.run(project)
                } label: {
                    HStack(spacing: 6) {
                        if state.isRunning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(state.isRunning ? "En cours…" : "Update")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.25))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(state.isRunning)
            }
        }
        .padding(16)
    }

    private func copyLogs(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var terminalOutput: some View {
        let output = selectedProjectID.map { updateRunner.state(for: $0).output } ?? ""

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(output.isEmpty ? "Aucune sortie pour l'instant." : output)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.green.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(14)
                    Color.clear.frame(height: 1).id("bottom")
                }
            }
            .onChange(of: output) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: selectedProjectID) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}

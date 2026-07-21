import SwiftUI

struct DashboardView: View {
    @ObservedObject var usageService: UsageService
    @ObservedObject var gitWatcher: GitWatcher
    @ObservedObject var urlMonitor: URLMonitor
    @ObservedObject var updateRunner: UpdateRunner
    @State private var showingSetup = false
    @State private var isRefreshing = false
    @State private var showingGitSidebar = true
    @State private var showingURLSidebar = true
    @State private var showingUpdateCenter = false
    @State private var updateProjects: [UpdateProject] = []

    private static let workspaceRoot = URL(fileURLWithPath: "~/Developer")

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if showingUpdateCenter {
                UpdateCenterView(
                    updateRunner: updateRunner,
                    gitWatcher: gitWatcher,
                    projects: updateProjects,
                    onBack: { showingUpdateCenter = false }
                )
            } else {
                HStack(spacing: 0) {
                    if showingGitSidebar && !gitWatcher.dirtyRepos.isEmpty {
                        gitSidebar
                            .transition(.move(edge: .leading))
                    }
                    content
                    if showingURLSidebar && !urlMonitor.urls.isEmpty {
                        urlSidebar
                            .transition(.move(edge: .trailing))
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showingGitSidebar)
        .animation(.easeInOut(duration: 0.2), value: showingURLSidebar)
        .onReceive(NotificationCenter.default.publisher(for: .showSetupSheet)) { _ in
            showingSetup = true
        }
        .onAppear {
            if usageService.snapshot.errorState == .needsConfig {
                showingSetup = true
            }
        }
        .sheet(isPresented: $showingSetup) {
            SetupSheetView(usageService: usageService, isPresented: $showingSetup)
        }
    }

    private var gitSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                Text("Non commités")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(gitWatcher.dirtyRepos.count)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("à commit").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
                HStack(spacing: 5) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("à push").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 14)

            Divider().background(Color.white.opacity(0.1))

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(gitWatcher.dirtyRepos) { repo in
                        GitRepoRow(
                            repo: repo,
                            isPushing: gitWatcher.pushingRepoIDs.contains(repo.id),
                            pushResult: gitWatcher.lastPushResults[repo.id]
                        ) {
                            gitWatcher.push(repo)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(Color.white.opacity(0.04))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundStyle(Color.white.opacity(0.08)),
            alignment: .trailing
        )
    }

    private var urlSidebar: some View {
        let downCount = urlMonitor.urls.filter { urlMonitor.statuses[$0]?.isDown == true }.count

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(downCount == 0 ? .green : .red)
                Text("Health checks")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if downCount > 0 {
                    Text("\(downCount)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
            .padding(16)

            Divider().background(Color.white.opacity(0.1))

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(urlMonitor.urls, id: \.self) { url in
                        URLStatusRow(url: url, status: urlMonitor.statuses[url])
                        Divider().background(Color.white.opacity(0.06))
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 240)
        .frame(maxHeight: .infinity)
        .background(Color.white.opacity(0.04))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundStyle(Color.white.opacity(0.08)),
            alignment: .leading
        )
    }

    @ViewBuilder
    private var content: some View {
        let hasData = usageService.snapshot.session != nil
            || usageService.snapshot.weekly != nil
            || usageService.snapshot.fable != nil

        ScrollView {
            VStack(spacing: 20) {
                header

                if hasData {
                    HStack(spacing: 14) {
                        if let session = usageService.snapshot.session {
                            KPICard(title: "Session (5h)", limit: session)
                        }
                        if let weekly = usageService.snapshot.weekly {
                            KPICard(title: "Hebdo (tous modèles)", limit: weekly)
                        }
                        if let fable = usageService.snapshot.fable {
                            KPICard(title: "Fable (hebdo)", limit: fable)
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    emptyState
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            statusLine
                .font(.system(size: 19, weight: .semibold))

            Spacer()

            if !gitWatcher.dirtyRepos.isEmpty {
                gitSidebarToggle
            }

            updateCenterButton

            if !urlMonitor.urls.isEmpty {
                urlSidebarToggle
            }

            refreshButton
        }
        .padding(.horizontal, 20)
    }

    private var gitSidebarToggle: some View {
        Button {
            showingGitSidebar.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                Text("\(gitWatcher.dirtyRepos.count)")
                    .font(.system(size: 13, weight: .bold))
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.2))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(showingGitSidebar ? "Masquer les projets non commités" : "Afficher les projets non commités")
    }

    private var updateCenterButton: some View {
        Button {
            updateProjects = UpdateScriptScanner.scan(root: Self.workspaceRoot)
            showingUpdateCenter = true
        } label: {
            Image(systemName: "terminal.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Scripts de mise à jour")
    }

    private var urlSidebarToggle: some View {
        let downCount = urlMonitor.urls.filter { urlMonitor.statuses[$0]?.isDown == true }.count

        return Button {
            showingURLSidebar.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                Text("\(urlMonitor.urls.count)")
                    .font(.system(size: 13, weight: .bold))
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background((downCount == 0 ? Color.green : Color.red).opacity(0.2))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(showingURLSidebar ? "Masquer les health checks" : "Afficher les health checks")
    }

    private func triggerRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            async let usage: Void = usageService.refresh()
            async let urls: Void = urlMonitor.checkAll()
            async let git: Void = gitWatcher.check()
            _ = await (usage, urls, git)
            isRefreshing = false
        }
    }

    private var refreshButton: some View {
        Button {
            triggerRefresh()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16, weight: .semibold))
                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                .foregroundStyle(.white)
                .padding(10)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .help("Rafraîchir maintenant (barre d'espace)")
    }

    @ViewBuilder
    private var statusLine: some View {
        switch usageService.snapshot.errorState {
        case .unauthorized:
            Label("Session expirée — reconfigure la commande cURL", systemImage: "lock.fill")
                .foregroundStyle(.orange)
        case .networkError:
            Label("Erreur réseau — nouvelle tentative dans quelques secondes", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .needsConfig, .none:
            if let last = usageService.snapshot.lastUpdated {
                Text("Mis à jour à \(last.formatted(date: .omitted, time: .standard))")
                    .foregroundStyle(.gray)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("Aucune donnée pour l'instant")
                .foregroundStyle(.white)
            Button("Configurer") { showingSetup = true }
        }
        .padding(.top, 60)
    }
}

private struct KPICard: View {
    let title: String
    let limit: LimitDisplay

    private var color: Color {
        guard let pace = limit.pace else { return .blue }
        if pace.delta > PaceCalculator.paceTolerance { return .red }
        if pace.delta < -PaceCalculator.paceTolerance { return .green }
        return .blue
    }

    private var rhythmText: String {
        guard let pace = limit.pace else { return "Rythme inconnu" }
        if pace.delta > PaceCalculator.paceTolerance {
            return "En avance de \(Int(pace.delta.rounded()))pts"
        } else if pace.delta < -PaceCalculator.paceTolerance {
            return "En retard de \(Int(abs(pace.delta).rounded()))pts"
        }
        return "Dans le rythme"
    }

    private var rhythmIcon: String {
        guard let pace = limit.pace else { return "questionmark.circle.fill" }
        if pace.delta > PaceCalculator.paceTolerance { return "arrow.up.circle.fill" }
        if pace.delta < -PaceCalculator.paceTolerance { return "arrow.down.circle.fill" }
        return "arrow.right.circle.fill"
    }

    private var projectionText: String {
        guard let pace = limit.pace else { return "—" }
        return pace.projectedPercent < 999 ? "\(Int(pace.projectedPercent.rounded()))%" : ">999%"
    }

    private var budgetText: String {
        guard let pace = limit.pace else { return "—" }
        return String(format: "%.1f%%/h", pace.hourlyBudget)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Image(systemName: rhythmIcon)
                    Text(rhythmText)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(color.opacity(0.15))
                .clipShape(Capsule())
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: min(limit.percent / 100, 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(limit.formattedPercent)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 160, height: 160)

            VStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(PaceCalculator.formatCountdown(limit.resetsAt, now: context.date))
                        .font(.system(size: 44, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }

                Text(PaceCalculator.formatAbsoluteReset(limit.resetsAt))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            Divider()
                .background(Color.white.opacity(0.1))

            VStack(spacing: 12) {
                PaceDetailRow(icon: "chart.line.uptrend.xyaxis", label: "Projection à l'échéance", value: projectionText)
                PaceDetailRow(icon: "bolt.fill", label: "Budget restant", value: budgetText)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct PaceDetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 18)
            Text(label)
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Text(value)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

private struct URLStatusRow: View {
    let url: String
    let status: MonitoredURLStatus?

    private var dotColor: Color {
        guard let status else { return .gray }
        return status.isDown ? .red : .green
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 8) {
                    Text(status?.title ?? url)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(url)

                    Spacer()

                    Circle()
                        .fill(dotColor)
                        .frame(width: 10, height: 10)
                }

                if status?.title != nil {
                    Text(url)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let lastCheck = status?.lastCheck {
                    HStack(alignment: .top, spacing: 8) {
                        Text(lastCheck.formatted(date: .numeric, time: .standard))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)

                        Spacer()

                        Text(Self.relativeText(since: lastCheck, now: context.date))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    Text("en attente…")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private static func relativeText(since date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "il y a \(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "il y a \(minutes) min" }
        let hours = minutes / 60
        return "il y a \(hours) h"
    }
}

private struct GitRepoRow: View {
    let repo: DirtyRepo
    let isPushing: Bool
    let pushResult: PushResult?
    let onPush: () -> Void

    private var isPushable: Bool {
        !repo.hasUncommittedChanges && repo.hasUnpushedCommits
    }

    private var helpText: String {
        if isPushing { return "Push en cours…" }
        if case .failure(let message) = pushResult { return message }
        if isPushable { return "Cliquer pour pousser vers GitHub" }
        return "Modifications non commitées — rien à pousser"
    }

    var body: some View {
        Button(action: onPush) {
            HStack(spacing: 10) {
                ZStack {
                    if isPushing {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Circle()
                            .fill(repo.hasUncommittedChanges ? Color.red : Color.orange)
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(width: 10, height: 10)

                Text(repo.id)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if !isPushing {
                    if case .failure = pushResult {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    } else if isPushable {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isPushable || isPushing)
        .help(helpText)
    }
}

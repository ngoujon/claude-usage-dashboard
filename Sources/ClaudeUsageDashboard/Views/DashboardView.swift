import SwiftUI

struct DashboardView: View {
    @ObservedObject var usageService: UsageService
    @ObservedObject var urlMonitor: URLMonitor
    @State private var showingSetup = false
    @State private var isRefreshing = false
    @State private var showingURLSidebar = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            HStack(spacing: 0) {
                content
                if showingURLSidebar && !urlMonitor.urls.isEmpty {
                    urlSidebar
                        .transition(.move(edge: .trailing))
                }
            }
        }
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

    private var urlSidebar: some View {
        let downCount = urlMonitor.urls.filter { urlMonitor.statuses[$0]?.isDown == true }.count

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(downCount == 0 ? .green : .red)
                Text("Health checks")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if downCount > 0 {
                    Text("\(downCount)")
                        .font(.system(size: 15, weight: .bold))
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
        .frame(width: 210)
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
            VStack(spacing: 12) {
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
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            statusLine
                .font(.system(size: 21, weight: .semibold))

            Spacer()

            if !urlMonitor.urls.isEmpty {
                urlSidebarToggle
            }

            refreshButton
        }
        .padding(.horizontal, 20)
    }

    private var urlSidebarToggle: some View {
        let downCount = urlMonitor.urls.filter { urlMonitor.statuses[$0]?.isDown == true }.count

        return Button {
            showingURLSidebar.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                Text("\(urlMonitor.urls.count)")
                    .font(.system(size: 15, weight: .bold))
            }
            .font(.system(size: 17, weight: .semibold))
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
            _ = await (usage, urls)
            isRefreshing = false
        }
    }

    private var refreshButton: some View {
        Button {
            triggerRefresh()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 18, weight: .semibold))
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

    /// Only meaningful while the projection is ahead of pace (>= 101%); "N/A" otherwise.
    private var pauseText: String {
        guard let pace = limit.pace, pace.projectedPercent >= PaceCalculator.aheadProjectionThreshold else { return "N/A" }
        return PaceCalculator.formatDuration(pace.pauseNeeded)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Image(systemName: rhythmIcon)
                    Text(rhythmText)
                }
                .font(.system(size: 15, weight: .semibold))
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
                    .stroke(Color.white.opacity(0.1), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: min(limit.percent / 100, 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(limit.formattedPercent)
                    .font(.system(size: 39, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 136, height: 136)

            VStack(spacing: 4) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(PaceCalculator.formatCountdown(limit.resetsAt, now: context.date))
                        .font(.system(size: 37, weight: .bold, design: .monospaced))
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

            VStack(spacing: 8) {
                PaceDetailRow(icon: "chart.line.uptrend.xyaxis", label: "Projection à l'échéance", value: projectionText)
                PaceDetailRow(icon: "bolt.fill", label: "Budget restant", value: budgetText)
                PaceDetailRow(icon: "pause.circle.fill", label: "Pause pour revenir dans le rythme", value: pauseText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18))
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
                .frame(width: 16)
            Text(label)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Text(value)
                .font(.system(size: 18, weight: .semibold))
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
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(url)

                    Spacer()

                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                        .help(downSinceHelpText(now: context.date))
                }

                if status?.title != nil {
                    Text(url)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let lastCheck = status?.lastCheck {
                    HStack(alignment: .top, spacing: 8) {
                        Text(lastCheck.formatted(date: .numeric, time: .standard))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)

                        Spacer()

                        Text(Self.relativeText(since: lastCheck, now: context.date))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    Text("en attente…")
                        .font(.system(size: 13))
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

    private func downSinceHelpText(now: Date) -> String {
        guard status?.isDown == true else { return "En ligne" }
        guard let downSince = status?.downSince else { return "Hors ligne" }
        return "Hors ligne depuis \(Self.durationText(since: downSince, now: now))"
    }

    private static func durationText(since date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "\(seconds) s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h" }
        let days = hours / 24
        let remainingHours = hours % 24
        if remainingHours == 0 { return "\(days) j" }
        return "\(days) j \(remainingHours) h"
    }
}

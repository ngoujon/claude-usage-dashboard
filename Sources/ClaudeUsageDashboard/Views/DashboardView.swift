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
                    VStack(spacing: 6) {
                        KPIHeaderRow(showingResetAndProjection: !showingURLSidebar)
                        VStack(spacing: 10) {
                            if let session = usageService.snapshot.session {
                                KPIRow(title: "Session", limit: session, showingResetAndProjection: !showingURLSidebar)
                            }
                            if let weekly = usageService.snapshot.weekly {
                                KPIRow(title: "Hebdo", limit: weekly, showingResetAndProjection: !showingURLSidebar)
                            }
                            if let fable = usageService.snapshot.fable {
                                KPIRow(title: "Fable", limit: fable, showingResetAndProjection: !showingURLSidebar)
                            }
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

private enum KPIColumn {
    static let title: CGFloat = 150
    static let usage: CGFloat = 80 + 8 + 150
    static let rhythm: CGFloat = 170
    static let reset: CGFloat = 200
    static let projection: CGFloat = 110
}

private struct KPIHeaderRow: View {
    let showingResetAndProjection: Bool

    var body: some View {
        HStack(spacing: 16) {
            Text("").frame(width: KPIColumn.title, alignment: .leading)
            Text("Utilisation").frame(width: KPIColumn.usage, alignment: .center)
            Text("Rythme").frame(width: KPIColumn.rhythm, alignment: .center)
            if showingResetAndProjection {
                Text("Reset").frame(width: KPIColumn.reset, alignment: .center)
                Text("Projection").frame(width: KPIColumn.projection, alignment: .center)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white.opacity(0.4))
        .textCase(.uppercase)
        .padding(.horizontal, 16 + 16)
    }
}

private struct KPIRow: View {
    let title: String
    let limit: LimitDisplay
    let showingResetAndProjection: Bool

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

    private let progressBarWidth: CGFloat = 150

    private var projectionText: String {
        guard let pace = limit.pace else { return "—" }
        return pace.projectedPercent < 999 ? "\(Int(pace.projectedPercent.rounded()))%" : ">999%"
    }

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.gray)
                .lineLimit(1)
                .frame(width: KPIColumn.title, alignment: .leading)

            HStack(spacing: 8) {
                Text(limit.formattedPercent)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 80, alignment: .leading)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: progressBarWidth)
                    Capsule()
                        .fill(color)
                        .frame(width: progressBarWidth * min(limit.percent / 100, 1))
                }
                .frame(width: progressBarWidth, height: 8)
            }
            .frame(width: KPIColumn.usage, alignment: .leading)

            HStack(spacing: 5) {
                Image(systemName: rhythmIcon)
                Text(rhythmText)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: KPIColumn.rhythm, alignment: .leading)

            if showingResetAndProjection {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PaceCalculator.formatCountdown(limit.resetsAt, now: context.date))
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(PaceCalculator.formatAbsoluteReset(limit.resetsAt))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                .frame(width: KPIColumn.reset, alignment: .leading)

                Text(projectionText)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: KPIColumn.projection, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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

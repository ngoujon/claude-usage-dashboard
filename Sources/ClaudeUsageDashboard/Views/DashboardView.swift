import SwiftUI

struct DashboardView: View {
    @ObservedObject var usageService: UsageService
    @State private var showingSetup = false
    @State private var isRefreshing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
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

    @ViewBuilder
    private var content: some View {
        let hasData = usageService.snapshot.session != nil
            || usageService.snapshot.weekly != nil
            || usageService.snapshot.fable != nil

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

            Spacer()
        }
        .padding(.top, 20)
    }

    private var header: some View {
        VStack(spacing: 6) {
            ZStack {
                Text("Suivi des quotas Claude")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                HStack {
                    Spacer()
                    refreshButton
                        .padding(.trailing, 40)
                }
            }
            statusLine
        }
    }

    private func triggerRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await usageService.refresh()
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
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.gray)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

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
                Text("RESET DANS  (JJ:HH:MM:SS)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(PaceCalculator.formatCountdown(limit.resetsAt, now: context.date))
                        .font(.system(size: 44, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }

                Text(PaceCalculator.formatAbsoluteReset(limit.resetsAt))
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Divider()
                .background(Color.white.opacity(0.1))

            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: rhythmIcon)
                    Text(rhythmText)
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(color.opacity(0.15))
                .clipShape(Capsule())

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
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 16)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

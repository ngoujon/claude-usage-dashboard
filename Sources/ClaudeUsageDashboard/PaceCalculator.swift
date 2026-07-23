import Foundation

enum PaceCalculator {
    static let sessionPeriod: TimeInterval = 5 * 3600
    static let weeklyPeriod: TimeInterval = 7 * 24 * 3600
    static let paceTolerance: Double = 5
    /// Projection thresholds for the pause-needed estimate: ahead of pace at/above 101%,
    /// "dans le rythme" between 90% and 100%.
    static let aheadProjectionThreshold: Double = 101
    static let onPaceProjectionTarget: Double = 100

    static func parseISODate(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: iso) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: iso)
    }

    static func findLimit(_ limits: [RawLimit], kind: String, modelName: String? = nil) -> RawLimit? {
        for limit in limits where limit.kind == kind {
            guard let modelName else { return limit }
            if limit.scope?.model?.displayName == modelName { return limit }
        }
        return nil
    }

    static func paceStatus(percent: Double, resetsAt: Date?, period: TimeInterval) -> PaceInfo? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSinceNow
        guard remaining > 0 else { return nil }
        let elapsed = period - remaining
        guard elapsed >= 60 else { return nil }

        let expectedPercent = elapsed / period * 100
        let projectedPercent = percent * period / elapsed
        let remainingHours = remaining / 3600
        let hourlyBudget = remainingHours > 0 ? max(0, 100 - percent) / remainingHours : 0

        // Elapsed time (within the period) at which projectedPercent would fall back to
        // onPaceProjectionTarget (100%) if no new usage happens — i.e. how long a pause
        // needs to last, starting now, to no longer be projected to overshoot.
        let elapsedNeeded = percent * period / onPaceProjectionTarget
        let pauseNeeded = max(0, elapsedNeeded - elapsed)

        return PaceInfo(
            delta: percent - expectedPercent,
            projectedPercent: projectedPercent,
            hourlyBudget: hourlyBudget,
            pauseNeeded: pauseNeeded
        )
    }

    static func paceArrow(_ pace: PaceInfo?) -> String {
        guard let pace else { return "" }
        if pace.delta > paceTolerance { return "↑" }
        if pace.delta < -paceTolerance { return "↓" }
        return "→"
    }

    static func formatPace(_ pace: PaceInfo?) -> String {
        guard let pace else { return "pas assez de recul pour estimer le rythme" }
        let rhythm: String
        if pace.delta > paceTolerance {
            rhythm = "en avance de \(Int(pace.delta.rounded()))pts"
        } else if pace.delta < -paceTolerance {
            rhythm = "en retard de \(Int(abs(pace.delta).rounded()))pts"
        } else {
            rhythm = "dans le rythme"
        }
        let projectedStr = pace.projectedPercent < 999 ? "\(Int(pace.projectedPercent.rounded()))%" : ">999%"
        let budgetStr = String(format: "%.1f", pace.hourlyBudget)
        return "\(rhythm) · projection \(projectedStr) à l'échéance · budget \(budgetStr)%/h"
    }

    static func formatCountdown(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—:—:—:—" }
        let delta = date.timeIntervalSince(now)
        if delta <= 0 { return "00:00:00:00" }
        let total = Int(delta)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d:%02d", days, hours, minutes, seconds)
    }

    static func formatAbsoluteReset(_ date: Date?) -> String {
        guard let date else { return "pas encore utilisé" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM 'à' HH:mm"
        return formatter.string(from: date).prefix(1).capitalized + formatter.string(from: date).dropFirst()
    }

    static func formatRemainingCompact(_ date: Date?) -> String {
        guard let date else { return "—" }
        let delta = date.timeIntervalSinceNow
        if delta <= 0 { return "reset…" }
        let totalMin = Int(delta / 60)
        let days = totalMin / 1440
        let rem = totalMin % 1440
        let hours = rem / 60
        let minutes = rem % 60

        if days > 0 { return "\(days)j\(hours)h" }
        if hours > 0 { return "\(hours)h\(String(format: "%02d", minutes))" }
        return "\(minutes)min"
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "0min" }
        let totalMin = max(1, Int(seconds / 60))
        let days = totalMin / 1440
        let rem = totalMin % 1440
        let hours = rem / 60
        let minutes = rem % 60

        if days > 0 { return "\(days)j\(hours)h" }
        if hours > 0 { return "\(hours)h\(String(format: "%02d", minutes))" }
        return "\(minutes)min"
    }
}

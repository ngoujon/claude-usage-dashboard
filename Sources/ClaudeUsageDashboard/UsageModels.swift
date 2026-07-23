import Foundation

struct UsageResponse: Decodable {
    let limits: [RawLimit]
}

struct RawLimit: Decodable {
    let kind: String
    let percent: Double
    let resetsAt: String?
    let scope: Scope?

    enum CodingKeys: String, CodingKey {
        case kind, percent
        case resetsAt = "resets_at"
        case scope
    }

    struct Scope: Decodable {
        let model: ModelScope?
    }

    struct ModelScope: Decodable {
        let displayName: String?
        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }
}

struct PaceInfo {
    let delta: Double
    let projectedPercent: Double
    let hourlyBudget: Double
    /// Time without any new usage needed to bring `delta` back down to the pace tolerance.
    let pauseNeeded: TimeInterval
}

struct LimitDisplay {
    let percent: Double
    let resetsAt: Date?
    let pace: PaceInfo?

    var formattedPercent: String {
        if percent.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(percent))%"
        }
        return String(format: "%.1f%%", percent)
    }
}

struct UsageSnapshot {
    var session: LimitDisplay?
    var weekly: LimitDisplay?
    var fable: LimitDisplay?
    var lastUpdated: Date?
    var errorState: ErrorState = .needsConfig

    enum ErrorState: Equatable {
        case none
        case needsConfig
        case unauthorized
        case networkError
    }
}

import CodexBarCore
import Foundation

enum TeamReportInterval: String, CaseIterable, Codable, Sendable, Identifiable {
    case automatic
    case oneMinute
    case twoMinutes
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes

    var id: String {
        self.rawValue
    }

    var label: String {
        switch self {
        case .automatic: "Auto"
        case .oneMinute: "1 min"
        case .twoMinutes: "2 min"
        case .fiveMinutes: "5 min"
        case .fifteenMinutes: "15 min"
        case .thirtyMinutes: "30 min"
        }
    }

    func resolvedSeconds(refreshFrequency: RefreshFrequency) -> TimeInterval {
        switch self {
        case .automatic:
            let refreshSeconds = refreshFrequency.seconds ?? RefreshFrequency.fiveMinutes.seconds ?? 300
            return max(300, refreshSeconds)
        case .oneMinute:
            return 60
        case .twoMinutes:
            return 120
        case .fiveMinutes:
            return 300
        case .fifteenMinutes:
            return 900
        case .thirtyMinutes:
            return 1800
        }
    }

    static func fromRecommendedSeconds(_ seconds: Int?) -> TeamReportInterval {
        guard let seconds, seconds > 0 else { return .automatic }
        let options: [(TeamReportInterval, Int)] = [
            (.oneMinute, 60),
            (.twoMinutes, 120),
            (.fiveMinutes, 300),
            (.fifteenMinutes, 900),
            (.thirtyMinutes, 1800),
        ]
        let closest = options.min { lhs, rhs in
            abs(lhs.1 - seconds) < abs(rhs.1 - seconds)
        }
        return closest?.0 ?? .automatic
    }
}

enum TeamReportResult: String, Codable, Sendable {
    case ok
    case throttled
    case authFailed
    case serverError
    case networkError
}

struct TeamReportingSettings: Codable, Sendable, Equatable {
    var serverBaseURL: URL
    var enabled: Bool
    var teamId: String?
    var teamName: String?
    var memberPublicId: String?
    var deviceId: String?
    var deviceLabel: String
    var reportInterval: TeamReportInterval
    var lastReportAt: Date?
    var lastReportResult: TeamReportResult?
    var lastReportErrorMessage: String?
    var tokenLast4: String?
    var claimCode: String?
    var claimExpiresAt: String?
    var claimPage: String?

    init(
        serverBaseURL: URL = TeamAPIConstants.defaultServerBaseURL,
        enabled: Bool = false,
        teamId: String? = nil,
        teamName: String? = nil,
        memberPublicId: String? = nil,
        deviceId: String? = nil,
        deviceLabel: String = Self.defaultDeviceLabel(),
        reportInterval: TeamReportInterval = .automatic,
        lastReportAt: Date? = nil,
        lastReportResult: TeamReportResult? = nil,
        lastReportErrorMessage: String? = nil,
        tokenLast4: String? = nil,
        claimCode: String? = nil,
        claimExpiresAt: String? = nil,
        claimPage: String? = nil)
    {
        self.serverBaseURL = serverBaseURL
        self.enabled = enabled
        self.teamId = teamId
        self.teamName = teamName
        self.memberPublicId = memberPublicId
        self.deviceId = deviceId
        self.deviceLabel = deviceLabel
        self.reportInterval = reportInterval
        self.lastReportAt = lastReportAt
        self.lastReportResult = lastReportResult
        self.lastReportErrorMessage = lastReportErrorMessage
        self.tokenLast4 = tokenLast4
        self.claimCode = claimCode
        self.claimExpiresAt = claimExpiresAt
        self.claimPage = claimPage
    }

    var isJoined: Bool {
        if let teamId, !teamId.isEmpty,
           let deviceId, !deviceId.isEmpty
        {
            return true
        }
        return false
    }

    mutating func clearMembershipKeepingPreferences() {
        self.enabled = false
        self.teamId = nil
        self.teamName = nil
        self.memberPublicId = nil
        self.deviceId = nil
        self.lastReportAt = nil
        self.lastReportResult = nil
        self.lastReportErrorMessage = nil
        self.tokenLast4 = nil
        self.claimCode = nil
        self.claimExpiresAt = nil
        self.claimPage = nil
    }

    static func defaultValue() -> TeamReportingSettings {
        TeamReportingSettings()
    }

    static func defaultDeviceLabel() -> String {
        let host = ProcessInfo.processInfo.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty {
            return "Mac"
        }
        return host
    }
}

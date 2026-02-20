import CodexBarCore
import Foundation

enum TeamSettingsError: LocalizedError {
    case missingInviteCode
    case missingDeviceID
    case noTeamMembership
    case invalidServerURL
    case invalidReportingToken

    var errorDescription: String? {
        switch self {
        case .missingInviteCode:
            "Enter an invite code first."
        case .missingDeviceID:
            "Team response was missing a device ID."
        case .noTeamMembership:
            "Join a team first."
        case .invalidServerURL:
            "Team server URL is invalid."
        case .invalidReportingToken:
            "Team server returned an invalid reporting token."
        }
    }
}

extension SettingsStore {
    struct TeamJoinResult: Sendable {
        let teamName: String
        let memberPublicID: String
        let deviceID: String
    }

    func joinTeam(inviteCode: String) async throws -> TeamJoinResult {
        let trimmedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { throw TeamSettingsError.missingInviteCode }

        var current = self.teamReportingSettings
        let deviceLabel = current.deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if deviceLabel.isEmpty {
            current.deviceLabel = TeamReportingSettings.defaultDeviceLabel()
        }

        guard let scheme = current.serverBaseURL.scheme,
              scheme == "https" || scheme == "http"
        else {
            throw TeamSettingsError.invalidServerURL
        }

        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let payload = TeamRedeemInviteRequest(
            inviteCode: trimmedCode,
            deviceLabel: current.deviceLabel,
            platform: "macos",
            appVersion: appVersion)
        let response = try await self.teamAPIClient.redeemInvite(baseURL: current.serverBaseURL, payload: payload)

        let deviceID = response.device.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deviceID.isEmpty else { throw TeamSettingsError.missingDeviceID }
        let reportingToken = response.deviceToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reportingToken.isEmpty else { throw TeamSettingsError.invalidReportingToken }

        try self.teamDeviceTokenStore.storeToken(reportingToken, deviceID: deviceID)

        current.enabled = true
        current.teamId = response.team.id
        current.teamName = response.team.name
        current.memberPublicId = response.member.publicID
        current.deviceId = deviceID
        current.deviceLabel = response.device.deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? current.deviceLabel
            : response.device.deviceLabel
        if response.reporting?.recommendedIntervalSeconds != nil {
            current.reportInterval = TeamReportInterval
                .fromRecommendedSeconds(response.reporting?.recommendedIntervalSeconds)
        }
        current.lastReportAt = nil
        current.lastReportResult = nil
        current.lastReportErrorMessage = nil
        current.tokenLast4 = String(reportingToken.suffix(4))
        current.claimCode = response.claim?.claimCode
        current.claimExpiresAt = response.claim?.expiresAt
        current.claimPage = response.claim?.claimPage
        self.teamReportingSettings = current

        CodexBarLog.logger(LogCategories.team).info(
            "Joined team",
            metadata: [
                "teamID": response.team.id,
                "deviceID": deviceID,
            ])

        return TeamJoinResult(
            teamName: response.team.name,
            memberPublicID: response.member.publicID,
            deviceID: deviceID)
    }

    func leaveTeam() {
        let current = self.teamReportingSettings
        if let deviceID = current.deviceId, !deviceID.isEmpty {
            do {
                try self.teamDeviceTokenStore.storeToken(nil, deviceID: deviceID)
            } catch {
                CodexBarLog.logger(LogCategories.team).warning(
                    "Failed to clear team token",
                    metadata: [
                        "deviceID": deviceID,
                        "error": error.localizedDescription,
                    ])
            }
        }

        var updated = current
        updated.clearMembershipKeepingPreferences()
        self.teamReportingSettings = updated
        CodexBarLog.logger(LogCategories.team).info("Left team")
    }

    func loadTeamDeviceToken() -> String? {
        guard let deviceID = self.teamReportingSettings.deviceId,
              !deviceID.isEmpty
        else {
            return nil
        }
        do {
            return try self.teamDeviceTokenStore.loadToken(deviceID: deviceID)
        } catch {
            CodexBarLog.logger(LogCategories.team).warning(
                "Failed to load team token",
                metadata: [
                    "deviceID": deviceID,
                    "error": error.localizedDescription,
                ])
            return nil
        }
    }

    func setTeamReportStatus(
        result: TeamReportResult,
        at date: Date?,
        message: String?,
        disableReporting: Bool)
    {
        self.updateTeamReportingSettings { settings in
            settings.lastReportResult = result
            settings.lastReportAt = date
            settings.lastReportErrorMessage = message
            if disableReporting {
                settings.enabled = false
            }
        }
    }

    func updateTeamReportingSettings(_ update: (inout TeamReportingSettings) -> Void) {
        var current = self.teamReportingSettings
        update(&current)
        self.teamReportingSettings = current
    }

    func teamDashboardURL() -> URL? {
        let settings = self.teamReportingSettings
        guard let scheme = settings.serverBaseURL.scheme,
              scheme == "https" || scheme == "http"
        else {
            return nil
        }
        guard let teamID = settings.teamId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !teamID.isEmpty
        else {
            return settings.serverBaseURL
        }
        return settings.serverBaseURL
            .appendingPathComponent("app")
            .appendingPathComponent("teams")
            .appendingPathComponent(teamID)
    }

    func teamClaimURL() -> URL? {
        let settings = self.teamReportingSettings
        guard let claimPage = settings.claimPage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !claimPage.isEmpty
        else {
            return nil
        }

        if let absoluteURL = URL(string: claimPage), absoluteURL.scheme != nil {
            return absoluteURL
        }

        let trimmedPath = claimPage.hasPrefix("/") ? String(claimPage.dropFirst()) : claimPage
        return settings.serverBaseURL.appendingPathComponent(trimmedPath)
    }
}

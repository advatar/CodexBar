import CodexBarCore
import Foundation

@MainActor
final class TeamReporter {
    private let logger = CodexBarLog.logger(LogCategories.team)
    private let appVersion: String
    private let minBackoffSeconds: TimeInterval = 60
    private let maxBackoffSeconds: TimeInterval = 30 * 60

    private var isReporting = false
    private var failureCount = 0
    private var nextAllowedAttemptAt: Date?

    init(appVersion: String = Bundle.main
        .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")
    {
        self.appVersion = appVersion
    }

    func maybeReport(store: UsageStore, force: Bool = false) async {
        if self.isReporting {
            return
        }

        let teamSettings = store.settings.teamReportingSettings
        guard teamSettings.enabled else { return }
        guard teamSettings.isJoined else { return }
        guard let deviceID = teamSettings.deviceId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !deviceID.isEmpty
        else {
            return
        }

        guard let token = store.settings.loadTeamDeviceToken(),
              !token.isEmpty
        else {
            store.settings.setTeamReportStatus(
                result: .authFailed,
                at: nil,
                message: "Team token missing. Join the team again.",
                disableReporting: true)
            return
        }

        let now = Date()
        if !force {
            if let nextAllowedAttemptAt, now < nextAllowedAttemptAt {
                return
            }
            let interval = teamSettings.reportInterval
                .resolvedSeconds(refreshFrequency: store.settings.refreshFrequency)
            if let lastReportAt = teamSettings.lastReportAt,
               now.timeIntervalSince(lastReportAt) < interval
            {
                return
            }
        }

        let cadenceSeconds = Int(teamSettings.reportInterval
            .resolvedSeconds(refreshFrequency: store.settings.refreshFrequency))
        let buildInput = TeamReportBuilder.BuildInput(
            snapshots: store.snapshots,
            tokenSnapshots: store.tokenSnapshots,
            sourceLabels: store.lastSourceLabels,
            versions: store.versions,
            statuses: self.teamStatuses(store: store, fallbackDate: now),
            creditsByProvider: self.creditsByProvider(store: store),
            openAIDashboardByProvider: self.openAIDashboardByProvider(store: store),
            appVersion: self.appVersion,
            refreshCadenceSeconds: cadenceSeconds)
        guard let payload = TeamReportBuilder.build(buildInput)
        else {
            return
        }

        let payloadData: Data
        do {
            payloadData = try TeamReportSanitizer.sanitizePayload(payload)
        } catch {
            self.applyFailure(
                store: store,
                result: .serverError,
                message: "Failed to prepare team report payload.",
                retryAfterSeconds: nil,
                disableReporting: false)
            self.logger.warning("Team payload sanitize failed", metadata: ["error": error.localizedDescription])
            return
        }

        self.isReporting = true
        defer {
            self.isReporting = false
        }

        do {
            let result = try await store.settings.teamAPIClient.reportUsage(
                baseURL: teamSettings.serverBaseURL,
                bearerToken: token,
                deviceID: deviceID,
                payloadData: payloadData)
            switch result {
            case .ok, .duplicate:
                self.failureCount = 0
                self.nextAllowedAttemptAt = nil
                store.settings.setTeamReportStatus(
                    result: .ok,
                    at: now,
                    message: nil,
                    disableReporting: false)
            }
        } catch let error as TeamAPIClientError {
            switch error {
            case .unauthorized:
                self.applyFailure(
                    store: store,
                    result: .authFailed,
                    message: error.errorDescription,
                    retryAfterSeconds: nil,
                    disableReporting: true)
            case let .throttled(retryAfterSeconds):
                self.applyFailure(
                    store: store,
                    result: .throttled,
                    message: error.errorDescription,
                    retryAfterSeconds: retryAfterSeconds,
                    disableReporting: false)
            case .serverStatus, .decodingFailed, .invalidResponse:
                self.applyFailure(
                    store: store,
                    result: .serverError,
                    message: error.errorDescription,
                    retryAfterSeconds: nil,
                    disableReporting: false)
            }
        } catch {
            self.applyFailure(
                store: store,
                result: .networkError,
                message: error.localizedDescription,
                retryAfterSeconds: nil,
                disableReporting: false)
        }
    }
}

extension TeamReporter {
    private func teamStatuses(
        store: UsageStore,
        fallbackDate: Date) -> [UsageProvider: TeamUsageReportPayload.ProviderSnapshot.Status]
    {
        var statuses: [UsageProvider: TeamUsageReportPayload.ProviderSnapshot.Status] = [:]
        statuses.reserveCapacity(store.statuses.count)

        for (provider, status) in store.statuses {
            statuses[provider] = TeamUsageReportPayload.ProviderSnapshot.Status(
                indicator: self.teamStatusIndicator(status.indicator),
                description: status.description,
                updatedAt: status.updatedAt ?? fallbackDate,
                url: self.statusURL(for: provider, store: store))
        }

        return statuses
    }

    private func teamStatusIndicator(
        _ indicator: ProviderStatusIndicator) -> TeamUsageReportPayload.ProviderSnapshot.Status.Indicator
    {
        switch indicator {
        case .none:
            .none
        case .minor, .maintenance:
            .minor
        case .major, .critical:
            .major
        case .unknown:
            .unknown
        }
    }

    private func statusURL(for provider: UsageProvider, store: UsageStore) -> String? {
        guard let metadata = store.providerMetadata[provider] else { return nil }
        return metadata.statusPageURL ?? metadata.statusLinkURL
    }

    private func creditsByProvider(store: UsageStore) -> [UsageProvider: CreditsSnapshot] {
        guard let credits = store.credits else { return [:] }
        return [.codex: credits]
    }

    private func openAIDashboardByProvider(store: UsageStore) -> [UsageProvider: OpenAIDashboardSnapshot] {
        guard let dashboard = store.openAIDashboard else { return [:] }
        return [.codex: dashboard]
    }

    private func applyFailure(
        store: UsageStore,
        result: TeamReportResult,
        message: String?,
        retryAfterSeconds: TimeInterval?,
        disableReporting: Bool)
    {
        let now = Date()
        self.failureCount = min(self.failureCount + 1, 8)
        let backoffSeconds = self.nextBackoffSeconds(retryAfterSeconds: retryAfterSeconds)
        self.nextAllowedAttemptAt = now.addingTimeInterval(backoffSeconds)
        self.logger.warning(
            "Team report failed",
            metadata: [
                "result": result.rawValue,
                "backoffSeconds": "\(Int(backoffSeconds))",
                "disableReporting": disableReporting ? "1" : "0",
            ])
        store.settings.setTeamReportStatus(
            result: result,
            at: nil,
            message: message,
            disableReporting: disableReporting)
    }

    private func nextBackoffSeconds(retryAfterSeconds: TimeInterval?) -> TimeInterval {
        if let retryAfterSeconds {
            return min(max(retryAfterSeconds, self.minBackoffSeconds), self.maxBackoffSeconds)
        }
        let exponential = self.minBackoffSeconds * pow(2, Double(max(0, self.failureCount - 1)))
        return min(exponential, self.maxBackoffSeconds)
    }
}

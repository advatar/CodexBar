import CodexBarCore
import Foundation
import Testing

@Suite
struct TeamReportingSanitizerTests {
    @Test
    func sanitizerRemovesIdentityAndEmailKeys() throws {
        let raw = """
        {
          "provider": "codex",
          "usage": {
            "accountEmail": "user@example.com",
            "accountOrganization": "Acme",
            "loginMethod": "Team",
            "identity": { "accountEmail": "user@example.com" },
            "primary": { "usedPercent": 12.3 }
          },
          "openaiDashboard": {
            "signedInEmail": "user@example.com"
          }
        }
        """

        let sanitized = try TeamReportSanitizer.sanitizeJSONData(Data(raw.utf8))
        let text = String(data: sanitized, encoding: .utf8) ?? ""

        #expect(text.contains("accountEmail") == false)
        #expect(text.contains("accountOrganization") == false)
        #expect(text.contains("loginMethod") == false)
        #expect(text.contains("signedInEmail") == false)
        #expect(text.contains("identity") == false)
        #expect(TeamReportSanitizer.containsForbiddenKeys(data: sanitized) == false)
    }

    @Test
    func reportBuilderProducesV1PayloadAndOmitsIdentityFields() throws {
        let now = Date(timeIntervalSince1970: 1_739_000_000)
        let reportID = try #require(UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"))

        let usageSnapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 44.6, windowMinutes: 300, resetsAt: now, resetDescription: "resets soon"),
            secondary: nil,
            tertiary: nil,
            providerCost: ProviderCostSnapshot(
                used: 12.34,
                limit: 100,
                currencyCode: "USD",
                period: "Monthly",
                resetsAt: now,
                updatedAt: now),
            updatedAt: now,
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: "user@example.com",
                accountOrganization: "Acme",
                loginMethod: "Team"))

        let tokenSnapshot = CostUsageTokenSnapshot(
            sessionTokens: 123,
            sessionCostUSD: 1.23,
            last30DaysTokens: 456,
            last30DaysCostUSD: 4.56,
            daily: [
                CostUsageDailyReport.Entry(
                    date: "2025-02-13",
                    inputTokens: 100,
                    outputTokens: 50,
                    cacheReadTokens: 25,
                    cacheCreationTokens: 15,
                    totalTokens: nil,
                    costUSD: nil,
                    modelsUsed: ["gpt-4.1"],
                    modelBreakdowns: [
                        CostUsageDailyReport.ModelBreakdown(modelName: "gpt-4.1", costUSD: 3.45),
                    ]),
            ],
            updatedAt: now)

        let credits = try CreditsSnapshot(
            remaining: 98.7,
            events: [
                CreditEvent(
                    id: #require(UUID(uuidString: "11111111-2222-4333-8444-555555555555")),
                    date: now,
                    service: "Code review",
                    creditsUsed: 1.5),
            ],
            updatedAt: now)

        let dashboard = OpenAIDashboardSnapshot(
            signedInEmail: "user@example.com",
            codeReviewRemainingPercent: 67.2,
            creditEvents: credits.events,
            dailyBreakdown: [
                OpenAIDashboardDailyBreakdown(
                    day: "2025-02-13",
                    services: [OpenAIDashboardServiceUsage(service: "Code review", creditsUsed: 1.5)],
                    totalCreditsUsed: 1.5),
            ],
            usageBreakdown: [],
            creditsPurchaseURL: nil,
            primaryLimit: nil,
            secondaryLimit: nil,
            creditsRemaining: nil,
            accountPlan: nil,
            updatedAt: now)

        let buildInput = TeamReportBuilder.BuildInput(
            snapshots: [.codex: usageSnapshot],
            tokenSnapshots: [.codex: tokenSnapshot],
            sourceLabels: [.codex: "openai-web"],
            versions: [.codex: "0.17.0"],
            statuses: [
                .codex: TeamUsageReportPayload.ProviderSnapshot.Status(
                    indicator: .major,
                    description: "Operational issue",
                    updatedAt: now,
                    url: "https://status.openai.com/"),
            ],
            creditsByProvider: [.codex: credits],
            openAIDashboardByProvider: [.codex: dashboard],
            appVersion: "1.2.3",
            refreshCadenceSeconds: 300,
            reportID: reportID,
            generatedAt: now)
        let payload = TeamReportBuilder.build(buildInput)

        let unwrapped = try #require(payload)
        let sanitizedData = try TeamReportSanitizer.sanitizePayload(unwrapped)
        #expect(TeamReportSanitizer.containsForbiddenKeys(data: sanitizedData) == false)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TeamUsageReportPayload.self, from: sanitizedData)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.reportId == reportID.uuidString.lowercased())
        #expect(decoded.client.platform == .macos)
        #expect(decoded.client.appVersion == "1.2.3")
        #expect(decoded.client.refreshCadenceSeconds == 300)

        #expect(decoded.snapshots.count == 1)
        let snapshot = decoded.snapshots[0]
        #expect(snapshot.provider == "codex")
        #expect(snapshot.version == "0.17.0")
        #expect(snapshot.source == "openai-web")
        #expect(snapshot.status?.indicator == .major)
        #expect(snapshot.usage.primary.usedPercent == 45)
        #expect(snapshot.usage.primary.windowMinutes == 300)
        #expect(snapshot.credits?.remaining == 98.7)
        #expect(snapshot.extras?.openaiDashboard?.codeReviewRemainingPercent == 67)
        #expect(snapshot.extras?.openaiDashboard?.creditEvents?.count == 1)
        #expect(snapshot.extras?.openaiDashboard?.dailyBreakdown?.count == 1)

        #expect(decoded.cost?.count == 1)
        #expect(decoded.cost?[0].provider == "codex")
        #expect(decoded.cost?[0].source == "local")
        #expect(decoded.cost?[0].daily?.count == 1)
        #expect(decoded.cost?[0].daily?[0].totalTokens == 190)
        #expect(decoded.cost?[0].daily?[0].totalCost == 3.45)
        #expect(decoded.cost?[0].totals?.totalTokens == 456)
        #expect(decoded.cost?[0].totals?.totalCost == 4.56)
    }

    @Test
    func reportBuilderUsesSecondaryWindowWhenPrimaryMissing() throws {
        let now = Date(timeIntervalSince1970: 1_739_000_000)

        let usageSnapshot = UsageSnapshot(
            primary: nil,
            secondary: RateWindow(usedPercent: 12.2, windowMinutes: 60, resetsAt: now, resetDescription: nil),
            tertiary: nil,
            updatedAt: now,
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: "user@example.com",
                accountOrganization: nil,
                loginMethod: nil))

        let reportID = try #require(UUID(uuidString: "99999999-8888-4777-9666-555555555555"))
        let buildInput = TeamReportBuilder.BuildInput(
            snapshots: [.codex: usageSnapshot],
            tokenSnapshots: [:],
            sourceLabels: [:],
            versions: [:],
            statuses: [:],
            creditsByProvider: [:],
            openAIDashboardByProvider: [:],
            appVersion: "1.2.3",
            reportID: reportID,
            generatedAt: now)
        let payload = TeamReportBuilder.build(buildInput)

        let unwrapped = try #require(payload)
        let sanitizedData = try TeamReportSanitizer.sanitizePayload(unwrapped)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TeamUsageReportPayload.self, from: sanitizedData)

        #expect(decoded.snapshots.count == 1)
        #expect(decoded.snapshots[0].usage.primary.usedPercent == 12)
        #expect(decoded.snapshots[0].usage.secondary == nil)
        #expect(decoded.snapshots[0].usage.tertiary == nil)
    }
}

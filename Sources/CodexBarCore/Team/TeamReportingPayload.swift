import Foundation

public struct TeamUsageReportPayload: Codable, Sendable, Equatable {
    public struct Client: Codable, Sendable, Equatable {
        public enum Platform: String, Codable, Sendable {
            case macos
            case linux
            case windows
            case unknown
        }

        public let platform: Platform
        public let appVersion: String
        public let refreshCadenceSeconds: Int?

        public init(platform: Platform, appVersion: String, refreshCadenceSeconds: Int? = nil) {
            self.platform = platform
            self.appVersion = appVersion
            self.refreshCadenceSeconds = refreshCadenceSeconds
        }
    }

    public struct ProviderSnapshot: Codable, Sendable, Equatable {
        public struct Status: Codable, Sendable, Equatable {
            public enum Indicator: String, Codable, Sendable {
                case none
                case minor
                case major
                case unknown
            }

            public let indicator: Indicator
            public let description: String?
            public let updatedAt: Date
            public let url: String?

            public init(indicator: Indicator, description: String?, updatedAt: Date, url: String?) {
                self.indicator = indicator
                self.description = description
                self.updatedAt = updatedAt
                self.url = url
            }
        }

        public struct UsageSnapshot: Codable, Sendable, Equatable {
            public struct UsageWindow: Codable, Sendable, Equatable {
                public let usedPercent: Int
                public let windowMinutes: Int?
                public let resetsAt: Date?
                public let resetDescription: String?

                public init(
                    usedPercent: Int,
                    windowMinutes: Int?,
                    resetsAt: Date?,
                    resetDescription: String?)
                {
                    self.usedPercent = usedPercent
                    self.windowMinutes = windowMinutes
                    self.resetsAt = resetsAt
                    self.resetDescription = resetDescription
                }
            }

            public let primary: UsageWindow
            public let secondary: UsageWindow?
            public let tertiary: UsageWindow?
            public let updatedAt: Date

            public init(primary: UsageWindow, secondary: UsageWindow?, tertiary: UsageWindow?, updatedAt: Date) {
                self.primary = primary
                self.secondary = secondary
                self.tertiary = tertiary
                self.updatedAt = updatedAt
            }
        }

        public struct Credits: Codable, Sendable, Equatable {
            public let remaining: Double
            public let updatedAt: Date

            public init(remaining: Double, updatedAt: Date) {
                self.remaining = remaining
                self.updatedAt = updatedAt
            }
        }

        public struct Extras: Codable, Sendable, Equatable {
            public struct OpenAIDashboardExtras: Codable, Sendable, Equatable {
                public struct CreditEvent: Codable, Sendable, Equatable {
                    public let id: String
                    public let date: Date
                    public let service: String
                    public let creditsUsed: Double

                    public init(id: String, date: Date, service: String, creditsUsed: Double) {
                        self.id = id
                        self.date = date
                        self.service = service
                        self.creditsUsed = creditsUsed
                    }
                }

                public struct ServiceUsage: Codable, Sendable, Equatable {
                    public let service: String
                    public let creditsUsed: Double

                    public init(service: String, creditsUsed: Double) {
                        self.service = service
                        self.creditsUsed = creditsUsed
                    }
                }

                public struct DailyCreditBreakdown: Codable, Sendable, Equatable {
                    public let day: String
                    public let services: [ServiceUsage]
                    public let totalCreditsUsed: Double

                    public init(day: String, services: [ServiceUsage], totalCreditsUsed: Double) {
                        self.day = day
                        self.services = services
                        self.totalCreditsUsed = totalCreditsUsed
                    }
                }

                public let codeReviewRemainingPercent: Int?
                public let creditEvents: [CreditEvent]?
                public let dailyBreakdown: [DailyCreditBreakdown]?
                public let updatedAt: Date?

                public init(
                    codeReviewRemainingPercent: Int?,
                    creditEvents: [CreditEvent]?,
                    dailyBreakdown: [DailyCreditBreakdown]?,
                    updatedAt: Date?)
                {
                    self.codeReviewRemainingPercent = codeReviewRemainingPercent
                    self.creditEvents = creditEvents
                    self.dailyBreakdown = dailyBreakdown
                    self.updatedAt = updatedAt
                }
            }

            public let openaiDashboard: OpenAIDashboardExtras?

            public init(openaiDashboard: OpenAIDashboardExtras?) {
                self.openaiDashboard = openaiDashboard
            }
        }

        public let provider: String
        public let version: String?
        public let source: String
        public let status: Status?
        public let usage: UsageSnapshot
        public let credits: Credits?
        public let extras: Extras?

        public init(
            provider: String,
            version: String?,
            source: String,
            status: Status?,
            usage: UsageSnapshot,
            credits: Credits?,
            extras: Extras?)
        {
            self.provider = provider
            self.version = version
            self.source = source
            self.status = status
            self.usage = usage
            self.credits = credits
            self.extras = extras
        }
    }

    public struct CostPayload: Codable, Sendable, Equatable {
        public struct CountBreakdown: Codable, Sendable, Equatable {
            public let name: String
            public let count: Int

            public init(name: String, count: Int) {
                self.name = name
                self.count = count
            }
        }

        public struct Security: Codable, Sendable, Equatable {
            public let approvalPolicies: [CountBreakdown]?
            public let sandboxModes: [CountBreakdown]?
            public let riskySkills: [CountBreakdown]?
            public let forbiddenSkills: [CountBreakdown]?

            public init(
                approvalPolicies: [CountBreakdown]?,
                sandboxModes: [CountBreakdown]?,
                riskySkills: [CountBreakdown]?,
                forbiddenSkills: [CountBreakdown]?)
            {
                self.approvalPolicies = approvalPolicies
                self.sandboxModes = sandboxModes
                self.riskySkills = riskySkills
                self.forbiddenSkills = forbiddenSkills
            }
        }

        public struct Thinking: Codable, Sendable, Equatable {
            public let reasoningOutputTokens: Int?
            public let effortLevels: [CountBreakdown]?

            public init(reasoningOutputTokens: Int?, effortLevels: [CountBreakdown]?) {
                self.reasoningOutputTokens = reasoningOutputTokens
                self.effortLevels = effortLevels
            }
        }

        public struct ModelStats: Codable, Sendable, Equatable {
            public struct ModelUsage: Codable, Sendable, Equatable {
                public let modelName: String
                public let inputTokens: Int?
                public let outputTokens: Int?
                public let cacheReadTokens: Int?
                public let cacheCreationTokens: Int?
                public let reasoningOutputTokens: Int?
                public let totalTokens: Int
                public let totalCost: Double
                public let activeDays: Int

                public init(
                    modelName: String,
                    inputTokens: Int?,
                    outputTokens: Int?,
                    cacheReadTokens: Int?,
                    cacheCreationTokens: Int?,
                    reasoningOutputTokens: Int?,
                    totalTokens: Int,
                    totalCost: Double,
                    activeDays: Int)
                {
                    self.modelName = modelName
                    self.inputTokens = inputTokens
                    self.outputTokens = outputTokens
                    self.cacheReadTokens = cacheReadTokens
                    self.cacheCreationTokens = cacheCreationTokens
                    self.reasoningOutputTokens = reasoningOutputTokens
                    self.totalTokens = totalTokens
                    self.totalCost = totalCost
                    self.activeDays = activeDays
                }
            }

            public let modelsUsed: Int
            public let models: [ModelUsage]

            public init(modelsUsed: Int, models: [ModelUsage]) {
                self.modelsUsed = modelsUsed
                self.models = models
            }
        }

        public struct CostDailyEntry: Codable, Sendable, Equatable {
            public struct ModelBreakdown: Codable, Sendable, Equatable {
                public let modelName: String
                public let cost: Double
                public let inputTokens: Int?
                public let outputTokens: Int?
                public let cacheReadTokens: Int?
                public let cacheCreationTokens: Int?
                public let reasoningOutputTokens: Int?
                public let totalTokens: Int?

                public init(
                    modelName: String,
                    cost: Double,
                    inputTokens: Int?,
                    outputTokens: Int?,
                    cacheReadTokens: Int?,
                    cacheCreationTokens: Int?,
                    reasoningOutputTokens: Int?,
                    totalTokens: Int?)
                {
                    self.modelName = modelName
                    self.cost = cost
                    self.inputTokens = inputTokens
                    self.outputTokens = outputTokens
                    self.cacheReadTokens = cacheReadTokens
                    self.cacheCreationTokens = cacheCreationTokens
                    self.reasoningOutputTokens = reasoningOutputTokens
                    self.totalTokens = totalTokens
                }
            }

            public let date: String
            public let inputTokens: Int?
            public let outputTokens: Int?
            public let cacheReadTokens: Int?
            public let cacheCreationTokens: Int?
            public let reasoningOutputTokens: Int?
            public let totalTokens: Int
            public let totalCost: Double
            public let modelsUsed: Int?
            public let modelBreakdowns: [ModelBreakdown]?
            public let approvalPolicies: [CountBreakdown]?
            public let sandboxModes: [CountBreakdown]?
            public let effortLevels: [CountBreakdown]?
            public let riskySkills: [CountBreakdown]?
            public let forbiddenSkills: [CountBreakdown]?

            public init(
                date: String,
                inputTokens: Int?,
                outputTokens: Int?,
                cacheReadTokens: Int?,
                cacheCreationTokens: Int?,
                reasoningOutputTokens: Int?,
                totalTokens: Int,
                totalCost: Double,
                modelsUsed: Int?,
                modelBreakdowns: [ModelBreakdown]?,
                approvalPolicies: [CountBreakdown]?,
                sandboxModes: [CountBreakdown]?,
                effortLevels: [CountBreakdown]?,
                riskySkills: [CountBreakdown]?,
                forbiddenSkills: [CountBreakdown]?)
            {
                self.date = date
                self.inputTokens = inputTokens
                self.outputTokens = outputTokens
                self.cacheReadTokens = cacheReadTokens
                self.cacheCreationTokens = cacheCreationTokens
                self.reasoningOutputTokens = reasoningOutputTokens
                self.totalTokens = totalTokens
                self.totalCost = totalCost
                self.modelsUsed = modelsUsed
                self.modelBreakdowns = modelBreakdowns
                self.approvalPolicies = approvalPolicies
                self.sandboxModes = sandboxModes
                self.effortLevels = effortLevels
                self.riskySkills = riskySkills
                self.forbiddenSkills = forbiddenSkills
            }
        }

        public struct CostTotals: Codable, Sendable, Equatable {
            public let inputTokens: Int?
            public let outputTokens: Int?
            public let cacheReadTokens: Int?
            public let cacheCreationTokens: Int?
            public let reasoningOutputTokens: Int?
            public let totalTokens: Int
            public let totalCost: Double

            public init(
                inputTokens: Int?,
                outputTokens: Int?,
                cacheReadTokens: Int?,
                cacheCreationTokens: Int?,
                reasoningOutputTokens: Int?,
                totalTokens: Int,
                totalCost: Double)
            {
                self.inputTokens = inputTokens
                self.outputTokens = outputTokens
                self.cacheReadTokens = cacheReadTokens
                self.cacheCreationTokens = cacheCreationTokens
                self.reasoningOutputTokens = reasoningOutputTokens
                self.totalTokens = totalTokens
                self.totalCost = totalCost
            }
        }

        public let provider: String
        public let source: String
        public let updatedAt: Date
        public let sessionTokens: Int?
        public let sessionCostUSD: Double?
        public let last30DaysTokens: Int?
        public let last30DaysCostUSD: Double?
        public let daily: [CostDailyEntry]?
        public let totals: CostTotals?
        public let security: Security?
        public let thinking: Thinking?
        public let modelStats: ModelStats?

        public init(
            provider: String,
            source: String,
            updatedAt: Date,
            sessionTokens: Int?,
            sessionCostUSD: Double?,
            last30DaysTokens: Int?,
            last30DaysCostUSD: Double?,
            daily: [CostDailyEntry]?,
            totals: CostTotals?,
            security: Security?,
            thinking: Thinking?,
            modelStats: ModelStats?)
        {
            self.provider = provider
            self.source = source
            self.updatedAt = updatedAt
            self.sessionTokens = sessionTokens
            self.sessionCostUSD = sessionCostUSD
            self.last30DaysTokens = last30DaysTokens
            self.last30DaysCostUSD = last30DaysCostUSD
            self.daily = daily
            self.totals = totals
            self.security = security
            self.thinking = thinking
            self.modelStats = modelStats
        }
    }

    public let schemaVersion: Int
    public let reportId: String
    public let generatedAt: Date
    public let client: Client
    public let snapshots: [ProviderSnapshot]
    public let cost: [CostPayload]?

    public init(
        schemaVersion: Int = 1,
        reportId: String,
        generatedAt: Date,
        client: Client,
        snapshots: [ProviderSnapshot],
        cost: [CostPayload]?)
    {
        self.schemaVersion = schemaVersion
        self.reportId = reportId
        self.generatedAt = generatedAt
        self.client = client
        self.snapshots = snapshots
        self.cost = cost
    }
}

public enum TeamReportBuilder {
    public struct BuildInput: Sendable {
        public let snapshots: [UsageProvider: UsageSnapshot]
        public let tokenSnapshots: [UsageProvider: CostUsageTokenSnapshot]
        public let sourceLabels: [UsageProvider: String]
        public let versions: [UsageProvider: String]
        public let statuses: [UsageProvider: TeamUsageReportPayload.ProviderSnapshot.Status]
        public let creditsByProvider: [UsageProvider: CreditsSnapshot]
        public let openAIDashboardByProvider: [UsageProvider: OpenAIDashboardSnapshot]
        public let appVersion: String
        public let platform: TeamUsageReportPayload.Client.Platform
        public let refreshCadenceSeconds: Int?
        public let reportID: UUID
        public let generatedAt: Date

        public init(
            snapshots: [UsageProvider: UsageSnapshot],
            tokenSnapshots: [UsageProvider: CostUsageTokenSnapshot],
            sourceLabels: [UsageProvider: String],
            versions: [UsageProvider: String],
            statuses: [UsageProvider: TeamUsageReportPayload.ProviderSnapshot.Status],
            creditsByProvider: [UsageProvider: CreditsSnapshot],
            openAIDashboardByProvider: [UsageProvider: OpenAIDashboardSnapshot],
            appVersion: String,
            platform: TeamUsageReportPayload.Client.Platform = .macos,
            refreshCadenceSeconds: Int? = nil,
            reportID: UUID = UUID(),
            generatedAt: Date = Date())
        {
            self.snapshots = snapshots
            self.tokenSnapshots = tokenSnapshots
            self.sourceLabels = sourceLabels
            self.versions = versions
            self.statuses = statuses
            self.creditsByProvider = creditsByProvider
            self.openAIDashboardByProvider = openAIDashboardByProvider
            self.appVersion = appVersion
            self.platform = platform
            self.refreshCadenceSeconds = refreshCadenceSeconds
            self.reportID = reportID
            self.generatedAt = generatedAt
        }
    }

    public static func build(_ input: BuildInput) -> TeamUsageReportPayload? {
        let orderedProviders = UsageProvider.allCases

        let usageSnapshots = orderedProviders.compactMap { provider -> TeamUsageReportPayload.ProviderSnapshot? in
            guard let snapshot = input.snapshots[provider] else { return nil }
            guard let windows = Self.windows(from: snapshot) else { return nil }

            let usage = TeamUsageReportPayload.ProviderSnapshot.UsageSnapshot(
                primary: windows.primary,
                secondary: windows.secondary,
                tertiary: windows.tertiary,
                updatedAt: snapshot.updatedAt)

            return TeamUsageReportPayload.ProviderSnapshot(
                provider: provider.rawValue,
                version: Self.normalizedString(input.versions[provider], maxLength: 128),
                source: Self.normalizedSource(input.sourceLabels[provider]),
                status: Self.sanitizedStatus(input.statuses[provider]),
                usage: usage,
                credits: input.creditsByProvider[provider].map(Self.creditsPayload(from:)),
                extras: input.openAIDashboardByProvider[provider].flatMap(Self.extrasPayload(from:)))
        }

        guard !usageSnapshots.isEmpty else { return nil }

        let costSnapshots = orderedProviders.compactMap { provider -> TeamUsageReportPayload.CostPayload? in
            guard let token = input.tokenSnapshots[provider] else { return nil }
            return Self.costPayload(from: token, provider: provider.rawValue)
        }

        return TeamUsageReportPayload(
            schemaVersion: 1,
            reportId: input.reportID.uuidString.lowercased(),
            generatedAt: input.generatedAt,
            client: TeamUsageReportPayload.Client(
                platform: input.platform,
                appVersion: Self.normalizedAppVersion(input.appVersion),
                refreshCadenceSeconds: Self.clampedRefreshCadenceSeconds(input.refreshCadenceSeconds)),
            snapshots: Array(usageSnapshots.prefix(50)),
            cost: costSnapshots.isEmpty ? nil : Array(costSnapshots.prefix(50)))
    }

    private static func windows(
        from snapshot: UsageSnapshot) -> (
        primary: TeamUsageReportPayload.ProviderSnapshot.UsageSnapshot.UsageWindow,
        secondary: TeamUsageReportPayload.ProviderSnapshot.UsageSnapshot.UsageWindow?,
        tertiary: TeamUsageReportPayload.ProviderSnapshot.UsageSnapshot.UsageWindow?)?
    {
        let windows = [snapshot.primary, snapshot.secondary, snapshot.tertiary]
            .compactMap { Self.window(from: $0) }
        guard let primary = windows.first else { return nil }
        let secondary = windows.count > 1 ? windows[1] : nil
        let tertiary = windows.count > 2 ? windows[2] : nil
        return (primary: primary, secondary: secondary, tertiary: tertiary)
    }

    private static func window(
        from window: RateWindow?) -> TeamUsageReportPayload.ProviderSnapshot.UsageSnapshot.UsageWindow?
    {
        guard let window else { return nil }
        return TeamUsageReportPayload.ProviderSnapshot.UsageSnapshot.UsageWindow(
            usedPercent: Self.clampedPercent(window.usedPercent),
            windowMinutes: window.windowMinutes.map { max(1, min(525_600, $0)) },
            resetsAt: window.resetsAt,
            resetDescription: Self.normalizedString(window.resetDescription, maxLength: 280))
    }

    private static func creditsPayload(
        from snapshot: CreditsSnapshot) -> TeamUsageReportPayload.ProviderSnapshot.Credits
    {
        TeamUsageReportPayload.ProviderSnapshot.Credits(
            remaining: max(0, snapshot.remaining),
            updatedAt: snapshot.updatedAt)
    }

    private static func extrasPayload(
        from snapshot: OpenAIDashboardSnapshot) -> TeamUsageReportPayload.ProviderSnapshot.Extras?
    {
        let codeReviewRemainingPercent = snapshot.codeReviewRemainingPercent.map(Self.clampedPercent)

        let creditEvents = Array(snapshot.creditEvents.prefix(2000)).map { event in
            TeamUsageReportPayload.ProviderSnapshot.Extras.OpenAIDashboardExtras.CreditEvent(
                id: event.id.uuidString.lowercased(),
                date: event.date,
                service: Self.normalizedString(event.service, fallback: "unknown", maxLength: 128) ?? "unknown",
                creditsUsed: max(0, event.creditsUsed))
        }

        let dailyBreakdown: [TeamUsageReportPayload.ProviderSnapshot.Extras.OpenAIDashboardExtras
            .DailyCreditBreakdown] =
            Array(snapshot.dailyBreakdown.prefix(366)).compactMap { item in
                guard let day = Self.normalizedDay(item.day) else { return nil }
                let services = Array(item.services.prefix(200)).map { service in
                    TeamUsageReportPayload.ProviderSnapshot.Extras.OpenAIDashboardExtras.ServiceUsage(
                        service: Self
                            .normalizedString(service.service, fallback: "unknown", maxLength: 128) ?? "unknown",
                        creditsUsed: max(0, service.creditsUsed))
                }
                return TeamUsageReportPayload.ProviderSnapshot.Extras.OpenAIDashboardExtras.DailyCreditBreakdown(
                    day: day,
                    services: services,
                    totalCreditsUsed: max(0, item.totalCreditsUsed))
            }

        let openAIDashboard = TeamUsageReportPayload.ProviderSnapshot.Extras.OpenAIDashboardExtras(
            codeReviewRemainingPercent: codeReviewRemainingPercent,
            creditEvents: creditEvents.isEmpty ? nil : creditEvents,
            dailyBreakdown: dailyBreakdown.isEmpty ? nil : dailyBreakdown,
            updatedAt: snapshot.updatedAt)

        return TeamUsageReportPayload.ProviderSnapshot.Extras(openaiDashboard: openAIDashboard)
    }

    private static func costPayload(
        from snapshot: CostUsageTokenSnapshot,
        provider: String) -> TeamUsageReportPayload.CostPayload
    {
        let dailyEntries = Array(snapshot.daily.prefix(366)).compactMap { Self.costDailyEntry(from: $0) }
        let security = Self.costSecurity(from: dailyEntries)
        let thinking = Self.costThinking(from: snapshot, dailyEntries: dailyEntries)
        let modelStats = Self.costModelStats(from: dailyEntries)
        return TeamUsageReportPayload.CostPayload(
            provider: provider,
            source: "local",
            updatedAt: snapshot.updatedAt,
            sessionTokens: Self.nonNegative(snapshot.sessionTokens),
            sessionCostUSD: Self.nonNegative(snapshot.sessionCostUSD),
            last30DaysTokens: Self.nonNegative(snapshot.last30DaysTokens),
            last30DaysCostUSD: Self.nonNegative(snapshot.last30DaysCostUSD),
            daily: dailyEntries.isEmpty ? nil : dailyEntries,
            totals: Self.costTotals(from: snapshot, dailyEntries: dailyEntries),
            security: security,
            thinking: thinking,
            modelStats: modelStats)
    }

    private static func costDailyEntry(
        from entry: CostUsageDailyReport.Entry) -> TeamUsageReportPayload.CostPayload.CostDailyEntry?
    {
        guard let date = normalizedDay(entry.date) else { return nil }

        let inputTokens = Self.nonNegative(entry.inputTokens)
        let outputTokens = Self.nonNegative(entry.outputTokens)
        let cacheReadTokens = Self.nonNegative(entry.cacheReadTokens)
        let cacheCreationTokens = Self.nonNegative(entry.cacheCreationTokens)
        let reasoningOutputTokens = Self.nonNegative(entry.reasoningOutputTokens)

        let derivedTokens = [inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens]
            .compactMap(\.self)
            .reduce(0, +)
        let totalTokens = Self.nonNegative(entry.totalTokens) ?? derivedTokens

        let modelBreakdowns = Self.costModelBreakdowns(from: entry.modelBreakdowns)
        let derivedCost = modelBreakdowns?.reduce(0) { $0 + $1.cost }
        let totalCost = Self.nonNegative(entry.costUSD) ?? derivedCost ?? 0

        let modelsUsed: Int? = {
            if let models = entry.modelsUsed {
                return max(0, models.count)
            }
            if let modelBreakdowns {
                return max(0, modelBreakdowns.count)
            }
            return nil
        }()

        return TeamUsageReportPayload.CostPayload.CostDailyEntry(
            date: date,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens,
            reasoningOutputTokens: reasoningOutputTokens,
            totalTokens: max(0, totalTokens),
            totalCost: max(0, totalCost),
            modelsUsed: modelsUsed,
            modelBreakdowns: modelBreakdowns,
            approvalPolicies: Self.costCountBreakdowns(from: entry.approvalPolicyBreakdowns),
            sandboxModes: Self.costCountBreakdowns(from: entry.sandboxModeBreakdowns),
            effortLevels: Self.costCountBreakdowns(from: entry.effortBreakdowns),
            riskySkills: Self.costCountBreakdowns(from: entry.riskySkillBreakdowns),
            forbiddenSkills: Self.costCountBreakdowns(from: entry.forbiddenSkillBreakdowns))
    }

    private static func costModelBreakdowns(
        from breakdowns: [CostUsageDailyReport.ModelBreakdown]?)
        -> [TeamUsageReportPayload.CostPayload.CostDailyEntry.ModelBreakdown]?
    {
        guard let breakdowns else { return nil }

        let payload = Array(breakdowns.prefix(200))
            .compactMap { breakdown -> TeamUsageReportPayload.CostPayload.CostDailyEntry.ModelBreakdown? in
                guard let name = Self.normalizedString(breakdown.modelName, maxLength: 128) else {
                    return nil
                }
                return TeamUsageReportPayload.CostPayload.CostDailyEntry.ModelBreakdown(
                    modelName: name,
                    cost: max(0, Self.nonNegative(breakdown.costUSD) ?? 0),
                    inputTokens: Self.nonNegative(breakdown.inputTokens),
                    outputTokens: Self.nonNegative(breakdown.outputTokens),
                    cacheReadTokens: Self.nonNegative(breakdown.cacheReadTokens),
                    cacheCreationTokens: Self.nonNegative(breakdown.cacheCreationTokens),
                    reasoningOutputTokens: Self.nonNegative(breakdown.reasoningOutputTokens),
                    totalTokens: Self.nonNegative(breakdown.totalTokens))
            }

        return payload.isEmpty ? nil : payload
    }

    private static func costCountBreakdowns(
        from breakdowns: [CostUsageDailyReport.CountBreakdown]?)
        -> [TeamUsageReportPayload.CostPayload.CountBreakdown]?
    {
        guard let breakdowns else { return nil }
        let payload = Array(breakdowns.prefix(200))
            .compactMap { item -> TeamUsageReportPayload.CostPayload.CountBreakdown? in
                guard let name = Self.normalizedString(item.name, maxLength: 128) else {
                    return nil
                }
                return TeamUsageReportPayload.CostPayload.CountBreakdown(
                    name: name,
                    count: max(0, item.count))
            }
        return payload.isEmpty ? nil : payload
    }

    private static func costTotals(
        from snapshot: CostUsageTokenSnapshot,
        dailyEntries: [TeamUsageReportPayload.CostPayload.CostDailyEntry])
        -> TeamUsageReportPayload.CostPayload.CostTotals?
    {
        if dailyEntries.isEmpty {
            guard snapshot.last30DaysTokens != nil || snapshot.last30DaysCostUSD != nil else {
                return nil
            }
            return TeamUsageReportPayload.CostPayload.CostTotals(
                inputTokens: nil,
                outputTokens: nil,
                cacheReadTokens: nil,
                cacheCreationTokens: nil,
                reasoningOutputTokens: nil,
                totalTokens: max(0, snapshot.last30DaysTokens ?? 0),
                totalCost: max(0, snapshot.last30DaysCostUSD ?? 0))
        }

        var inputTokensTotal = 0
        var outputTokensTotal = 0
        var cacheReadTokensTotal = 0
        var cacheCreationTokensTotal = 0
        var reasoningOutputTokensTotal = 0
        var sawInputTokens = false
        var sawOutputTokens = false
        var sawCacheReadTokens = false
        var sawCacheCreationTokens = false
        var sawReasoningOutputTokens = false

        var totalTokens = 0
        var totalCost = 0.0

        for entry in dailyEntries {
            if let inputTokens = entry.inputTokens {
                inputTokensTotal += inputTokens
                sawInputTokens = true
            }
            if let outputTokens = entry.outputTokens {
                outputTokensTotal += outputTokens
                sawOutputTokens = true
            }
            if let cacheReadTokens = entry.cacheReadTokens {
                cacheReadTokensTotal += cacheReadTokens
                sawCacheReadTokens = true
            }
            if let cacheCreationTokens = entry.cacheCreationTokens {
                cacheCreationTokensTotal += cacheCreationTokens
                sawCacheCreationTokens = true
            }
            if let reasoningOutputTokens = entry.reasoningOutputTokens {
                reasoningOutputTokensTotal += reasoningOutputTokens
                sawReasoningOutputTokens = true
            }
            totalTokens += entry.totalTokens
            totalCost += entry.totalCost
        }

        return TeamUsageReportPayload.CostPayload.CostTotals(
            inputTokens: sawInputTokens ? inputTokensTotal : nil,
            outputTokens: sawOutputTokens ? outputTokensTotal : nil,
            cacheReadTokens: sawCacheReadTokens ? cacheReadTokensTotal : nil,
            cacheCreationTokens: sawCacheCreationTokens ? cacheCreationTokensTotal : nil,
            reasoningOutputTokens: sawReasoningOutputTokens ? reasoningOutputTokensTotal : nil,
            totalTokens: max(0, Self.nonNegative(snapshot.last30DaysTokens) ?? totalTokens),
            totalCost: max(0, Self.nonNegative(snapshot.last30DaysCostUSD) ?? totalCost))
    }

    private static func costSecurity(
        from dailyEntries: [TeamUsageReportPayload.CostPayload.CostDailyEntry])
        -> TeamUsageReportPayload.CostPayload.Security?
    {
        var approval: [String: Int] = [:]
        var sandbox: [String: Int] = [:]
        var riskySkills: [String: Int] = [:]
        var forbiddenSkills: [String: Int] = [:]

        for entry in dailyEntries {
            Self.mergeCountBreakdowns(into: &approval, values: entry.approvalPolicies)
            Self.mergeCountBreakdowns(into: &sandbox, values: entry.sandboxModes)
            Self.mergeCountBreakdowns(into: &riskySkills, values: entry.riskySkills)
            Self.mergeCountBreakdowns(into: &forbiddenSkills, values: entry.forbiddenSkills)
        }

        let approvalPayload = Self.costCountBreakdownsFromMap(approval)
        let sandboxPayload = Self.costCountBreakdownsFromMap(sandbox)
        let riskyPayload = Self.costCountBreakdownsFromMap(riskySkills)
        let forbiddenPayload = Self.costCountBreakdownsFromMap(forbiddenSkills)
        guard approvalPayload != nil || sandboxPayload != nil || riskyPayload != nil || forbiddenPayload != nil else {
            return nil
        }

        return TeamUsageReportPayload.CostPayload.Security(
            approvalPolicies: approvalPayload,
            sandboxModes: sandboxPayload,
            riskySkills: riskyPayload,
            forbiddenSkills: forbiddenPayload)
    }

    private static func costThinking(
        from snapshot: CostUsageTokenSnapshot,
        dailyEntries: [TeamUsageReportPayload.CostPayload.CostDailyEntry])
        -> TeamUsageReportPayload.CostPayload.Thinking?
    {
        var effortLevels: [String: Int] = [:]
        for entry in dailyEntries {
            Self.mergeCountBreakdowns(into: &effortLevels, values: entry.effortLevels)
        }

        let reasoningFromRows = dailyEntries.compactMap(\.reasoningOutputTokens).reduce(0, +)
        let reasoningFromSnapshot = snapshot.daily.compactMap { Self.nonNegative($0.reasoningOutputTokens) }.reduce(
            0,
            +)
        let reasoning = max(reasoningFromRows, reasoningFromSnapshot)
        let reasoningValue = reasoning > 0 ? reasoning : nil
        let effortPayload = Self.costCountBreakdownsFromMap(effortLevels)
        guard reasoningValue != nil || effortPayload != nil else { return nil }
        return TeamUsageReportPayload.CostPayload.Thinking(
            reasoningOutputTokens: reasoningValue,
            effortLevels: effortPayload)
    }

    private static func costModelStats(
        from dailyEntries: [TeamUsageReportPayload.CostPayload.CostDailyEntry])
        -> TeamUsageReportPayload.CostPayload.ModelStats?
    {
        struct ModelAccumulator {
            var inputTokens = 0
            var outputTokens = 0
            var cacheReadTokens = 0
            var cacheCreationTokens = 0
            var reasoningOutputTokens = 0
            var totalTokens = 0
            var totalCost = 0.0
            var activeDays: Set<String> = []
            var sawInputTokens = false
            var sawOutputTokens = false
            var sawCacheReadTokens = false
            var sawCacheCreationTokens = false
            var sawReasoningOutputTokens = false
        }

        var models: [String: ModelAccumulator] = [:]

        for entry in dailyEntries {
            guard let breakdowns = entry.modelBreakdowns else { continue }
            for breakdown in breakdowns {
                guard let name = Self.normalizedString(breakdown.modelName, maxLength: 128) else { continue }
                var model = models[name] ?? ModelAccumulator()
                if let inputTokens = breakdown.inputTokens {
                    model.inputTokens += max(0, inputTokens)
                    model.sawInputTokens = true
                }
                if let outputTokens = breakdown.outputTokens {
                    model.outputTokens += max(0, outputTokens)
                    model.sawOutputTokens = true
                }
                if let cacheReadTokens = breakdown.cacheReadTokens {
                    model.cacheReadTokens += max(0, cacheReadTokens)
                    model.sawCacheReadTokens = true
                }
                if let cacheCreationTokens = breakdown.cacheCreationTokens {
                    model.cacheCreationTokens += max(0, cacheCreationTokens)
                    model.sawCacheCreationTokens = true
                }
                if let reasoningOutputTokens = breakdown.reasoningOutputTokens {
                    model.reasoningOutputTokens += max(0, reasoningOutputTokens)
                    model.sawReasoningOutputTokens = true
                }

                let derivedTokens = (breakdown.inputTokens ?? 0)
                    + (breakdown.outputTokens ?? 0)
                    + (breakdown.cacheReadTokens ?? 0)
                    + (breakdown.cacheCreationTokens ?? 0)
                let totalTokens = max(0, breakdown.totalTokens ?? derivedTokens)
                model.totalTokens += totalTokens
                model.totalCost += max(0, breakdown.cost)
                model.activeDays.insert(entry.date)
                models[name] = model
            }
        }

        guard !models.isEmpty else { return nil }

        let payload = models
            .map { name, model in
                TeamUsageReportPayload.CostPayload.ModelStats.ModelUsage(
                    modelName: name,
                    inputTokens: model.sawInputTokens ? model.inputTokens : nil,
                    outputTokens: model.sawOutputTokens ? model.outputTokens : nil,
                    cacheReadTokens: model.sawCacheReadTokens ? model.cacheReadTokens : nil,
                    cacheCreationTokens: model.sawCacheCreationTokens ? model.cacheCreationTokens : nil,
                    reasoningOutputTokens: model.sawReasoningOutputTokens ? model.reasoningOutputTokens : nil,
                    totalTokens: model.totalTokens,
                    totalCost: model.totalCost,
                    activeDays: model.activeDays.count)
            }
            .sorted { lhs, rhs in
                if lhs.totalTokens == rhs.totalTokens {
                    if lhs.totalCost == rhs.totalCost {
                        return lhs.modelName < rhs.modelName
                    }
                    return lhs.totalCost > rhs.totalCost
                }
                return lhs.totalTokens > rhs.totalTokens
            }

        return TeamUsageReportPayload.CostPayload.ModelStats(
            modelsUsed: payload.count,
            models: Array(payload.prefix(200)))
    }

    private static func mergeCountBreakdowns(
        into target: inout [String: Int],
        values: [TeamUsageReportPayload.CostPayload.CountBreakdown]?)
    {
        guard let values else { return }
        for item in values {
            guard let name = Self.normalizedString(item.name, maxLength: 128) else { continue }
            let count = max(0, item.count)
            if count == 0 { continue }
            target[name] = max(0, (target[name] ?? 0) + count)
        }
    }

    private static func costCountBreakdownsFromMap(_ values: [String: Int])
        -> [TeamUsageReportPayload.CostPayload.CountBreakdown]?
    {
        let payload = values
            .compactMap { name, count -> TeamUsageReportPayload.CostPayload.CountBreakdown? in
                guard let normalizedName = Self.normalizedString(name, maxLength: 128) else {
                    return nil
                }
                guard count > 0 else { return nil }
                return TeamUsageReportPayload.CostPayload.CountBreakdown(name: normalizedName, count: count)
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.name < rhs.name }
                return lhs.count > rhs.count
            }
        return payload.isEmpty ? nil : payload
    }

    private static func sanitizedStatus(
        _ status: TeamUsageReportPayload.ProviderSnapshot.Status?)
        -> TeamUsageReportPayload.ProviderSnapshot.Status?
    {
        guard let status else { return nil }
        return TeamUsageReportPayload.ProviderSnapshot.Status(
            indicator: status.indicator,
            description: Self.normalizedString(status.description, maxLength: 280),
            updatedAt: status.updatedAt,
            url: Self.normalizedURL(status.url))
    }

    private static func clampedPercent(_ value: Double) -> Int {
        let rounded = Int(value.rounded())
        return min(max(rounded, 0), 100)
    }

    private static func clampedRefreshCadenceSeconds(_ value: Int?) -> Int? {
        guard let value else { return nil }
        return max(30, min(86400, value))
    }

    private static func normalizedSource(_ value: String?) -> String {
        self.normalizedString(value, fallback: "unknown", maxLength: 64) ?? "unknown"
    }

    private static func normalizedAppVersion(_ value: String) -> String {
        self.normalizedString(value, fallback: "unknown", maxLength: 64) ?? "unknown"
    }

    private static func normalizedURL(_ value: String?) -> String? {
        guard let value = normalizedString(value, maxLength: 2048) else { return nil }
        guard let url = URL(string: value), url.scheme != nil else { return nil }
        return value
    }

    private static func normalizedDay(_ value: String) -> String? {
        guard let normalized = normalizedString(value, maxLength: 10) else {
            return nil
        }
        guard normalized.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return normalized
    }

    private static func normalizedString(
        _ value: String?,
        fallback: String? = nil,
        maxLength: Int) -> String?
    {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let source = trimmed.isEmpty ? fallback : trimmed
        guard let source else { return nil }
        guard !source.isEmpty else { return nil }
        if source.count <= maxLength { return source }
        let index = source.index(source.startIndex, offsetBy: maxLength)
        return String(source[..<index])
    }

    private static func nonNegative(_ value: Int?) -> Int? {
        guard let value else { return nil }
        return max(0, value)
    }

    private static func nonNegative(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return max(0, value)
    }
}

public enum TeamReportSanitizer {
    private static let blockedKeySubstrings: [String] = [
        "email",
        "identity",
        "organization",
        "cookie",
        "prompt",
    ]

    private static let blockedKeyExact: Set<String> = [
        "accountemail",
        "accountorganization",
        "signedinemail",
        "loginmethod",
        "filepath",
        "file_path",
    ]

    public static func sanitizeJSONData(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return data }
        let rawObject = try JSONSerialization.jsonObject(with: data)
        let sanitizedObject = Self.sanitizeJSONObject(rawObject)
        guard JSONSerialization.isValidJSONObject(sanitizedObject) else {
            return Data("{}".utf8)
        }
        return try JSONSerialization.data(withJSONObject: sanitizedObject, options: [])
    }

    public static func sanitizePayload(_ payload: TeamUsageReportPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return try Self.sanitizeJSONData(data)
    }

    public static func containsForbiddenKeys(data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        return Self.containsForbiddenKeys(in: object)
    }
}

extension TeamReportSanitizer {
    fileprivate static func sanitizeJSONObject(_ object: Any) -> Any {
        switch object {
        case let dictionary as [String: Any]:
            var sanitized: [String: Any] = [:]
            sanitized.reserveCapacity(dictionary.count)
            for (key, value) in dictionary {
                if Self.shouldDropKey(key) {
                    continue
                }
                sanitized[key] = Self.sanitizeJSONObject(value)
            }
            return sanitized
        case let array as [Any]:
            return array.map { Self.sanitizeJSONObject($0) }
        default:
            return object
        }
    }

    fileprivate static func containsForbiddenKeys(in object: Any) -> Bool {
        switch object {
        case let dictionary as [String: Any]:
            for (key, value) in dictionary {
                if Self.shouldDropKey(key) {
                    return true
                }
                if Self.containsForbiddenKeys(in: value) {
                    return true
                }
            }
            return false
        case let array as [Any]:
            return array.contains { Self.containsForbiddenKeys(in: $0) }
        default:
            return false
        }
    }

    fileprivate static func shouldDropKey(_ key: String) -> Bool {
        let normalized = key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if Self.blockedKeyExact.contains(normalized) {
            return true
        }
        return Self.blockedKeySubstrings.contains { normalized.contains($0) }
    }
}

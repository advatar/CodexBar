import Foundation

// swiftlint:disable type_body_length
enum CostUsageScanner {
    enum ClaudeLogProviderFilter: Sendable {
        case all
        case vertexAIOnly
        case excludeVertexAI
    }

    struct Options: Sendable {
        var codexSessionsRoot: URL?
        var claudeProjectsRoots: [URL]?
        var cacheRoot: URL?
        var refreshMinIntervalSeconds: TimeInterval = 60
        var claudeLogProviderFilter: ClaudeLogProviderFilter = .all
        /// Force a full rescan, ignoring per-file cache and incremental offsets.
        var forceRescan: Bool = false

        init(
            codexSessionsRoot: URL? = nil,
            claudeProjectsRoots: [URL]? = nil,
            cacheRoot: URL? = nil,
            claudeLogProviderFilter: ClaudeLogProviderFilter = .all,
            forceRescan: Bool = false)
        {
            self.codexSessionsRoot = codexSessionsRoot
            self.claudeProjectsRoots = claudeProjectsRoots
            self.cacheRoot = cacheRoot
            self.claudeLogProviderFilter = claudeLogProviderFilter
            self.forceRescan = forceRescan
        }
    }

    struct CodexParseResult: Sendable {
        let days: [String: [String: [Int]]]
        let codexContextDays: [String: CostUsageCodexContextDay]
        let parsedBytes: Int64
        let lastModel: String?
        let lastTotals: CostUsageCodexTotals?
        let lastApprovalPolicy: String?
        let lastSandboxMode: String?
        let lastEffort: String?
        let sessionId: String?
    }

    private struct CodexScanState {
        var seenSessionIds: Set<String> = []
        var seenFileIds: Set<String> = []
    }

    struct ClaudeParseResult: Sendable {
        let days: [String: [String: [Int]]]
        let parsedBytes: Int64
    }

    static func loadDailyReport(
        provider: UsageProvider,
        since: Date,
        until: Date,
        now: Date = Date(),
        options: Options = Options()) -> CostUsageDailyReport
    {
        let range = CostUsageDayRange(since: since, until: until)

        switch provider {
        case .codex:
            return self.loadCodexDaily(range: range, now: now, options: options)
        case .claude:
            return self.loadClaudeDaily(provider: .claude, range: range, now: now, options: options)
        case .zai:
            return CostUsageDailyReport(data: [], summary: nil)
        case .gemini:
            return CostUsageDailyReport(data: [], summary: nil)
        case .antigravity:
            return CostUsageDailyReport(data: [], summary: nil)
        case .cursor:
            return CostUsageDailyReport(data: [], summary: nil)
        case .opencode:
            return CostUsageDailyReport(data: [], summary: nil)
        case .factory:
            return CostUsageDailyReport(data: [], summary: nil)
        case .copilot:
            return CostUsageDailyReport(data: [], summary: nil)
        case .minimax:
            return CostUsageDailyReport(data: [], summary: nil)
        case .vertexai:
            var filtered = options
            if filtered.claudeLogProviderFilter == .all {
                filtered.claudeLogProviderFilter = .vertexAIOnly
            }
            return self.loadClaudeDaily(provider: .vertexai, range: range, now: now, options: filtered)
        case .kiro:
            return CostUsageDailyReport(data: [], summary: nil)
        case .kimi:
            return CostUsageDailyReport(data: [], summary: nil)
        case .kimik2:
            return CostUsageDailyReport(data: [], summary: nil)
        case .augment:
            return CostUsageDailyReport(data: [], summary: nil)
        case .jetbrains:
            return CostUsageDailyReport(data: [], summary: nil)
        case .amp:
            return CostUsageDailyReport(data: [], summary: nil)
        case .synthetic:
            return CostUsageDailyReport(data: [], summary: nil)
        case .warp:
            return CostUsageDailyReport(data: [], summary: nil)
        }
    }

    // MARK: - Day keys

    struct CostUsageDayRange: Sendable {
        let sinceKey: String
        let untilKey: String
        let scanSinceKey: String
        let scanUntilKey: String

        init(since: Date, until: Date) {
            self.sinceKey = Self.dayKey(from: since)
            self.untilKey = Self.dayKey(from: until)
            self.scanSinceKey = Self.dayKey(from: Calendar.current.date(byAdding: .day, value: -1, to: since) ?? since)
            self.scanUntilKey = Self.dayKey(from: Calendar.current.date(byAdding: .day, value: 1, to: until) ?? until)
        }

        static func dayKey(from date: Date) -> String {
            let cal = Calendar.current
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            let y = comps.year ?? 1970
            let m = comps.month ?? 1
            let d = comps.day ?? 1
            return String(format: "%04d-%02d-%02d", y, m, d)
        }

        static func isInRange(dayKey: String, since: String, until: String) -> Bool {
            if dayKey < since { return false }
            if dayKey > until { return false }
            return true
        }
    }

    // MARK: - Codex

    private static func defaultCodexSessionsRoot(options: Options) -> URL {
        if let override = options.codexSessionsRoot { return override }
        let env = ProcessInfo.processInfo.environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let env, !env.isEmpty {
            return URL(fileURLWithPath: env).appendingPathComponent("sessions", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    private static func codexSessionsRoots(options: Options) -> [URL] {
        let root = self.defaultCodexSessionsRoot(options: options)
        if let archived = self.codexArchivedSessionsRoot(sessionsRoot: root) {
            return [root, archived]
        }
        return [root]
    }

    private static func codexArchivedSessionsRoot(sessionsRoot: URL) -> URL? {
        guard sessionsRoot.lastPathComponent == "sessions" else { return nil }
        return sessionsRoot
            .deletingLastPathComponent()
            .appendingPathComponent("archived_sessions", isDirectory: true)
    }

    private static func listCodexSessionFiles(root: URL, scanSinceKey: String, scanUntilKey: String) -> [URL] {
        let partitioned = self.listCodexSessionFilesByDatePartition(
            root: root,
            scanSinceKey: scanSinceKey,
            scanUntilKey: scanUntilKey)
        let flat = self.listCodexSessionFilesFlat(root: root, scanSinceKey: scanSinceKey, scanUntilKey: scanUntilKey)
        var seen: Set<String> = []
        var out: [URL] = []
        for item in partitioned + flat where !seen.contains(item.path) {
            seen.insert(item.path)
            out.append(item)
        }
        return out
    }

    private static func listCodexSessionFilesByDatePartition(
        root: URL,
        scanSinceKey: String,
        scanUntilKey: String) -> [URL]
    {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var out: [URL] = []
        var date = Self.parseDayKey(scanSinceKey) ?? Date()
        let untilDate = Self.parseDayKey(scanUntilKey) ?? date

        while date <= untilDate {
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
            let y = String(format: "%04d", comps.year ?? 1970)
            let m = String(format: "%02d", comps.month ?? 1)
            let d = String(format: "%02d", comps.day ?? 1)

            let dayDir = root.appendingPathComponent(y, isDirectory: true)
                .appendingPathComponent(m, isDirectory: true)
                .appendingPathComponent(d, isDirectory: true)

            if let items = try? FileManager.default.contentsOfDirectory(
                at: dayDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
            {
                for item in items where item.pathExtension.lowercased() == "jsonl" {
                    out.append(item)
                }
            }

            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? untilDate.addingTimeInterval(1)
        }

        return out
    }

    private static func listCodexSessionFilesFlat(root: URL, scanSinceKey: String, scanUntilKey: String) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }

        var out: [URL] = []
        for item in items where item.pathExtension.lowercased() == "jsonl" {
            if let dayKey = Self.dayKeyFromFilename(item.lastPathComponent) {
                if !CostUsageDayRange.isInRange(dayKey: dayKey, since: scanSinceKey, until: scanUntilKey) {
                    continue
                }
            }
            out.append(item)
        }
        return out
    }

    private static let codexFilenameDateRegex = try? NSRegularExpression(pattern: "(\\d{4}-\\d{2}-\\d{2})")

    private static func dayKeyFromFilename(_ filename: String) -> String? {
        guard let regex = self.codexFilenameDateRegex else { return nil }
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        guard let match = regex.firstMatch(in: filename, range: range) else { return nil }
        guard let matchRange = Range(match.range(at: 1), in: filename) else { return nil }
        return String(filename[matchRange])
    }

    private static func fileIdentityString(fileURL: URL) -> String? {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileResourceIdentifierKey]) else { return nil }
        guard let identifier = values.fileResourceIdentifier else { return nil }
        if let data = identifier as? Data {
            return data.base64EncodedString()
        }
        return String(describing: identifier)
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func parseCodexFile(
        fileURL: URL,
        range: CostUsageDayRange,
        startOffset: Int64 = 0,
        initialModel: String? = nil,
        initialTotals: CostUsageCodexTotals? = nil,
        initialApprovalPolicy: String? = nil,
        initialSandboxMode: String? = nil,
        initialEffort: String? = nil) -> CodexParseResult
    {
        var currentModel = initialModel
        var previousTotals = initialTotals
        var currentApprovalPolicy = initialApprovalPolicy
        var currentSandboxMode = initialSandboxMode
        var currentEffort = initialEffort
        var sessionId: String?

        var days: [String: [String: [Int]]] = [:]
        var codexContextDays: [String: CostUsageCodexContextDay] = [:]
        var pendingRiskySkills: [String: Int] = [:]
        var pendingForbiddenSkills: [String: Int] = [:]
        var didAssignSessionSkills = false

        struct TokenDelta {
            let input: Int
            let cached: Int
            let output: Int
            let reasoningOutput: Int
        }

        func add(dayKey: String, model: String, delta: TokenDelta) {
            guard CostUsageDayRange.isInRange(dayKey: dayKey, since: range.scanSinceKey, until: range.scanUntilKey)
            else { return }
            let normModel = CostUsagePricing.normalizeCodexModel(model)

            var dayModels = days[dayKey] ?? [:]
            var packed = dayModels[normModel] ?? [0, 0, 0, 0]
            packed[0] = (packed[safe: 0] ?? 0) + delta.input
            packed[1] = (packed[safe: 1] ?? 0) + delta.cached
            packed[2] = (packed[safe: 2] ?? 0) + delta.output
            packed[3] = (packed[safe: 3] ?? 0) + delta.reasoningOutput
            dayModels[normModel] = packed
            days[dayKey] = dayModels
        }

        func increment(_ map: inout [String: Int], key: String?) {
            guard let key = Self.normalizedContextLabel(key) else { return }
            map[key] = max(0, (map[key] ?? 0) + 1)
        }

        func addContext(dayKey: String, approvalPolicy: String?, sandboxMode: String?, effort: String?) {
            guard CostUsageDayRange.isInRange(dayKey: dayKey, since: range.scanSinceKey, until: range.scanUntilKey)
            else { return }
            var context = codexContextDays[dayKey] ?? CostUsageCodexContextDay()
            increment(&context.approvalPolicies, key: approvalPolicy)
            increment(&context.sandboxModes, key: sandboxMode)
            increment(&context.effortLevels, key: effort)
            if context.isEmpty {
                codexContextDays.removeValue(forKey: dayKey)
            } else {
                codexContextDays[dayKey] = context
            }
        }

        func assignSessionSkillsIfNeeded(dayKey: String) {
            guard !didAssignSessionSkills else { return }
            guard !pendingRiskySkills.isEmpty || !pendingForbiddenSkills.isEmpty else { return }
            guard CostUsageDayRange.isInRange(dayKey: dayKey, since: range.scanSinceKey, until: range.scanUntilKey)
            else { return }

            var context = codexContextDays[dayKey] ?? CostUsageCodexContextDay()
            for (skill, count) in pendingRiskySkills {
                context.riskySkills[skill] = max(0, (context.riskySkills[skill] ?? 0) + count)
            }
            for (skill, count) in pendingForbiddenSkills {
                context.forbiddenSkills[skill] = max(0, (context.forbiddenSkills[skill] ?? 0) + count)
            }
            codexContextDays[dayKey] = context
            didAssignSessionSkills = true
        }

        let maxLineBytes = 256 * 1024
        let prefixBytes = maxLineBytes

        let parsedBytes = (try? CostUsageJsonl.scan(
            fileURL: fileURL,
            offset: startOffset,
            maxLineBytes: maxLineBytes,
            prefixBytes: prefixBytes,
            onLine: { line in
                guard !line.bytes.isEmpty else { return }
                guard !line.wasTruncated else { return }

                guard
                    line.bytes.containsAscii(#""type":"event_msg""#)
                    || line.bytes.containsAscii(#""type":"turn_context""#)
                    || line.bytes.containsAscii(#""type":"session_meta""#)
                else { return }

                if line.bytes.containsAscii(#""type":"event_msg""#), !line.bytes.containsAscii(#""token_count""#) {
                    return
                }

                guard
                    let obj = (try? JSONSerialization.jsonObject(with: line.bytes)) as? [String: Any],
                    let type = obj["type"] as? String
                else { return }

                if type == "session_meta" {
                    let payload = obj["payload"] as? [String: Any]
                    if sessionId == nil {
                        sessionId = payload?["session_id"] as? String
                            ?? payload?["sessionId"] as? String
                            ?? payload?["id"] as? String
                            ?? obj["session_id"] as? String
                            ?? obj["sessionId"] as? String
                            ?? obj["id"] as? String
                    }
                    if pendingRiskySkills.isEmpty, pendingForbiddenSkills.isEmpty {
                        let instructionsText =
                            payload?["instructions"] as? String
                                ?? (payload?["base_instructions"] as? [String: Any])?["text"] as? String
                        if let instructionsText {
                            let classified = Self.classifySkills(instructionsText)
                            pendingRiskySkills = classified.risky
                            pendingForbiddenSkills = classified.forbidden
                        }
                    }
                    if !didAssignSessionSkills {
                        let tsText = obj["timestamp"] as? String
                            ?? payload?["timestamp"] as? String
                        if let tsText,
                           let dayKey = Self.dayKeyFromTimestamp(tsText) ?? Self.dayKeyFromParsedISO(tsText)
                        {
                            assignSessionSkillsIfNeeded(dayKey: dayKey)
                        }
                    }
                    return
                }

                guard let tsText = obj["timestamp"] as? String else { return }
                guard let dayKey = Self.dayKeyFromTimestamp(tsText) ?? Self.dayKeyFromParsedISO(tsText) else { return }

                if type == "turn_context" {
                    if let payload = obj["payload"] as? [String: Any] {
                        if let model = payload["model"] as? String {
                            currentModel = model
                        } else if let info = payload["info"] as? [String: Any], let model = info["model"] as? String {
                            currentModel = model
                        }
                        currentApprovalPolicy = Self.normalizedContextLabel(payload["approval_policy"] as? String)
                        currentSandboxMode = Self.codexSandboxMode(from: payload["sandbox_policy"])
                        currentEffort = Self.codexEffortLevel(from: payload)
                        assignSessionSkillsIfNeeded(dayKey: dayKey)
                    }
                    return
                }

                guard type == "event_msg" else { return }
                guard let payload = obj["payload"] as? [String: Any] else { return }
                guard (payload["type"] as? String) == "token_count" else { return }

                let info = payload["info"] as? [String: Any]
                let modelFromInfo = info?["model"] as? String
                    ?? info?["model_name"] as? String
                    ?? payload["model"] as? String
                    ?? obj["model"] as? String
                let model = modelFromInfo ?? currentModel ?? "gpt-5"

                func toInt(_ v: Any?) -> Int {
                    if let n = v as? NSNumber { return n.intValue }
                    return 0
                }

                let total = (info?["total_token_usage"] as? [String: Any])
                let last = (info?["last_token_usage"] as? [String: Any])

                var deltaInput = 0
                var deltaCached = 0
                var deltaOutput = 0
                var deltaReasoningOutput = 0

                if let total {
                    let input = toInt(total["input_tokens"])
                    let cached = toInt(total["cached_input_tokens"] ?? total["cache_read_input_tokens"])
                    let output = toInt(total["output_tokens"])
                    let reasoningOutput = toInt(total["reasoning_output_tokens"] ?? total["reasoning_tokens"])

                    let prev = previousTotals
                    deltaInput = max(0, input - (prev?.input ?? 0))
                    deltaCached = max(0, cached - (prev?.cached ?? 0))
                    deltaOutput = max(0, output - (prev?.output ?? 0))
                    deltaReasoningOutput = max(0, reasoningOutput - (prev?.reasoningOutput ?? 0))
                    previousTotals = CostUsageCodexTotals(
                        input: input,
                        cached: cached,
                        output: output,
                        reasoningOutput: reasoningOutput)
                } else if let last {
                    deltaInput = max(0, toInt(last["input_tokens"]))
                    deltaCached = max(0, toInt(last["cached_input_tokens"] ?? last["cache_read_input_tokens"]))
                    deltaOutput = max(0, toInt(last["output_tokens"]))
                    deltaReasoningOutput = max(0, toInt(last["reasoning_output_tokens"] ?? last["reasoning_tokens"]))
                } else {
                    return
                }

                if deltaInput == 0, deltaCached == 0, deltaOutput == 0, deltaReasoningOutput == 0 { return }
                let cachedClamp = min(deltaCached, deltaInput)
                add(
                    dayKey: dayKey,
                    model: model,
                    delta: TokenDelta(
                        input: deltaInput,
                        cached: cachedClamp,
                        output: deltaOutput,
                        reasoningOutput: deltaReasoningOutput))
                addContext(
                    dayKey: dayKey,
                    approvalPolicy: currentApprovalPolicy,
                    sandboxMode: currentSandboxMode,
                    effort: currentEffort)
                assignSessionSkillsIfNeeded(dayKey: dayKey)
            })) ?? startOffset

        return CodexParseResult(
            days: days,
            codexContextDays: codexContextDays,
            parsedBytes: parsedBytes,
            lastModel: currentModel,
            lastTotals: previousTotals,
            lastApprovalPolicy: currentApprovalPolicy,
            lastSandboxMode: currentSandboxMode,
            lastEffort: currentEffort,
            sessionId: sessionId)
    }

    private static func scanCodexFile(
        fileURL: URL,
        range: CostUsageDayRange,
        cache: inout CostUsageCache,
        state: inout CodexScanState)
    {
        let path = fileURL.path
        let attrs = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtimeMs = Int64(mtime * 1000)
        let fileId = Self.fileIdentityString(fileURL: fileURL)

        func dropCachedFile(_ cached: CostUsageFileUsage?) {
            if let cached {
                Self.applyFileDays(cache: &cache, fileDays: cached.days, sign: -1)
                if let contextDays = cached.codexContextDays {
                    Self.applyCodexContextDays(cache: &cache, fileDays: contextDays, sign: -1)
                }
            }
            cache.files.removeValue(forKey: path)
        }

        if let fileId, state.seenFileIds.contains(fileId) {
            dropCachedFile(cache.files[path])
            return
        }

        let cached = cache.files[path]
        if let cachedSessionId = cached?.sessionId, state.seenSessionIds.contains(cachedSessionId) {
            dropCachedFile(cached)
            return
        }

        let needsSessionId = cached != nil && cached?.sessionId == nil
        if let cached,
           cached.mtimeUnixMs == mtimeMs,
           cached.size == size,
           !needsSessionId
        {
            if let cachedSessionId = cached.sessionId {
                state.seenSessionIds.insert(cachedSessionId)
            }
            if let fileId {
                state.seenFileIds.insert(fileId)
            }
            return
        }

        if let cached, cached.sessionId != nil {
            let startOffset = cached.parsedBytes ?? cached.size
            let canIncremental = size > cached.size && startOffset > 0 && startOffset <= size
                && cached.lastTotals != nil
            if canIncremental {
                let delta = Self.parseCodexFile(
                    fileURL: fileURL,
                    range: range,
                    startOffset: startOffset,
                    initialModel: cached.lastModel,
                    initialTotals: cached.lastTotals,
                    initialApprovalPolicy: cached.lastApprovalPolicy,
                    initialSandboxMode: cached.lastSandboxMode,
                    initialEffort: cached.lastEffort)
                let sessionId = delta.sessionId ?? cached.sessionId
                if let sessionId, state.seenSessionIds.contains(sessionId) {
                    dropCachedFile(cached)
                    return
                }

                if !delta.days.isEmpty {
                    Self.applyFileDays(cache: &cache, fileDays: delta.days, sign: 1)
                }
                if !delta.codexContextDays.isEmpty {
                    Self.applyCodexContextDays(cache: &cache, fileDays: delta.codexContextDays, sign: 1)
                }

                var mergedDays = cached.days
                Self.mergeFileDays(existing: &mergedDays, delta: delta.days)
                var mergedContextDays = cached.codexContextDays ?? [:]
                Self.mergeCodexContextDays(existing: &mergedContextDays, delta: delta.codexContextDays)
                cache.files[path] = Self.makeFileUsage(
                    mtimeUnixMs: mtimeMs,
                    size: size,
                    days: mergedDays,
                    codexContextDays: mergedContextDays.isEmpty ? nil : mergedContextDays,
                    parsedBytes: delta.parsedBytes,
                    lastModel: delta.lastModel,
                    lastTotals: delta.lastTotals,
                    lastApprovalPolicy: delta.lastApprovalPolicy,
                    lastSandboxMode: delta.lastSandboxMode,
                    lastEffort: delta.lastEffort,
                    sessionId: sessionId)
                if let sessionId {
                    state.seenSessionIds.insert(sessionId)
                }
                if let fileId {
                    state.seenFileIds.insert(fileId)
                }
                return
            }
        }

        if let cached {
            Self.applyFileDays(cache: &cache, fileDays: cached.days, sign: -1)
            if let contextDays = cached.codexContextDays {
                Self.applyCodexContextDays(cache: &cache, fileDays: contextDays, sign: -1)
            }
        }

        let parsed = Self.parseCodexFile(fileURL: fileURL, range: range)
        let sessionId = parsed.sessionId ?? cached?.sessionId
        if let sessionId, state.seenSessionIds.contains(sessionId) {
            cache.files.removeValue(forKey: path)
            return
        }

        let usage = Self.makeFileUsage(
            mtimeUnixMs: mtimeMs,
            size: size,
            days: parsed.days,
            codexContextDays: parsed.codexContextDays.isEmpty ? nil : parsed.codexContextDays,
            parsedBytes: parsed.parsedBytes,
            lastModel: parsed.lastModel,
            lastTotals: parsed.lastTotals,
            lastApprovalPolicy: parsed.lastApprovalPolicy,
            lastSandboxMode: parsed.lastSandboxMode,
            lastEffort: parsed.lastEffort,
            sessionId: sessionId)
        cache.files[path] = usage
        Self.applyFileDays(cache: &cache, fileDays: usage.days, sign: 1)
        if let contextDays = usage.codexContextDays {
            Self.applyCodexContextDays(cache: &cache, fileDays: contextDays, sign: 1)
        }
        if let sessionId {
            state.seenSessionIds.insert(sessionId)
        }
        if let fileId {
            state.seenFileIds.insert(fileId)
        }
    }

    private static func loadCodexDaily(range: CostUsageDayRange, now: Date, options: Options) -> CostUsageDailyReport {
        var cache = CostUsageCacheIO.load(provider: .codex, cacheRoot: options.cacheRoot)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)

        let refreshMs = Int64(max(0, options.refreshMinIntervalSeconds) * 1000)
        let shouldRefresh = refreshMs == 0 || cache.lastScanUnixMs == 0 || nowMs - cache.lastScanUnixMs > refreshMs

        let roots = self.codexSessionsRoots(options: options)
        var seenPaths: Set<String> = []
        var files: [URL] = []
        for root in roots {
            let rootFiles = Self.listCodexSessionFiles(
                root: root,
                scanSinceKey: range.scanSinceKey,
                scanUntilKey: range.scanUntilKey)
            for fileURL in rootFiles.sorted(by: { $0.path < $1.path }) where !seenPaths.contains(fileURL.path) {
                seenPaths.insert(fileURL.path)
                files.append(fileURL)
            }
        }
        let filePathsInScan = Set(files.map(\.path))

        if shouldRefresh {
            if options.forceRescan {
                cache = CostUsageCache()
            }
            var scanState = CodexScanState()
            for fileURL in files {
                Self.scanCodexFile(
                    fileURL: fileURL,
                    range: range,
                    cache: &cache,
                    state: &scanState)
            }

            for key in cache.files.keys where !filePathsInScan.contains(key) {
                if let old = cache.files[key] {
                    Self.applyFileDays(cache: &cache, fileDays: old.days, sign: -1)
                    if let contextDays = old.codexContextDays {
                        Self.applyCodexContextDays(cache: &cache, fileDays: contextDays, sign: -1)
                    }
                }
                cache.files.removeValue(forKey: key)
            }

            Self.pruneDays(cache: &cache, sinceKey: range.scanSinceKey, untilKey: range.scanUntilKey)
            Self.pruneCodexContextDays(cache: &cache, sinceKey: range.scanSinceKey, untilKey: range.scanUntilKey)
            cache.lastScanUnixMs = nowMs
            CostUsageCacheIO.save(provider: .codex, cache: cache, cacheRoot: options.cacheRoot)
        }

        return Self.buildCodexReportFromCache(cache: cache, range: range)
    }

    private static func buildCodexReportFromCache(
        cache: CostUsageCache,
        range: CostUsageDayRange) -> CostUsageDailyReport
    {
        var entries: [CostUsageDailyReport.Entry] = []
        var totalInput = 0
        var totalOutput = 0
        var totalTokens = 0
        var totalReasoningOutput = 0
        var totalCost: Double = 0
        var costSeen = false

        let dayKeys = cache.days.keys.sorted().filter {
            CostUsageDayRange.isInRange(dayKey: $0, since: range.sinceKey, until: range.untilKey)
        }

        for day in dayKeys {
            guard let models = cache.days[day] else { continue }
            let modelNames = models.keys.sorted()

            var dayInput = 0
            var dayOutput = 0
            var dayReasoningOutput = 0

            var breakdown: [CostUsageDailyReport.ModelBreakdown] = []
            var dayCost: Double = 0
            var dayCostSeen = false

            for model in modelNames {
                let packed = models[model] ?? [0, 0, 0, 0]
                let input = packed[safe: 0] ?? 0
                let cached = packed[safe: 1] ?? 0
                let output = packed[safe: 2] ?? 0
                let reasoningOutput = packed[safe: 3] ?? 0

                dayInput += input
                dayOutput += output
                dayReasoningOutput += reasoningOutput

                let cost = CostUsagePricing.codexCostUSD(
                    model: model,
                    inputTokens: input,
                    cachedInputTokens: cached,
                    outputTokens: output)
                breakdown.append(CostUsageDailyReport.ModelBreakdown(
                    modelName: model,
                    costUSD: cost,
                    inputTokens: input,
                    outputTokens: output,
                    cacheReadTokens: cached,
                    reasoningOutputTokens: reasoningOutput,
                    totalTokens: input + output))
                if let cost {
                    dayCost += cost
                    dayCostSeen = true
                }
            }

            breakdown.sort { lhs, rhs in (rhs.costUSD ?? -1) < (lhs.costUSD ?? -1) }

            let dayTotal = dayInput + dayOutput
            let entryCost = dayCostSeen ? dayCost : nil
            let context = cache.codexContextDays?[day]
            entries.append(CostUsageDailyReport.Entry(
                date: day,
                inputTokens: dayInput,
                outputTokens: dayOutput,
                totalTokens: dayTotal,
                costUSD: entryCost,
                modelsUsed: modelNames,
                modelBreakdowns: breakdown.isEmpty ? nil : breakdown,
                reasoningOutputTokens: dayReasoningOutput > 0 ? dayReasoningOutput : nil,
                approvalPolicyBreakdowns: Self.countBreakdowns(from: context?.approvalPolicies),
                sandboxModeBreakdowns: Self.countBreakdowns(from: context?.sandboxModes),
                effortBreakdowns: Self.countBreakdowns(from: context?.effortLevels),
                riskySkillBreakdowns: Self.countBreakdowns(from: context?.riskySkills),
                forbiddenSkillBreakdowns: Self.countBreakdowns(from: context?.forbiddenSkills)))

            totalInput += dayInput
            totalOutput += dayOutput
            totalTokens += dayTotal
            totalReasoningOutput += dayReasoningOutput
            if let entryCost {
                totalCost += entryCost
                costSeen = true
            }
        }

        let summary: CostUsageDailyReport.Summary? = entries.isEmpty
            ? nil
            : CostUsageDailyReport.Summary(
                totalInputTokens: totalInput,
                totalOutputTokens: totalOutput,
                totalTokens: totalTokens,
                totalCostUSD: costSeen ? totalCost : nil,
                totalReasoningOutputTokens: totalReasoningOutput > 0 ? totalReasoningOutput : nil)

        return CostUsageDailyReport(data: entries, summary: summary)
    }

    // MARK: - Shared cache mutations

    static func makeFileUsage(
        mtimeUnixMs: Int64,
        size: Int64,
        days: [String: [String: [Int]]],
        codexContextDays: [String: CostUsageCodexContextDay]? = nil,
        parsedBytes: Int64?,
        lastModel: String? = nil,
        lastTotals: CostUsageCodexTotals? = nil,
        lastApprovalPolicy: String? = nil,
        lastSandboxMode: String? = nil,
        lastEffort: String? = nil,
        sessionId: String? = nil) -> CostUsageFileUsage
    {
        CostUsageFileUsage(
            mtimeUnixMs: mtimeUnixMs,
            size: size,
            days: days,
            codexContextDays: codexContextDays,
            parsedBytes: parsedBytes,
            lastModel: lastModel,
            lastTotals: lastTotals,
            lastApprovalPolicy: lastApprovalPolicy,
            lastSandboxMode: lastSandboxMode,
            lastEffort: lastEffort,
            sessionId: sessionId)
    }

    static func mergeFileDays(
        existing: inout [String: [String: [Int]]],
        delta: [String: [String: [Int]]])
    {
        for (day, models) in delta {
            var dayModels = existing[day] ?? [:]
            for (model, packed) in models {
                let existingPacked = dayModels[model] ?? []
                let merged = Self.addPacked(a: existingPacked, b: packed, sign: 1)
                if merged.allSatisfy({ $0 == 0 }) {
                    dayModels.removeValue(forKey: model)
                } else {
                    dayModels[model] = merged
                }
            }

            if dayModels.isEmpty {
                existing.removeValue(forKey: day)
            } else {
                existing[day] = dayModels
            }
        }
    }

    static func mergeCodexContextDays(
        existing: inout [String: CostUsageCodexContextDay],
        delta: [String: CostUsageCodexContextDay])
    {
        for (day, next) in delta {
            var merged = existing[day] ?? CostUsageCodexContextDay()
            merged.approvalPolicies = Self.mergeCountMap(merged.approvalPolicies, delta: next.approvalPolicies, sign: 1)
            merged.sandboxModes = Self.mergeCountMap(merged.sandboxModes, delta: next.sandboxModes, sign: 1)
            merged.effortLevels = Self.mergeCountMap(merged.effortLevels, delta: next.effortLevels, sign: 1)
            merged.riskySkills = Self.mergeCountMap(merged.riskySkills, delta: next.riskySkills, sign: 1)
            merged.forbiddenSkills = Self.mergeCountMap(merged.forbiddenSkills, delta: next.forbiddenSkills, sign: 1)
            if merged.isEmpty {
                existing.removeValue(forKey: day)
            } else {
                existing[day] = merged
            }
        }
    }

    static func applyFileDays(cache: inout CostUsageCache, fileDays: [String: [String: [Int]]], sign: Int) {
        for (day, models) in fileDays {
            var dayModels = cache.days[day] ?? [:]
            for (model, packed) in models {
                let existing = dayModels[model] ?? []
                let merged = Self.addPacked(a: existing, b: packed, sign: sign)
                if merged.allSatisfy({ $0 == 0 }) {
                    dayModels.removeValue(forKey: model)
                } else {
                    dayModels[model] = merged
                }
            }

            if dayModels.isEmpty {
                cache.days.removeValue(forKey: day)
            } else {
                cache.days[day] = dayModels
            }
        }
    }

    static func applyCodexContextDays(
        cache: inout CostUsageCache,
        fileDays: [String: CostUsageCodexContextDay],
        sign: Int)
    {
        var all = cache.codexContextDays ?? [:]
        for (day, next) in fileDays {
            var merged = all[day] ?? CostUsageCodexContextDay()
            merged.approvalPolicies = Self.mergeCountMap(
                merged.approvalPolicies,
                delta: next.approvalPolicies,
                sign: sign)
            merged.sandboxModes = Self.mergeCountMap(merged.sandboxModes, delta: next.sandboxModes, sign: sign)
            merged.effortLevels = Self.mergeCountMap(merged.effortLevels, delta: next.effortLevels, sign: sign)
            merged.riskySkills = Self.mergeCountMap(merged.riskySkills, delta: next.riskySkills, sign: sign)
            merged.forbiddenSkills = Self.mergeCountMap(merged.forbiddenSkills, delta: next.forbiddenSkills, sign: sign)
            if merged.isEmpty {
                all.removeValue(forKey: day)
            } else {
                all[day] = merged
            }
        }
        cache.codexContextDays = all.isEmpty ? nil : all
    }

    static func pruneDays(cache: inout CostUsageCache, sinceKey: String, untilKey: String) {
        for key in cache.days.keys where !CostUsageDayRange.isInRange(dayKey: key, since: sinceKey, until: untilKey) {
            cache.days.removeValue(forKey: key)
        }
    }

    static func pruneCodexContextDays(cache: inout CostUsageCache, sinceKey: String, untilKey: String) {
        guard var all = cache.codexContextDays else { return }
        for key in all.keys where !CostUsageDayRange.isInRange(dayKey: key, since: sinceKey, until: untilKey) {
            all.removeValue(forKey: key)
        }
        cache.codexContextDays = all.isEmpty ? nil : all
    }

    private static func mergeCountMap(_ base: [String: Int], delta: [String: Int], sign: Int) -> [String: Int] {
        var out = base
        for (key, value) in delta {
            let next = (out[key] ?? 0) + sign * max(0, value)
            if next <= 0 {
                out.removeValue(forKey: key)
            } else {
                out[key] = next
            }
        }
        return out
    }

    static func addPacked(a: [Int], b: [Int], sign: Int) -> [Int] {
        let len = max(a.count, b.count)
        var out: [Int] = Array(repeating: 0, count: len)
        for idx in 0..<len {
            let next = (a[safe: idx] ?? 0) + sign * (b[safe: idx] ?? 0)
            out[idx] = max(0, next)
        }
        return out
    }

    private static func countBreakdowns(from map: [String: Int]?) -> [CostUsageDailyReport.CountBreakdown]? {
        guard let map else { return nil }
        let values = map
            .compactMap { key, count -> CostUsageDailyReport.CountBreakdown? in
                let normalized = Self.normalizedContextLabel(key)
                guard let normalized else { return nil }
                guard count > 0 else { return nil }
                return CostUsageDailyReport.CountBreakdown(name: normalized, count: count)
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.name < rhs.name }
                return lhs.count > rhs.count
            }
        return values.isEmpty ? nil : values
    }

    private static func normalizedContextLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= 64 { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 64)
        return String(trimmed[..<idx])
    }

    private static func codexSandboxMode(from raw: Any?) -> String? {
        if let mode = raw as? String {
            return self.normalizedContextLabel(mode)
        }
        guard let dict = raw as? [String: Any] else { return nil }
        let mode = dict["mode"] as? String
            ?? dict["type"] as? String
        return Self.normalizedContextLabel(mode)
    }

    private static func codexEffortLevel(from payload: [String: Any]) -> String? {
        if let effort = payload["effort"] as? String {
            return self.normalizedContextLabel(effort)
        }
        if let collaborationMode = payload["collaboration_mode"] as? [String: Any],
           let settings = collaborationMode["settings"] as? [String: Any],
           let effort = settings["reasoning_effort"] as? String
        {
            return Self.normalizedContextLabel(effort)
        }
        return nil
    }

    private static let forbiddenSkillKeywords: [String] = [
        "forbidden",
        "must not",
        "do not",
        "never use",
        "out of scope",
        "blocked",
    ]

    private static let riskySkillKeywords: [String] = [
        "approval",
        "private repo",
        "private repos",
        "service role",
        "token",
        "credential",
        "install",
        "notarize",
        "release",
        "destructive",
        "network",
    ]

    private static func classifySkills(_ text: String) -> (risky: [String: Int], forbidden: [String: Int]) {
        var risky: [String: Int] = [:]
        var forbidden: [String: Int] = [:]

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("- ") else { continue }
            guard line.contains("(file:") else { continue }
            guard let skill = Self.parseSkillName(from: line) else { continue }
            let lower = line.lowercased()

            if Self.forbiddenSkillKeywords.contains(where: { lower.contains($0) }) {
                forbidden[skill] = 1
            }
            if Self.riskySkillKeywords.contains(where: { lower.contains($0) }) {
                risky[skill] = 1
            }
        }

        return (risky: risky, forbidden: forbidden)
    }

    private static func parseSkillName(from line: String) -> String? {
        guard line.hasPrefix("- ") else { return nil }
        let trimmed = String(line.dropFirst(2))
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let name = trimmed[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.range(of: #"^[A-Za-z0-9._-]{1,64}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return name
    }

    // MARK: - Date parsing

    private static func parseDayKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3 else { return nil }
        guard
            let y = Int(parts[0]),
            let m = Int(parts[1]),
            let d = Int(parts[2])
        else { return nil }

        var comps = DateComponents()
        comps.calendar = Calendar.current
        comps.timeZone = TimeZone.current
        comps.year = y
        comps.month = m
        comps.day = d
        comps.hour = 12
        return comps.date
    }
}

// swiftlint:enable type_body_length

extension Data {
    func containsAscii(_ needle: String) -> Bool {
        guard let n = needle.data(using: .utf8) else { return false }
        return self.range(of: n) != nil
    }
}

extension [Int] {
    subscript(safe index: Int) -> Int? {
        if index < 0 { return nil }
        if index >= self.count { return nil }
        return self[index]
    }
}

extension [UInt8] {
    subscript(safe index: Int) -> UInt8? {
        if index < 0 { return nil }
        if index >= self.count { return nil }
        return self[index]
    }
}

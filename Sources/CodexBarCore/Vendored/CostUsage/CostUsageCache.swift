import Foundation

enum CostUsageCacheIO {
    private static func defaultCacheRoot() -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("CodexBar", isDirectory: true)
    }

    static func cacheFileURL(provider: UsageProvider, cacheRoot: URL? = nil) -> URL {
        let root = cacheRoot ?? self.defaultCacheRoot()
        return root
            .appendingPathComponent("cost-usage", isDirectory: true)
            .appendingPathComponent("\(provider.rawValue)-v1.json", isDirectory: false)
    }

    static func load(provider: UsageProvider, cacheRoot: URL? = nil) -> CostUsageCache {
        let url = self.cacheFileURL(provider: provider, cacheRoot: cacheRoot)
        if let decoded = self.loadCache(at: url) { return decoded }
        return CostUsageCache()
    }

    private static func loadCache(at url: URL) -> CostUsageCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let decoded = try? JSONDecoder().decode(CostUsageCache.self, from: data)
        else { return nil }
        guard decoded.version == 1 else { return nil }
        return decoded
    }

    static func save(provider: UsageProvider, cache: CostUsageCache, cacheRoot: URL? = nil) {
        let url = self.cacheFileURL(provider: provider, cacheRoot: cacheRoot)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let tmp = dir.appendingPathComponent(".tmp-\(UUID().uuidString).json", isDirectory: false)
        let data = (try? JSONEncoder().encode(cache)) ?? Data()
        do {
            try data.write(to: tmp, options: [.atomic])
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}

struct CostUsageCache: Codable, Sendable {
    var version: Int = 1
    var lastScanUnixMs: Int64 = 0

    /// filePath -> file usage
    var files: [String: CostUsageFileUsage] = [:]

    /// dayKey -> model -> packed usage
    var days: [String: [String: [Int]]] = [:]

    /// Codex-only context counters aggregated by day.
    var codexContextDays: [String: CostUsageCodexContextDay]?

    /// rootPath -> mtime (for Claude roots)
    var roots: [String: Int64]?
}

struct CostUsageFileUsage: Codable, Sendable {
    var mtimeUnixMs: Int64
    var size: Int64
    var days: [String: [String: [Int]]]
    var codexContextDays: [String: CostUsageCodexContextDay]?
    var parsedBytes: Int64?
    var lastModel: String?
    var lastTotals: CostUsageCodexTotals?
    var lastApprovalPolicy: String?
    var lastSandboxMode: String?
    var lastEffort: String?
    var sessionId: String?
}

struct CostUsageCodexContextDay: Codable, Sendable {
    var approvalPolicies: [String: Int] = [:]
    var sandboxModes: [String: Int] = [:]
    var effortLevels: [String: Int] = [:]
    var riskySkills: [String: Int] = [:]
    var forbiddenSkills: [String: Int] = [:]

    var isEmpty: Bool {
        self.approvalPolicies.isEmpty
            && self.sandboxModes.isEmpty
            && self.effortLevels.isEmpty
            && self.riskySkills.isEmpty
            && self.forbiddenSkills.isEmpty
    }
}

struct CostUsageCodexTotals: Codable, Sendable {
    var input: Int
    var cached: Int
    var output: Int
    var reasoningOutput: Int

    private enum CodingKeys: String, CodingKey {
        case input
        case cached
        case output
        case reasoningOutput
    }

    init(input: Int, cached: Int, output: Int, reasoningOutput: Int = 0) {
        self.input = input
        self.cached = cached
        self.output = output
        self.reasoningOutput = max(0, reasoningOutput)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.input = try container.decode(Int.self, forKey: .input)
        self.cached = try container.decode(Int.self, forKey: .cached)
        self.output = try container.decode(Int.self, forKey: .output)
        self.reasoningOutput = try max(0, container.decodeIfPresent(Int.self, forKey: .reasoningOutput) ?? 0)
    }
}

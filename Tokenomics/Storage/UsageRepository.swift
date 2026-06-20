import Foundation
import SwiftData

/// 对 SwiftData 的薄封装：插入去重、聚合统计、设置存取。
@MainActor
final class UsageRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Inserts

    @discardableResult
    func upsert(_ records: [UsageRecord]) -> Int {
        var inserted = 0
        for r in records {
            // 查询是否已有相同 dedupeKey
            let key = r.dedupeKey
            var fetch = FetchDescriptor<UsageRecord>(predicate: #Predicate { $0.dedupeKey == key })
            fetch.fetchLimit = 1
            if let existing = try? context.fetch(fetch), existing.isEmpty {
                context.insert(r)
                inserted += 1
            }
        }
        try? context.save()
        return inserted
    }

    // MARK: - Queries

    func fetchAll(limit: Int? = nil) -> [UsageRecord] {
        var fd = FetchDescriptor<UsageRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        if let limit { fd.fetchLimit = limit }
        return (try? context.fetch(fd)) ?? []
    }

    func fetch(since: Date, until: Date = Date()) -> [UsageRecord] {
        let fd = FetchDescriptor<UsageRecord>(
            predicate: #Predicate { $0.timestamp >= since && $0.timestamp <= until },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? context.fetch(fd)) ?? []
    }

    func fetchByProvider(_ provider: String) -> [UsageRecord] {
        let fd = FetchDescriptor<UsageRecord>(
            predicate: #Predicate { $0.provider == provider },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? context.fetch(fd)) ?? []
    }

    // MARK: - Collector State

    func loadState(collectorId: String) -> CollectorState? {
        var fd = FetchDescriptor<CollectorState>(predicate: #Predicate { $0.collectorId == collectorId })
        fd.fetchLimit = 1
        return try? context.fetch(fd).first
    }

    func saveState(_ state: CollectorState) {
        if loadState(collectorId: state.collectorId) == nil {
            context.insert(state)
        }
        try? context.save()
    }

    // MARK: - Pricing Override

    func fetchAllPricingOverrides() -> [PricingOverride] {
        let fd = FetchDescriptor<PricingOverride>(sortBy: [SortDescriptor(\.key)])
        return (try? context.fetch(fd)) ?? []
    }

    func upsertPricingOverride(_ override: PricingOverride) {
        let key = override.key
        var fd = FetchDescriptor<PricingOverride>(predicate: #Predicate { $0.key == key })
        fd.fetchLimit = 1
        if let existing = try? context.fetch(fd).first {
            existing.inputPer1M = override.inputPer1M
            existing.outputPer1M = override.outputPer1M
            existing.cacheWritePer1M = override.cacheWritePer1M
            existing.cacheReadPer1M = override.cacheReadPer1M
        } else {
            context.insert(override)
        }
        try? context.save()
    }

    func deletePricingOverride(key: String) {
        var fd = FetchDescriptor<PricingOverride>(predicate: #Predicate { $0.key == key })
        fd.fetchLimit = 1
        if let existing = try? context.fetch(fd).first {
            context.delete(existing)
            try? context.save()
        }
    }

    // MARK: - Custom Provider

    func fetchAllCustomProviders() -> [CustomProvider] {
        let fd = FetchDescriptor<CustomProvider>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(fd)) ?? []
    }

    func insertCustomProvider(_ provider: CustomProvider) {
        context.insert(provider)
        try? context.save()
    }

    func saveCustomProvider(_ provider: CustomProvider) {
        // @Model 实例修改后只需 save 即可
        try? context.save()
    }

    func deleteCustomProvider(id: String) {
        var fd = FetchDescriptor<CustomProvider>(predicate: #Predicate { $0.id == id })
        fd.fetchLimit = 1
        if let existing = try? context.fetch(fd).first {
            context.delete(existing)
            try? context.save()
        }
    }

    // MARK: - Cost Backfill

    /// 用当前定价表为历史 costUSD == 0 的记录回填费用。
    /// 通常在 PricingTable 更新或定价 override 变更后调用一次。
    @discardableResult
    func backfillMissingCosts(using pricing: PricingService) -> Int {
        let fd = FetchDescriptor<UsageRecord>(predicate: #Predicate { $0.costUSD == 0 })
        guard let records = try? context.fetch(fd) else { return 0 }
        var updated = 0
        for r in records {
            let c = pricing.cost(
                provider: r.provider,
                model: r.model,
                input: r.inputTokens,
                output: r.outputTokens,
                cacheCreation: r.cacheCreationTokens,
                cacheCreation1h: r.cacheCreation1hTokens,
                cacheRead: r.cacheReadTokens
            )
            if c > 0 {
                r.costUSD = c
                updated += 1
            }
        }
        if updated > 0 { try? context.save() }
        return updated
    }

    // MARK: - Claude Code Migration

    /// 旧版本 ClaudeCodeCollector 的 normalize 会把 "claude-opus-4-6/4-7/4-8" 这类
    /// 真实型号全部塌缩到 "claude-opus-4"（haiku/sonnet 同理）。
    /// 一旦这种被截断的脏数据进了 SwiftData，新版本仅靠 upsert 是无法纠正的，
    /// 因为 dedupeKey 已经存在、记录会被直接跳过。
    ///
    /// 这里做一次性迁移：检测到任意 sourceApp == "Claude Code" 的记录里有"被截断的旧型号名"，
    /// 就把 ClaudeCode 这一供应商的全部历史删掉，并清空其 CollectorState，
    /// 让 RefreshScheduler 下一轮以最新 normalize 全量重新解析 ~/.claude/projects。
    ///
    /// 返回被清理掉的记录条数（0 表示无需迁移）。
    @discardableResult
    func migrateClaudeCodeIfNeeded() -> Int {
        // 这些是"被旧 normalize 截断"的型号标记。
        // 注意：真实 jsonl 里 model 字段总是带 -4-5/-4-6/... 或日期后缀，
        // 所以裸的 "claude-opus-4" / "claude-haiku-4" / "claude-sonnet-4" 一定是旧数据。
        let truncated: Set<String> = ["claude-opus-4", "claude-haiku-4", "claude-sonnet-4"]
        let app = "Claude Code"
        let fd = FetchDescriptor<UsageRecord>(predicate: #Predicate { $0.sourceApp == app })
        guard let claudeRecords = try? context.fetch(fd) else { return 0 }
        let needsMigration = claudeRecords.contains { truncated.contains($0.model) }
        guard needsMigration else { return 0 }
        let count = claudeRecords.count
        for r in claudeRecords { context.delete(r) }
        // 同步清空 ClaudeCode collector 的游标，让下次 refresh 全量重解析
        var stateFd = FetchDescriptor<CollectorState>(predicate: #Predicate { $0.collectorId == "claude-code" })
        stateFd.fetchLimit = 1
        if let st = try? context.fetch(stateFd).first {
            st.lastRunAt = nil
            st.cursorPayload = nil
            st.lastError = nil
        }
        try? context.save()
        return count
    }

    /// 一次性迁移：旧版本未解析 1 小时缓存写入（usage.cache_creation.ephemeral_1h_input_tokens），
    /// 导致 Claude Code 的缓存写入全部按 5 分钟价计费，费用被系统性低估。
    /// 这里删除全部 Claude Code 历史记录并清空其游标，让下一轮 refresh 全量重解析，
    /// 重新带上 1h token 字段并按 2× 输入价正确计费。由调用方用一次性标志位 gate。
    ///
    /// 返回被清理掉的记录条数。
    @discardableResult
    func resetClaudeCodeRecordsForReparse() -> Int {
        let app = "Claude Code"
        let fd = FetchDescriptor<UsageRecord>(predicate: #Predicate { $0.sourceApp == app })
        guard let records = try? context.fetch(fd) else { return 0 }
        let count = records.count
        for r in records { context.delete(r) }
        var stateFd = FetchDescriptor<CollectorState>(predicate: #Predicate { $0.collectorId == "claude-code" })
        stateFd.fetchLimit = 1
        if let st = try? context.fetch(stateFd).first {
            st.lastRunAt = nil
            st.cursorPayload = nil
            st.lastError = nil
        }
        try? context.save()
        return count
    }
}

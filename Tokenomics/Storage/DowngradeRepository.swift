import Foundation
import SwiftData

/// `DowngradeSignal` 事件的持久化封装。
///
/// 与 `UsageRepository` 分开的原因：
/// - 事件量可能很大（每次 Claude Code 会话都可能触发一次被动检测），需要独立滚动清理策略；
/// - 语义完全不同（观察事件 vs. 计费用量），耦合会污染 `UsageRepository` 的公开面。
@MainActor
final class DowngradeRepository {
    let context: ModelContext
    /// 保留窗口（秒）。超出的旧事件会在 append 时被清理。
    private let retention: TimeInterval

    init(context: ModelContext, retentionDays: Int = 30) {
        self.context = context
        self.retention = TimeInterval(retentionDays) * 24 * 3600
    }

    // MARK: - Writes

    /// 追加一条事件。同一秒内如果已经有一条 "requestedModel + servedModel + source" 完全相同的记录，
    /// 视为重复，直接跳过。这样即便 collector 反复重跑也不会灌爆事件表。
    @discardableResult
    func append(_ signal: DowngradeSignal) -> Bool {
        let ts = signal.timestamp
        let bucket = Int(ts.timeIntervalSince1970)      // 秒级桶
        let src = signal.sourceRaw
        let req = signal.requestedModel
        let served = signal.servedModel

        var fd = FetchDescriptor<DowngradeSignal>(
            predicate: #Predicate {
                $0.sourceRaw == src
                    && $0.requestedModel == req
                    && $0.servedModel == served
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        fd.fetchLimit = 5
        if let existing = try? context.fetch(fd) {
            for e in existing {
                if Int(e.timestamp.timeIntervalSince1970) == bucket {
                    return false
                }
            }
        }

        context.insert(signal)
        try? context.save()
        rotateIfNeeded()
        return true
    }

    /// 清理超过保留窗口的旧事件。低成本，可在每次 append 后调用。
    private func rotateIfNeeded() {
        let cutoff = Date().addingTimeInterval(-retention)
        let fd = FetchDescriptor<DowngradeSignal>(
            predicate: #Predicate { $0.timestamp < cutoff }
        )
        guard let stale = try? context.fetch(fd), !stale.isEmpty else { return }
        for s in stale { context.delete(s) }
        try? context.save()
    }

    // MARK: - Reads

    func fetchAll(limit: Int? = nil) -> [DowngradeSignal] {
        var fd = FetchDescriptor<DowngradeSignal>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        if let limit { fd.fetchLimit = limit }
        return (try? context.fetch(fd)) ?? []
    }

    func fetchRecent(days: Int = 7) -> [DowngradeSignal] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(days) * 24 * 3600)
        let fd = FetchDescriptor<DowngradeSignal>(
            predicate: #Predicate { $0.timestamp >= cutoff },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? context.fetch(fd)) ?? []
    }

    /// 用于 Dashboard 卡片的健康度：取最近 24h 内**最严重**的判定作为整体状态。
    func currentHealth(withinHours hours: Int = 24) -> DowngradeVerdict {
        let cutoff = Date().addingTimeInterval(-TimeInterval(hours) * 3600)
        let fd = FetchDescriptor<DowngradeSignal>(
            predicate: #Predicate { $0.timestamp >= cutoff }
        )
        guard let recent = try? context.fetch(fd), !recent.isEmpty else {
            return .clean
        }
        var worst: DowngradeVerdict = .clean
        for r in recent {
            let v = r.verdict
            if v == .downgraded { return .downgraded }
            if v == .suspicious { worst = .suspicious }
        }
        return worst
    }

    /// 全清（用于设置里的"重置"操作）。
    func deleteAll() {
        let fd = FetchDescriptor<DowngradeSignal>()
        guard let all = try? context.fetch(fd) else { return }
        for r in all { context.delete(r) }
        try? context.save()
    }
}

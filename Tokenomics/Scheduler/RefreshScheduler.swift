import Foundation

/// 调度所有 Collector：启动时全量拉取一次，之后每 5 分钟轮询。
@MainActor
final class RefreshScheduler {
    private let collectors: [UsageCollector]
    private let repository: UsageRepository
    private let pricing: PricingService
    private let interval: TimeInterval
    private let onLog: (String) -> Void
    private let onCycleComplete: (() async -> Void)?
    private var timer: Timer?
    private var inflight = false

    init(
        collectors: [UsageCollector],
        repository: UsageRepository,
        pricing: PricingService,
        interval: TimeInterval = 300,
        onLog: @escaping (String) -> Void = { _ in },
        onCycleComplete: (() async -> Void)? = nil
    ) {
        self.collectors = collectors
        self.repository = repository
        self.pricing = pricing
        self.interval = interval
        self.onLog = onLog
        self.onCycleComplete = onCycleComplete
    }

    func start() async {
        await refreshNow()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshNow()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refreshNow() async {
        guard !inflight else { return }
        inflight = true
        defer { inflight = false }
        onLog("开始拉取 (collectors=\(collectors.count))")
        // 先把历史 costUSD == 0 的记录按当前定价表回填一次，
        // 这样定价表更新或老版本入库的零值记录都会被即时修正。
        let backfilled = repository.backfillMissingCosts(using: pricing)
        if backfilled > 0 {
            onLog("↺ 历史费用回填 \(backfilled) 条")
        }
        for collector in collectors {
            guard collector.isEnabled else {
                continue
            }
            let state = repository.loadState(collectorId: collector.id)
            let since = state?.lastRunAt
            do {
                let records = try await collector.collect(since: since)
                // 计价补全（如果 Collector 没填 costUSD）
                for rec in records where rec.costUSD == 0 {
                    rec.costUSD = pricing.cost(
                        provider: rec.provider,
                        model: rec.model,
                        input: rec.inputTokens,
                        output: rec.outputTokens,
                        cacheCreation: rec.cacheCreationTokens,
                        cacheRead: rec.cacheReadTokens
                    )
                }
                let inserted = repository.upsert(records)
                let newState = CollectorState(
                    collectorId: collector.id,
                    lastRunAt: Date(),
                    lastError: nil
                )
                if let existing = state {
                    existing.lastRunAt = Date()
                    existing.lastError = nil
                    try? repository.context.save()
                } else {
                    repository.saveState(newState)
                }
                onLog("✓ \(collector.displayName)：拉取 \(records.count) 条，新增 \(inserted)")
            } catch {
                if let existing = state {
                    existing.lastError = "\(error)"
                    try? repository.context.save()
                } else {
                    repository.saveState(CollectorState(
                        collectorId: collector.id,
                        lastRunAt: nil,
                        lastError: "\(error)"
                    ))
                }
                onLog("✗ \(collector.displayName)：\(error.localizedDescription)")
            }
        }
        onLog("拉取完成")
        if let hook = onCycleComplete {
            await hook()
        }
    }
}

import Foundation

/// 所有数据采集器的统一接口。
/// 每个 Collector 负责单个 AI 工具/供应商的数据获取，并把结果归一为 UsageRecord 列表。
protocol UsageCollector: AnyObject {
    /// 全局唯一 ID，例如 "claude-code"、"openai-api"
    var id: String { get }
    /// 展示名称
    var displayName: String { get }
    /// 是否已就绪（例如 API Key 是否已配置 / 本地路径是否存在）
    var isEnabled: Bool { get }
    /// 拉取自指定时间以来的用量。idempotent。
    func collect(since: Date?) async throws -> [UsageRecord]
    /// 增量游标。Scheduler 在调用 collect 前注入上一次保存的 cursor，
    /// collect 完成后读取最新值写回 CollectorState.cursorPayload。
    /// 默认实现为 no-op，老 collector 不受影响。
    var cursorPayload: String? { get set }
}

extension UsageCollector {
    var defaultSince: Date {
        Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    }

    var cursorPayload: String? {
        get { nil }
        set { _ = newValue }
    }
}

/// Collector 注册中心：实例化所有可用 collector。
enum CollectorRegistry {
    @MainActor
    static func makeAll(keychain: KeychainService) -> [UsageCollector] {
        return [
            ClaudeCodeCollector(),
            OpenAIAPICollector(keychain: keychain),
            AnthropicAPICollector(keychain: keychain)
        ]
    }
}

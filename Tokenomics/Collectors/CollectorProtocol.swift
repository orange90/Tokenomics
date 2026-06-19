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
}

extension UsageCollector {
    var defaultSince: Date {
        Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    }
}

/// Collector 注册中心：实例化所有可用 collector。
enum CollectorRegistry {
    @MainActor
    static func makeAll(keychain: KeychainService) -> [UsageCollector] {
        return [
            ClaudeCodeCollector(),
            CursorCollector(),
            TraeSoloCollector(),
            QoderCollector(),
            OpenAIAPICollector(keychain: keychain),
            AnthropicAPICollector(keychain: keychain),
            DeepSeekCollector(keychain: keychain),
            GeminiAPICollector(keychain: keychain),
            QwenCollector(keychain: keychain, region: .china),
            QwenCollector(keychain: keychain, region: .international),
            SiliconFlowCollector(keychain: keychain),
            OpenRouterCollector(keychain: keychain),
            StepFunCollector(keychain: keychain),
            MimoCollector(keychain: keychain),
            KimiCollector(keychain: keychain),
            MiniMaxCollector(keychain: keychain),
            GLMCollector(keychain: keychain),
            VolcengineCollector(keychain: keychain)
        ]
    }
}

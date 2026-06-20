import Foundation
import SwiftData

@Model
final class UsageRecord {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var provider: String
    var model: String
    var sourceApp: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    /// cacheCreationTokens 中属于「1 小时 TTL」缓存写入的部分（是 cacheCreationTokens 的子集，不额外计入 totalTokens）。
    /// Anthropic 对 1h 缓存写入按 2× 输入价计费，5 分钟缓存按 1.25× 输入价；二者必须分别计价。
    var cacheCreation1hTokens: Int = 0
    var cacheReadTokens: Int
    var costUSD: Double
    var requestId: String?
    /// 复合去重键：requestId ?? "\(sourceApp)|\(timestamp.timeIntervalSince1970)|\(input)|\(output)"
    @Attribute(.unique) var dedupeKey: String

    init(
        id: UUID = UUID(),
        timestamp: Date,
        provider: String,
        model: String,
        sourceApp: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int = 0,
        cacheCreation1hTokens: Int = 0,
        cacheReadTokens: Int = 0,
        costUSD: Double = 0,
        requestId: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.provider = provider
        self.model = model
        self.sourceApp = sourceApp
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheCreation1hTokens = min(max(0, cacheCreation1hTokens), max(0, cacheCreationTokens))
        self.cacheReadTokens = cacheReadTokens
        self.costUSD = costUSD
        self.requestId = requestId
        self.dedupeKey = Self.makeDedupeKey(
            requestId: requestId,
            sourceApp: sourceApp,
            timestamp: timestamp,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            model: model
        )
    }

    static func makeDedupeKey(
        requestId: String?,
        sourceApp: String,
        timestamp: Date,
        inputTokens: Int,
        outputTokens: Int,
        model: String
    ) -> String {
        if let rid = requestId, !rid.isEmpty {
            return "\(sourceApp)|\(rid)"
        }
        let ts = Int(timestamp.timeIntervalSince1970 * 1000)
        return "\(sourceApp)|\(model)|\(ts)|\(inputTokens)|\(outputTokens)"
    }

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }
}

/// 记录每个 Collector 的运行状态（上次成功拉取时间、文件 offset 等）。
@Model
final class CollectorState {
    @Attribute(.unique) var collectorId: String
    var lastRunAt: Date?
    var lastError: String?
    /// JSON 字符串：保存每个被解析文件的 inode/offset，用于增量解析
    var cursorPayload: String?

    init(collectorId: String, lastRunAt: Date? = nil, lastError: String? = nil, cursorPayload: String? = nil) {
        self.collectorId = collectorId
        self.lastRunAt = lastRunAt
        self.lastError = lastError
        self.cursorPayload = cursorPayload
    }
}

/// 用户自定义单价覆盖
@Model
final class PricingOverride {
    @Attribute(.unique) var key: String      // "provider:model"
    var inputPer1M: Double
    var outputPer1M: Double
    var cacheWritePer1M: Double
    var cacheReadPer1M: Double

    init(key: String, inputPer1M: Double, outputPer1M: Double, cacheWritePer1M: Double = 0, cacheReadPer1M: Double = 0) {
        self.key = key
        self.inputPer1M = inputPer1M
        self.outputPer1M = outputPer1M
        self.cacheWritePer1M = cacheWritePer1M
        self.cacheReadPer1M = cacheReadPer1M
    }
}

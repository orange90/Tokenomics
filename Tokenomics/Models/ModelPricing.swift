import Foundation

/// 单价均为 USD per 1,000,000 tokens
struct ModelPricing: Codable, Hashable {
    let provider: String
    let model: String
    let inputPer1M: Double
    let outputPer1M: Double
    /// 5 分钟 TTL 缓存写入单价（缺省按输入价处理）。
    var cacheWritePer1M: Double?
    var cacheReadPer1M: Double?
    /// 1 小时 TTL 缓存写入单价。缺省时按 Anthropic 规则取「2× 输入价」。
    var cache1hWritePer1M: Double? = nil

    var key: String { "\(provider):\(model)" }

    /// - Parameters:
    ///   - cacheCreation: 全部缓存写入 token（含 5m 与 1h）。
    ///   - cacheCreation1h: 其中属于 1 小时 TTL 的部分，按更高的 1h 单价计费；余下的算 5m。
    func cost(inputTokens: Int, outputTokens: Int, cacheCreation: Int = 0, cacheCreation1h: Int = 0, cacheRead: Int = 0) -> Double {
        let cc1h = max(0, min(cacheCreation1h, cacheCreation))
        let cc5m = max(0, cacheCreation) - cc1h
        let i = Double(inputTokens) * inputPer1M
        let o = Double(outputTokens) * outputPer1M
        let cwRate = cacheWritePer1M ?? inputPer1M
        let crRate = cacheReadPer1M ?? inputPer1M
        let cw1hRate = cache1hWritePer1M ?? (inputPer1M * 2)
        let cw = Double(cc5m) * cwRate
        let cw1h = Double(cc1h) * cw1hRate
        let cr = Double(cacheRead) * crRate
        return (i + o + cw + cw1h + cr) / 1_000_000.0
    }
}

struct PricingTable: Codable {
    let updatedAt: String
    let entries: [ModelPricing]
}

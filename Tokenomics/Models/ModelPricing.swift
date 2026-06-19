import Foundation

/// 单价均为 USD per 1,000,000 tokens
struct ModelPricing: Codable, Hashable {
    let provider: String
    let model: String
    let inputPer1M: Double
    let outputPer1M: Double
    var cacheWritePer1M: Double?
    var cacheReadPer1M: Double?

    var key: String { "\(provider):\(model)" }

    func cost(inputTokens: Int, outputTokens: Int, cacheCreation: Int = 0, cacheRead: Int = 0) -> Double {
        let i = Double(inputTokens) * inputPer1M
        let o = Double(outputTokens) * outputPer1M
        let cwRate = cacheWritePer1M ?? inputPer1M
        let crRate = cacheReadPer1M ?? inputPer1M
        let cw = Double(cacheCreation) * cwRate
        let cr = Double(cacheRead) * crRate
        return (i + o + cw + cr) / 1_000_000.0
    }
}

struct PricingTable: Codable {
    let updatedAt: String
    let entries: [ModelPricing]
}

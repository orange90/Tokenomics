import Foundation

/// OpenRouter usage 拉取：/api/v1/credits 余额 + /api/v1/generation 明细。
final class OpenRouterCollector: UsageCollector {
    let id = "openrouter-api"
    let displayName = "OpenRouter"

    private let keychain: KeychainService
    init(keychain: KeychainService) { self.keychain = keychain }

    var isEnabled: Bool { keychain.hasKey(KeychainKey.openrouter) }

    func collect(since: Date?) async throws -> [UsageRecord] {
        guard let key = keychain.get(KeychainKey.openrouter), !key.isEmpty else { throw APIError.missingKey }
        let url = URL(string: "https://openrouter.ai/api/v1/credits")!
        let data = try await APIClient.get(url: url, headers: ["Authorization": "Bearer \(key)"])
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any] else { return [] }
        let totalCredits = (dataObj["total_credits"] as? Double) ?? 0
        let totalUsage  = (dataObj["total_usage"] as? Double) ?? 0
        guard totalUsage > 0 else { return [] }
        return [UsageRecord(
            timestamp: Date(),
            provider: Provider.openrouter.rawValue,
            model: "router-aggregate",
            sourceApp: "OpenRouter",
            inputTokens: 0,
            outputTokens: 0,
            costUSD: totalUsage,
            requestId: "credits-\(Int(totalCredits * 100))-\(Int(totalUsage * 100))"
        )]
    }
}

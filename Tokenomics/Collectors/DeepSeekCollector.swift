import Foundation

/// DeepSeek 用量采集：调用 /user/balance（余额）。
/// DeepSeek 目前未提供按日明细的公开 API，因此本 Collector 只产出「余额变化」估算记录：
/// 每次拉取记录余额，并把上次余额与本次余额的差额按当前价折算为虚拟用量。
final class DeepSeekCollector: UsageCollector {
    let id = "deepseek-api"
    let displayName = "DeepSeek"

    private let keychain: KeychainService
    init(keychain: KeychainService) { self.keychain = keychain }

    var isEnabled: Bool { keychain.hasKey(KeychainKey.deepseek) }

    func collect(since: Date?) async throws -> [UsageRecord] {
        guard let key = keychain.get(KeychainKey.deepseek), !key.isEmpty else { throw APIError.missingKey }
        let url = URL(string: "https://api.deepseek.com/user/balance")!
        let data = try await APIClient.get(url: url, headers: [
            "Authorization": "Bearer \(key)",
            "Accept": "application/json"
        ])
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let infos = json["balance_infos"] as? [[String: Any]] else { return [] }

        var records: [UsageRecord] = []
        for info in infos {
            let currency = (info["currency"] as? String) ?? "CNY"
            let granted = Double(info["granted_balance"] as? String ?? "0") ?? 0
            let topped = Double(info["topped_up_balance"] as? String ?? "0") ?? 0
            let total = Double(info["total_balance"] as? String ?? "0") ?? 0
            // 这里只作为一次「快照」记录写入，cost 取为 0；上层 UI 可单独展示余额。
            let usd = currency == "CNY" ? (granted + topped - total) / 7.2 : (granted + topped - total)
            if usd <= 0 { continue }
            records.append(UsageRecord(
                timestamp: Date(),
                provider: Provider.deepseek.rawValue,
                model: "deepseek-chat",
                sourceApp: "DeepSeek API",
                inputTokens: 0,
                outputTokens: 0,
                costUSD: usd,
                requestId: "balance-\(Int(Date().timeIntervalSince1970))"
            ))
        }
        return records
    }
}

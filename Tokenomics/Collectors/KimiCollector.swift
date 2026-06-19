import Foundation

/// Kimi (Moonshot) 用量采集：调用 /v1/users/me/balance（账户余额）。
/// Moonshot 暂未提供按日明细的公开 API，因此本 Collector 与 DeepSeek / Stepfun 一致，
/// 以「累计授信(代金券+充值) - 当前可用余额」作为已用金额估算。
/// 接口响应示例：
/// {
///   "code": 0,
///   "data": {
///     "available_balance": 49.58,
///     "voucher_balance": 46.58,
///     "cash_balance": 3.00
///   }
/// }
/// 注：Moonshot 账户余额单位即美元（USD），无需再做汇率换算。
final class KimiCollector: UsageCollector {
    let id = "kimi-api"
    let displayName = "Kimi (Moonshot)"

    private let keychain: KeychainService
    init(keychain: KeychainService) { self.keychain = keychain }

    var isEnabled: Bool { keychain.hasKey(KeychainKey.kimi) }

    func collect(since: Date?) async throws -> [UsageRecord] {
        guard let key = keychain.get(KeychainKey.kimi), !key.isEmpty else { throw APIError.missingKey }
        let url = URL(string: "https://api.moonshot.ai/v1/users/me/balance")!
        let data = try await APIClient.get(url: url, headers: [
            "Authorization": "Bearer \(key)",
            "Accept": "application/json"
        ])
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        // 兼容两种返回结构：
        //   1) { "code": 0, "data": { ... } }
        //   2) 直接平铺字段（部分代理 / 文档版本会去掉外层 data）
        let payload: [String: Any] = (json["data"] as? [String: Any]) ?? json

        let available = doubleValue(payload, keys: ["available_balance", "availableBalance", "balance"])
        let voucher   = doubleValue(payload, keys: ["voucher_balance",   "voucherBalance"])
        let cash      = doubleValue(payload, keys: ["cash_balance",      "cashBalance"])

        let granted = voucher + cash
        let used = max(0, granted - available)
        if used <= 0 { return [] }

        return [UsageRecord(
            timestamp: Date(),
            provider: Provider.kimi.rawValue,
            model: "balance-snapshot",
            sourceApp: "Kimi (Moonshot)",
            inputTokens: 0,
            outputTokens: 0,
            costUSD: used,
            requestId: "balance-\(Int(Date().timeIntervalSince1970))"
        )]
    }

    private func doubleValue(_ json: [String: Any], keys: [String]) -> Double {
        for k in keys {
            if let v = json[k] as? Double { return v }
            if let v = json[k] as? Int    { return Double(v) }
            if let v = json[k] as? String, let d = Double(v) { return d }
        }
        return 0
    }
}

import Foundation

/// 阶跃星辰 (Stepfun) 用量采集：/v1/accounts（账户信息 + 余额）。
/// Stepfun 暂未提供按日明细的公开 API，因此本 Collector 与 SiliconFlow / DeepSeek 一致，
/// 用「累计充值 - 当前可用余额」作为已用金额估算，并把人民币按当前汇率折算为 USD。
final class StepFunCollector: UsageCollector {
    let id = "stepfun-api"
    let displayName = "阶跃星辰 (Stepfun)"

    private let keychain: KeychainService
    init(keychain: KeychainService) { self.keychain = keychain }

    var isEnabled: Bool { keychain.hasKey(KeychainKey.stepfun) }

    func collect(since: Date?) async throws -> [UsageRecord] {
        guard let key = keychain.get(KeychainKey.stepfun), !key.isEmpty else { throw APIError.missingKey }
        let url = URL(string: "https://api.stepfun.com/v1/accounts")!
        let data = try await APIClient.get(url: url, headers: [
            "Authorization": "Bearer \(key)",
            "Accept": "application/json"
        ])
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        // 字段命名兼容：available_balance / availableBalance、total_cash_balance / totalCashBalance、
        // total_voucher_balance / totalVoucherBalance（不同文档版本可能略有差异）。
        let available = doubleValue(json, keys: ["available_balance", "availableBalance", "balance"])
        let cash      = doubleValue(json, keys: ["total_cash_balance", "totalCashBalance", "total_charged", "charged_balance"])
        let voucher   = doubleValue(json, keys: ["total_voucher_balance", "totalVoucherBalance", "total_granted", "granted_balance"])

        let granted = cash + voucher
        let used = max(0, granted - available)
        if used <= 0 { return [] }
        // 阶跃星辰国内计费默认 CNY，按 7.2 粗略折算成 USD（实际汇率由上层重新换算展示）。
        let usd = used / 7.2
        return [UsageRecord(
            timestamp: Date(),
            provider: Provider.stepfun.rawValue,
            model: "balance-snapshot",
            sourceApp: "Stepfun",
            inputTokens: 0,
            outputTokens: 0,
            costUSD: usd,
            requestId: "balance-\(Int(Date().timeIntervalSince1970))"
        )]
    }

    private func doubleValue(_ json: [String: Any], keys: [String]) -> Double {
        for k in keys {
            if let v = json[k] as? Double { return v }
            if let v = json[k] as? Int    { return Double(v) }
            if let v = json[k] as? String, let d = Double(v) { return d }
        }
        // 部分返回会把余额包在 data 字段内
        if let data = json["data"] as? [String: Any] {
            for k in keys {
                if let v = data[k] as? Double { return v }
                if let v = data[k] as? Int    { return Double(v) }
                if let v = data[k] as? String, let d = Double(v) { return d }
            }
        }
        return 0
    }
}

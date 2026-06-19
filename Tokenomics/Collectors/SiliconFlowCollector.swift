import Foundation

/// 硅基流动 (SiliconFlow) 用量采集：/v1/user/info（余额）。
/// 同样以余额差额作为估算来源。
final class SiliconFlowCollector: UsageCollector {
    let id = "siliconflow-api"
    let displayName = "硅基流动"

    private let keychain: KeychainService
    init(keychain: KeychainService) { self.keychain = keychain }

    var isEnabled: Bool { keychain.hasKey(KeychainKey.siliconflow) }

    func collect(since: Date?) async throws -> [UsageRecord] {
        guard let key = keychain.get(KeychainKey.siliconflow), !key.isEmpty else { throw APIError.missingKey }
        let url = URL(string: "https://api.siliconflow.cn/v1/user/info")!
        let data = try await APIClient.get(url: url, headers: ["Authorization": "Bearer \(key)"])
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any] else { return [] }
        let total = Double(dataObj["totalBalance"] as? String ?? "0") ?? 0
        let charged = Double(dataObj["chargeBalance"] as? String ?? "0") ?? 0
        let used = max(0, charged - total)
        if used <= 0 { return [] }
        // SiliconFlow 默认 CNY 计费，折算成 USD
        let usd = used / 7.2
        return [UsageRecord(
            timestamp: Date(),
            provider: Provider.siliconflow.rawValue,
            model: "balance-snapshot",
            sourceApp: "SiliconFlow",
            inputTokens: 0,
            outputTokens: 0,
            costUSD: usd,
            requestId: "balance-\(Int(Date().timeIntervalSince1970))"
        )]
    }
}

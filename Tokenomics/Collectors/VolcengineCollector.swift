import Foundation

/// 火山方舟 (Volcengine Ark / 豆包) 用量采集：OpenAI 兼容协议
/// (https://ark.cn-beijing.volces.com/api/v3)。
/// 火山方舟开放平台目前未对外暴露 usage / balance 查询接口（账户余额与按日明细
/// 只能在火山引擎控制台查看），因此本 Collector 仅做 API Key 健康检查
/// （请求 /api/v3/models），暂不产出用量记录；待官方上线用量查询接口后再补充。
final class VolcengineCollector: UsageCollector {
    let id = "volcengine-api"
    let displayName = "火山方舟 (豆包)"

    private let keychain: KeychainService
    init(keychain: KeychainService) { self.keychain = keychain }

    var isEnabled: Bool { keychain.hasKey(KeychainKey.volcengine) }

    func collect(since: Date?) async throws -> [UsageRecord] {
        guard let key = keychain.get(KeychainKey.volcengine), !key.isEmpty else { throw APIError.missingKey }
        // 火山方舟 Ark 推理 API 与 OpenAI 兼容，使用 Bearer Token 鉴权。
        let url = URL(string: "https://ark.cn-beijing.volces.com/api/v3/models")!
        _ = try? await APIClient.get(url: url, headers: [
            "Authorization": "Bearer \(key)",
            "Accept": "application/json"
        ])
        return []
    }
}

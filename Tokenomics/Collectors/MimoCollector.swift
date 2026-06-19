import Foundation

/// 小米 MiMo 用量采集：OpenAI 兼容协议 (https://api.xiaomimimo.com/v1)。
/// 截至当前小米 MiMo 开放平台尚未对外暴露 usage / balance 查询接口，用量与配额仅可在控制台查看。
/// 因此本 Collector 仅做 API Key 健康检查（请求 /v1/models），暂不产出用量记录；
/// 待官方上线用量查询接口后再补充。
final class MimoCollector: UsageCollector {
    let id = "mimo-api"
    let displayName = "小米 MiMo"

    private let keychain: KeychainService
    init(keychain: KeychainService) { self.keychain = keychain }

    var isEnabled: Bool { keychain.hasKey(KeychainKey.mimo) }

    func collect(since: Date?) async throws -> [UsageRecord] {
        guard let key = keychain.get(KeychainKey.mimo), !key.isEmpty else { throw APIError.missingKey }
        // MiMo 文档示例同时支持 `api-key` 自定义头与标准 Authorization Bearer，两者一并发送以提高兼容性。
        let url = URL(string: "https://api.xiaomimimo.com/v1/models")!
        _ = try? await APIClient.get(url: url, headers: [
            "api-key": key,
            "Authorization": "Bearer \(key)",
            "Accept": "application/json"
        ])
        return []
    }
}

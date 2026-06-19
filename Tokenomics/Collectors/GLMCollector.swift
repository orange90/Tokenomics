import Foundation

/// 智谱 GLM (BigModel / Zhipu AI) 用量采集：OpenAI 兼容协议
/// (https://open.bigmodel.cn/api/paas/v4)。
/// 智谱开放平台目前未对外暴露 usage / balance 查询接口（账户余额与按日明细
/// 只能在智谱控制台 https://open.bigmodel.cn/usercenter 查看），因此本 Collector
/// 仅做 API Key 健康检查（请求 /api/paas/v4/models），暂不产出用量记录；
/// 待官方上线用量查询接口后再补充。
final class GLMCollector: UsageCollector {
    let id = "glm-api"
    let displayName = "智谱 GLM"

    private let keychain: KeychainService
    init(keychain: KeychainService) { self.keychain = keychain }

    var isEnabled: Bool { keychain.hasKey(KeychainKey.glm) }

    func collect(since: Date?) async throws -> [UsageRecord] {
        guard let key = keychain.get(KeychainKey.glm), !key.isEmpty else { throw APIError.missingKey }
        // 智谱 GLM 推理 API 与 OpenAI 兼容，使用 Bearer Token 鉴权。
        let url = URL(string: "https://open.bigmodel.cn/api/paas/v4/models")!
        _ = try? await APIClient.get(url: url, headers: [
            "Authorization": "Bearer \(key)",
            "Accept": "application/json"
        ])
        return []
    }
}

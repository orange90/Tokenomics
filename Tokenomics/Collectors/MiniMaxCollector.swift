import Foundation

/// MiniMax (海螺) 用量采集：OpenAI 兼容协议 (https://api.minimaxi.com/v1)。
/// MiniMax 开放平台目前未对外暴露稳定的 usage / balance 查询接口，用量与余额仅可在控制台查看。
/// 因此本 Collector 仅做 API Key 健康检查（请求 /v1/models），暂不产出用量记录；
/// 待官方上线公开的用量查询接口后再补充。
final class MiniMaxCollector: UsageCollector {
    let id = "minimax-api"
    let displayName = "MiniMax (海螺)"

    private let keychain: KeychainService
    init(keychain: KeychainService) { self.keychain = keychain }

    var isEnabled: Bool { keychain.hasKey(KeychainKey.minimax) }

    func collect(since: Date?) async throws -> [UsageRecord] {
        guard let key = keychain.get(KeychainKey.minimax), !key.isEmpty else { throw APIError.missingKey }
        let url = URL(string: "https://api.minimaxi.com/v1/models")!
        _ = try? await APIClient.get(url: url, headers: [
            "Authorization": "Bearer \(key)",
            "Accept": "application/json"
        ])
        return []
    }
}

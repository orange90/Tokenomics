import Foundation

/// Gemini (Google AI Studio) 暂未提供个人级别的 usage API，采用「占位」实现：
/// 若用户已配置 API Key，则插入一条说明记录，等待 Google 后续开放 usage 接口再扩展。
final class GeminiAPICollector: UsageCollector {
    let id = "gemini-api"
    let displayName = "Google Gemini"

    private let keychain: KeychainService
    init(keychain: KeychainService) { self.keychain = keychain }

    var isEnabled: Bool { keychain.hasKey(KeychainKey.gemini) }

    func collect(since: Date?) async throws -> [UsageRecord] {
        // 占位：仅校验 key 有效性
        guard let key = keychain.get(KeychainKey.gemini), !key.isEmpty else { throw APIError.missingKey }
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(key)")!
        _ = try await APIClient.get(url: url, headers: ["Accept": "application/json"])
        // 没有 usage API，返回空，由用户走「OpenRouter / 自建代理」方案
        return []
    }
}

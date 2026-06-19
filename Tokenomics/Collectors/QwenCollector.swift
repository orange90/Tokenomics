import Foundation

/// 千问 / Qwen DashScope 服务区域。
enum QwenRegion {
    case china       // 国内：dashscope.aliyuncs.com
    case international // 国际：dashscope-intl.aliyuncs.com

    var baseURL: String {
        switch self {
        case .china:         return "https://dashscope.aliyuncs.com"
        case .international: return "https://dashscope-intl.aliyuncs.com"
        }
    }

    var keychainKey: String {
        switch self {
        case .china:         return KeychainKey.qwen
        case .international: return KeychainKey.qwenIntl
        }
    }

    var collectorId: String {
        switch self {
        case .china:         return "qwen-api"
        case .international: return "qwen-intl-api"
        }
    }

    var displayName: String {
        switch self {
        case .china:         return "通义千问 (国内)"
        case .international: return "Qwen (International)"
        }
    }
}

/// 通义千问 (阿里 DashScope) 用量采集。
/// DashScope 暂无标准 usage 报表 API，使用 /api/v1/models 探测凭证健康。
/// 支持国内 (dashscope.aliyuncs.com) 与国际 (dashscope-intl.aliyuncs.com) 两个端点。
final class QwenCollector: UsageCollector {
    let id: String
    let displayName: String

    private let keychain: KeychainService
    private let region: QwenRegion

    init(keychain: KeychainService, region: QwenRegion = .china) {
        self.keychain = keychain
        self.region = region
        self.id = region.collectorId
        self.displayName = region.displayName
    }

    var isEnabled: Bool { keychain.hasKey(region.keychainKey) }

    func collect(since: Date?) async throws -> [UsageRecord] {
        guard let key = keychain.get(region.keychainKey), !key.isEmpty else { throw APIError.missingKey }
        let url = URL(string: "\(region.baseURL)/api/v1/models")!
        _ = try? await APIClient.get(url: url, headers: ["Authorization": "Bearer \(key)"])
        return []
    }
}

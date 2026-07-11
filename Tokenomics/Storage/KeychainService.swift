import Foundation
import Security

/// 简易 Keychain 封装，用于 API Key 存取。
final class KeychainService {
    private let service = "com.tokenomics.Tokenomics"

    func set(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(key) // overwrite
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    func hasKey(_ key: String) -> Bool {
        get(key) != nil
    }
}

/// 已知 Key 名常量
enum KeychainKey {
    static let openai     = "api.openai"
    static let anthropic  = "api.anthropic"
    /// 用户级 Anthropic API key（`sk-ant-api03-...`），用于 ClaudeDowngradeProbe 打
    /// `/v1/messages` 做金标探测。与 `anthropic`（admin key）分开，因为 admin key
    /// 只能访问 `/v1/organizations/*` 端点。
    static let anthropicCanary = "api.anthropic.canary"
}

import Foundation
import Security

/// 通过本地 Claude CLI OAuth 凭证拉取 Claude 订阅额度（5 小时窗口 + 每周窗口）。
///
/// 数据源参考：steipete/CodexBar - docs/claude.md
///   - 凭证：macOS Keychain 的 generic password，service = "Claude Code-credentials"
///           （新版本 Claude Code 默认存储位置，磁盘上没有 .credentials.json）
///   - 回退：~/.claude/.credentials.json（旧版本 Claude CLI 的存放方式）
///   - 接口：GET https://api.anthropic.com/api/oauth/usage
///   - Headers：Authorization: Bearer <access_token>, anthropic-beta: oauth-2025-04-20
///
/// 响应体（典型字段）：
/// {
///   "five_hour":  { "utilization": 12.3, "resets_at": "2026-..." },
///   "seven_day":  { "utilization": 42.1, "resets_at": "2026-..." },
///   "seven_day_sonnet": { ... },
///   "seven_day_opus":   { ... },
///   "subscriptionType": "max" / "pro" / ...
/// }
final class ClaudeQuotaProbe: QuotaProbe {
    let id = "claude"
    let displayName = "Claude"

    private let credentialsURL: URL
    private let keychainService = "Claude Code-credentials"

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.credentialsURL = home.appendingPathComponent(".claude/.credentials.json")
    }

    var isAvailable: Bool {
        if hasKeychainCredentials() { return true }
        return FileManager.default.fileExists(atPath: credentialsURL.path)
    }

    func fetch() async throws -> QuotaSnapshot {
        let token = try loadAccessToken()
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw APIError.parse("invalid URL")
        }
        // 注意：Anthropic OAuth usage 接口要求同时带 `anthropic-version`，
        // 否则即使 access token 有效也会返回 401 "Invalid authentication credentials"。
        let data = try await APIClient.get(url: url, headers: [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": "oauth-2025-04-20",
            "anthropic-version": "2023-06-01"
        ], timeout: 12)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.parse("Claude usage response not JSON")
        }

        var windows: [QuotaWindow] = []
        if let w = parseWindow(json["five_hour"], id: "five_hour", title: "5 小时", note: nil) {
            windows.append(w)
        }
        if let w = parseWindow(json["seven_day"], id: "seven_day", title: "每周", note: nil) {
            windows.append(w)
        }
        if let w = parseWindow(json["seven_day_sonnet"], id: "seven_day_sonnet", title: "每周", note: "Sonnet") {
            windows.append(w)
        }
        if let w = parseWindow(json["seven_day_opus"], id: "seven_day_opus", title: "每周", note: "Opus") {
            windows.append(w)
        }

        let plan = (json["subscriptionType"] as? String)
            ?? (json["rate_limit_tier"] as? String)
        let account = plan.map { "Claude \($0.capitalized)" }

        return QuotaSnapshot(
            id: id,
            providerName: displayName,
            accountIdentifier: account,
            windows: windows,
            fetchedAt: Date(),
            source: "OAuth API"
        )
    }

    // MARK: - Helpers

    private func parseWindow(_ raw: Any?, id: String, title: String, note: String?) -> QuotaWindow? {
        guard let dict = raw as? [String: Any] else { return nil }
        let util = (dict["utilization"] as? Double)
            ?? (dict["utilization"] as? Int).map(Double.init)
            ?? 0
        let resetsAtRaw = dict["resets_at"] ?? dict["reset_at"] ?? dict["next_reset_at"]
        let resetsAt: Date? = {
            guard let raw = resetsAtRaw else { return nil }
            if raw is String || raw is Double || raw is Int { return DateParsing.parse(raw) }
            return nil
        }()
        return QuotaWindow(id: id, title: title, usedPercent: util, resetsAt: resetsAt, note: note)
    }

    private func loadAccessToken() throws -> String {
        // 优先：Keychain "Claude Code-credentials"（新版本 Claude Code 默认）
        if let tok = try? readKeychainAccessToken() {
            return tok
        }
        // 回退：~/.claude/.credentials.json
        if FileManager.default.fileExists(atPath: credentialsURL.path) {
            let data = try Data(contentsOf: credentialsURL)
            return try parseAccessToken(from: data)
        }
        throw APIError.missingKey
    }

    /// 检查 Keychain 中是否有 "Claude Code-credentials" 条目。
    /// 注意：这里不读取数据，避免触发 macOS Keychain 授权弹窗；
    /// 真正的读取发生在 fetch() 时由用户主动触发。
    private func hasKeychainCredentials() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == errSecSuccess
    }

    private func readKeychainAccessToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw APIError.missingKey
        }
        return try parseAccessToken(from: data)
    }

    /// 从 Claude credentials JSON 中提取 access token。
    /// 兼容结构：
    ///   { "claudeAiOauth": { "accessToken": "..." } }
    ///   { "accessToken": "..." } / { "access_token": "..." }
    private func parseAccessToken(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.parse("Claude credentials not JSON")
        }
        if let outer = root["claudeAiOauth"] as? [String: Any] {
            if let tok = outer["accessToken"] as? String, !tok.isEmpty { return tok }
            if let tok = outer["access_token"] as? String, !tok.isEmpty { return tok }
        }
        if let tok = root["accessToken"] as? String, !tok.isEmpty { return tok }
        if let tok = root["access_token"] as? String, !tok.isEmpty { return tok }
        throw APIError.missingKey
    }
}

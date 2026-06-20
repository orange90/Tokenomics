import Foundation

/// 通过本地 Claude CLI OAuth 凭证拉取 Claude 订阅额度（5 小时窗口 + 每周窗口）。
///
/// 数据源参考：steipete/CodexBar - docs/claude.md
///   - 凭证：macOS Keychain 的 generic password，service = "Claude Code-credentials"
///           （新版本 Claude Code 默认存储位置，磁盘上没有 .credentials.json）
///   - 回退：~/.claude/.credentials.json（旧版本 Claude CLI 的存放方式）
///   - 接口：GET https://api.anthropic.com/api/oauth/usage
///   - Headers：Authorization: Bearer <access_token>, anthropic-beta: oauth-2025-04-20
///
/// 关键：access token 寿命很短，过期后必须先用 refresh token 静默刷新，否则 usage 接口
/// 直接 401/429。凭证读取 / 刷新 / 写回统一由 ``ClaudeOAuthCredentialStore`` 负责。
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

    private let store: ClaudeOAuthCredentialStore

    init(store: ClaudeOAuthCredentialStore = ClaudeOAuthCredentialStore()) {
        self.store = store
    }

    var isAvailable: Bool { store.isAvailable }

    func fetch() async throws -> QuotaSnapshot {
        var loaded = try store.load()

        // 1) access token 已过期且有 refresh token → 先静默刷新，避免必定失败的请求。
        if loaded.credentials.isExpired(), loaded.credentials.refreshToken != nil {
            loaded.credentials = try await store.refresh(loaded)
        }

        do {
            return try await fetchUsage(token: loaded.credentials.accessToken,
                                        fallbackPlan: loaded.credentials.subscriptionType)
        } catch APIError.httpStatus(let code, let body) where code == 401 {
            // 2) 兜底：expiresAt 缺失/不准导致 token 实际已失效 → 刷新一次再重试。
            guard loaded.credentials.refreshToken != nil else {
                throw APIError.httpStatus(code, body)
            }
            let refreshed = try await store.refresh(loaded)
            return try await fetchUsage(token: refreshed.accessToken,
                                        fallbackPlan: refreshed.subscriptionType)
        }
    }

    // MARK: - Usage fetch

    private func fetchUsage(token: String, fallbackPlan: String?) async throws -> QuotaSnapshot {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw APIError.parse("invalid URL")
        }
        // 注意：Anthropic OAuth usage 接口要求同时带 `anthropic-version`，
        // 否则即使 access token 有效也会返回 401 "Invalid authentication credentials"。
        let data = try await APIClient.get(url: url, headers: [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": "oauth-2025-04-20",
            "anthropic-version": "2023-06-01",
            "Accept": "application/json",
            "User-Agent": "claude-code/2.1.0"
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
            ?? fallbackPlan
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
}

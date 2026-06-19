import Foundation

/// 通过本地 Codex CLI OAuth 凭证拉取 Codex 订阅额度（5 小时窗口 + 每周窗口）。
///
/// 数据源参考：steipete/CodexBar - docs/codex.md
///   - 凭证文件：~/.codex/auth.json （或 $CODEX_HOME/auth.json）
///   - 接口：GET https://chatgpt.com/backend-api/wham/usage
///   - Headers：Authorization: Bearer <access_token>
///
/// 响应体（典型字段）：
/// {
///   "rate_limit": {
///     "primary_window":  { "used_percent": 12.3, "resets_at": "...", "window_minutes": 300 },
///     "secondary_window":{ "used_percent": 42.1, "resets_at": "...", "window_minutes": 10080 }
///   },
///   "additional_rate_limits": [
///     { "feature_id": "codex-spark", "title": "Codex Spark", "used_percent": 5, "resets_at": "..." }
///   ],
///   "account": { "email": "...", "plan_type": "plus" }
/// }
final class CodexQuotaProbe: QuotaProbe {
    let id = "codex"
    let displayName = "Codex"

    private let authURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let baseDir: URL
        if let custom = ProcessInfo.processInfo.environment["CODEX_HOME"], !custom.isEmpty {
            baseDir = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            baseDir = home.appendingPathComponent(".codex", isDirectory: true)
        }
        self.authURL = baseDir.appendingPathComponent("auth.json")
    }

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: authURL.path)
    }

    func fetch() async throws -> QuotaSnapshot {
        let token = try loadAccessToken()
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            throw APIError.parse("invalid URL")
        }
        let data = try await APIClient.get(url: url, headers: [
            "Authorization": "Bearer \(token)"
        ], timeout: 12)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.parse("Codex usage response not JSON")
        }

        var windows: [QuotaWindow] = []
        let rateLimit = json["rate_limit"] as? [String: Any]
        if let w = parseWindow(rateLimit?["primary_window"], id: "primary_window", title: "5 小时", note: nil) {
            windows.append(w)
        }
        if let w = parseWindow(rateLimit?["secondary_window"], id: "secondary_window", title: "每周", note: nil) {
            windows.append(w)
        }
        if let extras = json["additional_rate_limits"] as? [[String: Any]] {
            for extra in extras {
                let fid = (extra["feature_id"] as? String) ?? UUID().uuidString
                let title = (extra["title"] as? String) ?? fid
                if let w = parseWindow(extra, id: "extra-\(fid)", title: title, note: nil) {
                    windows.append(w)
                }
            }
        }

        let account = parseAccountIdentifier(json: json)

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
        let used: Double = {
            if let v = dict["used_percent"] as? Double { return v }
            if let v = dict["used_percent"] as? Int { return Double(v) }
            if let v = dict["utilization"] as? Double { return v }
            if let v = dict["utilization"] as? Int { return Double(v) }
            return 0
        }()
        let resetsAtRaw = dict["resets_at"] ?? dict["reset_at"] ?? dict["next_reset_at"]
        let resetsAt: Date? = {
            guard let raw = resetsAtRaw else { return nil }
            if raw is String || raw is Double || raw is Int { return DateParsing.parse(raw) }
            return nil
        }()
        return QuotaWindow(id: id, title: title, usedPercent: used, resetsAt: resetsAt, note: note)
    }

    private func parseAccountIdentifier(json: [String: Any]) -> String? {
        if let account = json["account"] as? [String: Any] {
            let email = account["email"] as? String
            let plan = (account["plan_type"] as? String) ?? (account["plan"] as? String)
            switch (email, plan) {
            case let (e?, p?): return "\(e) · \(p.capitalized)"
            case let (e?, nil): return e
            case let (nil, p?): return "Codex \(p.capitalized)"
            default: break
            }
        }
        if let plan = json["plan_type"] as? String { return "Codex \(plan.capitalized)" }
        return nil
    }

    private func loadAccessToken() throws -> String {
        let data = try Data(contentsOf: authURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.parse("Codex auth not JSON")
        }
        // 兼容多种结构：
        //   { "tokens": { "access_token": "..." } }
        //   { "OPENAI_API_KEY": "...", "tokens": { "access_token": "..." } }
        //   { "access_token": "..." }
        if let tokens = root["tokens"] as? [String: Any] {
            if let tok = tokens["access_token"] as? String, !tok.isEmpty { return tok }
            if let tok = tokens["accessToken"] as? String, !tok.isEmpty { return tok }
        }
        if let tok = root["access_token"] as? String, !tok.isEmpty { return tok }
        if let tok = root["accessToken"] as? String, !tok.isEmpty { return tok }
        // 退路：Codex 也支持纯 API key，但 wham/usage 仅认 OAuth bearer。
        throw APIError.missingKey
    }
}

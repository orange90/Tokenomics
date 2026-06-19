import Foundation

/// 通过浏览器（claude.ai）cookie 读取 Claude 订阅额度。
///
/// 数据流：
///   1. 由 ChromiumCookieReader 从本地 Brave/Chrome 解出 `sessionKey`（sk-ant-...）。
///   2. 以 `Cookie: sessionKey=<value>` 调用 claude.ai 的网页 API：
///        GET /api/organizations                 → 取 orgId
///        GET /api/organizations/{id}/usage      → 5h / 7d / 模型分窗使用率
///        GET /api/organizations/{id}/overage_spend_limit  → 额外用量（可选）
///        GET /api/account                       → email + plan
///   3. 映射成统一的 QuotaSnapshot。
///
/// 这条路径的限流策略与 `api.anthropic.com/api/oauth/usage` 完全独立，
/// 因此当 OAuth 接口被 429 时，仍然可以从这里拿到额度。
final class ClaudeWebQuotaProbe: QuotaProbe {
    let id = "claude"
    let displayName = "Claude"

    private let cookieReader: ChromiumCookieReader
    private let preferredBrowsers: () -> [ChromiumBrowser]

    /// `preferredBrowsers` 由调用方动态提供，方便 UI 改设置后立即生效。
    init(cookieReader: ChromiumCookieReader = ChromiumCookieReader(),
         preferredBrowsers: @escaping () -> [ChromiumBrowser] = { ChromiumBrowser.allCases }) {
        self.cookieReader = cookieReader
        self.preferredBrowsers = preferredBrowsers
    }

    var isAvailable: Bool {
        // 不在 isAvailable 里真的去解 cookie（会触发 Keychain 弹窗）。
        // 只检查目录存在 = 浏览器装了 / 可能登录了 claude.ai。
        for browser in preferredBrowsers() {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let base: URL
            switch browser {
            case .chrome:
                base = home.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
            case .brave:
                base = home.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser", isDirectory: true)
            }
            if FileManager.default.fileExists(atPath: base.path) { return true }
        }
        return false
    }

    func fetch() async throws -> QuotaSnapshot {
        let cookie: ChromiumCookieReader.ImportedCookie
        switch cookieReader.readSessionKey(preferred: preferredBrowsers()) {
        case .success(let c): cookie = c
        case .failure(let e): throw e
        }
        return try await fetch(usingSessionKey: cookie.sessionKey,
                               sourceLabel: "\(cookie.browser.displayName)/\(cookie.profile)")
    }

    /// 直接用一个已知的 sessionKey 拉数据，单测和"OAuth → Web fallback"路径都会调用它。
    func fetch(usingSessionKey sessionKey: String, sourceLabel: String) async throws -> QuotaSnapshot {
        // 1. 拿 orgId
        let orgs = try await getJSON(path: "/api/organizations", sessionKey: sessionKey)
        let orgList = (orgs as? [[String: Any]]) ?? []
        guard let orgId = (orgList.first?["uuid"] as? String) ?? (orgList.first?["id"] as? String) else {
            throw APIError.parse("Claude /api/organizations 返回为空或缺少 uuid")
        }

        // 2. usage
        let usageObj = try await getJSON(path: "/api/organizations/\(orgId)/usage", sessionKey: sessionKey)
        let usage = (usageObj as? [String: Any]) ?? [:]

        var windows: [QuotaWindow] = []
        if let w = parseWindow(usage["five_hour"], id: "five_hour", title: "5 小时", note: nil) {
            windows.append(w)
        }
        if let w = parseWindow(usage["seven_day"], id: "seven_day", title: "每周", note: nil) {
            windows.append(w)
        }
        if let w = parseWindow(usage["seven_day_sonnet"], id: "seven_day_sonnet", title: "每周", note: "Sonnet") {
            windows.append(w)
        }
        if let w = parseWindow(usage["seven_day_opus"], id: "seven_day_opus", title: "每周", note: "Opus") {
            windows.append(w)
        }

        // 3. account（best effort）
        var account: String? = nil
        if let accountObj = try? await getJSON(path: "/api/account", sessionKey: sessionKey),
           let dict = accountObj as? [String: Any] {
            let email = dict["email_address"] as? String
                ?? dict["email"] as? String
                ?? (dict["account"] as? [String: Any])?["email_address"] as? String
            let plan = dict["subscription_type"] as? String
                ?? dict["plan"] as? String
                ?? (dict["account"] as? [String: Any])?["subscription_type"] as? String
            switch (email, plan) {
            case let (e?, p?): account = "\(e) · \(p.capitalized)"
            case let (e?, nil): account = e
            case let (nil, p?): account = "Claude \(p.capitalized)"
            default: break
            }
        }

        return QuotaSnapshot(
            id: id,
            providerName: displayName,
            accountIdentifier: account,
            windows: windows,
            fetchedAt: Date(),
            source: "Browser Cookie (\(sourceLabel))"
        )
    }

    // MARK: - HTTP

    private func getJSON(path: String, sessionKey: String) async throws -> Any {
        guard let url = URL(string: "https://claude.ai\(path)") else {
            throw APIError.parse("invalid URL: \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        // claude.ai 后端会拒绝过分明显的非浏览器请求；用一个常见 UA 即可。
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: - Window 解析（与 ClaudeQuotaProbe 一致）

    private func parseWindow(_ raw: Any?, id: String, title: String, note: String?) -> QuotaWindow? {
        guard let dict = raw as? [String: Any] else { return nil }
        let util: Double
        if let d = dict["utilization"] as? Double {
            util = d
        } else if let i = dict["utilization"] as? Int {
            util = Double(i)
        } else if let d = dict["used_percent"] as? Double {
            util = d
        } else if let i = dict["used_percent"] as? Int {
            util = Double(i)
        } else {
            util = 0
        }
        let resetsAtRaw = dict["resets_at"] ?? dict["reset_at"] ?? dict["next_reset_at"]
        let resetsAt: Date? = {
            guard let raw = resetsAtRaw else { return nil }
            if raw is String || raw is Double || raw is Int { return DateParsing.parse(raw) }
            return nil
        }()
        return QuotaWindow(id: id, title: title, usedPercent: util, resetsAt: resetsAt, note: note)
    }
}

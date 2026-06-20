import Foundation
import Security

/// Claude Code 的 OAuth 凭证（来自 Keychain 或 ~/.claude/.credentials.json）。
struct ClaudeOAuthCredentials {
    var accessToken: String
    var refreshToken: String?
    /// access token 过期时间（毫秒 epoch，沿用 Claude Code 的存储格式）。
    var expiresAtMillis: Double?
    var subscriptionType: String?
    var rateLimitTier: String?

    var expiresAt: Date? {
        guard let ms = expiresAtMillis, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    /// access token 是否已过期（默认留 60s 余量；过期时间未知则按未过期处理，靠 401 兜底）。
    func isExpired(now: Date = Date(), skew: TimeInterval = 60) -> Bool {
        guard let exp = expiresAt else { return false }
        return now.addingTimeInterval(skew) >= exp
    }
}

/// 读取 / 刷新 / 写回 Claude Code 的 OAuth 凭证。
///
/// 背景：Claude 的 access token 寿命很短（约数小时）。旧版本探针直接拿存储里的
/// access token 调 usage 接口，token 一旦过期就必然 401/429，于是“拿不到额度”。
///
/// 这里参照 Claude CLI 自身的静默刷新行为：当 access token 过期时，用 refresh token
/// 调官方 OAuth 刷新端点换取新 token，并**写回原来源**（Keychain 或凭证文件）。
/// 写回是必要的——Anthropic 会轮换 refresh token，若不写回，下次 CLI（或本应用）
/// 仍拿旧 refresh token 去刷新会失败，反而把用户的 Claude 登录搞挂。写回后两边共享
/// 同一份最新凭证，保持一致。
///
/// 参考：steipete/CodexBar 通过拉起 `claude` CLI 触发刷新（CLI 自己写回 Keychain）；
/// 本应用未开启 App Sandbox，直接做刷新 + 写回更轻量。
final class ClaudeOAuthCredentialStore {
    enum Source: Equatable {
        case keychain
        case file(URL)
    }

    /// Claude Code 的公开 OAuth client id（CLI 内置常量）。
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    /// OAuth 刷新端点，按优先级排列。
    ///
    /// 两个 host 都能处理 refresh_token 授权，但**限流策略不同**：在国内经共享代理
    /// 出口访问时，`console.anthropic.com` 常对该出口 IP 返回 429（连无效 token 都
    /// 立刻 429），而 `api.anthropic.com/v1/oauth/token` 限流宽松、可正常换 token
    /// （无效 token 会干净地返回 400 invalid_grant）。所以优先 api、再退到 console。
    static let tokenEndpoints = [
        "https://api.anthropic.com/v1/oauth/token",
        "https://console.anthropic.com/v1/oauth/token"
    ]

    private let keychainService = "Claude Code-credentials"
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.fileURL = fileURL ?? home.appendingPathComponent(".claude/.credentials.json")
    }

    /// 进程内凭证缓存。读 Keychain 属跨进程操作、且对别家（Claude CLI）的条目会走 ACL
    /// 校验/弹窗，没必要每轮额度刷新都来一次。首次读后缓存；refresh 写回时更新；
    /// refresh 因 token 被外部轮换而失败时失效重读。
    private var cached: Loaded?
    private let cacheLock = NSLock()

    // MARK: - Availability

    /// 是否存在凭证。注意：不读取 Keychain 数据，避免触发授权弹窗。
    var isAvailable: Bool {
        hasKeychainCredentials() || FileManager.default.fileExists(atPath: fileURL.path)
    }

    private func hasKeychainCredentials() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true
        ]
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    // MARK: - Load

    /// 一次加载的结果：解析后的凭证 + 来源 + 完整 JSON（写回时保留 scopes 等其它字段）。
    struct Loaded {
        var credentials: ClaudeOAuthCredentials
        var source: Source
        var root: [String: Any]
        /// 字段是否嵌套在某个 key 下（如 "claudeAiOauth"），nil 表示位于 root 顶层。
        var innerKey: String?
    }

    func load() throws -> Loaded {
        cacheLock.lock()
        let hit = cached
        cacheLock.unlock()
        if let hit { return hit }

        let loaded = try loadFromSource()
        store(loaded)
        return loaded
    }

    /// 跳过缓存，强制从来源（Keychain / 文件）重新读取。
    private func loadFromSource() throws -> Loaded {
        // 优先 Keychain（新版本 Claude Code 默认），回退到 ~/.claude/.credentials.json。
        if let data = try? readKeychainData() {
            return try parse(data: data, source: .keychain)
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            return try parse(data: data, source: .file(fileURL))
        }
        throw APIError.missingKey
    }

    private func store(_ loaded: Loaded) {
        cacheLock.lock(); cached = loaded; cacheLock.unlock()
    }

    private func invalidateCache() {
        cacheLock.lock(); cached = nil; cacheLock.unlock()
    }

    private func parse(data: Data, source: Source) throws -> Loaded {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.parse("Claude credentials not JSON")
        }
        let inner: [String: Any]
        let innerKey: String?
        if let oauth = root["claudeAiOauth"] as? [String: Any] {
            inner = oauth
            innerKey = "claudeAiOauth"
        } else {
            inner = root
            innerKey = nil
        }

        func string(_ keys: [String]) -> String? {
            for k in keys { if let v = inner[k] as? String, !v.isEmpty { return v } }
            return nil
        }

        guard let access = string(["accessToken", "access_token"]) else {
            throw APIError.missingKey
        }
        let expiresMillis: Double? = {
            // expiresAt 通常是毫秒 epoch；兼容 expires_at（秒或毫秒）。
            if let v = inner["expiresAt"] as? Double { return v }
            if let v = inner["expiresAt"] as? Int { return Double(v) }
            if let v = inner["expires_at"] as? Double { return v > 1e12 ? v : v * 1000 }
            if let v = inner["expires_at"] as? Int { let d = Double(v); return d > 1e12 ? d : d * 1000 }
            return nil
        }()

        let creds = ClaudeOAuthCredentials(
            accessToken: access,
            refreshToken: string(["refreshToken", "refresh_token"]),
            expiresAtMillis: expiresMillis,
            subscriptionType: string(["subscriptionType"]),
            rateLimitTier: string(["rateLimitTier", "rate_limit_tier"])
        )
        return Loaded(credentials: creds, source: source, root: root, innerKey: innerKey)
    }

    // MARK: - Refresh

    /// 用 refresh token 换新 access token；成功后写回来源并返回新凭证。
    ///
    /// 加了缓存后要防一种情况：Claude CLI 可能在后台自己刷新并把 refresh token 轮换写回
    /// Keychain，使我们缓存里的那个失效。若刷新因此报认证错（400/401/403），就失效缓存、
    /// 重读来源；若来源里的 refresh token 确实已经换了，再用新值重试一次。
    func refresh(_ loaded: Loaded) async throws -> ClaudeOAuthCredentials {
        do {
            return try await performRefresh(loaded)
        } catch let error where Self.isAuthError(error) {
            invalidateCache()
            guard let fresh = try? loadFromSource(),
                  fresh.credentials.refreshToken != loaded.credentials.refreshToken else {
                throw error
            }
            store(fresh)
            return try await performRefresh(fresh)
        }
    }

    private static func isAuthError(_ error: Error) -> Bool {
        if case APIError.httpStatus(let code, _) = error, (400...403).contains(code) { return true }
        return false
    }

    private func performRefresh(_ loaded: Loaded) async throws -> ClaudeOAuthCredentials {
        guard let refreshToken = loaded.credentials.refreshToken else {
            throw APIError.missingKey
        }
        let body = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID
        ])
        let data = try await postRefresh(body: body)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccess = (json["access_token"] as? String) ?? (json["accessToken"] as? String),
              !newAccess.isEmpty else {
            throw APIError.parse("Claude token refresh response missing access_token")
        }
        let newRefresh = (json["refresh_token"] as? String)
            ?? (json["refreshToken"] as? String)
            ?? refreshToken
        let newExpiresMillis: Double? = {
            if let secs = json["expires_in"] as? Double { return (Date().timeIntervalSince1970 + secs) * 1000 }
            if let secs = json["expires_in"] as? Int { return (Date().timeIntervalSince1970 + Double(secs)) * 1000 }
            if let at = json["expires_at"] as? Double { return at > 1e12 ? at : at * 1000 }
            if let at = json["expires_at"] as? Int { let d = Double(at); return d > 1e12 ? d : d * 1000 }
            return nil
        }()

        var creds = loaded.credentials
        creds.accessToken = newAccess
        creds.refreshToken = newRefresh
        creds.expiresAtMillis = newExpiresMillis

        // 写回来源，保持与 Claude CLI 同步。best-effort：写回失败不影响本次拉取。
        persist(creds, into: loaded)
        return creds
    }

    /// 依次尝试各刷新端点。遇到 4xx 认证类错误（400/401/403）说明 refresh token
    /// 本身无效，直接抛出不再换 host；遇到 429 / 5xx / 网络错误则退到下一个 host。
    private func postRefresh(body: Data) async throws -> Data {
        let headers = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "claude-code/2.1.0"
        ]
        var lastError: Error = APIError.parse("no token endpoint")
        for endpoint in Self.tokenEndpoints {
            guard let url = URL(string: endpoint) else { continue }
            do {
                return try await APIClient.post(url: url, body: body, headers: headers, timeout: 15)
            } catch let error {
                lastError = error
                if case APIError.httpStatus(let code, _) = error, (400...403).contains(code) {
                    throw error
                }
                // 429 / 5xx / 网络错误 → 试下一个 host
                continue
            }
        }
        throw lastError
    }

    // MARK: - Persist

    private func persist(_ creds: ClaudeOAuthCredentials, into loaded: Loaded) {
        // 在原始 JSON 上原地更新，保留 scopes / subscriptionType / rateLimitTier 等其它字段。
        var inner: [String: Any]
        if let key = loaded.innerKey, let dict = loaded.root[key] as? [String: Any] {
            inner = dict
        } else {
            inner = loaded.root
        }
        inner["accessToken"] = creds.accessToken
        if let r = creds.refreshToken { inner["refreshToken"] = r }
        if let ms = creds.expiresAtMillis { inner["expiresAt"] = Int(ms) }

        var root = loaded.root
        if let key = loaded.innerKey {
            root[key] = inner
        } else {
            root = inner
        }

        // 先更新进程内缓存：下一轮 load() 直接拿到新 token，不必再读 Keychain。
        // 与下面的写回相互独立——即便写回失败，内存里的新凭证仍然有效。
        var updated = loaded
        updated.credentials = creds
        updated.root = root
        store(updated)

        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) else { return }

        switch loaded.source {
        case .keychain:
            updateKeychain(data: data)
        case .file(let url):
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    // MARK: - Keychain primitives

    private func readKeychainData() throws -> Data {
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
        return data
    }

    /// 用 SecItemUpdate 仅替换数据，**保留原条目的 ACL**（这样 Claude CLI 仍能读取）。
    private func updateKeychain(data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        _ = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
    }
}

import Foundation

/// Claude 额度采集偏好，控制 OAuth 与 Web Cookie 两条路径的组合方式。
///
/// 持久化到 UserDefaults（由 AppState 负责读写）：
///   - tc.claude.cookieAsPrimary  : Bool   是否让浏览器 cookie 作为主路（OAuth 退化为 fallback）
///   - tc.claude.browserPriority  : String CSV，例如 "brave,chrome"，决定枚举顺序
struct ClaudeQuotaPreferences: Equatable, Codable {
    /// true  = cookie 为主路，OAuth 当 fallback
    /// false = OAuth 为主路（默认），仅在 429/401 时回退到 cookie
    var cookieAsPrimary: Bool

    /// 浏览器枚举顺序。空数组等价于 `ChromiumBrowser.allCases`。
    var browserPriority: [ChromiumBrowser]

    static let `default` = ClaudeQuotaPreferences(
        cookieAsPrimary: false,
        browserPriority: ChromiumBrowser.allCases
    )

    var effectiveBrowserPriority: [ChromiumBrowser] {
        browserPriority.isEmpty ? ChromiumBrowser.allCases : browserPriority
    }
}

/// 组合 OAuth + Web Cookie 两条 Claude 额度路径，**对外仍然只暴露一个 "claude" probe**。
///
/// 行为：
///   - 默认（cookieAsPrimary=false）：
///       1) 先调 OAuth；
///       2) 若 OAuth 抛 HTTP 429 / 401，自动回退到 Web Cookie；
///       3) Web Cookie 仍失败则把"主路错误"和"fallback 错误"合并抛出。
///   - cookieAsPrimary=true：
///       1) 先尝试 Web Cookie；
///       2) 任意失败回退到 OAuth。
///
/// `isAvailable` 只要任一子路径可用即为 true。
final class ClaudeCompositeQuotaProbe: QuotaProbe {
    let id = "claude"
    let displayName = "Claude"

    private let oauth: ClaudeQuotaProbe
    private let web: ClaudeWebQuotaProbe
    private let preferences: () -> ClaudeQuotaPreferences

    init(oauth: ClaudeQuotaProbe = ClaudeQuotaProbe(),
         web: ClaudeWebQuotaProbe? = nil,
         preferences: @escaping () -> ClaudeQuotaPreferences = { .default }) {
        self.oauth = oauth
        self.preferences = preferences
        // 把 preferences 里的浏览器顺序透传给 Web probe
        self.web = web ?? ClaudeWebQuotaProbe(preferredBrowsers: {
            preferences().effectiveBrowserPriority
        })
    }

    var isAvailable: Bool {
        oauth.isAvailable || web.isAvailable
    }

    func fetch() async throws -> QuotaSnapshot {
        let prefs = preferences()
        if prefs.cookieAsPrimary {
            return try await runWithFallback(primary: web, fallback: oauth, isRecoverable: { _ in true })
        } else {
            return try await runWithFallback(primary: oauth, fallback: web, isRecoverable: Self.isOAuthRecoverable)
        }
    }

    // MARK: - Fallback runner

    private func runWithFallback<P: QuotaProbe, F: QuotaProbe>(
        primary: P,
        fallback: F,
        isRecoverable: (Error) -> Bool
    ) async throws -> QuotaSnapshot {
        // 主路不可用就直接走 fallback
        guard primary.isAvailable else {
            return try await fallback.fetch()
        }
        do {
            return try await primary.fetch()
        } catch let primaryError {
            guard isRecoverable(primaryError), fallback.isAvailable else {
                throw primaryError
            }
            do {
                return try await fallback.fetch()
            } catch let fallbackError {
                // 两条路都挂了，给一个组合错误，方便日志排查
                throw ClaudeCompositeError.bothFailed(primary: primaryError, fallback: fallbackError)
            }
        }
    }

    /// OAuth 路径下，什么错误值得回退到 cookie。
    /// - 429（限流）：典型，最常见。
    /// - 401（凭证失效）：CLI token 失效或 scope 缺失，cookie 路径可能还活着。
    /// - URLError 网络错误：保守放回退。
    static func isOAuthRecoverable(_ error: Error) -> Bool {
        if case APIError.httpStatus(let code, _) = error, code == 429 || code == 401 {
            return true
        }
        if (error as? URLError) != nil {
            return true
        }
        return false
    }
}

enum ClaudeCompositeError: LocalizedError {
    case bothFailed(primary: Error, fallback: Error)

    var errorDescription: String? {
        switch self {
        case .bothFailed(let p, let f):
            return "主路径失败：\(p.localizedDescription)；备用路径也失败：\(f.localizedDescription)"
        }
    }
}

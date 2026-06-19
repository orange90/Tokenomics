import Foundation

/// 单个额度窗口（如 5 小时窗口、每周窗口）。
struct QuotaWindow: Identifiable, Equatable {
    let id: String                    // 例如 "five_hour" / "seven_day"
    let title: String                 // 用户可读名称，例如 "5 小时"
    let usedPercent: Double           // 已使用百分比，0...100
    let resetsAt: Date?               // 下一次重置时间（若可知）
    let note: String?                 // 附加备注，例如 "Sonnet" / "Opus"

    var remainingPercent: Double { max(0, 100 - usedPercent) }
}

/// 单个提供方的额度快照（Claude / Codex）。
struct QuotaSnapshot: Identifiable, Equatable {
    let id: String                    // "claude" / "codex"
    let providerName: String          // "Claude" / "Codex"
    let accountIdentifier: String?    // 例如登录邮箱或 plan 名
    let windows: [QuotaWindow]
    let fetchedAt: Date
    let source: String                // "OAuth API" / "Browser Cookie" 等

    static func == (lhs: QuotaSnapshot, rhs: QuotaSnapshot) -> Bool {
        lhs.id == rhs.id &&
        lhs.providerName == rhs.providerName &&
        lhs.accountIdentifier == rhs.accountIdentifier &&
        lhs.windows == rhs.windows &&
        lhs.fetchedAt == rhs.fetchedAt &&
        lhs.source == rhs.source
    }
}

/// 拉取额度快照的探针协议。
protocol QuotaProbe: AnyObject {
    var id: String { get }
    var displayName: String { get }
    /// 是否具备拉取条件（例如本地是否存在 OAuth 凭证文件）。
    var isAvailable: Bool { get }
    /// 拉取最新快照。失败时抛错。
    func fetch() async throws -> QuotaSnapshot
}

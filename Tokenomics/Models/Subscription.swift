import Foundation

/// 用户订阅的某个 AI 服务套餐。
/// 用于「回本没」功能：把月度套餐费与本月按 Token 折算的等值开销做对比。
struct Subscription: Identifiable, Codable, Equatable {
    var id: String
    /// 关联的供应商 ID（Provider.rawValue 或 CustomProvider.id）
    var providerKey: String
    /// 套餐名称，例如 "Plus" / "Pro" / "Max 20x"
    var planName: String
    /// 每月费用（USD）
    var monthlyUSD: Double

    init(id: String = UUID().uuidString,
         providerKey: String,
         planName: String,
         monthlyUSD: Double) {
        self.id = id
        self.providerKey = providerKey
        self.planName = planName
        self.monthlyUSD = monthlyUSD
    }
}

/// 内置常见 AI 订阅套餐预设，方便用户一键添加。
struct SubscriptionPreset: Identifiable, Hashable {
    let id: String
    let providerKey: String
    let providerDisplayName: String
    let planName: String
    let monthlyUSD: Double

    static let all: [SubscriptionPreset] = [
        // OpenAI
        .init(id: "openai-plus", providerKey: Provider.openai.rawValue,
              providerDisplayName: Provider.openai.displayName,
              planName: "ChatGPT Plus", monthlyUSD: 20),
        .init(id: "openai-pro", providerKey: Provider.openai.rawValue,
              providerDisplayName: Provider.openai.displayName,
              planName: "ChatGPT Pro", monthlyUSD: 200),
        .init(id: "openai-team", providerKey: Provider.openai.rawValue,
              providerDisplayName: Provider.openai.displayName,
              planName: "ChatGPT Team", monthlyUSD: 30),
        // Anthropic
        .init(id: "claude-pro", providerKey: Provider.anthropic.rawValue,
              providerDisplayName: Provider.anthropic.displayName,
              planName: "Claude Pro", monthlyUSD: 20),
        .init(id: "claude-max-5x", providerKey: Provider.anthropic.rawValue,
              providerDisplayName: Provider.anthropic.displayName,
              planName: "Claude Max 5x", monthlyUSD: 100),
        .init(id: "claude-max-20x", providerKey: Provider.anthropic.rawValue,
              providerDisplayName: Provider.anthropic.displayName,
              planName: "Claude Max 20x", monthlyUSD: 200)
    ]

    /// 根据 quota probe 的 id（"claude" / "codex"）和 accountIdentifier
    /// （例如 "Claude Pro" / "Claude Max_20x" / "foo@bar · Plus" / "Codex Business"）
    /// 推断出最匹配的预设套餐。无法识别则返回 nil。
    static func match(probeID: String, accountIdentifier: String?) -> SubscriptionPreset? {
        let id = probeID.lowercased()
        let raw = (accountIdentifier ?? "").lowercased()
        switch id {
        case "claude":
            // 形如 "claude max_20x" / "claude max_5x" / "claude max" / "claude pro"
            if raw.contains("max") {
                if raw.contains("20") { return all.first { $0.id == "claude-max-20x" } }
                if raw.contains("5")  { return all.first { $0.id == "claude-max-5x" } }
                // 没指明倍数时按更常见的 5x 处理
                return all.first { $0.id == "claude-max-5x" }
            }
            if raw.contains("pro") {
                return all.first { $0.id == "claude-pro" }
            }
            // 兜底：能识别到 probe 但 plan 字段未知，按 Pro 起步价处理
            return all.first { $0.id == "claude-pro" }
        case "codex":
            // 形如 "foo@bar · plus" / "codex pro" / "codex business"
            if raw.contains("pro") {
                return all.first { $0.id == "openai-pro" }
            }
            if raw.contains("team") || raw.contains("business") {
                return all.first { $0.id == "openai-team" }
            }
            if raw.contains("plus") {
                return all.first { $0.id == "openai-plus" }
            }
            // 兜底：未知 plan 至少标个 Plus 起步价
            return all.first { $0.id == "openai-plus" }
        default:
            return nil
        }
    }
}

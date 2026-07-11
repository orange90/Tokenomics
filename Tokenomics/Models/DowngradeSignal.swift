import Foundation
import SwiftData

/// 一次"Claude 是否被降级/加标"的观察事件。
///
/// **设计边界（重要）**：
/// 这个模型**不试图**读取 Anthropic 内部的路由标签字符串
/// （例如推文里出现过的 `TOO_DUMB_TO_NEED_FABLE`），因为公开 API 不暴露那些字段。
/// 它只记录**客户端可以观察到的行为特征**，据此推断是否发生了降级：
///   - `requestedModel`：客户端在请求里指定的模型
///   - `servedModel`：响应体 `model` 字段实际返回的模型
///   - `verdict`：规则引擎的判定
///   - `headersDigest`：可疑响应头的紧凑摘要（`x-*` / `anthropic-*`），用于人工比对
///
/// Verdict 语义：
///   - `.clean`         🟢 未发现异常
///   - `.suspicious`    🟡 模型一致但存在其它可疑迹象（如 output_tokens 极低、新出现的头字段）
///   - `.downgraded`    🔴 明确降级（请求 model 与响应 model 属于不同档位，且响应档位低于请求档位）
///
enum DowngradeVerdict: String, Codable, CaseIterable {
    case clean
    case suspicious
    case downgraded
}

/// 事件来源：主动金标探测 or 从被动流量里嗅探出来的。
enum DowngradeSource: String, Codable, CaseIterable {
    case activeCanary  // ClaudeDowngradeProbe 发出的定期金标 prompt
    case passiveLog    // 从 ~/.claude/projects/*.jsonl 里读到的请求
}

@Model
final class DowngradeSignal {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var sourceRaw: String        // DowngradeSource.rawValue
    var verdictRaw: String       // DowngradeVerdict.rawValue
    var requestedModel: String
    var servedModel: String
    /// 结构化摘要：模型档位对比 / 输出 tokens / 头字段 diff 等，JSON 字符串。
    var detailsJSON: String
    /// 可读描述，直接展示到 UI。
    var summary: String
    /// 请求耗时（秒）。仅 activeCanary 有值。
    var elapsedSeconds: Double?
    /// canary 探测请求发送的 prompt 名称；被动信号为 nil。
    var canaryName: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: DowngradeSource,
        verdict: DowngradeVerdict,
        requestedModel: String,
        servedModel: String,
        summary: String,
        detailsJSON: String = "{}",
        elapsedSeconds: Double? = nil,
        canaryName: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sourceRaw = source.rawValue
        self.verdictRaw = verdict.rawValue
        self.requestedModel = requestedModel
        self.servedModel = servedModel
        self.summary = summary
        self.detailsJSON = detailsJSON
        self.elapsedSeconds = elapsedSeconds
        self.canaryName = canaryName
    }

    var source: DowngradeSource {
        DowngradeSource(rawValue: sourceRaw) ?? .passiveLog
    }

    var verdict: DowngradeVerdict {
        DowngradeVerdict(rawValue: verdictRaw) ?? .clean
    }
}

/// Claude 模型档位。数字越大档位越高。
/// 用于快速判定"降级"：请求 tier > 返回 tier ⇒ 明确降级。
enum ClaudeModelTier: Int, Comparable {
    case unknown = 0
    case haiku = 1
    case sonnet = 2
    case opus = 3

    static func < (lhs: ClaudeModelTier, rhs: ClaudeModelTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// 从 Anthropic 模型名推断档位。忽略版本号后缀。
    static func fromModelName(_ raw: String) -> ClaudeModelTier {
        let lower = raw.lowercased()
        if lower.contains("opus")   { return .opus }
        if lower.contains("sonnet") { return .sonnet }
        if lower.contains("haiku")  { return .haiku }
        // Anthropic 未来可能推出的其他系列：默认 unknown，规则引擎里按"未知"处理，不误报。
        return .unknown
    }
}

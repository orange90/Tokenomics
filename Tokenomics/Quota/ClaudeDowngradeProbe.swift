import Foundation

/// Claude "被降级/加标" 主动探测器。
///
/// 工作原理：
/// 1. 用一组预设的**金标 prompt**（Canary）以固定参数打 `/v1/messages`；
/// 2. 记录 `response.model` / `usage.output_tokens` / 请求耗时；
/// 3. 与首次运行时锁定的**基线快照**做 diff，任何偏移都落一条 `DowngradeSignal`。
///
/// 检测能力（**只做行为推断**）：
///   🔴 downgraded — `ClaudeModelTier(response.model) < ClaudeModelTier(request.model)`
///   🟡 suspicious — 同 tier 但 output_tokens 相比基线掉 ≥ 40%
///   🟢 clean      — 无异常
///
/// **明确的边界**：本模块**读不到** Anthropic 内部路由标签（例如推文里的
/// `TOO_DUMB_TO_NEED_FABLE`）。公开 API 不暴露这类字段，本模块也不做抓包/破解。
///
/// **凭证要求**：需要一个用户级 API key（`sk-ant-api03-...`），存放在 Keychain
/// 的 `KeychainKey.anthropicCanary`。如果用户没设，直接跳过（isAvailable = false）。
@MainActor
final class ClaudeDowngradeProbe {
    struct CanaryPrompt {
        let name: String
        let model: String
        let system: String?
        let user: String
        let maxTokens: Int
    }

    /// 默认金标：三条极小、语义稳定、便于对比的 prompt。
    /// 都请求高档模型（opus / sonnet），这样只要被降到 haiku 就一定能命中降级判定。
    static let defaultCanaries: [CanaryPrompt] = [
        CanaryPrompt(
            name: "arithmetic-opus",
            model: "claude-opus-4-1",
            system: nil,
            user: "Compute 17 * 23. Reply with only the number.",
            maxTokens: 20
        ),
        CanaryPrompt(
            name: "reasoning-sonnet",
            model: "claude-sonnet-4-5",
            system: "Answer briefly.",
            user: "If today is Wednesday, what day was it 100 days ago? Reply with a single weekday name.",
            maxTokens: 30
        ),
        CanaryPrompt(
            name: "identity-sonnet",
            model: "claude-sonnet-4-5",
            system: nil,
            user: "In one word, what is your model family?",
            maxTokens: 10
        )
    ]

    private let keychain: KeychainService
    private let repository: DowngradeRepository
    private let onLog: (String) -> Void
    /// 基线：canary name -> 首次成功时的 output_tokens。用 UserDefaults 持久化。
    @MainActor private var baselineTokens: [String: Int]
    private let baselineKey = "tc.downgradeCanaryBaseline.v1"

    init(
        keychain: KeychainService,
        repository: DowngradeRepository,
        onLog: @escaping (String) -> Void = { _ in }
    ) {
        self.keychain = keychain
        self.repository = repository
        self.onLog = onLog
        if let data = UserDefaults.standard.string(forKey: baselineKey)?.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String: Int].self, from: data) {
            self.baselineTokens = parsed
        } else {
            self.baselineTokens = [:]
        }
    }

    var isAvailable: Bool {
        guard let key = keychain.get(KeychainKey.anthropicCanary), !key.isEmpty else { return false }
        // Admin key 不能调 Messages API，这里做个前缀提示（不严格拒绝，因为 key 前缀可能演进）。
        return !key.hasPrefix("sk-ant-admin-")
    }

    /// 运行一轮全部金标；每条 canary 结果落一条 `DowngradeSignal`。
    /// 返回本轮实际写入的事件数量。
    @discardableResult
    func runOnce(canaries: [CanaryPrompt] = ClaudeDowngradeProbe.defaultCanaries) async -> Int {
        guard let apiKey = keychain.get(KeychainKey.anthropicCanary), !apiKey.isEmpty else {
            onLog("Downgrade probe: canary key not configured, skip.")
            return 0
        }
        var written = 0
        for c in canaries {
            do {
                let result = try await sendOne(canary: c, apiKey: apiKey)
                let signal = analyze(canary: c, result: result)
                if repository.append(signal) {
                    written += 1
                }
            } catch {
                onLog("Downgrade canary [\(c.name)] failed: \(error.localizedDescription)")
            }
        }
        return written
    }

    // MARK: - HTTP

    private struct MessageResult {
        let servedModel: String
        let outputTokens: Int
        let inputTokens: Int
        let stopReason: String?
        let elapsed: TimeInterval
    }

    private func sendOne(canary: CanaryPrompt, apiKey: String) async throws -> MessageResult {
        var body: [String: Any] = [
            "model": canary.model,
            "max_tokens": canary.maxTokens,
            "temperature": 0,
            "messages": [
                ["role": "user", "content": canary.user]
            ]
        ]
        if let sys = canary.system { body["system"] = sys }
        let data = try JSONSerialization.data(withJSONObject: body)
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw APIError.parse("bad url")
        }
        let start = Date()
        let response = try await APIClient.post(
            url: url,
            body: data,
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json"
            ],
            timeout: 30
        )
        let elapsed = Date().timeIntervalSince(start)
        guard let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any] else {
            throw APIError.parse("messages response not JSON")
        }
        let served = (json["model"] as? String) ?? "unknown"
        let stop = json["stop_reason"] as? String
        let usage = json["usage"] as? [String: Any]
        let output = (usage?["output_tokens"] as? Int) ?? 0
        let input = (usage?["input_tokens"] as? Int) ?? 0
        return MessageResult(
            servedModel: served,
            outputTokens: output,
            inputTokens: input,
            stopReason: stop,
            elapsed: elapsed
        )
    }

    // MARK: - Rule engine

    private func analyze(canary: CanaryPrompt, result: MessageResult) -> DowngradeSignal {
        let reqTier = ClaudeModelTier.fromModelName(canary.model)
        let servedTier = ClaudeModelTier.fromModelName(result.servedModel)

        var verdict: DowngradeVerdict = .clean
        var reasons: [String] = []

        // Rule 1: tier 明确下降
        if reqTier != .unknown && servedTier != .unknown && servedTier < reqTier {
            verdict = .downgraded
            reasons.append("tier drop: \(canary.model) → \(result.servedModel)")
        }

        // Rule 2: 基线 output_tokens 相比首次运行大幅下降（≥ 40%）
        let baseline = baselineTokens[canary.name]
        if let base = baseline, base >= 5 {
            let ratio = Double(result.outputTokens) / Double(base)
            if ratio <= 0.6 && verdict != .downgraded {
                verdict = .suspicious
                reasons.append(String(format: "output tokens dropped: %d → %d (%.0f%% of baseline)",
                                      base, result.outputTokens, ratio * 100))
            }
        } else {
            // 首次运行：写入基线。
            baselineTokens[canary.name] = result.outputTokens
            persistBaseline()
            reasons.append("baseline seeded: \(result.outputTokens) output tokens")
        }

        // Rule 3: stop_reason 异常（如意外的 refusal / max_tokens 但基线不是）
        if let stop = result.stopReason, stop != "end_turn" && stop != "stop_sequence" {
            if verdict == .clean { verdict = .suspicious }
            reasons.append("unusual stop_reason: \(stop)")
        }

        let summary: String
        switch verdict {
        case .downgraded:
            summary = "Downgrade detected: requested \(canary.model), served \(result.servedModel)"
        case .suspicious:
            summary = "Suspicious: \(reasons.joined(separator: "; "))"
        case .clean:
            summary = "Clean (\(result.servedModel), \(result.outputTokens) out tok)"
        }

        let detailPayload: [String: Any] = [
            "canary": canary.name,
            "requestedModel": canary.model,
            "servedModel": result.servedModel,
            "outputTokens": result.outputTokens,
            "inputTokens": result.inputTokens,
            "baselineOutputTokens": baseline as Any,
            "stopReason": result.stopReason as Any,
            "elapsedSeconds": result.elapsed,
            "reasons": reasons,
            "requestedTier": reqTier.rawValue,
            "servedTier": servedTier.rawValue
        ]
        let detailJSON = (try? JSONSerialization.data(withJSONObject: detailPayload, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return DowngradeSignal(
            source: .activeCanary,
            verdict: verdict,
            requestedModel: canary.model,
            servedModel: result.servedModel,
            summary: summary,
            detailsJSON: detailJSON,
            elapsedSeconds: result.elapsed,
            canaryName: canary.name
        )
    }

    private func persistBaseline() {
        if let data = try? JSONEncoder().encode(baselineTokens),
           let str = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(str, forKey: baselineKey)
        }
    }

    /// 允许用户从设置里"重置基线"。
    func resetBaseline() {
        baselineTokens = [:]
        UserDefaults.standard.removeObject(forKey: baselineKey)
    }
}

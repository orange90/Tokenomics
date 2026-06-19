import Foundation

/// Anthropic Admin Usage API。
/// 需要 admin API key（sk-ant-admin-...），通过 /v1/organizations/usage_report/messages 获取。
final class AnthropicAPICollector: UsageCollector {
    let id = "anthropic-api"
    let displayName = "Anthropic API"

    private let keychain: KeychainService
    init(keychain: KeychainService) { self.keychain = keychain }

    var isEnabled: Bool { keychain.hasKey(KeychainKey.anthropic) }

    func collect(since: Date?) async throws -> [UsageRecord] {
        guard let key = keychain.get(KeychainKey.anthropic), !key.isEmpty else { throw APIError.missingKey }
        let startDate = since ?? Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let startStr = iso.string(from: startDate)
        let urlStr = "https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at=\(startStr)&bucket_width=1d"
        guard let url = URL(string: urlStr) else { return [] }
        let data = try await APIClient.get(url: url, headers: [
            "x-api-key": key,
            "anthropic-version": "2023-06-01"
        ])
        return parse(data: data)
    }

    private func parse(data: Data) -> [UsageRecord] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buckets = json["data"] as? [[String: Any]] else { return [] }
        var records: [UsageRecord] = []
        for bucket in buckets {
            let ts = DateParsing.parse(bucket["starting_at"])
            guard let results = bucket["results"] as? [[String: Any]] else { continue }
            for r in results {
                let rawModel = (r["model"] as? String) ?? "claude-sonnet-4"
                let model = Self.normalizeModelName(rawModel)
                let input = (r["uncached_input_tokens"] as? Int) ?? (r["input_tokens"] as? Int) ?? 0
                let output = (r["output_tokens"] as? Int) ?? 0
                let cw = (r["cache_creation_input_tokens"] as? Int) ?? 0
                let cr = (r["cache_read_input_tokens"] as? Int) ?? 0
                if input == 0 && output == 0 && cw == 0 && cr == 0 { continue }
                records.append(UsageRecord(
                    timestamp: ts,
                    provider: Provider.anthropic.rawValue,
                    model: model,
                    sourceApp: "Anthropic API",
                    inputTokens: input,
                    outputTokens: output,
                    cacheCreationTokens: cw,
                    cacheReadTokens: cr
                ))
            }
        }
        return records
    }

    /// 将 Anthropic Admin Usage API 返回的带日期戳模型名归一化为定价表里的基础名。
    /// 例如：
    ///   "claude-sonnet-4-5-20250929" -> "claude-sonnet-4-5"
    ///   "claude-3-5-sonnet-20241022" -> "claude-3-5-sonnet"
    ///   "claude-opus-4-1-20250805"   -> "claude-opus-4-1"
    /// 不带日期戳的模型名原样返回。
    static func normalizeModelName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: "-\\d{6,8}$") else { return trimmed }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let stripped = regex.stringByReplacingMatches(in: trimmed, range: range, withTemplate: "")
        return stripped.isEmpty ? trimmed : stripped
    }
}

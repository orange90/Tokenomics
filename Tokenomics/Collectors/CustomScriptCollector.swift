import Foundation

/// 把一条 CustomProvider 包装成 UsageCollector。
/// 用法：CollectorRegistry.makeAll 时从 SwiftData 读出所有 CustomProvider，
/// 对每条 isCollectionEnabled == true 的实例生成一个 CustomScriptCollector。
final class CustomScriptCollector: UsageCollector {
    let id: String
    let displayName: String
    private let endpointURL: String
    private let httpMethod: String
    private let headersJSON: String
    private let bodyJSON: String?
    private let recordsPath: String
    private let modelField: String
    private let inputTokensField: String
    private let outputTokensField: String
    private let timestampField: String?
    private let costField: String?
    private let requestIdField: String?

    /// 用于写入 UsageRecord.provider，与 CustomProvider.id 完全一致
    private let providerKey: String

    /// 构造时把 SwiftData 实例的字段全部"拷"进来——避免在后台线程触碰 @Model。
    @MainActor
    init(provider: CustomProvider) {
        self.id = "custom-\(provider.id)"
        self.displayName = provider.name
        self.endpointURL = provider.endpointURL
        self.httpMethod = provider.httpMethod.uppercased()
        self.headersJSON = provider.headersJSON
        self.bodyJSON = provider.bodyJSON
        self.recordsPath = provider.recordsPath
        self.modelField = provider.modelField
        self.inputTokensField = provider.inputTokensField
        self.outputTokensField = provider.outputTokensField
        self.timestampField = provider.timestampField
        self.costField = provider.costField
        self.requestIdField = provider.requestIdField
        self.providerKey = provider.id
    }

    var isEnabled: Bool {
        !endpointURL.isEmpty && URL(string: endpointURL) != nil
    }

    func collect(since: Date?) async throws -> [UsageRecord] {
        guard let url = URL(string: endpointURL) else { return [] }
        let headers = parseHeaders()
        let data: Data
        if httpMethod == "POST" {
            let body = bodyJSON?.data(using: .utf8) ?? Data()
            data = try await APIClient.post(url: url, body: body, headers: headers)
        } else {
            data = try await APIClient.get(url: url, headers: headers)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }

        // 取出记录数组
        let arr: [Any]
        if recordsPath.isEmpty {
            arr = (root as? [Any]) ?? []
        } else {
            arr = (JSONPathResolver.value(at: recordsPath, in: root) as? [Any]) ?? []
        }

        var out: [UsageRecord] = []
        for item in arr {
            let model = (JSONPathResolver.value(at: modelField, in: item) as? String) ?? "unknown"
            let input = toInt(JSONPathResolver.value(at: inputTokensField, in: item))
            let output = toInt(JSONPathResolver.value(at: outputTokensField, in: item))
            let ts: Date = timestampField.flatMap {
                JSONPathResolver.value(at: $0, in: item)
            }.map { DateParsing.parse($0) } ?? Date()
            let cost: Double = costField.flatMap {
                toDouble(JSONPathResolver.value(at: $0, in: item))
            } ?? 0
            let rid: String? = requestIdField.flatMap {
                JSONPathResolver.value(at: $0, in: item) as? String
            }
            // since 过滤
            if let since, ts < since { continue }
            // 全为 0 的记录跳过，避免脏数据
            if input == 0 && output == 0 && cost == 0 { continue }
            out.append(UsageRecord(
                timestamp: ts,
                provider: providerKey,
                model: model,
                sourceApp: displayName,
                inputTokens: input,
                outputTokens: output,
                costUSD: cost,
                requestId: rid
            ))
        }
        return out
    }

    private func parseHeaders() -> [String: String] {
        guard let d = headersJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (k, v) in obj { result[k] = "\(v)" }
        return result
    }

    private func toInt(_ raw: Any?) -> Int {
        if let n = raw as? Int { return n }
        if let n = raw as? Double { return Int(n) }
        if let s = raw as? String, let n = Int(s) { return n }
        return 0
    }

    private func toDouble(_ raw: Any?) -> Double {
        if let n = raw as? Double { return n }
        if let n = raw as? Int { return Double(n) }
        if let s = raw as? String, let n = Double(s) { return n }
        return 0
    }
}

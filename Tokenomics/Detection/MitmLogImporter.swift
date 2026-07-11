import Foundation

/// P4 支撑：把用户自己抓的 mitmproxy 流 / HAR 文件解析成 `[PromptStegoHit]`。
///
/// 我们**不**做 MITM，也**不**代替用户装 mitmproxy CA。用户按 UI 引导装好后，
/// 自己 `mitmproxy` 抓一段 → 导出 flow（JSON）或 HAR；我们负责读该文件，
/// 找出 `api.anthropic.com/v1/messages` 的请求体，把请求体里 `system` 与
/// `messages[*].content` 里出现的 `Today's date` 段落喂给
/// [ClaudeLocalPromptScanner.scan(text:source:filePath:timestamp:)](file:///.../ClaudeLocalPromptScanner.swift)。
///
/// 支持两种格式：
///   1. **HAR 1.2**（推荐）—— 结构稳定，字段清晰。
///      入口：`log.entries[].request.postData.text` + `log.entries[].request.url`。
///   2. **mitmproxy `.flow` 导出的 JSON**（`mitmweb` → "Export → JSON" 或
///      `mitmdump -w flows.json`）——顶层是数组，每条含 `request.content`（base64）、
///      `request.pretty_host`、`request.path`。
enum MitmLogImporter {

    enum ImportError: Error, LocalizedError {
        case unreadable
        case unknownFormat
        case parseFailed(String)

        var errorDescription: String? {
            switch self {
            case .unreadable:                return "无法读取导入的日志文件"
            case .unknownFormat:             return "无法识别的日志格式（既不是 HAR 也不是 mitmproxy JSON）"
            case .parseFailed(let s):        return "解析失败：\(s)"
            }
        }
    }

    /// 用户导入的抓包文件 → 命中列表。
    /// - Parameter fileURL: 用户从 NSOpenPanel 选择的 .har / .json / .flow.json。
    static func importAndScan(fileURL: URL) throws -> [PromptStegoHit] {
        guard let data = try? Data(contentsOf: fileURL) else { throw ImportError.unreadable }
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            throw ImportError.parseFailed("非 JSON 格式")
        }

        // 判定格式
        if let dict = root as? [String: Any],
           let log = dict["log"] as? [String: Any],
           let entries = log["entries"] as? [[String: Any]] {
            return scanHAREntries(entries, sourceFile: fileURL)
        }
        if let arr = root as? [[String: Any]] {
            return scanMitmFlows(arr, sourceFile: fileURL)
        }
        throw ImportError.unknownFormat
    }

    // MARK: - HAR 1.2

    private static func scanHAREntries(_ entries: [[String: Any]], sourceFile: URL) -> [PromptStegoHit] {
        var hits: [PromptStegoHit] = []
        for e in entries {
            guard let req = e["request"] as? [String: Any],
                  let url = req["url"] as? String,
                  isAnthropicMessagesEndpoint(url) else { continue }
            let ts: Date? = (e["startedDateTime"] as? String).flatMap {
                ISO8601DateFormatter().date(from: $0)
            }
            let body: String? = {
                if let post = req["postData"] as? [String: Any], let t = post["text"] as? String { return t }
                return nil
            }()
            guard let bodyText = body else { continue }
            let extracted = extractTodaysDateChunks(fromBody: bodyText)
            for chunk in extracted {
                hits.append(contentsOf: ClaudeLocalPromptScanner.scan(
                    text: chunk,
                    source: .mitmLog,
                    filePath: sourceFile,
                    timestamp: ts
                ))
            }
        }
        return hits
    }

    // MARK: - mitmproxy JSON dump

    private static func scanMitmFlows(_ flows: [[String: Any]], sourceFile: URL) -> [PromptStegoHit] {
        var hits: [PromptStegoHit] = []
        for f in flows {
            guard let req = f["request"] as? [String: Any] else { continue }
            let host = (req["pretty_host"] as? String)
                ?? (req["host"] as? String)
                ?? ""
            let path = (req["path"] as? String) ?? ""
            let url = "https://\(host)\(path)"
            guard isAnthropicMessagesEndpoint(url) else { continue }

            let bodyText: String? = {
                // mitmproxy 通常把 content base64 编码放在 request.content
                if let b64 = req["content"] as? String,
                   let d = Data(base64Encoded: b64),
                   let s = String(data: d, encoding: .utf8) { return s }
                if let txt = req["text"] as? String { return txt }
                return nil
            }()
            guard let body = bodyText else { continue }
            let ts: Date? = (f["timestamp_start"] as? Double).map { Date(timeIntervalSince1970: $0) }
            for chunk in extractTodaysDateChunks(fromBody: body) {
                hits.append(contentsOf: ClaudeLocalPromptScanner.scan(
                    text: chunk,
                    source: .mitmLog,
                    filePath: sourceFile,
                    timestamp: ts
                ))
            }
        }
        return hits
    }

    // MARK: - helpers

    private static func isAnthropicMessagesEndpoint(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains("api.anthropic.com") && lower.contains("/v1/messages")
    }

    /// 从请求 body 里抽取"包含 today's date 锚点的片段"。
    /// 请求体通常是 JSON：`system` 字段 + `messages[*].content` 字段。为了不用完整
    /// JSON schema 做严格匹配（Anthropic 可能改结构），我们直接把整个 body 字符串
    /// 也传下去当作候选（Unicode 扫描是无损的，误报几乎为零）。
    private static func extractTodaysDateChunks(fromBody body: String) -> [String] {
        var chunks: [String] = [body]  // 全文本兜底
        if let data = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let sys = obj["system"] as? String { chunks.append(sys) }
            if let sysArr = obj["system"] as? [[String: Any]] {
                for item in sysArr {
                    if let t = item["text"] as? String { chunks.append(t) }
                }
            }
            if let messages = obj["messages"] as? [[String: Any]] {
                for m in messages {
                    if let s = m["content"] as? String { chunks.append(s) }
                    if let parts = m["content"] as? [[String: Any]] {
                        for p in parts {
                            if let t = p["text"] as? String { chunks.append(t) }
                        }
                    }
                }
            }
        }
        return chunks
    }
}

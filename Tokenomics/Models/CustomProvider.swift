import Foundation
import SwiftData

/// 用户自定义供应商。
///
/// 数据流：
/// 1. UI 在「设置 → 供应商」中创建一条 CustomProvider；
/// 2. AppState 在 bootstrap / 用户保存后重新构造 CollectorRegistry，
///    把这些 CustomProvider 包装成 CustomScriptCollector 注入 RefreshScheduler；
/// 3. CustomScriptCollector 按 endpointURL + headersJSON 发请求，
///    再按 recordsPath / 字段路径把 JSON 解析成 UsageRecord 入库。
///
/// 字段路径采用「点 + 数组下标」语法，例如 "data.usage[0].input_tokens"。
/// 全部解析使用 JSONPathResolver。
@Model
final class CustomProvider {
    /// 稳定唯一 ID（同时作为 Provider.rawValue 出现在 UsageRecord.provider 中），
    /// 形如 "custom:8F0E..."。一旦创建不再变更，重命名/换色不影响历史聚合。
    @Attribute(.unique) var id: String

    /// 展示名（用于侧边栏、汇总、API Key 列表）
    var name: String

    /// 品牌色（#RRGGBB），用于图标
    var colorHex: String

    /// 是否在 UI 中显示
    var isVisible: Bool

    /// 是否参与 RefreshScheduler 拉取
    var isCollectionEnabled: Bool

    // --- HTTP 配置 ---

    /// 拉取地址，例如 "https://api.example.com/v1/usage"
    var endpointURL: String

    /// HTTP 方法："GET" / "POST"
    var httpMethod: String

    /// JSON 编码的 headers 字典字符串，例如 {"Authorization":"Bearer ..."}.
    /// 这里直接存明文：API Key 由用户自行决定是否写在 Header 里。
    /// 注：内置供应商的 key 走 Keychain；自定义供应商以「外接脚本端点」为定位，
    /// 通常用户填的是公司内网或自建汇总接口，这里保持简单。
    var headersJSON: String

    /// POST 请求体（可空）。GET 时忽略。
    var bodyJSON: String?

    // --- 响应字段映射 ---

    /// 记录数组在响应里的路径，例如 "data.records"。
    /// 若整个响应本身就是数组，留空字符串。
    var recordsPath: String

    /// 单条记录里"模型名"的字段路径，例如 "model"
    var modelField: String

    /// 输入 token 字段路径
    var inputTokensField: String

    /// 输出 token 字段路径
    var outputTokensField: String

    /// 时间戳字段路径（可空，缺省用当次拉取时间）
    var timestampField: String?

    /// 费用字段路径（USD，可空）
    var costField: String?

    /// 请求 ID 字段路径（可空，参与去重）
    var requestIdField: String?

    var createdAt: Date

    init(
        id: String = "custom:\(UUID().uuidString)",
        name: String,
        colorHex: String = "#6366F1",
        isVisible: Bool = true,
        isCollectionEnabled: Bool = false,
        endpointURL: String = "",
        httpMethod: String = "GET",
        headersJSON: String = "{}",
        bodyJSON: String? = nil,
        recordsPath: String = "",
        modelField: String = "model",
        inputTokensField: String = "input_tokens",
        outputTokensField: String = "output_tokens",
        timestampField: String? = "timestamp",
        costField: String? = "cost_usd",
        requestIdField: String? = "id",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isVisible = isVisible
        self.isCollectionEnabled = isCollectionEnabled
        self.endpointURL = endpointURL
        self.httpMethod = httpMethod
        self.headersJSON = headersJSON
        self.bodyJSON = bodyJSON
        self.recordsPath = recordsPath
        self.modelField = modelField
        self.inputTokensField = inputTokensField
        self.outputTokensField = outputTokensField
        self.timestampField = timestampField
        self.costField = costField
        self.requestIdField = requestIdField
        self.createdAt = createdAt
    }
}

/// 简易 JSON Path 求值：支持 "a.b[0].c"。
enum JSONPathResolver {
    static func value(at path: String, in json: Any) -> Any? {
        guard !path.isEmpty else { return json }
        var current: Any? = json
        let tokens = tokenize(path)
        for token in tokens {
            guard let cur = current else { return nil }
            switch token {
            case .key(let k):
                if let dict = cur as? [String: Any] { current = dict[k] }
                else { return nil }
            case .index(let i):
                if let arr = cur as? [Any], i >= 0, i < arr.count { current = arr[i] }
                else { return nil }
            }
        }
        return current
    }

    private enum Token { case key(String); case index(Int) }

    private static func tokenize(_ path: String) -> [Token] {
        var tokens: [Token] = []
        var buf = ""
        var i = path.startIndex
        func flushKey() {
            if !buf.isEmpty { tokens.append(.key(buf)); buf = "" }
        }
        while i < path.endIndex {
            let c = path[i]
            if c == "." {
                flushKey()
            } else if c == "[" {
                flushKey()
                var num = ""
                i = path.index(after: i)
                while i < path.endIndex, path[i] != "]" {
                    num.append(path[i])
                    i = path.index(after: i)
                }
                if let n = Int(num) { tokens.append(.index(n)) }
            } else {
                buf.append(c)
            }
            if i < path.endIndex { i = path.index(after: i) }
        }
        flushKey()
        return tokens
    }
}

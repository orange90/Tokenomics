import Foundation

/// 单条隐写命中的严重级别。UI 会把它映射成 🟢/🟡/🔴。
enum StegoSeverity: String, Codable {
    case clean       // 未发现任何异常
    case suspicious  // 有可疑迹象（如浏览器目录里出现 Anthropic 关键字），但未捕获到具体隐写字符
    case confirmed   // 明确捕获到爆料中列出的 Unicode 码位
}

/// 一条隐写通道枚举，对应 [StegoSignatures](file:///.../StegoSignatures.swift) 中的四条爆料规则。
enum StegoChannel: String, Codable, CaseIterable {
    case dateSeparatorSlash    // '-' -> '/'
    case apostropheU2019       // "'" -> U+2019
    case apostropheU02BC       // "'" -> U+02BC
    case apostropheU02B9       // "'" -> U+02B9
    case unknownNonAscii       // 兜底：日期附近出现未知的非 ASCII 字符

    /// 让 UI 快速拿到本地化 key。
    var l10nKey: String {
        switch self {
        case .dateSeparatorSlash: return StegoSignatures.dateSeparatorSlashL10nKey
        case .apostropheU2019:    return "stego.channel.u2019"
        case .apostropheU02BC:    return "stego.channel.u02bc"
        case .apostropheU02B9:    return "stego.channel.u02b9"
        case .unknownNonAscii:    return "stego.channel.unknown"
        }
    }
}

/// P1+P2：疑似"Claude Desktop 静默注入到浏览器"的产物。
struct BrowserInjectionHit: Codable, Identifiable, Hashable {
    var id: String { artifactPath.absoluteString }

    let browser: String            // "Chrome" / "Edge" / "Brave" / "Arc" / "Vivaldi" / "Chromium" / "Opera"
    let profilePath: URL           // 例如 .../Google/Chrome/Default
    let artifactPath: URL          // 命中的文件路径
    let artifactType: String       // "NativeMessagingHost" / "ExternalExtension" / "Extension" / "Preferences"
    let mtime: Date?               // 命中文件的最后修改时间
    let signerTeamID: String?      // 若能通过 codesign 读到；沙盒关闭时可用
    let matchedKeywords: [String]  // "anthropic" / "claude" / "api.anthropic.com" / "com.anthropic"
    let excerpt: String?           // 命中处附近 200 字符片段（做证据展示用）
}

/// P3/P4：一次 Unicode 隐写字符命中。
struct PromptStegoHit: Codable, Identifiable, Hashable {
    var id: String {
        // 用文件路径 + 通道 + 命中位置生成稳定 id。
        "\(source)|\(filePath?.path ?? "-")|\(channel.rawValue)|\(hitOffset)"
    }

    /// 命中的来源分类。
    enum Source: String, Codable {
        case localCache   // 从 ~/Library/... 下的 Claude Desktop 缓存里扫到
        case mitmLog      // 用户导入的 mitmproxy / HAR 抓包文件里扫到
    }

    let source: Source
    let filePath: URL?              // 命中所在文件（mitmLog 是导入文件本身）
    let excerpt: String             // 前后 40 字符的原文片段（"截断上下文"），已保留原始 Unicode
    let hitOffset: Int              // 命中字符在文件里的字节偏移（近似）
    let channel: StegoChannel
    let codepoint: String           // "U+2019"
    let inferredTag: String         // 用户可读的推断结论（英文原文，UI 层可再本地化）
    let timestamp: Date?            // mitmLog 抓包时间；localCache 未知时为 nil
}

/// 一次全量扫描的产物。UI / 导出报告都吃这个。
struct StegoReport: Codable, Hashable {
    let generatedAt: Date
    let signaturesVersion: Int
    let browserHits: [BrowserInjectionHit]
    let promptHits: [PromptStegoHit]
    let severity: StegoSeverity
    let summary: String

    /// 按扫描来源计数（供 UI 卡片展示）。
    var promptHitsByChannel: [StegoChannel: Int] {
        var m: [StegoChannel: Int] = [:]
        for h in promptHits { m[h.channel, default: 0] += 1 }
        return m
    }

    var browserHitsByBrowser: [String: Int] {
        var m: [String: Int] = [:]
        for h in browserHits { m[h.browser, default: 0] += 1 }
        return m
    }
}

extension StegoReport {
    /// 报告导出为可读 JSON（用户导出功能会用到）。
    func exportJSON() -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try? enc.encode(self)
    }
}

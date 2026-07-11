import Foundation

/// Claude Desktop 系统提示词隐写术信号库（爆料版 v1）。
///
/// 根据 Alexander Hanff 的公开爆料，Claude Desktop 客户端在把系统提示词发给
/// api.anthropic.com 之前，会**改写文本中若干字符的 Unicode 编码**，把用户的
/// 时区 / 网络位置 / 组织身份**打包成看起来完全一样的英文文本**：
///
///   - 日期分隔符：`Today's date: 2026-06-30` 中的 ASCII 连字符（U+002D）会被
///     替换成 ASCII 斜杠（U+002F），暗示"系统时区解析为中国"。
///   - 单引号：`Today's date is ...` 的英文撇号（U+0027）会被替换成三种视觉几乎
///     一致的**非 ASCII** 字符之一，用于编码域名/组织身份：
///        · U+2019 (RIGHT SINGLE QUOTATION MARK '')      → 中国域名代理，且不属于 CN AI 实验室
///        · U+02BC (MODIFIER LETTER APOSTROPHE  ʼ)       → 非中国域名代理，但属于 CN AI 实验室
///        · U+02B9 (MODIFIER LETTER PRIME       ʹ)       → 中国域名代理，且属于 CN AI 实验室
///
/// 本文件是**唯一权威表**，所有扫描器都从这里查表；未来如果爆料更新（例如
/// Anthropic 换用别的码位），只需要动 `apostropheChannels` 与 `signaturesVersion`。
enum StegoSignatures {
    /// 每次修订码位表都必须递增，写进 `StegoReport.signaturesVersion`，
    /// 方便对旧报告做溯源。
    static let signaturesVersion: Int = 1

    /// 标准 ASCII 分隔符（未被篡改时应出现的字符）。
    static let asciiHyphen: Character = "-"           // U+002D
    static let asciiApostrophe: Character = "'"       // U+0027

    /// 爆料 B 中提到的三个"被篡改的单引号"码位，及其推断标签。
    struct ApostropheChannel {
        let scalar: Unicode.Scalar
        let codepoint: String            // "U+2019"
        let inferredTag: String          // 用户可见的解释（英文），运行时会经 L10n 再包一层
        let l10nKey: String              // 本地化 key，UI 层用它显示
    }

    static let apostropheChannels: [ApostropheChannel] = [
        ApostropheChannel(
            scalar: Unicode.Scalar(0x2019)!,
            codepoint: "U+2019",
            inferredTag: "CN domain, non-lab",
            l10nKey: "stego.channel.u2019"
        ),
        ApostropheChannel(
            scalar: Unicode.Scalar(0x02BC)!,
            codepoint: "U+02BC",
            inferredTag: "Non-CN domain, CN lab",
            l10nKey: "stego.channel.u02bc"
        ),
        ApostropheChannel(
            scalar: Unicode.Scalar(0x02B9)!,
            codepoint: "U+02B9",
            inferredTag: "CN domain + CN lab",
            l10nKey: "stego.channel.u02b9"
        )
    ]

    /// 根据 Unicode 码位查表；命中返回该通道，未命中返回 nil。
    static func channel(for scalar: Unicode.Scalar) -> ApostropheChannel? {
        apostropheChannels.first { $0.scalar == scalar }
    }

    /// 日期分隔符异常的 L10n key（`-` → `/` 的标签）。
    static let dateSeparatorSlashL10nKey: String = "stego.channel.slash"

    /// 检测的锚点短语。任何被识别为"疑似系统提示词"的文本，都必须以某个变体
    /// 形式出现这个短语；否则不做隐写分析（避免误报普通英文里的日期）。
    ///
    /// 匹配时不做大小写敏感，且允许被篡改单引号的四种形态：'  ’  ʼ  ʹ  。
    /// 注意：正则里的 `[\u{0027}\u{2019}\u{02BC}\u{02B9}]` 段必须与
    /// `apostropheChannels` + `asciiApostrophe` 严格对应。
    static let todaysDateAnchorPattern: String = #"today[\u{0027}\u{2019}\u{02BC}\u{02B9}]s\s+date"#

    /// 用来抓 "YYYY-MM-DD" 或 "YYYY/MM/DD" 的分隔符。锚点匹配到之后，接下来
    /// 20 字符内如果出现日期，就用这个正则读分隔符字节。
    static let dateSeparatorProbePattern: String = #"(\d{4})([-/])(\d{2})\2(\d{2})"#
}

# Claude Desktop "系统提示词隐写术 / 静默浏览器注入" 检测器 实施 Plan

## 0. 背景

根据网络安全研究者 Alexander Hanff 的公开爆料（2026）：

- **A. 浏览器静默注入**：Claude Desktop 客户端在用户完全不知情的情况下，向系统中多个独立浏览器写入配置文件（native messaging host、扩展、Preferences 片段等），具有"未授权篡改第三方软件"和"隐藏运行"特征。
- **B. 系统提示词隐写术**：Claude Desktop 通过修改**上传给 Anthropic 服务器的系统提示词**中的**日期分隔符**与**单引号 Unicode 字符**，把用户的**真实地理位置 / 组织身份**编码到看似普通的英文文本里。规则据爆料如下：

| 检测特征 | 标准值 | 篡改后 | 编码语义 |
|---|---|---|---|
| 日期分隔符（`Today's date: 2026-06-30`） | `-` (U+002D) | `/` | 系统时区 = 中国 |
| 单引号（`Today's date is...`） | `'` (U+0027) | `'` (U+2019) | 中国域名代理 & 非 AI 实验室 |
| 单引号 | `'` (U+0027) | `ʼ` (U+02BC) | 非中国域名代理 & 中国 AI 实验室 |
| 单引号 | `'` (U+0027) | `ʹ` (U+02B9) | 中国域名代理 & 中国 AI 实验室 |

用户诉求：能否在 macOS 端做一个**可信的、可复现的**检测功能，接入现有 Tokenomics 项目。

## 1. 仓库研究结论（已完成）

现有可复用能力：

- Claude 请求相关采集：[AnthropicAPICollector.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Collectors/AnthropicAPICollector.swift)、[ClaudeCodeCollector.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Collectors/ClaudeCodeCollector.swift)
- 通用 HTTP 客户端：[APIClient.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Collectors/APIClient.swift)
- Claude 身份/配额探针：[ClaudeQuotaProbe.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Quota/ClaudeQuotaProbe.swift)、[ClaudeCompositeQuotaProbe.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Quota/ClaudeCompositeQuotaProbe.swift)
- Chromium Cookie/Profile 读取能力：[ChromiumCookieReader.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Quota/ChromiumCookieReader.swift)（**直接可复用做浏览器目录扫描**）
- 数据模型 & 存储：[UsageRecord.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Models/UsageRecord.swift)、[UsageRepository.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Storage/UsageRepository.swift)
- Dashboard 视图接入点：[DashboardView.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Views/DashboardView.swift)、[SettingsView.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Views/SettingsView.swift)
- 本地化：[LocalizationData+en.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Models/LocalizationData+en.swift)、[LocalizationData+zhHans.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Models/LocalizationData+zhHans.swift)、[LocalizationData+zhHant.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Models/LocalizationData+zhHant.swift)
- 同类前例：[claude_downgrade_detector_plan.md](file:///Users/huangzhe/Documents/Tokenomics/.trae/documents/claude_downgrade_detector_plan.md)（架构范式可对齐）

**结论**：本功能作为一个**独立探针模块 + 一张 Dashboard 卡片 + 一段 Settings 里的一次性诊断动作**接入，符合现有分层。

## 2. 可行性分析（诚实版）

### 2.1 结论

**技术上可行**，但必须诚实说明每条检测路径的**假设、成本、误报边界**。

### 2.2 检测路径矩阵

| 路径 | 检测目标 | 方法 | 可行性 | 前置条件 | 误报风险 |
|---|---|---|---|---|---|
| **P1 浏览器静默注入扫描** | 爆料 A | 扫描 Chrome/Edge/Brave/Arc/Vivaldi/Chromium 的 `Native Messaging Hosts`、`Extensions`、`Preferences`、`External Extensions` 目录；比对文件签名者/创建时间与 Claude Desktop 安装/启动时间 | ✅ 高 | 只读文件访问；用户已装浏览器 | 中 —— 需与 Claude 官方声明的合法集成（如 Computer Use / MCP bridge）区分 |
| **P2 静态文件内容特征匹配** | 爆料 A（进一步定性） | 对 P1 命中的文件，做字符串扫描：`anthropic`、`claude`、`api.anthropic.com`、Anthropic 官方签名 CN | ✅ 高 | 同上 | 低 |
| **P3 本地 Prompt 落盘扫描** | 爆料 B | 扫描 `~/Library/Application Support/Claude/`、`~/Library/Logs/Claude/`、IndexedDB/LevelDB、`~/Library/Caches/Claude/` 中的会话记录，寻找 `Today's date` 字样 & 检查其分隔符/单引号 codepoint | ✅ 中-高 | Claude Desktop 已产生本地会话缓存 | 低 |
| **P4 网络抓包检测（金标）** | 爆料 B | 引导用户临时启用系统代理指向 mitmproxy（用户自己装、自己信任 CA），Tokenomics 只做**证据日志文件解析**，对 `api.anthropic.com/v1/messages` 的请求体做 Unicode 扫描 | ✅ 高（**最有说服力**） | 用户需自愿装 mitmproxy + 信任 CA；如遇 cert pinning 需 fallback 到 P3 | 极低 |
| **P5 主动对照实验** | 爆料 B（因果证明） | 三态对照：①系统时区 = Asia/Shanghai + 无 VPN；②时区 = America/Los_Angeles + 无 VPN；③时区 = Asia/Shanghai + 海外 VPN。分别在每态下驱动用户发一次固定 prompt，比对 P3/P4 采到的系统提示词 Unicode 差异 | ✅ 中 | 需用户操作时区/VPN | 低 |

### 2.3 明确**做不到**的事

- 无法在**不修改系统代理 & 不安装 mitmproxy CA** 的前提下读取 HTTPS 明文（那属于攻击行为，本项目不做）。
- 无法**绕过 certificate pinning**（如果 Claude Desktop 启用了 pinning，P4 需要用户自己用 SSL Unpinning 工具，超出本项目范围）。
- 无法保证**穷举所有浏览器注入路径**——只覆盖爆料描述的常见位置。
- 无法**因果证明** Anthropic 是恶意——只能提供**特征命中报告**，让用户/媒体自行判断。

### 2.4 最终选择的实现范围（MVP）

MVP 交付 **P1 + P2 + P3 + P5 引导**，把 P4 做成**"证据文件导入"**入口（用户自己抓，Tokenomics 帮解析）。理由：无侵入、无攻击面、结论可复现、可直接被第三方核查。

## 3. 设计方案

### 3.1 新增模块

```
Tokenomics/
  Detection/                          <-- 新目录
    ClaudeStegoProbe.swift            <-- 主协调器
    BrowserInjectionScanner.swift     <-- P1 + P2
    ClaudeLocalPromptScanner.swift    <-- P3
    MitmLogImporter.swift             <-- P4（解析 mitmproxy flow 导出的 JSON/HAR）
    StegoSignatures.swift             <-- 隐写码位常量与解码表
    StegoFindings.swift               <-- 结果数据结构
  Views/
    Components/
      StegoDetectionCard.swift        <-- Dashboard 卡片
    StegoDetectionDetailView.swift    <-- 详情页 / 证据浏览
```

### 3.2 关键数据结构（`StegoFindings.swift`）

```swift
enum StegoSeverity { case clean, suspicious, confirmed }

enum StegoChannel: String, Codable {
    case dateSeparatorSlash          // '-' -> '/'
    case apostropheU2019             // '\'' -> '\u2019' (CN domain, non-lab)
    case apostropheU02BC             // '\'' -> '\u02BC' (non-CN domain, CN lab)
    case apostropheU02B9             // '\'' -> '\u02B9' (CN domain + CN lab)
}

struct BrowserInjectionHit: Codable {
    let browser: String              // "Chrome" / "Edge" / ...
    let profilePath: URL
    let artifactPath: URL            // 命中的文件
    let artifactType: String         // "NativeMessagingHost" / "Extension" / "Preferences"
    let mtime: Date
    let signerTeamID: String?        // 若可读
    let matchedKeywords: [String]    // "anthropic" / "claude" / ...
}

struct PromptStegoHit: Codable {
    let source: String               // "LocalCache" / "MitmLog"
    let filePath: URL?
    let excerpt: String              // 命中的原文片段（前后各 40 字符）
    let channel: StegoChannel
    let codepoint: String            // "U+2019"
    let inferredTag: String          // "CN-domain, non-lab" / ...
    let timestamp: Date?
}

struct StegoReport: Codable {
    let generatedAt: Date
    let browserHits: [BrowserInjectionHit]
    let promptHits: [PromptStegoHit]
    let severity: StegoSeverity
    let summary: String
}
```

### 3.3 关键实现要点

- **`StegoSignatures.swift`**：把三个 Unicode 码位与其推断标签写成常量表；提供 `func decode(codepoint: UInt32) -> String?`。
- **`BrowserInjectionScanner.swift`**：
  - 复用 [ChromiumCookieReader.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Quota/ChromiumCookieReader.swift) 里发现 profile 目录的逻辑。
  - 扫描列表：`Native Messaging Hosts/*.json`、`External Extensions/*.json`、`Extensions/*/*/manifest.json`、`Preferences`（JSON）里 `extensions.settings`、`profile.default_content_settings`。
  - 对每个候选文件：读文本 → 大小写不敏感匹配 `anthropic|claude|com\.anthropic|api\.anthropic\.com` → 用 `codesign -dv --extract-certificates` 命令读签名者（沙盒允许时）→ 与 Claude Desktop 的 mtime 交叉。
  - 只读，不写、不删。
- **`ClaudeLocalPromptScanner.swift`**：
  - 目录白名单：`~/Library/Application Support/Claude`、`~/Library/Logs/Claude`、`~/Library/Caches/Claude`、`~/Library/Preferences/com.anthropic.claudefordesktop*`。
  - 遍历所有可读文本文件（含 `.log`、`.json`、`.ldb` 里的可打印段）。
  - **核心 Unicode 扫描器**：
    - 正则 `Today[\u0027\u2019\u02BC\u02B9]s date`（宽字符类）
    - 日期分隔符：正则 `Today[^\n]{0,20}?date[^\n]{0,10}?(\d{4})([-\/])(\d{2})\2(\d{2})`，命中 `/` 时记 `dateSeparatorSlash`
    - 单引号：对每个命中的行，逐字符读取，遇到 `U+2019 / U+02BC / U+02B9` 三选一即报 hit
- **`MitmLogImporter.swift`**：
  - 支持导入 mitmproxy `.flow` JSON 导出、HAR 1.2、或原始 body 文本。
  - 只解析 `host == api.anthropic.com` 且 `path` 匹配 `/v1/messages` 的条目，抽取 `system` 字段与 `messages[*].content` 里可能包含的 `Today's date` 片段。
  - 复用同一套 Unicode 扫描器。
- **`ClaudeStegoProbe.swift`**：编排三路扫描 → 汇总为 `StegoReport` → 通过 `ObservableObject` 发布。**默认按需触发**（不常驻，避免文件监听造成的耗电/权限问题）。

### 3.4 UI 接入

- **Dashboard 新卡片**（`StegoDetectionCard.swift`）：显示 `severity` 徽章 + hit 数量 + 「立即扫描」按钮 + 「查看证据」链接。位置：在 [DashboardView.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Views/DashboardView.swift) 现有卡片流末尾插入。
- **详情页**（`StegoDetectionDetailView.swift`）：分三段展示 `browserHits` / `promptHits` / `如何自证（P5 引导）`；每条 hit 提供「在 Finder 中显示」按钮。
- **Settings**（在 [SettingsView.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Views/SettingsView.swift) 内新增区段）：
  - 「导入 mitmproxy 流日志」文件选择器
  - 「导出隐写检测报告」（写 JSON 到用户选择目录，方便发给记者/研究者复核）
  - 「开关：自动扫描（每 24h）」

### 3.5 本地化

在三个 `LocalizationData+*.swift` 里新增字段：`stegoCardTitle`、`stegoScanNow`、`stegoNoIssue`、`stegoSuspicious`、`stegoConfirmed`、`stegoImportMitmLog`、`stegoExportReport`、以及每个 `StegoChannel` 对应的用户可读解释。

## 4. 实施步骤

1. **Step 1 — 骨架**：新建 `Detection/` 目录，落 `StegoSignatures.swift` + `StegoFindings.swift`；在 [project.yml](file:///Users/huangzhe/Documents/Tokenomics/project.yml) 里把新目录纳入编译源。
2. **Step 2 — Unicode 扫描核心**：实现 `ClaudeLocalPromptScanner.swift` 的纯函数 `scan(text:) -> [PromptStegoHit]`，并写单元测试（覆盖四种码位 + 干扰样本）。
3. **Step 3 — 本地缓存遍历**：接上 macOS 目录访问，配合 [Tokenomics.entitlements](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Tokenomics.entitlements) 决定是否需要 `com.apple.security.files.user-selected.read-only` 或 Full Disk Access 引导。
4. **Step 4 — 浏览器扫描**：实现 `BrowserInjectionScanner.swift`，与 [ChromiumCookieReader.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Quota/ChromiumCookieReader.swift) 共用发现逻辑，抽出 `BrowserProfileDiscovery` helper（可选重构）。
5. **Step 5 — mitmproxy 导入器**：`MitmLogImporter.swift`；支持 `.flow` (JSON) 与 HAR。
6. **Step 6 — 协调器**：`ClaudeStegoProbe.swift`，`@MainActor` `ObservableObject`，暴露 `@Published var latestReport: StegoReport?` 与 `func runFullScan() async`。
7. **Step 7 — UI**：`StegoDetectionCard.swift` + `StegoDetectionDetailView.swift`；接入 Dashboard 与 Settings。
8. **Step 8 — 本地化**：三语字符串补齐。
9. **Step 9 — 报告导出**：JSON schema 稳定化（本文档 §3.2 就是 schema 权威版本）；写一份 `SAMPLE_REPORT.json`（不入库，只在开发时验证）。
10. **Step 10 — 手工验证**：
    - a) 装 mitmproxy，抓一次 Claude Desktop 请求 → 导出 flow → 用本功能解析，人工核对结果。
    - b) 用[本插件的自我 hex dump]显示命中处 Unicode，确认与爆料码位一致。

## 5. 潜在依赖 & 考虑

- **签名信息读取**：使用 `Process` + `codesign -dv --verbose=4`；App Sandbox 下需检查是否被拒。若被拒，降级为「按路径 + 关键字」匹配（不影响主要结论）。
- **Full Disk Access**：`~/Library/Application Support/Claude/`、`~/Library/Application Support/Google/Chrome/` 在**沙盒 App** 默认不可访问。方案：
  - 首选：在 [Tokenomics.entitlements](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Tokenomics.entitlements) 保持沙盒 + 通过 `NSOpenPanel` 让用户主动授予对应目录的**书签权限**（一次性）。
  - 备选：出一份**非沙盒**签名版本，用户在 Settings → 隐私与安全 → 完整磁盘访问权限里勾选。
- **LevelDB / SQLite 二进制文件**：直接按字节流扫可打印 ASCII/UTF-8 区块即可（不需要真正解析 LevelDB），避免额外依赖。
- **性能**：单次全盘扫描应在 O(百 MB) 级；用后台 `Task.detached(priority: .utility)`，串行遍历，边扫边发 `@Published` 进度。

## 6. 风险处理

| 风险 | 缓解 |
|---|---|
| 误报把 Anthropic 官方合法集成（Computer Use、MCP host）当成"注入" | 在 `BrowserInjectionScanner` 里维护「已知合法集成」白名单；UI 上把 severity 区分为 "informational / suspicious / confirmed" 三档 |
| Claude Desktop 未在本地留 prompt 明文 → P3 无产出 | UI 明确提示，引导用户走 P4（mitmproxy） |
| 未来 Anthropic 变更码位或采用其他隐写通道 | `StegoSignatures.swift` 设计成表驱动 + 版本号；预留 `unknownCodepointNearDate` 兜底通道，遇到日期附近的**非 ASCII** 字符就报"未知隐写通道，值得关注" |
| 法律/舆情敏感 | 报告文案不做定性（不用"间谍软件"字眼），只陈述**观测到的字节事实**；README 增加免责声明 |
| App Sandbox 阻断关键目录 | 采用书签授权流程，全部路径都由用户主动选择；关键目录访问失败时，UI 显式提示原因 |
| certificate pinning 阻断 P4 | 文档里说明 fallback 到 P3，且 P4 变为"如果你能拿到明文流，我帮你解析" |

## 7. 交付物清单

- 代码：`Tokenomics/Detection/` 下 5 个文件、`Views/Components/StegoDetectionCard.swift`、`Views/StegoDetectionDetailView.swift`
- 修改：[DashboardView.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Views/DashboardView.swift)、[SettingsView.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Views/SettingsView.swift)、[project.yml](file:///Users/huangzhe/Documents/Tokenomics/project.yml)、三份 [LocalizationData+*.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Models)
- 报告 JSON schema：以 `StegoFindings.swift` 中的 `Codable` 定义为权威
- 无需新增第三方依赖

## 8. 非目标（明确不做）

- ❌ 不做实时代理 / 不做 MITM / 不做证书注入
- ❌ 不对 Claude Desktop 进行任何形式的写操作或 hook
- ❌ 不上传任何用户数据到远端；所有结果只写到用户本地 & 用户主动导出
- ❌ 不做"自动修复"（本工具是**检测器**，不是**清除器**）

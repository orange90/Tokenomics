# Tokenomics

[中文](#中文) | [English](#english)

---

<a id="中文"></a>

## 中文

> 一款原生 macOS 应用，统一统计本机各 AI 工具（Claude Code / OpenAI / Anthropic）的 token 用量与对应 USD / CNY 花费，并支持自定义脚本接入任意来源。

### 功能特性

- 📊 **统一仪表盘** — 今日 / 本周 / 本月 / 累计花费与趋势一目了然，支持模型维度拆解、配额卡片、缓存命中率、5 小时窗口拆解、回本分析
- 🧩 **任务级视图** — [TasksView](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Views/TasksView.swift) 直接解析 `~/.claude/projects/<cwd>/<sessionId>.jsonl`，按项目 / 会话粒度查看 token、费用、模型分布
- 🔌 **多源采集**
  - 本地日志解析：Claude Code (`~/.claude/projects`)
  - 官方 API 拉取：OpenAI、Anthropic
  - 自定义脚本/接口采集（[CustomScriptCollector](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Collectors/CustomScriptCollector.swift)）：用任意 HTTP 接口或脚本输出 JSON 即可接入其他来源
- 💰 **精准计价** — 内置最新模型单价表（详见 [PricingTable.json](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Resources/PricingTable.json)），按 input / output / cache write / cache read 分别计算；支持单价覆盖
- 📈 **配额探测** — Claude 订阅配额（Web / OAuth / Composite 多通道）与 Codex 配额实时回显
- 💱 **多币种** — USD / CNY 切换，自动汇率（见 [ExchangeRateService.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Pricing/ExchangeRateService.swift)）
- 🌏 **多语言** — 简体中文 / 繁体中文 / English 三语界面，默认跟随系统
- 🔒 **隐私优先** — 全本地运行，API Key 走 macOS Keychain，零上传

### 技术栈

- Swift 5.9+ / SwiftUI / SwiftData / Swift Charts
- macOS 14 (Sonoma) +
- Xcode 15+

### 项目结构

详见 [token_calc_plan.md](file:///Users/huangzhe/Documents/Tokenomics/.trae/documents/token_calc_plan.md)。

```
Tokenomics/
├── TokenomicsApp.swift          # 入口
├── Models/                      # 数据模型与本地化
├── Collectors/                  # AI 工具采集器（Claude Code / OpenAI / Anthropic + 自定义脚本）
├── Pricing/                     # 计价与汇率
├── Quota/                       # Claude / Codex 配额探测
├── Storage/                     # 持久化 / Keychain
├── Scheduler/                   # 后台刷新调度
├── Resources/                   # 单价表、Assets
└── Views/                       # SwiftUI 界面（仪表盘 / 回本 / 模型 / 任务 / 日志 / 设置）
```

关键目录速览：

- [Collectors](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Collectors) — 所有采集器实现
- [Views](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Views) — 仪表盘、回本分析、Provider 详情、模型拆解、任务详情、设置
- [Models](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Models) — `UsageRecord`、`Provider`、`Subscription`、`ModelPricing` 等

### 在 Xcode 中打开

本仓库以源码 + [project.yml](file:///Users/huangzhe/Documents/Tokenomics/project.yml) 的形式组织，使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 一键生成 Xcode 项目：

```bash
# 安装 XcodeGen (一次性)
brew install xcodegen

# 在仓库根目录执行
xcodegen generate

# 打开生成的项目
open Tokenomics.xcodeproj
```

> 若不想安装 XcodeGen，可直接用 Xcode 新建一个 macOS App 项目，把 `Tokenomics/` 下的所有文件拖入项目即可运行。

### 签名与 App Sandbox

- **App Sandbox 必须保持关闭** —— 沙盒应用读不到 Claude CLI 写在 login keychain 中的 `Claude Code-credentials`，也访问不了 `~/.claude` 目录。详见 [project.yml](file:///Users/huangzhe/Documents/Tokenomics/project.yml#L36-L41)。
- **使用稳定签名身份（Apple Development）** —— macOS 钥匙串的「始终允许」是按代码签名身份记忆的，ad-hoc 二进制 cdhash 每次 build 都会变，授权挂不住，会反复弹窗。仓库默认配置为 `CODE_SIGN_IDENTITY = "Apple Development"`，配合免费的 Apple Developer 账号即可；如需修改 Team，请在 [project.yml](file:///Users/huangzhe/Documents/Tokenomics/project.yml#L42-L54) 中调整 `DEVELOPMENT_TEAM`。

### 开发状态

| 里程碑 | 状态 |
|---|---|
| M1 项目骨架 | ✅ |
| M2 Claude Code 采集 + 计价 | ✅ |
| M3 API 采集（OpenAI / Anthropic） | ✅ |
| M4 可视化与体验（图表、回本、任务详情、多语言） | ✅ |
| M5 更多供应商接入（TRAE Solo / Cursor / Gemini / 通义 / DeepSeek / Qoder / 智谱 GLM / 硅基流动 / OpenRouter / StepFun / Mimo / Kimi / 火山引擎 / MiniMax 等） | 🚧 计划中 |

### 隐私

- 全部用量数据存储在本机 `~/Library/Application Support/Tokenomics/`
- API Key 通过 macOS Keychain 加密存储（见 [KeychainService.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Storage/KeychainService.swift)）
- 应用网络出站仅限：用户启用的官方 API + 汇率服务

### License

MIT

---

<a id="english"></a>

## English

> A native macOS app that unifies token usage and USD / CNY spend across AI tools on your Mac — Claude Code, OpenAI, and Anthropic — with a custom-script collector for plugging in any other source.

### Features

- 📊 **Unified dashboard** — today / week / month / lifetime spend with trends, per-model breakdown, quota cards, cache-hit ratio, 5-hour window breakdown, and breakeven analysis
- 🧩 **Task-level view** — [TasksView](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Views/TasksView.swift) parses `~/.claude/projects/<cwd>/<sessionId>.jsonl` directly, surfacing tokens / cost / model mix per project and session
- 🔌 **Multi-source collection**
  - Local log parsing: Claude Code (`~/.claude/projects`)
  - Official API pull: OpenAI, Anthropic
  - Custom script collector ([CustomScriptCollector](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Collectors/CustomScriptCollector.swift)) — emit JSON from any script to plug in your own source
  - 🚧 More providers (TRAE Solo / Cursor / Gemini / Qwen / DeepSeek / Qoder / Zhipu GLM / SiliconFlow / OpenRouter / StepFun / Mimo / Kimi / Volcengine / MiniMax, etc.) are in progress and not yet available
- 💰 **Accurate pricing** — built-in latest price table (see [PricingTable.json](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Resources/PricingTable.json)), separately costed for input / output / cache write / cache read, with per-entry overrides
- 📈 **Quota probing** — live Claude subscription quota (Web / OAuth / Composite channels) and Codex quota
- 💱 **Multi-currency** — USD / CNY toggle with automatic FX rates (see [ExchangeRateService.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Pricing/ExchangeRateService.swift))
- 🌏 **Multilingual** — Simplified Chinese / Traditional Chinese / English, follows system locale by default
- 🔒 **Privacy-first** — runs fully local, API keys live in macOS Keychain, zero upload

### Stack

- Swift 5.9+ / SwiftUI / SwiftData / Swift Charts
- macOS 14 (Sonoma) +
- Xcode 15+

### Project layout

See [token_calc_plan.md](file:///Users/huangzhe/Documents/Tokenomics/.trae/documents/token_calc_plan.md).

```
Tokenomics/
├── TokenomicsApp.swift          # entry point
├── Models/                      # data models & localization
├── Collectors/                  # provider collectors (Claude Code / OpenAI / Anthropic + custom script)
├── Pricing/                     # pricing & FX
├── Quota/                       # Claude / Codex quota probes
├── Storage/                     # persistence / Keychain
├── Scheduler/                   # background refresh
├── Resources/                   # price table, assets
└── Views/                       # SwiftUI screens (dashboard / breakeven / models / tasks / logs / settings)
```

Key directories:

- [Collectors](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Collectors) — every collector implementation
- [Views](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Views) — dashboard, breakeven, provider detail, model breakdown, tasks, settings
- [Models](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Models) — `UsageRecord`, `Provider`, `Subscription`, `ModelPricing`, ...

### Open in Xcode

The repo is source + [project.yml](file:///Users/huangzhe/Documents/Tokenomics/project.yml). Use [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project:

```bash
# Install XcodeGen (once)
brew install xcodegen

# From the repo root
xcodegen generate

# Open the generated project
open Tokenomics.xcodeproj
```

> Or create a new macOS App in Xcode and drag the contents of `Tokenomics/` in.

### Signing & App Sandbox

- **App Sandbox must stay disabled** — a sandboxed app cannot read the `Claude Code-credentials` entry the Claude CLI writes into login keychain, nor reach `~/.claude`. See [project.yml](file:///Users/huangzhe/Documents/Tokenomics/project.yml#L36-L41).
- **Use a stable signing identity (Apple Development)** — macOS keychain remembers the "Always Allow" decision per code-signing identity. An ad-hoc binary's cdhash changes every build, so the grant never sticks and you'll be re-prompted forever. The repo defaults to `CODE_SIGN_IDENTITY = "Apple Development"`; a free Apple Developer account is enough. Adjust `DEVELOPMENT_TEAM` in [project.yml](file:///Users/huangzhe/Documents/Tokenomics/project.yml#L42-L54) if needed.

### Status

| Milestone | State |
|---|---|
| M1 Project skeleton | ✅ |
| M2 Claude Code collection + pricing | ✅ |
| M3 API collectors (OpenAI / Anthropic) | ✅ |
| M4 Visualization & UX (charts, breakeven, tasks, i18n) | ✅ |
| M5 More providers (TRAE Solo / Cursor / Gemini / Qwen / DeepSeek / Qoder / Zhipu GLM / SiliconFlow / OpenRouter / StepFun / Mimo / Kimi / Volcengine / MiniMax, etc.) | 🚧 planned |

### Privacy

- All usage data lives in `~/Library/Application Support/Tokenomics/` on your Mac
- API keys are stored encrypted in macOS Keychain (see [KeychainService.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Storage/KeychainService.swift))
- Outbound traffic is limited to user-enabled official APIs and the FX service

### License

MIT

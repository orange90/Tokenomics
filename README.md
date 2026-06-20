# Tokenomics

[中文](#中文) | [English](#english)

---

<a id="中文"></a>

## 中文

> 一款原生 macOS 应用，统一统计本机 Claude Code、OpenAI / Codex、Anthropic 的 token 用量与对应 USD / CNY 花费，并支持通过自定义脚本/接口接入其他来源。

### 功能特性

- 📊 **统一仪表盘** — 今日 / 本周 / 本月 / 累计花费与趋势一目了然，支持模型维度拆解、配额卡片、回本分析
- 🔌 **多源采集**
  - 本地日志解析：Claude Code (`~/.claude/projects`)、Codex CLI / Codex Desktop (`~/.codex/sessions`)
  - 官方 API 拉取：Anthropic Admin Usage API、OpenAI Organization Usage API
  - 自定义脚本/接口采集（CustomScriptCollector）：用任意 HTTP 接口或脚本输出 JSON 即可接入其他来源
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
└── Views/                       # SwiftUI 界面
```

关键目录速览：

- [Collectors](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Collectors) — 所有采集器实现
- [Views](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Views) — 仪表盘、Provider 详情、模型拆解、回本分析、设置
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
>
> 注意：App Sandbox **必须保持关闭**——沙盒应用读不到 Claude CLI 写在 login keychain 中的 `Claude Code-credentials`，也访问不了 `~/.claude` 目录。详见 [project.yml](file:///Users/huangzhe/Documents/Tokenomics/project.yml#L33-L41)。

### 打包发布 DMG（免费方案，无需 Apple 开发者账号）

仓库内附 [release.sh](file:///Users/huangzhe/Documents/Tokenomics/scripts/release.sh)，使用 **ad-hoc 签名**（identity = `-`）+ Hardened Runtime，本地一行命令即可产出可分发的 DMG：

```bash
# 一次性：把 xcode-select 切到 Xcode.app（不是 Command Line Tools）
sudo xcode-select -s /Applications/Xcode.app

# 可选：更漂亮的 DMG 排版
brew install create-dmg

# 打包（自动读取 project.yml 的 MARKETING_VERSION，也可手动指定）
./scripts/release.sh
./scripts/release.sh 0.2.0
```

产物：

- `build/export/Tokenomics.app`
- `build/Tokenomics-<version>.dmg`

### 安装（给最终用户）

由于没有付费 Apple Developer ID，Gatekeeper 首次会提示「无法验证开发者」，二选一即可：

1. **右键打开法**：在 Applications 里 **右键 Tokenomics.app → 打开**，弹窗里再点一次「打开」，以后双击即可。
2. **一行命令法**：终端执行 `xattr -dr com.apple.quarantine /Applications/Tokenomics.app`，之后双击直接进。

> 升级到新版本后，可能需要再次执行上述任一操作（ad-hoc 签名的 cdhash 每次构建会变）。

### 开发状态

| 里程碑 | 状态 |
|---|---|
| M1 项目骨架 | ✅ |
| M2 Claude Code 采集 + 计价 | ✅ |
| M3 API 采集（OpenAI / Anthropic） | ✅ |
| M4 可视化与体验（图表、回本、多语言） | ✅ |
| M5 发布打包（ad-hoc DMG） | ✅ |

### 隐私

- 全部用量数据存储在本机 `~/Library/Application Support/Tokenomics/`
- API Key 通过 macOS Keychain 加密存储（见 [KeychainService.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Storage/KeychainService.swift)）
- 应用网络出站仅限：用户启用的官方 API + 汇率服务

### License

MIT

---

<a id="english"></a>

## English

> A native macOS app that unifies token usage and USD / CNY spend across the AI tools on your Mac — Claude Code, OpenAI / Codex, and Anthropic — with a custom-script collector for plugging in any other source.

### Features

- 📊 **Unified dashboard** — today / week / month / lifetime spend with trends, per-model breakdown, quota cards, and breakeven analysis
- 🔌 **Multi-source collection**
  - Local log parsing: Claude Code (`~/.claude/projects`), Codex CLI / Codex Desktop (`~/.codex/sessions`)
  - Official API pull: Anthropic Admin Usage API, OpenAI Organization Usage API
  - Custom script / HTTP collector — emit JSON from any endpoint or script to plug in your own source
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
└── Views/                       # SwiftUI screens
```

Key directories:

- [Collectors](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Collectors) — every collector implementation
- [Views](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Views) — dashboard, provider detail, model breakdown, breakeven, settings
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
>
> Note: App Sandbox **must stay disabled** — a sandboxed app cannot read the `Claude Code-credentials` entry the Claude CLI writes into login keychain, nor reach `~/.claude`. See [project.yml](file:///Users/huangzhe/Documents/Tokenomics/project.yml#L33-L41).

### Packaging a DMG (free, no Apple Developer Program)

Use the bundled [release.sh](file:///Users/huangzhe/Documents/Tokenomics/scripts/release.sh) — it ad-hoc signs (identity `-`) with Hardened Runtime and produces a distributable DMG in one shot:

```bash
# One-time: point xcode-select to Xcode.app (not Command Line Tools)
sudo xcode-select -s /Applications/Xcode.app

# Optional: nicer DMG layout
brew install create-dmg

# Build (reads MARKETING_VERSION from project.yml, or pass one)
./scripts/release.sh
./scripts/release.sh 0.2.0
```

Outputs:

- `build/export/Tokenomics.app`
- `build/Tokenomics-<version>.dmg`

### Install (for end users)

Without a paid Developer ID, Gatekeeper will show "cannot verify the developer" on first launch. Either:

1. **Right-click open**: in Applications, **right-click Tokenomics.app → Open**, then click *Open* in the dialog. Subsequent launches work normally.
2. **One-liner**: `xattr -dr com.apple.quarantine /Applications/Tokenomics.app`, then double-click.

> After upgrading, you may need to repeat either step (ad-hoc signature's cdhash changes per build).

### Status

| Milestone | State |
|---|---|
| M1 Project skeleton | ✅ |
| M2 Claude Code collection + pricing | ✅ |
| M3 API collectors (OpenAI / Anthropic) | ✅ |
| M4 Visualization & UX (charts, breakeven, i18n) | ✅ |
| M5 Release packaging (ad-hoc DMG) | ✅ |

### Privacy

- All usage data lives in `~/Library/Application Support/Tokenomics/` on your Mac
- API keys are stored encrypted in macOS Keychain (see [KeychainService.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Storage/KeychainService.swift))
- Outbound traffic is limited to user-enabled official APIs and the FX service

### License

MIT

# Tokenomics

> 一款原生 macOS 应用，统一统计本机各 AI 工具（Claude Code / OpenAI / TRAE Solo / Cursor / Gemini / 通义 / DeepSeek / Qoder / 硅基流动 / OpenRouter / StepFun / Mimo / Kimi 等）的 token 用量与对应 USD/CNY 花费。

## 功能特性

- 📊 **统一仪表盘** — 今日 / 本周 / 本月 / 累计花费一目了然
- 🔌 **多源采集**
  - 本地日志解析：Claude Code (`~/.claude/projects`)、Cursor、TRAE Solo、Qoder
  - 官方 API 拉取：OpenAI、Anthropic、DeepSeek、Gemini、Qwen、SiliconFlow、OpenRouter、StepFun、Mimo、Kimi
- 💰 **精准计价** — 内置最新模型单价表（详见 [PricingTable.json](file:///Users/huangzhe/Documents/token_calc/Tokenomics/Resources/PricingTable.json)），按 input / output / cache 分别计算；支持单价覆盖
- 💱 **多币种** — USD / CNY 切换，自动汇率
- 🔒 **隐私优先** — 全本地运行，API Key 走 Keychain，零上传

## 技术栈

- Swift 5.9+ / SwiftUI / SwiftData / Swift Charts
- macOS 14 (Sonoma) +
- Xcode 15+

## 项目结构

详见 [.trae/documents/token_calc_plan.md](./.trae/documents/token_calc_plan.md)。

```
Tokenomics/
├── TokenomicsApp.swift          # 入口
├── Models/                     # 数据模型
├── Collectors/                 # 各 AI 工具采集器
├── Pricing/                    # 计价与汇率
├── Storage/                    # 持久化 / Keychain
├── Scheduler/                  # 调度
└── Views/                      # SwiftUI 界面
```

## 在 Xcode 中打开

本仓库以源码 + `project.yml` 的形式组织，使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 一键生成 Xcode 项目：

```bash
# 安装 XcodeGen (一次性)
brew install xcodegen

# 在仓库根目录执行
xcodegen generate

# 打开生成的项目
open Tokenomics.xcodeproj
```

> 若不想安装 XcodeGen，可直接用 Xcode 新建一个 macOS App 项目，把 `Tokenomics/` 下的所有文件拖入项目，并在 `Signing & Capabilities` 中勾选 App Sandbox（建议同时勾选 User Selected File、Network Client），即可运行。

## 开发状态

| 里程碑 | 状态 |
|---|---|
| M1 项目骨架 | ✅ |
| M2 Claude Code 采集 + 计价 | ✅ |
| M3 API 采集（OpenAI / Anthropic / DeepSeek / ...）| ✅ |
| M4 Cursor / TRAE / Qoder 采集 | ✅ |
| M5 可视化与体验 | ✅ |
| M6 发布打包 | ⏳ |

## 隐私

- 全部用量数据存储在本机 `~/Library/Application Support/Tokenomics/`
- API Key 通过 macOS Keychain 加密存储
- 应用网络出站仅限：用户启用的官方 API + 汇率服务

## License

MIT

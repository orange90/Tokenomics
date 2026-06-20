# Tokenomics - macOS AI Token 用量统计应用

## 1. 项目概述

### 1.1 目标
开发一款原生 macOS 应用 **Tokenomics**，集中统计本机上各类 AI 工具消耗的 token 数量及对应的美元/人民币花费。聚合多源数据后，给用户清晰可视化的「今日 / 本周 / 本月 / 累计」消耗仪表盘。

### 1.2 核心价值
- 一处看完所有 AI 工具花了多少钱
- 多模型、多供应商、多终端的统一计价
- 完全本地化运行，敏感数据（API Key、日志）不离开本机

### 1.3 用户选择确认
| 选项 | 决策 |
|---|---|
| 技术栈 | **SwiftUI + Swift（原生）** |
| 数据来源 | **本地日志解析 + 官方 API 拉取** |
| 应用形态 | **纯独立窗口应用（Dock）** |
| 覆盖工具 (MVP+扩展) | Claude Code、ChatGPT/OpenAI、TRAE Solo、Cursor、Gemini、通义、DeepSeek、Qoder、硅基流动 (SiliconFlow)、OpenRouter |

---

## 2. 仓库研究结论
当前工作目录 [token_calc](file:///Users/huangzhe/Documents/token_calc) 为空目录，需要从零初始化 Xcode 项目。无现存代码、依赖或约定可继承，因此所有结构均为新建。

---

## 3. 技术栈与依赖

- **语言/框架**: Swift 5.9+ / SwiftUI / Combine / SwiftData (或 Core Data)
- **最低系统版本**: macOS 14 (Sonoma) - 以使用最新的 SwiftData & Charts
- **构建**: Xcode 15+，使用 Swift Package Manager 管理依赖
- **数据可视化**: Apple Charts (Swift Charts)
- **网络**: URLSession + async/await
- **解析**:
  - `Foundation.JSONDecoder` 解析 JSONL/JSON 日志
  - 自定义解析器处理各家 CLI 的本地缓存目录
- **存储**:
  - SwiftData 持久化用量明细
  - Keychain 存储用户填入的 API Key
- **货币汇率**: 调用免费汇率 API（如 exchangerate.host）缓存 USD→CNY

---

## 4. 模块化设计

应用按「采集层 → 归一化层 → 计价层 → 存储层 → 展示层」分层。每个文件单一职责，控制在 300 行以内。

### 4.1 目录结构（计划新建）
```
Tokenomics/
├── TokenomicsApp.swift              # 入口 @main
├── Models/
│   ├── UsageRecord.swift           # 统一用量模型（@Model）
│   ├── Provider.swift              # 供应商枚举（OpenAI/Anthropic/...）
│   ├── ModelPricing.swift          # 单价表（input/output/cache）
│   └── Currency.swift              # 货币与汇率
├── Collectors/                     # 数据采集器（每家一个文件）
│   ├── CollectorProtocol.swift     # 统一接口
│   ├── ClaudeCodeCollector.swift   # 解析 ~/.claude/projects/**/*.jsonl
│   ├── CursorCollector.swift       # 解析 ~/Library/Application Support/Cursor
│   ├── TraeSoloCollector.swift     # 解析 TRAE 本地日志
│   ├── QoderCollector.swift        # 解析 Qoder 本地缓存
│   ├── OpenAIAPICollector.swift    # api.openai.com/v1/usage
│   ├── AnthropicAPICollector.swift # 官方 admin usage API
│   ├── GeminiAPICollector.swift    # Google AI usage
│   ├── DeepSeekCollector.swift     # platform.deepseek.com/api/v0/user/balance & usage
│   ├── QwenCollector.swift         # 通义 dashscope usage
│   ├── SiliconFlowCollector.swift  # siliconflow.cn usage API
│   └── OpenRouterCollector.swift   # openrouter.ai/api/v1/usage
├── Pricing/
│   ├── PricingService.swift        # 计价主服务
│   ├── PricingTable.json           # 内置最新单价表（按 model→provider）
│   └── ExchangeRateService.swift   # USD↔CNY 汇率
├── Storage/
│   ├── PersistenceController.swift # SwiftData 容器
│   ├── KeychainService.swift       # API Key 安全存储
│   └── UsageRepository.swift       # 增删查改 + 聚合查询
├── Scheduler/
│   └── RefreshScheduler.swift      # 定时拉取 / 文件监听 (FSEvents)
├── Views/
│   ├── DashboardView.swift         # 总览：今日/本周/本月卡片 + 趋势图
│   ├── ProviderDetailView.swift    # 单家供应商明细
│   ├── ModelBreakdownView.swift    # 按模型分组
│   ├── SettingsView.swift          # API Key、采集开关、汇率、单价覆盖
│   └── Components/
│       ├── CostCard.swift
│       ├── UsageChart.swift
│       └── ProviderRow.swift
└── Resources/
    └── Assets.xcassets             # 图标、品牌色
```

---

## 5. 关键功能与实现步骤

### 5.1 统一用量数据模型
```swift
@Model
final class UsageRecord {
    var id: UUID
    var timestamp: Date
    var provider: String        // "anthropic" / "openai" ...
    var model: String           // "claude-sonnet-4" / "gpt-4o" ...
    var sourceApp: String       // "Claude Code" / "Cursor" / "OpenAI API" ...
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    var cacheReadTokens: Int
    var costUSD: Double
    var requestId: String?      // 用于去重
}
```
通过 `requestId` + `timestamp + sourceApp` 复合唯一约束实现幂等导入。

### 5.2 采集层 (Collectors)
每个 Collector 遵循统一协议：
```swift
protocol UsageCollector {
    var id: String { get }
    var displayName: String { get }
    func collect(since: Date) async throws -> [UsageRecord]
}
```

**本地日志类**（优先 MVP）：
- **Claude Code**: 扫描 `~/.claude/projects/**/*.jsonl`，每行是一次消息，含 `message.usage` 字段（input/output/cache_creation/cache_read tokens）。使用 `FSEventStream` 增量监听。
- **Cursor**: 解析 `~/Library/Application Support/Cursor/User/workspaceStorage` 内的 SQLite 用量缓存（若可用），否则提示用户在 Cursor 设置中导出。
- **TRAE Solo**: 解析 `~/Library/Application Support/Trae/...` 下的 usage 日志（具体路径需运行时探测）。
- **Qoder**: 同上，扫描其 Application Support 目录。

**官方 API 类**：
- **OpenAI** (`/v1/usage` 或新版 dashboard API)
- **Anthropic Admin Usage API** (需要 admin key)
- **Google Gemini** (AI Studio / Vertex usage)
- **DeepSeek** `/user/balance`、`/user/usage`
- **通义/DashScope** usage 接口
- **SiliconFlow** 用户用量接口
- **OpenRouter** `/api/v1/generation` & `/credits`

不可直接拿到精确明细的供应商（如 ChatGPT Plus 订阅）采用 **会话计数 + 估算**模式，并在 UI 上明确标注「订阅制估算」。

### 5.3 计价层 (PricingService)
- 维护 `PricingTable.json`，按 `provider.model` → `{input, output, cache_write, cache_read}` USD per 1M tokens
- 计算公式：
  ```
  cost = (input * p.input + output * p.output + cacheCreate * p.cw + cacheRead * p.cr) / 1_000_000
  ```
- 允许用户在 SettingsView 中覆盖单价（应对企业折扣 / 第三方代理）
- 汇率：缓存 1 小时，离线兜底使用上次值

### 5.4 调度与文件监听
- `RefreshScheduler` 启动时全量回扫一次 + 每 5 分钟轮询 API
- 本地日志使用 **DispatchSource FSEvents** 监听增量文件追加
- 解析过的文件位点（offset）持久化，避免重复处理

### 5.5 UI 模块
- **DashboardView**: 顶部 4 张卡片（今日 / 本周 / 本月 / 累计），下方折线图（按天）+ 堆叠柱图（按供应商占比）
- **ProviderDetailView**: 点击进入特定供应商，按模型分组、时间筛选
- **SettingsView**:
  - 各 Collector 启用开关
  - API Key 输入（Keychain）
  - 自定义汇率 / 货币显示偏好（CNY / USD / 双显示）
  - 单价覆盖编辑器
  - 数据导出 CSV
- **菜单栏图标 (可选简化为应用图标徽章)**: 显示今日花费

### 5.6 安全与隐私
- 所有数据本地存储，不上传
- API Key 仅写入 Keychain，UI 显示掩码
- 沙盒：申请「用户选择的文件」+「Downloads/AppData 读取」权限，必要时引导用户授予 `Full Disk Access` 来访问其它应用的日志目录
- 网络出站请求白名单化（设置中可见）

---

## 6. 实施步骤（按里程碑）

### M1 - 项目骨架
1. 新建 Xcode SwiftUI macOS 项目 `Tokenomics`
2. 配置 SwiftData、Charts、Keychain 依赖
3. 建立目录结构 & 空的协议/模型
4. 接入基础 Dashboard 静态界面（mock 数据）

### M2 - 核心采集 (Claude Code 优先)
1. 实现 `UsageRecord` 模型与 `PersistenceController`
2. 实现 `ClaudeCodeCollector`（全量 + 增量监听）
3. 接入 `PricingService` 与内置最新 Claude 单价
4. Dashboard 显示真实数据

### M3 - API 类采集
1. `KeychainService` + Settings 中 API Key UI
2. `OpenAIAPICollector`、`AnthropicAPICollector`、`DeepSeekCollector`、`OpenRouterCollector`、`SiliconFlowCollector`
3. `RefreshScheduler` 周期拉取 & 去重

### M4 - 扩展采集
1. `CursorCollector`、`TraeSoloCollector`、`QoderCollector`
2. `GeminiCollector`、`QwenCollector`
3. 处理 ChatGPT 订阅制估算

### M5 - 可视化与体验
1. 完整 Charts 图表 / 趋势 / 模型分布
2. 汇率服务 + 双货币切换
3. 数据导出 CSV / JSON
4. 单价覆盖 UI
5. 应用图标 / 品牌打磨

### M6 - 打磨与发布
1. 错误处理 / 离线兜底
2. 单元测试覆盖采集解析与计价
3. 性能：长日志增量解析压测
4. 公证 (notarize) & DMG 打包

---

## 7. 风险与对策

| 风险 | 对策 |
|---|---|
| 各家工具的本地日志格式无文档、可能变化 | 在 Collector 内做版本探测；解析失败时降级到「未知用量」并提示用户 |
| ChatGPT/Claude Desktop 订阅制无 API 暴露明细 | 标注「估算」并允许用户手动校正；提供「按对话条目估算」模式 |
| 模型价格频繁变动 | `PricingTable.json` 支持 OTA 更新（从 GitHub release 拉取最新）+ 本地覆盖 |
| 访问其他应用沙盒目录受限 | 引导用户启用 Full Disk Access；不强依赖，缺数据时给出明确提示 |
| API Key 泄漏 | 严格走 Keychain；UI 掩码；导出数据时剥离密钥 |
| 不同时区/重复记录 | 用 `requestId` + 时间窗去重；明细统一存 UTC，展示按本地时区 |

---

## 8. 验收标准

- 应用启动后 5 秒内显示今日 Claude Code 真实消耗（前提：本地日志存在）
- 在 Settings 配置 OpenAI / DeepSeek API Key 后，10 分钟内出现对应供应商卡片
- 切换 CNY/USD 显示，所有数额同步变化
- 单价编辑后历史记录重新计算（可选：仅影响新数据）
- 完全离线时仍能展示已采集的本地日志统计

---

## 9. 后续可选增强（非本期）

- 菜单栏极简模式 / 桌面 Widget
- 预算告警 & 通知中心提醒
- 按项目 / 按 Git 仓库归集 Claude Code 用量
- 团队多机汇总（端到端加密同步）
- iCloud 同步设备间用量


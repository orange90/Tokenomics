# Claude 降级/标签检测（`TOO_DUMB_TO_NEED_FABLE` 类信号）实施 Plan

## 0. 背景

推文（@thdxr，2026-07-26）声称：他的很多 prompt 都被 Claude 服务端"降级"，日志里出现了一个内部标记 `TOO_DUMB_TO_NEED_FABLE`。
含义推断：Anthropic 后端存在**用户/会话分层路由**，会根据某些启发式给请求打标签，把它们下发到**更小/更便宜的模型**或**精简版 system prompt**。

用户诉求：能不能实现一个功能，用来**检测 Claude 有没有给我加什么标记**，接入到现有的 macOS SwiftUI 项目 Tokenomics 里。

## 1. 仓库研究结论（已完成）

现有能力（可复用）：
- Claude 请求采集：[AnthropicAPICollector.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Collectors/AnthropicAPICollector.swift)、[ClaudeCodeCollector.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Collectors/ClaudeCodeCollector.swift)
- 通用 HTTP：[APIClient.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Collectors/APIClient.swift)
- Claude 配额/身份探针：[ClaudeQuotaProbe.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Quota/ClaudeQuotaProbe.swift)、[ClaudeWebQuotaProbe.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Quota/ClaudeWebQuotaProbe.swift)、[ClaudeCompositeQuotaProbe.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Quota/ClaudeCompositeQuotaProbe.swift)
- OAuth 凭证：[ClaudeOAuthCredentials.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Quota/ClaudeOAuthCredentials.swift)
- 数据模型：[UsageRecord.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Models/UsageRecord.swift)、[QuotaSnapshot.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Models/QuotaSnapshot.swift)
- 现有视图：[DashboardView.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Views/DashboardView.swift)、[ProviderDetailView.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Views/ProviderDetailView.swift)

结论：把"降级检测"实现为一个**独立探针 + 数据记录 + Dashboard 卡片**，可无缝挂接现有架构。

## 2. 技术可行性分析（诚实版）

必须提前声明的**边界**：
- Anthropic **不会**在公开 API 响应里明文暴露 `TOO_DUMB_TO_NEED_FABLE` 这种内部标签。那条推文里的字符串来自 dax 自己（SST/opencode 作者）的**客户端日志**，很可能是他自己在客户端针对某些响应特征打的分类名，或者从某个内部/半内部端点拿到的。
- 因此，本功能**不能保证"读到那个字符串"本身**，而是要通过**可观测的行为特征**去**推断**你是否被降级/加标。
- 所有检测都基于 **官方 API 响应**、**响应头**、**返回字段**、**行为对比**，不做任何抓包/中间人/破解。

**可观测的降级信号（按可靠性排序）**：

| # | 信号 | 来源 | 可靠性 |
|---|---|---|---|
| 1 | `response.model` 与 `request.model` 不一致 | Messages API 返回体 | 高 |
| 2 | `stop_reason` / `usage` 异常（如异常低的 output tokens） | 返回体 | 中 |
| 3 | 响应头里的路由/实验标记（`anthropic-ratelimit-*`、`x-*`、`request-id` 关联） | HTTP headers | 中 |
| 4 | 同一 prompt 在不同账号/时段的响应质量差异（金标 prompt 对比） | 主动探测 | 高但成本高 |
| 5 | Claude Code / claude.ai Web 端 `/api/organizations/…` 返回的 `capabilities` / `flags` / `entitlements` 字段 | Web 端点（已在项目里用） | 中，字段易变 |
| 6 | 输出长度、latency、TTFT 相对基线的偏移 | 客户端计时 | 低-中 |

## 3. 设计方案

新增一个 **`ClaudeDowngradeProbe`** 模块，双路检测：

### A. 被动检测（Passive Inspection）
从现有采集流里，把每次 Claude 响应的以下字段落库：
- `request.model`（用户指定）
- `response.model`（实际返回）
- `usage.input_tokens` / `output_tokens` / `cache_read` / `cache_creation`
- 响应头白名单：`anthropic-organization-id`、`anthropic-ratelimit-*`、`request-id`、任何 `x-*`
- `stop_reason`
- 请求耗时 & TTFT（若可得）

规则引擎判定：
- `response.model != request.model` → **明确降级**
- 短时间内同一 model 的 output tokens 显著低于个人历史 P50 → **可疑**
- 头里出现从未见过的 `x-*` 字段 → **新标签疑似**

### B. 主动探测（Active Canary）
定义一组 **"金标 prompt"**（3~5 条，覆盖推理/编码/长文），定期（默认每 6h 或手动触发）以固定参数发一次，记录：
- 返回 model
- output tokens
- 一段可哈希的输出摘要（不存原文，只存 SHA-256 前缀 + 长度）
- 全部响应头

用**首次探测**作为基线快照，之后每次探测与基线做 diff，任何偏移都记入"标签疑似事件"。

### C. Web 端信号（可选，复用现有能力）
在 [ClaudeWebQuotaProbe.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Quota/ClaudeWebQuotaProbe.swift) 已用的组织/账户接口上，额外抽取 `capabilities` / `flags` / `experiments` 之类字段（若存在），落到同一张事件表。

## 4. 需要新增/修改的文件

**新增：**
- [ClaudeDowngradeProbe.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Quota/ClaudeDowngradeProbe.swift) — 主动探测器
- [DowngradeSignal.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Models/DowngradeSignal.swift) — 事件模型（timestamp / kind / requestedModel / servedModel / headersDiff / verdict）
- [DowngradeRepository.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Storage/DowngradeRepository.swift) — 事件持久化
- [DowngradeCard.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Views/Components/DowngradeCard.swift) — Dashboard 卡片，展示：最近事件、金标 prompt 状态、"是否被降级"红/黄/绿指示灯
- [DowngradeDetailView.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Views/DowngradeDetailView.swift) — 事件列表 + 每次响应头/字段 diff

**修改：**
- [AnthropicAPICollector.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Collectors/AnthropicAPICollector.swift) — 采集响应时额外抽 `response.model` / headers / stop_reason 交给 `DowngradeRepository`
- [ClaudeCodeCollector.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Collectors/ClaudeCodeCollector.swift) — 同上（若日志里有）
- [APIClient.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Collectors/APIClient.swift) — 暴露响应头 & 增加计时
- [DashboardView.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Views/DashboardView.swift) — 插入 `DowngradeCard`
- [RefreshScheduler.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Scheduler/RefreshScheduler.swift) — 注册金标探测周期任务
- [SettingsView.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Views/SettingsView.swift) — 开关：启用主动探测、探测频率、金标 prompt 编辑
- 本地化：[LocalizationData+en.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Models/LocalizationData+en.swift)、[LocalizationData+zhHans.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Models/LocalizationData+zhHans.swift)、[LocalizationData+zhHant.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Models/LocalizationData+zhHans.swift) 追加相应文案

## 5. 实施步骤

1. **数据层**：新增 `DowngradeSignal` 模型 + `DowngradeRepository`（沿用现有 `UsageRepository` 的持久化风格）
2. **采集增强**：`APIClient` 返回 (data, HTTPURLResponse)；`AnthropicAPICollector` / `ClaudeCodeCollector` 解析并写入 signal
3. **主动探针**：`ClaudeDowngradeProbe` 实现金标 prompt 发送（复用 [ClaudeOAuthCredentials.swift](file:///Users/huangzhe/Documents/Tokenomics/Tokenomics/Quota/ClaudeOAuthCredentials.swift) 或用户配置的 API key）
4. **判定规则**：在 Probe 内实现规则引擎（模型不一致 / 头字段 diff / 输出长度偏移）
5. **调度**：`RefreshScheduler` 增加 downgrade 周期任务（默认 6h，可关）
6. **UI**：`DowngradeCard` + `DowngradeDetailView`，Settings 里加开关
7. **本地化**：补齐三语文案
8. **手动验证**：
   - 故意用 `claude-3-5-haiku` 请求 `claude-opus-4` → 应触发"模型不一致"
   - 关闭 API key → 应优雅降级为"无数据"
9. **构建**：`xcodebuild -project` 或 `swift build`（按项目现有方式）通过

## 6. 依赖与考虑

- **不新增第三方依赖**，仅使用 Foundation / Combine / SwiftUI
- 金标 prompt 会消耗 token。默认关闭主动探测，用户在 Settings 显式启用
- 响应头/字段随 Anthropic API 迭代会变；`headers 白名单` 用配置化列表，未来易调整
- 事件表可能增长快，加入**最多保留 30 天**滚动清理（在 `DowngradeRepository`）

## 7. 风险处理

| 风险 | 处理 |
|---|---|
| Anthropic 关闭 `response.model` 字段 | Probe 优雅降级到"仅头 diff" |
| 用户没有 API key | UI 显示引导，仅走被动模式（如果有 Claude Code 日志） |
| 主动探测被误判为滥用 | 频率下限锁死为 ≥ 1h，且请求量极小（<500 tokens/次） |
| 误报太多（模型不一致其实是用户自己在 CLI 里切了模型） | 判定规则里，把"同一 request-id 内的路由差异"和"用户显式切换"分离；只在**请求 model 是高档且返回是低档**时才标红 |
| 用户以为能读到 `TOO_DUMB_TO_NEED_FABLE` 原文 | 在 UI 明确说明：**本功能不做抓包，只做行为推断**；实际抓不到那个字符串，除非未来 Anthropic 官方暴露 |

## 8. 交付形态

一个 **Dashboard 上的"路由健康"卡片**：
- 🟢 未观察到降级
- 🟡 有可疑事件（模型一致但输出/头异常）
- 🔴 明确降级（`response.model` 低于 `request.model`）

点进去看事件时间线、每次响应的 model 对比、header diff、金标 prompt 走向。

## 9. 实施期偏离说明（写入实现后回填）

**已做**：`DowngradeSignal` 模型 + `DowngradeRepository`（30 天滚动清理）+ `ClaudeDowngradeProbe`（金标 canary + 规则引擎）+ Dashboard 卡片 + 详情页 + Settings 开关 + 三语文案 + Scheduler 周期任务 + `KeychainKey.anthropicCanary`（与 admin key 分离）。

**主动放弃 / 未做（相对原 Plan）**：
1. **不改造 `APIClient`** 暴露响应头。原 Plan 提到用它做"头字段 diff"，实际发现现有的 3 个 Collector 都用它，风险扩散过大；改成把响应体解析里就能拿到的字段（`response.model` / `usage`）作为主判据即可，头 diff 未来若确需再单独扩展。
2. **不改造 `AnthropicAPICollector`** 做被动检测。它拉的是聚合 `usage_report/messages`，本身不含请求侧的 `model`，做被动检测信号很弱。
3. **不在 `ClaudeCodeCollector.mapLine` 落被动 signal**。jsonl 只记录 `message.model`（服务端返回值），没有"用户请求时选择的 model"字段，缺失对照组容易误报。这个能力等 Anthropic 或 Claude Code 在 jsonl 里加入 `requestedModel` 后再做。

结果：本次交付**仅走主动 canary 一条路径**，但这条路径**信号最可靠**，能覆盖用户诉求的核心场景（是否被暗中降级/加标）。

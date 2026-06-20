import SwiftUI
import SwiftData

struct ProviderDetailView: View {
    let providerKey: String
    let displayName: String
    let colorHex: String
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var localization: LocalizationManager
    @Query private var allRecords: [UsageRecord]

    init(provider: Provider) {
        self.providerKey = provider.rawValue
        self.displayName = provider.displayName
        self.colorHex = provider.brandColorHex
        let pv = provider.rawValue
        _allRecords = Query(
            filter: #Predicate { $0.provider == pv },
            sort: [SortDescriptor(\UsageRecord.timestamp, order: .reverse)]
        )
    }

    /// 自定义供应商使用此入口：providerKey 即 CustomProvider.id
    init(customProviderKey: String, displayName: String, colorHex: String) {
        self.providerKey = customProviderKey
        self.displayName = displayName
        self.colorHex = colorHex
        let pv = customProviderKey
        _allRecords = Query(
            filter: #Predicate { $0.provider == pv },
            sort: [SortDescriptor(\UsageRecord.timestamp, order: .reverse)]
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Circle().fill(Color(hex: colorHex)).frame(width: 14, height: 14)
                    Text(displayName).font(.title.bold())
                    Spacer()
                    Text(L10n.tr("provider_detail.count_total.fmt", allRecords.count, CurrencyFormatting.format(usd: totalCost, currency: appState.currency, usdCnyRate: appState.usdCnyRate)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if allRecords.isEmpty {
                    ContentUnavailableView(L10n.tr("provider_detail.empty.title.fmt", displayName),
                        systemImage: "questionmark.folder",
                        description: Text(L10n.tr("provider_detail.empty.desc")))
                    apiKeyGuide
                } else {
                    modelBreakdown
                    recentList
                }
            }
            .padding(20)
        }
        .id(localization.language.rawValue)
    }

    private var totalCost: Double { allRecords.reduce(0) { $0 + $1.costUSD } }

    private var modelBreakdown: some View {
        let grouped = Dictionary(grouping: allRecords) { $0.model }
        let rows = grouped.map { (model, recs) -> (String, Double, Int) in
            (model, recs.reduce(0) { $0 + $1.costUSD }, recs.reduce(0) { $0 + $1.totalTokens })
        }.sorted { $0.1 > $1.1 }
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("provider_detail.by_model")).font(.headline)
            VStack(spacing: 0) {
                ForEach(rows, id: \.0) { row in
                    HStack {
                        Text(row.0).font(.body.monospaced())
                        Spacer()
                        Text(L10n.tr("provider_detail.tokens.fmt", row.2.formatted())).foregroundStyle(.secondary).font(.caption)
                        Text(CurrencyFormatting.format(usd: row.1, currency: appState.currency, usdCnyRate: appState.usdCnyRate))
                            .frame(width: 160, alignment: .trailing)
                            .monospacedDigit().font(.callout.weight(.medium))
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator)))
        }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("provider_detail.recent")).font(.headline)
            VStack(spacing: 0) {
                ForEach(allRecords.prefix(100)) { r in
                    RecordRow(record: r, currency: appState.currency, rate: appState.usdCnyRate)
                    Divider()
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator)))
        }
    }

    // MARK: - API Key 获取指引

    @ViewBuilder
    private var apiKeyGuide: some View {
        if let guide = APIKeyGuide.guide(for: providerKey) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "key.horizontal.fill")
                        .foregroundStyle(Color(hex: colorHex))
                    Text(L10n.tr("provider_detail.api_key_guide.fmt", guide.keyName))
                        .font(.headline)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { idx, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(idx + 1).")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .trailing)
                            Text(step)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let url = guide.consoleURL, let link = URL(string: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                        Link(url, destination: link)
                            .font(.callout)
                    }
                    .padding(.top, 2)
                }

                if let note = guide.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: colorHex).opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color(hex: colorHex).opacity(0.35), lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - API Key Guide 数据

private struct APIKeyGuide {
    let keyName: String
    let steps: [String]
    let consoleURL: String?
    let note: String?

    static func guide(for providerKey: String) -> APIKeyGuide? {
        switch providerKey {
        case Provider.anthropic.rawValue:
            return APIKeyGuide(
                keyName: "Anthropic Admin API Key",
                steps: [
                    "用组织管理员账号登录 Anthropic Console。",
                    "进入左侧「Settings(设置)」→「Admin Keys(管理员密钥)」标签页。",
                    "点击右上角「Create Admin Key」按钮，给密钥起一个名字（如 Tokenomics）。",
                    "复制生成的 sk-ant-admin01-... 密钥（只显示一次）。",
                    "回到 Tokenomics → 设置 →「API Keys」标签，把它粘贴到「Anthropic Admin Key」并保存。"
                ],
                consoleURL: "https://console.anthropic.com/settings/admin-keys",
                note: "必须是组织 Owner 才能创建 Admin Key；普通 sk-ant-api03-... 调用密钥无法访问 usage_report 接口。"
            )

        case Provider.openai.rawValue:
            return APIKeyGuide(
                keyName: "OpenAI Admin Key",
                steps: [
                    "使用组织 Owner 账号登录 OpenAI Platform。",
                    "进入左下角头像 →「Your Profile」→「Admin keys」（或直接访问下方链接）。",
                    "点击「Create new admin key」，名字填 Tokenomics，权限选默认即可。",
                    "复制生成的 sk-admin-... 密钥（只显示一次）。",
                    "回到 Tokenomics → 设置 →「API Keys」标签，把它粘贴到「OpenAI Admin Key」并保存。"
                ],
                consoleURL: "https://platform.openai.com/settings/organization/admin-keys",
                note: "普通 sk-... 用户密钥没有 /v1/organization/usage 权限，必须使用 Admin Key。"
            )

        case Provider.google.rawValue:
            return APIKeyGuide(
                keyName: "Gemini API Key",
                steps: [
                    "用 Google 账号登录 Google AI Studio。",
                    "点击左上角「Get API key」按钮。",
                    "选择已有的 Google Cloud 项目，或新建一个项目。",
                    "点击「Create API key in new project」并复制生成的密钥。",
                    "回到 Tokenomics → 设置 →「API Keys」标签，把它粘贴到「Gemini API Key」并保存。"
                ],
                consoleURL: "https://aistudio.google.com/apikey",
                note: "Google 暂未提供官方 usage 接口，这里只做健康检查；用量统计需自行配置 Cloud Billing 导出。"
            )

        case Provider.deepseek.rawValue:
            return APIKeyGuide(
                keyName: "DeepSeek API Key",
                steps: [
                    "登录 DeepSeek 开放平台 platform.deepseek.com。",
                    "进入左侧「API keys（API 密钥）」页面。",
                    "点击「创建 API Key」，给它命名（如 Tokenomics）。",
                    "复制生成的 sk-... 密钥（只显示一次）。",
                    "回到 Tokenomics → 设置 →「API Keys」标签，把它粘贴到「DeepSeek API Key」并保存。"
                ],
                consoleURL: "https://platform.deepseek.com/api_keys",
                note: "DeepSeek 仅提供 /user/balance 余额接口，Tokenomics 会按余额变化推算消耗。"
            )

        case Provider.qwen.rawValue:
            return APIKeyGuide(
                keyName: "DashScope API Key（国内）",
                steps: [
                    "用阿里云账号登录 DashScope 控制台 bailian.console.aliyun.com。",
                    "右上角点击头像 →「API-KEY 管理」。",
                    "点击「创建新的 API-KEY」，选择默认业务空间。",
                    "复制生成的 sk-... 密钥。",
                    "回到 Tokenomics → 设置 →「API Keys」标签，粘贴到「通义千问 (国内) DashScope Key」并保存。"
                ],
                consoleURL: "https://bailian.console.aliyun.com/?apiKey=1",
                note: "国内端点为 dashscope.aliyuncs.com；如果你使用国际站，请改用「Qwen (International) Key」。"
            )

        case Provider.qwenIntl.rawValue:
            return APIKeyGuide(
                keyName: "DashScope International API Key",
                steps: [
                    "登录国际版 DashScope 控制台 dashscope-intl.console.aliyun.com。",
                    "右上角头像 →「API Keys」页面。",
                    "点击「Create New API Key」。",
                    "复制生成的 sk-... 密钥。",
                    "回到 Tokenomics → 设置 →「API Keys」标签，粘贴到「Qwen (International) Key」并保存。"
                ],
                consoleURL: "https://dashscope-intl.console.aliyun.com/apiKey",
                note: "国际端点为 dashscope-intl.aliyuncs.com，与国内站账号体系独立。"
            )

        case Provider.siliconflow.rawValue:
            return APIKeyGuide(
                keyName: "SiliconFlow API Key",
                steps: [
                    "登录硅基流动控制台 cloud.siliconflow.cn。",
                    "进入左侧「账户管理」→「API 密钥」。",
                    "点击「新建 API 密钥」，填写描述。",
                    "复制生成的 sk-... 密钥。",
                    "回到 Tokenomics → 设置 →「API Keys」标签，粘贴到「SiliconFlow Key」并保存。"
                ],
                consoleURL: "https://cloud.siliconflow.cn/account/ak",
                note: "Tokenomics 会调用 /v1/user/info 获取账户余额快照。"
            )

        case Provider.openrouter.rawValue:
            return APIKeyGuide(
                keyName: "OpenRouter API Key",
                steps: [
                    "登录 openrouter.ai。",
                    "点击右上角头像 →「Keys」。",
                    "点击「Create Key」，填写名称。",
                    "复制生成的 sk-or-... 密钥。",
                    "回到 Tokenomics → 设置 →「API Keys」标签，粘贴到「OpenRouter Key」并保存。"
                ],
                consoleURL: "https://openrouter.ai/settings/keys",
                note: "Tokenomics 会调用 /api/v1/credits 获取信用额度并推算消耗。"
            )

        case Provider.stepfun.rawValue:
            return APIKeyGuide(
                keyName: "Stepfun API Key",
                steps: [
                    "登录阶跃星辰开放平台 platform.stepfun.com。",
                    "进入「接口密钥」页面。",
                    "点击「创建密钥」并填写名称。",
                    "复制生成的密钥。",
                    "回到 Tokenomics → 设置 →「API Keys」标签，粘贴到「Stepfun API Key」并保存。"
                ],
                consoleURL: "https://platform.stepfun.com/interface-key",
                note: "Tokenomics 会调用 /v1/accounts 获取余额快照。"
            )

        case Provider.mimo.rawValue:
            return APIKeyGuide(
                keyName: "小米 MiMo API Key",
                steps: [
                    "登录小米开放平台或 MiMo 控制台 dev.mi.com / mimo.xiaomi.com。",
                    "进入「API 密钥」/「应用管理」页面。",
                    "新建应用并申请 API Key。",
                    "复制生成的 Key 值。",
                    "回到 Tokenomics → 设置 →「API Keys」标签，粘贴到「小米 MiMo API Key」并保存。"
                ],
                consoleURL: nil,
                note: "MiMo 暂未开放 usage 查询接口，仅做健康检查；后续若开放将自动接入。"
            )

        case Provider.kimi.rawValue:
            return APIKeyGuide(
                keyName: "Kimi (Moonshot) API Key",
                steps: [
                    "登录 Moonshot 开放平台 platform.moonshot.cn。",
                    "进入「账户总览」→「API Key 管理」。",
                    "点击「新建」，填写名称和所属项目。",
                    "复制生成的 sk-... 密钥。",
                    "回到 Tokenomics → 设置 →「API Keys」标签，粘贴到「Kimi (Moonshot) API Key」并保存。"
                ],
                consoleURL: "https://platform.moonshot.cn/console/api-keys",
                note: "Tokenomics 会调用 /v1/users/me/balance 获取余额快照。"
            )

        case Provider.glm.rawValue:
            return APIKeyGuide(
                keyName: "智谱 GLM API Key",
                steps: [
                    "登录智谱 BigModel 控制台 open.bigmodel.cn。",
                    "进入右上角头像 →「API Keys」页面。",
                    "点击「添加新的 API Key」。",
                    "复制生成的密钥（形如 xxx.yyy）。",
                    "回到 Tokenomics → 设置 →「API Keys」标签，粘贴到「智谱 GLM API Key」并保存。"
                ],
                consoleURL: "https://open.bigmodel.cn/usercenter/apikeys",
                note: "BigModel 端点为 open.bigmodel.cn，目前仅做健康检查。"
            )

        case Provider.minimax.rawValue:
            return APIKeyGuide(
                keyName: "MiniMax (海螺) API Key",
                steps: [
                    "登录 MiniMax 开放平台 platform.minimaxi.com。",
                    "进入「账户管理」→「接口密钥」。",
                    "点击「创建新的 API Key」并复制。",
                    "复制生成的密钥。",
                    "回到 Tokenomics → 设置 →「API Keys」标签，粘贴到「MiniMax (海螺) API Key」并保存。"
                ],
                consoleURL: "https://platform.minimaxi.com/user-center/basic-information/interface-key",
                note: "MiniMax 暂未开放 usage 查询接口，仅做健康检查。"
            )

        case Provider.volcengine.rawValue:
            return APIKeyGuide(
                keyName: "火山方舟 (豆包) API Key",
                steps: [
                    "登录火山引擎控制台 console.volcengine.com。",
                    "进入「火山方舟」→「API Key 管理」（路径：方舟 → 在线推理 → API Key）。",
                    "点击「创建 API Key」，选择允许访问的接入点。",
                    "复制生成的密钥。",
                    "回到 Tokenomics → 设置 →「API Keys」标签，粘贴到「火山方舟 (豆包) API Key」并保存。"
                ],
                consoleURL: "https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey",
                note: "Ark 端点为 ark.cn-beijing.volces.com，目前仅做健康检查。"
            )

        case Provider.cursor.rawValue:
            return APIKeyGuide(
                keyName: "Cursor 本地日志",
                steps: [
                    "Cursor 无需配置 API Key——Tokenomics 直接读取本地日志。",
                    "请确认你已经登录并使用过 Cursor（macOS 版）。",
                    "默认日志路径：~/Library/Application Support/Cursor/logs。",
                    "如果路径存在但仍无数据，可在「设置 → 数据 → 立即拉取一次」手动触发。"
                ],
                consoleURL: nil,
                note: nil
            )

        case Provider.traeSolo.rawValue:
            return APIKeyGuide(
                keyName: "TRAE Solo 本地日志",
                steps: [
                    "TRAE Solo 无需配置 API Key——Tokenomics 直接读取本地日志。",
                    "请确认 TRAE Solo (macOS) 已经登录并产生过对话记录。",
                    "默认日志路径：~/Library/Application Support/TRAE/、~/.trae 等。",
                    "可在「设置 → 数据 → 立即拉取一次」手动触发解析。"
                ],
                consoleURL: nil,
                note: nil
            )

        case Provider.qoder.rawValue:
            return APIKeyGuide(
                keyName: "Qoder 本地日志",
                steps: [
                    "Qoder 无需配置 API Key——Tokenomics 直接读取本地日志。",
                    "请确认 Qoder (macOS) 已经登录并使用过。",
                    "默认日志路径位于 Qoder 应用沙盒目录下。",
                    "可在「设置 → 数据 → 立即拉取一次」手动触发解析。"
                ],
                consoleURL: nil,
                note: nil
            )

        default:
            // 自定义供应商与未知供应商：给出通用指引
            return APIKeyGuide(
                keyName: "API Key / 自定义端点",
                steps: [
                    "前往该服务商的官方控制台，登录账号。",
                    "在「API 密钥」/「Access Token」相关页面创建一个新密钥。",
                    "复制密钥后回到 Tokenomics → 设置 →「供应商 → 自定义」。",
                    "编辑该自定义供应商，把密钥填入 Headers JSON 的 Authorization 字段（如 Bearer YOUR_KEY）。",
                    "保存并启用「拉取」开关，等待下一次定时任务。"
                ],
                consoleURL: nil,
                note: "如果是内置供应商但未列出指引，可直接到设置 →「API Keys」按提示填写。"
            )
        }
    }
}

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

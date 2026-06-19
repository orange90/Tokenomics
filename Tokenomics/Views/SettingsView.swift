import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: Tab = .keys

    enum Tab: String, CaseIterable, Identifiable {
        case keys = "API Keys"
        case providers = "供应商"
        case subscriptions = "订阅"
        case quotaSources = "额度采集"
        case display = "显示"
        case pricing = "单价"
        case data = "数据"
        var id: String { rawValue }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            APIKeysSettings()
                .tabItem { Label("API Keys", systemImage: "key.horizontal") }
                .tag(Tab.keys)

            ProvidersSettings()
                .tabItem { Label("供应商", systemImage: "rectangle.stack.badge.person.crop") }
                .tag(Tab.providers)

            SubscriptionsSettings()
                .tabItem { Label("订阅", systemImage: "creditcard") }
                .tag(Tab.subscriptions)

            QuotaSourcesSettings()
                .tabItem { Label("额度采集", systemImage: "gauge.with.dots.needle.bottom.50percent") }
                .tag(Tab.quotaSources)

            DisplaySettings()
                .tabItem { Label("显示", systemImage: "paintbrush") }
                .tag(Tab.display)

            PricingSettings()
                .tabItem { Label("单价", systemImage: "dollarsign.circle") }
                .tag(Tab.pricing)

            DataSettings()
                .tabItem { Label("数据", systemImage: "internaldrive") }
                .tag(Tab.data)
        }
        .frame(width: 680, height: 520)
        .padding(20)
    }
}

// MARK: - API Keys

private struct APIKeysSettings: View {
    @EnvironmentObject private var appState: AppState

    private let entries: [(provider: String, label: String, key: String, hint: String)] = [
        (Provider.openai.rawValue,      "OpenAI Admin Key",         KeychainKey.openai,     "用于 /v1/organization/usage 接口"),
        (Provider.anthropic.rawValue,   "Anthropic Admin Key",      KeychainKey.anthropic,  "用于 /v1/organizations/usage_report 接口"),
        (Provider.deepseek.rawValue,    "DeepSeek API Key",         KeychainKey.deepseek,   "拉取 /user/balance"),
        (Provider.google.rawValue,      "Gemini API Key",           KeychainKey.gemini,     "用作健康检查（暂无 usage API）"),
        (Provider.qwen.rawValue,        "通义千问 (国内) DashScope Key", KeychainKey.qwen, "国内端点 dashscope.aliyuncs.com，健康检查"),
        (Provider.qwenIntl.rawValue,    "Qwen (International) Key", KeychainKey.qwenIntl,   "国际端点 dashscope-intl.aliyuncs.com，健康检查"),
        (Provider.siliconflow.rawValue, "SiliconFlow Key",          KeychainKey.siliconflow,"拉取 /v1/user/info"),
        (Provider.openrouter.rawValue,  "OpenRouter Key",           KeychainKey.openrouter, "拉取 /api/v1/credits"),
        (Provider.stepfun.rawValue,     "Stepfun API Key",          KeychainKey.stepfun,    "拉取 /v1/accounts（余额快照）"),
        (Provider.mimo.rawValue,        "小米 MiMo API Key",         KeychainKey.mimo,       "用作健康检查（暂无 usage API）"),
        (Provider.kimi.rawValue,        "Kimi (Moonshot) API Key",  KeychainKey.kimi,       "拉取 /v1/users/me/balance（余额快照）"),
        (Provider.minimax.rawValue,     "MiniMax (海螺) API Key",    KeychainKey.minimax,    "用作健康检查（暂无 usage API）"),
        (Provider.glm.rawValue,         "智谱 GLM API Key",          KeychainKey.glm,        "BigModel 端点 open.bigmodel.cn，健康检查"),
        (Provider.volcengine.rawValue,  "火山方舟 (豆包) API Key",   KeychainKey.volcengine, "Ark 端点 ark.cn-beijing.volces.com，健康检查")
    ]

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("在下方为各个服务商填写 API Key，App 会用它们去拉取用量或余额。")
                        .font(.callout)
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("服务商").font(.caption.weight(.semibold))
                            Text("AI 服务名称").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(width: 140, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("用途").font(.caption.weight(.semibold))
                            Text("该 Key 用于调用哪个接口").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("API Key").font(.caption.weight(.semibold))
                            Text("粘贴你的密钥并点击「保存」").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(width: 260, alignment: .leading)
                    }
                    Text("密钥保存在系统 Keychain 中，不会随数据库导出。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("说明")
            }

            Section {
                let visible = entries.filter { !appState.isProviderHidden($0.provider) }
                if visible.isEmpty {
                    Text("所有内置供应商均已在「供应商」标签下隐藏。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(visible, id: \.key) { e in
                    APIKeyRow(label: e.label, keyName: e.key, hint: e.hint, keychain: appState.keychain)
                }
            } header: {
                Text("密钥列表")
            }
        }
        .formStyle(.grouped)
    }
}

private struct APIKeyRow: View {
    let label: String
    let keyName: String
    let hint: String
    let keychain: KeychainService
    @State private var value: String = ""
    @State private var hasKey: Bool = false

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text(label).font(.body.weight(.medium))
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                SecureField(hasKey ? "已设置（输入新值覆盖）" : "未设置", text: $value)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                HStack {
                    Button("保存") {
                        keychain.set(value, for: keyName)
                        value = ""
                        hasKey = keychain.hasKey(keyName)
                    }
                    .disabled(value.isEmpty)
                    Button("删除") {
                        keychain.delete(keyName)
                        hasKey = false
                    }
                    .disabled(!hasKey)
                }
            }
        }
        .onAppear { hasKey = keychain.hasKey(keyName) }
    }
}

// MARK: - Display

private struct DisplaySettings: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("外观") {
                Picker("显示模式", selection: Binding(
                    get: { appState.appearance },
                    set: { appState.updateAppearance($0) }
                )) {
                    ForEach(AppearanceMode.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("货币") {
                Picker("显示", selection: Binding(
                    get: { appState.currency },
                    set: { appState.updateCurrency($0) }
                )) {
                    ForEach(Currency.allCases) { Text($0.displayName).tag($0) }
                }
                HStack {
                    Text("当前汇率")
                    Spacer()
                    Text("1 USD = ¥\(String(format: "%.4f", appState.usdCnyRate))")
                        .monospacedDigit()
                    Button("刷新") {
                        Task {
                            if let r = try? await appState.exchangeRateService.fetchUSDtoCNY(forceRefresh: true) {
                                await MainActor.run { appState.usdCnyRate = r }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Pricing Override

private struct PricingSettings: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var ctx
    @Query(sort: \PricingOverride.key) private var overrides: [PricingOverride]
    @State private var newKey: String = ""
    @State private var newInput: String = ""
    @State private var newOutput: String = ""
    @State private var filterText: String = ""
    @State private var expandedProviders: Set<String> = [
        Provider.anthropic.rawValue,
        Provider.openai.rawValue
    ]
    /// 用于触发视图刷新——pricingService 不是 ObservableObject，
    /// builtin 表如果在 Settings 窗口首次出现时还未加载完，需要在 onAppear 兜底加载并刷新。
    @State private var pricingRevision: Int = 0

    private var overridesByKey: [String: PricingOverride] {
        Dictionary(uniqueKeysWithValues: overrides.map { ($0.key, $0) })
    }

    /// 把内置表按 provider 分组
    private var groupedBuiltin: [(provider: String, entries: [ModelPricing])] {
        let all = appState.pricingService.allEntries
        let grouped = Dictionary(grouping: all) { $0.provider }
        let providerOrder: [String] = Provider.allCases.map { $0.rawValue }
        return grouped
            .map { (provider: $0.key, entries: $0.value.sorted { $0.model < $1.model }) }
            .sorted { lhs, rhs in
                let li = providerOrder.firstIndex(of: lhs.provider) ?? Int.max
                let ri = providerOrder.firstIndex(of: rhs.provider) ?? Int.max
                if li != ri { return li < ri }
                return lhs.provider < rhs.provider
            }
    }

    private func providerDisplayName(_ key: String) -> String {
        Provider(rawValue: key)?.displayName ?? key
    }

    private func providerColor(_ key: String) -> Color {
        Color(hex: Provider(rawValue: key)?.brandColorHex ?? "#9CA3AF")
    }

    private func matchesFilter(provider: String, model: String) -> Bool {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        return provider.lowercased().contains(q)
            || providerDisplayName(provider).lowercased().contains(q)
            || model.lowercased().contains(q)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("模型单价（USD per 1M tokens）").font(.headline)
                    Text("已内置 Anthropic / OpenAI 等常用模型公开单价；如需覆盖，填写下方表单或在列表中点击「覆盖」。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                TextField("搜索 provider 或 model", text: $filterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // 表头
                    HStack(spacing: 8) {
                        Text("模型").frame(maxWidth: .infinity, alignment: .leading)
                        Text("输入").frame(width: 80, alignment: .trailing)
                        Text("输出").frame(width: 80, alignment: .trailing)
                        Text("缓存写").frame(width: 70, alignment: .trailing)
                        Text("缓存读").frame(width: 70, alignment: .trailing)
                        Text("").frame(width: 60)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)

                    ForEach(groupedBuiltin, id: \.provider) { group in
                        let filtered = group.entries.filter { matchesFilter(provider: group.provider, model: $0.model) }
                        if !filtered.isEmpty {
                            providerGroupView(provider: group.provider, entries: filtered)
                        }
                    }

                    // 额外的覆盖项（用户手动添加、但不在内置表里的）
                    let extraOverrides = overrides.filter { o in
                        appState.pricingService.allEntries.first(where: { $0.key == o.key }) == nil
                    }
                    if !extraOverrides.isEmpty {
                        Text("自定义条目").font(.subheadline.weight(.semibold))
                            .padding(.top, 10)
                            .padding(.horizontal, 6)
                        ForEach(extraOverrides) { o in
                            HStack(spacing: 8) {
                                Text(o.key).font(.body.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(String(format: "%.4f", o.inputPer1M))
                                    .frame(width: 80, alignment: .trailing).monospacedDigit()
                                Text(String(format: "%.4f", o.outputPer1M))
                                    .frame(width: 80, alignment: .trailing).monospacedDigit()
                                Text(String(format: "%.4f", o.cacheWritePer1M))
                                    .frame(width: 70, alignment: .trailing).monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.4f", o.cacheReadPer1M))
                                    .frame(width: 70, alignment: .trailing).monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Button(role: .destructive) {
                                    appState.repository?.deletePricingOverride(key: o.key)
                                    appState.pricingService.loadOverrides(from: appState.repository!)
                                    pricingRevision = appState.pricingService.revision
                                } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                                    .frame(width: 60)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("手动添加 / 覆盖单价").font(.subheadline.weight(.semibold))
                HStack {
                    TextField("key (provider:model)", text: $newKey).textFieldStyle(.roundedBorder)
                    TextField("input", text: $newInput).textFieldStyle(.roundedBorder).frame(width: 80)
                    TextField("output", text: $newOutput).textFieldStyle(.roundedBorder).frame(width: 80)
                    Button("保存") {
                        guard !newKey.isEmpty,
                              let i = Double(newInput),
                              let o = Double(newOutput) else { return }
                        let override = PricingOverride(key: newKey, inputPer1M: i, outputPer1M: o)
                        appState.repository?.upsertPricingOverride(override)
                        appState.pricingService.loadOverrides(from: appState.repository!)
                        newKey = ""; newInput = ""; newOutput = ""
                        pricingRevision = appState.pricingService.revision
                    }
                }
            }
        }
        .onAppear {
            // 兜底：Settings 窗口可能比 RootView 的 bootstrap 更早出现，
            // 此时 builtin 表是空的；这里主动加载一次，并通过 @State 触发本视图刷新。
            if !appState.pricingService.isBuiltinLoaded {
                _ = appState.pricingService.loadBuiltinTable()
                if let repo = appState.repository {
                    appState.pricingService.loadOverrides(from: repo)
                }
            }
            pricingRevision = appState.pricingService.revision
        }
    }

    @ViewBuilder
    private func providerGroupView(provider: String, entries: [ModelPricing]) -> some View {
        let isOpen = expandedProviders.contains(provider)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isOpen { expandedProviders.remove(provider) }
                else { expandedProviders.insert(provider) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Circle().fill(providerColor(provider)).frame(width: 10, height: 10)
                    Text(providerDisplayName(provider)).font(.subheadline.weight(.semibold))
                    Text("(\(entries.count))").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
            }
            .buttonStyle(.plain)

            if isOpen {
                ForEach(entries, id: \.key) { entry in
                    let override = overridesByKey[entry.key]
                    pricingRow(entry: entry, override: override)
                    Divider()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isOpen ? Color.secondary.opacity(0.06) : Color.clear)
        )
    }

    @ViewBuilder
    private func pricingRow(entry: ModelPricing, override: PricingOverride?) -> some View {
        let inVal = override?.inputPer1M ?? entry.inputPer1M
        let outVal = override?.outputPer1M ?? entry.outputPer1M
        let cwVal = override?.cacheWritePer1M ?? entry.cacheWritePer1M ?? 0
        let crVal = override?.cacheReadPer1M ?? entry.cacheReadPer1M ?? 0
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(entry.model).font(.body.monospaced())
                if override != nil {
                    Text("已覆盖")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.4f", inVal))
                .frame(width: 80, alignment: .trailing).monospacedDigit()
            Text(String(format: "%.4f", outVal))
                .frame(width: 80, alignment: .trailing).monospacedDigit()
            Text(cwVal > 0 ? String(format: "%.4f", cwVal) : "—")
                .frame(width: 70, alignment: .trailing).monospacedDigit()
                .foregroundStyle(.secondary)
            Text(crVal > 0 ? String(format: "%.4f", crVal) : "—")
                .frame(width: 70, alignment: .trailing).monospacedDigit()
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Button {
                    newKey = entry.key
                    newInput = String(format: "%.4f", inVal)
                    newOutput = String(format: "%.4f", outVal)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .help("把当前价格填入下方表单以便覆盖")

                if override != nil {
                    Button(role: .destructive) {
                        appState.repository?.deletePricingOverride(key: entry.key)
                        appState.pricingService.loadOverrides(from: appState.repository!)
                        pricingRevision = appState.pricingService.revision
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help("移除覆盖，恢复内置单价")
                }
            }
            .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
    }
}

// MARK: - Data

private struct DataSettings: View {
    @EnvironmentObject private var appState: AppState
    @Query private var records: [UsageRecord]

    var body: some View {
        Form {
            Section("数据库") {
                HStack {
                    Text("记录总数")
                    Spacer()
                    Text("\(records.count)").monospacedDigit()
                }
            }
            Section("操作") {
                Button("立即拉取一次") {
                    appState.manualRefresh()
                }
                .disabled(appState.isRefreshing)

                Button("导出 CSV") {
                    exportCSV()
                }
            }
            Section("路径") {
                Text("数据存储于 macOS SwiftData 容器（沙盒内 ~/Library/Containers/com.tokenomics.Tokenomics）")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "tokenomics-export.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var csv = "timestamp,provider,model,source,inputTokens,outputTokens,cacheCreation,cacheRead,costUSD\n"
        for r in records {
            csv += "\(ISO8601DateFormatter().string(from: r.timestamp)),\(r.provider),\(r.model),\(r.sourceApp),\(r.inputTokens),\(r.outputTokens),\(r.cacheCreationTokens),\(r.cacheReadTokens),\(r.costUSD)\n"
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Providers (visibility + custom providers)

private struct ProvidersSettings: View {
    @EnvironmentObject private var appState: AppState
    @State private var editing: CustomProvider?
    @State private var showingNew = false

    private let builtinPalette: [Color] = [.blue, .indigo, .purple, .pink, .red, .orange, .yellow, .green, .teal, .cyan]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("控制 App 中显示哪些供应商图标。隐藏后将从侧边栏、仪表盘汇总、API Keys 列表中移除。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            TabView {
                builtinList
                    .tabItem { Text("内置") }
                customList
                    .tabItem { Text("自定义") }
            }
        }
        .sheet(isPresented: $showingNew) {
            CustomProviderEditor(initial: nil) { newProvider in
                appState.addCustomProvider(newProvider)
            }
        }
        .sheet(item: $editing) { existing in
            CustomProviderEditor(initial: existing) { _ in
                // 编辑器中已经直接改了 @Model 实例，这里只需触发 reload
                appState.updateCustomProvider(existing)
            }
        }
    }

    private var builtinList: some View {
        let allBuiltin = Provider.allCases.filter { $0 != .unknown }
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(allBuiltin) { p in
                    HStack(spacing: 10) {
                        Circle().fill(Color(hex: p.brandColorHex)).frame(width: 12, height: 12)
                        Text(p.displayName)
                        Spacer()
                        Toggle("显示", isOn: Binding(
                            get: { !appState.isProviderHidden(p.rawValue) },
                            set: { appState.setProviderHidden(p.rawValue, hidden: !$0) }
                        ))
                        .labelsHidden()
                    }
                    .padding(.vertical, 8)
                    .padding(.leading, 4)
                    .padding(.trailing, 16)
                    Divider()
                }
            }
            .padding(.trailing, 4)
        }
    }

    private var customList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("自定义供应商").font(.headline)
                Spacer()
                Button {
                    showingNew = true
                } label: {
                    Label("新增", systemImage: "plus")
                }
            }
            .padding(.bottom, 8)

            if appState.customProviders.isEmpty {
                Text("还没有自定义供应商。点击「新增」可以添加一个外部脚本端点。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(appState.customProviders) { cp in
                            HStack(spacing: 10) {
                                Circle().fill(Color(hex: cp.colorHex)).frame(width: 12, height: 12)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cp.name)
                                    Text(cp.endpointURL.isEmpty ? "未配置端点" : cp.endpointURL)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Toggle("拉取", isOn: Binding(
                                    get: { cp.isCollectionEnabled },
                                    set: { v in
                                        cp.isCollectionEnabled = v
                                        appState.updateCustomProvider(cp)
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .help("启用后会按 5 分钟间隔自动拉取")
                                Toggle("显示", isOn: Binding(
                                    get: { !appState.isProviderHidden(cp.id) },
                                    set: { appState.setProviderHidden(cp.id, hidden: !$0) }
                                ))
                                .labelsHidden()
                                Button { editing = cp } label: { Image(systemName: "pencil") }
                                    .buttonStyle(.borderless)
                                Button(role: .destructive) {
                                    appState.deleteCustomProvider(id: cp.id)
                                } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 8)
                            .padding(.leading, 4)
                            .padding(.trailing, 16)
                            Divider()
                        }
                    }
                    .padding(.trailing, 4)
                }
            }
        }
    }
}

private struct CustomProviderEditor: View {
    @Environment(\.dismiss) private var dismiss
    let initial: CustomProvider?
    let onSave: (CustomProvider) -> Void

    @State private var name: String = ""
    @State private var colorHex: String = "#6366F1"
    @State private var endpointURL: String = ""
    @State private var httpMethod: String = "GET"
    @State private var headersJSON: String = "{\n  \"Authorization\": \"Bearer YOUR_KEY\"\n}"
    @State private var bodyJSON: String = ""
    @State private var recordsPath: String = "data"
    @State private var modelField: String = "model"
    @State private var inputTokensField: String = "input_tokens"
    @State private var outputTokensField: String = "output_tokens"
    @State private var timestampField: String = "timestamp"
    @State private var costField: String = "cost_usd"
    @State private var requestIdField: String = "id"
    @State private var isCollectionEnabled: Bool = false

    private let palette: [String] = [
        "#6366F1", "#3B82F6", "#0EA5E9", "#14B8A6",
        "#22C55E", "#EAB308", "#F97316", "#EF4444",
        "#EC4899", "#A855F7", "#64748B", "#111827"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(initial == nil ? "新增自定义供应商" : "编辑自定义供应商")
                .font(.title3.bold())
                .padding(.bottom, 8)

            ScrollView {
                Form {
                    Section("基础") {
                        TextField("名称（显示用）", text: $name)
                        HStack {
                            Text("颜色")
                            Spacer()
                            ForEach(palette, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle().strokeBorder(colorHex == hex ? Color.primary : .clear, lineWidth: 2)
                                    )
                                    .onTapGesture { colorHex = hex }
                            }
                        }
                        Toggle("启用自动拉取", isOn: $isCollectionEnabled)
                    }

                    Section("HTTP") {
                        TextField("Endpoint URL", text: $endpointURL)
                            .textFieldStyle(.roundedBorder)
                        Picker("方法", selection: $httpMethod) {
                            Text("GET").tag("GET")
                            Text("POST").tag("POST")
                        }
                        .pickerStyle(.segmented)
                        VStack(alignment: .leading) {
                            Text("Headers (JSON)").font(.caption).foregroundStyle(.secondary)
                            TextEditor(text: $headersJSON)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 80)
                                .border(.separator)
                        }
                        if httpMethod == "POST" {
                            VStack(alignment: .leading) {
                                Text("Body (JSON)").font(.caption).foregroundStyle(.secondary)
                                TextEditor(text: $bodyJSON)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(height: 60)
                                    .border(.separator)
                            }
                        }
                    }

                    Section {
                        TextField("记录数组路径 (recordsPath，留空表示根本身是数组)", text: $recordsPath)
                        TextField("模型字段", text: $modelField)
                        TextField("input tokens 字段", text: $inputTokensField)
                        TextField("output tokens 字段", text: $outputTokensField)
                        TextField("时间戳字段（可选）", text: $timestampField)
                        TextField("费用 USD 字段（可选）", text: $costField)
                        TextField("请求 ID 字段（可选，用于去重）", text: $requestIdField)
                    } header: {
                        Text("字段映射")
                    } footer: {
                        Text("路径语法：a.b[0].c  例：data.records 表示根对象 data 下的 records 数组")
                            .font(.caption2)
                    }
                }
                .formStyle(.grouped)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button(initial == nil ? "添加" : "保存") {
                    if let existing = initial {
                        existing.name = name
                        existing.colorHex = colorHex
                        existing.endpointURL = endpointURL
                        existing.httpMethod = httpMethod
                        existing.headersJSON = headersJSON
                        existing.bodyJSON = bodyJSON.isEmpty ? nil : bodyJSON
                        existing.recordsPath = recordsPath
                        existing.modelField = modelField
                        existing.inputTokensField = inputTokensField
                        existing.outputTokensField = outputTokensField
                        existing.timestampField = timestampField.isEmpty ? nil : timestampField
                        existing.costField = costField.isEmpty ? nil : costField
                        existing.requestIdField = requestIdField.isEmpty ? nil : requestIdField
                        existing.isCollectionEnabled = isCollectionEnabled
                        onSave(existing)
                    } else {
                        let p = CustomProvider(
                            name: name.isEmpty ? "未命名" : name,
                            colorHex: colorHex,
                            isVisible: true,
                            isCollectionEnabled: isCollectionEnabled,
                            endpointURL: endpointURL,
                            httpMethod: httpMethod,
                            headersJSON: headersJSON,
                            bodyJSON: bodyJSON.isEmpty ? nil : bodyJSON,
                            recordsPath: recordsPath,
                            modelField: modelField,
                            inputTokensField: inputTokensField,
                            outputTokensField: outputTokensField,
                            timestampField: timestampField.isEmpty ? nil : timestampField,
                            costField: costField.isEmpty ? nil : costField,
                            requestIdField: requestIdField.isEmpty ? nil : requestIdField
                        )
                        onSave(p)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
            .padding(.top, 10)
        }
        .padding(20)
        .frame(width: 560, height: 620)
        .onAppear {
            if let p = initial {
                name = p.name
                colorHex = p.colorHex
                endpointURL = p.endpointURL
                httpMethod = p.httpMethod
                headersJSON = p.headersJSON
                bodyJSON = p.bodyJSON ?? ""
                recordsPath = p.recordsPath
                modelField = p.modelField
                inputTokensField = p.inputTokensField
                outputTokensField = p.outputTokensField
                timestampField = p.timestampField ?? ""
                costField = p.costField ?? ""
                requestIdField = p.requestIdField ?? ""
                isCollectionEnabled = p.isCollectionEnabled
            }
        }
    }
}

// MARK: - Subscriptions

private struct SubscriptionsSettings: View {
    @EnvironmentObject private var appState: AppState
    @State private var editing: Subscription?
    @State private var showingNew: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("订阅套餐").font(.headline)
                    Text("添加你已订阅的 ChatGPT Plus / Claude Pro / Cursor Pro 等，用来在「回本没」页面计算回本率。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingNew = true
                } label: {
                    Label("新增", systemImage: "plus")
                }
            }
            .padding(.bottom, 12)

            if appState.subscriptions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "creditcard.trianglebadge.exclamationmark")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("还没有订阅记录")
                        .font(.subheadline)
                    Text("点击右上角「新增」从预设套餐里挑选，或自定义月费。")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(appState.subscriptions) { sub in
                            let provider = Provider(rawValue: sub.providerKey)
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(hex: provider?.brandColorHex ?? "#9CA3AF"))
                                    .frame(width: 12, height: 12)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider?.displayName ?? sub.providerKey)
                                        .font(.body.weight(.medium))
                                    Text(sub.planName)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(String(format: "$%.2f / 月", sub.monthlyUSD))
                                    .monospacedDigit()
                                Button { editing = sub } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                                Button(role: .destructive) {
                                    appState.deleteSubscription(id: sub.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 8)
                            .padding(.leading, 4)
                            .padding(.trailing, 16)
                            Divider()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingNew) {
            SubscriptionEditor(initial: nil) { sub in
                appState.addSubscription(sub)
            }
        }
        .sheet(item: $editing) { sub in
            SubscriptionEditor(initial: sub) { updated in
                appState.updateSubscription(updated)
            }
        }
    }
}

private struct SubscriptionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let initial: Subscription?
    let onSave: (Subscription) -> Void

    @State private var providerKey: String = Provider.openai.rawValue
    @State private var planName: String = ""
    @State private var monthlyUSDText: String = ""
    @State private var selectedPresetID: String? = nil

    private var availableBuiltin: [Provider] {
        Provider.allCases.filter { $0 != .unknown }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(initial == nil ? "新增订阅" : "编辑订阅")
                .font(.title3.bold())
                .padding(.bottom, 12)

            Form {
                if initial == nil {
                    Section("快速选择预设") {
                        Picker("预设套餐", selection: $selectedPresetID) {
                            Text("（自定义）").tag(String?.none)
                            ForEach(SubscriptionPreset.all) { p in
                                Text("\(p.providerDisplayName) · \(p.planName)  $\(String(format: "%.0f", p.monthlyUSD))")
                                    .tag(Optional(p.id))
                            }
                        }
                        .onChange(of: selectedPresetID) { _, newID in
                            if let id = newID, let p = SubscriptionPreset.all.first(where: { $0.id == id }) {
                                providerKey = p.providerKey
                                planName = p.planName
                                monthlyUSDText = String(format: "%.2f", p.monthlyUSD)
                            }
                        }
                    }
                }

                Section("基础信息") {
                    Picker("供应商", selection: $providerKey) {
                        ForEach(availableBuiltin) { p in
                            Text(p.displayName).tag(p.rawValue)
                        }
                    }
                    TextField("套餐名（如 Plus / Pro / Max 20x）", text: $planName)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Text("月费 (USD)")
                        Spacer()
                        TextField("0.00", text: $monthlyUSDText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button(initial == nil ? "添加" : "保存") {
                    let usd = Double(monthlyUSDText.replacingOccurrences(of: ",", with: ".")) ?? 0
                    let trimmedName = planName.trimmingCharacters(in: .whitespaces)
                    guard usd > 0, !trimmedName.isEmpty else { return }
                    if let existing = initial {
                        var updated = existing
                        updated.providerKey = providerKey
                        updated.planName = trimmedName
                        updated.monthlyUSD = usd
                        onSave(updated)
                    } else {
                        let sub = Subscription(providerKey: providerKey, planName: trimmedName, monthlyUSD: usd)
                        onSave(sub)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(planName.trimmingCharacters(in: .whitespaces).isEmpty
                          || (Double(monthlyUSDText.replacingOccurrences(of: ",", with: ".")) ?? 0) <= 0)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            if let p = initial {
                providerKey = p.providerKey
                planName = p.planName
                monthlyUSDText = String(format: "%.2f", p.monthlyUSD)
            }
        }
    }
}

// MARK: - 额度采集（Claude OAuth ↔ 浏览器 Cookie）

private struct QuotaSourcesSettings: View {
    @EnvironmentObject private var appState: AppState
    @State private var probeResult: String?
    @State private var probing: Bool = false

    private var prefs: ClaudeQuotaPreferences { appState.claudeQuotaPreferences }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Claude 订阅额度采集").font(.headline)
                    Text("Claude 的 5 小时 / 每周 额度可以从两条数据源拉取。OAuth 接口虽然官方，但被限流（HTTP 429）的几率高；浏览器 Cookie 路径走 claude.ai 网页 API，限流策略独立，是 OAuth 被限流时的兜底。")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GroupBox("主路径") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: Binding<Bool>(
                            get: { prefs.cookieAsPrimary },
                            set: { newValue in
                                var p = prefs
                                p.cookieAsPrimary = newValue
                                appState.updateClaudeQuotaPreferences(p)
                            }
                        )) {
                            Text("OAuth 接口（默认）").tag(false)
                            Text("浏览器 Cookie（绕开 OAuth 限流）").tag(true)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                        Text(prefs.cookieAsPrimary
                             ? "首选从本地浏览器读 claude.ai cookie，失败时回退到 OAuth。"
                             : "首选 OAuth；遇到 429 / 401 时自动回退到浏览器 Cookie。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("浏览器优先级") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("从上到下尝试，先成功的浏览器优先使用其 cookie。点开关切换是否启用某个浏览器。")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(orderedBrowsers(), id: \.self) { browser in
                            HStack(spacing: 12) {
                                Image(systemName: prefs.effectiveBrowserPriority.contains(browser)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(prefs.effectiveBrowserPriority.contains(browser) ? .blue : .secondary)
                                Text(browser.displayName)
                                    .frame(width: 80, alignment: .leading)
                                Text(browserHint(browser))
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("↑") { move(browser, by: -1) }
                                    .disabled(!canMove(browser, by: -1))
                                    .buttonStyle(.borderless)
                                Button("↓") { move(browser, by: +1) }
                                    .disabled(!canMove(browser, by: +1))
                                    .buttonStyle(.borderless)
                                Toggle("", isOn: Binding<Bool>(
                                    get: { prefs.effectiveBrowserPriority.contains(browser) },
                                    set: { toggle(browser, on: $0) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("连通性测试") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button {
                                runCookieProbe()
                            } label: {
                                Label(probing ? "正在测试…" : "立即从浏览器读取 cookie",
                                      systemImage: "key.viewfinder")
                            }
                            .disabled(probing)
                            Spacer()
                        }
                        if let r = probeResult {
                            Text(r)
                                .font(.caption.monospaced())
                                .foregroundStyle(r.hasPrefix("✓") ? .green : .red)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("第一次读取会弹出系统钥匙串授权，点「始终允许」即可。")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: - 浏览器优先级编辑辅助

    private func orderedBrowsers() -> [ChromiumBrowser] {
        // 展示顺序 = 当前 effectivePriority + 未启用项追加在末尾
        var seen = Set<ChromiumBrowser>()
        var ordered: [ChromiumBrowser] = []
        for b in prefs.effectiveBrowserPriority where !seen.contains(b) {
            ordered.append(b); seen.insert(b)
        }
        for b in ChromiumBrowser.allCases where !seen.contains(b) {
            ordered.append(b); seen.insert(b)
        }
        return ordered
    }

    private func canMove(_ browser: ChromiumBrowser, by delta: Int) -> Bool {
        let list = orderedBrowsers()
        guard let idx = list.firstIndex(of: browser) else { return false }
        let target = idx + delta
        return target >= 0 && target < list.count
    }

    private func move(_ browser: ChromiumBrowser, by delta: Int) {
        var list = orderedBrowsers()
        guard let idx = list.firstIndex(of: browser) else { return }
        let target = idx + delta
        guard target >= 0 && target < list.count else { return }
        list.swapAt(idx, target)
        var p = prefs
        // 仅保留当前启用的浏览器
        p.browserPriority = list.filter { p.effectiveBrowserPriority.contains($0) }
        appState.updateClaudeQuotaPreferences(p)
    }

    private func toggle(_ browser: ChromiumBrowser, on: Bool) {
        var p = prefs
        var current = p.effectiveBrowserPriority
        if on {
            if !current.contains(browser) { current.append(browser) }
        } else {
            current.removeAll { $0 == browser }
        }
        p.browserPriority = current
        appState.updateClaudeQuotaPreferences(p)
    }

    private func browserHint(_ b: ChromiumBrowser) -> String {
        switch b {
        case .chrome: return "Google Chrome (~/Library/Application Support/Google/Chrome)"
        case .brave:  return "Brave Browser (~/Library/Application Support/BraveSoftware/Brave-Browser)"
        }
    }

    // MARK: - 连通性测试

    private func runCookieProbe() {
        probing = true
        probeResult = nil
        let priority = prefs.effectiveBrowserPriority
        Task.detached {
            let reader = ChromiumCookieReader()
            let result = reader.readSessionKey(preferred: priority)
            await MainActor.run {
                switch result {
                case .success(let c):
                    let suffix = String(c.sessionKey.suffix(6))
                    probeResult = "✓ 已从 \(c.browser.displayName)/\(c.profile) 读到 sessionKey（…\(suffix)），host=\(c.hostKey)"
                case .failure(let e):
                    probeResult = "✗ \(e.localizedDescription)"
                }
                probing = false
            }
        }
    }
}

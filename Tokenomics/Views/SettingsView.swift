import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var localization: LocalizationManager
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
                .tabItem { Label(L10n.tr("settings.tab.keys"), systemImage: "key.horizontal") }
                .tag(Tab.keys)

            ProvidersSettings()
                .tabItem { Label(L10n.tr("settings.tab.providers"), systemImage: "rectangle.stack.badge.person.crop") }
                .tag(Tab.providers)

            SubscriptionsSettings()
                .tabItem { Label(L10n.tr("settings.tab.subscriptions"), systemImage: "creditcard") }
                .tag(Tab.subscriptions)

            QuotaSourcesSettings()
                .tabItem { Label(L10n.tr("settings.tab.quotaSources"), systemImage: "gauge.with.dots.needle.bottom.50percent") }
                .tag(Tab.quotaSources)

            DisplaySettings()
                .tabItem { Label(L10n.tr("settings.tab.display"), systemImage: "paintbrush") }
                .tag(Tab.display)

            PricingSettings()
                .tabItem { Label(L10n.tr("settings.tab.pricing"), systemImage: "dollarsign.circle") }
                .tag(Tab.pricing)

            DataSettings()
                .tabItem { Label(L10n.tr("settings.tab.data"), systemImage: "internaldrive") }
                .tag(Tab.data)
        }
        .frame(width: 680, height: 520)
        .padding(20)
        .id(localization.language.rawValue)
    }
}

// MARK: - API Keys

private struct APIKeysSettings: View {
    @EnvironmentObject private var appState: AppState

    private var entries: [(provider: String, label: String, key: String, hint: String)] {
        [
            (Provider.openai.rawValue,      "OpenAI Admin Key",         KeychainKey.openai,     L10n.tr("apikey.hint.openai")),
            (Provider.anthropic.rawValue,   "Anthropic Admin Key",      KeychainKey.anthropic,  L10n.tr("apikey.hint.anthropic"))
        ]
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("settings.keys.intro"))
                        .font(.callout)
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tr("settings.keys.col.provider")).font(.caption.weight(.semibold))
                            Text(L10n.tr("settings.keys.col.provider.sub")).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(width: 140, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tr("settings.keys.col.usage")).font(.caption.weight(.semibold))
                            Text(L10n.tr("settings.keys.col.usage.sub")).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tr("settings.keys.col.apikey")).font(.caption.weight(.semibold))
                            Text(L10n.tr("settings.keys.col.apikey.sub")).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(width: 260, alignment: .leading)
                    }
                    Text(L10n.tr("settings.keys.security"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text(L10n.tr("settings.keys.section.note"))
            }

            Section {
                let visible = entries.filter { !appState.isProviderHidden($0.provider) }
                if visible.isEmpty {
                    Text(L10n.tr("settings.keys.empty"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(visible, id: \.key) { e in
                    APIKeyRow(label: e.label, keyName: e.key, hint: e.hint, keychain: appState.keychain)
                }
            } header: {
                Text(L10n.tr("settings.keys.section.list"))
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
                SecureField(hasKey ? L10n.tr("settings.keys.placeholder.set") : L10n.tr("settings.keys.placeholder.unset"), text: $value)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                HStack {
                    Button(L10n.tr("common.save")) {
                        keychain.set(value, for: keyName)
                        value = ""
                        hasKey = keychain.hasKey(keyName)
                    }
                    .disabled(value.isEmpty)
                    Button(L10n.tr("common.delete")) {
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
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        Form {
            Section(L10n.tr("settings.language.section")) {
                Picker(L10n.tr("settings.language.picker"), selection: Binding(
                    get: { localization.language },
                    set: { localization.update($0) }
                )) {
                    Text(L10n.tr("lang.simplified_chinese")).tag(AppLanguage.zhHans)
                    Text(L10n.tr("lang.traditional_chinese")).tag(AppLanguage.zhHant)
                    Text(L10n.tr("lang.english")).tag(AppLanguage.en)
                    Text(L10n.tr("lang.system")).tag(AppLanguage.system)
                }
                .pickerStyle(.menu)
            }

            Section(L10n.tr("settings.display.appearance")) {
                Picker(L10n.tr("settings.display.mode"), selection: Binding(
                    get: { appState.appearance },
                    set: { appState.updateAppearance($0) }
                )) {
                    ForEach(AppearanceMode.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section(L10n.tr("settings.display.currency")) {
                Picker(L10n.tr("settings.display.currency.label"), selection: Binding(
                    get: { appState.currency },
                    set: { appState.updateCurrency($0) }
                )) {
                    ForEach(Currency.allCases) { Text($0.displayName).tag($0) }
                }
                HStack {
                    Text(L10n.tr("settings.display.rate"))
                    Spacer()
                    Text("1 USD = ¥\(String(format: "%.4f", appState.usdCnyRate))")
                        .monospacedDigit()
                    Button(L10n.tr("settings.display.rate.refresh")) {
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
                    Text(L10n.tr("pricing.title")).font(.headline)
                    Text(L10n.tr("pricing.desc"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                TextField(L10n.tr("pricing.search"), text: $filterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // 表头
                    HStack(spacing: 8) {
                        Text(L10n.tr("pricing.col.model")).frame(maxWidth: .infinity, alignment: .leading)
                        Text(L10n.tr("pricing.col.input")).frame(width: 80, alignment: .trailing)
                        Text(L10n.tr("pricing.col.output")).frame(width: 80, alignment: .trailing)
                        Text(L10n.tr("pricing.col.cacheWrite")).frame(width: 70, alignment: .trailing)
                        Text(L10n.tr("pricing.col.cacheRead")).frame(width: 70, alignment: .trailing)
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
                        Text(L10n.tr("pricing.custom_entries")).font(.subheadline.weight(.semibold))
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
                Text(L10n.tr("pricing.add_section")).font(.subheadline.weight(.semibold))
                HStack {
                    TextField(L10n.tr("pricing.placeholder.key"), text: $newKey).textFieldStyle(.roundedBorder)
                    TextField(L10n.tr("pricing.placeholder.input"), text: $newInput).textFieldStyle(.roundedBorder).frame(width: 80)
                    TextField(L10n.tr("pricing.placeholder.output"), text: $newOutput).textFieldStyle(.roundedBorder).frame(width: 80)
                    Button(L10n.tr("common.save")) {
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
                    Text(L10n.tr("pricing.overridden"))
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
                .help(L10n.tr("pricing.help.fill_form"))

                if override != nil {
                    Button(role: .destructive) {
                        appState.repository?.deletePricingOverride(key: entry.key)
                        appState.pricingService.loadOverrides(from: appState.repository!)
                        pricingRevision = appState.pricingService.revision
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.tr("pricing.help.remove_override"))
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

    /// 月度账单 / 月度 CSV / Markdown 摘要使用的目标月份。默认是当前月。
    @State private var selectedMonth: Date = {
        Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    }()
    @State private var lastExportMessage: String?
    @State private var includeMonthlySummaryInJSON: Bool = true

    /// 给账单 PDF 上打印的「账户 / 团队」名（可选）。
    @State private var accountName: String = ""

    var body: some View {
        Form {
            Section(L10n.tr("data.section.db")) {
                HStack {
                    Text(L10n.tr("data.records.total"))
                    Spacer()
                    Text("\(records.count)").monospacedDigit()
                }
            }

            Section(L10n.tr("data.section.actions")) {
                Button(L10n.tr("data.fetch_now")) {
                    appState.manualRefresh()
                }
                .disabled(appState.isRefreshing)
            }

            Section(L10n.tr("data.section.export.raw")) {
                Text(L10n.tr("data.export.raw.desc"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button(L10n.tr("data.export_csv")) { exportRawCSV() }
                    Button(L10n.tr("data.export_json")) { exportRawJSON() }
                    Toggle(L10n.tr("data.export.json.include_monthly"), isOn: $includeMonthlySummaryInJSON)
                        .toggleStyle(.checkbox)
                        .help(L10n.tr("data.export.json.include_monthly.help"))
                }
            }

            Section(L10n.tr("data.section.export.monthly")) {
                Text(L10n.tr("data.export.monthly.desc"))
                    .font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text(L10n.tr("data.export.monthly.month"))
                    MonthPicker(selection: $selectedMonth)
                        .frame(width: 200)
                    Spacer()
                }

                HStack(spacing: 12) {
                    Text(L10n.tr("data.export.monthly.account"))
                    TextField(L10n.tr("data.export.monthly.account.placeholder"),
                              text: $accountName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }

                HStack(spacing: 10) {
                    Button {
                        exportMonthlyPDF()
                    } label: {
                        Label(L10n.tr("data.export.monthly.pdf"), systemImage: "doc.richtext")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        exportMonthlyCSV()
                    } label: {
                        Label(L10n.tr("data.export.monthly.csv"), systemImage: "tablecells")
                    }

                    Button {
                        copyMonthlyMarkdown()
                    } label: {
                        Label(L10n.tr("data.export.monthly.copy_md"), systemImage: "doc.on.clipboard")
                    }
                }

                if let msg = lastExportMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L10n.tr("data.section.path")) {
                Text(L10n.tr("data.path.desc"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: selectedMonth)
    }

    private func providerDisplayName(_ key: String) -> String {
        if let p = Provider(rawValue: key), p != .unknown {
            return p.displayName
        }
        if let cp = appState.customProviders.first(where: { $0.id == key }) {
            return cp.name
        }
        return key
    }

    private func buildReport() -> ReportExporter.MonthlyReport {
        ReportExporter.buildMonthlyReport(
            records: records,
            month: selectedMonth,
            providerDisplay: providerDisplayName(_:)
        )
    }

    // MARK: - Actions

    private func exportRawCSV() {
        let csv = ReportExporter.makeCSV(records: records)
        ReportExporter.saveWithPanel(
            suggestedName: "tokenomics-export.csv",
            contentTypes: [.commaSeparatedText]
        ) { url in
            try csv.write(to: url, atomically: true, encoding: .utf8)
            lastExportMessage = L10n.tr("data.export.saved.fmt", url.path)
        }
    }

    private func exportRawJSON() {
        let report = includeMonthlySummaryInJSON ? buildReport() : nil
        let data = ReportExporter.makeJSON(records: records, monthlyReport: report,
                                           rate: appState.usdCnyRate)
        ReportExporter.saveWithPanel(
            suggestedName: "tokenomics-export.json",
            contentTypes: [.json]
        ) { url in
            try data.write(to: url, options: .atomic)
            lastExportMessage = L10n.tr("data.export.saved.fmt", url.path)
        }
    }

    private func exportMonthlyPDF() {
        let report = buildReport()
        let pdf = ReportExporter.makeMonthlyPDF(
            report: report,
            currency: appState.currency,
            rate: appState.usdCnyRate,
            accountName: accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : accountName
        )
        ReportExporter.saveWithPanel(
            suggestedName: "tokenomics-\(report.monthLabel).pdf",
            contentTypes: [.pdf]
        ) { url in
            try pdf.write(to: url, options: .atomic)
            lastExportMessage = L10n.tr("data.export.saved.fmt", url.path)
        }
    }

    private func exportMonthlyCSV() {
        let report = buildReport()
        let csv = ReportExporter.makeMonthlyCSV(report: report, rate: appState.usdCnyRate)
        ReportExporter.saveWithPanel(
            suggestedName: "tokenomics-\(report.monthLabel)-summary.csv",
            contentTypes: [.commaSeparatedText]
        ) { url in
            try csv.write(to: url, atomically: true, encoding: .utf8)
            lastExportMessage = L10n.tr("data.export.saved.fmt", url.path)
        }
    }

    private func copyMonthlyMarkdown() {
        let report = buildReport()
        let md = ReportExporter.makeMonthlyMarkdown(
            report: report,
            currency: appState.currency,
            rate: appState.usdCnyRate
        )
        ReportExporter.copyToPasteboard(md)
        lastExportMessage = L10n.tr("data.export.copied.md.fmt", monthLabel)
    }
}

/// 月份选择器：用 menu 列出最近 24 个月。
/// 不用 DatePicker(.compact) 的原因是它最细只能到 day，UI 上还要再点几次才能定位月。
private struct MonthPicker: View {
    @Binding var selection: Date

    private var options: [Date] {
        let cal = Calendar.current
        let now = Date()
        let curStart = cal.dateInterval(of: .month, for: now)?.start ?? now
        var list: [Date] = []
        for i in 0..<24 {
            if let d = cal.date(byAdding: .month, value: -i, to: curStart) {
                list.append(d)
            }
        }
        return list
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { d in
                Text(Self.fmt.string(from: d)).tag(d)
            }
        }
        .labelsHidden()
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
            Text(L10n.tr("providers.intro"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            TabView {
                builtinList
                    .tabItem { Text(L10n.tr("providers.tab.builtin")) }
                customList
                    .tabItem { Text(L10n.tr("providers.tab.custom")) }
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
                        Toggle(L10n.tr("providers.toggle.show"), isOn: Binding(
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
                Text(L10n.tr("providers.custom.title")).font(.headline)
                Spacer()
                Button {
                    showingNew = true
                } label: {
                    Label(L10n.tr("common.new"), systemImage: "plus")
                }
            }
            .padding(.bottom, 8)

            if appState.customProviders.isEmpty {
                Text(L10n.tr("providers.custom.empty"))
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
                                    Text(cp.endpointURL.isEmpty ? L10n.tr("providers.custom.no_endpoint") : cp.endpointURL)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Toggle(L10n.tr("providers.toggle.collect"), isOn: Binding(
                                    get: { cp.isCollectionEnabled },
                                    set: { v in
                                        cp.isCollectionEnabled = v
                                        appState.updateCustomProvider(cp)
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .help(L10n.tr("providers.toggle.collect.help"))
                                Toggle(L10n.tr("providers.toggle.show"), isOn: Binding(
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
            Text(initial == nil ? L10n.tr("custom.editor.new") : L10n.tr("custom.editor.edit"))
                .font(.title3.bold())
                .padding(.bottom, 8)

            ScrollView {
                Form {
                    Section(L10n.tr("custom.editor.section.basic")) {
                        TextField(L10n.tr("custom.editor.name"), text: $name)
                        HStack {
                            Text(L10n.tr("custom.editor.color"))
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
                        Toggle(L10n.tr("custom.editor.enable_collect"), isOn: $isCollectionEnabled)
                    }

                    Section(L10n.tr("custom.editor.section.http")) {
                        TextField(L10n.tr("custom.editor.endpoint"), text: $endpointURL)
                            .textFieldStyle(.roundedBorder)
                        Picker(L10n.tr("custom.editor.method"), selection: $httpMethod) {
                            Text("GET").tag("GET")
                            Text("POST").tag("POST")
                        }
                        .pickerStyle(.segmented)
                        VStack(alignment: .leading) {
                            Text(L10n.tr("custom.editor.headers")).font(.caption).foregroundStyle(.secondary)
                            TextEditor(text: $headersJSON)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 80)
                                .border(.separator)
                        }
                        if httpMethod == "POST" {
                            VStack(alignment: .leading) {
                                Text(L10n.tr("custom.editor.body")).font(.caption).foregroundStyle(.secondary)
                                TextEditor(text: $bodyJSON)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(height: 60)
                                    .border(.separator)
                            }
                        }
                    }

                    Section {
                        TextField(L10n.tr("custom.editor.records_path"), text: $recordsPath)
                        TextField(L10n.tr("custom.editor.model_field"), text: $modelField)
                        TextField(L10n.tr("custom.editor.input_field"), text: $inputTokensField)
                        TextField(L10n.tr("custom.editor.output_field"), text: $outputTokensField)
                        TextField(L10n.tr("custom.editor.timestamp_field"), text: $timestampField)
                        TextField(L10n.tr("custom.editor.cost_field"), text: $costField)
                        TextField(L10n.tr("custom.editor.requestid_field"), text: $requestIdField)
                    } header: {
                        Text(L10n.tr("custom.editor.section.mapping"))
                    } footer: {
                        Text(L10n.tr("custom.editor.mapping.footer"))
                            .font(.caption2)
                    }
                }
                .formStyle(.grouped)
            }

            HStack {
                Spacer()
                Button(L10n.tr("common.cancel")) { dismiss() }
                Button(initial == nil ? L10n.tr("common.add") : L10n.tr("common.save")) {
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
                            name: name.isEmpty ? L10n.tr("custom.editor.unnamed") : name,
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
                    Text(L10n.tr("subs.title")).font(.headline)
                    Text(L10n.tr("subs.desc"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingNew = true
                } label: {
                    Label(L10n.tr("common.new"), systemImage: "plus")
                }
            }
            .padding(.bottom, 12)

            if appState.subscriptions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "creditcard.trianglebadge.exclamationmark")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(L10n.tr("subs.empty.title"))
                        .font(.subheadline)
                    Text(L10n.tr("subs.empty.desc"))
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
                                Text(L10n.tr("subs.monthly.fmt", sub.monthlyUSD))
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
            Text(initial == nil ? L10n.tr("subs.editor.new") : L10n.tr("subs.editor.edit"))
                .font(.title3.bold())
                .padding(.bottom, 12)

            Form {
                if initial == nil {
                    Section(L10n.tr("subs.editor.preset_section")) {
                        Picker(L10n.tr("subs.editor.preset_picker"), selection: $selectedPresetID) {
                            Text(L10n.tr("subs.editor.preset_custom")).tag(String?.none)
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

                Section(L10n.tr("subs.editor.basic")) {
                    Picker(L10n.tr("subs.editor.provider"), selection: $providerKey) {
                        ForEach(availableBuiltin) { p in
                            Text(p.displayName).tag(p.rawValue)
                        }
                    }
                    TextField(L10n.tr("subs.editor.plan_name"), text: $planName)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Text(L10n.tr("subs.editor.monthly_usd"))
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
                Button(L10n.tr("common.cancel")) { dismiss() }
                Button(initial == nil ? L10n.tr("common.add") : L10n.tr("common.save")) {
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
                    Text(L10n.tr("quota.title")).font(.headline)
                    Text(L10n.tr("quota.desc"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GroupBox(L10n.tr("quota.primary")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: Binding<Bool>(
                            get: { prefs.cookieAsPrimary },
                            set: { newValue in
                                var p = prefs
                                p.cookieAsPrimary = newValue
                                appState.updateClaudeQuotaPreferences(p)
                            }
                        )) {
                            Text(L10n.tr("quota.primary.oauth")).tag(false)
                            Text(L10n.tr("quota.primary.cookie")).tag(true)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                        Text(prefs.cookieAsPrimary
                             ? L10n.tr("quota.primary.cookie_desc")
                             : L10n.tr("quota.primary.oauth_desc"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(L10n.tr("quota.browser.priority")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("quota.browser.priority.desc"))
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

                GroupBox(L10n.tr("quota.test")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button {
                                runCookieProbe()
                            } label: {
                                Label(probing ? L10n.tr("quota.test.running") : L10n.tr("quota.test.run"),
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
                        Text(L10n.tr("quota.test.keychain_hint"))
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
                    probeResult = "✓ " + L10n.tr("quota.probe.success.fmt", c.browser.displayName, c.profile, suffix, c.hostKey)
                case .failure(let e):
                    probeResult = "✗ \(e.localizedDescription)"
                }
                probing = false
            }
        }
    }
}

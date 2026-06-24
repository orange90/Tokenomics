import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var localization: LocalizationManager
    @Query(sort: \UsageRecord.timestamp, order: .reverse) private var records: [UsageRecord]

    /// 顶部「5h 限额」框选中的供应商。默认 OpenAI。
    @State private var fiveHourProvider: Provider = .openai
    /// 由 TasksScanner 拉到的任务列表（仅用于顶部 5h 卡片按任务拆分）。
    /// 拉取放在 .task 里异步执行，避免阻塞首屏。
    @State private var taskSessions: [TaskSession] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                section(L10n.tr("dashboard.five_hour.section")) {
                    FiveHourBreakdownCard(
                        snapshot: appState.quotaSnapshots[snapshotKey(for: fiveHourProvider)],
                        selectedProvider: fiveHourProvider,
                        sessionsToday: sessionsToday(for: fiveHourProvider),
                        onSelectProvider: { fiveHourProvider = $0 }
                    )
                }

                if !appState.quotaSnapshots.isEmpty {
                    section(L10n.tr("dashboard.section.quota")) {
                        let cols = quotaColumns
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(quotaCards, id: \.snapshot.id) { item in
                                QuotaCard(
                                    snapshot: item.snapshot,
                                    accent: item.accent,
                                    usage: planUsage(for: item.snapshot.id),
                                    currency: appState.currency,
                                    usdCnyRate: appState.usdCnyRate
                                )
                            }
                        }
                    }
                }

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    CostCard(title: L10n.tr("dashboard.cost.today"), costUSD: sum(records: today),
                             totalTokens: tokens(today),
                             currency: appState.currency, rate: appState.usdCnyRate,
                             accent: .blue)
                    CostCard(title: L10n.tr("dashboard.cost.week"), costUSD: sum(records: thisWeek),
                             totalTokens: tokens(thisWeek),
                             currency: appState.currency, rate: appState.usdCnyRate,
                             accent: .green)
                    CostCard(title: L10n.tr("dashboard.cost.month"), costUSD: sum(records: thisMonth),
                             totalTokens: tokens(thisMonth),
                             currency: appState.currency, rate: appState.usdCnyRate,
                             accent: .orange)
                    CostCard(title: L10n.tr("dashboard.cost.total"), costUSD: sum(records: records),
                             totalTokens: tokens(records),
                             currency: appState.currency, rate: appState.usdCnyRate,
                             accent: .pink)
                }

                section(L10n.tr("dashboard.section.trend")) {
                    UsageTrendChart(
                        data: trendData(),
                        rate: appState.usdCnyRate,
                        currency: appState.currency
                    )
                }

                section(L10n.tr("dashboard.section.by_provider")) {
                    VStack(spacing: 0) {
                        ForEach(providerSummaries(), id: \.key) { item in
                            ProviderRow(
                                providerKey: item.key,
                                displayName: item.displayName,
                                colorHex: item.colorHex,
                                totalCostUSD: item.cost,
                                totalTokens: item.tokens,
                                recordCount: item.count,
                                currency: appState.currency,
                                rate: appState.usdCnyRate
                            )
                            Divider()
                        }
                        if providerSummaries().isEmpty {
                            ContentUnavailableView(L10n.tr("dashboard.empty.title"), systemImage: "tray",
                                description: Text(L10n.tr("dashboard.empty.desc")))
                                .padding()
                        }
                    }
                }

                section(L10n.tr("dashboard.section.recent")) {
                    VStack(spacing: 0) {
                        ForEach(records.prefix(30)) { r in
                            RecordRow(record: r, currency: appState.currency, rate: appState.usdCnyRate)
                            Divider()
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .id(localization.language.rawValue)
        .task {
            await reloadTaskSessions()
        }
    }

    /// 后台扫描 Claude / Codex 的 jsonl 任务日志，仅用于顶部 5h 卡片的「按任务拆分」。
    /// 与 TasksView 共用 TasksScanner，但这里不做 selection / sort 等交互。
    private func reloadTaskSessions() async {
        let pricing = appState.pricingService
        let result = await Task.detached(priority: .utility) {
            TasksScanner.scanAll(pricing: pricing)
        }.value
        self.taskSessions = result.sessions
    }

    /// 仅返回今天（startOfDay 之后）且属于指定 provider 的会话。
    /// FiveHourBreakdownCard 内部还会按 5h 窗口起点二次过滤。
    private func sessionsToday(for provider: Provider) -> [TaskSession] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return taskSessions.filter { s in
            guard s.provider == provider else { return false }
            guard let ts = s.lastTimestamp else { return false }
            return ts >= startOfToday
        }
    }

    /// AppState.quotaSnapshots 的 key 是 probe id（"claude" / "codex"），
    /// 这里把 Provider 反查回去。
    private func snapshotKey(for p: Provider) -> String {
        switch p {
        case .anthropic: return "claude"
        case .openai:    return "codex"
        case .unknown:   return ""
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("dashboard.title"))
                    .font(.title.bold())
                Text(L10n.tr("dashboard.rate.fmt", String(format: "%.2f", appState.usdCnyRate)) +
                     (appState.lastRefreshAt.map { L10n.tr("dashboard.rate.last_update.fmt", timeFmt.string(from: $0)) } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker(L10n.tr("dashboard.picker.currency"), selection: Binding(
                get: { appState.currency },
                set: { appState.updateCurrency($0) }
            )) {
                ForEach(Currency.allCases) { c in
                    Text(c.displayName).tag(c)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.background.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
                )
        }
    }

    // MARK: - Aggregations

    private var today: [UsageRecord] {
        let start = Calendar.current.startOfDay(for: Date())
        return records.filter { $0.timestamp >= start }
    }

    private var thisWeek: [UsageRecord] {
        let now = Date()
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        return records.filter { $0.timestamp >= start }
    }

    private var thisMonth: [UsageRecord] {
        let now = Date()
        let start = Calendar.current.dateInterval(of: .month, for: now)?.start ?? now
        return records.filter { $0.timestamp >= start }
    }

    private func sum(records: [UsageRecord]) -> Double { records.reduce(0) { $0 + $1.costUSD } }
    private func tokens(_ records: [UsageRecord]) -> Int { records.reduce(0) { $0 + $1.totalTokens } }

    private func trendData() -> [DailyCost] {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -13, to: cal.startOfDay(for: Date())) else { return [] }
        let filtered = records.filter { $0.timestamp >= cutoff }
        var grouped: [String: [UsageRecord]] = [:]
        for r in filtered {
            let day = cal.startOfDay(for: r.timestamp)
            let key = "\(day.timeIntervalSince1970)|\(r.provider)"
            grouped[key, default: []].append(r)
        }
        return grouped.map { k, recs -> DailyCost in
            let parts = k.split(separator: "|")
            let ts = TimeInterval(parts[0]) ?? 0
            let provider = String(parts[1])
            let providerName = Provider(rawValue: provider)?.displayName ?? provider
            return DailyCost(day: Date(timeIntervalSince1970: ts),
                             provider: providerName,
                             costUSD: recs.reduce(0) { $0 + $1.costUSD })
        }
        .sorted { $0.day < $1.day }
    }

    private struct ProviderSummary {
        let key: String        // Provider.rawValue 或 CustomProvider.id
        let displayName: String
        let colorHex: String
        let cost: Double
        let tokens: Int
        let count: Int
    }

    private func providerSummaries() -> [ProviderSummary] {
        var dict: [String: (Double, Int, Int)] = [:]
        for r in thisMonth {
            var cur = dict[r.provider] ?? (0, 0, 0)
            cur.0 += r.costUSD
            cur.1 += r.totalTokens
            cur.2 += 1
            dict[r.provider] = cur
        }
        let customById = Dictionary(uniqueKeysWithValues: appState.customProviders.map { ($0.id, $0) })
        return dict.compactMap { key, value -> ProviderSummary? in
            if appState.isProviderHidden(key) { return nil }
            if let p = Provider(rawValue: key), p != .unknown {
                return ProviderSummary(key: key, displayName: p.displayName, colorHex: p.brandColorHex,
                                       cost: value.0, tokens: value.1, count: value.2)
            }
            if let cp = customById[key] {
                return ProviderSummary(key: key, displayName: cp.name, colorHex: cp.colorHex,
                                       cost: value.0, tokens: value.1, count: value.2)
            }
            // 既不是内置也不是自定义（可能是历史遗留），用 unknown 兜底
            return ProviderSummary(key: key, displayName: key, colorHex: Provider.unknown.brandColorHex,
                                   cost: value.0, tokens: value.1, count: value.2)
        }
        .sorted { $0.cost > $1.cost }
    }

    private let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    // MARK: - Quotas

    private struct QuotaCardItem {
        let snapshot: QuotaSnapshot
        let accent: Color
    }

    private var quotaCards: [QuotaCardItem] {
        // 保持稳定顺序：Claude 在前，Codex 在后，其他 probe 排在末尾。
        let order = ["claude", "codex"]
        let snaps = appState.quotaSnapshots
        var items: [QuotaCardItem] = []
        for id in order {
            if let snap = snaps[id] {
                items.append(QuotaCardItem(snapshot: snap, accent: accent(for: id)))
            }
        }
        for (id, snap) in snaps where !order.contains(id) {
            items.append(QuotaCardItem(snapshot: snap, accent: accent(for: id)))
        }
        return items
    }

    private var quotaColumns: [GridItem] {
        let n = max(1, min(quotaCards.count, 2))
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: n)
    }

    private func accent(for probeID: String) -> Color {
        switch probeID {
        case "claude": return Color(hex: Provider.anthropic.brandColorHex)
        case "codex":  return Color(hex: Provider.openai.brandColorHex)
        default:       return .accentColor
        }
    }

    /// 把额度探针 id 映射到 UsageRecord.provider 字段，用于按 Plan 聚合真实用量。
    /// 未识别的 probe 返回 nil，对应卡片只显示零值。
    private func providerKey(forProbeID probeID: String) -> String? {
        switch probeID {
        case "claude": return Provider.anthropic.rawValue
        case "codex":  return Provider.openai.rawValue
        default:       return nil
        }
    }

    /// 计算某个 Plan（按 probe id 区分）在今日 / 近 7 天 / 近 30 天的用量。
    /// 时间窗口以「日历自然日」为基准：今日=startOfDay(now)，
    /// 近 7 天 = startOfDay(now) - 6 天起到现在，近 30 天同理 - 29 天。
    private func planUsage(for probeID: String) -> PlanUsageStats {
        guard let key = providerKey(forProbeID: probeID) else { return .zero }
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let week  = cal.date(byAdding: .day, value: -6,  to: startOfToday) ?? startOfToday
        let month = cal.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday

        var todayCost = 0.0, todayTokens = 0
        var weekCost  = 0.0, weekTokens  = 0
        var monthCost = 0.0, monthTokens = 0
        for r in records where r.provider == key {
            if r.timestamp < month { continue }
            monthCost += r.costUSD
            monthTokens += r.totalTokens
            if r.timestamp >= week {
                weekCost += r.costUSD
                weekTokens += r.totalTokens
            }
            if r.timestamp >= startOfToday {
                todayCost += r.costUSD
                todayTokens += r.totalTokens
            }
        }
        return PlanUsageStats(
            todayCostUSD: todayCost, todayTokens: todayTokens,
            weekCostUSD: weekCost, weekTokens: weekTokens,
            monthCostUSD: monthCost, monthTokens: monthTokens
        )
    }
}

struct RecordRow: View {
    let record: UsageRecord
    let currency: Currency
    let rate: Double
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(record.sourceApp) · \(record.model)").font(.callout)
                Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatting.format(usd: record.costUSD, currency: currency, usdCnyRate: rate))
                    .font(.callout.weight(.medium)).monospacedDigit()
                Text(L10n.tr("dashboard.recordrow.io.fmt", record.inputTokens.formatted(), record.outputTokens.formatted()))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

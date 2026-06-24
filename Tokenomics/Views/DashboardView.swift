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
        // 一次遍历计算所有聚合（today / week / month / total / trend / byProvider / planUsage）。
        // 相比原来 6+ 个 computed property 各自 O(N) filter + reduce，这里只扫一遍 records。
        let agg = computeAggregates()
        let summaries = providerSummaries(from: agg)
        return ScrollView {
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
                                    usage: planUsage(for: item.snapshot.id, agg: agg),
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
                    CostCard(title: L10n.tr("dashboard.cost.today"), costUSD: agg.todayCost,
                             totalTokens: agg.todayTokens,
                             currency: appState.currency, rate: appState.usdCnyRate,
                             accent: .blue)
                    CostCard(title: L10n.tr("dashboard.cost.week"), costUSD: agg.weekCost,
                             totalTokens: agg.weekTokens,
                             currency: appState.currency, rate: appState.usdCnyRate,
                             accent: .green)
                    CostCard(title: L10n.tr("dashboard.cost.month"), costUSD: agg.monthCost,
                             totalTokens: agg.monthTokens,
                             currency: appState.currency, rate: appState.usdCnyRate,
                             accent: .orange)
                    CostCard(title: L10n.tr("dashboard.cost.total"), costUSD: agg.totalCost,
                             totalTokens: agg.totalTokens,
                             currency: appState.currency, rate: appState.usdCnyRate,
                             accent: .pink)
                }

                section(L10n.tr("dashboard.section.trend")) {
                    UsageTrendChart(
                        data: agg.trend,
                        rate: appState.usdCnyRate,
                        currency: appState.currency
                    )
                }

                section(L10n.tr("dashboard.section.by_provider")) {
                    VStack(spacing: 0) {
                        ForEach(summaries, id: \.key) { item in
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
                        if summaries.isEmpty {
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

    /// 一次遍历 records 同时填好 today / week (ISO weekOfYear) / month / total 的
    /// cost 与 tokens，以及 (day × providerKey) 趋势桶、按 providerKey 的月度统计。
    /// 所有时间窗口在循环外预先解析，循环里只做比较。
    /// 相比原来 6+ 个 computed property 各自 O(N) filter + reduce，这里仅扫一遍 records。
    private struct Aggregates {
        var todayCost: Double = 0
        var todayTokens: Int = 0
        var weekCost: Double = 0
        var weekTokens: Int = 0
        var monthCost: Double = 0
        var monthTokens: Int = 0
        var totalCost: Double = 0
        var totalTokens: Int = 0
        /// 趋势图（近 14 天）按 day × provider 聚合的 cost。
        var trend: [DailyCost] = []
        /// 按 providerKey 的"近 30 天日历窗"统计：cost / tokens / record count。
        var monthByProvider: [String: (cost: Double, tokens: Int, count: Int)] = [:]
        /// 各 provider 在 today / lastWeek(滚动 7 天) / lastMonth(滚动 30 天) 的 cost & tokens。
        var planByProvider: [String: PlanUsageStats] = [:]
    }

    private func computeAggregates() -> Aggregates {
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
        let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? startOfToday
        let trendCutoff = cal.date(byAdding: .day, value: -13, to: startOfToday) ?? startOfToday
        // planUsage 用"滚动窗口"语义：近 7/30 天，与上面 ISO 周 / 自然月不冲突。
        let last7Start = cal.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let last30Start = cal.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday

        var agg = Aggregates()
        // (dayEpoch, providerKey) -> cost
        var trendBuckets: [String: Double] = [:]
        // providerKey -> (todayCost, todayTokens, weekCost, weekTokens, monthCost, monthTokens)
        var planBuckets: [String: (Double, Int, Double, Int, Double, Int)] = [:]

        for r in records {
            let ts = r.timestamp
            let cost = r.costUSD
            let tokens = r.totalTokens
            agg.totalCost += cost
            agg.totalTokens += tokens

            if ts >= startOfToday {
                agg.todayCost += cost
                agg.todayTokens += tokens
            }
            if ts >= weekStart {
                agg.weekCost += cost
                agg.weekTokens += tokens
            }
            if ts >= monthStart {
                agg.monthCost += cost
                agg.monthTokens += tokens
                var cur = agg.monthByProvider[r.provider] ?? (0, 0, 0)
                cur.cost += cost
                cur.tokens += tokens
                cur.count += 1
                agg.monthByProvider[r.provider] = cur
            }
            if ts >= trendCutoff {
                let dayStart = cal.startOfDay(for: ts)
                let key = "\(dayStart.timeIntervalSince1970)|\(r.provider)"
                trendBuckets[key, default: 0] += cost
            }
            if ts >= last30Start {
                var cur = planBuckets[r.provider] ?? (0, 0, 0, 0, 0, 0)
                cur.4 += cost; cur.5 += tokens
                if ts >= last7Start {
                    cur.2 += cost; cur.3 += tokens
                }
                if ts >= startOfToday {
                    cur.0 += cost; cur.1 += tokens
                }
                planBuckets[r.provider] = cur
            }
        }

        agg.trend = trendBuckets.map { k, v -> DailyCost in
            let parts = k.split(separator: "|")
            let ts = TimeInterval(parts[0]) ?? 0
            let providerKey = String(parts[1])
            let providerName = Provider(rawValue: providerKey)?.displayName ?? providerKey
            return DailyCost(day: Date(timeIntervalSince1970: ts),
                             provider: providerName,
                             costUSD: v)
        }.sorted { $0.day < $1.day }

        agg.planByProvider = planBuckets.mapValues { v in
            PlanUsageStats(
                todayCostUSD: v.0, todayTokens: v.1,
                weekCostUSD: v.2, weekTokens: v.3,
                monthCostUSD: v.4, monthTokens: v.5
            )
        }
        return agg
    }

    private func providerSummaries(from agg: Aggregates) -> [ProviderSummary] {
        let customById = Dictionary(uniqueKeysWithValues: appState.customProviders.map { ($0.id, $0) })
        return agg.monthByProvider.compactMap { key, value -> ProviderSummary? in
            if appState.isProviderHidden(key) { return nil }
            if let p = Provider(rawValue: key), p != .unknown {
                return ProviderSummary(key: key, displayName: p.displayName, colorHex: p.brandColorHex,
                                       cost: value.cost, tokens: value.tokens, count: value.count)
            }
            if let cp = customById[key] {
                return ProviderSummary(key: key, displayName: cp.name, colorHex: cp.colorHex,
                                       cost: value.cost, tokens: value.tokens, count: value.count)
            }
            return ProviderSummary(key: key, displayName: key, colorHex: Provider.unknown.brandColorHex,
                                   cost: value.cost, tokens: value.tokens, count: value.count)
        }
        .sorted { $0.cost > $1.cost }
    }

    private struct ProviderSummary {
        let key: String        // Provider.rawValue 或 CustomProvider.id
        let displayName: String
        let colorHex: String
        let cost: Double
        let tokens: Int
        let count: Int
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
    /// 不再单独扫一遍 records；直接从 computeAggregates() 已经填好的 planByProvider 取桶。
    private func planUsage(for probeID: String, agg: Aggregates) -> PlanUsageStats {
        guard let key = providerKey(forProbeID: probeID) else { return .zero }
        return agg.planByProvider[key] ?? .zero
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

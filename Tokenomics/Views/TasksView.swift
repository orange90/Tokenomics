import SwiftUI
import Charts

/// 「任务详情」标签页。
///
/// 与 ClaudeCodeCollector 共用同一数据源：~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl。
/// 每个 jsonl 文件 = 一个 Claude Code 会话（任务），文件名即 sessionId，
/// 所在目录名经反编码后即任务运行所在的项目路径（cwd）。
///
/// 设计目标：直接读 jsonl（而非 SwiftData 里的 UsageRecord），
/// 因为 UsageRecord 目前没有 sessionId / cwd 字段，无法在 App 层做"按任务"聚合。
/// 这样可以在「不改动现有数据模型与采集流水线」的前提下，复用项目里现成的
/// 模型 normalize 与 PricingService 计价能力，给出任务粒度的 token / 费用视图。
struct TasksView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var localization: LocalizationManager

    @State private var sessions: [TaskSession] = []
    @State private var projects: [String] = []
    @State private var selectedProject: String = ""   // "" 表示全部
    @State private var selectedProvider: ProviderFilter = .all
    @State private var selectedSessionID: String?
    @State private var isLoading: Bool = false
    @State private var sortMode: SortMode = .cost
    @State private var lastError: String?

    enum SortMode: String, CaseIterable, Identifiable {
        case cost, tokens, recent
        var id: String { rawValue }
        var labelKey: String {
            switch self {
            case .cost:   return "tasks.sort.cost"
            case .tokens: return "tasks.sort.tokens"
            case .recent: return "tasks.sort.recent"
            }
        }
    }

    enum ProviderFilter: String, CaseIterable, Identifiable {
        case all, anthropic, openai
        var id: String { rawValue }
        var labelKey: String {
            switch self {
            case .all:       return "tasks.filter.all_providers"
            case .anthropic: return "provider.anthropic"
            case .openai:    return "provider.openai"
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let oneThird = max(320, geo.size.width / 3)
            HSplitView {
                leftPane
                    .frame(minWidth: 320, idealWidth: oneThird)
                rightPane
                    .frame(minWidth: 420)
            }
        }
        .id(localization.language.rawValue)
        .task {
            await reload()
        }
    }

    // MARK: - Left pane (list)

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if isLoading && sessions.isEmpty {
                ProgressView().padding()
                Spacer()
            } else if filteredSessions.isEmpty {
                emptyState
                Spacer()
            } else {
                List(selection: $selectedSessionID) {
                    ForEach(filteredSessions) { s in
                        sessionRow(s)
                            .tag(s.id as String?)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("tasks.title")).font(.title2.bold())
                Spacer()
                Button {
                    Task { await reload(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(L10n.tr("tasks.reload"))
                .disabled(isLoading)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    providerPicker.frame(minWidth: 130)
                    projectPicker.frame(minWidth: 110, maxWidth: .infinity)
                    sortPicker.frame(minWidth: 130)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        providerPicker.frame(maxWidth: .infinity)
                        sortPicker.frame(maxWidth: .infinity)
                    }
                    projectPicker.frame(maxWidth: .infinity)
                }
            }
            Text(L10n.tr("tasks.subtitle.fmt", filteredSessions.count, sessions.count))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let err = lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(12)
    }

    private var providerPicker: some View {
        Picker(L10n.tr("tasks.filter.provider"), selection: $selectedProvider) {
            ForEach(ProviderFilter.allCases) { p in
                Text(L10n.tr(p.labelKey)).tag(p)
            }
        }
        .pickerStyle(.menu)
    }

    private var projectPicker: some View {
        Picker(L10n.tr("tasks.filter.project"), selection: $selectedProject) {
            Text(L10n.tr("tasks.filter.all_projects")).tag("")
            ForEach(visibleProjects, id: \.self) { p in
                Text(prettyProjectName(p)).tag(p)
            }
        }
        .pickerStyle(.menu)
    }

    private var sortPicker: some View {
        Picker(L10n.tr("tasks.sort"), selection: $sortMode) {
            ForEach(SortMode.allCases) { m in
                Text(L10n.tr(m.labelKey)).tag(m)
            }
        }
        .pickerStyle(.menu)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            L10n.tr("tasks.empty.title"),
            systemImage: "tray",
            description: Text(L10n.tr("tasks.empty.desc"))
        )
        .padding()
    }

    private func sessionRow(_ s: TaskSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                providerBadge(s.provider)
                Text(s.shortID).font(.body.monospaced())
                Spacer()
                Text(CurrencyFormatting.format(usd: s.totalCostUSD,
                                               currency: appState.currency,
                                               usdCnyRate: appState.usdCnyRate))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }
            Text(prettyProjectName(s.projectDir))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 10) {
                Label(s.totalTokens.formatted(), systemImage: "number")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let last = s.lastTimestamp {
                    Label(Self.relative.localizedString(for: last, relativeTo: Date()),
                          systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if s.messageCount > 0 {
                    Label("\(s.messageCount)", systemImage: "bubble.left.and.bubble.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Right pane (detail)

    private var rightPane: some View {
        Group {
            if let sid = selectedSessionID,
               let s = sessions.first(where: { $0.id == sid }) {
                TaskDetailPane(
                    session: s,
                    projectSiblings: projectSiblings(for: s),
                    providerSiblings: providerSiblings(for: s),
                    snapshot: appState.quotaSnapshots[snapshotKey(for: s.provider)]
                )
                    .environmentObject(appState)
                    .environmentObject(localization)
            } else {
                ContentUnavailableView(
                    L10n.tr("tasks.detail.empty.title"),
                    systemImage: "sidebar.right",
                    description: Text(L10n.tr("tasks.detail.empty.desc"))
                )
            }
        }
    }

    /// AppState.quotaSnapshots 用的是 probe.id（"claude" / "codex"），
    /// 这里把 Provider 反查回去。.unknown 时返回空串，外层会拿到 nil snapshot。
    private func snapshotKey(for p: Provider) -> String {
        switch p {
        case .anthropic: return "claude"
        case .openai:    return "codex"
        case .unknown:   return ""
        }
    }

    /// 与选中任务属于同一项目（projectDir）+ 同一 provider 的所有会话，
    /// 用于绘制右侧那张「每次运行的额度使用图」。
    private func projectSiblings(for s: TaskSession) -> [TaskSession] {
        sessions.filter { $0.provider == s.provider && $0.projectDir == s.projectDir }
    }

    /// 与选中任务属于同一 provider 的所有会话，用于计算"窗口内总用量"分母。
    /// 注意：5h/weekly 限额是按账号算，不是按项目算，所以分母必须跨项目。
    private func providerSiblings(for s: TaskSession) -> [TaskSession] {
        sessions.filter { $0.provider == s.provider }
    }

    // MARK: - Derived

    private var filteredSessions: [TaskSession] {
        var base = sessions
        switch selectedProvider {
        case .all:       break
        case .anthropic: base = base.filter { $0.provider == .anthropic }
        case .openai:    base = base.filter { $0.provider == .openai }
        }
        if !selectedProject.isEmpty {
            base = base.filter { $0.projectDir == selectedProject }
        }
        switch sortMode {
        case .cost:
            return base.sorted { $0.totalCostUSD > $1.totalCostUSD }
        case .tokens:
            return base.sorted { $0.totalTokens > $1.totalTokens }
        case .recent:
            return base.sorted {
                ($0.lastTimestamp ?? .distantPast) > ($1.lastTimestamp ?? .distantPast)
            }
        }
    }

    /// 项目下拉只展示当前 provider 过滤后还存在的项目，避免出现"选了空"的死状态。
    private var visibleProjects: [String] {
        let pool: [TaskSession]
        switch selectedProvider {
        case .all:       pool = sessions
        case .anthropic: pool = sessions.filter { $0.provider == .anthropic }
        case .openai:    pool = sessions.filter { $0.provider == .openai }
        }
        return Array(Set(pool.map { $0.projectDir })).sorted()
    }

    @ViewBuilder
    private func providerBadge(_ p: Provider) -> some View {
        let color = Color(hex: p.brandColorHex)
        Text(providerShortLabel(p))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.45)))
            )
            .foregroundStyle(color)
    }

    private func providerShortLabel(_ p: Provider) -> String {
        switch p {
        case .anthropic: return "Claude"
        case .openai:    return "Codex"
        case .unknown:   return "—"
        }
    }

    // MARK: - Loading

    private func reload(force: Bool = false) async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        let pricing = appState.pricingService
        let result: (sessions: [TaskSession], projects: [String], error: String?)
        result = await Task.detached(priority: .userInitiated) {
            TasksScanner.scanAll(pricing: pricing)
        }.value
        self.sessions = result.sessions
        self.projects = result.projects
        self.lastError = result.error
        if let sid = selectedSessionID, sessions.contains(where: { $0.id == sid }) == false {
            selectedSessionID = nil
        }
        if selectedSessionID == nil {
            selectedSessionID = filteredSessions.first?.id
        }
    }

    // MARK: - Helpers

    /// Claude Code 把 cwd 编码成目录名时把 `/` 替成 `-`，例如
    /// `-Users-huangzhe-Documents-Tokenomics` 对应 `/Users/huangzhe/Documents/Tokenomics`。
    /// 我们没法 100% 还原（因为路径里本来就可能有 `-`），但展示用「basename」已经够直观。
    /// 对 Codex 这条路径，projectDir 本身就是 cwd basename，不会以 `-` 开头，直接返回即可。
    private func prettyProjectName(_ raw: String) -> String {
        if !raw.hasPrefix("-") { return raw }
        let parts = raw.split(separator: "-").map(String.init).filter { !$0.isEmpty }
        return parts.last ?? raw
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

// MARK: - Detail pane

private struct TaskDetailPane: View {
    let session: TaskSession
    /// 同项目 + 同 provider 的兄弟任务，用于右侧时间-占比折线图。
    let projectSiblings: [TaskSession]
    /// 同 provider 的兄弟任务，用于计算 5h/weekly 窗口内的"总用量"分母。
    let providerSiblings: [TaskSession]
    /// 当前 provider 的最新额度快照（从 AppState 直接传入）。
    let snapshot: QuotaSnapshot?
    @EnvironmentObject private var appState: AppState

    @State private var chartMetric: ProjectTimelineMetric = .totalCost
    @State private var chartRange: ProjectTimelineRange = .all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                titleBlock
                statsGrid
                quotaShareBlock
                projectTimelineChart
                modelBreakdown
                turnBreakdown
                if !session.cwd.isEmpty {
                    metaBlock
                }
            }
            .padding(20)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.shortID)
                .font(.title.bold())
                .textSelection(.enabled)
            Text(session.id)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var statsGrid: some View {
        let columns = [
            GridItem(.flexible()), GridItem(.flexible()),
            GridItem(.flexible()), GridItem(.flexible())
        ]
        return LazyVGrid(columns: columns, spacing: 12) {
            statCard(L10n.tr("tasks.stat.cost"),
                     value: CurrencyFormatting.format(usd: session.totalCostUSD,
                                                     currency: appState.currency,
                                                     usdCnyRate: appState.usdCnyRate),
                     accent: .pink)
            statCard(L10n.tr("tasks.stat.tokens"),
                     value: session.totalTokens.formatted(),
                     accent: .blue)
            statCard(L10n.tr("tasks.stat.messages"),
                     value: session.messageCount.formatted(),
                     accent: .orange)
            statCard(L10n.tr("tasks.stat.duration"),
                     value: session.durationDescription,
                     accent: .green)
        }
    }

    private func statCard(_ title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(0.30)))
        )
    }

    // MARK: - Quota share

    /// 「本次任务占 5h / weekly 限额的多少」。
    ///
    /// 思路：Anthropic / OpenAI 的额度接口只回 utilization%，不回绝对 token 上限。
    /// 但我们能拿到「同 provider 这个窗口里跑过的所有任务的总 token 数」，
    /// 用 utilization% 反推每 token 占额度的比例，再乘上本次任务的 token 数，
    /// 就能得到「本次任务占 N% 的 5h / weekly 限额」。
    /// 没有快照、或者本次任务不在当前窗口里时，统一显示 "—"。
    private var quotaShareBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("tasks.quota_share.title")).font(.headline)
            Text(L10n.tr("tasks.quota_share.hint"))
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                quotaShareCard(
                    title: L10n.tr("tasks.quota_share.five_hour"),
                    window: fiveHourWindow,
                    accent: .purple
                )
                quotaShareCard(
                    title: L10n.tr("tasks.quota_share.weekly"),
                    window: weeklyWindow,
                    accent: .teal
                )
            }
        }
    }

    private func quotaShareCard(title: String, window: QuotaWindow?, accent: Color) -> some View {
        let share = window.flatMap { self.share(in: $0, for: session) }
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(share.map { Self.percentFmt($0) } ?? "—")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                if share != nil {
                    Text(L10n.tr("tasks.quota_share.of_limit"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let w = window {
                Text(L10n.tr("tasks.quota_share.window_used.fmt", Self.percentFmt(w.usedPercent)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.tr("tasks.quota_share.no_snapshot"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(0.30)))
        )
    }

    private var fiveHourWindow: QuotaWindow? {
        snapshot?.windows.first { $0.id == "five_hour" }
    }

    /// 优先匹配总周窗口（没有 note 的 seven_day），其次任何 seven_day 前缀的窗口。
    /// Claude 同时返回 seven_day / seven_day_sonnet / seven_day_opus，前两者题图更直观。
    private var weeklyWindow: QuotaWindow? {
        if let w = snapshot?.windows.first(where: { $0.id == "seven_day" }) { return w }
        return snapshot?.windows.first { $0.id.hasPrefix("seven_day") }
    }

    /// 给定窗口（5h / weekly）和某个 session，返回该 session 占该窗口限额的百分比。
    /// 当 session 的 lastTimestamp 不落在窗口内、或窗口内总 token 为 0、或没有 resetsAt 时，返回 nil。
    fileprivate func share(in window: QuotaWindow, for s: TaskSession) -> Double? {
        guard let resets = window.resetsAt else { return nil }
        let duration: TimeInterval = window.id == "five_hour" ? 5 * 3600 : 7 * 86400
        let start = resets.addingTimeInterval(-duration)
        guard let ts = s.lastTimestamp, ts >= start, ts <= resets else { return nil }
        let inWindow = providerSiblings.filter {
            guard let t = $0.lastTimestamp else { return false }
            return t >= start && t <= resets
        }
        let totalTokens = inWindow.reduce(0) { $0 + $1.totalTokens }
        guard totalTokens > 0, s.totalTokens > 0 else { return nil }
        let ratio = Double(s.totalTokens) / Double(totalTokens)
        return ratio * window.usedPercent
    }

    // MARK: - Per-project timeline chart

    /// 「这个项目每次任务的用量时间轴」。
    /// x 轴 = 任务结束时间；y 轴 = 用户可在五个维度间切换（输入/输出/缓存命中/缓存创建/费用）。
    /// 数据源是 projectSiblings —— 当前项目 + 当前 provider 的所有任务。
    /// 不依赖 5h 窗口和额度快照，因此 Claude/Codex 没拉过额度也能用。
    private var projectTimelineChart: some View {
        let points = timelinePoints
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.tr("tasks.project_timeline.title")).font(.headline)
                Spacer()
                Picker("", selection: $chartRange) {
                    ForEach(ProjectTimelineRange.allCases) { r in
                        Text(L10n.tr(r.labelKey)).tag(r)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 130)
                Picker("", selection: $chartMetric) {
                    ForEach(ProjectTimelineMetric.allCases) { m in
                        Text(L10n.tr(m.labelKey)).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)
            }
            Text(L10n.tr("tasks.project_timeline.hint"))
                .font(.caption).foregroundStyle(.secondary)
            if points.isEmpty {
                Text(L10n.tr("tasks.project_timeline.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                Chart(points) { p in
                    LineMark(
                        x: .value(L10n.tr("tasks.project_timeline.x"), p.time),
                        y: .value(L10n.tr(chartMetric.labelKey), p.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(chartMetric.accent)
                    PointMark(
                        x: .value(L10n.tr("tasks.project_timeline.x"), p.time),
                        y: .value(L10n.tr(chartMetric.labelKey), p.value)
                    )
                    .foregroundStyle(p.isCurrent ? Color.pink : chartMetric.accent)
                    .symbolSize(p.isCurrent ? 140 : 50)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = value.as(Double.self) {
                                Text(yAxisLabel(d))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month().day().hour().minute())
                    }
                }
                .frame(minHeight: 220)
                Text(L10n.tr("tasks.project_timeline.count.fmt", points.count))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        )
    }

    /// 把同项目的会话按时间排序，并把当前选中的纵轴维度抽出来，方便 Charts 渲染。
    /// 同时按 chartRange 做截断：「过去 N 天」一律以"现在"为参考点而不是任务区间右端，
    /// 避免出现"选过去一天但显示三天前那批"的反直觉行为。
    private var timelinePoints: [TimelinePoint] {
        let now = Date()
        let cutoff: Date? = chartRange.duration.map { now.addingTimeInterval(-$0) }
        return projectSiblings.compactMap { s -> TimelinePoint? in
            guard let ts = s.lastTimestamp else { return nil }
            if let c = cutoff, ts < c { return nil }
            return TimelinePoint(
                id: s.id,
                time: ts,
                value: chartMetric.value(from: s),
                isCurrent: s.id == session.id
            )
        }.sorted { $0.time < $1.time }
    }

    fileprivate struct TimelinePoint: Identifiable {
        let id: String
        let time: Date
        let value: Double
        let isCurrent: Bool
    }

    /// Y 轴 tick 的展示。cost 走货币格式化；token 维度做 K/M 缩写。
    private func yAxisLabel(_ v: Double) -> String {
        switch chartMetric {
        case .totalCost:
            return CurrencyFormatting.format(usd: v, currency: appState.currency, usdCnyRate: appState.usdCnyRate)
        case .input, .output, .cacheRead, .cacheCreation:
            return Self.tokensShort(v)
        }
    }

    private static func tokensShort(_ v: Double) -> String {
        switch v {
        case 1_000_000...: return String(format: "%.1fM", v / 1_000_000)
        case 1_000...:     return String(format: "%.1fK", v / 1_000)
        default:           return String(format: "%.0f", v)
        }
    }

    private static func percentFmt(_ v: Double) -> String {
        if v >= 10 { return String(format: "%.0f%%", v) }
        if v >= 1  { return String(format: "%.1f%%", v) }
        return String(format: "%.2f%%", v)
    }

    private var modelBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("tasks.by_model")).font(.headline)
            VStack(spacing: 0) {
                HStack {
                    Text(L10n.tr("tasks.col.model")).font(.caption.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(L10n.tr("tasks.col.input")).font(.caption.bold())
                        .frame(width: 90, alignment: .trailing)
                    Text(L10n.tr("tasks.col.output")).font(.caption.bold())
                        .frame(width: 90, alignment: .trailing)
                    Text(L10n.tr("tasks.col.cache_w")).font(.caption.bold())
                        .frame(width: 90, alignment: .trailing)
                    Text(L10n.tr("tasks.col.cache_r")).font(.caption.bold())
                        .frame(width: 100, alignment: .trailing)
                    Text(L10n.tr("tasks.col.cost")).font(.caption.bold())
                        .frame(width: 140, alignment: .trailing)
                }
                .padding(.vertical, 6)
                Divider()
                ForEach(session.modelRows) { row in
                    HStack {
                        Text(row.model).font(.body.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.input.formatted())
                            .frame(width: 90, alignment: .trailing)
                            .monospacedDigit().foregroundStyle(.secondary)
                        Text(row.output.formatted())
                            .frame(width: 90, alignment: .trailing)
                            .monospacedDigit().foregroundStyle(.secondary)
                        Text(row.cacheCreation.formatted())
                            .frame(width: 90, alignment: .trailing)
                            .monospacedDigit().foregroundStyle(.secondary)
                        Text(row.cacheRead.formatted())
                            .frame(width: 100, alignment: .trailing)
                            .monospacedDigit().foregroundStyle(.secondary)
                        Text(CurrencyFormatting.format(usd: row.cost,
                                                       currency: appState.currency,
                                                       usdCnyRate: appState.usdCnyRate))
                            .frame(width: 140, alignment: .trailing)
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

    private var turnBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("tasks.by_turn")).font(.headline)
            Text(L10n.tr("tasks.by_turn.hint")).font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(session.turns) { turn in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(turn.preview)
                                .font(.body)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 8) {
                                if let ts = turn.timestamp {
                                    Text(Self.timeFmt.string(from: ts))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(L10n.tr("tasks.turn.tokens.fmt", turn.totalTokens.formatted()))
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(L10n.tr("tasks.turn.replies.fmt", turn.assistantCount))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Text(CurrencyFormatting.format(usd: turn.cost,
                                                       currency: appState.currency,
                                                       usdCnyRate: appState.usdCnyRate))
                            .frame(width: 160, alignment: .trailing)
                            .monospacedDigit().font(.callout.weight(.medium))
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
                if session.turns.isEmpty {
                    Text(L10n.tr("tasks.by_turn.empty"))
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator)))
        }
    }

    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.tr("tasks.meta")).font(.headline)
            metaRow(L10n.tr("tasks.meta.cwd"), session.cwd)
            if let branch = session.gitBranch, !branch.isEmpty {
                metaRow(L10n.tr("tasks.meta.branch"), branch)
            }
            metaRow(L10n.tr("tasks.meta.file"), session.fileURL.path)
            if let first = session.firstTimestamp {
                metaRow(L10n.tr("tasks.meta.first"), Self.fullFmt.string(from: first))
            }
            if let last = session.lastTimestamp {
                metaRow(L10n.tr("tasks.meta.last"), Self.fullFmt.string(from: last))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator)))
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value).font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let fullFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}

// MARK: - Model

/// 「项目任务时间轴图」的时间范围筛选。`duration` 为 nil 时表示「全部」，
/// 其余四个选项以"现在"往前推 N 天作为截断点。
enum ProjectTimelineRange: String, CaseIterable, Identifiable {
    case day1
    case day3
    case day7
    case day30
    case all

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .day1:  return "tasks.project_timeline.range.day1"
        case .day3:  return "tasks.project_timeline.range.day3"
        case .day7:  return "tasks.project_timeline.range.day7"
        case .day30: return "tasks.project_timeline.range.day30"
        case .all:   return "tasks.project_timeline.range.all"
        }
    }

    /// 截断长度（秒）。nil = 不截断，画全部历史。
    var duration: TimeInterval? {
        switch self {
        case .day1:  return 1 * 86_400
        case .day3:  return 3 * 86_400
        case .day7:  return 7 * 86_400
        case .day30: return 30 * 86_400
        case .all:   return nil
        }
    }
}

/// 「项目任务时间轴图」纵轴可选维度。用户在 Picker 里切换，X 轴始终是时间。
/// raw value 留空因为枚举里没有跨进程持久化需求，全部走 .rawValue / labelKey 拼装。
enum ProjectTimelineMetric: String, CaseIterable, Identifiable {
    case input
    case output
    case cacheRead
    case cacheCreation
    case totalCost

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .input:         return "tasks.project_timeline.metric.input"
        case .output:        return "tasks.project_timeline.metric.output"
        case .cacheRead:     return "tasks.project_timeline.metric.cache_read"
        case .cacheCreation: return "tasks.project_timeline.metric.cache_creation"
        case .totalCost:     return "tasks.project_timeline.metric.cost"
        }
    }

    /// 折线 / 散点的着色，五个维度各自一个色调以便用户切换时一眼分辨。
    var accent: Color {
        switch self {
        case .input:         return .blue
        case .output:        return .green
        case .cacheRead:     return .teal
        case .cacheCreation: return .indigo
        case .totalCost:     return .pink
        }
    }

    /// 从一个 TaskSession 里取出该维度的数值。token 类用 Double 是为了和 cost 共用 Y 轴类型。
    func value(from s: TaskSession) -> Double {
        switch self {
        case .input:         return Double(s.inputTokens)
        case .output:        return Double(s.outputTokens)
        case .cacheRead:     return Double(s.cacheReadTokens)
        case .cacheCreation: return Double(s.cacheCreationTokens)
        case .totalCost:     return s.totalCostUSD
        }
    }
}

struct TaskSession: Identifiable, Equatable {
    let id: String                 // sessionId
    let provider: Provider         // 来源 provider（Anthropic / OpenAI）
    let fileURL: URL
    let projectDir: String         // 编码后的目录名（Claude）或 cwd basename（Codex），用于左侧分组
    let cwd: String                // jsonl 行里的 cwd（原始绝对路径）
    let gitBranch: String?
    let firstTimestamp: Date?
    let lastTimestamp: Date?
    let messageCount: Int          // assistant 消息条数（即对 LLM 的请求数）
    let totalCostUSD: Double
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let modelRows: [ModelRow]
    let turns: [TurnRow]

    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }

    var shortID: String {
        // 取 sessionId 前 8 位作为短标签
        String(id.prefix(8))
    }

    var durationDescription: String {
        guard let f = firstTimestamp, let l = lastTimestamp, l > f else { return "—" }
        let secs = Int(l.timeIntervalSince(f))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    static func == (lhs: TaskSession, rhs: TaskSession) -> Bool { lhs.id == rhs.id }

    struct ModelRow: Identifiable {
        var id: String { model }
        let model: String
        let input: Int
        let output: Int
        let cacheCreation: Int
        let cacheRead: Int
        let cost: Double
    }

    struct TurnRow: Identifiable {
        let id: String                 // user message uuid 或合成 key
        let preview: String            // 用户那一轮提问的文本片段
        let timestamp: Date?
        let assistantCount: Int
        let totalTokens: Int
        let cost: Double
    }
}

// MARK: - Scanner

/// 扫描两个本地来源，按 sessionId 聚合成 TaskSession：
///   - ~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl   （Claude Code）
///   - ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl         （Codex CLI / Desktop，"项目"取 cwd 的 basename）
enum TasksScanner {
    static func scanAll(pricing: PricingService) -> (sessions: [TaskSession], projects: [String], error: String?) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var sessions: [TaskSession] = []
        var projects = Set<String>()
        var errors: [String] = []

        // 1) Claude Code
        let claudeRoot = home.appendingPathComponent(".claude/projects", isDirectory: true)
        if FileManager.default.fileExists(atPath: claudeRoot.path) {
            let projectDirs = (try? FileManager.default.contentsOfDirectory(at: claudeRoot, includingPropertiesForKeys: nil)) ?? []
            for dir in projectDirs {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let project = dir.lastPathComponent
                let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
                for f in files where f.pathExtension.lowercased() == "jsonl" {
                    if let s = parseSession(file: f, projectDir: project, pricing: pricing) {
                        sessions.append(s)
                        projects.insert(project)
                    }
                }
            }
        } else {
            errors.append("~/.claude/projects not found")
        }

        // 2) Codex CLI / Desktop（按项目=cwd basename 聚合）
        let codexRoot = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        if FileManager.default.fileExists(atPath: codexRoot.path) {
            if let enumerator = FileManager.default.enumerator(
                at: codexRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let url as URL in enumerator where url.pathExtension.lowercased() == "jsonl" {
                    if let s = parseCodexSession(file: url, pricing: pricing) {
                        sessions.append(s)
                        projects.insert(s.projectDir)
                    }
                }
            }
        } else {
            errors.append("~/.codex/sessions not found")
        }

        // 两个目录都不存在才视为错误，单边缺失只是隐藏对应来源。
        let err: String? = (sessions.isEmpty && !errors.isEmpty) ? errors.joined(separator: "; ") : nil
        return (sessions, projects.sorted(), err)
    }

    private static func parseSession(file: URL, projectDir: String, pricing: PricingService) -> TaskSession? {
        guard let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8) else { return nil }

        var sessionID: String = file.deletingPathExtension().lastPathComponent
        var cwd: String = ""
        var branch: String? = nil
        var first: Date? = nil
        var last: Date? = nil

        // 按模型聚合
        var perModel: [String: (Int, Int, Int, Int, Double)] = [:]
        var assistantCount = 0

        // 轮次聚合：每次遇到 user message 起一个新轮，期间收集所有 assistant usage。
        struct TurnAcc {
            var id: String
            var preview: String
            var timestamp: Date?
            var assistantCount: Int = 0
            var tokens: Int = 0
            var cost: Double = 0
        }
        var turns: [TurnAcc] = []
        // sidechain（subagent）也是带有 user 消息的，会让真实"主线轮次"被打断。
        // 这里把 sidechain 上的开销都算到当前主线 turn 里，避免被切碎。
        var currentMainTurn: Int? = nil

        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            if let sid = obj["sessionId"] as? String, !sid.isEmpty { sessionID = sid }
            if cwd.isEmpty, let c = obj["cwd"] as? String { cwd = c }
            if branch == nil, let b = obj["gitBranch"] as? String, !b.isEmpty { branch = b }

            let ts = parseTimestamp(obj["timestamp"])
            if let ts {
                if first == nil || ts < (first ?? .distantFuture) { first = ts }
                if last == nil  || ts > (last  ?? .distantPast)   { last = ts }
            }

            let type = obj["type"] as? String
            let isSidechain = (obj["isSidechain"] as? Bool) ?? false

            switch type {
            case "user":
                if !isSidechain {
                    let preview = extractUserPreview(obj)
                    let id = (obj["uuid"] as? String) ?? UUID().uuidString
                    turns.append(TurnAcc(id: id, preview: preview, timestamp: ts))
                    currentMainTurn = turns.count - 1
                }
            case "assistant":
                guard let message = obj["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else { continue }
                let model = (message["model"] as? String) ?? "unknown"
                let normalized = normalizeClaudeModel(model)

                let input = (usage["input_tokens"] as? Int) ?? 0
                let output = (usage["output_tokens"] as? Int) ?? 0
                let cw = (usage["cache_creation_input_tokens"] as? Int) ?? 0
                let cr = (usage["cache_read_input_tokens"] as? Int) ?? 0
                if input == 0 && output == 0 && cw == 0 && cr == 0 { continue }

                let cost = pricing.cost(
                    provider: Provider.anthropic.rawValue,
                    model: normalized,
                    input: input,
                    output: output,
                    cacheCreation: cw,
                    cacheRead: cr
                )
                assistantCount += 1
                var acc = perModel[normalized] ?? (0, 0, 0, 0, 0.0)
                acc.0 += input; acc.1 += output; acc.2 += cw; acc.3 += cr; acc.4 += cost
                perModel[normalized] = acc

                if let idx = currentMainTurn, idx < turns.count {
                    turns[idx].assistantCount += 1
                    turns[idx].tokens += input + output + cw + cr
                    turns[idx].cost += cost
                }
            default:
                break
            }
        }

        // 过滤掉完全没有 token 消耗的会话（纯队列日志或刚开就关掉的）
        let totalIn = perModel.values.reduce(0) { $0 + $1.0 }
        let totalOut = perModel.values.reduce(0) { $0 + $1.1 }
        let totalCW = perModel.values.reduce(0) { $0 + $1.2 }
        let totalCR = perModel.values.reduce(0) { $0 + $1.3 }
        let totalCost = perModel.values.reduce(0.0) { $0 + $1.4 }
        if totalIn == 0 && totalOut == 0 && totalCW == 0 && totalCR == 0 { return nil }

        let modelRows = perModel.map { (k, v) in
            TaskSession.ModelRow(model: k, input: v.0, output: v.1,
                                 cacheCreation: v.2, cacheRead: v.3, cost: v.4)
        }.sorted { $0.cost > $1.cost }

        let turnRows = turns.filter { $0.assistantCount > 0 || $0.tokens > 0 }
            .map { TaskSession.TurnRow(id: $0.id, preview: $0.preview,
                                       timestamp: $0.timestamp,
                                       assistantCount: $0.assistantCount,
                                       totalTokens: $0.tokens,
                                       cost: $0.cost) }

        return TaskSession(
            id: sessionID,
            provider: .anthropic,
            fileURL: file,
            projectDir: projectDir,
            cwd: cwd,
            gitBranch: branch,
            firstTimestamp: first,
            lastTimestamp: last,
            messageCount: assistantCount,
            totalCostUSD: totalCost,
            inputTokens: totalIn,
            outputTokens: totalOut,
            cacheCreationTokens: totalCW,
            cacheReadTokens: totalCR,
            modelRows: modelRows,
            turns: turnRows
        )
    }

    /// 与 ClaudeCodeCollector.normalizeClaudeModel 保持一致——直接复制而不是 expose，
    /// 是为了避免改动 Collector 的可见性。两边变更频率都很低，重复成本可接受。
    private static func normalizeClaudeModel(_ raw: String) -> String {
        let lower = raw.lowercased()
        let knownPrefixes = [
            "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6", "claude-opus-4-5", "claude-opus-4-1", "claude-opus-4",
            "claude-sonnet-4-8", "claude-sonnet-4-7", "claude-sonnet-4-6", "claude-sonnet-4-5", "claude-sonnet-4",
            "claude-haiku-4-8", "claude-haiku-4-7", "claude-haiku-4-6", "claude-haiku-4-5", "claude-haiku-4",
            "claude-fable-5", "claude-mythos-5", "claude-mythos-preview",
            "claude-3-7-sonnet", "claude-3-7-haiku",
            "claude-3-5-sonnet", "claude-3-5-haiku",
            "claude-3-opus", "claude-3-sonnet", "claude-3-haiku"
        ]
        for p in knownPrefixes where lower.contains(p) { return p }
        return raw
    }

    private static func parseTimestamp(_ raw: Any?) -> Date? {
        if let s = raw as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            let f2 = ISO8601DateFormatter()
            if let d = f2.date(from: s) { return d }
        }
        if let n = raw as? Double { return Date(timeIntervalSince1970: n) }
        return nil
    }

    /// 把 user 消息的 content 折成单行预览（用户消息里 content 既可能是 string，
    /// 也可能是 [{type:"text", text:"..."}, {type:"tool_result", ...}]）。
    private static func extractUserPreview(_ obj: [String: Any]) -> String {
        guard let message = obj["message"] as? [String: Any] else { return "(user)" }
        if let s = message["content"] as? String {
            return condense(s)
        }
        if let arr = message["content"] as? [[String: Any]] {
            for item in arr {
                if (item["type"] as? String) == "text", let t = item["text"] as? String {
                    return condense(t)
                }
            }
            // 没有 text 段，多半是 tool_result 之类，给一个占位
            return "(tool result)"
        }
        return "(user)"
    }

    private static func condense(_ s: String) -> String {
        let collapsed = s.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count > 200 {
            return String(collapsed.prefix(200)) + "…"
        }
        return collapsed
    }

    // MARK: - Codex parsing

    /// 解析单个 ~/.codex/sessions 下的 rollout-*.jsonl。
    /// 关键事件：session_meta 提供 cwd / sessionId；turn_context 切换当前 model；
    /// event_msg.payload.type=="token_count" 携带 info.last_token_usage 是本轮增量。
    /// "用户轮次"以 event_msg.payload.type=="user_message" 为锚点；
    /// 项目（projectDir）取 cwd basename，例如 `/Users/me/foo/bar` → `bar`。
    private static func parseCodexSession(file: URL, pricing: PricingService) -> TaskSession? {
        guard let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8) else { return nil }

        var sessionID: String = extractCodexSessionId(from: file.lastPathComponent) ?? file.deletingPathExtension().lastPathComponent
        var cwd: String = ""
        var currentModel: String = "gpt-5.5"
        var first: Date? = nil
        var last: Date? = nil

        var perModel: [String: (Int, Int, Int, Int, Double)] = [:]
        var assistantCount = 0

        struct TurnAcc {
            var id: String
            var preview: String
            var timestamp: Date?
            var assistantCount: Int = 0
            var tokens: Int = 0
            var cost: Double = 0
        }
        var turns: [TurnAcc] = []
        var currentTurn: Int? = nil

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            let ts = parseTimestamp(obj["timestamp"])
            if let ts {
                if first == nil || ts < (first ?? .distantFuture) { first = ts }
                if last == nil  || ts > (last  ?? .distantPast)   { last = ts }
            }

            let type = obj["type"] as? String
            let payload = obj["payload"] as? [String: Any]

            switch type {
            case "session_meta":
                if let id = payload?["id"] as? String, !id.isEmpty { sessionID = id }
                if cwd.isEmpty, let c = payload?["cwd"] as? String { cwd = c }
                if let model = payload?["model"] as? String, !model.isEmpty { currentModel = model }
                // 兼容嵌套 payload.payload.model 的旧版本格式
                if let inner = payload?["payload"] as? [String: Any],
                   let model = inner["model"] as? String, !model.isEmpty {
                    currentModel = model
                }
            case "turn_context":
                if let c = payload?["cwd"] as? String, cwd.isEmpty { cwd = c }
                if let model = payload?["model"] as? String, !model.isEmpty { currentModel = model }
            case "event_msg":
                guard let p = payload else { continue }
                let subtype = p["type"] as? String
                if subtype == "user_message" {
                    let raw = (p["message"] as? String) ?? "(user)"
                    let preview = condense(raw)
                    // 过滤掉 Codex 启动时自动注入的 <environment_context>…</environment_context>
                    if preview.hasPrefix("<environment_context>") { continue }
                    let id = (obj["id"] as? String) ?? UUID().uuidString
                    turns.append(TurnAcc(id: "\(sessionID)#\(turns.count)#\(id)", preview: preview, timestamp: ts))
                    currentTurn = turns.count - 1
                } else if subtype == "token_count",
                          let info = p["info"] as? [String: Any],
                          let lastUsage = info["last_token_usage"] as? [String: Any] {
                    let input = (lastUsage["input_tokens"] as? Int) ?? 0
                    let output = (lastUsage["output_tokens"] as? Int) ?? 0
                    let cachedInput = (lastUsage["cached_input_tokens"] as? Int) ?? 0
                    let reasoning = (lastUsage["reasoning_output_tokens"] as? Int) ?? 0
                    if input == 0 && output == 0 && cachedInput == 0 { continue }

                    let nonCachedInput = max(0, input - cachedInput)
                    let totalOutput = output + reasoning
                    let normalized = normalizeOpenAIModel(currentModel)
                    let cost = pricing.cost(
                        provider: Provider.openai.rawValue,
                        model: normalized,
                        input: nonCachedInput,
                        output: totalOutput,
                        cacheCreation: 0,
                        cacheRead: cachedInput
                    )
                    assistantCount += 1
                    var acc = perModel[normalized] ?? (0, 0, 0, 0, 0.0)
                    acc.0 += nonCachedInput; acc.1 += totalOutput; acc.2 += 0; acc.3 += cachedInput; acc.4 += cost
                    perModel[normalized] = acc
                    if let idx = currentTurn, idx < turns.count {
                        turns[idx].assistantCount += 1
                        turns[idx].tokens += nonCachedInput + totalOutput + cachedInput
                        turns[idx].cost += cost
                    }
                }
            default:
                break
            }
        }

        let totalIn = perModel.values.reduce(0) { $0 + $1.0 }
        let totalOut = perModel.values.reduce(0) { $0 + $1.1 }
        let totalCW = perModel.values.reduce(0) { $0 + $1.2 }
        let totalCR = perModel.values.reduce(0) { $0 + $1.3 }
        let totalCost = perModel.values.reduce(0.0) { $0 + $1.4 }
        if totalIn == 0 && totalOut == 0 && totalCR == 0 { return nil }

        let modelRows = perModel.map { (k, v) in
            TaskSession.ModelRow(model: k, input: v.0, output: v.1,
                                 cacheCreation: v.2, cacheRead: v.3, cost: v.4)
        }.sorted { $0.cost > $1.cost }

        let turnRows = turns.filter { $0.assistantCount > 0 || $0.tokens > 0 }
            .map { TaskSession.TurnRow(id: $0.id, preview: $0.preview,
                                       timestamp: $0.timestamp,
                                       assistantCount: $0.assistantCount,
                                       totalTokens: $0.tokens,
                                       cost: $0.cost) }

        let project = codexProjectKey(cwd: cwd, file: file)
        return TaskSession(
            id: sessionID,
            provider: .openai,
            fileURL: file,
            projectDir: project,
            cwd: cwd,
            gitBranch: nil,
            firstTimestamp: first,
            lastTimestamp: last,
            messageCount: assistantCount,
            totalCostUSD: totalCost,
            inputTokens: totalIn,
            outputTokens: totalOut,
            cacheCreationTokens: totalCW,
            cacheReadTokens: totalCR,
            modelRows: modelRows,
            turns: turnRows
        )
    }

    /// rollout-2026-06-18T07-00-39-<uuid>.jsonl → "<uuid>"
    private static func extractCodexSessionId(from filename: String) -> String? {
        let stem = (filename as NSString).deletingPathExtension
        let parts = stem.split(separator: "-")
        guard parts.count >= 5 else { return nil }
        return parts.suffix(5).joined(separator: "-")
    }

    /// Codex 没有像 Claude 那样把项目编码进目录名，所以这里用 cwd basename 作为项目 key；
    /// 找不到 cwd（极少数损坏的 rollout）时退回到日期分组目录。
    private static func codexProjectKey(cwd: String, file: URL) -> String {
        if !cwd.isEmpty {
            let last = (cwd as NSString).lastPathComponent
            return last.isEmpty ? cwd : last
        }
        return file.deletingLastPathComponent().lastPathComponent
    }

    private static func normalizeOpenAIModel(_ raw: String) -> String {
        let lower = raw.lowercased()
        let knownPrefixes = [
            "gpt-5.5-pro", "gpt-5.5",
            "gpt-5.4-nano", "gpt-5.4-mini", "gpt-5.4-pro", "gpt-5.4",
            "gpt-5.3", "gpt-5.2", "gpt-5.1", "gpt-5",
            "gpt-4.1-mini", "gpt-4.1-nano", "gpt-4.1",
            "gpt-4o-mini", "gpt-4o",
            "o4-mini", "o3-mini", "o3", "o1-mini", "o1",
            "codex-mini", "codex"
        ]
        for p in knownPrefixes where lower.contains(p) { return p }
        return raw
    }
}

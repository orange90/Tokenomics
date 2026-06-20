import Foundation
import SwiftUI
import SwiftData
import Combine

/// 显示外观模式
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return L10n.tr("appearance.system")
        case .light:  return L10n.tr("appearance.light")
        case .dark:   return L10n.tr("appearance.dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// 应用全局状态：负责 collectors 注册、Scheduler 启停、显示偏好。
@MainActor
final class AppState: ObservableObject {
    @Published var currency: Currency = .both
    @Published var usdCnyRate: Double = 7.20
    @Published var lastRefreshAt: Date?
    @Published var isRefreshing: Bool = false
    @Published var statusMessages: [String] = []
    @Published var appearance: AppearanceMode = .system

    /// 被用户隐藏的供应商 ID 集合（内置用 Provider.rawValue，自定义用 CustomProvider.id）。
    /// 仅影响 UI 可见性，不影响数据采集；持久化到 UserDefaults。
    @Published var hiddenProviderIDs: Set<String> = []

    /// 当前已加载的自定义供应商快照（供 UI 直接读取，不必再 query）。
    @Published var customProviders: [CustomProvider] = []

    /// 用户订阅的 AI 服务套餐（用于「回本没」功能）
    @Published var subscriptions: [Subscription] = []

    /// Claude / Codex 等订阅额度快照，按 probe.id 索引（"claude" / "codex"）。
    @Published var quotaSnapshots: [String: QuotaSnapshot] = [:]

    /// Claude 额度采集偏好（OAuth ↔ 浏览器 cookie 的优先级、浏览器顺序）。
    /// 改动会通过 quotaService 闭包实时生效，无需重建 service。
    @Published var claudeQuotaPreferences: ClaudeQuotaPreferences = .default

    private(set) var pricingService: PricingService = PricingService()
    private(set) var exchangeRateService: ExchangeRateService = ExchangeRateService()
    private(set) var keychain: KeychainService = KeychainService()
    private(set) var repository: UsageRepository?
    private(set) var scheduler: RefreshScheduler?
    private(set) lazy var quotaService: QuotaService = QuotaService(
        claudePreferences: { [weak self] in
            self?.claudeQuotaPreferences ?? .default
        }
    )

    @AppStorage("tc.preferredCurrency") private var preferredCurrencyRaw: String = Currency.both.rawValue
    @AppStorage("tc.hiddenProviders") private var hiddenProvidersRaw: String = ""
    @AppStorage("tc.preferredAppearance") private var preferredAppearanceRaw: String = AppearanceMode.system.rawValue
    @AppStorage("tc.subscriptions") private var subscriptionsRaw: String = ""
    @AppStorage("tc.claudeQuotaPrefs") private var claudeQuotaPrefsRaw: String = ""

    func bootstrap(modelContext: ModelContext) async {
        // 1. 读取偏好
        self.currency = Currency(rawValue: preferredCurrencyRaw) ?? .both
        self.appearance = AppearanceMode(rawValue: preferredAppearanceRaw) ?? .system
        self.hiddenProviderIDs = Self.decodeHidden(hiddenProvidersRaw)
        self.subscriptions = Self.decodeSubscriptions(subscriptionsRaw)
        self.claudeQuotaPreferences = Self.decodeClaudePrefs(claudeQuotaPrefsRaw)

        // 2. 初始化 Repository
        let repo = UsageRepository(context: modelContext)
        self.repository = repo

        // 2.1 读取自定义供应商
        self.customProviders = repo.fetchAllCustomProviders()

        // 3. 加载定价表
        let loaded = pricingService.loadBuiltinTable()
        pricingService.loadOverrides(from: repo)
        if !loaded {
            appendStatus("⚠️ 内置单价表加载失败，请重装应用或检查 PricingTable.json")
        } else {
            appendStatus("✓ 已内置 \(pricingService.allEntries.count) 条模型单价")
        }
        // 触发依赖 pricingService 的 SwiftUI 视图刷新（PricingSettings 等）
        self.objectWillChange.send()

        // 3.1 立即用新的内置/覆盖单价回填历史 costUSD == 0 的记录，
        //     让首页在首轮 collector 跑完前就能看到正确金额。
        if loaded {
            let n = repo.backfillMissingCosts(using: pricingService)
            if n > 0 { appendStatus("↺ 启动回填：修正 \(n) 条历史 0 金额记录") }
        }

        // 4. 刷新汇率（异步，不阻塞）
        Task {
            if let rate = try? await exchangeRateService.fetchUSDtoCNY() {
                self.usdCnyRate = rate
            }
        }

        // 5. 构建并启动 Scheduler
        let collectors = buildCollectors()
        let scheduler = RefreshScheduler(
            collectors: collectors,
            repository: repo,
            pricing: pricingService,
            onLog: { [weak self] msg in
                Task { @MainActor in
                    self?.appendStatus(msg)
                }
            },
            onCycleComplete: { [weak self] in
                await self?.refreshQuotas()
            }
        )
        self.scheduler = scheduler

        // 5.1 一次性迁移：清理旧版本截断的 Claude Code 脏数据，让下一轮 refresh 全量重解析
        let migrated = repo.migrateClaudeCodeIfNeeded()
        if migrated > 0 {
            appendStatus("⟳ 迁移：清理被旧 normalize 截断的 \(migrated) 条 Claude Code 记录，将全量重新解析")
        }

        await scheduler.start()
    }

    /// 内置 + 启用中的自定义供应商打包成 collectors。
    private func buildCollectors() -> [UsageCollector] {
        var list = CollectorRegistry.makeAll(keychain: keychain)
        for cp in customProviders where cp.isCollectionEnabled {
            list.append(CustomScriptCollector(provider: cp))
        }
        return list
    }

    /// 自定义供应商发生变化（新增/编辑/启用/删除）时，重建 scheduler。
    /// 注意：这里直接用新 collectors 替换 scheduler，原有 timer 会被覆盖。
    func reloadCustomProviders() {
        guard let repo = repository else { return }
        self.customProviders = repo.fetchAllCustomProviders()
        guard let oldScheduler = scheduler else { return }
        oldScheduler.stop()
        let newScheduler = RefreshScheduler(
            collectors: buildCollectors(),
            repository: repo,
            pricing: pricingService,
            onLog: { [weak self] msg in
                Task { @MainActor in self?.appendStatus(msg) }
            },
            onCycleComplete: { [weak self] in
                await self?.refreshQuotas()
            }
        )
        self.scheduler = newScheduler
        Task { await newScheduler.start() }
    }

    func updateCurrency(_ c: Currency) {
        currency = c
        preferredCurrencyRaw = c.rawValue
    }

    func updateAppearance(_ a: AppearanceMode) {
        appearance = a
        preferredAppearanceRaw = a.rawValue
    }

    // MARK: - Hidden providers

    func isProviderHidden(_ id: String) -> Bool {
        hiddenProviderIDs.contains(id)
    }

    func setProviderHidden(_ id: String, hidden: Bool) {
        if hidden { hiddenProviderIDs.insert(id) }
        else { hiddenProviderIDs.remove(id) }
        hiddenProvidersRaw = Self.encodeHidden(hiddenProviderIDs)
    }

    private static func decodeHidden(_ raw: String) -> Set<String> {
        let parts = raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        return Set(parts)
    }

    private static func encodeHidden(_ ids: Set<String>) -> String {
        ids.sorted().joined(separator: ",")
    }

    // MARK: - Custom providers CRUD

    func addCustomProvider(_ provider: CustomProvider) {
        guard let repo = repository else { return }
        repo.insertCustomProvider(provider)
        reloadCustomProviders()
    }

    func updateCustomProvider(_ provider: CustomProvider) {
        guard let repo = repository else { return }
        repo.saveCustomProvider(provider)
        reloadCustomProviders()
    }

    func deleteCustomProvider(id: String) {
        guard let repo = repository else { return }
        repo.deleteCustomProvider(id: id)
        hiddenProviderIDs.remove(id)
        hiddenProvidersRaw = Self.encodeHidden(hiddenProviderIDs)
        reloadCustomProviders()
    }

    func appendStatus(_ s: String) {
        let stamped = "[\(Self.timeFmt.string(from: Date()))] \(s)"
        statusMessages.insert(stamped, at: 0)
        if statusMessages.count > 100 { statusMessages.removeLast(statusMessages.count - 100) }
    }

    // MARK: - Subscriptions

    func addSubscription(_ sub: Subscription) {
        subscriptions.append(sub)
        persistSubscriptions()
    }

    func updateSubscription(_ sub: Subscription) {
        if let idx = subscriptions.firstIndex(where: { $0.id == sub.id }) {
            subscriptions[idx] = sub
            persistSubscriptions()
        }
    }

    func deleteSubscription(id: String) {
        subscriptions.removeAll { $0.id == id }
        persistSubscriptions()
    }

    private func persistSubscriptions() {
        subscriptionsRaw = Self.encodeSubscriptions(subscriptions)
    }

    /// 基于当前已抓到的 quotaSnapshots（仪表盘 Claude / Codex OAuth 探测结果），
    /// 推断出尚未加入 subscriptions 列表的套餐预设。
    /// 同一个 providerKey 已存在订阅的会被跳过，避免重复导入。
    func detectedSubscriptionsFromQuotas() -> [SubscriptionPreset] {
        var seen = Set<String>()  // 用 preset.id 去重
        var result: [SubscriptionPreset] = []
        let existingProviders = Set(subscriptions.map { $0.providerKey })
        for (pid, snap) in quotaSnapshots {
            guard let preset = SubscriptionPreset.match(
                probeID: pid, accountIdentifier: snap.accountIdentifier
            ) else { continue }
            if existingProviders.contains(preset.providerKey) { continue }
            if seen.insert(preset.id).inserted {
                result.append(preset)
            }
        }
        return result
    }

    /// 把检测到的预设一键写入 subscriptions。
    /// 返回实际新增的数量。
    @discardableResult
    func importDetectedSubscriptions() -> Int {
        let detected = detectedSubscriptionsFromQuotas()
        guard !detected.isEmpty else { return 0 }
        for p in detected {
            let sub = Subscription(
                providerKey: p.providerKey,
                planName: p.planName,
                monthlyUSD: p.monthlyUSD
            )
            subscriptions.append(sub)
        }
        persistSubscriptions()
        appendStatus("✓ 已从仪表盘探测结果导入 \(detected.count) 个订阅")
        return detected.count
    }

    private static func decodeSubscriptions(_ raw: String) -> [Subscription] {
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([Subscription].self, from: data)) ?? []
    }

    private static func encodeSubscriptions(_ subs: [Subscription]) -> String {
        guard let data = try? JSONEncoder().encode(subs),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    // MARK: - Claude 额度采集偏好

    func updateClaudeQuotaPreferences(_ p: ClaudeQuotaPreferences) {
        claudeQuotaPreferences = p
        claudeQuotaPrefsRaw = Self.encodeClaudePrefs(p)
    }

    private static func decodeClaudePrefs(_ raw: String) -> ClaudeQuotaPreferences {
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return .default }
        return (try? JSONDecoder().decode(ClaudeQuotaPreferences.self, from: data)) ?? .default
    }

    private static func encodeClaudePrefs(_ p: ClaudeQuotaPreferences) -> String {
        guard let data = try? JSONEncoder().encode(p),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    func manualRefresh() {
        guard let scheduler else { return }
        isRefreshing = true
        Task {
            // refreshNow() 完成后会触发 onCycleComplete，从而拉取额度。
            await scheduler.refreshNow()
            self.lastRefreshAt = Date()
            self.isRefreshing = false
        }
    }

    /// 拉取 Claude / Codex 订阅额度快照。失败的 probe 会在状态栏打印一条日志。
    func refreshQuotas() async {
        let available = quotaService.availableProbes
        guard !available.isEmpty else { return }
        appendStatus("开始拉取订阅额度 (probes=\(available.count))")
        let result = await quotaService.fetchAll()
        for (pid, snap) in result.snapshots {
            quotaSnapshots[pid] = snap
            let names = snap.windows.map { w -> String in
                let suffix = w.note.map { " (\($0))" } ?? ""
                return "\(w.title)\(suffix) \(Int(w.usedPercent))%"
            }
            appendStatus("✓ \(snap.providerName) 额度：\(names.joined(separator: "、"))")
        }
        for (pid, err) in result.errors {
            appendStatus("✗ \(pid) 额度拉取失败：\(err.localizedDescription)")
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

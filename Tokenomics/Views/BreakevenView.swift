import SwiftUI
import SwiftData

/// 「回本啦」页面：现代化设计，把月度套餐费 vs 本月按 Token 真实使用量换算的等值费用
/// 做对比，让用户一眼看到自己「赚回来了多少」。
struct BreakevenView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var localization: LocalizationManager
    @Query(sort: \UsageRecord.timestamp, order: .reverse) private var records: [UsageRecord]

    var body: some View {
        ScrollView(.vertical) {
            Group {
                if appState.subscriptions.isEmpty {
                    emptyState
                        .padding(20)
                } else {
                    let allStats = computeAllStats()
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(Array(allStats.enumerated()), id: \.offset) { _, stats in
                            subscriptionColumn(stats: stats)
                                .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .id(localization.language.rawValue)
        .onAppear { autoImportDetectedIfNeeded() }
        .onChange(of: appState.quotaSnapshots) { _, _ in autoImportDetectedIfNeeded() }
    }

    @ViewBuilder
    private func subscriptionColumn(stats: BreakevenStats) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            subscriptionHeader(stats: stats)
            heroCard(stats: stats)
            badgeCard(stats: stats)
            investmentReturnCard(stats: stats)
            timelineCard(stats: stats)
            usageOverviewCard(stats: stats)
            apiComparisonCard(stats: stats)
            tipBar(stats: stats)
        }
    }

    @ViewBuilder
    private func subscriptionHeader(stats: BreakevenStats) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: stats.primaryProviderColorHex))
                .frame(width: 10, height: 10)
            Text(L10n.tr("breakeven.header.fmt", stats.primaryProviderName, stats.primarySubscription.planName))
                .font(.system(size: 18, weight: .bold))
            Spacer()
        }
    }

    /// 仪表盘已经识别到的订阅直接静默导入。
    private func autoImportDetectedIfNeeded() {
        guard !appState.detectedSubscriptionsFromQuotas().isEmpty else { return }
        appState.importDetectedSubscriptions()
    }

    // MARK: - Stats Aggregation

    /// 本月所有记录
    private var thisMonth: [UsageRecord] {
        let now = Date()
        let start = Calendar.current.dateInterval(of: .month, for: now)?.start ?? now
        return records.filter { $0.timestamp >= start }
    }

    private func computeAllStats() -> [BreakevenStats] {
        // 按供应商聚合本月所有记录
        var byProvider: [String: (cost: Double, tokens: Int, count: Int)] = [:]
        for r in thisMonth {
            var cur = byProvider[r.provider] ?? (0, 0, 0)
            cur.cost += r.costUSD
            cur.tokens += r.totalTokens
            cur.count += 1
            byProvider[r.provider] = cur
        }

        // 按月费从高到低稳定排序，体验上把"主套餐"放在前面
        let subs = appState.subscriptions.sorted(by: { $0.monthlyUSD > $1.monthlyUSD })
        return subs.map { sub in
            computeStats(for: sub, byProvider: byProvider)
        }
    }

    private func computeStats(
        for sub: Subscription,
        byProvider: [String: (cost: Double, tokens: Int, count: Int)]
    ) -> BreakevenStats {
        let stat = byProvider[sub.providerKey] ?? (0, 0, 0)

        // 单个订阅：投入即该订阅月费，等值即该供应商本月的等值
        let monthly = sub.monthlyUSD
        let equivalent = stat.cost
        let ratio = monthly > 0 ? equivalent / monthly : 0

        // 时间线节点
        let now = Date()
        let monthStart = Calendar.current.dateInterval(of: .month, for: now)?.start ?? now
        let timeline = buildTimeline(
            monthStart: monthStart,
            now: now,
            totalMonthly: monthly,
            primaryProviderKey: sub.providerKey,
            currentRatio: ratio,
            currentEquivalent: equivalent
        )

        return BreakevenStats(
            primarySubscription: sub,
            primaryProviderName: Provider(rawValue: sub.providerKey)?.displayName ?? sub.providerKey,
            primaryProviderColorHex: Provider(rawValue: sub.providerKey)?.brandColorHex ?? "#10A37F",
            primaryCost: stat.cost,
            primaryTokens: stat.tokens,
            primaryRequests: stat.count,
            totalMonthlyUSD: monthly,
            totalEquivalentUSD: equivalent,
            ratio: ratio,
            timeline: timeline
        )
    }

    private func buildTimeline(
        monthStart: Date,
        now: Date,
        totalMonthly: Double,
        primaryProviderKey: String,
        currentRatio: Double,
        currentEquivalent: Double
    ) -> [TimelineEvent] {
        // 按时间顺序累加该供应商当月每条记录的 costUSD
        let monthRecords = records
            .filter { $0.timestamp >= monthStart && $0.provider == primaryProviderKey }
            .sorted(by: { $0.timestamp < $1.timestamp })

        var events: [TimelineEvent] = []
        events.append(TimelineEvent(
            date: monthStart,
            title: L10n.tr("breakeven.tier.title"),
            subtitle: L10n.tr("breakeven.tier.subtitle"),
            kind: .start
        ))

        // 找到 100% / 300% 的时间点
        let targets: [(Double, String)] = [
            (1.0, L10n.tr("breakeven.first_breakeven")),
            (3.0, L10n.tr("breakeven.rate_300"))
        ]
        var cumulative = 0.0
        var hit: [Double: Date] = [:]
        for r in monthRecords {
            cumulative += r.costUSD
            for (t, _) in targets where hit[t] == nil {
                if totalMonthly > 0 && cumulative / totalMonthly >= t {
                    hit[t] = r.timestamp
                }
            }
        }
        for (t, label) in targets {
            if let d = hit[t] {
                let pct = Int(t * 100)
                let amt = totalMonthly * t
                events.append(TimelineEvent(
                    date: d,
                    title: label,
                    subtitle: L10n.tr("breakeven.timeline.milestone.fmt", pct, formatUSDCompact(amt)),
                    kind: .milestone
                ))
            }
        }

        // 当前节点
        events.append(TimelineEvent(
            date: now,
            title: L10n.tr("breakeven.timeline.current.fmt", currentRatio * 100),
            subtitle: L10n.tr("breakeven.timeline.value.fmt", formatUSDCompact(currentEquivalent)),
            kind: .current
        ))

        return events.sorted(by: { $0.date < $1.date })
    }

    // MARK: - Hero Card

    @ViewBuilder
    private func heroCard(stats: BreakevenStats) -> some View {
        let isBreakeven = stats.ratio >= 1
        let pctText = String(format: "%.0f%%", stats.ratio * 100)
        let multiple = String(format: "%.2f", stats.ratio)

        ZStack(alignment: .topTrailing) {
            // 背景渐变
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(
                    colors: isBreakeven
                        ? [Color(hex: "#E8F8EC"), Color(hex: "#F5FBF1")]
                        : [Color(hex: "#FFF7E6"), Color(hex: "#FFFBF0")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))

            // 装饰碎纸
            confetti.opacity(0.85)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        // 顶部 chip
                        HStack(spacing: 6) {
                            Text("🎉").font(.system(size: 13))
                            Text(isBreakeven ? L10n.tr("breakeven.hero.cheers") : L10n.tr("breakeven.hero.keep_going"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: "#1E7E34"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(Color.white.opacity(0.85))
                                .overlay(Capsule().stroke(Color(hex: "#A6E1B4"), lineWidth: 1))
                        )

                        // 主标题
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isBreakeven ? L10n.tr("breakeven.hero.title.done") : L10n.tr("breakeven.hero.title.almost"))
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(Color(hex: "#1E7E34"))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(pctText)
                                .font(.system(size: 48, weight: .heavy))
                                .foregroundStyle(Color(hex: "#1E7E34"))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }

                        Text(L10n.tr("breakeven.hero.subtitle.fmt", multiple))
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#3E6B49"))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    trophy
                }

                // 三栏小数据
                HStack(spacing: 8) {
                    heroMetric(
                        title: L10n.tr("breakeven.metric.paid"),
                        value: formatUSDCompact(stats.totalMonthlyUSD),
                        subtitle: L10n.tr("breakeven.metric.paid.sub")
                    )
                    heroMetric(
                        title: L10n.tr("breakeven.metric.value"),
                        value: formatUSDCompact(stats.totalEquivalentUSD),
                        subtitle: L10n.tr("breakeven.metric.value.sub")
                    )
                    heroMetric(
                        title: L10n.tr("breakeven.metric.saved"),
                        value: formatUSDCompact(max(0, stats.totalEquivalentUSD - stats.totalMonthlyUSD)),
                        subtitle: L10n.tr("breakeven.metric.saved.sub")
                    )
                }
            }
            .padding(18)
        }
        .frame(minHeight: 280)
    }

    @ViewBuilder
    private func heroMetric(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "#5A6B5E"))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(hex: "#1E7E34"))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: "#7A8A7E"))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.85))
        )
    }

    private var trophy: some View {
        ZStack {
            // 奖杯本体
            Image(systemName: "trophy.fill")
                .font(.system(size: 90))
                .foregroundStyle(LinearGradient(
                    colors: [Color(hex: "#FFD24A"), Color(hex: "#F0A500")],
                    startPoint: .top, endPoint: .bottom
                ))
                .shadow(color: Color(hex: "#F0A500").opacity(0.4), radius: 10, x: 0, y: 4)
            // 星星
            Image(systemName: "star.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.white)
                .offset(y: -6)
        }
        .frame(width: 110, height: 110)
    }

    private var confetti: some View {
        ZStack {
            ForEach(0..<18, id: \.self) { i in
                let colors: [Color] = [
                    Color(hex: "#FFB6C1"), Color(hex: "#87CEEB"),
                    Color(hex: "#FFD700"), Color(hex: "#98FB98"),
                    Color(hex: "#DDA0DD"), Color(hex: "#FFA07A")
                ]
                let positions: [CGPoint] = [
                    CGPoint(x: 50, y: 40),  CGPoint(x: 120, y: 70),
                    CGPoint(x: 200, y: 30), CGPoint(x: 280, y: 80),
                    CGPoint(x: 360, y: 50), CGPoint(x: 440, y: 100),
                    CGPoint(x: 80, y: 200), CGPoint(x: 160, y: 230),
                    CGPoint(x: 260, y: 180), CGPoint(x: 380, y: 210),
                    CGPoint(x: 480, y: 160), CGPoint(x: 540, y: 230),
                    CGPoint(x: 30, y: 130), CGPoint(x: 590, y: 60),
                    CGPoint(x: 580, y: 180), CGPoint(x: 20, y: 240),
                    CGPoint(x: 320, y: 240), CGPoint(x: 420, y: 30)
                ]
                Rectangle()
                    .fill(colors[i % colors.count])
                    .frame(width: 6, height: 10)
                    .rotationEffect(.degrees(Double(i) * 23))
                    .position(positions[i % positions.count])
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Badge Card (血赚级用户)

    @ViewBuilder
    private func badgeCard(stats: BreakevenStats) -> some View {
        let tier = userTier(ratio: stats.ratio)
        HStack(spacing: 14) {
            // 徽章图形
            badgeIcon(tier: tier)
                .frame(width: 88, height: 104)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(tier.title)
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(tier.emoji).font(.system(size: 16))
                }
                Text(L10n.tr("breakeven.badge.plan_value.fmt", stats.primarySubscription.planName))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(L10n.tr("breakeven.badge.multiples.fmt", stats.ratio))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(hex: "#1E7E34"))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 2) {
                Text(L10n.tr("breakeven.badge.surpassed"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(alignment: .center, spacing: 6) {
                    Text("\(tier.percentile)%")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(hex: "#1E7E34"))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(hex: "#A0D9B4"))
                }
                Text(L10n.tr("breakeven.badge.users"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    @ViewBuilder
    private func badgeIcon(tier: UserTier) -> some View {
        ZStack {
            // 盾牌底
            ShieldShape()
                .fill(LinearGradient(
                    colors: [tier.color, tier.color.opacity(0.75)],
                    startPoint: .top, endPoint: .bottom
                ))
                .shadow(color: tier.color.opacity(0.3), radius: 6, x: 0, y: 3)
            ShieldShape()
                .stroke(Color.white.opacity(0.6), lineWidth: 2)
                .padding(4)

            VStack(spacing: 4) {
                Image(systemName: tier.iconName)
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                Text(tier.title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.15)))
                HStack(spacing: 2) {
                    ForEach(0..<tier.stars, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(Color(hex: "#FFD700"))
                    }
                }
            }
        }
    }

    private func userTier(ratio: Double) -> UserTier {
        switch ratio {
        case 5...:
            return UserTier(
                title: L10n.tr("breakeven.tier.fire"), emoji: "🔥", iconName: "flame.fill",
                color: Color(hex: "#E85D2A"), stars: 3, percentile: 92
            )
        case 3..<5:
            return UserTier(
                title: L10n.tr("breakeven.tier.diamond"), emoji: "💎", iconName: "diamond.fill",
                color: Color(hex: "#1E90FF"), stars: 3, percentile: 80
            )
        case 1..<3:
            return UserTier(
                title: L10n.tr("breakeven.tier.done"), emoji: "✨", iconName: "checkmark.seal.fill",
                color: Color(hex: "#10A37F"), stars: 2, percentile: 60
            )
        case 0.5..<1:
            return UserTier(
                title: L10n.tr("breakeven.tier.almost"), emoji: "🚀", iconName: "arrow.up.right",
                color: Color(hex: "#F0A500"), stars: 2, percentile: 35
            )
        default:
            return UserTier(
                title: L10n.tr("breakeven.tier.newbie"), emoji: "🌱", iconName: "leaf.fill",
                color: Color(hex: "#9CA3AF"), stars: 1, percentile: 15
            )
        }
    }

    // MARK: - Investment vs Return

    @ViewBuilder
    private func investmentReturnCard(stats: BreakevenStats) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr("breakeven.invret.title"))
                        .font(.system(size: 16, weight: .semibold))
                    Text(L10n.tr("breakeven.invret.desc"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.0f%%", stats.ratio * 100))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(hex: "#1E7E34"))
                        .monospacedDigit()
                    Text(L10n.tr("breakeven.invret.rate"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            // 支付 / 获得价值标签
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr("breakeven.invret.paid"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(formatUSDCompact(stats.totalMonthlyUSD))
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L10n.tr("breakeven.invret.gained"))
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: "#1E7E34"))
                    Text(formatUSDCompact(stats.totalEquivalentUSD))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "#1E7E34"))
                        .monospacedDigit()
                }
            }

            // 一体化的箭头进度条
            GeometryReader { geo in
                let trackHeight: CGFloat = 28
                let headWidth: CGFloat = 22
                let fraction = progressFraction(ratio: stats.ratio)
                let bodyMin: CGFloat = 56
                let totalWidth = max(bodyMin + headWidth, geo.size.width * fraction)

                ZStack(alignment: .leading) {
                    // 轨道
                    Capsule()
                        .fill(Color(hex: "#EAF5EE"))
                        .frame(height: trackHeight)

                    // 一体化箭头（圆角尾 + 尖头）
                    ArrowBarShape(headWidth: headWidth, cornerRadius: trackHeight / 2)
                        .fill(LinearGradient(
                            colors: [Color(hex: "#7DD896"), Color(hex: "#3FB46A"), Color(hex: "#1E7E34")],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .overlay(
                            // 顶部高光
                            ArrowBarShape(headWidth: headWidth, cornerRadius: trackHeight / 2)
                                .fill(LinearGradient(
                                    colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                                    startPoint: .top, endPoint: .center
                                ))
                                .blendMode(.plusLighter)
                        )
                        .frame(width: totalWidth, height: trackHeight)
                        .shadow(color: Color(hex: "#2E9B4F").opacity(0.25), radius: 6, x: 0, y: 3)
                }
            }
            .frame(height: 28)
            .padding(.top, 4)
        }
        .padding(20)
        .background(cardBackground)
    }

    /// 把 0~ ∞ 的 ratio 压到 0.1 ~ 0.95 的进度区间，方便可视化。
    private func progressFraction(ratio: Double) -> Double {
        // 1x => 0.5, 3x => 0.75, 7x => 0.95
        let r = max(0, ratio)
        let f = 1 - exp(-r / 2.5)
        return min(0.95, max(0.1, f))
    }

    // MARK: - Timeline

    @ViewBuilder
    private func timelineCard(stats: BreakevenStats) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("breakeven.timeline.title"))
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(stats.timeline.enumerated()), id: \.offset) { _, evt in
                    HStack(alignment: .top, spacing: 12) {
                        Text(timelineDate(evt.date))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .leading)

                        Image(systemName: evt.kind == .current
                              ? "checkmark.circle.fill"
                              : "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(evt.kind == .current
                                             ? Color(hex: "#1E7E34")
                                             : Color(hex: "#7DD896"))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(evt.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(evt.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minHeight: 220, alignment: .topLeading)
        .background(cardBackground)
    }

    private func timelineDate(_ d: Date) -> String {
        let f = DateFormatter()
        let langCode: String
        switch localization.language.resolved {
        case .zhHant: langCode = "zh-Hant"
        case .en:     langCode = "en"
        default:      langCode = "zh-Hans"
        }
        f.locale = Locale(identifier: langCode)
        f.setLocalizedDateFormatFromTemplate(L10n.tr("breakeven.timeline.date_fmt"))
        return f.string(from: d)
    }

    // MARK: - Usage Overview

    @ViewBuilder
    private func usageOverviewCard(stats: BreakevenStats) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("breakeven.overview.title.fmt", stats.primaryProviderName))
                .font(.system(size: 16, weight: .semibold))

            overviewRow(
                icon: "circle.hexagongrid.fill",
                iconColor: Color(hex: "#10A37F"),
                title: L10n.tr("breakeven.overview.tokens"),
                value: stats.primaryTokens.formatted()
            )
            overviewRow(
                icon: "bubble.left.fill",
                iconColor: Color(hex: "#5BA3F5"),
                title: L10n.tr("breakeven.overview.requests"),
                value: stats.primaryRequests.formatted()
            )
            overviewRow(
                icon: "waveform.path.ecg",
                iconColor: Color(hex: "#E85D7A"),
                title: L10n.tr("breakeven.overview.month_eq"),
                value: formatUSDCompact(stats.primaryCost)
            )

            HStack {
                Text(L10n.tr("breakeven.overview.view_models"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "#1E7E34"))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "#1E7E34"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: "#F2FAF4"))
            )

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minHeight: 220, alignment: .topLeading)
        .background(cardBackground)
    }

    @ViewBuilder
    private func overviewRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(iconColor.opacity(0.12)).frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)
            }
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
        }
    }

    // MARK: - API Comparison

    @ViewBuilder
    private func apiComparisonCard(stats: BreakevenStats) -> some View {
        let saved = max(0, stats.totalEquivalentUSD - stats.totalMonthlyUSD)
        let savedPct = stats.totalEquivalentUSD > 0
            ? saved / stats.totalEquivalentUSD * 100
            : 0

        VStack(alignment: .leading, spacing: 14) {
            // 顶部：API 等值 与 当前已付，并排
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("breakeven.api.title"))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(L10n.tr("breakeven.api.desc.fmt", stats.primaryProviderName))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(formatUSDCompact(stats.totalEquivalentUSD))
                        .font(.system(size: 20, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("breakeven.api.now_paid"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(formatUSDCompact(stats.totalMonthlyUSD))
                        .font(.system(size: 20, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(L10n.tr("breakeven.api.plan_cost.fmt", stats.primarySubscription.planName))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 底部：节省高亮，居中横幅
            HStack(spacing: 12) {
                Image(systemName: "face.smiling.inverse")
                    .font(.system(size: 32))
                    .foregroundStyle(LinearGradient(
                        colors: [Color(hex: "#FFD24A"), Color(hex: "#F0A500")],
                        startPoint: .top, endPoint: .bottom
                    ))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr("breakeven.api.saved"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(hex: "#1E7E34"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(hex: "#E8F8EC")))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(formatUSDCompact(saved))
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color(hex: "#1E7E34"))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(L10n.tr("breakeven.api.saved_pct.fmt", savedPct))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "#F2FAF4"))
            )
        }
        .padding(18)
        .background(cardBackground)
    }

    // MARK: - Tip Bar

    @ViewBuilder
    private func tipBar(stats: BreakevenStats) -> some View {
        let tip = stats.ratio >= 1
            ? L10n.tr("breakeven.tip.done.fmt", stats.primarySubscription.planName)
            : L10n.tr("breakeven.tip.almost")
        HStack(spacing: 8) {
            Text(L10n.tr("breakeven.tip.label"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "#7A6A1B"))
            Text(tip)
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "#5A5418"))
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#F0C200"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(
                    colors: [Color(hex: "#FFFBE6"), Color(hex: "#FFF7CC")],
                    startPoint: .leading, endPoint: .trailing
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "#F0D862"), lineWidth: 1)
                )
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "creditcard")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(L10n.tr("breakeven.empty.title"))
                .font(.title3.weight(.semibold))
            Text(L10n.tr("breakeven.empty.desc"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(cardBackground)
    }

    // MARK: - Shared

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    /// 紧凑的 USD 显示（不带四位小数）
    private func formatUSDCompact(_ usd: Double) -> String {
        switch appState.currency {
        case .cny:
            return String(format: "¥%.2f", usd * appState.usdCnyRate)
        default:
            return String(format: "$%.2f", usd)
        }
    }
}

// MARK: - Models

private struct BreakevenStats {
    let primarySubscription: Subscription
    let primaryProviderName: String
    let primaryProviderColorHex: String
    let primaryCost: Double
    let primaryTokens: Int
    let primaryRequests: Int
    let totalMonthlyUSD: Double
    let totalEquivalentUSD: Double
    let ratio: Double
    let timeline: [TimelineEvent]
}

private struct TimelineEvent {
    enum Kind { case start, milestone, current }
    let date: Date
    let title: String
    let subtitle: String
    let kind: Kind
}

private struct UserTier {
    let title: String
    let emoji: String
    let iconName: String
    let color: Color
    let stars: Int
    let percentile: Int
}

// MARK: - Shield Shape

private struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addLine(to: CGPoint(x: w, y: h * 0.18))
        p.addLine(to: CGPoint(x: w, y: h * 0.6))
        p.addQuadCurve(
            to: CGPoint(x: w * 0.5, y: h),
            control: CGPoint(x: w, y: h * 0.95)
        )
        p.addQuadCurve(
            to: CGPoint(x: 0, y: h * 0.6),
            control: CGPoint(x: 0, y: h * 0.95)
        )
        p.addLine(to: CGPoint(x: 0, y: h * 0.18))
        p.closeSubpath()
        return p
    }
}

// MARK: - Arrow Bar Shape

/// 一体化的「箭头进度条」：左端圆角，右端尖头。
private struct ArrowBarShape: Shape {
    /// 箭头尖端部分的水平宽度
    var headWidth: CGFloat
    /// 左端圆角半径（一般等于条高的一半）
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let r = min(cornerRadius, h / 2)
        // 箭尖宽度受总宽限制，避免过短时挤变形
        let head = max(0, min(headWidth, w - r))
        let bodyEnd = w - head
        let midY = h / 2

        // 起点：左上圆弧起始
        p.move(to: CGPoint(x: r, y: 0))
        // 顶边到尾部 body 末端
        p.addLine(to: CGPoint(x: bodyEnd, y: 0))
        // 上斜边收到箭尖
        p.addLine(to: CGPoint(x: w, y: midY))
        // 下斜边回到底边
        p.addLine(to: CGPoint(x: bodyEnd, y: h))
        // 底边到左下圆弧起始
        p.addLine(to: CGPoint(x: r, y: h))
        // 左下圆角
        p.addArc(
            center: CGPoint(x: r, y: h - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        // 左侧竖边
        p.addLine(to: CGPoint(x: 0, y: r))
        // 左上圆角
        p.addArc(
            center: CGPoint(x: r, y: r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        p.closeSubpath()
        return p
    }
}

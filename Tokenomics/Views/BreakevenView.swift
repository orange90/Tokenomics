import SwiftUI
import SwiftData

/// 「回本啦」页面：现代化设计，把月度套餐费 vs 本月按 Token 真实使用量换算的等值费用
/// 做对比，让用户一眼看到自己「赚回来了多少」。
struct BreakevenView: View {
    @EnvironmentObject private var appState: AppState
    @Query(sort: \UsageRecord.timestamp, order: .reverse) private var records: [UsageRecord]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if appState.subscriptions.isEmpty {
                    emptyState
                } else {
                    let stats = computeStats()
                    heroCard(stats: stats)
                    badgeCard(stats: stats)
                    investmentReturnCard(stats: stats)

                    HStack(alignment: .top, spacing: 16) {
                        timelineCard(stats: stats)
                            .frame(maxWidth: .infinity)
                        usageOverviewCard(stats: stats)
                            .frame(maxWidth: .infinity)
                    }

                    apiComparisonCard(stats: stats)
                    tipBar(stats: stats)
                }
            }
            .padding(20)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { autoImportDetectedIfNeeded() }
        .onChange(of: appState.quotaSnapshots) { _, _ in autoImportDetectedIfNeeded() }
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

    private func computeStats() -> BreakevenStats {
        // 主订阅：选取金额最大的一个作为"主套餐"展示
        let primary = appState.subscriptions.max(by: { $0.monthlyUSD < $1.monthlyUSD })
            ?? appState.subscriptions.first!

        // 按供应商聚合本月所有记录
        var byProvider: [String: (cost: Double, tokens: Int, count: Int)] = [:]
        for r in thisMonth {
            var cur = byProvider[r.provider] ?? (0, 0, 0)
            cur.cost += r.costUSD
            cur.tokens += r.totalTokens
            cur.count += 1
            byProvider[r.provider] = cur
        }
        let primaryStat = byProvider[primary.providerKey] ?? (0, 0, 0)

        // 总值：所有订阅 vs 所有等值
        let totalMonthly = appState.subscriptions.reduce(0) { $0 + $1.monthlyUSD }
        let totalEquivalent = appState.subscriptions.reduce(0.0) {
            $0 + (byProvider[$1.providerKey]?.cost ?? 0)
        }
        let ratio = totalMonthly > 0 ? totalEquivalent / totalMonthly : 0

        // 时间线节点
        let now = Date()
        let monthStart = Calendar.current.dateInterval(of: .month, for: now)?.start ?? now
        let timeline = buildTimeline(
            monthStart: monthStart,
            now: now,
            totalMonthly: totalMonthly,
            byProvider: byProvider,
            primaryProviderKey: primary.providerKey,
            currentRatio: ratio,
            currentEquivalent: totalEquivalent
        )

        return BreakevenStats(
            primarySubscription: primary,
            primaryProviderName: Provider(rawValue: primary.providerKey)?.displayName ?? primary.providerKey,
            primaryProviderColorHex: Provider(rawValue: primary.providerKey)?.brandColorHex ?? "#10A37F",
            primaryCost: primaryStat.cost,
            primaryTokens: primaryStat.tokens,
            primaryRequests: primaryStat.count,
            totalMonthlyUSD: totalMonthly,
            totalEquivalentUSD: totalEquivalent,
            ratio: ratio,
            timeline: timeline
        )
    }

    private func buildTimeline(
        monthStart: Date,
        now: Date,
        totalMonthly: Double,
        byProvider: [String: (cost: Double, tokens: Int, count: Int)],
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
            title: "套餐生效",
            subtitle: "开始使用",
            kind: .start
        ))

        // 找到 100% / 300% 的时间点
        let targets: [(Double, String)] = [(1.0, "首次回本"), (3.0, "回本率 300%")]
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
                    subtitle: "回本率达到 \(pct)% · 价值 \(formatUSDCompact(amt))",
                    kind: .milestone
                ))
            }
        }

        // 当前节点
        events.append(TimelineEvent(
            date: now,
            title: String(format: "回本率 %.0f%% (当前)", currentRatio * 100),
            subtitle: "价值达到 \(formatUSDCompact(currentEquivalent))",
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

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    // 顶部 chip
                    HStack(spacing: 6) {
                        Text("🎉").font(.system(size: 13))
                        Text(isBreakeven ? "恭喜你！" : "继续加油！")
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
                        Text(isBreakeven ? "已回本！" : "还差一点")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color(hex: "#1E7E34"))
                        Text(pctText)
                            .font(.system(size: 64, weight: .heavy))
                            .foregroundStyle(Color(hex: "#1E7E34"))
                            .monospacedDigit()
                    }

                    Text("你已经赚回套餐费用的 \(multiple) 倍 🎉")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "#3E6B49"))

                    // 三栏小数据
                    HStack(spacing: 12) {
                        heroMetric(
                            title: "支付金额",
                            value: formatUSDCompact(stats.totalMonthlyUSD),
                            subtitle: "本月套餐支出"
                        )
                        heroMetric(
                            title: "获得价值",
                            value: formatUSDCompact(stats.totalEquivalentUSD),
                            subtitle: "Token 等值价值"
                        )
                        heroMetric(
                            title: "节省金额",
                            value: formatUSDCompact(max(0, stats.totalEquivalentUSD - stats.totalMonthlyUSD)),
                            subtitle: "相当于省下"
                        )
                    }
                }
                .padding(.leading, 24)
                .padding(.vertical, 22)

                Spacer(minLength: 0)

                trophy
                    .padding(.trailing, 24)
                    .padding(.top, 18)
            }
        }
        .frame(minHeight: 280)
    }

    @ViewBuilder
    private func heroMetric(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "#5A6B5E"))
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: "#1E7E34"))
                .monospacedDigit()
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: "#7A8A7E"))
        }
        .padding(.horizontal, 12)
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
                .font(.system(size: 130))
                .foregroundStyle(LinearGradient(
                    colors: [Color(hex: "#FFD24A"), Color(hex: "#F0A500")],
                    startPoint: .top, endPoint: .bottom
                ))
                .shadow(color: Color(hex: "#F0A500").opacity(0.4), radius: 12, x: 0, y: 6)
            // 星星
            Image(systemName: "star.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.white)
                .offset(y: -10)
        }
        .frame(width: 160, height: 160)
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
        HStack(spacing: 20) {
            // 徽章图形
            badgeIcon(tier: tier)
                .frame(width: 110, height: 130)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(tier.title)
                        .font(.system(size: 20, weight: .bold))
                    Text(tier.emoji).font(.system(size: 18))
                }
                Text("你的 Token 使用量已经达到")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("\(stats.primarySubscription.planName) 套餐价值的")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.2f 倍", stats.ratio))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color(hex: "#1E7E34"))
                    .monospacedDigit()
            }

            Spacer(minLength: 16)

            VStack(spacing: 6) {
                Text("超过了")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack(alignment: .center, spacing: 10) {
                    Text("\(tier.percentile)%")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(Color(hex: "#1E7E34"))
                        .monospacedDigit()
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color(hex: "#A0D9B4"))
                }
                Text("的用户")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 8)
        }
        .padding(20)
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
                title: "血赚级用户", emoji: "🔥", iconName: "flame.fill",
                color: Color(hex: "#E85D2A"), stars: 3, percentile: 92
            )
        case 3..<5:
            return UserTier(
                title: "回本达人", emoji: "💎", iconName: "diamond.fill",
                color: Color(hex: "#1E90FF"), stars: 3, percentile: 80
            )
        case 1..<3:
            return UserTier(
                title: "已回本", emoji: "✨", iconName: "checkmark.seal.fill",
                color: Color(hex: "#10A37F"), stars: 2, percentile: 60
            )
        case 0.5..<1:
            return UserTier(
                title: "接近回本", emoji: "🚀", iconName: "arrow.up.right",
                color: Color(hex: "#F0A500"), stars: 2, percentile: 35
            )
        default:
            return UserTier(
                title: "新手用户", emoji: "🌱", iconName: "leaf.fill",
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
                    Text("投入 vs 回报")
                        .font(.system(size: 16, weight: .semibold))
                    Text("用更少的钱，获得了更多的价值")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.0f%%", stats.ratio * 100))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(hex: "#1E7E34"))
                        .monospacedDigit()
                    Text("回本率")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            // 进度条带箭头
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // 支付左侧标
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("支付")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(formatUSDCompact(stats.totalMonthlyUSD))
                                .font(.system(size: 14, weight: .semibold))
                                .monospacedDigit()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("获得价值")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(hex: "#1E7E34"))
                            Text(formatUSDCompact(stats.totalEquivalentUSD))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: "#1E7E34"))
                                .monospacedDigit()
                        }
                    }
                    .offset(y: -28)

                    // 进度条
                    Capsule()
                        .fill(Color(hex: "#E8F8EC"))
                        .frame(height: 24)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color(hex: "#7DD896"), Color(hex: "#2E9B4F")],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(40, geo.size.width * progressFraction(ratio: stats.ratio)),
                               height: 24)
                    // 箭头尖
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(hex: "#2E9B4F"))
                        .offset(x: max(28, geo.size.width * progressFraction(ratio: stats.ratio)) - 8)
                }
            }
            .frame(height: 24)
            .padding(.top, 28)
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
            Text("回本时间线")
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
        f.dateFormat = "M月d日"
        return f.string(from: d)
    }

    // MARK: - Usage Overview

    @ViewBuilder
    private func usageOverviewCard(stats: BreakevenStats) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("使用概览 (\(stats.primaryProviderName))")
                .font(.system(size: 16, weight: .semibold))

            overviewRow(
                icon: "circle.hexagongrid.fill",
                iconColor: Color(hex: "#10A37F"),
                title: "Token 使用量",
                value: stats.primaryTokens.formatted()
            )
            overviewRow(
                icon: "bubble.left.fill",
                iconColor: Color(hex: "#5BA3F5"),
                title: "请求次数",
                value: stats.primaryRequests.formatted()
            )
            overviewRow(
                icon: "waveform.path.ecg",
                iconColor: Color(hex: "#E85D7A"),
                title: "本月等值",
                value: formatUSDCompact(stats.primaryCost)
            )

            HStack {
                Text("查看模型分布")
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

        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("如果按 API 计费")
                    .font(.system(size: 14, weight: .semibold))
                Text("如果你直接通过 \(stats.primaryProviderName) API 使用\n本月你需要支付")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(formatUSDCompact(stats.totalEquivalentUSD))
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 6) {
                Text("相当于省下")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: "#1E7E34"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: "#E8F8EC")))
                Text(formatUSDCompact(saved))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color(hex: "#1E7E34"))
                    .monospacedDigit()
                Text(String(format: "省了 %.1f%%", savedPct))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("而现在你只支付了")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(formatUSDCompact(stats.totalMonthlyUSD))
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                    Text("\(stats.primarySubscription.planName) 套餐费用")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "face.smiling.inverse")
                    .font(.system(size: 36))
                    .foregroundStyle(LinearGradient(
                        colors: [Color(hex: "#FFD24A"), Color(hex: "#F0A500")],
                        startPoint: .top, endPoint: .bottom
                    ))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(cardBackground)
    }

    // MARK: - Tip Bar

    @ViewBuilder
    private func tipBar(stats: BreakevenStats) -> some View {
        let tip = stats.ratio >= 1
            ? "继续保持！你正在充分利用 \(stats.primarySubscription.planName) 套餐的强大能力 ✨"
            : "再多用一些，距离回本只差一点啦 💪"
        HStack(spacing: 8) {
            Text("💡 小贴士")
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
            Text("还没添加任何订阅")
                .font(.title3.weight(.semibold))
            Text("请到「设置 → 订阅」中添加你订阅的 ChatGPT Plus / Claude Pro / Cursor Pro 等套餐。\n如果你登录了 Claude Code / Codex CLI，回到「仪表盘」等几秒，订阅会被自动识别。")
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

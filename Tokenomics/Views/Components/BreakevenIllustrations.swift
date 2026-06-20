import SwiftUI

// MARK: - Palette
//
// 自绘的 3D 插画统一用这套色板，模拟设计稿里的暖金 / 翠绿光泽。
// 故意不依赖 Color(hex:)，让这些组件可以独立被快照渲染验证。

private enum Gold {
    static let glow   = Color(red: 1.00, green: 0.84, blue: 0.36)
    static let hi     = Color(red: 1.00, green: 0.97, blue: 0.82) // 高光
    static let lite   = Color(red: 1.00, green: 0.87, blue: 0.42)
    static let mid    = Color(red: 0.99, green: 0.74, blue: 0.15)
    static let deep   = Color(red: 0.93, green: 0.57, blue: 0.05)
    static let shade  = Color(red: 0.74, green: 0.41, blue: 0.02)
    static let core   = Color(red: 0.58, green: 0.31, blue: 0.00)
}

private enum Grn {
    static let hi    = Color(red: 0.74, green: 0.93, blue: 0.80)
    static let lite  = Color(red: 0.36, green: 0.81, blue: 0.50)
    static let mid   = Color(red: 0.20, green: 0.70, blue: 0.40)
    static let deep  = Color(red: 0.10, green: 0.52, blue: 0.24)
    static let dark  = Color(red: 0.05, green: 0.38, blue: 0.17)
}

private enum Flame {
    static let core = Color(red: 1.00, green: 0.95, blue: 0.62)
    static let warm = Color(red: 1.00, green: 0.72, blue: 0.16)
    static let hot  = Color(red: 0.98, green: 0.42, blue: 0.08)
    static let deep = Color(red: 0.90, green: 0.24, blue: 0.05)
}

// MARK: - Trophy
//
// 金色奖杯：杯身 + 双耳手柄 + 中央星星 + 杯颈 + 底座 + 绿色奖台 + 金色铭牌，
// 叠加镜面高光、光晕和落地阴影，呈现立体光泽。

struct TrophyIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            ZStack {
                // 背后暖金光晕
                Circle()
                    .fill(RadialGradient(
                        colors: [Gold.glow.opacity(0.42), Gold.glow.opacity(0.0)],
                        center: .center, startRadius: 0, endRadius: W * 0.52))
                    .frame(width: W * 1.2, height: W * 1.2)
                    .position(x: W * 0.5, y: H * 0.40)

                // 落地阴影
                Ellipse()
                    .fill(Color.black.opacity(0.10))
                    .frame(width: W * 0.60, height: H * 0.05)
                    .blur(radius: 4)
                    .position(x: W * 0.5, y: H * 0.965)

                // 绿色奖台 + 铭牌
                podium(W, H)

                // 杯颈 + 底盘
                stem(W, H)

                // 双耳手柄（在杯身后面）
                handles(W, H)

                // 杯身
                bowl(W, H)
            }
        }
    }

    private func podium(_ W: CGFloat, _ H: CGFloat) -> some View {
        let pw = W * 0.72, ph = H * 0.155
        return ZStack {
            RoundedRectangle(cornerRadius: ph * 0.28, style: .continuous)
                .fill(LinearGradient(
                    colors: [Grn.lite, Grn.mid, Grn.deep],
                    startPoint: .top, endPoint: .bottom))
            // 顶面高光
            RoundedRectangle(cornerRadius: ph * 0.28, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.45), Color.white.opacity(0.0)],
                    startPoint: .top, endPoint: .center))
                .blendMode(.plusLighter)
            // 金色铭牌
            RoundedRectangle(cornerRadius: ph * 0.18, style: .continuous)
                .fill(LinearGradient(
                    colors: [Gold.lite, Gold.mid, Gold.deep],
                    startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: ph * 0.18, style: .continuous)
                        .stroke(Gold.hi.opacity(0.7), lineWidth: 1))
                .frame(width: pw * 0.5, height: ph * 0.46)
        }
        .frame(width: pw, height: ph)
        .shadow(color: Grn.dark.opacity(0.35), radius: 5, x: 0, y: 4)
        .position(x: W * 0.5, y: H * 0.875)
    }

    private func stem(_ W: CGFloat, _ H: CGFloat) -> some View {
        ZStack {
            // 杯颈
            Capsule()
                .fill(LinearGradient(
                    colors: [Gold.lite, Gold.mid, Gold.deep],
                    startPoint: .leading, endPoint: .trailing))
                .frame(width: W * 0.085, height: H * 0.14)
                .position(x: W * 0.5, y: H * 0.70)
            // 底盘（梯形感的扁圆盘）
            Ellipse()
                .fill(LinearGradient(
                    colors: [Gold.hi, Gold.mid, Gold.deep],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: W * 0.30, height: H * 0.055)
                .position(x: W * 0.5, y: H * 0.775)
            Ellipse()
                .fill(LinearGradient(
                    colors: [Gold.lite, Gold.deep],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: W * 0.20, height: H * 0.04)
                .position(x: W * 0.5, y: H * 0.74)
        }
    }

    private func handles(_ W: CGFloat, _ H: CGFloat) -> some View {
        ZStack {
            TrophyHandlesShape()
                .stroke(LinearGradient(
                    colors: [Gold.lite, Gold.mid, Gold.deep],
                    startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: W * 0.08, lineCap: .round))
            TrophyHandlesShape()
                .stroke(Gold.hi.opacity(0.65),
                    style: StrokeStyle(lineWidth: W * 0.022, lineCap: .round))
        }
        .frame(width: W * 0.86, height: H * 0.46)
        .position(x: W * 0.5, y: H * 0.34)
    }

    private func bowl(_ W: CGFloat, _ H: CGFloat) -> some View {
        let bw = W * 0.62, bh = H * 0.56
        return ZStack {
            // 杯口（内腔，暗金）
            Ellipse()
                .fill(RadialGradient(
                    colors: [Gold.core, Gold.shade],
                    center: .center, startRadius: 0, endRadius: bw * 0.5))
                .frame(width: bw * 0.92, height: bh * 0.26)
                .position(x: bw * 0.5, y: bh * 0.11)

            // 杯身
            TrophyBowlShape()
                .fill(LinearGradient(
                    colors: [Gold.hi, Gold.lite, Gold.mid, Gold.deep],
                    startPoint: .top, endPoint: .bottom))

            // 杯口亮边
            Ellipse()
                .stroke(LinearGradient(
                    colors: [Gold.hi, Gold.mid, Gold.hi],
                    startPoint: .leading, endPoint: .trailing),
                    lineWidth: bh * 0.035)
                .frame(width: bw * 0.92, height: bh * 0.26)
                .position(x: bw * 0.5, y: bh * 0.11)

            // 左侧镜面高光
            Ellipse()
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.55), Color.white.opacity(0.0)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: bw * 0.16, height: bh * 0.42)
                .rotationEffect(.degrees(-12))
                .position(x: bw * 0.31, y: bh * 0.42)
                .blendMode(.plusLighter)
                .blur(radius: 0.6)

            // 中央星星
            StarShape()
                .fill(LinearGradient(
                    colors: [Color.white, Gold.hi],
                    startPoint: .top, endPoint: .bottom))
                .overlay(
                    StarShape().stroke(Gold.deep.opacity(0.25), lineWidth: 0.8))
                .frame(width: bw * 0.34, height: bw * 0.34)
                .shadow(color: Gold.shade.opacity(0.3), radius: 1, x: 0, y: 1)
                .position(x: bw * 0.5, y: bh * 0.40)
        }
        .frame(width: bw, height: bh)
        .shadow(color: Gold.shade.opacity(0.28), radius: 8, x: 0, y: 6)
        .position(x: W * 0.5, y: H * 0.345)
    }
}

// MARK: - Tier Badge
//
// 等级勋章：盾形六边外框 + 内盾 + 顶部高光 + 火焰图标 + 飘带名牌 + 星星。

struct TierBadgeIllustration: View {
    var title: String
    var stars: Int
    var iconName: String
    var iconColor: Color

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            ZStack {
                // 外盾
                ShieldBadgeShape()
                    .fill(LinearGradient(
                        colors: [Grn.deep, Grn.dark],
                        startPoint: .top, endPoint: .bottom))
                    .overlay(
                        ShieldBadgeShape()
                            .stroke(Grn.dark, style: StrokeStyle(lineWidth: W * 0.05, lineJoin: .round)))
                    .shadow(color: Grn.dark.opacity(0.4), radius: 6, x: 0, y: 4)

                // 内盾
                ShieldBadgeShape()
                    .fill(LinearGradient(
                        colors: [Grn.lite, Grn.mid, Grn.deep],
                        startPoint: .top, endPoint: .bottom))
                    .overlay(
                        // 顶部光泽
                        ShieldBadgeShape()
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.45), Color.white.opacity(0.0)],
                                startPoint: .top, endPoint: .center))
                            .blendMode(.plusLighter))
                    .frame(width: W * 0.80, height: H * 0.80)
                    .position(x: W * 0.5, y: H * 0.46)

                // 火焰图标（上部）
                BadgeFlame(iconName: iconName, iconColor: iconColor)
                    .frame(width: W * 0.34, height: H * 0.34)
                    .position(x: W * 0.5, y: H * 0.33)

                // 飘带名牌
                ribbon(W, H)

                // 星星
                stars(W, H)
            }
        }
    }

    private func ribbon(_ W: CGFloat, _ H: CGFloat) -> some View {
        ZStack {
            RibbonShape()
                .fill(LinearGradient(
                    colors: [Grn.deep, Grn.dark],
                    startPoint: .top, endPoint: .bottom))
                .overlay(
                    RibbonShape()
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                .shadow(color: Grn.dark.opacity(0.4), radius: 2, x: 0, y: 2)
            Text(title)
                .font(.system(size: H * 0.085, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, W * 0.12)
        }
        .frame(width: W * 0.98, height: H * 0.20)
        .position(x: W * 0.5, y: H * 0.60)
    }

    private func stars(_ W: CGFloat, _ H: CGFloat) -> some View {
        HStack(spacing: W * 0.04) {
            ForEach(0..<max(1, stars), id: \.self) { _ in
                StarShape()
                    .fill(LinearGradient(
                        colors: [Gold.hi, Gold.mid],
                        startPoint: .top, endPoint: .bottom))
                    .overlay(StarShape().stroke(Gold.deep.opacity(0.35), lineWidth: 0.5))
                    .frame(width: W * 0.11, height: W * 0.11)
            }
        }
        .position(x: W * 0.5, y: H * 0.80)
    }
}

/// 勋章里的火焰：橙黄火焰 + 内核 + 柔光。
private struct BadgeFlame: View {
    var iconName: String
    var iconColor: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // 火焰类等级用自绘火焰，其它等级回退到 SF Symbol 保持语义。
            if iconName == "flame.fill" {
                ZStack {
                    FlameShape()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: w * 1.04, height: h * 1.04)
                        .blur(radius: 3)
                    FlameShape()
                        .fill(LinearGradient(
                            colors: [Flame.warm, Flame.hot, Flame.deep],
                            startPoint: .top, endPoint: .bottom))
                        .frame(width: w, height: h)
                    FlameShape()
                        .fill(LinearGradient(
                            colors: [Flame.core, Flame.warm],
                            startPoint: .top, endPoint: .bottom))
                        .frame(width: w * 0.52, height: h * 0.58)
                        .offset(y: h * 0.16)
                }
                .position(x: w * 0.5, y: h * 0.5)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: min(w, h) * 0.78, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: iconColor.opacity(0.5), radius: 4)
                    .position(x: w * 0.5, y: h * 0.5)
            }
        }
    }
}

// MARK: - Coin Stack
//
// 金币堆：每枚硬币 = 顶面亮椭圆 + 侧厚 + 边缘暗椭圆，叠成一摞，前面再斜放一枚。

struct CoinStackIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            let cw = W * 0.62
            ZStack {
                // 倚靠的一枚（后面）
                coin(cx: W * 0.66, cy: H * 0.62, cw: cw * 0.92)
                // 主堆叠（自下而上）
                coin(cx: W * 0.40, cy: H * 0.80, cw: cw)
                coin(cx: W * 0.40, cy: H * 0.64, cw: cw)
                coin(cx: W * 0.42, cy: H * 0.48, cw: cw)
            }
        }
    }

    private func coin(cx: CGFloat, cy: CGFloat, cw: CGFloat) -> some View {
        let ch = cw * 0.40          // 顶面椭圆高
        let thick = cw * 0.18       // 厚度
        return ZStack {
            // 底边暗椭圆
            Ellipse()
                .fill(Gold.shade)
                .frame(width: cw, height: ch)
                .offset(y: thick)
            // 侧厚
            Rectangle()
                .fill(LinearGradient(
                    colors: [Gold.deep, Gold.mid, Gold.deep],
                    startPoint: .leading, endPoint: .trailing))
                .frame(width: cw, height: thick)
            // 顶面
            Ellipse()
                .fill(RadialGradient(
                    colors: [Gold.hi, Gold.lite, Gold.mid],
                    center: UnitPoint(x: 0.4, y: 0.35),
                    startRadius: 0, endRadius: cw * 0.6))
                .frame(width: cw, height: ch)
            // 顶面内圈
            Ellipse()
                .stroke(Gold.deep.opacity(0.4), lineWidth: max(0.6, cw * 0.02))
                .frame(width: cw * 0.66, height: ch * 0.66)
            // 顶面高光弧
            Ellipse()
                .trim(from: 0.55, to: 0.85)
                .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: max(0.8, cw * 0.03), lineCap: .round))
                .frame(width: cw * 0.78, height: ch * 0.78)
        }
        .frame(width: cw, height: ch + thick)
        .position(x: cx, y: cy)
    }
}

// MARK: - People Group
//
// 立体人群：中间一个主体（深绿），后面左右两个稍小、偏淡，呈“超过 N%”的群像。

struct PeopleGroupIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            ZStack {
                person(cx: W * 0.27, cy: H * 0.56, s: W * 0.40, tone: Grn.hi)
                person(cx: W * 0.73, cy: H * 0.56, s: W * 0.40, tone: Grn.hi)
                person(cx: W * 0.50, cy: H * 0.50, s: W * 0.52, tone: Grn.mid)
            }
        }
    }

    private func person(cx: CGFloat, cy: CGFloat, s: CGFloat, tone: Color) -> some View {
        let head = s * 0.42
        return ZStack {
            // 身体（肩部）
            PersonBustShape()
                .fill(LinearGradient(
                    colors: [tone, tone.opacity(0.82)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: s, height: s * 0.62)
                .offset(y: s * 0.42)
            // 头
            Circle()
                .fill(LinearGradient(
                    colors: [tone, tone.opacity(0.82)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: head, height: head)
                .offset(y: -s * 0.22)
            // 头顶高光
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: head * 0.4, height: head * 0.4)
                .offset(x: -head * 0.12, y: -s * 0.30)
                .blendMode(.plusLighter)
        }
        .frame(width: s, height: s)
        .position(x: cx, y: cy)
    }
}

// MARK: - Rocket
//
// 火箭：白色弹体 + 红色鼻锥 + 蓝色舷窗 + 红色尾翼 + 火焰，外加云团点缀。

struct RocketIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            ZStack {
                // 云团
                cloud(cx: W * 0.30, cy: H * 0.86, s: W * 0.34)
                cloud(cx: W * 0.72, cy: H * 0.80, s: W * 0.30)

                // 尾焰
                FlameShape()
                    .fill(LinearGradient(
                        colors: [Flame.warm, Flame.hot, Flame.deep],
                        startPoint: .top, endPoint: .bottom))
                    .rotationEffect(.degrees(180))
                    .frame(width: W * 0.22, height: H * 0.26)
                    .position(x: W * 0.5, y: H * 0.80)

                // 尾翼
                FinShape()
                    .fill(LinearGradient(colors: [Flame.hot, Flame.deep], startPoint: .top, endPoint: .bottom))
                    .frame(width: W * 0.20, height: H * 0.24)
                    .position(x: W * 0.36, y: H * 0.66)
                FinShape()
                    .fill(LinearGradient(colors: [Flame.hot, Flame.deep], startPoint: .top, endPoint: .bottom))
                    .scaleEffect(x: -1, y: 1)
                    .frame(width: W * 0.20, height: H * 0.24)
                    .position(x: W * 0.64, y: H * 0.66)

                // 弹体
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color.white, Color(white: 0.86)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: W * 0.34, height: H * 0.62)
                    .position(x: W * 0.5, y: H * 0.46)
                // 弹体左侧阴影
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color.black.opacity(0.12), Color.clear],
                        startPoint: .trailing, endPoint: .leading))
                    .frame(width: W * 0.34, height: H * 0.62)
                    .position(x: W * 0.5, y: H * 0.46)

                // 鼻锥
                NoseShape()
                    .fill(LinearGradient(colors: [Flame.hot, Flame.deep], startPoint: .top, endPoint: .bottom))
                    .frame(width: W * 0.34, height: H * 0.28)
                    .position(x: W * 0.5, y: H * 0.20)

                // 舷窗
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 0.65, green: 0.85, blue: 1.0), Color(red: 0.20, green: 0.55, blue: 0.95)],
                        center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: W * 0.12))
                    .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: W * 0.018))
                    .frame(width: W * 0.16, height: W * 0.16)
                    .position(x: W * 0.5, y: H * 0.40)
            }
        }
    }

    private func cloud(cx: CGFloat, cy: CGFloat, s: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color.white).frame(width: s * 0.6, height: s * 0.6).offset(x: -s * 0.22)
            Circle().fill(Color.white).frame(width: s * 0.8, height: s * 0.8)
            Circle().fill(Color.white).frame(width: s * 0.55, height: s * 0.55).offset(x: s * 0.26)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
        .position(x: cx, y: cy)
    }
}

// MARK: - Shapes

/// 五点盾形（平顶、尖底），配合 round lineJoin 描边可呈现圆角徽章轮廓。
private struct ShieldBadgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.16, y: h * 0.10))
        p.addLine(to: CGPoint(x: w * 0.84, y: h * 0.10))
        p.addLine(to: CGPoint(x: w * 0.96, y: h * 0.44))
        p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.96))
        p.addLine(to: CGPoint(x: w * 0.04, y: h * 0.44))
        p.closeSubpath()
        return p
    }
}

/// 飘带 / 名牌：两端尖角的横幅。
private struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h * 0.5))
        p.addLine(to: CGPoint(x: w * 0.10, y: 0))
        p.addLine(to: CGPoint(x: w * 0.90, y: 0))
        p.addLine(to: CGPoint(x: w, y: h * 0.5))
        p.addLine(to: CGPoint(x: w * 0.90, y: h))
        p.addLine(to: CGPoint(x: w * 0.10, y: h))
        p.closeSubpath()
        return p
    }
}

/// 五角星。
struct StarShape: Shape {
    var points: Int = 5
    var innerRatio: CGFloat = 0.44
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rOuter = min(rect.width, rect.height) / 2
        let rInner = rOuter * innerRatio
        let n = points * 2
        for i in 0..<n {
            let angle = (CGFloat(i) / CGFloat(n)) * 2 * .pi - .pi / 2
            let r = (i % 2 == 0) ? rOuter : rInner
            let pt = CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// 火焰轮廓。
private struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addCurve(to: CGPoint(x: w * 0.95, y: h * 0.62),
                   control1: CGPoint(x: w * 0.64, y: h * 0.20),
                   control2: CGPoint(x: w * 0.98, y: h * 0.40))
        p.addCurve(to: CGPoint(x: w * 0.5, y: h),
                   control1: CGPoint(x: w * 0.93, y: h * 0.86),
                   control2: CGPoint(x: w * 0.72, y: h))
        p.addCurve(to: CGPoint(x: w * 0.05, y: h * 0.62),
                   control1: CGPoint(x: w * 0.28, y: h),
                   control2: CGPoint(x: w * 0.07, y: h * 0.86))
        p.addCurve(to: CGPoint(x: w * 0.5, y: 0),
                   control1: CGPoint(x: w * 0.02, y: h * 0.38),
                   control2: CGPoint(x: w * 0.40, y: h * 0.24))
        p.closeSubpath()
        return p
    }
}

/// 奖杯杯身轮廓（高脚杯造型）。
private struct TrophyBowlShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.04, y: h * 0.14))
        p.addQuadCurve(to: CGPoint(x: w * 0.96, y: h * 0.14),
                       control: CGPoint(x: w * 0.5, y: h * 0.30))
        p.addQuadCurve(to: CGPoint(x: w * 0.60, y: h * 0.88),
                       control: CGPoint(x: w * 1.06, y: h * 0.48))
        p.addQuadCurve(to: CGPoint(x: w * 0.40, y: h * 0.88),
                       control: CGPoint(x: w * 0.5, y: h * 1.06))
        p.addQuadCurve(to: CGPoint(x: w * 0.04, y: h * 0.14),
                       control: CGPoint(x: w * -0.06, y: h * 0.48))
        p.closeSubpath()
        return p
    }
}

/// 奖杯双耳手柄（两条开放曲线，描边后形成左右把手）。
private struct TrophyHandlesShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // 左耳
        p.move(to: CGPoint(x: w * 0.32, y: h * 0.14))
        p.addCurve(to: CGPoint(x: w * 0.31, y: h * 0.62),
                   control1: CGPoint(x: w * -0.02, y: h * 0.14),
                   control2: CGPoint(x: w * -0.02, y: h * 0.62))
        // 右耳
        p.move(to: CGPoint(x: w * 0.68, y: h * 0.14))
        p.addCurve(to: CGPoint(x: w * 0.69, y: h * 0.62),
                   control1: CGPoint(x: w * 1.02, y: h * 0.14),
                   control2: CGPoint(x: w * 1.02, y: h * 0.62))
        return p
    }
}

/// 人物半身（肩部）轮廓。
private struct PersonBustShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: h * 0.5))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: 0),
                       control: CGPoint(x: w * 0.04, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: h * 0.5),
                       control: CGPoint(x: w * 0.96, y: 0))
        p.addLine(to: CGPoint(x: w, y: h))
        p.closeSubpath()
        return p
    }
}

/// 火箭尾翼。
private struct FinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h * 0.7))
        p.addQuadCurve(to: CGPoint(x: 0, y: h),
                       control: CGPoint(x: w * 0.5, y: h))
        p.addLine(to: CGPoint(x: w * 0.55, y: h * 0.2))
        p.closeSubpath()
        return p
    }
}

/// 火箭鼻锥。
private struct NoseShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: h),
                       control: CGPoint(x: w * 0.96, y: h * 0.7))
        p.addLine(to: CGPoint(x: 0, y: h))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: 0),
                       control: CGPoint(x: w * 0.04, y: h * 0.7))
        p.closeSubpath()
        return p
    }
}

#if DEBUG
#Preview("Illustrations") {
    HStack(spacing: 30) {
        TrophyIllustration().frame(width: 130, height: 140)
        TierBadgeIllustration(title: "血赚级用户", stars: 3, iconName: "flame.fill",
                              iconColor: .orange).frame(width: 96, height: 112)
        CoinStackIllustration().frame(width: 90, height: 80)
        PeopleGroupIllustration().frame(width: 80, height: 60)
        RocketIllustration().frame(width: 90, height: 120)
    }
    .padding(40)
    .background(Color(white: 0.96))
}
#endif

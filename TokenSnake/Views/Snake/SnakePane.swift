import SwiftUI

struct SnakePane: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let snapshot = store.snake
        let end = Calendar.current.date(byAdding: .day, value: 1, to: store.currentDay) ?? .distantFuture
        let recent = store.entries.filter { $0.totalTokens > 0 && $0.createdAt < end }.prefix(3)
        ScrollView {
            VStack(spacing: 10) {
                Panel(padding: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snapshot.name)
                                    .font(Typography.title(15))
                                    .foregroundStyle(Theme.text)
                                Text("\(snapshot.growth.stage) · \(snapshot.mood.label)")
                                    .font(Typography.caption())
                                    .foregroundStyle(Theme.text2)
                            }
                            Spacer()
                            Text("Lv.\(snapshot.growth.level)")
                                .font(Typography.display(22))
                                .monospacedDigit()
                                .foregroundStyle(snapshot.growth.level >= 50 ? Theme.gold : Theme.accent)
                        }

                        SnakeStage(snapshot: snapshot)
                            .frame(height: 150)

                        HStack(alignment: .firstTextBaseline) {
                            Text("累積吃下")
                                .font(Typography.caption())
                                .foregroundStyle(Theme.text2)
                            Spacer()
                            Text("\(Formatters.compactTokens(snapshot.growth.totalTokens)) tokens")
                                .font(Typography.body(14))
                                .monospacedDigit()
                                .foregroundStyle(Theme.accent)
                        }
                        GlowProgress(progress: snapshot.growth.progress)
                        if let remaining = snapshot.growth.tokensToNextLevel {
                            Text("再吃 \(Formatters.compactTokens(remaining)) tokens → Lv.\(snapshot.growth.level + 1)")
                                .font(Typography.caption())
                                .foregroundStyle(Theme.text2)
                        }
                        Text(storyLine(snapshot))
                            .font(Typography.caption())
                            .foregroundStyle(Theme.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    feedingStat("今日吃下", "\(Formatters.compactTokens(snapshot.todayTokens)) tokens")
                    feedingStat("今日進食", "\(snapshot.todayFedCount) 次")
                }

                if !recent.isEmpty {
                    Panel(padding: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("最近進食")
                                .font(Typography.body(12))
                                .foregroundStyle(Theme.text2)
                            ForEach(recent) { entry in
                                HStack(spacing: 7) {
                                    ProviderBadge(provider: entry.provider)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(entry.model)
                                            .font(Typography.caption())
                                            .foregroundStyle(Theme.text)
                                            .lineLimit(1)
                                        Text("\(entry.source?.label ?? "手動") · \(Formatters.shortDate(entry.createdAt)) \(Formatters.time(entry.createdAt))")
                                            .font(Typography.caption(10))
                                            .foregroundStyle(Theme.text3)
                                    }
                                    Spacer(minLength: 4)
                                    Text("+\(Formatters.compactTokens(entry.totalTokens))")
                                        .font(Typography.body(12))
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }

                Panel(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("近 13 週進食紀錄")
                            .font(Typography.body(12))
                            .foregroundStyle(Theme.text2)
                        UsageHeatmap()
                            .frame(height: 88)
                        Text("顏色代表每日 tokens 用量")
                            .font(Typography.caption(10))
                            .foregroundStyle(Theme.text3)
                    }
                }
            }
        }
    }

    private func feedingStat(_ title: String, _ value: String) -> some View {
        Panel(padding: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typography.caption()).foregroundStyle(Theme.text3)
                Text(value).font(Typography.body(13)).foregroundStyle(Theme.text).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func storyLine(_ snapshot: SnakeSnapshot) -> String {
        switch snapshot.mood {
        case .sleeping:
            "下一筆用量同步後，小蛇就會孵化。"
        case .resting:
            "今天先休息，已累積的成長會保留。"
        case .growing, .legendary:
            "每筆用量自動變成食物，累積 tokens 就會變長、升級。"
        }
    }
}

struct UsageHeatmap: View {
    @Environment(AppStore.self) private var store
    private let weeks = 13
    private let days = 7

    var body: some View {
        let totals = store.dailyTokenTotals
        let today = store.currentDay
        GeometryReader { geo in
            let gap: CGFloat = 3
            let cell = min(
                (geo.size.width - CGFloat(weeks - 1) * gap) / CGFloat(weeks),
                (geo.size.height - CGFloat(days - 1) * gap) / CGFloat(days)
            )
            HStack(alignment: .top, spacing: gap) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: gap) {
                        ForEach(0..<days, id: \.self) { day in
                            let date = HeatmapGrid.date(week: week, day: day, weeks: weeks, today: today)
                            let tokens = totals[date] ?? 0
                            let value = SnakeGrowth.activityValue(tokens: tokens)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(heatmapFill(value, isFuture: date > today))
                                .frame(width: cell, height: cell)
                                .help("\(Formatters.shortDate(date)) · \(Formatters.compactTokens(tokens)) tokens")
                        }
                    }
                }
            }
        }
    }

    private func heatmapFill(_ value: Double, isFuture: Bool) -> Color {
        switch HeatmapPalette.color(value: value, isFuture: isFuture) {
        case .future: Color.white.opacity(0.03)
        case .empty: Color.white.opacity(0.06)
        case .low: Theme.accentDeep.opacity(0.55)
        case .mid: Theme.accent.opacity(0.55)
        case .high: Theme.accent
        }
    }
}

struct SnakeStage: View {
    var snapshot: SnakeSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mealStartedAt: Date?
    @State private var mealTokens = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                drawTrack(context: &context, size: size)
                drawFood(context: &context, size: size, time: time)
                drawSnake(context: &context, size: size, time: time)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.ink.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(snapshot.growth.stage)，等級 \(snapshot.growth.level)，累積 \(snapshot.growth.totalTokens) tokens")
        .onAppear {
            if snapshot.todayTokens > 0 {
                mealTokens = snapshot.latestMealTokens
                mealStartedAt = .now
            }
        }
        .onChange(of: snapshot.growth.totalTokens) { oldValue, newValue in
            if newValue > oldValue {
                mealTokens = newValue - oldValue
                mealStartedAt = .now
            }
        }
    }

    private var speed: Double { snapshot.mood == .resting ? 0.022 : 0.045 }

    private var bodyColor: Color {
        switch snapshot.mood {
        case .sleeping: Theme.text3
        case .resting: Theme.accent.opacity(0.7)
        case .growing: Theme.accent
        case .legendary: Theme.gold
        }
    }

    private func drawTrack(context: inout GraphicsContext, size: CGSize) {
        let rect = StadiumGeometry.rect(in: size)
        var path = Path()
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: rect.height / 2, height: rect.height / 2))
        context.stroke(path, with: .color(Color.white.opacity(0.06)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        context.stroke(path, with: .color(bodyColor.opacity(0.15)), style: StrokeStyle(lineWidth: 1, dash: [2, 7]))
    }

    private func drawFood(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        guard let start = mealStartedAt?.timeIntervalSinceReferenceDate, mealTokens > 0 else { return }
        let elapsed = time - start
        if elapsed >= 0 && elapsed < 1.5 {
            let point = StadiumGeometry.point(progress: start * speed + speed * 1.5, in: StadiumGeometry.rect(in: size))
            let glow = CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
            context.fill(Path(ellipseIn: glow), with: .color(Theme.gold.opacity(0.15)))
            context.fill(Path(ellipseIn: glow.insetBy(dx: 6, dy: 6)), with: .color(Theme.gold))
        }
        if elapsed >= 1.5 && elapsed < 4 {
            let alpha = min(1, (4 - elapsed) / 1.5)
            context.draw(
                Text("+\(Formatters.compactTokens(mealTokens)) tokens")
                    .font(Typography.body(12)).foregroundStyle(Theme.gold.opacity(alpha)),
                at: CGPoint(x: size.width / 2, y: size.height / 2)
            )
        }
    }

    private func drawSnake(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        if snapshot.mood == .sleeping {
            let egg = CGRect(x: size.width / 2 - 18, y: size.height / 2 - 24, width: 36, height: 46)
            context.fill(Path(ellipseIn: egg), with: .color(Theme.surfaceRaised))
            context.stroke(Path(ellipseIn: egg), with: .color(Theme.hairlineStrong), lineWidth: 1)
            context.fill(Path(ellipseIn: egg.insetBy(dx: 10, dy: 14)), with: .color(Theme.accent.opacity(0.35)))
            return
        }

        let track = StadiumGeometry.rect(in: size)
        let count = snapshot.growth.bodySegments
        let headT = time * speed
        for i in (0..<count).reversed() {
            let t = headT - Double(i) * 0.011
            let point = StadiumGeometry.point(progress: t, in: track)
            let radius: CGFloat = i == 0 ? 8.5 : max(3.2, 7.2 - CGFloat(i) * 0.055)
            let segment = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            let alpha = i == 0 ? 1.0 : 0.4 + 0.5 * (1 - Double(i) / Double(count))
            context.fill(Path(ellipseIn: segment), with: .color(bodyColor.opacity(alpha)))
            if i == 0 {
                context.stroke(Path(ellipseIn: segment.insetBy(dx: -2, dy: -2)), with: .color(bodyColor.opacity(0.3)), lineWidth: 3)
                let ahead = StadiumGeometry.point(progress: t + 0.002, in: track)
                let angle = atan2(ahead.y - point.y, ahead.x - point.x)
                for side: CGFloat in [-1, 1] {
                    let eyeX = point.x + cos(angle) * 3 - sin(angle) * side * 3.5
                    let eyeY = point.y + sin(angle) * 3 + cos(angle) * side * 3.5
                    context.fill(Path(ellipseIn: CGRect(x: eyeX - 1.2, y: eyeY - 1.2, width: 2.4, height: 2.4)), with: .color(Theme.ink))
                }
                if let start = mealStartedAt, (1.4...2).contains(time - start.timeIntervalSinceReferenceDate) {
                    let ring = segment.insetBy(dx: -6, dy: -6)
                    context.stroke(Path(ellipseIn: ring), with: .color(Theme.gold.opacity(0.6)), lineWidth: 2)
                }
            }
        }
    }
}

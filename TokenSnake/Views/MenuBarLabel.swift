import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 5) {
            MenuBarSnakeGlyph(mood: store.snake.mood)
                .frame(width: 14, height: 14)
            Text(store.menuBarText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 2)
        .help(menuHelp)
    }

    private var menuHelp: String {
        let price = store.unpricedTodayCount > 0 ? "\(store.unpricedTodayCount) 筆待補費率" : "估算 \(Formatters.currency(store.insights.todayCost))"
        return "TokenSnake · 今日 \(Formatters.compactTokens(store.insights.todayTokens)) · \(price)"
    }
}

struct MenuBarSnakeGlyph: View {
    var mood: SnakeMood

    var body: some View {
        Canvas { context, size in
            let color: Color = {
                switch mood {
                case .sleeping: Theme.text3
                case .resting: Theme.text2
                case .growing: Theme.accent
                case .legendary: Theme.gold
                }
            }()

            let bodyPath = Path { path in
                path.move(to: CGPoint(x: size.width * 0.12, y: size.height * 0.62))
                path.addCurve(
                    to: CGPoint(x: size.width * 0.52, y: size.height * 0.38),
                    control1: CGPoint(x: size.width * 0.18, y: size.height * 0.18),
                    control2: CGPoint(x: size.width * 0.36, y: size.height * 0.90)
                )
                path.addCurve(
                    to: CGPoint(x: size.width * 0.90, y: size.height * 0.42),
                    control1: CGPoint(x: size.width * 0.66, y: size.height * 0.02),
                    control2: CGPoint(x: size.width * 0.78, y: size.height * 0.78)
                )
            }
            context.stroke(bodyPath, with: .color(color), style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))

            let head = CGRect(x: size.width * 0.74, y: size.height * 0.22, width: size.width * 0.24, height: size.height * 0.24)
            context.fill(Path(ellipseIn: head), with: .color(color))
            context.fill(
                Path(ellipseIn: CGRect(x: head.midX - 0.8, y: head.midY - 0.8, width: 1.6, height: 1.6)),
                with: .color(Theme.ink)
            )
        }
    }
}

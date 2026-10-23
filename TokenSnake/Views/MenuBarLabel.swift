import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 5) {
            MenuBarSnakeGlyph(mood: store.snake.mood)
                .frame(width: MenuBarSnakeArtwork.pointSize, height: MenuBarSnakeArtwork.pointSize)
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
        Image(nsImage: MenuBarSnakeArtwork.image)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .accessibilityLabel("小蛇，\(mood.label)")
    }
}

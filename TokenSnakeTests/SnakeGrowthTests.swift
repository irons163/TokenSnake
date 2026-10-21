import Foundation
import Testing
@testable import TokenSnake

struct SnakeGrowthTests {
    @Test(arguments: [
        (0, 1, 1_000_000), (999_999, 1, 1),
        (1_000_000, 2, 3_000_000), (3_999_999, 2, 1),
        (4_000_000, 3, 5_000_000), (9_000_000, 4, 7_000_000)
    ])
    func levelBoundaries(total: Int, level: Int, remaining: Int) {
        let growth = SnakeGrowth(totalTokens: total)
        #expect(growth.level == level)
        #expect(growth.tokensToNextLevel == remaining)
        #expect(growth.progress >= 0 && growth.progress < 1)
    }

    @Test func progressAndBodyLengthComeFromTokens() {
        let first = SnakeGrowth(totalTokens: 2_500_000)
        #expect(first.progress == 0.5)
        let next = SnakeGrowth(totalTokens: 4_000_000)
        #expect(next.bodySegments > first.bodySegments)
        #expect(next.progress == 0)
    }

    @Test func invalidAndVeryLargeTotalsStaySafe() {
        #expect(SnakeGrowth(totalTokens: -1) == SnakeGrowth(totalTokens: 0))
        let largest = SnakeGrowth(totalTokens: Int.max)
        #expect(largest.level > 1)
        #expect(largest.progress == 1)
        #expect(largest.nextLevelTokens == nil)
        #expect(largest.bodySegments == 70)
    }

    @Test func growthStagesAndDailyActivity() {
        #expect(SnakeGrowth(totalTokens: 0).stage == "蛇蛋")
        #expect(SnakeGrowth(totalTokens: 1).stage == "幼蛇")
        #expect(SnakeGrowth(totalTokens: 81_000_000).stage == "長蛇")
        #expect(SnakeGrowth(totalTokens: 576_000_000).stage == "靈蛇")
        #expect(SnakeGrowth(totalTokens: 2_401_000_000).stage == "星蛇")
        #expect(SnakeGrowth.activityValue(tokens: 0) == 0)
        #expect(SnakeGrowth.activityValue(tokens: 100) == 0.25)
        #expect(SnakeGrowth.activityValue(tokens: 1_000_000) == 0.5)
        #expect(SnakeGrowth.activityValue(tokens: 10_000_000) == 0.75)
        #expect(SnakeGrowth.activityValue(tokens: 100_000_000) == 1)
    }
}

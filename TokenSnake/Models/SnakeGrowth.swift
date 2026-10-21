import Foundation

struct SnakeGrowth: Equatable {
    static let tokensPerGrowthUnit = 1_000_000
    let totalTokens: Int
    let level: Int

    init(totalTokens: Int) {
        self.totalTokens = max(0, totalTokens)
        let units = self.totalTokens / Self.tokensPerGrowthUnit
        var root = Int(Double(units).squareRoot())
        while (root + 1) * (root + 1) <= units { root += 1 }
        while root * root > units { root -= 1 }
        level = root + 1
    }

    // Level 2 starts at 1M tokens, level 3 at 4M, level 4 at 9M, etc.
    var levelStartTokens: Int { (level - 1) * (level - 1) * Self.tokensPerGrowthUnit }

    var nextLevelTokens: Int? {
        let result = (level * level).multipliedReportingOverflow(by: Self.tokensPerGrowthUnit)
        return result.overflow ? nil : result.partialValue
    }

    var tokensToNextLevel: Int? { nextLevelTokens.map { $0 - totalTokens } }

    var progress: Double {
        guard let nextLevelTokens else { return 1 }
        return Double(totalTokens - levelStartTokens) / Double(nextLevelTokens - levelStartTokens)
    }

    var bodySegments: Int { min(70, level + 2) }

    var stage: String {
        if totalTokens == 0 { return "蛇蛋" }
        switch level {
        case ..<10: return "幼蛇"
        case ..<25: return "長蛇"
        case ..<50: return "靈蛇"
        default: return "星蛇"
        }
    }

    static func activityValue(tokens: Int) -> Double {
        switch tokens {
        case ...0: 0
        case ..<1_000_000: 0.25
        case ..<10_000_000: 0.5
        case ..<100_000_000: 0.75
        default: 1
        }
    }
}

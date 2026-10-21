import AppKit
import SwiftUI
import Testing
@testable import TokenSnake

@Suite
@MainActor
struct ViewRenderingTests {
    @Test func popoverTabsAndSettingsRender() {
        let (store, _, _) = StoreHarness.make()
        store.loadDemoData()
        render(PopoverRoot(tab: .tokens).environment(store))
        render(PopoverRoot(tab: .snake).environment(store))
        render(PopoverRoot(tab: .tokens, showSettings: true).environment(store))
    }

    @Test func emptyStatesRender() {
        let (store, _, _) = StoreHarness.make()
        store.updateSettings {
            $0.lastProvider = .openai
            $0.lastModel = "missing-model"
        }
        render(TokensPane().environment(store))
        render(SubscriptionSettingsSection().environment(store))
        render(SnakePane().environment(store))
        render(MenuBarLabel().environment(store))
        render(SettingsPane(onClose: {}).environment(store))
        render(LocalSyncSection().environment(store))
        render(ManualEntrySheet(onSave: { _ in }))
        render(SubscriptionEditor(account: Pricing.subscriptionTemplates[0], onSave: { _ in }))
    }

    @Test func filledStatesRender() {
        let (store, _, _) = StoreHarness.make()
        store.loadDemoData()
        store.addEntry(StoreHarness.expensiveEntry())
        render(TokensPane().environment(store))
        render(SubscriptionSettingsSection().environment(store))
        render(SnakePane().environment(store))
        render(MenuBarLabel().environment(store))
        render(SettingsPane(onClose: {}).environment(store))
    }

    @Test func componentsRender() {
        var provider = AIProvider.openai
        var model = "GPT-5"
        render(
            QuickLogCard(provider: Binding(get: { provider }, set: { provider = $0 }), model: Binding(get: { model }, set: { model = $0 })) { _ in }
        )
        render(TokenRow(entry: StoreHarness.cheapEntry(), onDelete: {}))
        render(TokenRow(entry: StoreHarness.cheapEntry(), showsModel: false, onDelete: {}))
        if let group = ModelUsageGroup.groups(from: [StoreHarness.cheapEntry()]).first {
            render(ModelUsageGroupRow(group: group, onDelete: { _ in }))
        }
        render(ProviderBadge(provider: .perplexity))
        render(Sparkline(values: [0, 1, 4, 2, 8]))
        render(Sparkline(values: [0, 0, 0]))
        render(GlowProgress(progress: 0))
        render(GlowProgress(progress: 0.4))
        render(GlowProgress(progress: 1.4, tint: Theme.danger, height: 8))
        render(Chip(title: "Cursor", selected: true, action: {}))
        render(Chip(title: "GPT", symbol: "sparkle", selected: false, flexible: false, action: {}))
        render(Panel { Text("hi") })
        render(GlassBackground().frame(width: 40, height: 40))
        render(UsageHeatmap().environment(StoreHarness.make().0))
        render(SubscriptionCard(account: Pricing.subscriptionTemplates[0]).environment(StoreHarness.make().0))
        render(SubscriptionCard(account: Pricing.subscriptionTemplates[2]).environment(StoreHarness.make().0))
        render(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).frame(width: 20, height: 20))
        render(HideTitleBar())
        render(MenuBarSnakeGlyph(mood: .sleeping))
        render(MenuBarSnakeGlyph(mood: .resting))
        render(MenuBarSnakeGlyph(mood: .growing))
        render(MenuBarSnakeGlyph(mood: .legendary))
    }

    @Test func snakeStagesCoverMoods() {
        for snapshot in [
            SnakeSnapshot(name: "小蛇", growth: SnakeGrowth(totalTokens: 0), todayTokens: 0, todayFedCount: 0),
            SnakeSnapshot(name: "Byte", growth: SnakeGrowth(totalTokens: 100_000_000), todayTokens: 0, todayFedCount: 0),
            SnakeSnapshot(name: "Naga", growth: SnakeGrowth(totalTokens: 100_000_000), todayTokens: 1_000, todayFedCount: 1),
            SnakeSnapshot(name: "青行", growth: SnakeGrowth(totalTokens: 3_000_000_000), todayTokens: 1_000, todayFedCount: 1)
        ] {
            render(SnakeStage(snapshot: snapshot).frame(width: 320, height: 150))
        }
    }

    @Test func appSceneBuilds() {
        let app = TokenSnakeApp()
        _ = app.body
    }

    @Test func themeTypographyExists() {
        _ = Typography.display()
        _ = Typography.title()
        _ = Typography.body()
        _ = Typography.caption()
        _ = Typography.mono()
        _ = Theme.accentGlow
        #expect(Theme.popoverWidth > 0)
        #expect(Theme.popoverHeight > 0)
    }

    private func render<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: Theme.popoverWidth, height: Theme.popoverHeight)
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.fittingSize.width >= 0)
    }
}

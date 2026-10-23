import AppKit
import Testing
@testable import TokenSnake

struct AIBrandTests {
    @Test(arguments: [
        ("gpt-5.6-terra", AIBrand.openai),
        ("claude-opus-5-5", .claude),
        ("deepseek-v4.1-flash-free", .deepseek),
        ("deepseek/deepseek-v4-flash-0731", .deepseek),
        ("gateway/anthropic/claude-opus-5-5", .claude),
        ("  Qwen3.8-Max  ", .qwen),
        ("kimi-k3", .kimi),
        ("GLM-5.3-Flash", .zai),
        ("muse-spark-1.3-contributor", .meta),
        ("meta-llama/llama-3.3-70b", .meta),
        ("Gemini 3 Pro", .gemini),
        ("grok-4", .grok),
        ("sonar-pro", .perplexity)
    ])
    func identifiesModelBrand(model: String, expected: AIBrand) {
        #expect(AIBrand.resolve(model: model, provider: .custom) == expected)
    }

    @Test func modelBrandTakesPrecedenceOverGateway() {
        #expect(AIBrand.resolve(model: "deepseek-v4.1-flash", provider: .openai) == .deepseek)
        #expect(AIBrand.resolve(model: "claude-opus-5-5", provider: .cursor) == .claude)
        #expect(AIBrand.resolve(model: "gpt-5.6-terra", provider: .copilot) == .openai)
    }

    @Test func unknownModelsUseProviderOrNeutralFallback() {
        #expect(AIBrand.resolve(provider: .anthropic) == .claude)
        #expect(AIBrand.resolve(model: "Cursor 包含額度", provider: .cursor) == .cursor)
        #expect(AIBrand.resolve(model: "unknown-model", provider: .copilot) == .copilot)
        #expect(AIBrand.resolve(model: "anonymous-preview", provider: .custom) == .unknown)
        #expect(AIBrand.resolve(model: "my-deepseek-wrapper", provider: .custom) == .unknown)
        #expect(AIBrand.resolve(model: "gptish", provider: .custom) == .unknown)
        #expect(AIBrand.resolve(model: "deepseeker", provider: .custom) == .unknown)
    }

    @MainActor @Test func brandArtworkAndLicenseAreBundled() throws {
        for brand in AIBrand.allCases where brand != .unknown {
            let name = try #require(brand.assetName)
            let image = try #require(NSImage(named: name))
            #expect(image.size.width > 0 && image.size.height > 0)
            // A loadable SVG can still render almost empty if CoreSVG rejects a
            // compact path command. Exercise the actual macOS vector decoder.
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 24,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32
            ))
            let graphics = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            graphics.cgContext.clear(CGRect(x: 0, y: 0, width: 24, height: 24))
            image.draw(in: NSRect(x: 0, y: 0, width: 24, height: 24))
            NSGraphicsContext.restoreGraphicsState()
            let visiblePixels = (0..<24).reduce(0) { count, x in
                count + (0..<24).filter { bitmap.colorAt(x: x, y: $0)!.alphaComponent > 0.5 }.count
            }
            #expect(visiblePixels > 25, "\(brand.displayName) must render a complete mark")
        }
        let notice = try #require(Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"))
        #expect(try String(contentsOf: notice, encoding: .utf8).contains("Copyright (c) 2023 LobeHub"))
    }
}

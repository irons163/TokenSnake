import SwiftUI

enum Theme {
    static let bg = Color(red: 0.055, green: 0.067, blue: 0.058)
    static let surface = Color(red: 0.086, green: 0.106, blue: 0.090)
    static let surfaceRaised = Color(red: 0.118, green: 0.145, blue: 0.118)
    static let ink = Color(red: 0.035, green: 0.043, blue: 0.038)

    static let accent = Color(red: 0.38, green: 0.96, blue: 0.56)
    static let accentDeep = Color(red: 0.10, green: 0.42, blue: 0.28)
    static let accentGlow = Color(red: 0.30, green: 0.90, blue: 0.48).opacity(0.35)
    static let gold = Color(red: 0.96, green: 0.80, blue: 0.38)
    static let danger = Color(red: 0.96, green: 0.40, blue: 0.40)
    static let warning = Color(red: 0.98, green: 0.74, blue: 0.30)

    static let text = Color(red: 0.93, green: 0.97, blue: 0.93)
    static let text2 = Color(red: 0.62, green: 0.72, blue: 0.64)
    static let text3 = Color(red: 0.42, green: 0.50, blue: 0.44)

    static let hairline = Color.white.opacity(0.08)
    static let hairlineStrong = Color.white.opacity(0.14)

    static let popoverWidth: CGFloat = 360
    static let popoverHeight: CGFloat = 540
}

enum Typography {
    static func display(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static func title(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static func body(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    static func caption(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    static func mono(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

struct GlassBackground: View {
    var body: some View {
        ZStack {
            Theme.bg
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .opacity(0.55)
            RadialGradient(
                colors: [Theme.accentDeep.opacity(0.55), .clear],
                center: .topLeading,
                startRadius: 8,
                endRadius: 260
            )
            RadialGradient(
                colors: [Theme.accent.opacity(0.08), .clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 220
            )
        }
        .ignoresSafeArea()
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct Panel<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.surface.opacity(0.92))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Theme.hairlineStrong, Theme.hairline],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
            }
    }
}

struct GlowProgress: View {
    var progress: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.75), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(height, geo.size.width * clamped))
                    .shadow(color: tint.opacity(0.55), radius: 6, y: 0)
            }
        }
        .frame(height: height)
    }
}

struct Chip: View {
    var title: String
    var symbol: String? = nil
    var selected: Bool
    var tint: Color = Theme.accent
    var flexible: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
            }
            .font(Typography.body(12))
            .foregroundStyle(selected ? Theme.ink : Theme.text)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .frame(maxWidth: flexible ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? tint : Theme.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.clear : Theme.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct HideTitleBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.styleMask.insert(.fullSizeContentView)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

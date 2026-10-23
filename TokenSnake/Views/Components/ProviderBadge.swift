import SwiftUI

struct ProviderBadge: View {
    var provider: AIProvider
    var model: String? = nil

    private var brand: AIBrand { AIBrand.resolve(model: model, provider: provider) }

    var body: some View {
        Group {
            if let asset = brand.assetName {
                Image(asset)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            } else {
                Image(systemName: "cpu")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .foregroundStyle(brand.foreground)
        .frame(width: 16, height: 16)
        .frame(width: 22, height: 22)
        .background(Circle().fill(brand.tint))
        .accessibilityLabel(brand.displayName)
        .help(brand.displayName)
    }
}

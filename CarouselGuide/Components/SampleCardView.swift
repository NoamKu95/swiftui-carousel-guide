import SwiftUI

struct SampleCardView: View {
    let item: CarouselItem
    var style: Style = .featured

    enum Style {
        case featured
        case compact
    }

    /// Contrasting fill for glyphs/text on primary/secondary card surfaces.
    private var onFill: Color { Color(.systemBackground) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Opaque base so stacked neighbors never show through translucent gradient stops.
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.primary)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: item.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: item.symbolName)
                .font(.system(size: style == .featured ? 92 : 64, weight: .semibold))
                .foregroundStyle(onFill.opacity(0.22))
                .rotationEffect(.degrees(-8))
                .padding(style == .featured ? 24 : 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(onFill)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(onFill.opacity(0.88))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(style == .featured ? 22 : 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.subtitle)")
    }
}

#Preview {
    SampleCardView(item: SampleData.destinations[0])
        .frame(height: 240)
        .padding()
}

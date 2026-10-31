import SwiftUI

struct SampleCardView: View {
    let item: CarouselItem
    var style: Style = .featured

    enum Style {
        case featured
        case compact
    }

    /// Featured (horizontal) cards use a fixed width:height ratio so finite SwiftUI and
    /// infinite UIKit hosts resolve the **same pixel height** from the same page width.
    /// Compact (vertical) fills the pager’s proposed page frame instead.
    static let featuredAspectRatio: CGFloat = 4.0 / 3.0

    var body: some View {
        let chrome = ZStack(alignment: .bottomLeading) {
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
                .foregroundStyle(.white.opacity(0.18))
                .rotationEffect(.degrees(-8))
                .padding(style == .featured ? 24 : 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(style == .featured ? 22 : 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: item.gradientColors.last?.opacity(0.35) ?? .black.opacity(0.2), radius: 16, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.subtitle)")

        switch style {
        case .featured:
            chrome
                .aspectRatio(Self.featuredAspectRatio, contentMode: .fit)
        case .compact:
            chrome
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    SampleCardView(item: SampleData.destinations[0])
        .frame(width: 320)
        .padding()
}

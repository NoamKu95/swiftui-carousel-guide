import SwiftUI

struct PageIndicatorView: View {
    let count: Int
    let currentIndex: Int
    var axis: CarouselAxis = .horizontal

    var body: some View {
        let stack = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(spacing: 8))

        stack {
            ForEach(0..<count, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == currentIndex ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(
                        width: axis == .horizontal ? (index == currentIndex ? 18 : 7) : 7,
                        height: axis == .vertical ? (index == currentIndex ? 18 : 7) : 7
                    )
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentIndex)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(currentIndex + 1) of \(count)")
        .accessibilityValue("\(currentIndex + 1)")
        .accessibilityAdjustableAction { direction in
            // Parent owns selection; indicator is informational.
            _ = direction
        }
    }
}

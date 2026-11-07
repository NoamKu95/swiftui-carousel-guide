import SwiftUI

/// Page dots that scrub with a **continuous** page position.
///
/// Pass a fractional `progress` (e.g. `2.35`) while the carousel is mid-swipe:
/// the current page’s capsule shrinks / deselects while the destination grows /
/// selects in lockstep. Integer values match the old snap-only behavior.
struct PageIndicatorView: View {
    let count: Int
    /// Continuous index along the pages (wraps for looping carousels).
    var progress: CGFloat
    var axis: CarouselAxis = .horizontal

    private let inactiveSize: CGFloat = 7
    private let activeExtra: CGFloat = 11

    private var roundedIndex: Int {
        guard count > 0 else { return 0 }
        let n = CGFloat(count)
        var x = progress.truncatingRemainder(dividingBy: n)
        if x < 0 { x += n }
        return Int(x.rounded()) % count
    }

    var body: some View {
        let stack = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(spacing: 8))

        stack {
            ForEach(0..<count, id: \.self) { index in
                let amount = selectionAmount(for: index)
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.35))
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(Double(amount)))
                    }
                    .frame(
                        width: axis == .horizontal ? inactiveSize + activeExtra * amount : inactiveSize,
                        height: axis == .vertical ? inactiveSize + activeExtra * amount : inactiveSize
                    )
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(roundedIndex + 1) of \(count)")
        .accessibilityValue("\(roundedIndex + 1)")
        .accessibilityAdjustableAction { direction in
            // Parent owns selection; indicator is informational.
            _ = direction
        }
    }

    /// `1` = fully selected, `0` = fully idle. Linear falloff over one page of
    /// circular distance so two neighbors share the transition during a scrub.
    private func selectionAmount(for index: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let n = CGFloat(count)
        var x = progress.truncatingRemainder(dividingBy: n)
        if x < 0 { x += n }
        var delta = abs(CGFloat(index) - x)
        delta = min(delta, n - delta)
        return max(0, 1 - delta)
    }
}

extension PageIndicatorView {
    /// Snap-only convenience — same as `progress: CGFloat(currentIndex)`.
    init(count: Int, currentIndex: Int, axis: CarouselAxis = .horizontal) {
        self.count = count
        self.progress = CGFloat(currentIndex)
        self.axis = axis
    }
}

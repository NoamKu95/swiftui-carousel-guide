import CoreGraphics

/// Layout math for `StackedInfiniteCarouselView` — kept free of SwiftUI so demos
/// can size containers without importing the full stack view generics.
enum StackCarouselMetrics {
    /// ISO credit-card width ÷ height.
    static let creditCardAspectRatio: CGFloat = 1.586

    static let spacingRatioVertical: CGFloat = 0.55
    /// Tighter gap so a wide horizontal focused card still shows peeks.
    static let spacingRatioHorizontal: CGFloat = 0.30
    /// Worst-case neighbor scale used for container extent (≈ 90° on a 4-ring).
    static let neighborScaleAtOne: CGFloat = 0.88
    static let extentSlackRatio: CGFloat = 0.22
    /// Focused horizontal card width as a fraction of the stage.
    static let horizontalFocusWidthRatio: CGFloat = 0.88
    /// Farthest slot we still draw (matches opacity window in the stack view).
    static let maxVisibleSlot: Int = 2

    /// How far from focus a resting card can sit for this count (capped by what we draw).
    /// Two-item mode only uses the leading peek (one side), so outer = 1.
    static func visibleOuterSlot(itemCount: Int) -> Int {
        guard itemCount > 1 else { return 1 }
        if itemCount == 2 { return 1 }
        return min(maxVisibleSlot, max(itemCount / 2, 1))
    }

    static func spacingRatio(for axis: CarouselAxis, itemCount: Int = 3) -> CGFloat {
        let base = axis == .horizontal ? spacingRatioHorizontal : spacingRatioVertical
        if itemCount <= 1 { return base }
        // Two-slot ring: slightly tighter on vertical so the arc doesn’t dominate.
        if itemCount == 2 {
            return axis == .vertical ? base * 0.9 : base
        }

        // Vertical: pack tighter as count grows so ±1 / ±2 peeks don’t stretch
        // the stage into a tall strip. 3-up keeps the calibrated base look.
        if axis == .vertical {
            let outer = CGFloat(visibleOuterSlot(itemCount: itemCount))
            var pack = 1 / outer // 3-up: 1; 4+: 0.5 so two slots fit like one did
            if itemCount > 4 {
                pack *= 4 / CGFloat(itemCount)
            }
            return base * pack
        }

        // Horizontal: mild tighten only — width is usually the constraint.
        if itemCount >= 4 {
            return base * min(1, 3 / CGFloat(itemCount))
        }
        return base
    }

    /// Card size along the scroll axis (height when vertical, width when horizontal).
    static func cardMainLength(
        forCardCrossAxis crossAxis: CGFloat,
        aspectRatio: CGFloat = creditCardAspectRatio,
        axis: CarouselAxis = .vertical
    ) -> CGFloat {
        axis == .vertical ? crossAxis / aspectRatio : crossAxis * aspectRatio
    }

    /// Container extent along the scroll axis so rest neighbors aren’t clipped.
    static func stackExtent(
        forCardCrossAxis crossAxis: CGFloat,
        aspectRatio: CGFloat = creditCardAspectRatio,
        axis: CarouselAxis = .vertical,
        spacingRatio: CGFloat? = nil,
        itemCount: Int = 3
    ) -> CGFloat {
        let ratio = spacingRatio ?? self.spacingRatio(for: axis, itemCount: itemCount)
        let cardMain = cardMainLength(forCardCrossAxis: crossAxis, aspectRatio: aspectRatio, axis: axis)
        let spacing = cardMain * ratio
        let outer = CGFloat(visibleOuterSlot(itemCount: itemCount))
        let orbitReach = outer * spacing
        let slack = cardMain * extentSlackRatio
        return 2 * orbitReach + cardMain * neighborScaleAtOne + slack
    }

    /// Inverse of `stackExtent` — card cross size that makes the stack fit in `extent`.
    static func cardCrossAxis(
        fittingStackExtent extent: CGFloat,
        aspectRatio: CGFloat = creditCardAspectRatio,
        axis: CarouselAxis = .vertical,
        spacingRatio: CGFloat? = nil,
        itemCount: Int = 3
    ) -> CGFloat {
        let ratio = spacingRatio ?? self.spacingRatio(for: axis, itemCount: itemCount)
        let mainPerCross = axis == .vertical ? (1 / aspectRatio) : aspectRatio
        let outer = CGFloat(visibleOuterSlot(itemCount: itemCount))
        let multiplier = 2 * outer * ratio + neighborScaleAtOne + extentSlackRatio
        return extent / (mainPerCross * multiplier)
    }
}

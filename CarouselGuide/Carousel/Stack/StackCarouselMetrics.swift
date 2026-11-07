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

    /// Resting peek for a card parked opposite the focus (`depth → -1`).
    static let backPeekRatio: CGFloat = 1.0
    /// Extra orbit (as a fraction of spacing) so a 4+ rear card sits *beyond*
    /// the ±1 side peeks instead of directly under them.
    static let backPeekBeyondSideRatio: CGFloat = 0.55

    static func spacingRatio(for axis: CarouselAxis, itemCount: Int = 3) -> CGFloat {
        let base = axis == .horizontal ? spacingRatioHorizontal : spacingRatioVertical
        if itemCount == 2 { return base * 1.15 }
        if itemCount >= 4 { return base * 1.1 }
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
        // Even rings park a rear peek beyond the ±1 side slot — size for that.
        let orbitReach: CGFloat = {
            if itemCount >= 4 {
                return spacing * (1 + backPeekBeyondSideRatio)
            }
            if itemCount == 2 {
                // Mid-swipe puts the two cards on opposite sides at ±spacing.
                return spacing
            }
            return spacing
        }()
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
        let orbitMul: CGFloat = {
            if itemCount >= 4 { return 2 * (1 + backPeekBeyondSideRatio) }
            return 2
        }()
        let multiplier = orbitMul * ratio + neighborScaleAtOne + extentSlackRatio
        return extent / (mainPerCross * multiplier)
    }
}

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

    /// When two items sit at ±90° mid-swipe, orbit = spacing × this (keeps the
    /// farthest separation tighter than a full rest peek).
    static let twoItemMidOrbitFactor: CGFloat = 0.42
    /// Extra orbit pushed onto a card parked near the back (`depth → -1`) so it
    /// peeks instead of vanishing behind the focus (2-item rest, 4-item rear).
    static let backPeekRatio: CGFloat = 1.0

    static func spacingRatio(for axis: CarouselAxis, itemCount: Int = 3) -> CGFloat {
        let base = axis == .horizontal ? spacingRatioHorizontal : spacingRatioVertical
        // Rest peek for the card opposite the focus (2-item / even rings).
        if itemCount == 2 { return base * 1.15 }
        // Four+ rings place ±1 neighbors nearer the equator (larger face).
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
        // Two-item mid-swipe puts cards on opposite sides — size for that span.
        let orbitSpan: CGFloat = {
            if itemCount == 2 {
                return 2 * spacing * twoItemMidOrbitFactor
            }
            return 2 * spacing
        }()
        let slack = cardMain * extentSlackRatio
        return orbitSpan + cardMain * neighborScaleAtOne + slack
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
        let orbitMul: CGFloat = itemCount == 2 ? (2 * twoItemMidOrbitFactor) : 2
        let multiplier = orbitMul * ratio + neighborScaleAtOne + extentSlackRatio
        return extent / (mainPerCross * multiplier)
    }
}

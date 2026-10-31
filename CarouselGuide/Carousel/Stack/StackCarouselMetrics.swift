import CoreGraphics

/// Layout math for `StackedInfiniteCarouselView` — kept free of SwiftUI so demos
/// can size containers without importing the full stack view generics.
enum StackCarouselMetrics {
    /// ISO credit-card width ÷ height.
    static let creditCardAspectRatio: CGFloat = 1.586

    static let spacingRatioVertical: CGFloat = 0.55
    /// Tighter gap so a wide horizontal focused card still shows peeks.
    static let spacingRatioHorizontal: CGFloat = 0.30
    static let neighborScaleAtOne: CGFloat = 0.82
    static let extentSlackRatio: CGFloat = 0.18
    /// Focused horizontal card width as a fraction of the stage.
    static let horizontalFocusWidthRatio: CGFloat = 0.88

    static func spacingRatio(for axis: CarouselAxis) -> CGFloat {
        axis == .horizontal ? spacingRatioHorizontal : spacingRatioVertical
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
        spacingRatio: CGFloat? = nil
    ) -> CGFloat {
        let ratio = spacingRatio ?? self.spacingRatio(for: axis)
        let cardMain = cardMainLength(forCardCrossAxis: crossAxis, aspectRatio: aspectRatio, axis: axis)
        let spacing = cardMain * ratio
        let slack = cardMain * extentSlackRatio
        return 2 * spacing + cardMain * neighborScaleAtOne + slack
    }

    /// Inverse of `stackExtent` — card cross size that makes the stack fit in `extent`.
    static func cardCrossAxis(
        fittingStackExtent extent: CGFloat,
        aspectRatio: CGFloat = creditCardAspectRatio,
        axis: CarouselAxis = .vertical,
        spacingRatio: CGFloat? = nil
    ) -> CGFloat {
        let ratio = spacingRatio ?? self.spacingRatio(for: axis)
        let mainPerCross = axis == .vertical ? (1 / aspectRatio) : aspectRatio
        let multiplier = 2 * ratio + neighborScaleAtOne + extentSlackRatio
        return extent / (mainPerCross * multiplier)
    }
}

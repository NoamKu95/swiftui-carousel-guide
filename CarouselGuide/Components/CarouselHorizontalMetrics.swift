import CoreGraphics

/// Single source of truth for **horizontal** card pixel height.
///
/// Finite SwiftUI and infinite UIKit must use these numbers so Infinite Horizontal
/// and Finite Horizontal demos render the same card size for a given page width.
enum CarouselHorizontalMetrics {
    /// Width ÷ height of the featured card chrome (`SampleCardView` featured).
    static let cardAspectRatio: CGFloat = 4.0 / 3.0

    /// Vertical padding around the card in the horizontal demos (page-indicator clearance).
    static let contentPaddingTop: CGFloat = 8
    static let contentPaddingBottom: CGFloat = 28

    static var contentPaddingVertical: CGFloat {
        contentPaddingTop + contentPaddingBottom
    }

    /// Total page item height: aspect-fit card + demo padding (not the stage height).
    static func pageItemHeight(forPageWidth width: CGFloat) -> CGFloat {
        let cardHeight = width / cardAspectRatio
        return cardHeight + contentPaddingVertical
    }
}

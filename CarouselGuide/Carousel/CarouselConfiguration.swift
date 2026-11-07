import SwiftUI

/// Shared knobs for `CarouselView` (finite + infinite paging).
struct CarouselConfiguration: Equatable, Sendable {
    var axis: CarouselAxis = .horizontal
    var isInfinite: Bool = false
    var autoScrollEnabled: Bool = false
    var autoScrollInterval: TimeInterval = 1.5
    var spacing: CGFloat = 16
    var contentInsets: EdgeInsets = EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)
    var showsIndicators: Bool = false

    /// Leading/top inset used by finite `contentMargins` along the scroll axis.
    var scrollContentMargin: CGFloat {
        contentInsets.mainLeading(axis)
    }

    static let horizontal = CarouselConfiguration(axis: .horizontal)
    static let vertical = CarouselConfiguration(axis: .vertical)
    static let horizontalInfinite = CarouselConfiguration(axis: .horizontal, isInfinite: true)
    static let verticalInfinite = CarouselConfiguration(axis: .vertical, isInfinite: true)
}

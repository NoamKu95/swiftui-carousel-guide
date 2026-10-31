import SwiftUI

enum DemoKind: String, CaseIterable, Identifiable, Hashable {
    case horizontal
    case vertical
    case horizontalInfinite
    case verticalInfinite
    case stackedThreeInfinite
    case stackedThreeInfiniteHorizontal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .horizontal: "Horizontal Carousel"
        case .vertical: "Vertical Carousel"
        case .horizontalInfinite: "Infinite Horizontal"
        case .verticalInfinite: "Infinite Vertical"
        case .stackedThreeInfinite: "3-Up Stack (Vertical)"
        case .stackedThreeInfiniteHorizontal: "3-Up Stack (Horizontal)"
        }
    }

    var subtitle: String {
        switch self {
        case .horizontal:
            "Snapping pages that scroll left and right"
        case .vertical:
            "A paging stack for stories and reels-style layouts"
        case .horizontalInfinite:
            "Seamless looping across a repeating strip"
        case .verticalInfinite:
            "Endless vertical paging without a hard edge"
        case .stackedThreeInfinite:
            "Three cards on a vertical 3D circle — top arcs behind to become bottom"
        case .stackedThreeInfiniteHorizontal:
            "Three cards on a horizontal 3D circle — wide cards, left arcs behind to right"
        }
    }

    var systemImage: String {
        switch self {
        case .horizontal: "rectangle.split.2x1"
        case .vertical: "rectangle.split.1x2"
        case .horizontalInfinite: "infinity.circle"
        case .verticalInfinite: "arrow.up.arrow.down.circle"
        case .stackedThreeInfinite: "rectangle.stack"
        case .stackedThreeInfiniteHorizontal: "rectangle.stack.fill"
        }
    }

    /// True for either stacked peek carousel (not `CarouselView` / UIScrollView).
    var isStackedThreeInfinite: Bool {
        self == .stackedThreeInfinite || self == .stackedThreeInfiniteHorizontal
    }

    var configuration: CarouselConfiguration {
        switch self {
        case .horizontal:
            CarouselConfiguration(axis: .horizontal, isInfinite: false)
        case .vertical:
            CarouselConfiguration(
                axis: .vertical,
                isInfinite: false,
                contentInsets: EdgeInsets(top: 24, leading: 20, bottom: 24, trailing: 20)
            )
        case .horizontalInfinite:
            CarouselConfiguration(axis: .horizontal, isInfinite: true)
        case .verticalInfinite:
            CarouselConfiguration(
                axis: .vertical,
                isInfinite: true,
                contentInsets: EdgeInsets(top: 24, leading: 20, bottom: 24, trailing: 20)
            )
        case .stackedThreeInfinite:
            CarouselConfiguration(axis: .vertical, isInfinite: true)
        case .stackedThreeInfiniteHorizontal:
            CarouselConfiguration(axis: .horizontal, isInfinite: true)
        }
    }

    var items: [CarouselItem] {
        switch self {
        case .horizontal, .horizontalInfinite:
            SampleData.destinations
        case .vertical, .verticalInfinite:
            SampleData.playlists
        case .stackedThreeInfinite, .stackedThreeInfiniteHorizontal:
            SampleData.cardDesigns
        }
    }
}

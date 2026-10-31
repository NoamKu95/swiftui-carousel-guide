import SwiftUI

/// Catalog entry for each root-menu demo.
enum DemoKind: String, CaseIterable, Identifiable, Hashable {
    case horizontal
    case vertical
    case horizontalInfinite
    case verticalInfinite
    case stackedVertical
    case stackedHorizontal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .horizontal: "Horizontal Carousel"
        case .vertical: "Vertical Carousel"
        case .horizontalInfinite: "Infinite Horizontal"
        case .verticalInfinite: "Infinite Vertical"
        case .stackedVertical: "3-Up Stack (Vertical)"
        case .stackedHorizontal: "3-Up Stack (Horizontal)"
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
        case .stackedVertical:
            "Three cards on a vertical 3D circle — top arcs behind to become bottom"
        case .stackedHorizontal:
            "Three cards on a horizontal 3D circle — wide cards, left arcs behind to right"
        }
    }

    var systemImage: String {
        switch self {
        case .horizontal: "rectangle.split.2x1"
        case .vertical: "rectangle.split.1x2"
        case .horizontalInfinite: "infinity.circle"
        case .verticalInfinite: "arrow.up.arrow.down.circle"
        case .stackedVertical: "rectangle.stack"
        case .stackedHorizontal: "rectangle.stack.fill"
        }
    }

    /// Stacked circle demos (not `CarouselView` / UIScrollView).
    var isStacked: Bool {
        self == .stackedVertical || self == .stackedHorizontal
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
        case .stackedVertical:
            CarouselConfiguration(axis: .vertical, isInfinite: true)
        case .stackedHorizontal:
            CarouselConfiguration(axis: .horizontal, isInfinite: true)
        }
    }

    var items: [CarouselItem] {
        switch self {
        case .horizontal, .horizontalInfinite:
            SampleData.destinations
        case .vertical, .verticalInfinite:
            SampleData.playlists
        case .stackedVertical, .stackedHorizontal:
            SampleData.cardDesigns
        }
    }

    var modeCaption: String {
        switch self {
        case .stackedHorizontal:
            return "Drag slowly to watch the circle rotate. The leading card arcs behind the center and emerges on the trailing side."
        case .stackedVertical:
            return "Drag slowly to watch the 3D circle rotate. The top card moves behind the center and emerges as the bottom."
        case .horizontal, .vertical, .horizontalInfinite, .verticalInfinite:
            return configuration.isInfinite
                ? "Auto-advances forever. Dragging pauses playback, then it resumes after a short delay."
                : "Auto-advances through the set and wraps to the start. Dragging pauses, then playback resumes."
        }
    }

    func modeCaption(autoScrollEnabled: Bool) -> String {
        if isStacked {
            if autoScrollEnabled {
                return axis == .horizontal
                    ? "Cards ride a horizontal 3D circle — the left card travels behind and becomes the right. Auto-advances the wheel."
                    : "Cards ride a 3D circle — the top card travels behind and becomes the bottom. Auto-advances the wheel."
            }
            return modeCaption
        }
        return autoScrollEnabled
            ? modeCaption
            : "Manual only — nothing advances until you scroll or swipe."
    }

    var axis: CarouselAxis { configuration.axis }

    var footerLabel: String {
        if isStacked {
            return axis == .horizontal ? "3-up infinite stack · H" : "3-up infinite stack · V"
        }
        return configuration.isInfinite ? "Infinite loop" : "Finite range"
    }

    var footerSystemImage: String {
        if isStacked {
            return axis == .horizontal ? "rectangle.stack.fill" : "rectangle.stack"
        }
        return configuration.isInfinite ? "infinity" : "arrow.left.arrow.right"
    }

    var rowAccent: LinearGradient {
        switch self {
        case .horizontal:
            LinearGradient(colors: [.primary, .secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .vertical:
            LinearGradient(colors: [.secondary, .primary.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .horizontalInfinite:
            LinearGradient(colors: [.primary.opacity(0.85), .secondary.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .verticalInfinite:
            LinearGradient(colors: [.secondary.opacity(0.9), .primary], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .stackedVertical:
            LinearGradient(colors: [.primary.opacity(0.7), .secondary.opacity(0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .stackedHorizontal:
            LinearGradient(colors: [.secondary.opacity(0.75), .primary.opacity(0.9)], startPoint: .leading, endPoint: .trailing)
        }
    }
}

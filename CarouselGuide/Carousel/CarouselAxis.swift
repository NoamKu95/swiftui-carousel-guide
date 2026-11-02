import SwiftUI

/// Scroll direction for paging and stacked carousels.
enum CarouselAxis: String, CaseIterable, Identifiable, Sendable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var scrollAxis: Axis.Set {
        self == .horizontal ? .horizontal : .vertical
    }

    /// Edges for `contentMargins(_:_:for:)` along the scroll axis.
    var marginEdges: Edge.Set {
        self == .horizontal ? .horizontal : .vertical
    }

    var title: String {
        switch self {
        case .horizontal: "Horizontal"
        case .vertical: "Vertical"
        }
    }
}

extension EdgeInsets {
    func mainLeading(_ axis: CarouselAxis) -> CGFloat {
        axis == .horizontal ? leading : top
    }

    func mainTrailing(_ axis: CarouselAxis) -> CGFloat {
        axis == .horizontal ? trailing : bottom
    }
}

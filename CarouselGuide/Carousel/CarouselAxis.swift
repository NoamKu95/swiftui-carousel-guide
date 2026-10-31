import SwiftUI

/// Scroll direction for paging and stacked carousels.
enum CarouselAxis: String, CaseIterable, Identifiable, Sendable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var scrollAxis: Axis.Set {
        self == .horizontal ? .horizontal : .vertical
    }

    var title: String {
        switch self {
        case .horizontal: "Horizontal"
        case .vertical: "Vertical"
        }
    }
}

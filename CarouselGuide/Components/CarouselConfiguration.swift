import SwiftUI

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

// Not Sendable: EdgeInsets is not Sendable under complete concurrency checking.
struct CarouselConfiguration: Equatable {
    var axis: CarouselAxis = .horizontal
    var isInfinite: Bool = false
    var autoScrollEnabled: Bool = false
    var autoScrollInterval: TimeInterval = 3.0
    var spacing: CGFloat = 16
    var contentInsets: EdgeInsets = EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)
    var showsIndicators: Bool = false

    static let horizontal = CarouselConfiguration(axis: .horizontal)
    static let vertical = CarouselConfiguration(axis: .vertical)
    static let horizontalInfinite = CarouselConfiguration(axis: .horizontal, isInfinite: true)
    static let verticalInfinite = CarouselConfiguration(axis: .vertical, isInfinite: true)
}

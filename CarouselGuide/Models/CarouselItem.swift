import SwiftUI

// Not Sendable: SwiftUI.Color is not Sendable under complete concurrency checking.
struct CarouselItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
    let gradientColors: [Color]

    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String,
        symbolName: String,
        gradientColors: [Color]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.gradientColors = gradientColors
    }
}

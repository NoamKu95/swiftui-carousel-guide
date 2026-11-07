import SwiftUI

enum SampleData {
    static let destinations: [CarouselItem] = [
        CarouselItem(
            id: "kyoto",
            title: "Kyoto Temples",
            subtitle: "Misty mornings and vermillion gates",
            symbolName: "building.columns.fill",
            gradientColors: [.primary, .secondary]
        ),
        CarouselItem(
            id: "lisbon",
            title: "Lisbon Hills",
            subtitle: "Trams, tiles, and Atlantic light",
            symbolName: "tram.fill",
            gradientColors: [.secondary, .primary.opacity(0.75)]
        ),
        CarouselItem(
            id: "reykjavik",
            title: "Reykjavík Nights",
            subtitle: "Aurora above black sand beaches",
            symbolName: "moon.stars.fill",
            gradientColors: [.primary.opacity(0.92), .secondary.opacity(0.7)]
        ),
        CarouselItem(
            id: "marrakech",
            title: "Marrakech Souks",
            subtitle: "Spices, lanterns, and courtyard hush",
            symbolName: "flame.fill",
            gradientColors: [.secondary.opacity(0.95), .primary]
        ),
        CarouselItem(
            id: "vancouver",
            title: "Vancouver Coast",
            subtitle: "Evergreens meeting the Pacific",
            symbolName: "water.waves",
            gradientColors: [.primary.opacity(0.8), .secondary]
        ),
        CarouselItem(
            id: "seoul",
            title: "Seoul Evenings",
            subtitle: "Neon alleys and quiet hanok lanes",
            symbolName: "sparkles",
            gradientColors: [.secondary, .primary.opacity(0.85)]
        )
    ]

    static let playlists: [CarouselItem] = [
        CarouselItem(
            id: "focus",
            title: "Deep Focus",
            subtitle: "Ambient loops for long sessions",
            symbolName: "brain.head.profile",
            gradientColors: [.primary, .secondary.opacity(0.8)]
        ),
        CarouselItem(
            id: "sunrise",
            title: "Sunrise Run",
            subtitle: "Percussive energy, rising tempo",
            symbolName: "figure.run",
            gradientColors: [.secondary, .primary.opacity(0.7)]
        ),
        CarouselItem(
            id: "late",
            title: "Late Drive",
            subtitle: "Soft synths for empty roads",
            symbolName: "car.fill",
            gradientColors: [.primary.opacity(0.9), .secondary]
        ),
        CarouselItem(
            id: "kitchen",
            title: "Kitchen Radio",
            subtitle: "Jazz standards while you cook",
            symbolName: "fork.knife",
            gradientColors: [.secondary.opacity(0.85), .primary.opacity(0.8)]
        ),
        CarouselItem(
            id: "rain",
            title: "Rain Window",
            subtitle: "Piano sketches for grey afternoons",
            symbolName: "cloud.rain.fill",
            gradientColors: [.primary.opacity(0.7), .secondary.opacity(0.9)]
        )
    ]

    /// Card-design picks for the stacked demos.
    /// IDs must be unique — `ForEach` keyed by `id` will drop duplicates.
    /// Gradients stay fully opaque so the focused card never reveals neighbors through fill.
    static let cardDesigns: [CarouselItem] = [
        CarouselItem(
            id: "card-onyx",
            title: "Onyx",
            subtitle: "Matte black with subtle grain",
            symbolName: "creditcard.fill",
            gradientColors: [.blue, .blue]
        ),
        CarouselItem(
            id: "card-sand",
            title: "Sand",
            subtitle: "Warm neutral for everyday spend",
            symbolName: "creditcard.fill",
            gradientColors: [.pink, .pink]
        ),
        CarouselItem(
            id: "card-slate",
            title: "Slate",
            subtitle: "Cool tone with sharp contrast",
            symbolName: "creditcard.fill",
            gradientColors: [.purple, .purple]
        ),
        CarouselItem(
            id: "card-slate2",
            title: "Card 4",
            subtitle: "Card 4",
            symbolName: "creditcard.fill",
            gradientColors: [.yellow, .yellow]
        ),
        CarouselItem(
            id: "card-slate3",
            title: "Card 5",
            subtitle: "Card 5",
            symbolName: "creditcard.fill",
            gradientColors: [.green, .green]
        )
    ]
}

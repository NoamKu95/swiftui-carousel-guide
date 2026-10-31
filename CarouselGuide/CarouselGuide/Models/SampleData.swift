import SwiftUI

enum SampleData {
    static let destinations: [CarouselItem] = [
        CarouselItem(
            id: "kyoto",
            title: "Kyoto Temples",
            subtitle: "Misty mornings and vermillion gates",
            symbolName: "building.columns.fill",
            gradientColors: [Color(hex: 0x1F4E5F), Color(hex: 0x79A8A9)]
        ),
        CarouselItem(
            id: "lisbon",
            title: "Lisbon Hills",
            subtitle: "Trams, tiles, and Atlantic light",
            symbolName: "tram.fill",
            gradientColors: [Color(hex: 0xC46B3A), Color(hex: 0xF2C14E)]
        ),
        CarouselItem(
            id: "reykjavik",
            title: "Reykjavík Nights",
            subtitle: "Aurora above black sand beaches",
            symbolName: "moon.stars.fill",
            gradientColors: [Color(hex: 0x0B1D36), Color(hex: 0x3D84A8)]
        ),
        CarouselItem(
            id: "marrakech",
            title: "Marrakech Souks",
            subtitle: "Spices, lanterns, and courtyard hush",
            symbolName: "flame.fill",
            gradientColors: [Color(hex: 0x8C2F39), Color(hex: 0xD4A373)]
        ),
        CarouselItem(
            id: "vancouver",
            title: "Vancouver Coast",
            subtitle: "Evergreens meeting the Pacific",
            symbolName: "water.waves",
            gradientColors: [Color(hex: 0x1B4332), Color(hex: 0x74C69D)]
        ),
        CarouselItem(
            id: "seoul",
            title: "Seoul Evenings",
            subtitle: "Neon alleys and quiet hanok lanes",
            symbolName: "sparkles",
            gradientColors: [Color(hex: 0x3A0CA3), Color(hex: 0xF72585)]
        )
    ]

    static let playlists: [CarouselItem] = [
        CarouselItem(
            id: "focus",
            title: "Deep Focus",
            subtitle: "Ambient loops for long sessions",
            symbolName: "brain.head.profile",
            gradientColors: [Color(hex: 0x14213D), Color(hex: 0x4361EE)]
        ),
        CarouselItem(
            id: "sunrise",
            title: "Sunrise Run",
            subtitle: "Percussive energy, rising tempo",
            symbolName: "figure.run",
            gradientColors: [Color(hex: 0xFF6B35), Color(hex: 0xF7C59F)]
        ),
        CarouselItem(
            id: "late",
            title: "Late Drive",
            subtitle: "Soft synths for empty roads",
            symbolName: "car.fill",
            gradientColors: [Color(hex: 0x22223B), Color(hex: 0x4A4E69)]
        ),
        CarouselItem(
            id: "kitchen",
            title: "Kitchen Radio",
            subtitle: "Jazz standards while you cook",
            symbolName: "fork.knife",
            gradientColors: [Color(hex: 0x6A994E), Color(hex: 0xA7C957)]
        ),
        CarouselItem(
            id: "rain",
            title: "Rain Window",
            subtitle: "Piano sketches for grey afternoons",
            symbolName: "cloud.rain.fill",
            gradientColors: [Color(hex: 0x495057), Color(hex: 0xADB5BD)]
        )
    ]
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

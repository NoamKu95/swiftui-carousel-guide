# SwiftUI Carousel Guide

Companion iOS demo for the Medium article on building polished SwiftUI carousels — finite and infinite, horizontal and vertical, with auto-scroll and manual control.

**Repo:** https://github.com/NoamKu95/swiftui-carousel-guide  
**Requires:** Xcode 15+, iOS 17 SDK, a Mac.

## Open & run

1. Clone this repository.
2. Open `CarouselGuide.xcodeproj` in Xcode.
3. Select an iPhone simulator (or a device).
4. Press **Run** (`⌘R`).

No CocoaPods/SPM packages are required — the app is pure SwiftUI.

## Demo map

The root menu lists four carousel kinds. Each demo page has an **Auto / Manual** segmented control (8 combinations total):

| Demo | Axis | Looping | Sample content |
|------|------|---------|----------------|
| Horizontal Carousel | Horizontal | Finite | Travel destinations |
| Vertical Carousel | Vertical | Finite | Playlists |
| Infinite Horizontal | Horizontal | Seamless loop | Travel destinations |
| Infinite Vertical | Vertical | Seamless loop | Playlists |

On **Auto**, the carousel advances on an adjustable interval, pauses while you drag, then resumes. On **Manual**, nothing auto-advances.

## Project structure

```
CarouselGuide/
├── CarouselGuideApp.swift          # App entry
├── Models/
│   ├── CarouselItem.swift
│   └── SampleData.swift
├── Components/
│   ├── CarouselConfiguration.swift # Axis, looping, auto-scroll knobs
│   ├── CarouselView.swift          # Shared pager: finite + infinite via scrollPosition
│   ├── AutoScrollController.swift  # Pause / resume timer
│   ├── SampleCardView.swift
│   └── PageIndicatorView.swift
└── Screens/
    ├── DemoKind.swift
    ├── DemoMenuView.swift          # Root navigation list
    └── CarouselDemoView.swift      # Per-demo page with Auto/Manual
```

### Component API (quick look)

```swift
CarouselView(
    items: destinations,
    configuration: CarouselConfiguration(
        axis: .horizontal,
        isInfinite: true,
        autoScrollEnabled: true,
        autoScrollInterval: 3
    ),
    selection: $selectedID
) { item in
    SampleCardView(item: item)
}
```

## Guide concepts

This repo implements the patterns in [`GUIDE.md`](./GUIDE.md) (Medium Articles project path: `docs/swiftui-carousels-guide.md`):

- Snapping with `scrollTargetBehavior(.viewAligned)` and `scrollPosition(id:)`
- Infinite looping via a triple-buffered item list + silent recenter
- Auto-scroll that yields to user interaction
- Accessibility labels, selected traits, and Dynamic Type–friendly typography

## License

Sample code for educational use with the Medium Articles project.

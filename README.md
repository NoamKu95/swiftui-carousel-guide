# SwiftUI Carousel Guide

Interview-ready iOS sample that demonstrates **six** carousel patterns in one app:

1. Finite horizontal  
2. Finite vertical  
3. Infinite horizontal (UIKit pager)  
4. Infinite vertical (UIKit pager)  
5. 3D infinite vertical (circle stack)  
6. 3D infinite horizontal (circle stack)  

Each demo supports **Auto** and **Manual** modes with pause-on-drag.

**Repo:** https://github.com/NoamKu95/swiftui-carousel-guide  
**Requires:** Xcode 15+, iOS 17 SDK

## Run

1. Open `CarouselGuide.xcodeproj`
2. Pick an iPhone simulator
3. Run (`⌘R`)

No SPM / CocoaPods dependencies.

## Architecture

Reusable carousel toolkit is separated from the demo shell:

```
CarouselGuide/
├── App/                         # @main entry
├── Carousel/                    # ← drop into another app
│   ├── CarouselAxis.swift
│   ├── CarouselConfiguration.swift
│   ├── AutoScrollController.swift
│   ├── CarouselView.swift       # finite + infinite facade
│   ├── FiniteCarouselLayout.swift
│   ├── PageIndicatorView.swift
│   ├── Infinite/
│   │   ├── InfinitePagingScrollView.swift
│   │   └── InfinitePagingController.swift
│   └── Stack/
│       ├── StackCarouselMetrics.swift
│       └── StackedInfiniteCarouselView.swift
├── Demo/                        # sample screens + data only
│   ├── Models/
│   ├── Components/
│   └── Screens/
└── Resources/
```

| Concern | Type | Notes |
|---------|------|--------|
| Finite paging | `CarouselView` → `FiniteCarouselLayout` | SwiftUI `scrollTargetBehavior` |
| Infinite paging | `CarouselView` → `InfinitePagingScrollView` | Triple-buffer + `setContentOffset` |
| 3-up circle | `StackedInfiniteCarouselView` | Continuous ring `progress` |
| Auto-scroll | `AutoScrollController` | Shared timer + resume delay |
| Layout math | `StackCarouselMetrics` | Axis-aware sizing helpers |

### Drop-in usage

`CarouselView` takes items, a `CarouselConfiguration`, selection, and a card builder. Axis / infinite / auto-scroll / interval / insets all live on the configuration (the demo builds it from `DemoKind` + the Auto/Manual controls):

```swift
var configuration = CarouselConfiguration(
    axis: .horizontal,
    isInfinite: true,
    autoScrollEnabled: true,
    autoScrollInterval: 3
)
CarouselView(
    items: destinations,
    configuration: configuration,
    selection: $selectedID
) { item in
    SampleCardView(item: item, style: .featured)
        .padding(.bottom, 28)
}
```

The 3D stack is a separate API — it needs axis, aspect ratio, and explicit auto-scroll hooks:

```swift
StackedInfiniteCarouselView(
    items: cardDesigns,
    currentIndex: $index,
    axis: .vertical,
    cardAspectRatio: StackCarouselMetrics.creditCardAspectRatio,
    autoAdvanceTick: autoScroll.tick,
    autoScrollEnabled: true,
    onUserDrag: { autoScroll.pauseForUserInteraction() }
) { item in
    SampleCardView(item: item, style: .featured)
}
.frame(height: StackCarouselMetrics.stackExtent(forCardCrossAxis: width))
```

## Demo map

| Demo | Axis | Looping | Content |
|------|------|---------|---------|
| Horizontal Carousel | H | Finite | Destinations |
| Vertical Carousel | V | Finite | Playlists |
| Infinite Horizontal | H | Seamless | Destinations |
| Infinite Vertical | V | Seamless | Playlists |
| 3D Infinite Vertical | V circle | Infinite · 3 | Card designs |
| 3D Infinite Horizontal | H circle | Infinite · 3 | Card designs |

## Guide

Deep-dive patterns and trade-offs live in [`GUIDE.md`](./GUIDE.md).

## License

Sample code for educational / interview use.

# Building Polished Carousels in SwiftUI (Finite, Infinite, Auto & Manual)

SwiftUI finally gives us first-class paging primitives — `scrollTargetBehavior`, `scrollPosition`, and `containerRelativeFrame` — that feel as crisp as UIKit’s `UICollectionView` without dropping to a representable. This guide walks through the carousel shapes you’ll ship in real apps, each with **auto-scroll** and **manual** modes:

1. Regular horizontal carousel  
2. Regular vertical carousel  
3. Horizontal infinite (seamless loop)  
4. Vertical infinite (seamless loop)  
5. **3-up infinite stack** — center card focused, neighbors peek with scale (card-picker style)

The first four share `CarouselView`; the 3-up stack is `StackedInfiniteCarouselView`. All live in the companion demo app.

> **Companion app:** https://github.com/NoamKu95/swiftui-carousel-guide — open `CarouselGuide.xcodeproj` (iOS 17+) and explore each demo from the root menu. Every page has an Auto / Manual control.

---

## Mental model

A carousel is three concerns stacked on top of a `ScrollView`:

| Concern | SwiftUI lever |
|--------|----------------|
| Page size & spacing | `containerRelativeFrame` + `spacing` |
| Snap / paging feel | `scrollTargetBehavior(.viewAligned)` + `scrollTargetLayout()` |
| Programmatic selection | `scrollPosition(id:)` bound to an item id |
| Auto-advance | A timer that writes the next id into that binding |
| Infinite loop | Repeat the dataset and silently recenter onto the middle copy |

Get those right and horizontal vs vertical is mostly an axis swap. Finite vs infinite is an item-buffer strategy.

---

## Shared configuration

Keep knobs in one place so demos (and production screens) stay consistent:

```swift
enum CarouselAxis {
    case horizontal, vertical

    var scrollAxis: Axis.Set {
        self == .horizontal ? .horizontal : .vertical
    }
}

struct CarouselConfiguration {
    var axis: CarouselAxis = .horizontal
    var isInfinite: Bool = false
    var autoScrollEnabled: Bool = false
    var autoScrollInterval: TimeInterval = 3
    var spacing: CGFloat = 16
    var contentInsets: EdgeInsets = EdgeInsets(
        top: 8, leading: 20, bottom: 8, trailing: 20
    )
}
```

The public view looks like this:

```swift
CarouselView(
    items: destinations,
    configuration: .init(axis: .horizontal, autoScrollEnabled: true),
    selection: $selectedID
) { item in
    DestinationCard(item: item)
}
```

One component, eight behaviors — driven by `axis`, `isInfinite`, and `autoScrollEnabled`.

---

## 1. Regular horizontal carousel

Use this for featured content, onboarding, product shelves — anywhere the set has a real start and end.

### Core layout

```swift
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: configuration.spacing) {
        ForEach(items) { item in
            content(item)
                .containerRelativeFrame(.horizontal)
                .id(item.id)
        }
    }
    .scrollTargetLayout()
}
.scrollTargetBehavior(.viewAligned)
.scrollPosition(id: $selection)
.contentMargins(.horizontal, 20, for: .scrollContent)
```

**Why this snaps cleanly**

- `scrollTargetLayout()` marks each child as a valid resting place.  
- `.viewAligned` parks the scroll view so a target lines up with the visible frame.  
- `scrollPosition(id:)` gives you a binding you can drive from a timer, page dots, or deep links.  
- `contentMargins` insets the first/last page without breaking alignment math.

### Manual vs auto

Manual is the default: the user owns the scroll view. For auto-scroll, advance the binding on a timer:

```swift
func advance() {
    guard let current = selection,
          let index = items.firstIndex(where: { $0.id == current }) else { return }

    let next = items[(index + 1) % items.count].id
    withAnimation(.smooth(duration: 0.55)) {
        selection = next
    }
}
```

Finite carousels can either wrap (`% count`) or stop at the last page. The demo wraps so Auto mode keeps moving; Manual mode never calls `advance()`.

---

## 2. Regular vertical carousel

Same recipe — swap the axis. Great for story viewers, workout steps, or playlist browsers.

```swift
ScrollView(.vertical, showsIndicators: false) {
    VStack(spacing: configuration.spacing) {
        ForEach(items) { item in
            content(item)
                .containerRelativeFrame(.vertical)
                .id(item.id)
        }
    }
    .scrollTargetLayout()
}
.scrollTargetBehavior(.viewAligned)
.scrollPosition(id: $selection)
.contentMargins(.vertical, 24, for: .scrollContent)
```

Tips that make vertical feel intentional:

- Give cards a slightly more compact visual style — tall pages amplify empty space.  
- Put page indicators on the **trailing** edge (a vertical capsule stack) so they don’t fight the title.  
- Prefer larger vertical insets so the active card breathes inside the safe area.

---

## 3. Horizontal infinite carousel

“Infinite” means the user never hits a hard stop. The classic SwiftUI approach:

1. Render the dataset **three times** (copies `0`, `1`, `2`).  
2. Start (and stay) on copy `1` — the middle band.  
3. Whenever the settled page lands on copy `0` or `2`, jump back to the matching item in copy `1` **without animation**.

```swift
struct LoopedItem<Item: Identifiable & Hashable>: Identifiable, Hashable {
    let copy: Int
    let item: Item
    var id: String { "\(copy)-\(item.id)" }
}

var loopedItems: [LoopedItem<Item>] {
    (0..<3).flatMap { copy in
        items.map { LoopedItem(copy: copy, item: $0) }
    }
}
```

Wire selection through a *loop* id while exposing the real item id to your UI:

```swift
// Infinite auto-scroll: use UIScrollView (UIViewControllerRepresentable).
// Triple-buffer pages; auto-advance must move contentOffset with animation:
scrollView.setContentOffset(nextPageOffset, animated: true)

// After the animation ends, silently recenter onto the middle copy if needed:
scrollView.setContentOffset(middleCopyOffset, animated: false)
```

**Why infinite auto looked like a card swap (including after SwiftUI `scrollTo` attempts):** manual infinite already scrolled via gesture physics. Programmatic SwiftUI `scrollPosition` / `ScrollViewProxy.scrollTo` under `withAnimation` still **snapped** to the next looped page for the infinite layout (especially noticeable on **vertical**), so the card appeared to replace in place. Finite auto works because it animates a small non-looping `scrollPosition` id set. **Fix used in the companion app:** infinite mode is a UIKit pager (`InfinitePagingScrollView`) that advances with `setContentOffset(_:animated:)` on both axes; finite stays pure SwiftUI. Verify by watching neighboring cards **slide**, matching finite vertical auto.

**When not to use infinite:** short catalogs (2–3 items) where looping feels gimmicky, or content with a meaningful “end” (checkout steps, onboarding).

---

## 4. Vertical infinite carousel

Identical buffering strategy on the vertical axis. This is the pattern behind endless story/reel viewers when your data is a rotating set rather than a network page.

```swift
ScrollView(.vertical) {
    VStack(spacing: spacing) {
        ForEach(loopedItems) { looped in
            content(looped.item)
                .containerRelativeFrame(.vertical)
                .id(looped.id)
        }
    }
    .scrollTargetLayout()
}
.scrollTargetBehavior(.viewAligned)
.scrollPosition(id: $loopSelection)
```

Same UIKit `setContentOffset(_:animated:)` pager as horizontal infinite — only the scroll axis changes. Soft haptics on auto-advance help vertical paging feel deliberate without shouting.

---

## 5. 3-up infinite stack (peek + scale)

Full-page paging is wrong when the product wants **three cards visible** — a focused center with scaled neighbors (card design pickers, cover-flow-ish stacks). Don’t use `ScrollView` paging here: drive a small window of virtual offsets (`-2…+2`) with transforms:

```swift
let pageOffset = CGFloat(virtualOffset) + dragFraction
let translationY = pageOffset * interCardSpacing   // ~0.55 × cardHeight
let scale = 1 - min(abs(pageOffset) * 0.15, 0.30)
```

Cards stay fully opaque (depth via scale + zIndex only). Infinite looping uses a large virtual index (remap after settle so `dragOffset = ±pageExtent` becomes `index ± 1, dragOffset = 0` with no jump). Size with `StackedInfiniteCarouselView.stackExtent(…)` so the container fits the center card plus ±1 neighbors — don’t clip them.

---

## Auto-scroll that respects the user

A carousel that fights the finger is a bug. Own pause/resume in a small controller:

```swift
@MainActor
final class AutoScrollController: ObservableObject {
    @Published private(set) var tick: UInt64 = 0
    @Published private(set) var isPausedByUserInteraction = false

    private var timer: AnyCancellable?
    private var resumeWorkItem: DispatchWorkItem?

    func configure(enabled: Bool, interval: TimeInterval) { /* rebuild timer */ }

    func pauseForUserInteraction(resumeAfter: TimeInterval = 2.4) {
        isPausedByUserInteraction = true
        resumeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.isPausedByUserInteraction = false
            self?.rebuildTimer()
        }
        resumeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + resumeAfter, execute: work)
        rebuildTimer()
    }
}
```

Hook drag state with a simultaneous gesture (or `scrollPhase` on newer OS versions):

```swift
.simultaneousGesture(
    DragGesture(minimumDistance: 4)
        .onChanged { _ in isDragging = true }
        .onEnded { _ in isDragging = false }
)
.onChange(of: isDragging) { _, dragging in
    if dragging { autoScroll.pauseForUserInteraction() }
}
```

Rules of thumb:

- **Manual mode** never starts the timer.  
- **Auto mode** pauses on drag and resumes after a short idle delay.  
- Advancing should use `withAnimation` so `scrollPosition` interpolates instead of hard-cutting.  
- A soft impact haptic on auto-advance sells the motion; skip it on manual snaps (the scroll physics already give feedback).

---

## Page indicators & accessibility

Indicators are status, not a second scroll view:

```swift
PageIndicatorView(
    count: items.count,
    currentIndex: currentIndex,
    axis: configuration.axis
)
```

Accessibility checklist that pays off immediately:

- Combine title + subtitle on each card (`accessibilityElement(children: .combine)`).  
- Mark the selected page with `.accessibilityAddTraits(.isSelected)`.  
- Expose “Page *n* of *m*” on the indicator.  
- Prefer system fonts and avoid fixed-height text boxes so Dynamic Type can grow.  
- Don’t rely on color alone — pair the indicator width/height change with a clear accessibility value.

VoiceOver users typically swipe through cards as regular elements; keep the carousel a containable group rather than a single custom rotor unless you have a strong reason.

---

## Putting it together in a demo screen

Each demo page in the companion app shares one screen: a segmented **Auto / Manual** control, optional interval slider, the `CarouselView`, and a footer showing finite vs infinite plus the current index.

```swift
struct CarouselDemoView: View {
    let kind: DemoKind
    @State private var autoScrollEnabled = true
    @State private var selection: String?

    private var configuration: CarouselConfiguration {
        var config = kind.configuration
        config.autoScrollEnabled = autoScrollEnabled
        return config
    }

    var body: some View {
        VStack {
            Picker("Scroll mode", selection: $autoScrollEnabled) {
                Text("Auto").tag(true)
                Text("Manual").tag(false)
            }
            .pickerStyle(.segmented)

            CarouselView(
                items: kind.items,
                configuration: configuration,
                selection: $selection
            ) { item in
                SampleCardView(item: item)
            }
        }
    }
}
```

That single toggle is what turns four kinds into eight modes without duplicating layout code.

---

## Implementation checklist

Before you ship a carousel:

- [ ] Snap feels locked — no half-page rests at normal flick speeds  
- [ ] First and last pages (finite) aren’t clipped by home indicator / notch  
- [ ] Infinite recenter is invisible (test by flinging quickly across a seam)  
- [ ] Auto-scroll pauses on interaction and resumes cleanly  
- [ ] Manual mode never auto-advances  
- [ ] Rotation / Split View still page-aligns (relying on `containerRelativeFrame` helps)  
- [ ] VoiceOver reads card content; page position is announced somehow  
- [ ] Reduced Motion: consider shortening or disabling auto-scroll animations when `accessibilityReduceMotion` is on

---

## What to steal from the companion app

| File | Role |
|------|------|
| `CarouselView.swift` | Finite SwiftUI layout + wires infinite UIKit pager |
| `InfinitePagingScrollView.swift` | Infinite H/V pager via animated `contentOffset`. H pages fill the offered stage (same pageSize as finite); V lean path unchanged. |
| `StackedInfiniteCarouselView.swift` | 3-up infinite peek stack (scale / opacity / zIndex by page offset) |
| `AutoScrollController.swift` | Timer lifecycle with resume delay |
| `CarouselConfiguration.swift` | Shared knobs / axis helpers |
| `CarouselDemoView.swift` | Auto/Manual UX pattern |
| `SampleCardView.swift` | Fills the page frame it’s given |

Clone the repo, run the eight demos, then lift `CarouselView` into your project. Start with a finite horizontal shelf; add infinite and auto-scroll only when the product story needs them.

Ship carousels that feel inevitable — not clever.

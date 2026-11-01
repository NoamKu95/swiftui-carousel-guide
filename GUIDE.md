# Building Carousels in SwiftUI — Finite, Infinite, Auto & 3D Stack

A practical guide to the carousel shapes you actually ship: finite and infinite paging (horizontal + vertical), auto vs manual playback, and a 3-up “3D circle” stack. We’ll build each piece step by step, and I’ll call out **why** that piece exists — not just what to paste.

Complete code: https://github.com/NoamKu95/swiftui-carousel-guide  
Open `CarouselGuide.xcodeproj` (iOS 17+) and run the six demos from the root menu.

### What will you learn?

1. How to build a snapping finite carousel in pure SwiftUI (horizontal & vertical).
2. Why infinite auto-scroll needs a UIKit `UIScrollView` pager — and how to wire it.
3. How to pause/resume auto-scroll without fighting the user’s finger.
4. How to build a 3D infinite stack (center + neighbors) that rotates as a circle on either axis.

### Pre-required knowledge

1. Basic SwiftUI (`ScrollView`, `@State`, `@Binding`, generics).
2. Comfortable reading a small `UIViewControllerRepresentable`.

---

## Starting point

A carousel is not “a fancy `ScrollView`.” It’s three jobs that must stay in sync:

1. **Page size** — each card fills a predictable slot.
2. **Snap** — a flick rests on a page, not halfway between two.
3. **Selection** — something outside the scroll view (timer, dots, deep link) can move the page.

Finite vs infinite is a data strategy. Horizontal vs vertical is mostly an axis swap. Auto vs manual is whether a timer is allowed to write selection.

Reusable toolkit in the repo lives under `CarouselGuide/Carousel/`. Demo chrome is under `CarouselGuide/Demo/`.

---

## Step 1 — Shared configuration

Keep every knob in one value type so demos (and production screens) don’t fork.

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
    var autoScrollInterval: TimeInterval = 3.0
    var spacing: CGFloat = 16
    var contentInsets: EdgeInsets = EdgeInsets(
        top: 8, leading: 20, bottom: 8, trailing: 20
    )
    var showsIndicators: Bool = false
}
```
*(From `Carousel/CarouselConfiguration.swift` + `Carousel/CarouselAxis.swift`.)*

**Why?** One component can express eight product modes (`axis` × `isInfinite` × auto/manual) without duplicating layout code. When a designer asks “can this shelf loop?”, you flip a flag instead of rewriting the screen.

Public call site:

```swift
CarouselView(
    items: destinations,
    configuration: .init(axis: .horizontal, autoScrollEnabled: true),
    selection: $selectedID
) { item in
    DestinationCard(item: item)
}
```

---

## Step 2 — Finite snapping carousel (pure SwiftUI)

Use this when the set has a real start and end: featured shelves, onboarding pages, product strips.

In the companion app this is `Carousel/FiniteCarouselLayout.swift` — the engine `CarouselView` uses whenever `isInfinite == false`.

### Layout

```swift
struct FiniteCarouselLayout<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    let configuration: CarouselConfiguration
    @Binding var selection: Item.ID?
    @Binding var isDragging: Bool
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        GeometryReader { proxy in
            let pageSize = pageSize(in: proxy.size)

            ScrollView(configuration.axis.scrollAxis, showsIndicators: configuration.showsIndicators) {
                contentStack(pageSize: pageSize)
                    .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selection)
            .contentMargins(
                configuration.axis == .horizontal ? .horizontal : .vertical,
                configuration.axis == .horizontal
                    ? configuration.contentInsets.leading
                    : configuration.contentInsets.top,
                for: .scrollContent
            )
            .simultaneousGesture(dragGesture)
        }
    }

    @ViewBuilder
    private func contentStack(pageSize: CGSize) -> some View {
        let layout = configuration.axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: configuration.spacing))
            : AnyLayout(VStackLayout(spacing: configuration.spacing))

        layout {
            ForEach(items) { item in
                content(item)
                    .frame(
                        width: configuration.axis == .horizontal ? pageSize.width : nil,
                        height: pageSize.height
                    )
                    .containerRelativeFrame(
                        configuration.axis == .horizontal ? .horizontal : .vertical,
                        count: 1,
                        span: 1,
                        spacing: configuration.spacing,
                        alignment: .center
                    )
                    .id(item.id)
                    .accessibilityAddTraits(item.id == selection ? .isSelected : [])
            }
        }
    }

    private func pageSize(in size: CGSize) -> CGSize {
        if configuration.axis == .horizontal {
            let width = max(
                size.width
                    - configuration.contentInsets.leading
                    - configuration.contentInsets.trailing,
                120
            )
            return CGSize(width: width, height: size.height)
        }
        let height = max(
            size.height
                - configuration.contentInsets.top
                - configuration.contentInsets.bottom,
            120
        )
        return CGSize(width: size.width, height: height)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { _ in if !isDragging { isDragging = true } }
            .onEnded { _ in isDragging = false }
    }
}
```

**What do we have in this code?**

- `GeometryReader` + `pageSize(in:)` — compute the stage page from the offered size minus insets (same numbers the infinite UIKit pager mirrors for horizontal).
- `AnyLayout` (`HStack` / `VStack`) — one code path for both axes.
- Explicit `.frame` **and** `containerRelativeFrame` — fill the stage page, then declare it as a scroll target.
- `scrollTargetLayout()` + `.viewAligned` + `scrollPosition(id:)` — snap + programmable selection.
- `contentMargins` — inset the first/last page from `configuration.contentInsets`.
- `dragGesture` — pause-only signal for auto-scroll (`minimumDistance: 20` so short flicks stay owned by paging).

**Why this snaps cleanly:** SwiftUI’s paging APIs only work when targets are declared (`scrollTargetLayout`) *and* a behavior is set (`.viewAligned`). Skipping either one is how you get that “almost snapped” feel. The explicit `pageSize` frame keeps horizontal cards from growing past the stage — the same contract the infinite pager uses.

### Vertical is the same recipe

`configuration.axis` swaps scroll axis, stack layout, margins, and `pageSize` math. Put indicators on the **trailing** edge so they don’t fight the title. Prefer slightly larger vertical insets so the active card breathes inside the safe area.

---

## Step 3 — Auto-scroll that respects the user

A carousel that fights the finger is a bug. Own pause/resume in a tiny controller:

```swift
@MainActor
final class AutoScrollController: ObservableObject {
    @Published private(set) var tick: UInt64 = 0
    @Published private(set) var isPausedByUserInteraction = false

    private var timer: AnyCancellable?
    private var resumeWorkItem: DispatchWorkItem?
    private var interval: TimeInterval = 3
    private var isEnabled = false

    func configure(enabled: Bool, interval: TimeInterval) {
        self.interval = max(interval, 0.8)
        self.isEnabled = enabled
        rebuildTimer()
    }

    func pauseForUserInteraction(resumeAfter: TimeInterval = 2.4) {
        guard isEnabled else { return }
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

    func stop() { /* cancel timer + resume work */ }

    private func rebuildTimer() {
        timer?.cancel()
        guard isEnabled, !isPausedByUserInteraction else { return }
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick &+= 1 }
    }
}
```

Wire drag → pause:

```swift
.simultaneousGesture(
    DragGesture(minimumDistance: 20)
        .onChanged { _ in if !isDragging { isDragging = true } }
        .onEnded { _ in isDragging = false }
)
.onChange(of: isDragging) { _, dragging in
    if dragging { autoScroll.pauseForUserInteraction() }
}
.onChange(of: autoScroll.tick) { _, _ in
    advanceFiniteSelection() // write next id under withAnimation
}
```

**Why a separate controller?** Screens shouldn’t own `Timer` lifecycle. The controller is reusable for both the SwiftUI finite pager and the UIKit infinite pager (they both just observe `tick`).

**Rules of thumb:**

- Manual mode never starts the timer.
- Auto mode pauses on drag and resumes after a short idle delay.
- Finite advance uses `withAnimation` so `scrollPosition` interpolates instead of hard-cutting.

---

## Step 4 — Infinite paging (and why SwiftUI isn’t enough)

“Infinite” means the user never hits a hard stop. The classic approach:

1. Render the dataset **three times** (copies `0`, `1`, `2`).
2. Start (and stay) on copy `1` — the middle band.
3. When the settled page lands on copy `0` or `2`, jump back to the matching item in copy `1` **without animation**.

```swift
// Conceptual buffer
var loopedCount: Int { items.count * 3 }
var middleStart: Int { items.count } // first index of copy 1
```

### The catch with auto-scroll

Manual infinite already scrolls — gesture physics move `contentOffset`.  
Programmatic SwiftUI `scrollPosition` / `scrollTo` under `withAnimation` often **snaps** to the next looped page for this triple-buffer layout (especially vertical). Neighboring cards don’t slide; they replace in place. Finite auto still looks fine because it animates a small non-looping id set.

**Why UIKit here?** `UIScrollView.setContentOffset(_:animated:)` always produces a real slide on both axes. Finite stays pure SwiftUI; infinite becomes a representable.

### Representable bridge

```swift
struct InfinitePagingScrollView<Item: Identifiable & Hashable, Page: View>: UIViewControllerRepresentable {
    let items: [Item]
    let axis: CarouselAxis
    @Binding var selection: Item.ID?
    @Binding var isDragging: Bool
    var autoAdvanceTick: UInt64
    var autoScrollEnabled: Bool
    @ViewBuilder var pageBuilder: (Item) -> Page

    func updateUIViewController(_ controller: InfinitePagingController<Item, Page>, context: Context) {
        // …sync axis / builder…
        if autoScrollEnabled, context.coordinator.lastTick != autoAdvanceTick {
            context.coordinator.lastTick = autoAdvanceTick
            if !context.coordinator.dragging {
                controller.advanceOnePage(animated: true)
            }
        }
    }
}
```

### Controller essentials

```swift
func advanceOnePage(animated: Bool) {
    let next = min(currentPageIndex() + 1, loopedCount - 1)
    setOffset(toPage: next, animated: animated) // setContentOffset
}

func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
    emitSelection(forPage: currentPageIndex())
    recenterIfNeeded() // silent jump into middle copy
}
```

**Snap physics tip:** decide the landing page from the **lift offset + velocity**, not UIKit’s projected target. Rounding the projected target (and double-counting velocity) is how short flicks cancel or double-advance.

**When not to use infinite:** short catalogs (2–3 items) where looping feels gimmicky, or flows with a meaningful end (checkout, onboarding).

---

## Step 5 — Facade: one `CarouselView`

Hide the finite/infinite split behind a single entry point:

```swift
struct CarouselView<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    var configuration: CarouselConfiguration = .horizontal
    @Binding var selection: Item.ID?
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        if configuration.isInfinite {
            InfinitePagingScrollView(/* … */)
        } else {
            FiniteCarouselLayout(/* … */)
        }
        // own AutoScrollController; forward tick / pause
    }
}
```

**Why a facade?** Call sites shouldn’t care whether the implementation is SwiftUI or UIKit. Product code passes `isInfinite` and gets the correct engine.

---

## Step 6 — 3D infinite stack (3-up circle)

Full-page paging is wrong when the product wants **three cards on screen** — a focused center with peeks (card-design pickers). Don’t use `ScrollView` paging. Place every item on a ring and drive continuous `progress` from the drag.

### The model

```swift
let progress = CGFloat(internalIndex) - dragFraction  // live while dragging
let delta = ringDelta(itemIndex: i, progress: progress) // shortest signed slots
let angle = delta * (2 * .pi / CGFloat(itemCount))
let orbit = sin(angle) * radius   // y when vertical, x when horizontal
let depth = cos(angle)            // 1 = front … −1 = behind
let scale = 0.70 + 0.30 * ((depth + 1) / 2)
```

**What do we have in this code?**

- `progress` — continuous position on the ring (index + live drag).
- `ringDelta` — shortest signed distance on a circular item list (handles wrap).
- `orbit` / `depth` — place the card in the plane and decide who’s in front.
- `scale` — smaller when behind so the wheel reads as depth **without** tilting the card.

**Why a circle instead of a linear offset?** On a slow swipe the leading neighbor must **arc behind** the center and emerge as the trailing neighbor (top→bottom vertically, left→right horizontally). A linear “slide off / slide on” never shows that path.

### Settling without a jump

```swift
// Commit one slot, then remap:
withAnimation(.spring(response: 0.48, dampingFraction: 0.88)) {
    dragOffset = CGFloat(-direction) * slotExtent
}
// After the spring:
internalIndex += direction
dragOffset = 0
currentIndex = realIndex(for: internalIndex)
```

At `dragOffset = ±slotExtent` the transforms match `(index ± 1, dragOffset = 0)`, so the remap is invisible.

### Sizing

Use shared metrics so the container fits rest neighbors:

```swift
let height = StackCarouselMetrics.stackExtent(
    forCardCrossAxis: width,
    axis: .vertical
)
```

Horizontal demos size the focused card ~88% of stage width and reserve space under the wheel for indicators/shadows so dots aren’t covered.

Cards stay **face-on** (no `rotation3DEffect`). Depth is scale + zIndex + a dark shadow (not `.primary` — that becomes a white glow in Dark Mode).

Same component for both axes: `StackedInfiniteCarouselView(axis: .vertical)` / `.horizontal`.

---

## Step 7 — Demo shell (Auto / Manual)

Each demo page shares one screen: segmented Auto/Manual, optional interval, stage, footer.

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

            if kind.isStacked {
                StackedInfiniteCarouselView(/* … */)
            } else {
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
}
```

**Why one toggle?** It turns six kinds into twelve modes without duplicating layout. The catalog (`DemoKind`) owns titles, sample data, and axis — the screen only binds playback state.

---

## Implementation checklist

Before you ship:

- [ ] Snap feels locked — no half-page rests at normal flick speeds  
- [ ] First/last finite pages aren’t clipped by home indicator / notch  
- [ ] Infinite recenter is invisible (fling quickly across a seam)  
- [ ] Auto-scroll pauses on interaction and resumes cleanly  
- [ ] Manual mode never auto-advances  
- [ ] Infinite auto **slides** neighboring cards (not an instant swap)  
- [ ] 3D stack: slow drag shows the behind-the-center arc  
- [ ] Shadows stay visible in Dark Mode (use black opacity, not `.primary`)  
- [ ] VoiceOver reads card content; indicator exposes “Page n of m”

---

## What to steal from the companion app

| File | Role |
|------|------|
| `Carousel/CarouselView.swift` | Finite + infinite facade |
| `Carousel/FiniteCarouselLayout.swift` | Pure-SwiftUI snapping pager |
| `Carousel/Infinite/InfinitePagingScrollView.swift` | UIKit representable bridge |
| `Carousel/Infinite/InfinitePagingController.swift` | Triple-buffer + snap physics |
| `Carousel/Stack/StackedInfiniteCarouselView.swift` | 3D circle stack (V + H) |
| `Carousel/Stack/StackCarouselMetrics.swift` | Axis-aware sizing helpers |
| `Carousel/AutoScrollController.swift` | Timer + resume delay |
| `Carousel/CarouselConfiguration.swift` | Shared knobs |

Clone the repo, run the six demos, then lift the `Carousel/` folder into your project. Start with a finite horizontal shelf; add infinite and the 3D stack only when the product story needs them.

Ship carousels that feel inevitable — not clever.

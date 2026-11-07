import SwiftUI

/// Infinite **3-up** carousel: cards sit on a vertical or horizontal **3D circle**.
///
/// At rest you see center + neighbors. On a slow swipe the stack rotates as a
/// wheel — the leading neighbor travels *behind* the center and emerges on the
/// trailing side. Cards stay face-on (scale + orbit + zIndex only).
///
/// `progress` is continuous (`internalIndex − dragFraction`). After a committed
/// step the virtual index remaps so the loop never ends.
///
/// Count notes:
/// - **2 items:** dedicated engine — rest spots are only **center + leading peek**
///   (top / leading). Front moves with the swipe onto the peek; the peek takes the
///   long arc through behind onto center so the swap still reads as a wheel.
/// - **3 items:** classic `2π/3` ring.
/// - **4+ items:** depth from the circle; orbit uses slot spacing so the far card
///   sits in its own lane instead of under a ±1 neighbor.
/// - **Opacity:** focus = opaque, ±1 = semi, ±2 = faint; anything farther is hidden.
struct StackedInfiniteCarouselView<Item: Identifiable, Card: View>: View {

    // MARK: - Sizing helpers (forwarded for call-site convenience)

    static var interCardSpacingRatioVertical: CGFloat { StackCarouselMetrics.spacingRatioVertical }
    static var interCardSpacingRatioHorizontal: CGFloat { StackCarouselMetrics.spacingRatioHorizontal }

    static func defaultSpacingRatio(for axis: CarouselAxis, itemCount: Int = 3) -> CGFloat {
        StackCarouselMetrics.spacingRatio(for: axis, itemCount: itemCount)
    }

    static func cardMainLength(
        forCardCrossAxis crossAxis: CGFloat,
        aspectRatio: CGFloat = StackCarouselMetrics.creditCardAspectRatio,
        axis: CarouselAxis = .vertical
    ) -> CGFloat {
        StackCarouselMetrics.cardMainLength(
            forCardCrossAxis: crossAxis,
            aspectRatio: aspectRatio,
            axis: axis
        )
    }

    static func stackExtent(
        forCardCrossAxis crossAxis: CGFloat,
        aspectRatio: CGFloat = StackCarouselMetrics.creditCardAspectRatio,
        axis: CarouselAxis = .vertical,
        spacingRatio: CGFloat? = nil,
        itemCount: Int = 3
    ) -> CGFloat {
        StackCarouselMetrics.stackExtent(
            forCardCrossAxis: crossAxis,
            aspectRatio: aspectRatio,
            axis: axis,
            spacingRatio: spacingRatio,
            itemCount: itemCount
        )
    }

    static func cardCrossAxis(
        fittingStackExtent extent: CGFloat,
        aspectRatio: CGFloat = StackCarouselMetrics.creditCardAspectRatio,
        axis: CarouselAxis = .vertical,
        spacingRatio: CGFloat? = nil,
        itemCount: Int = 3
    ) -> CGFloat {
        StackCarouselMetrics.cardCrossAxis(
            fittingStackExtent: extent,
            aspectRatio: aspectRatio,
            axis: axis,
            spacingRatio: spacingRatio,
            itemCount: itemCount
        )
    }

    // MARK: - Inputs

    let items: [Item]
    @Binding var currentIndex: Int
    /// Continuous page position for indicators (`0..<count`, fractional while scrubbing).
    @Binding var scrubProgress: CGFloat
    var axis: CarouselAxis = .vertical
    var cardAspectRatio: CGFloat = StackCarouselMetrics.creditCardAspectRatio
    /// Override center-to-center gap ratio; `nil` uses the axis + count default.
    var spacingRatio: CGFloat? = nil
    var autoAdvanceTick: UInt64 = 0
    var autoScrollEnabled: Bool = false
    var onUserDrag: (() -> Void)? = nil
    @ViewBuilder var cardBuilder: (Item) -> Card

    @State private var internalIndex: Int
    @State private var dragOffset: CGFloat = 0
    @State private var lastAutoTick: UInt64 = 0
    @State private var isSettling = false
    /// Drives settle / cancel so `dragOffset` (and scrub progress) update every frame.
    /// `withAnimation` only interpolates rendering — bindings would jump to the end.
    @State private var settleTask: Task<Void, Never>?

    private var itemCount: Int { items.count }

    private var resolvedSpacingRatio: CGFloat {
        spacingRatio ?? StackCarouselMetrics.spacingRatio(for: axis, itemCount: itemCount)
    }

    /// Angular step for the 3+ ring engine (`2π/n`). Unused by the 2-slot path.
    private var stepAngle: CGFloat {
        guard itemCount > 0 else { return 0 }
        return 2 * .pi / CGFloat(itemCount)
    }

    init(
        items: [Item],
        currentIndex: Binding<Int>,
        scrubProgress: Binding<CGFloat> = .constant(0),
        axis: CarouselAxis = .vertical,
        cardAspectRatio: CGFloat = StackCarouselMetrics.creditCardAspectRatio,
        spacingRatio: CGFloat? = nil,
        autoAdvanceTick: UInt64 = 0,
        autoScrollEnabled: Bool = false,
        onUserDrag: (() -> Void)? = nil,
        @ViewBuilder cardBuilder: @escaping (Item) -> Card
    ) {
        self.items = items
        self._currentIndex = currentIndex
        self._scrubProgress = scrubProgress
        self.axis = axis
        self.cardAspectRatio = cardAspectRatio
        self.spacingRatio = spacingRatio
        self.autoAdvanceTick = autoAdvanceTick
        self.autoScrollEnabled = autoScrollEnabled
        self.onUserDrag = onUserDrag
        self.cardBuilder = cardBuilder
        let start = items.isEmpty ? 0 : items.count * 50 + currentIndex.wrappedValue
        self._internalIndex = State(initialValue: start)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let stageMain = axis == .vertical ? geo.size.height : geo.size.width
            let stageCross = axis == .vertical ? geo.size.width : geo.size.height
            let cardMain = axis == .vertical
                ? stageCross / cardAspectRatio
                : min(
                    stageCross * cardAspectRatio,
                    stageMain * StackCarouselMetrics.horizontalFocusWidthRatio
                )
            let cardCross = axis == .vertical ? stageCross : cardMain / cardAspectRatio
            let interCardSpacing = cardMain * resolvedSpacingRatio
            let slotExtent = max(cardMain, 1)
            let dragFraction = dragOffset / slotExtent
            let progress = CGFloat(internalIndex) - dragFraction

            let logical = Self.logicalPageProgress(virtual: progress, count: itemCount)
            stackContent(
                slotExtent: slotExtent,
                cardMain: cardMain,
                cardCross: cardCross,
                interCardSpacing: interCardSpacing,
                progress: progress,
                logicalProgress: logical
            )
        }
    }

    @ViewBuilder
    private func stackContent(
        slotExtent: CGFloat,
        cardMain: CGFloat,
        cardCross: CGFloat,
        interCardSpacing: CGFloat,
        progress: CGFloat,
        logicalProgress: CGFloat
    ) -> some View {
        let step = stepAngle
        let radius = ringRadius(spacing: interCardSpacing)
        // Front + one level back + second level. Farther slots stay unmounted.
        let visibleWindow: CGFloat = 2.45

        ZStack {
            // Identity by *offset* so duplicate `Item.id` values (easy when
            // prototyping) cannot collapse multiple cards into one view.
            ForEach(Array(items.enumerated()), id: \.offset) { itemIndex, item in
                let wrapped = wrappedDelta(itemIndex: itemIndex, progress: progress)
                let opacity = cardOpacity(forWrappedDelta: wrapped)
                if abs(wrapped) < visibleWindow, opacity > 0.01 {
                    cardLayer(
                        item: item,
                        itemIndex: itemIndex,
                        progress: progress,
                        wrappedDelta: wrapped,
                        stepAngle: step,
                        radius: radius,
                        spacing: interCardSpacing,
                        cardMain: cardMain,
                        cardCross: cardCross,
                        opacity: opacity
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(dragGesture(slotExtent: slotExtent))
        .onAppear {
            lastAutoTick = autoAdvanceTick
            publishScrubProgress(logicalProgress)
        }
        .onChange(of: logicalProgress) { _, value in
            publishScrubProgress(value)
        }
        .onChange(of: autoAdvanceTick) { _, tick in
            guard autoScrollEnabled, !isSettling, itemCount > 0 else { return }
            guard tick != lastAutoTick else { return }
            lastAutoTick = tick
            commitStep(direction: +1, slotExtent: slotExtent)
        }
        .onChange(of: currentIndex) { _, newValue in
            guard itemCount > 0, !isSettling else { return }
            let targetReal = ((newValue % itemCount) + itemCount) % itemCount
            if realIndex(for: internalIndex) != targetReal {
                internalIndex = itemCount * 50 + targetReal
                dragOffset = 0
            }
        }
        .onChange(of: itemCount) { _, newCount in
            guard newCount > 0 else { return }
            let real = realIndex(for: internalIndex)
            let clamped = min(real, newCount - 1)
            internalIndex = newCount * 50 + clamped
            dragOffset = 0
            if currentIndex != clamped {
                currentIndex = clamped
            }
        }
    }

    @ViewBuilder
    private func cardLayer(
        item: Item,
        itemIndex: Int,
        progress: CGFloat,
        wrappedDelta: CGFloat,
        stepAngle: CGFloat,
        radius: CGFloat,
        spacing: CGFloat,
        cardMain: CGFloat,
        cardCross: CGFloat,
        opacity: Double
    ) -> some View {
        let placement = orbitPlacement(
            itemIndex: itemIndex,
            progress: progress,
            wrappedDelta: wrappedDelta,
            stepAngle: stepAngle,
            radius: radius,
            spacing: spacing
        )
        let depth = placement.depth
        let orbit = placement.orbit
        let scale = 0.70 + 0.30 * ((depth + 1) * 0.5)
        // Prefer slot distance over depth — two-item mid-swipe has depth ≈ 0 for both.
        let isFront = abs(wrappedDelta) < 0.5

        cardBuilder(item)
            .frame(
                width: axis == .vertical ? cardCross : cardMain,
                height: axis == .vertical ? cardMain : cardCross
            )
            .compositingGroup()
            .shadow(
                color: .black.opacity((isFront ? 0.35 : max(0.08, 0.22 * Double((depth + 1) * 0.5))) * opacity),
                radius: isFront ? 18 : 8,
                y: isFront ? 10 : 4
            )
            .opacity(opacity)
            .scaleEffect(scale)
            .offset(
                x: axis == .horizontal ? orbit : 0,
                y: axis == .vertical ? orbit : 0
            )
            .zIndex(Double(depth))
            .allowsHitTesting(isFront && !isSettling)
    }

    /// Opacity by slot distance from the focused card:
    /// front = 1, ±1 = semi, ±2 = faint, farther = hidden.
    private func cardOpacity(forWrappedDelta delta: CGFloat) -> Double {
        let d = abs(Double(delta))
        let stops: [(Double, Double)] = [
            (0.0, 1.00),
            (1.0, 0.58),
            (2.0, 0.26),
            (2.45, 0.00)
        ]
        if d <= stops[0].0 { return stops[0].1 }
        for index in 0..<(stops.count - 1) {
            let (d0, o0) = stops[index]
            let (d1, o1) = stops[index + 1]
            if d <= d1 {
                let t = (d - d0) / (d1 - d0)
                return o0 + (o1 - o0) * t
            }
        }
        return 0
    }

    // MARK: - Ring placement

    private func ringRadius(spacing: CGFloat) -> CGFloat {
        let s = abs(sin(stepAngle))
        if s > 0.001 {
            return spacing / s
        }
        return spacing
    }

    private func orbitPlacement(
        itemIndex: Int,
        progress: CGFloat,
        wrappedDelta: CGFloat,
        stepAngle: CGFloat,
        radius: CGFloat,
        spacing: CGFloat
    ) -> (orbit: CGFloat, depth: CGFloat) {
        // Facade: 2-slot engine vs full ring (same idea as CarouselView’s finite/infinite split).
        if itemCount == 2 {
            return twoSlotPlacement(itemIndex: itemIndex, progress: progress, spacing: spacing)
        }

        let rawDelta = CGFloat(itemIndex) - progress
        let angle = rawDelta * stepAngle
        let depth = cos(angle)

        // 4+: slot orbit so the far card has its own lane (circle sin would
        // park it under a ±1 neighbor at the same |orbit|).
        if itemCount >= 4 {
            return (wrappedDelta * spacing, depth)
        }

        return (sin(angle) * radius, depth)
    }

    /// Two rest spots (center + leading peek), circular travel between them.
    ///
    /// Swipe-matched wheel (progress+ / drag toward leading):
    /// - outbound (`phase` 0 → −1): front takes the **short** arc onto the leading
    ///   peek (moves with the finger);
    /// - inbound (`phase` +1 → 0): peek takes the **long** arc through behind onto
    ///   center (arrives from under).
    /// Rest is always center + leading — reverse swipe just runs the same wheel backward.
    private func twoSlotPlacement(
        itemIndex: Int,
        progress: CGFloat,
        spacing: CGFloat
    ) -> (orbit: CGFloat, depth: CGFloat) {
        var phase = CGFloat(itemIndex) - progress
        phase = phase.truncatingRemainder(dividingBy: 2)
        if phase > 1 {
            phase -= 2
        } else if phase <= -1 {
            phase += 2
        }

        let peek = 2 * CGFloat.pi / 3 // leading rest angle magnitude (top / leading)
        let longArc = 2 * CGFloat.pi - peek // via behind
        let angle: CGFloat
        if phase <= 0 {
            // 0 → −peek as phase 0 → −1 (with the swipe toward leading)
            angle = phase * peek
        } else {
            // −peek → −2π (≡ 0) as phase 1 → 0 (long way through behind)
            angle = -peek - (1 - phase) * longArc
        }

        // Vertical reads large with credit-card height — keep that ring a bit tighter.
        let radiusScale: CGFloat = axis == .vertical ? 0.78 : 1
        let radius = (spacing / sin(peek)) * radiusScale
        return (sin(angle) * radius, cos(angle))
    }

    // MARK: - Index math

    private func realIndex(for virtual: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        return ((virtual % itemCount) + itemCount) % itemCount
    }

    /// Maps the virtual ring progress onto `0..<count` for page indicators.
    static func logicalPageProgress(virtual: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let n = CGFloat(count)
        var x = virtual.truncatingRemainder(dividingBy: n)
        if x < 0 { x += n }
        return x
    }

    private func publishScrubProgress(_ value: CGFloat) {
        if abs(scrubProgress - value) > 0.0005 {
            scrubProgress = value
        }
    }

    /// Shortest signed distance — visibility culling + 4+ slot orbits.
    private func wrappedDelta(itemIndex: Int, progress: CGFloat) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        let n = CGFloat(itemCount)
        var delta = CGFloat(itemIndex) - progress
        delta = delta.truncatingRemainder(dividingBy: n)
        if delta > n / 2 {
            delta -= n
        } else if delta < -n / 2 {
            delta += n
        }
        return delta
    }

    // MARK: - Drag

    private func dragGesture(slotExtent: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Cancel a spring-back so the finger isn't fighting the settle loop.
                if !isSettling, settleTask != nil {
                    settleTask?.cancel()
                    settleTask = nil
                }
                guard !isSettling else { return }
                if dragOffset == 0 {
                    onUserDrag?()
                }
                dragOffset = axis == .vertical
                    ? value.translation.height
                    : value.translation.width
            }
            .onEnded { value in
                guard !isSettling else { return }
                let translation = axis == .vertical
                    ? value.translation.height
                    : value.translation.width
                let predicted = axis == .vertical
                    ? value.predictedEndTranslation.height
                    : value.predictedEndTranslation.width
                let threshold = slotExtent / 4
                let decisive = abs(predicted) > abs(translation) ? predicted : translation

                if abs(decisive) > threshold {
                    // Keep multi-slot drags / flicks — don't settle back to a single page.
                    let steps = max(1, Int((abs(decisive) / slotExtent).rounded()))
                    let direction = decisive > 0 ? -1 : +1
                    commitStep(direction: direction, slotExtent: slotExtent, steps: steps)
                } else {
                    // Snappy ease-out; matches the old spring's feel better than a full ease-in-out.
                    animateDragOffset(to: 0, duration: 0.28)
                }
            }
    }

    /// `direction` +1 = next, −1 = previous.
    /// Used by both manual commit and auto-scroll ticks.
    private func commitStep(direction: Int, slotExtent: CGFloat, steps: Int = 1) {
        guard itemCount > 0, !isSettling else { return }
        let pageCount = max(1, steps)
        isSettling = true
        let targetOffset = CGFloat(-direction) * slotExtent * CGFloat(pageCount)
        // Spring response was 0.55, but most travel finishes earlier — keep wall-clock short
        // and scale only slightly for multi-page flicks.
        let duration = min(0.42, 0.26 + 0.06 * Double(pageCount))

        animateDragOffset(to: targetOffset, duration: duration) {
            internalIndex += direction * pageCount
            dragOffset = 0
            currentIndex = realIndex(for: internalIndex)
            isSettling = false
        }
    }

    /// Steps `dragOffset` on the main actor so scrub progress tracks auto-scroll
    /// and settle the same way it tracks a finger drag.
    private func animateDragOffset(
        to target: CGFloat,
        duration: TimeInterval,
        onComplete: @escaping () -> Void = {}
    ) {
        settleTask?.cancel()
        let start = dragOffset
        let delta = target - start
        guard abs(delta) > 0.5 else {
            dragOffset = target
            onComplete()
            return
        }

        settleTask = Task { @MainActor in
            let startTime = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startTime)
                let t = min(1, elapsed / duration)
                // Ease-out cubic — fast start like a damped spring, no slow ease-in.
                let eased = 1 - pow(1 - t, 3)
                dragOffset = start + delta * CGFloat(eased)
                if t >= 1 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            guard !Task.isCancelled else { return }
            dragOffset = target
            onComplete()
        }
    }
}

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
/// - **2 items:** one step maps to `4π/3` (not `π`) so a swipe arcs through the
///   back instead of resting on the ±180° singularity (which caused top↔bottom
///   teleports and a “dip then rise” peek).
/// - **3 items:** classic `2π/3` ring.
/// - **4+ items:** depth still comes from the circle; orbit uses slot spacing so
///   the far card sits in its own lane instead of under a ±1 neighbor.
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

    private var itemCount: Int { items.count }

    private var resolvedSpacingRatio: CGFloat {
        spacingRatio ?? StackCarouselMetrics.spacingRatio(for: axis, itemCount: itemCount)
    }

    /// Angular step around the ring.
    /// Two items use a longer step so travel passes through the back (depth -1)
    /// and rests at a 3-up-style peek — never on the ±π singularity.
    private var stepAngle: CGFloat {
        guard itemCount > 0 else { return 0 }
        if itemCount == 2 {
            return 4 * .pi / 3
        }
        return 2 * .pi / CGFloat(itemCount)
    }

    init(
        items: [Item],
        currentIndex: Binding<Int>,
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

            stackContent(
                slotExtent: slotExtent,
                cardMain: cardMain,
                cardCross: cardCross,
                interCardSpacing: interCardSpacing,
                progress: progress
            )
        }
    }

    @ViewBuilder
    private func stackContent(
        slotExtent: CGFloat,
        cardMain: CGFloat,
        cardCross: CGFloat,
        interCardSpacing: CGFloat,
        progress: CGFloat
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
        .onAppear { lastAutoTick = autoAdvanceTick }
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
        let isFront = depth > 0.85

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

    /// Continuous placement from the *raw* slot delta (no shortest-path wrap).
    private func orbitPlacement(
        itemIndex: Int,
        progress: CGFloat,
        wrappedDelta: CGFloat,
        stepAngle: CGFloat,
        radius: CGFloat,
        spacing: CGFloat
    ) -> (orbit: CGFloat, depth: CGFloat) {
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

    // MARK: - Index math

    private func realIndex(for virtual: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        return ((virtual % itemCount) + itemCount) % itemCount
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

                if decisive > threshold {
                    commitStep(direction: -1, slotExtent: slotExtent)
                } else if decisive < -threshold {
                    commitStep(direction: +1, slotExtent: slotExtent)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        dragOffset = 0
                    }
                }
            }
    }

    /// `direction` +1 = next, −1 = previous.
    private func commitStep(direction: Int, slotExtent: CGFloat) {
        guard itemCount > 0, !isSettling else { return }
        isSettling = true
        let targetOffset = CGFloat(-direction) * slotExtent

        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
            dragOffset = targetOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
            internalIndex += direction
            dragOffset = 0
            currentIndex = realIndex(for: internalIndex)
            isSettling = false
        }
    }
}

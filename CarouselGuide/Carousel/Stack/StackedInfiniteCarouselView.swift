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
/// Placement uses the *raw* slot delta for `sin`/`cos` (not shortest-path wrap)
/// so a 2-item step travels continuously through ±90° instead of jumping from
/// top peek to bottom peek. Cards parked opposite the focus get a peek bias;
/// on 4+ rings that bias sits *beyond* the ±1 side peeks so the rear card isn’t
/// hidden underneath a neighbor.
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

    /// True ring step (`2π/n`) so every count shares one continuous circle.
    private var stepAngle: CGFloat {
        guard itemCount > 0 else { return 0 }
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
        // Shortest-path distance only for culling — placement uses raw deltas.
        let visibleWindow = CGFloat(max(itemCount, 1)) / 2 + 0.05

        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { itemIndex, item in
                let wrapped = wrappedDelta(itemIndex: itemIndex, progress: progress)
                if abs(wrapped) < visibleWindow {
                    cardLayer(
                        item: item,
                        itemIndex: itemIndex,
                        progress: progress,
                        stepAngle: step,
                        radius: radius,
                        spacing: interCardSpacing,
                        cardMain: cardMain,
                        cardCross: cardCross
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
        stepAngle: CGFloat,
        radius: CGFloat,
        spacing: CGFloat,
        cardMain: CGFloat,
        cardCross: CGFloat
    ) -> some View {
        let placement = orbitPlacement(
            itemIndex: itemIndex,
            progress: progress,
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
                color: .black.opacity(isFront ? 0.35 : max(0.08, 0.22 * Double((depth + 1) * 0.5))),
                radius: isFront ? 18 : 8,
                y: isFront ? 10 : 4
            )
            .scaleEffect(scale)
            .offset(
                x: axis == .horizontal ? orbit : 0,
                y: axis == .vertical ? orbit : 0
            )
            .zIndex(Double(depth))
            .allowsHitTesting(isFront && !isSettling)
    }

    // MARK: - Ring placement

    /// Radius such that a 1-slot neighbor’s `sin(step)·radius ≈ spacing`.
    /// For 2 items `sin(π) = 0`; mid-swipe orbit is then ±spacing.
    private func ringRadius(spacing: CGFloat) -> CGFloat {
        let s = sin(stepAngle)
        if abs(s) > 0.001 {
            return spacing / s
        }
        return spacing
    }

    /// Continuous circle placement from the *raw* slot delta.
    ///
    /// Shortest-path wrapping jumps by a full turn at ±n/2 — for 2 items that
    /// teleports a top peek to a bottom peek. `sin`/`cos` already wrap angles.
    private func orbitPlacement(
        itemIndex: Int,
        progress: CGFloat,
        stepAngle: CGFloat,
        radius: CGFloat,
        spacing: CGFloat
    ) -> (orbit: CGFloat, depth: CGFloat) {
        let rawDelta = CGFloat(itemIndex) - progress
        let angle = rawDelta * stepAngle
        let depth = cos(angle)
        let sinA = sin(angle)
        var orbit = sinA * radius

        // Cards nearly opposite the focus (depth → -1) would sit under the
        // center — and on 4+ rings, under a ±1 side peek at the same orbit.
        let opposite = max(0 as CGFloat, -depth - 0.75) / 0.25
        if opposite > 0 {
            let side: CGFloat = {
                if abs(sinA) > 0.02 { return sinA > 0 ? 1 : -1 }
                // Exact back: keep the approach half-plane (avoids a rest flip).
                let probe = sin(angle + (angle >= 0 ? -0.01 : 0.01))
                return probe >= 0 ? 1 : -1
            }()
            var target = spacing * StackCarouselMetrics.backPeekRatio
            if itemCount >= 4 {
                target = spacing * (1 + StackCarouselMetrics.backPeekBeyondSideRatio)
            }
            let mag = abs(orbit) * (1 - min(opposite, 1)) + target * min(opposite, 1)
            orbit = side * mag
        }
        return (orbit, depth)
    }

    // MARK: - Index math

    private func realIndex(for virtual: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        return ((virtual % itemCount) + itemCount) % itemCount
    }

    /// Shortest signed distance — used only for visibility culling.
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

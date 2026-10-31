import SwiftUI

/// Infinite **3-up** carousel: cards sit on a vertical or horizontal **3D circle**.
///
/// At rest you see center + neighbors. On a slow swipe the stack rotates as a
/// wheel — the leading neighbor travels *behind* the center and emerges on the
/// trailing side. Cards stay face-on (scale + orbit + zIndex only).
///
/// `progress` is continuous (`internalIndex − dragFraction`). After a committed
/// step the virtual index remaps so the loop never ends.
struct StackedInfiniteCarouselView<Item: Identifiable, Card: View>: View {

    // MARK: - Sizing helpers (forwarded for call-site convenience)

    static var interCardSpacingRatioVertical: CGFloat { StackCarouselMetrics.spacingRatioVertical }
    static var interCardSpacingRatioHorizontal: CGFloat { StackCarouselMetrics.spacingRatioHorizontal }

    static func defaultSpacingRatio(for axis: CarouselAxis) -> CGFloat {
        StackCarouselMetrics.spacingRatio(for: axis)
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
        spacingRatio: CGFloat? = nil
    ) -> CGFloat {
        StackCarouselMetrics.stackExtent(
            forCardCrossAxis: crossAxis,
            aspectRatio: aspectRatio,
            axis: axis,
            spacingRatio: spacingRatio
        )
    }

    static func cardCrossAxis(
        fittingStackExtent extent: CGFloat,
        aspectRatio: CGFloat = StackCarouselMetrics.creditCardAspectRatio,
        axis: CarouselAxis = .vertical,
        spacingRatio: CGFloat? = nil
    ) -> CGFloat {
        StackCarouselMetrics.cardCrossAxis(
            fittingStackExtent: extent,
            aspectRatio: aspectRatio,
            axis: axis,
            spacingRatio: spacingRatio
        )
    }

    // MARK: - Inputs

    let items: [Item]
    @Binding var currentIndex: Int
    var axis: CarouselAxis = .vertical
    var cardAspectRatio: CGFloat = StackCarouselMetrics.creditCardAspectRatio
    /// Override center-to-center gap ratio; `nil` uses the axis default.
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
        spacingRatio ?? StackCarouselMetrics.spacingRatio(for: axis)
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
        let count = itemCount
        let stepAngle = count > 0 ? (2 * CGFloat.pi / CGFloat(count)) : 0
        let radius: CGFloat = {
            let s = sin(stepAngle)
            return abs(s) > 0.001 ? interCardSpacing / s : interCardSpacing
        }()
        // Rest shows ±1; keep ±2 during a step so larger rings can arc behind.
        let visibleWindow = min(2.55, CGFloat(max(count, 1)) / 2 + 0.05)

        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { itemIndex, item in
                let delta = ringDelta(itemIndex: itemIndex, progress: progress)
                if abs(delta) < visibleWindow {
                    cardLayer(
                        item: item,
                        delta: delta,
                        stepAngle: stepAngle,
                        radius: radius,
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
    }

    @ViewBuilder
    private func cardLayer(
        item: Item,
        delta: CGFloat,
        stepAngle: CGFloat,
        radius: CGFloat,
        cardMain: CGFloat,
        cardCross: CGFloat
    ) -> some View {
        let angle = delta * stepAngle
        let depth = cos(angle)
        let orbit = sin(angle) * radius
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

    // MARK: - Index math

    private func realIndex(for virtual: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        return ((virtual % itemCount) + itemCount) % itemCount
    }

    /// Shortest signed distance on the ring from `progress` to item `i`, in slots.
    private func ringDelta(itemIndex: Int, progress: CGFloat) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        let n = CGFloat(itemCount)
        var delta = CGFloat(itemIndex) - progress
        delta = delta.truncatingRemainder(dividingBy: n)
        if delta > n / 2 { delta -= n }
        if delta <= -n / 2 { delta += n }
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

        withAnimation(.spring(response: 0.48, dampingFraction: 0.88)) {
            dragOffset = targetOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
            internalIndex += direction
            dragOffset = 0
            currentIndex = realIndex(for: internalIndex)
            isSettling = false
        }
    }
}

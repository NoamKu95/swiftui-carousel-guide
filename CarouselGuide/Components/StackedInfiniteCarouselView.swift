import SwiftUI

/// Infinite **3-up** carousel: cards sit on a vertical (or horizontal) **3D circle**.
///
/// At rest you see center + neighbors. On a slow swipe the stack rotates as a
/// wheel — the top card travels *behind* the center and emerges as the bottom
/// card (and the reverse for the other direction). Dropping the linear
/// “slide off / slide on” path is what sells the circle.
///
/// `progress` is continuous (`internalIndex − dragFraction`), so every frame of
/// a slow drag remaps angles. After a committed step we remap the virtual index
/// the same way as before so the loop never ends.
struct StackedInfiniteCarouselView<Item: Identifiable, Card: View>: View {

    // MARK: Sizing

    /// Center-to-center gap as a fraction of card height (vertical) / width (horizontal).
    /// Computed (not stored) — generic types can't have static stored properties.
    static var interCardSpacingRatio: CGFloat { 0.55 }

    /// Scale applied at a rest neighbor (`|Δ| == 1`) when measuring the stack.
    private static var neighborScaleAtOne: CGFloat { 0.82 }

    /// Container extent the caller should reserve so rest neighbors aren’t clipped.
    ///
    /// `2 × spacing + cardMain × neighborScale` (+ slack for shadow / mid-orbit).
    static func stackExtent(forCardCrossAxis crossAxis: CGFloat, aspectRatio: CGFloat = 1.586) -> CGFloat {
        let cardMain = crossAxis / aspectRatio
        let spacing = cardMain * interCardSpacingRatio
        let slack = cardMain * 0.18
        return 2 * spacing + cardMain * neighborScaleAtOne + slack
    }

    // MARK: Inputs

    let items: [Item]
    @Binding var currentIndex: Int
    var axis: CarouselAxis = .vertical
    /// Width ÷ height of one card (ISO credit-card default 1.586).
    var cardAspectRatio: CGFloat = 1.586
    /// Auto-advance ticks from `AutoScrollController` (0 = ignore).
    var autoAdvanceTick: UInt64 = 0
    var autoScrollEnabled: Bool = false
    var onUserDrag: (() -> Void)? = nil
    @ViewBuilder var cardBuilder: (Item) -> Card

    @State private var internalIndex: Int
    @State private var dragOffset: CGFloat = 0
    @State private var lastAutoTick: UInt64 = 0
    @State private var isSettling = false

    private var itemCount: Int { items.count }

    init(
        items: [Item],
        currentIndex: Binding<Int>,
        axis: CarouselAxis = .vertical,
        cardAspectRatio: CGFloat = 1.586,
        autoAdvanceTick: UInt64 = 0,
        autoScrollEnabled: Bool = false,
        onUserDrag: (() -> Void)? = nil,
        @ViewBuilder cardBuilder: @escaping (Item) -> Card
    ) {
        self.items = items
        self._currentIndex = currentIndex
        self.axis = axis
        self.cardAspectRatio = cardAspectRatio
        self.autoAdvanceTick = autoAdvanceTick
        self.autoScrollEnabled = autoScrollEnabled
        self.onUserDrag = onUserDrag
        self.cardBuilder = cardBuilder
        let start = items.isEmpty ? 0 : items.count * 50 + currentIndex.wrappedValue
        self._internalIndex = State(initialValue: start)
    }

    private func realIndex(for virtual: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        return ((virtual % itemCount) + itemCount) % itemCount
    }

    /// Shortest signed distance on the ring from `progress` to item `i`, in slots.
    private func ringDelta(itemIndex: Int, progress: CGFloat) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        let n = CGFloat(itemCount)
        var delta = CGFloat(itemIndex) - progress
        // Wrap into (-n/2, n/2]
        delta = delta.truncatingRemainder(dividingBy: n)
        if delta > n / 2 { delta -= n }
        if delta <= -n / 2 { delta += n }
        return delta
    }

    var body: some View {
        GeometryReader { geo in
            let pageExtent = axis == .vertical ? geo.size.height : geo.size.width
            let crossExtent = axis == .vertical ? geo.size.width : geo.size.height
            let cardCross = crossExtent
            let cardMain = axis == .vertical
                ? crossExtent / cardAspectRatio
                : crossExtent * cardAspectRatio
            let interCardSpacing = cardMain * Self.interCardSpacingRatio
            // Swipe toward negative translation → progress advances (next).
            let dragFraction = pageExtent > 0 ? dragOffset / pageExtent : 0
            let progress = CGFloat(internalIndex) - dragFraction

            stackContent(
                pageExtent: pageExtent,
                cardMain: cardMain,
                cardCross: cardCross,
                interCardSpacing: interCardSpacing,
                progress: progress
            )
        }
    }

    @ViewBuilder
    private func stackContent(
        pageExtent: CGFloat,
        cardMain: CGFloat,
        cardCross: CGFloat,
        interCardSpacing: CGFloat,
        progress: CGFloat
    ) -> some View {
        let count = itemCount
        // Radius chosen so a rest neighbor (|Δ| == 1) lands at ±interCardSpacing.
        let stepAngle = count > 0 ? (2 * CGFloat.pi / CGFloat(count)) : 0
        let radius: CGFloat = {
            let s = sin(stepAngle)
            return abs(s) > 0.001 ? interCardSpacing / s : interCardSpacing
        }()

        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { itemIndex, item in
                let delta = ringDelta(itemIndex: itemIndex, progress: progress)
                // Only keep cards within ~1½ seats — for a 3-item ring that’s everyone.
                let isVisible = abs(delta) < 1.55

                if isVisible {
                    let angle = delta * stepAngle
                    let depth = cos(angle) // 1 = front, −1 = behind center
                    let orbit = sin(angle) * radius
                    // Front = 1.0; back of the circle tucks smaller so it reads as behind.
                    let scale = 0.70 + 0.30 * ((depth + 1) * 0.5)
                    let isFront = depth > 0.85
                    let tilt = angle * 0.42 // radians → partial 3D pitch/yaw

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
                        .rotation3DEffect(
                            .radians(Double(tilt)),
                            axis: axis == .vertical
                                ? (x: 1, y: 0, z: 0)
                                : (x: 0, y: 1, z: 0),
                            perspective: 0.55
                        )
                        .offset(
                            x: axis == .horizontal ? orbit : 0,
                            y: axis == .vertical ? orbit : 0
                        )
                        .zIndex(Double(depth))
                        .allowsHitTesting(isFront && !isSettling)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(dragGesture(pageExtent: pageExtent))
        .onAppear { lastAutoTick = autoAdvanceTick }
        .onChange(of: autoAdvanceTick) { _, tick in
            guard autoScrollEnabled, !isSettling, itemCount > 0 else { return }
            guard tick != lastAutoTick else { return }
            lastAutoTick = tick
            commitStep(direction: +1, pageExtent: pageExtent)
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

    // MARK: - Drag

    private func dragGesture(pageExtent: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isSettling else { return }
                if dragOffset == 0 {
                    onUserDrag?()
                }
                // Live offset — no threshold while dragging, so a slow swipe
                // continuously rotates the circle.
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
                let threshold = pageExtent / 4

                let decisive = abs(predicted) > abs(translation) ? predicted : translation

                if decisive > threshold {
                    commitStep(direction: -1, pageExtent: pageExtent)
                } else if decisive < -threshold {
                    commitStep(direction: +1, pageExtent: pageExtent)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        dragOffset = 0
                    }
                }
            }
    }

    /// `direction` +1 = next, −1 = previous. Animates one slot on the circle, then remaps.
    private func commitStep(direction: Int, pageExtent: CGFloat) {
        guard itemCount > 0, !isSettling else { return }
        isSettling = true
        let targetOffset = CGFloat(-direction) * pageExtent

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

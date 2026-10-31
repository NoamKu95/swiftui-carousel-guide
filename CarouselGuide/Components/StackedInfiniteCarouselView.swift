import SwiftUI

/// Infinite carousel that keeps **~3 cards on screen** at once (center + neighbors),
/// with scale / opacity / depth by page offset.
///
/// Port of the production `VerticalInfiniteCarouselView` pattern (card-selection style):
/// stacked transforms instead of a full-page `ScrollView`. Horizontal uses the same
/// model on the X axis.
struct StackedInfiniteCarouselView<Item: Identifiable, Card: View>: View {

    // MARK: Sizing

    /// Container height (vertical) or width (horizontal) the caller should reserve.
    /// Matches the Android-derived ratio: container ≈ cardSize × 1.544.
    static func stackExtent(forCardCrossAxis crossAxis: CGFloat, aspectRatio: CGFloat = 1.586) -> CGFloat {
        (crossAxis / aspectRatio) * 1.544
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

    var body: some View {
        GeometryReader { geo in
            let pageExtent = axis == .vertical ? geo.size.height : geo.size.width
            let crossExtent = axis == .vertical ? geo.size.width : geo.size.height
            // Card size from cross-axis (width for vertical stack, height for horizontal).
            let cardMain: CGFloat
            let cardCross: CGFloat
            if axis == .vertical {
                cardCross = crossExtent
                cardMain = crossExtent / cardAspectRatio
            } else {
                cardMain = crossExtent * cardAspectRatio
                cardCross = crossExtent
            }

            // Center-to-center spacing — same 90/350 ratio as the reference implementation.
            let interCardSpacing = pageExtent * (90.0 / 350.0)
            let dragFraction = pageExtent > 0 ? dragOffset / pageExtent : 0

            ZStack {
                ForEach([-2, -1, 0, 1, 2], id: \.self) { virtualOffset in
                    let realIdx = realIndex(for: internalIndex + virtualOffset)
                    let pageOffset = CGFloat(virtualOffset) + dragFraction
                    let absOffset = abs(pageOffset)

                    let translation = pageOffset * interCardSpacing
                    let scale = 1.0 - min(absOffset * 0.15, 0.30)
                    let alpha = absOffset >= 1.5 ? 0.0 : max(0, 1.0 - Double(absOffset) * 0.30)

                    cardBuilder(items[realIdx])
                        .frame(
                            width: axis == .vertical ? cardCross : cardMain,
                            height: axis == .vertical ? cardMain : cardCross
                        )
                        .scaleEffect(scale)
                        .opacity(alpha)
                        .offset(
                            x: axis == .horizontal ? translation : 0,
                            y: axis == .vertical ? translation : 0
                        )
                        .zIndex(1.0 - Double(absOffset))
                        .allowsHitTesting(virtualOffset == 0 && !isSettling)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
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
                // External selection (e.g. indicator) — jump virtual index without animation.
                guard itemCount > 0, !isSettling else { return }
                let targetReal = ((newValue % itemCount) + itemCount) % itemCount
                if realIndex(for: internalIndex) != targetReal {
                    internalIndex = itemCount * 50 + targetReal
                    dragOffset = 0
                }
            }
        }
    }

    // MARK: - Drag

    private func dragGesture(pageExtent: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
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
                let threshold = pageExtent / 3

                // Prefer flick intent when prediction is strong.
                let decisive = abs(predicted) > abs(translation) ? predicted : translation

                if decisive > threshold {
                    // Drag content down / right → previous item.
                    commitStep(direction: -1, pageExtent: pageExtent)
                } else if decisive < -threshold {
                    commitStep(direction: +1, pageExtent: pageExtent)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        dragOffset = 0
                    }
                }
            }
    }

    /// `direction` +1 = next, −1 = previous. Animates one slot then remaps the virtual index.
    private func commitStep(direction: Int, pageExtent: CGFloat) {
        guard itemCount > 0, !isSettling else { return }
        isSettling = true
        let targetOffset = CGFloat(-direction) * pageExtent

        withAnimation(.spring(response: 0.40, dampingFraction: 0.85)) {
            dragOffset = targetOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            internalIndex += direction
            dragOffset = 0
            currentIndex = realIndex(for: internalIndex)
            isSettling = false
        }
    }
}

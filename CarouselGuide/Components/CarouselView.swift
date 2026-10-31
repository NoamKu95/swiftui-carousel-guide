import SwiftUI

/// A reusable snapping carousel for finite or infinite (seamless looping) content.
///
/// Finite auto-scroll animates `scrollPosition` by writing the item id under `withAnimation`.
/// Infinite auto-scroll must also produce a real content-offset slide: we advance an adjacent
/// **Int page index** and call `ScrollViewProxy.scrollTo` inside the same `withAnimation`.
/// Merely assigning a looped string id was snapping without a visible scroll.
struct CarouselView<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    var configuration: CarouselConfiguration = .horizontal
    @Binding var selection: Item.ID?
    @ViewBuilder var content: (Item) -> Content

    @StateObject private var autoScroll = AutoScrollController()
    @State private var isDragging = false

    private var resolvedSelection: Binding<Item.ID?> {
        Binding(
            get: { selection ?? items.first?.id },
            set: { selection = $0 }
        )
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: "rectangle.stack",
                    description: Text("Provide at least one item to render a carousel.")
                )
            } else if configuration.isInfinite {
                InfiniteCarouselLayout(
                    items: items,
                    configuration: configuration,
                    selection: resolvedSelection,
                    isDragging: $isDragging,
                    autoAdvanceTick: autoScroll.tick,
                    autoScrollEnabled: configuration.autoScrollEnabled,
                    content: content
                )
            } else {
                FiniteCarouselLayout(
                    items: items,
                    configuration: configuration,
                    selection: resolvedSelection,
                    isDragging: $isDragging,
                    content: content
                )
            }
        }
        .onAppear {
            if selection == nil {
                selection = items.first?.id
            }
            autoScroll.configure(
                enabled: configuration.autoScrollEnabled,
                interval: configuration.autoScrollInterval
            )
        }
        .onChange(of: configuration.autoScrollEnabled) { _, enabled in
            autoScroll.configure(enabled: enabled, interval: configuration.autoScrollInterval)
        }
        .onChange(of: configuration.autoScrollInterval) { _, interval in
            autoScroll.configure(
                enabled: configuration.autoScrollEnabled,
                interval: interval
            )
        }
        .onChange(of: isDragging) { _, dragging in
            if dragging {
                autoScroll.pauseForUserInteraction()
            }
        }
        .onChange(of: autoScroll.tick) { _, _ in
            // Finite advances here. Infinite observes `autoScroll.tick` inside its layout
            // so it can call `ScrollViewProxy.scrollTo` under `withAnimation`.
            guard !configuration.isInfinite else { return }
            advanceFiniteSelection()
        }
        .onDisappear {
            autoScroll.stop()
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(configuration.isInfinite ? "Loops continuously" : "Scrolls through items")
    }

    private func advanceFiniteSelection() {
        guard configuration.autoScrollEnabled, !items.isEmpty, !isDragging else { return }
        guard let current = selection ?? items.first?.id,
              let index = items.firstIndex(where: { $0.id == current }) else { return }

        let nextIndex = index + 1 < items.count ? index + 1 : 0
        withAnimation(.smooth(duration: 0.55)) {
            selection = items[nextIndex].id
        }

        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
        #endif
    }
}

// MARK: - Finite layout

private struct FiniteCarouselLayout<Item: Identifiable & Hashable, Content: View>: View {
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
                        height: configuration.axis == .vertical ? pageSize.height : nil
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
        } else {
            let height = max(
                size.height
                    - configuration.contentInsets.top
                    - configuration.contentInsets.bottom,
                120
            )
            return CGSize(width: size.width, height: height)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { _ in
                if !isDragging { isDragging = true }
            }
            .onEnded { _ in
                isDragging = false
            }
    }
}

// MARK: - Infinite layout

/// Holds flags/generation without SwiftUI `@State` writes during an in-flight scroll animation.
/// Prior fixes mutated `@State` in `onChange(of: scrollID)` and cancelled the animation,
/// so `scrollPosition` jumped (card swap) instead of sliding.
@MainActor
private final class InfiniteScrollCoordinator: ObservableObject {
    var generation: UInt64 = 0
    var isProgrammaticScroll = false
}

private struct InfiniteCarouselLayout<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    let configuration: CarouselConfiguration
    @Binding var selection: Item.ID?
    @Binding var isDragging: Bool
    var autoAdvanceTick: UInt64
    var autoScrollEnabled: Bool
    @ViewBuilder var content: (Item) -> Content

    /// Triple-buffered strip. Scroll targets use **stable Int indices** (0 ..< 3N).
    private var loopCount: Int { items.count * 3 }

    private var middleStartIndex: Int { items.count }

    @State private var pageIndex: Int?
    @StateObject private var coordinator = InfiniteScrollCoordinator()

    private let slideAnimation = Animation.smooth(duration: 0.55)
    private let slideDuration: TimeInterval = 0.55
    private let recenterDelay: TimeInterval = 0.8

    var body: some View {
        GeometryReader { geometry in
            let pageSize = pageSize(in: geometry.size)

            ScrollViewReader { proxy in
                ScrollView(configuration.axis.scrollAxis, showsIndicators: configuration.showsIndicators) {
                    let layout = configuration.axis == .horizontal
                        ? AnyLayout(HStackLayout(spacing: configuration.spacing))
                        : AnyLayout(VStackLayout(spacing: configuration.spacing))

                    layout {
                        ForEach(0..<loopCount, id: \.self) { index in
                            let item = items[index % items.count]
                            content(item)
                                .frame(
                                    width: configuration.axis == .horizontal ? pageSize.width : nil,
                                    height: configuration.axis == .vertical ? pageSize.height : nil
                                )
                                .containerRelativeFrame(
                                    configuration.axis == .horizontal ? .horizontal : .vertical,
                                    count: 1,
                                    span: 1,
                                    spacing: configuration.spacing,
                                    alignment: .center
                                )
                                // Int id == scrollPosition / scrollTo target. Do not use item.id here —
                                // duplicates across copies would make programmatic scroll ambiguous.
                                .id(index)
                                .accessibilityAddTraits(item.id == selection ? .isSelected : [])
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $pageIndex)
                .contentMargins(
                    configuration.axis == .horizontal ? .horizontal : .vertical,
                    configuration.axis == .horizontal
                        ? configuration.contentInsets.leading
                        : configuration.contentInsets.top,
                    for: .scrollContent
                )
                .simultaneousGesture(dragGesture)
                .onAppear {
                    initializePageIfNeeded(proxy: proxy)
                }
                .onChange(of: autoAdvanceTick) { _, _ in
                    guard autoScrollEnabled, !isDragging else { return }
                    advanceOnePage(proxy: proxy)
                }
                .onChange(of: pageIndex) { _, newValue in
                    handlePageIndexChanged(newValue)
                }
                .onChange(of: isDragging) { _, dragging in
                    if dragging {
                        coordinator.generation &+= 1
                        coordinator.isProgrammaticScroll = false
                    } else {
                        scheduleRecenter(proxy: proxy)
                    }
                }
            }
        }
    }

    private func initializePageIfNeeded(proxy: ScrollViewProxy) {
        guard pageIndex == nil, !items.isEmpty else { return }

        let initialItemID = selection ?? items.first?.id
        let itemOffset = items.firstIndex(where: { $0.id == initialItemID }) ?? 0
        let initial = middleStartIndex + itemOffset

        // Land on middle copy with no animation (first frame only).
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pageIndex = initial
            proxy.scrollTo(initial, anchor: .center)
        }
        selection = items[itemOffset].id
    }

    /// Auto-advance: animate a real scroll to the next adjacent Int page.
    private func advanceOnePage(proxy: ScrollViewProxy) {
        guard !items.isEmpty else { return }

        let current = pageIndex ?? middleStartIndex
        // Always step forward into the buffer; recenter later if we leave the middle copy.
        let next = min(current + 1, loopCount - 1)
        guard next != current else { return }

        coordinator.isProgrammaticScroll = true
        coordinator.generation &+= 1
        let generation = coordinator.generation
        let nextItemID = items[next % items.count].id

        // Primary driver: animated scrollTo — this is what produces the finger-drag slide.
        // Also update pageIndex in the same animation so scrollPosition stays consistent.
        withAnimation(slideAnimation) {
            pageIndex = next
            proxy.scrollTo(next, anchor: .center)
        }

        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
        #endif

        // Defer logical selection until the slide finishes — avoids parent chrome rebuilding
        // mid-animation (page dots / footer) and never uses disablesAnimations here.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(slideDuration * 1_000_000_000))
            guard generation == coordinator.generation else { return }
            if selection != nextItemID {
                selection = nextItemID
            }
            coordinator.isProgrammaticScroll = false
            scheduleRecenter(proxy: proxy)
        }
    }

    private func handlePageIndexChanged(_ newValue: Int?) {
        guard let newValue, !items.isEmpty else { return }
        // User-driven scroll: keep logical selection live. Programmatic path syncs after slide.
        guard !coordinator.isProgrammaticScroll else { return }
        let itemID = items[newValue % items.count].id
        if selection != itemID {
            selection = itemID
        }
    }

    private func scheduleRecenter(proxy: ScrollViewProxy) {
        guard !isDragging, !items.isEmpty else { return }
        coordinator.generation &+= 1
        let generation = coordinator.generation

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(recenterDelay * 1_000_000_000))
            guard generation == coordinator.generation, !isDragging else { return }
            recenterToMiddleCopy(proxy: proxy)
        }
    }

    private func recenterToMiddleCopy(proxy: ScrollViewProxy) {
        guard let current = pageIndex, !items.isEmpty else { return }
        let copy = current / items.count
        guard copy != 1 else { return }

        let offset = current % items.count
        let middle = middleStartIndex + offset

        coordinator.isProgrammaticScroll = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pageIndex = middle
            proxy.scrollTo(middle, anchor: .center)
        }
        coordinator.isProgrammaticScroll = false
    }

    private func pageSize(in size: CGSize) -> CGSize {
        if configuration.axis == .horizontal {
            let width = max(
                size.width
                    - configuration.contentInsets.leading
                    - configuration.contentInsets.trailing,
                120
            )
            return CGSize(width: width, height: max(size.height, 120))
        } else {
            let height = max(
                size.height
                    - configuration.contentInsets.top
                    - configuration.contentInsets.bottom,
                120
            )
            return CGSize(width: max(size.width, 120), height: height)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { _ in
                if !isDragging { isDragging = true }
            }
            .onEnded { _ in
                isDragging = false
            }
    }
}

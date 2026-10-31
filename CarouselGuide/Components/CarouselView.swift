import SwiftUI

/// Shared snapping carousel.
///
/// **Finite and infinite auto-scroll use the same mechanism:**
/// `withAnimation { scrollPositionID = nextAdjacentPageID }` where that binding is
/// exactly what `.scrollPosition(id:)` observes — identical to a user-driven page change.
///
/// Infinite only differs by feeding a triple-buffered page list with unique IDs, then
/// silently recentering onto the middle copy after the animated scroll settles.
///
/// **Init caveat:** the ScrollView starts at content offset 0 (copy 0). If `scrollPositionID`
/// is set to a middle-copy id before layout actually moves there, the first animated
/// advance interpolates from offset 0 across the whole first copy. We pin to middle
/// without animation (and delay the auto-scroll timer) until that settle completes.
struct CarouselView<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    var configuration: CarouselConfiguration = .horizontal
    @Binding var selection: Item.ID?
    @ViewBuilder var content: (Item) -> Content

    @StateObject private var autoScroll = AutoScrollController()
    @State private var isDragging = false

    /// The id `.scrollPosition(id:)` watches. For finite: `"0|itemID"`.
    /// For infinite: `"copy|itemID"` within the looped strip.
    @State private var scrollPositionID: String?
    @State private var isProgrammaticAdvance = false
    /// Infinite: false until we've silently landed on the middle copy after layout.
    @State private var isReadyForAutoAdvance = false

    private var pages: [PageRef<Item>] {
        PageRef<Item>.makePages(from: items, infinite: configuration.isInfinite)
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: "rectangle.stack",
                    description: Text("Provide at least one item to render a carousel.")
                )
            } else {
                PagingScrollLayout(
                    pages: pages,
                    configuration: configuration,
                    scrollPositionID: $scrollPositionID,
                    isDragging: $isDragging,
                    logicalSelection: selection,
                    onScrollViewAppeared: {
                        Task { @MainActor in
                            await pinInfiniteToMiddleCopyIfNeeded()
                        }
                    },
                    content: content
                )
            }
        }
        .onAppear {
            prepareInitialScrollPosition()
            if !configuration.isInfinite {
                isReadyForAutoAdvance = true
                startAutoScrollIfNeeded()
            }
            // Infinite starts the timer only after `pinInfiniteToMiddleCopyIfNeeded`.
        }
        .onChange(of: configuration.isInfinite) { _, isInfinite in
            scrollPositionID = nil
            isReadyForAutoAdvance = !isInfinite
            prepareInitialScrollPosition()
            if isInfinite {
                autoScroll.stop()
                Task { @MainActor in
                    await pinInfiniteToMiddleCopyIfNeeded()
                }
            } else {
                startAutoScrollIfNeeded()
            }
        }
        .onChange(of: configuration.autoScrollEnabled) { _, enabled in
            if enabled, isReadyForAutoAdvance {
                startAutoScrollIfNeeded()
            } else if !enabled {
                autoScroll.stop()
            }
        }
        .onChange(of: configuration.autoScrollInterval) { _, _ in
            if isReadyForAutoAdvance {
                startAutoScrollIfNeeded()
            }
        }
        .onChange(of: isDragging) { _, dragging in
            if dragging {
                isProgrammaticAdvance = false
                autoScroll.pauseForUserInteraction()
            }
        }
        .onChange(of: autoScroll.tick) { _, _ in
            advanceToNextPage()
        }
        .onChange(of: scrollPositionID) { _, newValue in
            handleScrollPositionChanged(newValue)
        }
        .onDisappear {
            autoScroll.stop()
            isReadyForAutoAdvance = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(configuration.isInfinite ? "Loops continuously" : "Scrolls through items")
    }

    private func startAutoScrollIfNeeded() {
        autoScroll.configure(
            enabled: configuration.autoScrollEnabled && isReadyForAutoAdvance,
            interval: configuration.autoScrollInterval
        )
    }

    /// Silently park on the middle-copy page that matches the logical selection, then arm the timer.
    @MainActor
    private func pinInfiniteToMiddleCopyIfNeeded() async {
        guard configuration.isInfinite, !items.isEmpty else {
            isReadyForAutoAdvance = true
            startAutoScrollIfNeeded()
            return
        }

        let pageList: [PageRef<Item>] = pages
        let logical = selection ?? items[0].id
        guard let middleID = PageRef<Item>.middleID(for: logical, in: pageList) else {
            isReadyForAutoAdvance = true
            startAutoScrollIfNeeded()
            return
        }

        // Apply (and re-apply after layout) without animation so the first auto tick
        // only has to move one adjacent page.
        snapScrollPosition(to: middleID)
        try? await Task.sleep(nanoseconds: 50_000_000)
        snapScrollPosition(to: middleID)
        try? await Task.sleep(nanoseconds: 50_000_000)
        snapScrollPosition(to: middleID)

        if selection == nil {
            selection = logical
        }

        isReadyForAutoAdvance = true
        startAutoScrollIfNeeded()
    }

    private func snapScrollPosition(to id: String) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollPositionID = id
        }
    }

    /// Timer fired → animate the ScrollView to the next adjacent page (same as finite).
    private func advanceToNextPage() {
        guard configuration.autoScrollEnabled, isReadyForAutoAdvance else { return }
        guard !items.isEmpty, !isDragging else { return }
        let pageList: [PageRef<Item>] = pages
        guard !pageList.isEmpty else { return }

        // If somehow still off the middle copy (e.g. init race), snap there and skip this tick
        // rather than animating across copy 0.
        if configuration.isInfinite {
            let currentID = scrollPositionID
            let currentPage = currentID.flatMap { id in pageList.first(where: { $0.id == id }) }
            if currentPage == nil || currentPage?.copy != 1 {
                let logical = currentPage?.item.id ?? selection ?? items[0].id
                if let middleID = PageRef<Item>.middleID(for: logical, in: pageList) {
                    snapScrollPosition(to: middleID)
                }
                return
            }
        }

        let currentID = scrollPositionID ?? pageList[configuration.isInfinite ? items.count : 0].id
        guard let currentIndex = pageList.firstIndex(where: { $0.id == currentID }) else { return }

        let nextIndex: Int
        if configuration.isInfinite {
            nextIndex = min(currentIndex + 1, pageList.count - 1)
        } else if currentIndex + 1 < pageList.count {
            nextIndex = currentIndex + 1
        } else {
            nextIndex = 0
        }

        let nextID = pageList[nextIndex].id
        guard nextID != currentID else { return }

        isProgrammaticAdvance = true

        withAnimation(.smooth(duration: 0.55)) {
            scrollPositionID = nextID
        }

        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
        #endif

        let logical = pageList[nextIndex].item.id
        let needsRecenter = configuration.isInfinite && pageList[nextIndex].copy != 1
        let middleID = PageRef<Item>.middleID(for: logical, in: pageList)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 560_000_000)
            if selection != logical {
                selection = logical
            }
            if needsRecenter, let middleID {
                try? await Task.sleep(nanoseconds: 200_000_000)
                snapScrollPosition(to: middleID)
            }
            isProgrammaticAdvance = false
        }
    }

    private func handleScrollPositionChanged(_ newValue: String?) {
        guard let newValue else { return }
        let pageList: [PageRef<Item>] = pages
        guard let page = pageList.first(where: { (page: PageRef<Item>) in page.id == newValue }) else {
            return
        }

        if !isProgrammaticAdvance, selection != page.item.id {
            selection = page.item.id
        }
    }

    private func prepareInitialScrollPosition() {
        guard !items.isEmpty else { return }
        let logical = selection ?? items[0].id
        let pageList: [PageRef<Item>] = pages

        let targetID: String?
        if configuration.isInfinite {
            targetID = PageRef<Item>.middleID(for: logical, in: pageList) ?? pageList[items.count].id
        } else {
            targetID = PageRef<Item>.finiteID(for: logical)
        }

        if let targetID {
            snapScrollPosition(to: targetID)
        }
        if selection == nil {
            selection = logical
        }
    }
}

// MARK: - Page refs (unique scroll targets)

private struct PageRef<Item: Identifiable & Hashable>: Identifiable, Hashable {
    /// Unique scroll-position identity. Finite: `"0|itemID"`. Infinite: `"copy|itemID"`.
    let id: String
    let copy: Int
    let item: Item

    static func finiteID(for itemID: Item.ID) -> String {
        "0|\(String(describing: itemID))"
    }

    static func makeID(copy: Int, itemID: Item.ID) -> String {
        "\(copy)|\(String(describing: itemID))"
    }

    static func makePages(from items: [Item], infinite: Bool) -> [PageRef<Item>] {
        guard !items.isEmpty else { return [] }
        let copies = infinite ? 3 : 1
        return (0..<copies).flatMap { copy in
            items.map { PageRef(id: makeID(copy: copy, itemID: $0.id), copy: copy, item: $0) }
        }
    }

    static func middleID(for itemID: Item.ID, in pages: [PageRef<Item>]) -> String? {
        pages.first(where: { $0.copy == 1 && $0.item.id == itemID })?.id
    }
}

// MARK: - Single paging layout (finite + infinite)

private struct PagingScrollLayout<Item: Identifiable & Hashable, Content: View>: View {
    let pages: [PageRef<Item>]
    let configuration: CarouselConfiguration
    @Binding var scrollPositionID: String?
    @Binding var isDragging: Bool
    var logicalSelection: Item.ID?
    var onScrollViewAppeared: () -> Void
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        GeometryReader { geometry in
            let pageSize = pageSize(in: geometry.size)

            ScrollViewReader { scrollProxy in
                ScrollView(configuration.axis.scrollAxis, showsIndicators: configuration.showsIndicators) {
                    let layout = configuration.axis == .horizontal
                        ? AnyLayout(HStackLayout(spacing: configuration.spacing))
                        : AnyLayout(VStackLayout(spacing: configuration.spacing))

                    layout {
                        ForEach(pages) { page in
                            content(page.item)
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
                                .id(page.id)
                                .accessibilityAddTraits(
                                    page.item.id == logicalSelection ? .isSelected : AccessibilityTraits()
                                )
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrollPositionID)
                .contentMargins(
                    configuration.axis == .horizontal ? .horizontal : .vertical,
                    configuration.axis == .horizontal
                        ? configuration.contentInsets.leading
                        : configuration.contentInsets.top,
                    for: .scrollContent
                )
                .simultaneousGesture(dragGesture)
                .onAppear {
                    // Jump to the prepared middle/finite id without animation (offset starts at 0).
                    if let scrollPositionID {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            scrollProxy.scrollTo(scrollPositionID, anchor: .center)
                        }
                    }
                    onScrollViewAppeared()
                }
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

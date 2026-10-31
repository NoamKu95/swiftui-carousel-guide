import SwiftUI

/// Shared snapping carousel.
///
/// Finite and infinite auto-scroll both animate the binding that `.scrollPosition(id:)` watches.
/// Infinite uses a triple-buffered page list and recenters onto the middle copy after settle.
///
/// **First-tick overshoot:** A ScrollView lays out at content offset 0 (start of copy 0).
/// If `scrollPositionID` is assigned to a middle-copy id *after* that first layout, the binding
/// and the real offset diverge. The first `withAnimation` then interpolates from offset 0 across
/// the whole first copy. Fix: do **not** create the ScrollView until `scrollPositionID` is
/// already the middle-copy (or finite) id, then arm the auto-scroll timer only after layout.
struct CarouselView<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    var configuration: CarouselConfiguration = .horizontal
    @Binding var selection: Item.ID?
    @ViewBuilder var content: (Item) -> Content

    @StateObject private var autoScroll = AutoScrollController()
    @State private var isDragging = false

    /// Binding watched by `.scrollPosition(id:)`. Nil means the pager has not been mounted yet.
    @State private var scrollPositionID: String?
    @State private var isProgrammaticAdvance = false
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
            } else if scrollPositionID == nil {
                // Critical: resolve the target id BEFORE mounting any ScrollView so the first
                // layout is already on the middle copy (infinite) / first page (finite).
                Color.clear
                    .accessibilityHidden(true)
                    .onAppear {
                        assignInitialScrollPositionID()
                    }
            } else {
                PagingScrollLayout(
                    pages: pages,
                    configuration: configuration,
                    scrollPositionID: $scrollPositionID,
                    isDragging: $isDragging,
                    logicalSelection: selection,
                    content: content
                )
                .onAppear {
                    Task { @MainActor in
                        await armAutoScrollAfterPagerLaidOut()
                    }
                }
            }
        }
        .onChange(of: configuration.isInfinite) { _, _ in
            // Remount pager from a fresh initial id.
            autoScroll.stop()
            isReadyForAutoAdvance = false
            scrollPositionID = nil
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

    // MARK: - Init / arming

    /// Sets `scrollPositionID` once. Until this runs, no ScrollView exists.
    private func assignInitialScrollPositionID() {
        guard scrollPositionID == nil, !items.isEmpty else { return }
        let pageList: [PageRef<Item>] = pages
        let logical = selection ?? items[0].id

        let target: String
        if configuration.isInfinite {
            target = PageRef<Item>.middleID(for: logical, in: pageList) ?? pageList[items.count].id
        } else {
            target = PageRef<Item>.finiteID(for: logical)
        }

        // No animation — this is the identity the upcoming ScrollView should be born with.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollPositionID = target
        }
        if selection == nil {
            selection = logical
        }
    }

    @MainActor
    private func armAutoScrollAfterPagerLaidOut() async {
        guard !isReadyForAutoAdvance else { return }

        // Let the newly mounted ScrollView apply scrollPosition during layout.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 32_000_000)

        // Re-assert the same id without animation (no-op if already there; repairs races).
        if let scrollPositionID {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.scrollPositionID = scrollPositionID
            }
        }

        // One more frame so any silent re-assert is committed before the timer can fire.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 32_000_000)

        // Final safety: never arm while infinite binding points outside middle copy.
        if configuration.isInfinite, !isOnMiddleCopy(scrollPositionID) {
            let logical = selection ?? items[0].id
            if let middle = PageRef<Item>.middleID(for: logical, in: pages) {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    scrollPositionID = middle
                }
                await Task.yield()
            }
        }

        isReadyForAutoAdvance = true
        startAutoScrollIfNeeded()
    }

    private func startAutoScrollIfNeeded() {
        autoScroll.configure(
            enabled: configuration.autoScrollEnabled && isReadyForAutoAdvance,
            interval: configuration.autoScrollInterval
        )
    }

    private func isOnMiddleCopy(_ id: String?) -> Bool {
        guard configuration.isInfinite, let id else { return true }
        return pages.first(where: { $0.id == id })?.copy == 1
    }

    // MARK: - Auto-advance

    private func advanceToNextPage() {
        guard configuration.autoScrollEnabled, isReadyForAutoAdvance else { return }
        guard !items.isEmpty, !isDragging else { return }

        let pageList: [PageRef<Item>] = pages
        guard !pageList.isEmpty else { return }

        // Refuse to animate from a non-middle starting point — silent repair, skip this tick.
        if configuration.isInfinite, !isOnMiddleCopy(scrollPositionID) {
            let logical = pageList.first(where: { $0.id == scrollPositionID })?.item.id
                ?? selection
                ?? items[0].id
            if let middle = PageRef<Item>.middleID(for: logical, in: pageList) {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    scrollPositionID = middle
                }
            }
            return
        }

        guard let currentID = scrollPositionID,
              let currentIndex = pageList.firstIndex(where: { $0.id == currentID }) else {
            return
        }

        // Adjacent +1 only (finite wraps).
        let nextIndex: Int
        if configuration.isInfinite {
            nextIndex = min(currentIndex + 1, pageList.count - 1)
        } else if currentIndex + 1 < pageList.count {
            nextIndex = currentIndex + 1
        } else {
            nextIndex = 0
        }

        // Verify adjacency for infinite: must be exactly one step in the buffer.
        if configuration.isInfinite, nextIndex != currentIndex + 1 {
            return
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
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    scrollPositionID = middleID
                }
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
}

// MARK: - Page refs

private struct PageRef<Item: Identifiable & Hashable>: Identifiable, Hashable {
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

// MARK: - Paging layout

private struct PagingScrollLayout<Item: Identifiable & Hashable, Content: View>: View {
    let pages: [PageRef<Item>]
    let configuration: CarouselConfiguration
    @Binding var scrollPositionID: String?
    @Binding var isDragging: Bool
    var logicalSelection: Item.ID?
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        GeometryReader { geometry in
            let pageSize = pageSize(in: geometry.size)

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

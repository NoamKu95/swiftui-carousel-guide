import SwiftUI

/// Shared snapping carousel.
///
/// **Finite and infinite auto-scroll use the same mechanism:**
/// `withAnimation { scrollPositionID = nextAdjacentPageID }` where that binding is
/// exactly what `.scrollPosition(id:)` observes — identical to a user-driven page change.
///
/// Infinite only differs by feeding a triple-buffered page list with unique IDs, then
/// silently recentering onto the middle copy after the animated scroll settles.
struct CarouselView<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    var configuration: CarouselConfiguration = .horizontal
    @Binding var selection: Item.ID?
    @ViewBuilder var content: (Item) -> Content

    @StateObject private var autoScroll = AutoScrollController()
    @State private var isDragging = false

    /// The id `.scrollPosition(id:)` watches. For finite this equals `Item.ID` (stringified).
    /// For infinite this is `"copy|itemID"` for an adjacent page in the looped strip.
    @State private var scrollPositionID: String?
    @State private var isProgrammaticAdvance = false

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
                // ONE layout path for finite and infinite — same ScrollView / scrollPosition.
                PagingScrollLayout(
                    pages: pages,
                    configuration: configuration,
                    scrollPositionID: $scrollPositionID,
                    isDragging: $isDragging,
                    logicalSelection: selection,
                    content: content
                )
            }
        }
        .onAppear {
            bootstrapScrollPositionIfNeeded()
            autoScroll.configure(
                enabled: configuration.autoScrollEnabled,
                interval: configuration.autoScrollInterval
            )
        }
        .onChange(of: configuration.isInfinite) { _, _ in
            scrollPositionID = nil
            bootstrapScrollPositionIfNeeded()
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
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(configuration.isInfinite ? "Loops continuously" : "Scrolls through items")
    }

    /// Timer fired → animate the ScrollView to the next adjacent page (same as finite).
    private func advanceToNextPage() {
        guard configuration.autoScrollEnabled, !items.isEmpty, !isDragging else { return }
        let pageList = pages
        guard !pageList.isEmpty else { return }

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

        // THIS is the scroll: mutate the binding `.scrollPosition(id:)` observes.
        withAnimation(.smooth(duration: 0.55)) {
            scrollPositionID = nextID
        }

        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
        #endif

        let logical = pageList[nextIndex].item.id
        let needsRecenter = configuration.isInfinite && pageList[nextIndex].copy != 1
        let middleID = PageRef<Item>.middleID(for: logical, in: pageList)

        // Sync logical selection + optional silent recenter AFTER the slide completes.
        // Touching selection/recenter in the same turn as the animated scroll was a prior failure mode.
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

        // User-driven scroll: keep logical selection live. Programmatic path syncs after animation.
        if !isProgrammaticAdvance, selection != page.item.id {
            selection = page.item.id
        }
    }

    private func bootstrapScrollPositionIfNeeded() {
        guard scrollPositionID == nil, !items.isEmpty else {
            syncLogicalSelectionFromScrollIfNeeded()
            return
        }
        let logical = selection ?? items[0].id
        let pageList: [PageRef<Item>] = pages
        if configuration.isInfinite {
            scrollPositionID = PageRef<Item>.middleID(for: logical, in: pageList)
                ?? pageList[items.count].id
        } else {
            scrollPositionID = PageRef<Item>.finiteID(for: logical)
        }
        if selection == nil {
            selection = logical
        }
    }

    private func syncLogicalSelectionFromScrollIfNeeded() {
        let pageList: [PageRef<Item>] = pages
        guard let scrollPositionID,
              let page = pageList.first(where: { (page: PageRef<Item>) in page.id == scrollPositionID }),
              selection != page.item.id else { return }
        selection = page.item.id
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

/// Exact finite-style pager. Infinite just passes more `pages` with unique ids.
private struct PagingScrollLayout<Item: Identifiable & Hashable, Content: View>: View {
    let pages: [PageRef<Item>]
    let configuration: CarouselConfiguration
    @Binding var scrollPositionID: String?
    @Binding var isDragging: Bool
    var logicalSelection: Item.ID?
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        GeometryReader { proxy in
            let pageSize = pageSize(in: proxy.size)

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
            // Reinforce programmatic page changes (timer / binding writes).
            .animation(.smooth(duration: 0.55), value: scrollPositionID)
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

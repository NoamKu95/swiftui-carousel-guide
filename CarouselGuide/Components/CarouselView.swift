import SwiftUI

/// A reusable snapping carousel for finite or infinite (seamless looping) content.
///
/// - Finite: scrolls through `items` once with natural start/end boundaries.
/// - Infinite: repeats the dataset and recenters so looping feels continuous.
/// - Auto-scroll: advances on an interval, pauses while the user drags, then resumes.
///
/// Infinite auto-scroll mirrors finite: `withAnimation` writes the **scroll-position id**
/// directly (an adjacent looped page id). Logical `selection` is synced on the next
/// run-loop turn so no `disablesAnimations` transaction can cancel the scroll move.
struct CarouselView<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    var configuration: CarouselConfiguration = .horizontal
    @Binding var selection: Item.ID?
    @ViewBuilder var content: (Item) -> Content

    @StateObject private var autoScroll = AutoScrollController()
    @State private var isDragging = false
    /// Scroll-position identity for infinite mode (`"copy-itemID"`). Owned here so auto-advance
    /// mutates it inside the same `withAnimation` call stack as finite `selection` updates.
    @State private var infiniteScrollID: String?

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
                    scrollID: $infiniteScrollID,
                    isDragging: $isDragging,
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
            if configuration.isInfinite, infiniteScrollID == nil {
                infiniteScrollID = LoopedIdentity.middleCopyID(
                    for: selection ?? items.first?.id,
                    items: items
                )
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
            advanceSelection()
        }
        .onDisappear {
            autoScroll.stop()
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(configuration.isInfinite ? "Loops continuously" : "Scrolls through items")
    }

    private func advanceSelection() {
        guard configuration.autoScrollEnabled, !items.isEmpty, !isDragging else { return }

        // Critical: animate the binding that `.scrollPosition(id:)` observes — same as finite.
        withAnimation(.smooth(duration: 0.55)) {
            if configuration.isInfinite {
                infiniteScrollID = LoopedIdentity.nextAdjacentID(
                    items: items,
                    currentScrollID: infiniteScrollID,
                    fallbackItemID: selection
                )
            } else {
                guard let current = selection ?? items.first?.id,
                      let index = items.firstIndex(where: { $0.id == current }) else { return }
                let nextIndex = index + 1 < items.count ? index + 1 : 0
                selection = items[nextIndex].id
            }
        }

        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
        #endif
    }
}

// MARK: - Looped identity helpers

private enum LoopedIdentity {
    static func makeID<ID: Hashable>(copy: Int, itemID: ID) -> String {
        "\(copy)-\(String(describing: itemID))"
    }

    static func middleCopyID<Item: Identifiable>(
        for itemID: Item.ID?,
        items: [Item]
    ) -> String? {
        guard let itemID else {
            guard let first = items.first?.id else { return nil }
            return makeID(copy: 1, itemID: first)
        }
        return makeID(copy: 1, itemID: itemID)
    }

    /// Next page in the triple-buffered strip (always +1) so the scroll view moves forward.
    static func nextAdjacentID<Item: Identifiable>(
        items: [Item],
        currentScrollID: String?,
        fallbackItemID: Item.ID?
    ) -> String? {
        let loopedIDs: [String] = (0..<3).flatMap { copy in
            items.map { makeID(copy: copy, itemID: $0.id) }
        }
        guard !loopedIDs.isEmpty else { return nil }

        let currentIndex: Int = {
            if let currentScrollID,
               let index = loopedIDs.firstIndex(of: currentScrollID) {
                return index
            }
            if let fallbackItemID,
               let index = loopedIDs.firstIndex(of: makeID(copy: 1, itemID: fallbackItemID)) {
                return index
            }
            return loopedIDs.firstIndex(of: makeID(copy: 1, itemID: items[0].id)) ?? 0
        }()

        if currentIndex + 1 < loopedIDs.count {
            return loopedIDs[currentIndex + 1]
        }

        let itemIndex = currentIndex % max(items.count, 1)
        let nextItemIndex = (itemIndex + 1) % items.count
        return makeID(copy: 1, itemID: items[nextItemIndex].id)
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
                    .modifier(SelectedTraitModifier(isSelected: item.id == selection))
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

private struct SelectedTraitModifier: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        // Avoid `if isSelected` branching — that swaps view identity mid-scroll and can
        // cancel `scrollPosition` animation (especially in infinite mode).
        content.accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Infinite layout

private struct InfiniteCarouselLayout<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    let configuration: CarouselConfiguration
    @Binding var selection: Item.ID?
    /// Parent-owned scroll position — auto-advance mutates this under `withAnimation`.
    @Binding var scrollID: String?
    @Binding var isDragging: Bool
    @ViewBuilder var content: (Item) -> Content

    private var loopedItems: [LoopedItem<Item>] {
        guard !items.isEmpty else { return [] }
        return (0..<3).flatMap { copy in
            items.map { LoopedItem(copy: copy, item: $0) }
        }
    }

    @State private var isRecentering = false
    @State private var recenterWorkItem: DispatchWorkItem?
    @State private var suppressSelectionToScrollSync = false

    private let scrollAnimation = Animation.smooth(duration: 0.55)
    private let recenterDelay: TimeInterval = 0.75

    var body: some View {
        GeometryReader { proxy in
            let pageSize = pageSize(in: proxy.size)

            ScrollView(configuration.axis.scrollAxis, showsIndicators: configuration.showsIndicators) {
                let layout = configuration.axis == .horizontal
                    ? AnyLayout(HStackLayout(spacing: configuration.spacing))
                    : AnyLayout(VStackLayout(spacing: configuration.spacing))

                layout {
                    ForEach(loopedItems) { looped in
                        content(looped.item)
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
                            .id(looped.id)
                            .modifier(SelectedTraitModifier(isSelected: looped.item.id == selection))
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrollID)
            .contentMargins(
                configuration.axis == .horizontal ? .horizontal : .vertical,
                configuration.axis == .horizontal
                    ? configuration.contentInsets.leading
                    : configuration.contentInsets.top,
                for: .scrollContent
            )
            .simultaneousGesture(dragGesture)
            .onAppear {
                if scrollID == nil {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        scrollID = LoopedIdentity.middleCopyID(
                            for: selection ?? items.first?.id,
                            items: items
                        )
                    }
                }
            }
            .onDisappear {
                recenterWorkItem?.cancel()
                recenterWorkItem = nil
            }
            .onChange(of: scrollID) { _, newValue in
                handleScrollIDChange(to: newValue)
            }
            .onChange(of: selection) { _, newValue in
                handleExternalSelectionChange(newValue)
            }
            .onChange(of: isDragging) { _, dragging in
                if dragging {
                    recenterWorkItem?.cancel()
                } else {
                    scheduleRecenterAfterScrollSettles()
                }
            }
        }
    }

    private func handleScrollIDChange(to newValue: String?) {
        guard !isRecentering, let newValue else { return }
        guard let match = loopedItems.first(where: { $0.id == newValue }) else { return }

        // Sync logical selection after the scroll animation completes.
        // Updating selection in the same turn (especially with disablesAnimations)
        // was cancelling `scrollPosition` animation and looked like a card jump.
        let itemID = match.item.id
        suppressSelectionToScrollSync = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) {
            if selection != itemID {
                selection = itemID
            }
            suppressSelectionToScrollSync = false
        }

        scheduleRecenterAfterScrollSettles()
    }

    private func handleExternalSelectionChange(_ itemID: Item.ID?) {
        guard !isRecentering, !suppressSelectionToScrollSync, let itemID else { return }

        if let scrollID,
           let match = loopedItems.first(where: { $0.id == scrollID }),
           match.item.id == itemID {
            return
        }

        guard let target = nearestLoopedItem(for: itemID) else { return }

        withAnimation(scrollAnimation) {
            scrollID = target.id
        }
    }

    private func nearestLoopedItem(for itemID: Item.ID) -> LoopedItem<Item>? {
        let matches = loopedItems.filter { $0.item.id == itemID }
        guard !matches.isEmpty else { return nil }

        guard let scrollID,
              let currentIndex = loopedItems.firstIndex(where: { $0.id == scrollID }) else {
            return matches.first(where: { $0.copy == 1 }) ?? matches.first
        }

        return matches.min { lhs, rhs in
            let left = loopedItems.firstIndex(where: { $0.id == lhs.id }).map { abs($0 - currentIndex) } ?? .max
            let right = loopedItems.firstIndex(where: { $0.id == rhs.id }).map { abs($0 - currentIndex) } ?? .max
            return left < right
        }
    }

    private func scheduleRecenterAfterScrollSettles() {
        guard !isDragging else { return }
        recenterWorkItem?.cancel()

        let work = DispatchWorkItem {
            recenterIfNeeded(force: false)
        }
        recenterWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + recenterDelay, execute: work)
    }

    private func recenterIfNeeded(force: Bool) {
        guard !items.isEmpty, !isDragging else { return }

        let preferredCopy = 1
        let current: LoopedItem<Item>? = {
            if let scrollID,
               let match = loopedItems.first(where: { $0.id == scrollID }) {
                return match
            }
            if let selection,
               let match = loopedItems.first(where: { $0.copy == preferredCopy && $0.item.id == selection }) {
                return match
            }
            return loopedItems.first(where: { $0.copy == preferredCopy })
        }()

        guard let current else { return }
        let shouldRecenter = force || current.copy != preferredCopy
        guard shouldRecenter else { return }

        guard let middle = loopedItems.first(where: {
            $0.copy == preferredCopy && $0.item.id == current.item.id
        }) else { return }

        isRecentering = true
        suppressSelectionToScrollSync = true

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollID = middle.id
        }

        DispatchQueue.main.async {
            isRecentering = false
            suppressSelectionToScrollSync = false
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

private struct LoopedItem<Item: Identifiable & Hashable>: Identifiable, Hashable {
    let copy: Int
    let item: Item

    var id: String {
        LoopedIdentity.makeID(copy: copy, itemID: item.id)
    }
}

import SwiftUI

/// A reusable snapping carousel for finite or infinite (seamless looping) content.
///
/// - Finite: scrolls through `items` once with natural start/end boundaries.
/// - Infinite: repeats the dataset and recenters so looping feels continuous.
/// - Auto-scroll: advances on an interval, pauses while the user drags, then resumes.
struct CarouselView<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    var configuration: CarouselConfiguration = .horizontal
    @Binding var selection: Item.ID?
    @ViewBuilder var content: (Item) -> Content

    @StateObject private var autoScroll = AutoScrollController()
    @State private var isDragging = false
    /// Bumped on each auto-advance tick so infinite layouts can scroll to the next adjacent page.
    @State private var autoAdvanceToken: UInt64 = 0

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
                    autoAdvanceToken: autoAdvanceToken,
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

        if configuration.isInfinite {
            // Infinite layout consumes this token and animates to the next adjacent looped page.
            autoAdvanceToken &+= 1
        } else {
            guard let current = selection ?? items.first?.id,
                  let index = items.firstIndex(where: { $0.id == current }) else { return }

            let nextIndex = index + 1 < items.count ? index + 1 : 0
            withAnimation(.smooth(duration: 0.55)) {
                selection = items[nextIndex].id
            }
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
        if isSelected {
            content.accessibilityAddTraits(.isSelected)
        } else {
            content
        }
    }
}

// MARK: - Infinite layout

private struct InfiniteCarouselLayout<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    let configuration: CarouselConfiguration
    @Binding var selection: Item.ID?
    @Binding var isDragging: Bool
    var autoAdvanceToken: UInt64
    @ViewBuilder var content: (Item) -> Content

    /// Three copies keep the active window away from either edge.
    private var loopedItems: [LoopedItem<Item>] {
        guard !items.isEmpty else { return [] }
        return (0..<3).flatMap { copy in
            items.map { item in
                LoopedItem(copy: copy, item: item)
            }
        }
    }

    @State private var loopSelection: LoopedItem<Item>.ID?
    @State private var isRecentering = false
    @State private var recenterWorkItem: DispatchWorkItem?

    private let scrollAnimation = Animation.smooth(duration: 0.55)
    private let recenterDelay: TimeInterval = 0.7

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
            .scrollPosition(id: $loopSelection)
            .contentMargins(
                configuration.axis == .horizontal ? .horizontal : .vertical,
                configuration.axis == .horizontal
                    ? configuration.contentInsets.leading
                    : configuration.contentInsets.top,
                for: .scrollContent
            )
            .simultaneousGesture(dragGesture)
            .onAppear {
                recenterIfNeeded(force: true)
            }
            .onDisappear {
                recenterWorkItem?.cancel()
                recenterWorkItem = nil
            }
            .onChange(of: autoAdvanceToken) { _, _ in
                advanceToNextAdjacentPage()
            }
            .onChange(of: selection) { _, newValue in
                // External selection changes (page dots / parent) — prefer an adjacent copy so we scroll.
                syncLoopSelectionToward(newValue)
            }
            .onChange(of: loopSelection) { _, newValue in
                guard !isRecentering, let newValue else { return }
                if let match = loopedItems.first(where: { $0.id == newValue }) {
                    if selection != match.item.id {
                        // Keep logical selection in sync without requesting another scroll.
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            selection = match.item.id
                        }
                    }
                }
                scheduleRecenterAfterScrollSettles()
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

    /// Auto-scroll: always move one page forward in the looped buffer so `scrollPosition` animates.
    private func advanceToNextAdjacentPage() {
        guard !items.isEmpty, !isDragging else { return }

        let currentIndex: Int = {
            if let loopSelection,
               let index = loopedItems.firstIndex(where: { $0.id == loopSelection }) {
                return index
            }
            if let selection,
               let index = loopedItems.firstIndex(where: { $0.copy == 1 && $0.item.id == selection }) {
                return index
            }
            return loopedItems.firstIndex(where: { $0.copy == 1 }) ?? 0
        }()

        let nextIndex = min(currentIndex + 1, loopedItems.count - 1)
        let next = loopedItems[nextIndex]

        withAnimation(scrollAnimation) {
            loopSelection = next.id
        }
    }

    /// When the parent changes logical selection, scroll to the nearest matching looped page.
    private func syncLoopSelectionToward(_ itemID: Item.ID?) {
        guard let itemID, !isRecentering else { return }

        if let current = loopSelection,
           let match = loopedItems.first(where: { $0.id == current }),
           match.item.id == itemID {
            return
        }

        guard let target = nearestLoopedItem(for: itemID) else { return }

        withAnimation(scrollAnimation) {
            loopSelection = target.id
        }
    }

    private func nearestLoopedItem(for itemID: Item.ID) -> LoopedItem<Item>? {
        let matches = loopedItems.filter { $0.item.id == itemID }
        guard !matches.isEmpty else { return nil }

        guard let loopSelection,
              let currentIndex = loopedItems.firstIndex(where: { $0.id == loopSelection }) else {
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
            if let loopSelection,
               let match = loopedItems.first(where: { $0.id == loopSelection }) {
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

        if let middle = loopedItems.first(where: { $0.copy == preferredCopy && $0.item.id == current.item.id }) {
            isRecentering = true
            // Jump without animation so the loop seam stays invisible — only after scroll has settled.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                loopSelection = middle.id
            }
            DispatchQueue.main.async { isRecentering = false }
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

private struct LoopedItem<Item: Identifiable & Hashable>: Identifiable, Hashable {
    let copy: Int
    let item: Item

    var id: String { "\(copy)-\(item.id)" }
}

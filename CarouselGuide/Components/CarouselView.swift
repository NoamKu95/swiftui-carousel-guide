import SwiftUI

/// A reusable snapping carousel for finite or infinite (seamless looping) content.
///
/// - **Finite:** pure SwiftUI `ScrollView` + `scrollPosition(id:)` — auto-advance animates
///   by writing the next item id under `withAnimation` (works well for a non-looping set).
/// - **Infinite:** UIKit `UIScrollView` representable — SwiftUI programmatic
///   `scrollPosition` / `scrollTo` only *snapped* (card replace, no slide) for the
///   triple-buffer infinite layout, while manual dragging still scrolled. Auto-advance
///   uses `setContentOffset(_:animated:)` so neighboring cards visibly slide on both axes.
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
                // Same GeometryReader shell as FiniteCarouselLayout so the pager is sized to the
                // stage — not to UIScrollView.contentSize (that made infinite H cards much taller).
                GeometryReader { _ in
                    InfinitePagingScrollView(
                        items: items,
                        axis: configuration.axis,
                        spacing: configuration.spacing,
                        contentInsets: configuration.contentInsets,
                        selection: resolvedSelection,
                        isDragging: $isDragging,
                        autoAdvanceTick: autoScroll.tick,
                        autoScrollEnabled: configuration.autoScrollEnabled,
                        pageBuilder: content
                    )
                }
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
            // Finite only — infinite consumes `autoScroll.tick` inside the UIKit representable.
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

// MARK: - Finite layout (pure SwiftUI)

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
                        let horizontalHeight = CarouselHorizontalMetrics.pageItemHeight(
                            forPageWidth: pageSize.width
                        )
                        content(item)
                            .containerRelativeFrame(
                                configuration.axis == .horizontal ? .horizontal : .vertical,
                                count: 1,
                                span: 1,
                                spacing: configuration.spacing,
                                alignment: .center
                            )
                            // Apply exact size AFTER containerRelativeFrame so H height is the
                            // shared metrics value (not the stage). Matches infinite UIKit hosts.
                            .frame(
                                width: configuration.axis == .horizontal ? pageSize.width : nil,
                                height: configuration.axis == .horizontal
                                    ? horizontalHeight
                                    : pageSize.height
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

import SwiftUI

/// Reusable snapping carousel for finite or infinite (seamless looping) content.
///
/// - **Finite:** SwiftUI `ScrollView` + `scrollPosition(id:)` — auto-advance animates
///   by writing the next item id under `withAnimation`.
/// - **Infinite:** UIKit `UIScrollView` representable — `setContentOffset(_:animated:)`
///   so neighboring cards visibly slide on both axes (SwiftUI programmatic scroll
///   only snapped for the triple-buffer layout).
///
/// Both paths publish continuous `scrubProgress` so page indicators can morph
/// mid-swipe (and during auto-advance), not only on page settle.
struct CarouselView<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    var configuration: CarouselConfiguration = .horizontal
    @Binding var selection: Item.ID?
    /// Continuous page position (`0..<count`, fractional while scrolling).
    @Binding var scrubProgress: CGFloat
    @ViewBuilder var content: (Item) -> Content

    @StateObject private var autoScroll = AutoScrollController()
    @State private var isDragging = false

    private var resolvedSelection: Binding<Item.ID?> {
        Binding(
            get: { selection ?? items.first?.id },
            set: { selection = $0 }
        )
    }

    init(
        items: [Item],
        configuration: CarouselConfiguration = .horizontal,
        selection: Binding<Item.ID?>,
        scrubProgress: Binding<CGFloat> = .constant(0),
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.configuration = configuration
        self._selection = selection
        self._scrubProgress = scrubProgress
        self.content = content
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
                GeometryReader { geo in
                    InfinitePagingScrollView(
                        items: items,
                        axis: configuration.axis,
                        spacing: configuration.spacing,
                        contentInsets: configuration.contentInsets,
                        selection: resolvedSelection,
                        isDragging: $isDragging,
                        scrubProgress: $scrubProgress,
                        autoAdvanceTick: autoScroll.tick,
                        autoScrollEnabled: configuration.autoScrollEnabled,
                        pageBuilder: content
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            } else {
                FiniteCarouselLayout(
                    items: items,
                    configuration: configuration,
                    selection: resolvedSelection,
                    isDragging: $isDragging,
                    scrubProgress: $scrubProgress,
                    content: content
                )
            }
        }
        .onAppear {
            if selection == nil {
                selection = items.first?.id
            }
            if let selection,
               let index = items.firstIndex(where: { $0.id == selection }) {
                scrubProgress = CGFloat(index)
            }
            syncAutoScroll()
        }
        .onChange(of: configuration.autoScrollEnabled) { _, _ in syncAutoScroll() }
        .onChange(of: configuration.autoScrollInterval) { _, _ in syncAutoScroll() }
        .onChange(of: isDragging) { _, dragging in
            if dragging {
                autoScroll.pauseForUserInteraction()
            }
        }
        .onChange(of: autoScroll.tick) { _, _ in
            guard !configuration.isInfinite else { return }
            advanceFiniteSelection()
        }
        .onDisappear {
            autoScroll.stop()
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(configuration.isInfinite ? "Loops continuously" : "Scrolls through items")
    }

    private func syncAutoScroll() {
        autoScroll.configure(
            enabled: configuration.autoScrollEnabled,
            interval: configuration.autoScrollInterval
        )
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

import SwiftUI

/// Shared carousel entry point.
///
/// - **Finite:** SwiftUI `ScrollView` + `scrollPosition(id:)` — auto-advance animates that binding.
/// - **Infinite:** `InfiniteUIScrollPager` (UIKit). SwiftUI could not prove the first layout was on
///   the middle copy (offset stayed 0), so the first animated tick overshot. UIKit pins with
///   `setContentOffset(animated: false)`, **verifies** the measured offset, then arms the timer.
///   Advances use `setContentOffset(animated: true)` with an exact +1 page delta.
struct CarouselView<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    var configuration: CarouselConfiguration = .horizontal
    @Binding var selection: Item.ID?
    @ViewBuilder var content: (Item) -> Content

    @StateObject private var autoScroll = AutoScrollController()
    @State private var isDragging = false
    /// Infinite: false until UIKit reports a verified middle-copy content offset.
    @State private var infinitePagerReady = false

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
                InfiniteUIScrollPager(
                    items: items,
                    axis: configuration.axis,
                    spacing: configuration.spacing,
                    contentInsets: configuration.contentInsets,
                    selection: resolvedSelection,
                    isDragging: $isDragging,
                    autoAdvanceTick: autoScroll.tick,
                    autoScrollEnabled: configuration.autoScrollEnabled && infinitePagerReady,
                    onReady: {
                        infinitePagerReady = true
                        startAutoScrollIfNeeded()
                    },
                    pageBuilder: content
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
            if configuration.isInfinite {
                // Timer stays off until `onReady` from the verified middle pin.
                infinitePagerReady = false
                autoScroll.stop()
            } else {
                infinitePagerReady = true
                startAutoScrollIfNeeded()
            }
        }
        .onChange(of: configuration.isInfinite) { _, isInfinite in
            autoScroll.stop()
            infinitePagerReady = !isInfinite
            if !isInfinite {
                startAutoScrollIfNeeded()
            }
        }
        .onChange(of: configuration.autoScrollEnabled) { _, enabled in
            if enabled {
                startAutoScrollIfNeeded()
            } else {
                autoScroll.stop()
            }
        }
        .onChange(of: configuration.autoScrollInterval) { _, _ in
            startAutoScrollIfNeeded()
        }
        .onChange(of: isDragging) { _, dragging in
            if dragging {
                autoScroll.pauseForUserInteraction()
            }
        }
        .onChange(of: autoScroll.tick) { _, _ in
            // Infinite consumes ticks inside the UIKit representable (only when ready).
            guard !configuration.isInfinite else { return }
            advanceFiniteSelection()
        }
        .onDisappear {
            autoScroll.stop()
            infinitePagerReady = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(configuration.isInfinite ? "Loops continuously" : "Scrolls through items")
    }

    private func startAutoScrollIfNeeded() {
        let enabled = configuration.autoScrollEnabled
            && (!configuration.isInfinite || infinitePagerReady)
        autoScroll.configure(enabled: enabled, interval: configuration.autoScrollInterval)
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

// MARK: - Finite (pure SwiftUI)

private struct FiniteCarouselLayout<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    let configuration: CarouselConfiguration
    @Binding var selection: Item.ID?
    @Binding var isDragging: Bool
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        GeometryReader { geometry in
            let pageSize = pageSize(in: geometry.size)

            ScrollView(configuration.axis.scrollAxis, showsIndicators: configuration.showsIndicators) {
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
                            .accessibilityAddTraits(
                                item.id == selection ? .isSelected : AccessibilityTraits()
                            )
                    }
                }
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

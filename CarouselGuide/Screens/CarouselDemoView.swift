import SwiftUI

struct CarouselDemoView: View {
    let kind: DemoKind

    @State private var autoScrollEnabled = true
    @State private var selection: String?
    @State private var stackedIndex: Int = 0
    @State private var interval: Double = 3.0
    @StateObject private var stackedAutoScroll = AutoScrollController()

    private var configuration: CarouselConfiguration {
        var config = kind.configuration
        config.autoScrollEnabled = autoScrollEnabled
        config.autoScrollInterval = interval
        return config
    }

    private var currentIndex: Int {
        if kind.isStackedThreeInfinite {
            return stackedIndex
        }
        guard let selection,
              let index = kind.items.firstIndex(where: { $0.id == selection }) else {
            return 0
        }
        return index
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

            carouselStage
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .background(demoBackground)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selection = kind.items.first?.id
            stackedIndex = 0
            syncStackedAutoScroll()
        }
        .onChange(of: autoScrollEnabled) { _, _ in
            syncStackedAutoScroll()
        }
        .onChange(of: interval) { _, _ in
            syncStackedAutoScroll()
        }
        .onDisappear {
            stackedAutoScroll.stop()
        }
    }

    private func syncStackedAutoScroll() {
        guard kind.isStackedThreeInfinite else {
            stackedAutoScroll.stop()
            return
        }
        stackedAutoScroll.configure(enabled: autoScrollEnabled, interval: interval)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Scroll mode", selection: $autoScrollEnabled) {
                Text("Auto").tag(true)
                Text("Manual").tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Scroll mode")

            if autoScrollEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Interval")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(interval, format: .number.precision(.fractionLength(1)))s")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $interval, in: 1.5...5.0, step: 0.5)
                        .tint(.primary)
                        .accessibilityLabel("Auto-scroll interval")
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Text(modeCaption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.easeInOut(duration: 0.2), value: autoScrollEnabled)
    }

    private var modeCaption: String {
        if kind.isStackedThreeInfinite {
            return autoScrollEnabled
                ? "Center card is focused; neighbors peek above and below. Auto-advances the stack."
                : "Swipe the stack to change the focused card. Neighbors stay visible with scale."
        }
        if autoScrollEnabled {
            return kind.configuration.isInfinite
                ? "Auto-advances forever. Dragging pauses playback, then it resumes after a short delay."
                : "Auto-advances through the set and wraps to the start. Dragging pauses, then playback resumes."
        }
        return "Manual only — nothing advances until you scroll or swipe."
    }

    private var carouselStage: some View {
        Group {
            if kind.isStackedThreeInfinite {
                stackedStage
            } else {
                pagedStage
            }
        }
    }

    private var pagedStage: some View {
        ZStack(alignment: kind.configuration.axis == .horizontal ? .bottom : .trailing) {
            CarouselView(
                items: kind.items,
                configuration: configuration,
                selection: $selection
            ) { item in
                SampleCardView(
                    item: item,
                    style: kind.configuration.axis == .vertical ? .compact : .featured
                )
                .padding(
                    kind.configuration.axis == .horizontal
                        ? EdgeInsets(top: 8, leading: 0, bottom: 28, trailing: 0)
                        : EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 36)
                )
            }

            PageIndicatorView(
                count: kind.items.count,
                currentIndex: currentIndex,
                axis: kind.configuration.axis
            )
            .padding(kind.configuration.axis == .horizontal ? 12 : 16)
        }
        .padding(.horizontal, kind.configuration.axis == .vertical ? 12 : 0)
    }

    /// Matches JuniorCardSelectionSV: carousel + trailing indicator, height from width.
    private var stackedStage: some View {
        GeometryReader { geo in
            let indicatorWidth: CGFloat = 4
            let spacing: CGFloat = 16
            let carouselWidth = max(geo.size.width - indicatorWidth - spacing, 120)
            let aspect: CGFloat = 1.586
            let stackHeight = StackedInfiniteCarouselView<CarouselItem, EmptyView>
                .stackExtent(forCardCrossAxis: carouselWidth, aspectRatio: aspect)

            HStack(spacing: spacing) {
                StackedInfiniteCarouselView(
                    items: kind.items,
                    currentIndex: $stackedIndex,
                    axis: .vertical,
                    cardAspectRatio: aspect,
                    autoAdvanceTick: stackedAutoScroll.tick,
                    autoScrollEnabled: autoScrollEnabled,
                    onUserDrag: { stackedAutoScroll.pauseForUserInteraction() }
                ) { item in
                    SampleCardView(item: item, style: .featured)
                }
                // Height from stackExtent so ±1 neighbors fit without clipping.
                .frame(width: carouselWidth, height: stackHeight)

                PageIndicatorView(
                    count: kind.items.count,
                    currentIndex: stackedIndex,
                    axis: .vertical
                )
                .frame(width: indicatorWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .padding(.horizontal, 20)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label(
                kind.isStackedThreeInfinite
                    ? "3-up infinite stack"
                    : (kind.configuration.isInfinite ? "Infinite loop" : "Finite range"),
                systemImage: kind.isStackedThreeInfinite
                    ? "rectangle.stack"
                    : (kind.configuration.isInfinite ? "infinity" : "arrow.left.arrow.right")
            )
            .foregroundStyle(.secondary)

            Spacer()

            Text("\(currentIndex + 1) / \(kind.items.count)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
                .accessibilityLabel("Item \(currentIndex + 1) of \(kind.items.count)")
        }
        .font(.subheadline)
    }

    private var demoBackground: some View {
        LinearGradient(
            colors: [
                Color.primary.opacity(0.05),
                Color.secondary.opacity(0.08)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .background(Color(.systemBackground))
        .ignoresSafeArea()
    }
}

#Preview("Horizontal") {
    NavigationStack {
        CarouselDemoView(kind: .horizontal)
    }
}

#Preview("3-Up Stack") {
    NavigationStack {
        CarouselDemoView(kind: .stackedThreeInfinite)
    }
}

import SwiftUI
import UIKit

/// Shared demo shell: Auto/Manual controls, stage, and footer for every `DemoKind`.
struct CarouselDemoView: View {
    let kind: DemoKind

    @State private var autoScrollEnabled = true
    @State private var selection: String?
    @State private var stackedIndex = 0
    @State private var interval = 1.5
    @StateObject private var stackedAutoScroll = AutoScrollController()

    private var configuration: CarouselConfiguration {
        var config = kind.configuration
        config.autoScrollEnabled = autoScrollEnabled
        config.autoScrollInterval = interval
        return config
    }

    private var currentIndex: Int {
        if kind.isStacked { return stackedIndex }
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
        // Chevron only — hide the previous screen’s “Carousels” label.
        .background(MinimalBackButtonTitle())
        .onAppear {
            selection = kind.items.first?.id
            stackedIndex = 0
            syncStackedAutoScroll()
        }
        .onChange(of: autoScrollEnabled) { _, _ in syncStackedAutoScroll() }
        .onChange(of: interval) { _, _ in syncStackedAutoScroll() }
        .onDisappear { stackedAutoScroll.stop() }
    }

    private func syncStackedAutoScroll() {
        guard kind.isStacked else {
            stackedAutoScroll.stop()
            return
        }
        stackedAutoScroll.configure(enabled: autoScrollEnabled, interval: interval)
    }

    // MARK: - Controls

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

            Text(kind.modeCaption(autoScrollEnabled: autoScrollEnabled))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.easeInOut(duration: 0.2), value: autoScrollEnabled)
    }

    // MARK: - Stages

    @ViewBuilder
    private var carouselStage: some View {
        if kind.isStacked {
            stackedStage
        } else {
            pagedStage
        }
    }

    private var pagedStage: some View {
        ZStack(alignment: kind.axis == .horizontal ? .bottom : .trailing) {
            CarouselView(
                items: kind.items,
                configuration: configuration,
                selection: $selection
            ) { item in
                SampleCardView(
                    item: item,
                    style: kind.axis == .vertical ? .compact : .featured
                )
                .padding(
                    kind.axis == .horizontal
                        ? EdgeInsets(top: 8, leading: 0, bottom: 28, trailing: 0)
                        : EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 36)
                )
            }

            PageIndicatorView(
                count: kind.items.count,
                currentIndex: currentIndex,
                axis: kind.axis
            )
            .padding(kind.axis == .horizontal ? 12 : 16)
        }
        .padding(.horizontal, kind.axis == .vertical ? 12 : 0)
    }

    private var stackedStage: some View {
        let axis = kind.axis
        return GeometryReader { geo in
            let aspect = StackCarouselMetrics.creditCardAspectRatio
            let spacing: CGFloat = 20

            if axis == .horizontal {
                horizontalStackedStage(geo: geo, aspect: aspect, spacing: spacing)
            } else {
                verticalStackedStage(geo: geo, aspect: aspect, spacing: spacing)
            }
        }
        .padding(.horizontal, kind.axis == .horizontal ? 12 : 20)
    }

    private func horizontalStackedStage(geo: GeometryProxy, aspect: CGFloat, spacing: CGFloat) -> some View {
        let indicatorRow: CGFloat = 28
        let shadowPad: CGFloat = 18
        let availableHeight = max(geo.size.height - indicatorRow - spacing - shadowPad, 160)
        let targetCardWidth = geo.size.width * StackCarouselMetrics.horizontalFocusWidthRatio
        let cardHeight = min(availableHeight, targetCardWidth / aspect)

        return VStack(spacing: spacing) {
            StackedInfiniteCarouselView(
                items: kind.items,
                currentIndex: $stackedIndex,
                axis: .horizontal,
                cardAspectRatio: aspect,
                autoAdvanceTick: stackedAutoScroll.tick,
                autoScrollEnabled: autoScrollEnabled,
                onUserDrag: { stackedAutoScroll.pauseForUserInteraction() }
            ) { item in
                SampleCardView(item: item, style: .featured)
            }
            .frame(maxWidth: .infinity)
            .frame(height: cardHeight)
            .padding(.bottom, shadowPad)

            PageIndicatorView(
                count: kind.items.count,
                currentIndex: stackedIndex,
                axis: .horizontal
            )
            .frame(height: indicatorRow)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func verticalStackedStage(geo: GeometryProxy, aspect: CGFloat, spacing: CGFloat) -> some View {
        let indicatorThickness: CGFloat = 8
        let carouselWidth = max(geo.size.width - indicatorThickness - spacing, 120)
        let stackHeight = StackCarouselMetrics.stackExtent(
            forCardCrossAxis: carouselWidth,
            aspectRatio: aspect,
            axis: .vertical,
            itemCount: kind.items.count
        )

        return HStack(spacing: spacing) {
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
            .frame(width: carouselWidth, height: stackHeight)

            PageIndicatorView(
                count: kind.items.count,
                currentIndex: stackedIndex,
                axis: .vertical
            )
            .frame(width: indicatorThickness)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Chrome

    private var footer: some View {
        HStack(spacing: 12) {
            Label(kind.footerLabel, systemImage: kind.footerSystemImage)
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

/// Sets the parent navigation item to `.minimal` back-button mode so only the
/// chevron shows (SwiftUI has no first-class modifier for this on all SDKs).
private struct MinimalBackButtonTitle: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        Controller()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    private final class Controller: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard let parentItem = navigationController?.viewControllers.dropLast().last?.navigationItem else {
                return
            }
            parentItem.backButtonDisplayMode = .minimal
            parentItem.backButtonTitle = ""
        }
    }
}

#Preview("Horizontal") {
    NavigationStack {
        CarouselDemoView(kind: .horizontal)
    }
}

#Preview("3D Infinite Vertical") {
    NavigationStack {
        CarouselDemoView(kind: .stackedVertical)
    }
}

#Preview("3D Infinite Horizontal") {
    NavigationStack {
        CarouselDemoView(kind: .stackedHorizontal)
    }
}

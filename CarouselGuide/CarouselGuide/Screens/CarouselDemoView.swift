import SwiftUI

struct CarouselDemoView: View {
    let kind: DemoKind

    @State private var autoScrollEnabled = true
    @State private var selection: String?
    @State private var interval: Double = 3.0

    private var configuration: CarouselConfiguration {
        var config = kind.configuration
        config.autoScrollEnabled = autoScrollEnabled
        config.autoScrollInterval = interval
        return config
    }

    private var currentIndex: Int {
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
        }
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
                        Spacer()
                        Text("\(interval, format: .number.precision(.fractionLength(1)))s")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $interval, in: 1.5...5.0, step: 0.5)
                        .tint(Color(hex: 0x1F4E5F))
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
        if autoScrollEnabled {
            return kind.configuration.isInfinite
                ? "Auto-advances forever. Dragging pauses playback, then it resumes after a short delay."
                : "Auto-advances through the set and wraps to the start. Dragging pauses, then playback resumes."
        }
        return "Manual only — nothing advances until you scroll or swipe."
    }

    private var carouselStage: some View {
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

    private var footer: some View {
        HStack(spacing: 12) {
            Label(kind.configuration.isInfinite ? "Infinite loop" : "Finite range", systemImage: kind.configuration.isInfinite ? "infinity" : "arrow.left.arrow.right")
            Spacer()
            Text("\(currentIndex + 1) / \(kind.items.count)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(.ultraThinMaterial))
                .accessibilityLabel("Item \(currentIndex + 1) of \(kind.items.count)")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var demoBackground: some View {
        LinearGradient(
            colors: [
                Color(hex: 0xF8F6F2),
                Color(hex: 0xEDF1F5)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

#Preview("Horizontal") {
    NavigationStack {
        CarouselDemoView(kind: .horizontal)
    }
}

#Preview("Vertical Infinite") {
    NavigationStack {
        CarouselDemoView(kind: .verticalInfinite)
    }
}

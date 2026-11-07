import SwiftUI
import UIKit

/// Pure-SwiftUI snapping pager used by `CarouselView` when `isInfinite == false`.
struct FiniteCarouselLayout<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    let configuration: CarouselConfiguration
    @Binding var selection: Item.ID?
    @Binding var isDragging: Bool
    @Binding var scrubProgress: CGFloat
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        GeometryReader { proxy in
            let pageSize = pageSize(in: proxy.size)
            let pageMain = configuration.axis == .horizontal ? pageSize.width : pageSize.height
            let pageStride = max(pageMain + configuration.spacing, 1)

            ScrollView(configuration.axis.scrollAxis, showsIndicators: configuration.showsIndicators) {
                contentStack(pageSize: pageSize)
                    .scrollTargetLayout()
                    .background {
                        // KVO on the underlying UIScrollView so scrub tracks both
                        // finger dragging and animated `scrollPosition` auto-advance.
                        FiniteScrollOffsetObserver(
                            axis: configuration.axis,
                            pageStride: pageStride,
                            onProgress: { progress in
                                publishScrub(progress)
                            }
                        )
                    }
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selection)
            .contentMargins(
                configuration.axis.marginEdges,
                configuration.scrollContentMargin,
                for: .scrollContent
            )
            .simultaneousGesture(dragGesture)
            .onAppear {
                syncScrubToSelection()
            }
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
                        height: pageSize.height
                    )
                    .containerRelativeFrame(
                        configuration.axis == .horizontal ? .horizontal : .vertical,
                        count: 1,
                        span: 1,
                        spacing: configuration.spacing,
                        alignment: .center
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
        }

        let height = max(
            size.height
                - configuration.contentInsets.top
                - configuration.contentInsets.bottom,
            120
        )
        return CGSize(width: size.width, height: height)
    }

    private func publishScrub(_ value: CGFloat) {
        if abs(scrubProgress - value) > 0.0005 {
            scrubProgress = value
        }
    }

    private func syncScrubToSelection() {
        guard let selection,
              let index = items.firstIndex(where: { $0.id == selection }) else {
            publishScrub(0)
            return
        }
        publishScrub(CGFloat(index))
    }

    /// Pause-only signal for auto-scroll. High `minimumDistance` keeps short flicks
    /// owned by `ScrollView` paging instead of this gesture.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { _ in
                if !isDragging { isDragging = true }
            }
            .onEnded { _ in
                isDragging = false
            }
    }
}

/// Observes `contentOffset` on the enclosing `UIScrollView` under a SwiftUI
/// `ScrollView`, publishing fractional page progress for indicator scrubbing.
private struct FiniteScrollOffsetObserver: UIViewRepresentable {
    var axis: CarouselAxis
    var pageStride: CGFloat
    var onProgress: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onProgress: onProgress)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.axis = axis
        context.coordinator.pageStride = pageStride
        context.coordinator.onProgress = onProgress
        context.coordinator.attachIfNeeded(from: uiView)
    }

    final class Coordinator {
        var axis: CarouselAxis = .horizontal
        var pageStride: CGFloat = 1
        var onProgress: (CGFloat) -> Void
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?

        init(onProgress: @escaping (CGFloat) -> Void) {
            self.onProgress = onProgress
        }

        func attachIfNeeded(from view: UIView) {
            // Walk up after SwiftUI inserts us into the hierarchy.
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                guard let scroll = view.enclosingScrollView() else { return }
                guard scroll !== self.scrollView else {
                    self.emit(from: scroll)
                    return
                }
                self.scrollView = scroll
                self.observation = scroll.observe(\.contentOffset, options: [.initial, .new]) { [weak self] scrollView, _ in
                    self?.emit(from: scrollView)
                }
            }
        }

        private func emit(from scrollView: UIScrollView) {
            guard pageStride > 0.5 else { return }
            let raw = axis == .horizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y
            onProgress(raw / pageStride)
        }
    }
}

private extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        var current: UIView? = self
        while let view = current {
            if let scroll = view as? UIScrollView {
                return scroll
            }
            current = view.superview
        }
        return nil
    }
}

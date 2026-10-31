import SwiftUI
import UIKit

/// UIKit-backed infinite pager for both axes.
///
/// SwiftUI `ScrollView` + `scrollPosition` / `scrollTo` did not animate auto-advance for the
/// infinite triple-buffer layout (cards swapped with no content-offset slide). Manual dragging
/// still worked because gesture physics move the offset. This representable advances with
/// `UIScrollView.setContentOffset(_:animated:)`, which always produces a real slide.
struct InfinitePagingScrollView<Item: Identifiable & Hashable, Page: View>: UIViewControllerRepresentable {
    let items: [Item]
    let axis: CarouselAxis
    let spacing: CGFloat
    let contentInsets: EdgeInsets
    @Binding var selection: Item.ID?
    @Binding var isDragging: Bool
    var autoAdvanceTick: UInt64
    var autoScrollEnabled: Bool
    @ViewBuilder var pageBuilder: (Item) -> Page

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, isDragging: $isDragging)
    }

    func makeUIViewController(context: Context) -> InfinitePagingController<Item, Page> {
        let controller = InfinitePagingController<Item, Page>()
        controller.axis = axis
        controller.spacing = spacing
        controller.insets = contentInsets
        controller.pageBuilder = pageBuilder
        controller.onSelect = { id in
            context.coordinator.applySelection(id)
        }
        controller.onDragging = { dragging in
            context.coordinator.applyDragging(dragging)
        }
        controller.reload(items: items, selecting: selection)
        context.coordinator.lastTick = autoAdvanceTick
        return controller
    }

    func updateUIViewController(_ controller: InfinitePagingController<Item, Page>, context: Context) {
        controller.axis = axis
        controller.spacing = spacing
        controller.insets = contentInsets
        controller.pageBuilder = pageBuilder
        controller.onSelect = { id in
            context.coordinator.applySelection(id)
        }
        controller.onDragging = { dragging in
            context.coordinator.applyDragging(dragging)
        }

        if controller.items.map(\.id) != items.map(\.id) {
            controller.reload(items: items, selecting: selection)
        }

        if autoScrollEnabled,
           context.coordinator.lastTick != autoAdvanceTick {
            context.coordinator.lastTick = autoAdvanceTick
            if !context.coordinator.dragging {
                controller.advanceOnePage(animated: true)
            }
        }
    }

    final class Coordinator {
        var selection: Binding<Item.ID?>
        var isDragging: Binding<Bool>
        var lastTick: UInt64 = 0
        var dragging = false

        init(selection: Binding<Item.ID?>, isDragging: Binding<Bool>) {
            self.selection = selection
            self.isDragging = isDragging
        }

        func applySelection(_ id: Item.ID) {
            if selection.wrappedValue != id {
                selection.wrappedValue = id
            }
        }

        func applyDragging(_ value: Bool) {
            dragging = value
            if isDragging.wrappedValue != value {
                isDragging.wrappedValue = value
            }
        }
    }
}

// MARK: - Page host wrapper

/// Concrete hosted root so horizontal pages can apply finite’s **width-only** `.frame(width:)`
/// without losing `Page` typing on `UIHostingController`.
///
/// Finite H: `.frame(width:)` + `containerRelativeFrame(.horizontal)` — height is content-sized
/// (featured card aspect ratio). Infinite H mirrors that width constraint and measures height.
/// Vertical passes `width: nil` and keeps the lean path so auto-scroll stays stable.
private struct PageHost<Content: View>: View {
    let content: Content
    var width: CGFloat?

    var body: some View {
        if let width {
            content
                .frame(width: width, alignment: .center)
        } else {
            content
        }
    }
}

// MARK: - UIScrollView controller

@MainActor
final class InfinitePagingController<Item: Identifiable & Hashable, Page: View>: UIViewController, UIScrollViewDelegate {
    var axis: CarouselAxis = .vertical
    var spacing: CGFloat = 16
    var insets: EdgeInsets = EdgeInsets()
    var pageBuilder: ((Item) -> Page)?
    var onSelect: ((Item.ID) -> Void)?
    var onDragging: ((Bool) -> Void)?

    private(set) var items: [Item] = []

    private let scrollView = UIScrollView()
    private var hosts: [UIHostingController<PageHost<Page>>] = []
    private var pageLength: CGFloat = 0

    private var loopedCount: Int { items.count * 3 }
    private var middleStart: Int { items.count }
    private var strideLength: CGFloat { pageLength + spacing }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        scrollView.delegate = self
        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bounces = true
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.clipsToBounds = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let length: CGFloat = axis == .horizontal
            ? max(view.bounds.width - insets.leading - insets.trailing, 1)
            : max(view.bounds.height - insets.top - insets.bottom, 1)

        if abs(length - pageLength) > 0.5 {
            let previousIndex = currentPageIndex()
            pageLength = length
            layoutPages()
            setOffset(toPage: clampedMiddle(previousIndex), animated: false)
        }
    }

    func reload(items: [Item], selecting selection: Item.ID?) {
        self.items = items
        rebuildHosts()
        pageLength = 0
        view.setNeedsLayout()
        view.layoutIfNeeded()

        let offset = items.firstIndex(where: { $0.id == selection }) ?? 0
        let page = middleStart + offset
        setOffset(toPage: page, animated: false)
        emitSelection(forPage: page)
    }

    /// Animated content-offset advance — this is the auto-scroll slide.
    func advanceOnePage(animated: Bool) {
        guard !items.isEmpty, pageLength > 0 else { return }
        let next = min(currentPageIndex() + 1, loopedCount - 1)
        setOffset(toPage: next, animated: animated)
        if !animated {
            emitSelection(forPage: next)
            recenterIfNeeded()
        }
    }

    // MARK: Layout

    private func rebuildHosts() {
        hosts.forEach {
            $0.willMove(toParent: nil)
            $0.view.removeFromSuperview()
            $0.removeFromParent()
        }
        hosts.removeAll()

        guard let pageBuilder, !items.isEmpty else { return }

        let horizontal = axis == .horizontal
        for index in 0..<loopedCount {
            let root = PageHost(content: pageBuilder(items[index % items.count]), width: nil)
            let host = UIHostingController(rootView: root)
            host.view.backgroundColor = .clear
            host.view.clipsToBounds = false // allow card shadow like finite ScrollView
            host.view.translatesAutoresizingMaskIntoConstraints = true
            host.view.autoresizingMask = []
            if #available(iOS 16.0, *) {
                // H: measure intrinsic height (aspect-ratio card). V: frames stay authoritative.
                host.sizingOptions = horizontal ? [.intrinsicContentSize] : []
            }
            if horizontal, #available(iOS 16.4, *) {
                // Avoid safe-area padding inflating host height past finite’s SwiftUI card.
                host.safeAreaRegions = []
            }
            addChild(host)
            scrollView.addSubview(host.view)
            host.didMove(toParent: self)
            hosts.append(host)
        }
    }

    private func layoutPages() {
        guard !items.isEmpty, pageLength > 0, hosts.count == loopedCount else { return }
        guard let pageBuilder else { return }

        let horizontal = axis == .horizontal
        scrollView.alwaysBounceHorizontal = horizontal
        scrollView.alwaysBounceVertical = !horizontal

        for (index, host) in hosts.enumerated() {
            let main = CGFloat(index) * strideLength
            let item = items[index % items.count]
            if horizontal {
                // FiniteHorizontalDemo path:
                //   content.frame(width: pageSize.width) + containerRelativeFrame(.horizontal)
                //   → height from featured aspect ratio (+ demo padding), centered in stage.
                // Match that pixel height via sizeThatFits; do NOT stretch to stage height.
                host.rootView = PageHost(content: pageBuilder(item), width: pageLength)
                let proposal = CGSize(width: pageLength, height: UIView.layoutFittingExpandedSize.height)
                let fitted = host.sizeThatFits(in: proposal)
                let height = min(max(fitted.height, 1), max(view.bounds.height, 1))
                let y = (view.bounds.height - height) * 0.5
                host.view.frame = CGRect(
                    x: insets.leading + main,
                    y: y,
                    width: pageLength,
                    height: height
                )
            } else {
                // Unchanged vertical frames / lean host — keep infinite V auto-scroll behavior.
                host.rootView = PageHost(content: pageBuilder(item), width: nil)
                host.view.frame = CGRect(
                    x: insets.leading,
                    y: insets.top + main,
                    width: max(view.bounds.width - insets.leading - insets.trailing, 1),
                    height: pageLength
                )
            }
        }

        // Offset for page i is `i * strideLength`. Content must extend far enough for the last page.
        let contentSpan = insets.mainLeading(axis)
            + CGFloat(loopedCount) * pageLength
            + CGFloat(max(loopedCount - 1, 0)) * spacing
            + insets.mainTrailing(axis)

        scrollView.contentSize = horizontal
            ? CGSize(width: contentSpan, height: view.bounds.height)
            : CGSize(width: view.bounds.width, height: contentSpan)
    }

    private func setOffset(toPage index: Int, animated: Bool) {
        let index = min(max(index, 0), max(loopedCount - 1, 0))
        // Page frame main origin = insets.mainLeading + index * stride.
        // Keep the leading/top inset visible: offset = index * stride.
        let main = CGFloat(index) * strideLength
        let point = axis == .horizontal ? CGPoint(x: main, y: 0) : CGPoint(x: 0, y: main)
        scrollView.setContentOffset(point, animated: animated)
    }

    private func currentPageIndex() -> Int {
        guard strideLength > 0 else { return middleStart }
        let raw = axis == .horizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y
        return min(max(Int(round(raw / strideLength)), 0), max(loopedCount - 1, 0))
    }

    private func clampedMiddle(_ index: Int) -> Int {
        guard !items.isEmpty else { return 0 }
        let logical = ((index % items.count) + items.count) % items.count
        return middleStart + logical
    }

    private func emitSelection(forPage index: Int) {
        guard !items.isEmpty else { return }
        onSelect?(items[index % items.count].id)
    }

    private func recenterIfNeeded() {
        guard !items.isEmpty else { return }
        let current = currentPageIndex()
        guard current / items.count != 1 else { return }
        setOffset(toPage: clampedMiddle(current), animated: false)
    }

    // MARK: UIScrollViewDelegate

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        onDragging?(true)
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        guard strideLength > 0 else { return }
        let horizontal = axis == .horizontal
        let proposed = horizontal ? targetContentOffset.pointee.x : targetContentOffset.pointee.y
        var index = Int(round(proposed / strideLength))

        let v = horizontal ? velocity.x : velocity.y
        if v < -0.3 { index += 1 }
        if v > 0.3 { index -= 1 }

        index = min(max(index, 0), max(loopedCount - 1, 0))
        let snapped = CGFloat(index) * strideLength
        if horizontal {
            targetContentOffset.pointee.x = snapped
        } else {
            targetContentOffset.pointee.y = snapped
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            finishUserScroll()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishUserScroll()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        let index = currentPageIndex()
        emitSelection(forPage: index)
        recenterIfNeeded()
    }

    private func finishUserScroll() {
        onDragging?(false)
        let index = currentPageIndex()
        emitSelection(forPage: index)
        recenterIfNeeded()
    }
}

private extension EdgeInsets {
    func mainLeading(_ axis: CarouselAxis) -> CGFloat {
        axis == .horizontal ? leading : top
    }

    func mainTrailing(_ axis: CarouselAxis) -> CGFloat {
        axis == .horizontal ? trailing : bottom
    }
}

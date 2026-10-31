import SwiftUI
import UIKit

/// Infinite carousel backed by `UIScrollView` with a **verified** middle-copy pin.
///
/// SwiftUI `scrollPosition` could not guarantee the first layout was on the middle copy
/// (offset stayed 0), so the first animated advance interpolated across copy 0.
/// Here we `setContentOffset(_:animated: false)`, wait for layout, **measure** the offset,
/// and only then signal `onReady` so the auto-scroll timer may fire.
struct InfiniteUIScrollPager<Item: Identifiable & Hashable, Page: View>: UIViewControllerRepresentable {
    let items: [Item]
    let axis: CarouselAxis
    let spacing: CGFloat
    let contentInsets: EdgeInsets
    @Binding var selection: Item.ID?
    @Binding var isDragging: Bool
    /// Incremented by the parent timer only after `onReady`.
    var autoAdvanceTick: UInt64
    var autoScrollEnabled: Bool
    var onReady: () -> Void
    @ViewBuilder var pageBuilder: (Item) -> Page

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> InfiniteUIScrollController<Item, Page> {
        let controller = InfiniteUIScrollController<Item, Page>()
        controller.axis = axis
        controller.spacing = spacing
        controller.insets = contentInsets
        controller.pageBuilder = pageBuilder
        controller.onSelect = { context.coordinator.applySelection($0) }
        controller.onDragging = { context.coordinator.applyDragging($0) }
        controller.onReady = { context.coordinator.markReady() }
        controller.reload(items: items, selecting: selection)
        context.coordinator.lastTick = autoAdvanceTick
        return controller
    }

    func updateUIViewController(_ controller: InfiniteUIScrollController<Item, Page>, context: Context) {
        context.coordinator.parent = self
        controller.axis = axis
        controller.spacing = spacing
        controller.insets = contentInsets
        controller.pageBuilder = pageBuilder
        controller.onSelect = { context.coordinator.applySelection($0) }
        controller.onDragging = { context.coordinator.applyDragging($0) }
        controller.onReady = { context.coordinator.markReady() }

        if controller.items.map(\.id) != items.map(\.id) {
            context.coordinator.ready = false
            controller.reload(items: items, selecting: selection)
        }

        // Auto-advance only after verified middle pin; exactly +1 page.
        if autoScrollEnabled,
           context.coordinator.ready,
           !context.coordinator.dragging,
           context.coordinator.lastTick != autoAdvanceTick {
            context.coordinator.lastTick = autoAdvanceTick
            let advanced = controller.advanceExactlyOnePage(animated: true)
            if !advanced {
                // Pin repair; skip this tick rather than overshoot.
                controller.forcePinToMiddle(animated: false)
            }
        }
    }

    final class Coordinator {
        var parent: InfiniteUIScrollPager
        var lastTick: UInt64 = 0
        var dragging = false
        var ready = false
        private var didNotifyReady = false

        init(parent: InfiniteUIScrollPager) {
            self.parent = parent
        }

        func markReady() {
            ready = true
            guard !didNotifyReady else { return }
            didNotifyReady = true
            parent.onReady()
        }

        func applySelection(_ id: Item.ID) {
            if parent.selection != id {
                parent.selection = id
            }
        }

        func applyDragging(_ value: Bool) {
            dragging = value
            if parent.isDragging != value {
                parent.isDragging = value
            }
        }
    }
}

// MARK: - Controller

@MainActor
final class InfiniteUIScrollController<Item: Identifiable & Hashable, Page: View>: UIViewController, UIScrollViewDelegate {
    var axis: CarouselAxis = .vertical
    var spacing: CGFloat = 16
    var insets: EdgeInsets = EdgeInsets()
    var pageBuilder: ((Item) -> Page)?
    var onSelect: ((Item.ID) -> Void)?
    var onDragging: ((Bool) -> Void)?
    var onReady: (() -> Void)?

    private(set) var items: [Item] = []

    private let scrollView = UIScrollView()
    private var hosts: [UIHostingController<Page>] = []
    private var pageLength: CGFloat = 0
    private var verifiedMiddlePin = false
    private var isProgrammaticAnimation = false

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

        let sizeChanged = abs(length - pageLength) > 0.5
        if sizeChanged {
            pageLength = length
            layoutPages()
            verifiedMiddlePin = false
        }

        if !verifiedMiddlePin, pageLength > 0, !items.isEmpty {
            performVerifiedMiddlePin()
        }
    }

    func reload(items: [Item], selecting selection: Item.ID?) {
        self.items = items
        verifiedMiddlePin = false
        rebuildHosts()
        pageLength = 0
        view.setNeedsLayout()
        view.layoutIfNeeded()
        if pageLength > 0 {
            performVerifiedMiddlePin(preferredLogical: selection)
        }
    }

    /// Hard pin: set offset without animation, layout, measure, only then mark ready.
    func forcePinToMiddle(animated: Bool) {
        verifiedMiddlePin = false
        performVerifiedMiddlePin(animated: animated)
    }

    @discardableResult
    func advanceExactlyOnePage(animated: Bool) -> Bool {
        guard verifiedMiddlePin, !items.isEmpty, pageLength > 0 else { return false }

        let current = currentPageIndex()
        // Must already be on middle copy before animating forward.
        guard current / items.count == 1 else {
            performVerifiedMiddlePin()
            return false
        }

        let next = current + 1
        guard next == current + 1, next < loopedCount else { return false }

        // Abort if this would skip pages (should be impossible with +1, kept as a hard guard).
        let delta = next - current
        guard delta == 1 else { return false }

        isProgrammaticAnimation = animated
        setOffset(toPage: next, animated: animated)
        if !animated {
            isProgrammaticAnimation = false
            emitSelection(forPage: next)
            recenterIfNeeded()
        }
        return true
    }

    // MARK: Pin / layout

    private func performVerifiedMiddlePin(preferredLogical: Item.ID? = nil, animated: Bool = false) {
        guard !items.isEmpty, pageLength > 0, hosts.count == loopedCount else { return }

        scrollView.layoutIfNeeded()

        let logical = preferredLogical
            ?? currentLogicalID()
            ?? items[0].id
        let offsetIndex = items.firstIndex(where: { $0.id == logical }).map { middleStart + $0 } ?? middleStart
        let expected = offset(forPage: offsetIndex)

        setOffset(toPage: offsetIndex, animated: false)
        scrollView.layoutIfNeeded()

        let actual = axis == .horizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y
        let expectedMain = axis == .horizontal ? expected.x : expected.y

        if abs(actual - expectedMain) <= 1.0 {
            verifiedMiddlePin = true
            emitSelection(forPage: offsetIndex)
            onReady?()
        } else {
            // Retry once more on the next run loop after layout settles.
            verifiedMiddlePin = false
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.verifiedMiddlePin else { return }
                self.setOffset(toPage: offsetIndex, animated: false)
                self.scrollView.layoutIfNeeded()
                let retry = self.axis == .horizontal
                    ? self.scrollView.contentOffset.x
                    : self.scrollView.contentOffset.y
                if abs(retry - expectedMain) <= 1.0 {
                    self.verifiedMiddlePin = true
                    self.emitSelection(forPage: offsetIndex)
                    self.onReady?()
                }
            }
        }
    }

    private func rebuildHosts() {
        hosts.forEach {
            $0.willMove(toParent: nil)
            $0.view.removeFromSuperview()
            $0.removeFromParent()
        }
        hosts.removeAll()
        guard let pageBuilder, !items.isEmpty else { return }
        for index in 0..<loopedCount {
            let host = UIHostingController(rootView: pageBuilder(items[index % items.count]))
            host.view.backgroundColor = .clear
            addChild(host)
            scrollView.addSubview(host.view)
            host.didMove(toParent: self)
            hosts.append(host)
        }
    }

    private func layoutPages() {
        guard !items.isEmpty, pageLength > 0, hosts.count == loopedCount else { return }
        let horizontal = axis == .horizontal
        scrollView.alwaysBounceHorizontal = horizontal
        scrollView.alwaysBounceVertical = !horizontal

        for (index, host) in hosts.enumerated() {
            let main = CGFloat(index) * strideLength
            if horizontal {
                host.view.frame = CGRect(
                    x: insets.leading + main,
                    y: insets.top,
                    width: pageLength,
                    height: max(view.bounds.height - insets.top - insets.bottom, 1)
                )
            } else {
                host.view.frame = CGRect(
                    x: insets.leading,
                    y: insets.top + main,
                    width: max(view.bounds.width - insets.leading - insets.trailing, 1),
                    height: pageLength
                )
            }
        }

        let contentSpan = (horizontal ? insets.leading + insets.trailing : insets.top + insets.bottom)
            + CGFloat(loopedCount) * pageLength
            + CGFloat(max(loopedCount - 1, 0)) * spacing

        scrollView.contentSize = horizontal
            ? CGSize(width: contentSpan, height: view.bounds.height)
            : CGSize(width: view.bounds.width, height: contentSpan)
    }

    private func offset(forPage index: Int) -> CGPoint {
        let main = CGFloat(index) * strideLength
        return axis == .horizontal ? CGPoint(x: main, y: 0) : CGPoint(x: 0, y: main)
    }

    private func setOffset(toPage index: Int, animated: Bool) {
        let index = min(max(index, 0), max(loopedCount - 1, 0))
        scrollView.setContentOffset(offset(forPage: index), animated: animated)
    }

    private func currentPageIndex() -> Int {
        guard strideLength > 0 else { return middleStart }
        let raw = axis == .horizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y
        return min(max(Int(round(raw / strideLength)), 0), max(loopedCount - 1, 0))
    }

    private func currentLogicalID() -> Item.ID? {
        guard !items.isEmpty else { return nil }
        return items[currentPageIndex() % items.count].id
    }

    private func emitSelection(forPage index: Int) {
        guard !items.isEmpty else { return }
        onSelect?(items[index % items.count].id)
    }

    private func recenterIfNeeded() {
        guard !items.isEmpty else { return }
        let current = currentPageIndex()
        guard current / items.count != 1 else { return }
        let middle = middleStart + (current % items.count)
        setOffset(toPage: middle, animated: false)
        // Still on a verified middle page after silent jump.
        verifiedMiddlePin = true
    }

    // MARK: UIScrollViewDelegate

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isProgrammaticAnimation = false
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
        if !decelerate { finishUserScroll() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishUserScroll()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        let index = currentPageIndex()
        emitSelection(forPage: index)
        isProgrammaticAnimation = false
        recenterIfNeeded()
    }

    private func finishUserScroll() {
        onDragging?(false)
        let index = currentPageIndex()
        emitSelection(forPage: index)
        recenterIfNeeded()
        verifiedMiddlePin = (index / max(items.count, 1)) == 1 || items.isEmpty
    }
}

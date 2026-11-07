import SwiftUI
import UIKit

/// Concrete hosted root with an exact size so `UIHostingController` stays typed as
/// `PageHost<Page>` (not `some View`).
///
/// Horizontal pages fill the stage (same as finite `pageSize`). Vertical keeps
/// `size: nil` so the lean auto-scroll path is unchanged.
struct PageHost<Content: View>: View {
    let content: Content
    var size: CGSize?

    var body: some View {
        if let size {
            content
                .frame(width: size.width, height: size.height, alignment: .center)
        } else {
            content
        }
    }
}

/// Triple-buffered `UIScrollView` pager: three copies of the item list, silent
/// recenter into the middle copy, velocity-aware snap on drag end.
@MainActor
final class InfinitePagingController<Item: Identifiable & Hashable, Page: View>: UIViewController, UIScrollViewDelegate {
    var axis: CarouselAxis = .vertical
    var spacing: CGFloat = 16
    var insets: EdgeInsets = EdgeInsets()
    var pageBuilder: ((Item) -> Page)?
    var onSelect: ((Item.ID) -> Void)?
    var onDragging: ((Bool) -> Void)?
    /// Fractional logical page (`0..<count`) while scrolling / animating.
    var onScrubProgress: ((CGFloat) -> Void)?

    private(set) var items: [Item] = []

    private let scrollView = UIScrollView()
    private var hosts: [UIHostingController<PageHost<Page>>] = []
    private var pageLength: CGFloat = 0
    private var lastLayoutBounds: CGSize = .zero

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
        scrollView.isDirectionalLockEnabled = true
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

        let boundsChanged = abs(view.bounds.width - lastLayoutBounds.width) > 0.5
            || abs(view.bounds.height - lastLayoutBounds.height) > 0.5
        let lengthChanged = abs(length - pageLength) > 0.5

        if lengthChanged || boundsChanged {
            let previousIndex = currentPageIndex()
            pageLength = length
            lastLayoutBounds = view.bounds.size
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
        emitScrubProgress()
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

        for index in 0..<loopedCount {
            let root = PageHost(content: pageBuilder(items[index % items.count]), size: nil)
            let host = UIHostingController(rootView: root)
            host.view.backgroundColor = .clear
            host.view.clipsToBounds = (axis == .horizontal)
            host.view.translatesAutoresizingMaskIntoConstraints = true
            host.view.autoresizingMask = []
            if #available(iOS 16.0, *) {
                host.sizingOptions = []
            }
            if axis == .horizontal, #available(iOS 16.4, *) {
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
                let size = CGSize(width: pageLength, height: max(view.bounds.height, 1))
                host.rootView = PageHost(content: pageBuilder(item), size: size)
                host.view.frame = CGRect(
                    x: insets.leading + main,
                    y: 0,
                    width: size.width,
                    height: size.height
                )
            } else {
                host.rootView = PageHost(content: pageBuilder(item), size: nil)
                host.view.frame = CGRect(
                    x: insets.leading,
                    y: insets.top + main,
                    width: max(view.bounds.width - insets.leading - insets.trailing, 1),
                    height: pageLength
                )
            }
        }

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

    private func emitScrubProgress() {
        guard !items.isEmpty, strideLength > 0 else { return }
        let raw = axis == .horizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y
        let page = raw / strideLength
        let n = CGFloat(items.count)
        var logical = page.truncatingRemainder(dividingBy: n)
        if logical < 0 { logical += n }
        onScrubProgress?(logical)
    }

    private func recenterIfNeeded() {
        guard !items.isEmpty else { return }
        let current = currentPageIndex()
        guard current / items.count != 1 else { return }
        setOffset(toPage: clampedMiddle(current), animated: false)
        emitScrubProgress()
    }

    // MARK: UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        emitScrubProgress()
    }

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
        // Snap from the lift offset + velocity (not UIKit's projected target),
        // so short flicks and long drags feel consistent.
        let current = horizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y
        let v = horizontal ? velocity.x : velocity.y
        let resting = current / strideLength

        let index: Int
        if v > 0.2 {
            index = Int(floor(resting)) + 1
        } else if v < -0.2 {
            index = Int(ceil(resting)) - 1
        } else {
            index = Int(resting.rounded())
        }

        let clamped = min(max(index, 0), max(loopedCount - 1, 0))
        let snapped = CGFloat(clamped) * strideLength
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

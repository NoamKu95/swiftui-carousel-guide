import SwiftUI
import UIKit

/// UIKit-backed infinite pager bridge for both axes.
///
/// SwiftUI `scrollPosition` / `scrollTo` did not animate auto-advance for the
/// triple-buffer layout. This representable advances with
/// `UIScrollView.setContentOffset(_:animated:)`, which always slides.
struct InfinitePagingScrollView<Item: Identifiable & Hashable, Page: View>: UIViewControllerRepresentable {
    let items: [Item]
    let axis: CarouselAxis
    let spacing: CGFloat
    let contentInsets: EdgeInsets
    @Binding var selection: Item.ID?
    @Binding var isDragging: Bool
    @Binding var scrubProgress: CGFloat
    var autoAdvanceTick: UInt64
    var autoScrollEnabled: Bool
    @ViewBuilder var pageBuilder: (Item) -> Page

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, isDragging: $isDragging, scrubProgress: $scrubProgress)
    }

    func makeUIViewController(context: Context) -> InfinitePagingController<Item, Page> {
        let controller = InfinitePagingController<Item, Page>()
        apply(to: controller, context: context)
        controller.reload(items: items, selecting: selection)
        context.coordinator.lastTick = autoAdvanceTick
        return controller
    }

    func updateUIViewController(_ controller: InfinitePagingController<Item, Page>, context: Context) {
        apply(to: controller, context: context)

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

    private func apply(to controller: InfinitePagingController<Item, Page>, context: Context) {
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
        controller.onScrubProgress = { progress in
            context.coordinator.applyScrubProgress(progress)
        }
    }

    final class Coordinator {
        var selection: Binding<Item.ID?>
        var isDragging: Binding<Bool>
        var scrubProgress: Binding<CGFloat>
        var lastTick: UInt64 = 0
        var dragging = false

        init(
            selection: Binding<Item.ID?>,
            isDragging: Binding<Bool>,
            scrubProgress: Binding<CGFloat>
        ) {
            self.selection = selection
            self.isDragging = isDragging
            self.scrubProgress = scrubProgress
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

        func applyScrubProgress(_ value: CGFloat) {
            if abs(scrubProgress.wrappedValue - value) > 0.0005 {
                scrubProgress.wrappedValue = value
            }
        }
    }
}

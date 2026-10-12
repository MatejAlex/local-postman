import AppKit
import SwiftUI

/// Two panes with a draggable divider, laid out in SwiftUI alone.
///
/// VSplitView and HSplitView are NSSplitViews underneath, and inside a
/// NavigationSplitView detail they crash the window: each pane reports a new
/// minimum size during the constraint pass, which invalidates the constraints
/// again, until AppKit throws "more Update Constraints passes than there are
/// views". This one has no NSView of its own, so there is nothing to loop.
struct PaneSplit<First: View, Second: View>: View {
    let axis: Axis
    /// The share of the space the first pane gets, kept per axis across launches.
    @Binding var fraction: Double
    var minFirst: CGFloat = 200
    var minSecond: CGFloat = 160
    @ViewBuilder var first: First
    @ViewBuilder var second: Second

    @State private var dragStart: Double?

    private let thickness: CGFloat = 1
    private let grabArea: CGFloat = 9

    var body: some View {
        GeometryReader { proxy in
            let total = axis == .vertical ? proxy.size.height : proxy.size.width
            let firstLength = clampedLength(total: total)

            let layout = axis == .vertical
                ? AnyLayout(VStackLayout(spacing: 0))
                : AnyLayout(HStackLayout(spacing: 0))

            layout {
                first
                    .frame(
                        width: axis == .horizontal ? firstLength : nil,
                        height: axis == .vertical ? firstLength : nil
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                divider(total: total)
                second
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func clampedLength(total: CGFloat) -> CGFloat {
        let available = max(total - thickness, 0)
        let wanted = available * fraction
        let upper = max(available - minSecond, 0)
        return min(max(wanted, min(minFirst, upper)), upper)
    }

    private func divider(total: CGFloat) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(
                width: axis == .horizontal ? thickness : nil,
                height: axis == .vertical ? thickness : nil
            )
            .overlay {
                Color.clear
                    .frame(
                        width: axis == .horizontal ? grabArea : nil,
                        height: axis == .vertical ? grabArea : nil
                    )
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            (axis == .vertical ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = dragStart ?? fraction
                                if dragStart == nil { dragStart = start }
                                let delta = axis == .vertical ? value.translation.height : value.translation.width
                                guard total > 0 else { return }
                                fraction = min(max(start + delta / total, 0.05), 0.95)
                            }
                            .onEnded { _ in dragStart = nil }
                    )
                    .onTapGesture(count: 2) { fraction = 0.5 }
            }
            .zIndex(1)
    }
}

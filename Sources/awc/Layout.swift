import Libawc
import Wlroots

public protocol Layout {
    func doLayout<View>(stack: Stack<View>, box: wlr_box) -> [(View, wlr_box)]
    func nextLayout() -> Layout?
}

extension Layout {
    public func nextLayout() -> Layout? {
        nil
    }
}

/// The simplest of all layouts: renders the focused surface fullscreen.
public class Full : Layout {
    public func doLayout<View>(stack: Stack<View>, box: wlr_box) -> [(View, wlr_box)] {
        [(stack.focus, box)]
    }
}

/// A layout that splits the screen horizontally and shows two windows. The left window is always
/// the main window, and the right is either the currently focused window or the second window in
/// layout order.
public class TwoPane: Layout {
    private let split = 0.5

    public func doLayout<View>(stack: Stack<View>, box: wlr_box) -> [(View, wlr_box)] {
        let (left, right) = splitHorizontally(by: self.split, box: box)
        switch stack.up.reverse() {
        case .cons(let main, _): return [(main, left), (stack.focus, right)]
        case .empty:
            switch stack.down {
            case .cons(let next, _): return [(stack.focus, left), (next, right)]
            case .empty: return [(stack.focus, box)]
            }
        }
    }
}

public class Choose: Layout {
    private let current: Layout
    private let next: List<Layout>
    private let layouts: List<Layout>

    public init(_ first: Layout, _ others: Layout...) {
        self.current = first
        self.next = List(collection: others)
        self.layouts = first ++ self.next
    }

    private init(current: Layout, next: List<Layout>, layouts: List<Layout>) {
        assert(!layouts.isEmpty())
        self.current = current
        self.next = next
        self.layouts = layouts
    }

    public func doLayout<View>(stack: Stack<View>, box: wlr_box) -> [(View, wlr_box)] {
        self.current.doLayout(stack: stack, box: box)
    }

    public func nextLayout() -> Layout? {
        if let nextLayout = current.nextLayout() {
            return self.replace(current: nextLayout)
        } else if case let .cons(nextLayout, next) = self.next {
            return Choose(current: nextLayout, next: next, layouts: self.layouts)
        } else if case let .cons(firstLayout, next) = self.layouts {
            return Choose(current: firstLayout, next: next, layouts: self.layouts)
        } else {
            assertionFailure()
            return nil
        }
    }

    private func replace(current: Layout) -> Layout {
        Choose(current: current, next: self.next, layouts: self.layouts)
    }
}

/// Divides the display into two rectangles with the given ratio.
func splitHorizontally(by: Double, box: wlr_box) -> (wlr_box, wlr_box) {
    let leftWidth = Int32(floor(Double(box.width) * by))
    let left = wlr_box(x: box.x, y: box.y, width: leftWidth, height: box.height)
    let right = wlr_box(x: box.x + leftWidth, y: box.y, width: box.width - leftWidth, height: box.height)
    return (left, right)
}

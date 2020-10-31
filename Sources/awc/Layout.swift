import Libawc
import Wlroots

// XXX Can this be parametrized over the view again?
public protocol Layout {
    associatedtype View

    // XXX
    func emptyLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L, View>,
        box: wlr_box
    ) -> [(View, wlr_box)] where View == L.View

    // XXX
    func doLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L, View>,
        stack: Stack<View>,
        box: wlr_box
    ) -> [(View, wlr_box)] where View == L.View

    func nextLayout() -> Self?
}

// Default implementations
extension Layout {
    public func emptyLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L, View>,
        box: wlr_box
    ) -> [(View, wlr_box)] where View == L.View {
        []
    }

    public func nextLayout() -> Self? {
        nil
    }
}

// /// The simplest of all layouts: renders the focused surface fullscreen.
public class Full<View> : Layout {
    public func doLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L, View>,
        stack: Stack<View>,
        box: wlr_box
    ) -> [(View, wlr_box)] where View == L.View {
        [(stack.focus, box)]
    }
}

/// A layout that splits the screen horizontally and shows two windows. The left window is always
/// the main window, and the right is either the currently focused window or the second window in
/// layout order.
public class TwoPane<View>: Layout {
    private let split = 0.5

    public func doLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L, View>,
        stack: Stack<View>,
        box: wlr_box
    ) -> [(View, wlr_box)] where L.View == View {
        let (left, right) = splitHorizontally(by: self.split, box: box)
        switch stack.up.reverse() {
        case .cons(let main, _): return [(main, left), (stack.focus, right)]
        case .empty:
            switch stack.down {
            case .cons(let next, _): return [(next, right), (stack.focus, left)]
            case .empty: return [(stack.focus, box)]
            }
        }
    }
}

public final class Choose<Left: Layout, Right: Layout>: Layout where Left.View == Right.View {
    private enum Branch {
        case left
        case right
    }
    private let current: Branch
    private let left: Left
    private let right: Right
    private let start: (Left, Right)

    public init(_ left: Left, _ right: Right) {
        self.current = .left
        self.left = left
        self.right = right
        self.start = (left, right)
    }

    private init(left: Left, right: Right, current: Branch, start: (Left, Right)) {
        self.current = current
        self.left = left
        self.right = right
        self.start = start
    }

    // XXX empty layout

    public func doLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L, Left.View>,
        stack: Stack<Left.View>,
        box: wlr_box
    ) -> [(Left.View, wlr_box)] where L.View == Left.View {
        switch self.current {
        case .left: return self.left.doLayout(dataProvider: dataProvider, output: output, stack: stack, box: box)
        case .right: return self.right.doLayout(dataProvider: dataProvider, output: output, stack: stack, box: box)
        }
    }

    public func nextLayout() -> Choose<Left, Right>? {
        switch self.current {
        case .left:
            if let next = self.left.nextLayout() {
                return Choose(left: next, right: self.right, current: self.current, start: self.start)
            } else {
                return Choose(left: self.left, right: self.right, current: .right, start: self.start)
            }
        case .right:
            if let next = self.right.nextLayout() {
                return Choose(left: self.left, right: next, current: self.current, start: self.start)
            } else {
                return Choose(left: self.start.0, right: self.start.1, current: .left, start: self.start)
            }
        }
    }
}

/// Divides the display into two rectangles with the given ratio.
func splitHorizontally(by: Double, box: wlr_box) -> (wlr_box, wlr_box) {
    let leftWidth = Int32(floor(Double(box.width) * by))
    let left = wlr_box(x: box.x, y: box.y, width: leftWidth, height: box.height)
    let right = wlr_box(x: box.x + leftWidth, y: box.y, width: box.width - leftWidth, height: box.height)
    return (left, right)
}

import Libawc
import Wlroots

public struct ViewAttribute: Hashable {
    internal let name: String

    static let focused: ViewAttribute = "focused"
    static let floating: ViewAttribute = "floating"
    static let undecorated: ViewAttribute = "undecorated"
}

extension ViewAttribute: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = ViewAttribute(name: value)
    }
}

public protocol Layout {
    associatedtype View
    /// Type that is used by `Output`s to manage their state.
    associatedtype OutputData

    /// Called when there are no views.
    func emptyLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)] where L.View == View, L.OutputData == OutputData

    /// Arrange the list of given views.
    func doLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        stack: Stack<L.View>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)] where L.View == View, L.OutputData == OutputData

    func firstLayout() -> Self
    func nextLayout() -> Self?
}

// Default implementations
extension Layout {
    public func emptyLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)] {
        []
    }

    public func firstLayout() -> Self {
        self
    }

    public func nextLayout() -> Self? {
        nil
    }
}

/// The simplest of all layouts: renders the focused surface fullscreen.
public class Full<View, OutputData> : Layout {
    public func doLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        stack: Stack<L.View>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)] where L.View == View {
        [(stack.focus, [.focused], box)]
    }
}

/// A layout that splits the screen horizontally and shows two windows. The left window is always
/// the main window, and the right is either the currently focused window or the second window in
/// layout order.
public class TwoPane<View, OutputData>: Layout {
    private let split = 0.5

    public func doLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        stack: Stack<View>,
        box: wlr_box
    ) -> [(View, Set<ViewAttribute>, wlr_box)] where L.View == View {
        let (left, right) = splitHorizontally(by: self.split, box: box)
        switch stack.up.reverse() {
        case .cons(let main, _): return [(main, [], left), (stack.focus, [.focused], right)]
        case .empty:
            switch stack.down {
            case .cons(let next, _): return [(next, [], right), (stack.focus, [.focused], left)]
            case .empty: return [(stack.focus, [.focused], box)]
            }
        }
    }
}

public final class Choose<Left: Layout, Right: Layout>: Layout
    where Left.View == Right.View, Left.OutputData == Right.OutputData
{
    public typealias View = Left.View
    public typealias OutputData = Left.OutputData

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

    public func emptyLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        box: wlr_box
    ) -> [(Left.View, Set<ViewAttribute>, wlr_box)] where L.View == Left.View {
        switch self.current {
        case .left: return self.left.emptyLayout(dataProvider: dataProvider, output: output, box: box)
        case .right: return self.right.emptyLayout(dataProvider: dataProvider, output: output, box: box)
        }
    }

    public func doLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        stack: Stack<Left.View>,
        box: wlr_box
    ) -> [(Left.View, Set<ViewAttribute>, wlr_box)] where L.View == Left.View, L.OutputData == Left.OutputData {
        switch self.current {
        case .left: return self.left.doLayout(dataProvider: dataProvider, output: output, stack: stack, box: box)
        case .right: return self.right.doLayout(dataProvider: dataProvider, output: output, stack: stack, box: box)
        }
    }

    public func firstLayout() -> Choose<Left, Right> {
        Choose(left: self.start.0, right: self.start.1, current: .left, start: self.start)
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
                return nil
            }
        }
    }
}

infix operator |||: LogicalDisjunctionPrecedence

func |||<L: Layout, R: Layout>(left: L, right: R) -> Choose<L, R> where L.View == R.View {
    Choose(left, right)
}

/// Rotates another layout by 90 degrees.
public final class Rotated<L: Layout>: Layout {
    public typealias View = L.View
    public typealias OutputData = L.OutputData

    private let layout: L

    init(layout: L) {
        self.layout = layout
    }

    public func emptyLayout<M: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<M>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)] where M.View == L.View, M.OutputData == L.OutputData {
        self.layout
            .emptyLayout(dataProvider: dataProvider, output: output, box: box.rotated())
            .map { (view, attributes, viewBox) in (view, attributes, viewBox.rotated()) }
    }

    public func doLayout<M: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<M>,
        stack: Stack<L.View>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)] where M.View == L.View, M.OutputData == L.OutputData {
        self.layout
            .doLayout(dataProvider: dataProvider, output: output, stack: stack, box: box.rotated())
            .map { (view, attributes, viewBox) in (view, attributes, viewBox.rotated()) }
    }
}

private extension wlr_box {
    func rotated() -> wlr_box {
        wlr_box(x: self.y, y: self.x, width: self.height, height: self.width)
    }
}


/// Divides the display into two rectangles with the given ratio.
func splitHorizontally(by: Double, box: wlr_box) -> (wlr_box, wlr_box) {
    let leftWidth = Int32(floor(Double(box.width) * by))
    let left = wlr_box(x: box.x, y: box.y, width: leftWidth, height: box.height)
    let right = wlr_box(x: box.x + leftWidth, y: box.y, width: box.width - leftWidth, height: box.height)
    return (left, right)
}

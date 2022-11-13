import DataStructures
import Wlroots

/// A layout that wraps another layout and limits the number of shown views.
public final class Capped<WrappedLayout: Layout>: Layout {
    public typealias View = WrappedLayout.View
    public typealias OutputData = WrappedLayout.OutputData

    public var description: String {
        get {
            "Capped(\(self.layout.description), \(self.limit))"
        }
    }

    private let layout: WrappedLayout
    private let limit: Int

    public init(layout: WrappedLayout, limit: Int) {
        self.layout = layout
        self.limit = limit
    }

    public func emptyLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)]
    where WrappedLayout.View == L.View, WrappedLayout.OutputData == L.OutputData {
        self.layout.emptyLayout(dataProvider: dataProvider, output: output, box: box)
    }

    public func doLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        stack: Stack<L.View>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)]
    where WrappedLayout.View == L.View, WrappedLayout.OutputData == L.OutputData {
        self.layout.doLayout(
            dataProvider: dataProvider,
            output: output,
            stack: stack.first(n: self.limit),
            box: box)
    }

    public func expand() -> Capped<WrappedLayout> {
        Capped(layout: self.layout.expand(), limit: self.limit)
    }

    public func shrink() -> Capped<WrappedLayout> {
        Capped(layout: self.layout.shrink(), limit: self.limit)
    }
}

fileprivate extension List {
    func takeLast(n: Int) -> (Int, Self) {
        guard n > 0 else {
            return (0, List.empty)
        }

        let nodes = Array(sequence(
            first: self,
            next: { if case .cons(_, let xs) = $0 { return xs } else { return nil } })
        // The last entry is the empty node
        ).dropLast()

        if nodes.count > n {
            return (n, nodes[nodes.count - n])
        } else {
            return (nodes.count, self)
        }
    }
}

fileprivate extension Stack {
    func first(n: Int) -> Self {
        let (taken, up) = self.up.takeLast(n: n - 1)
        let remaining = n - taken
        if remaining == 1 {
            return Stack(up: up, focus: self.focus, down: List.empty)
        } else {
            let down = List<T>(sequence: self.down.prefix(remaining - 1))
            return Stack(up: up, focus: self.focus, down: down)
        }
    }
}
 
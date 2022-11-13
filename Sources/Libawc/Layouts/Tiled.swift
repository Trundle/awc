import DataStructures
import Wlroots

/// Splits the output vertically into two regions: the main view is displayed on
/// the left and the remaining views are displaded tiled horizontally on the right.
public final class Tiled<View: Equatable, OutputData>: Layout {
    public let description: String = "Tiled"

    private let split: Double
    private let delta: Double

    public init(split: Double, delta: Double) {
        self.split = split
        self.delta = delta
    }

    public func emptyLayout<M: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<M>,
        box: wlr_box
    ) -> [(View, Set<ViewAttribute>, wlr_box)] {
        []
    }

    public func doLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        stack: Stack<View>,
        box: wlr_box
    ) -> [(View, Set<ViewAttribute>, wlr_box)] {
        let views = stack.toArray()
        guard views.count > 1 else {
            return [(views.first!, [.focused], box)]
        }

        let (left, right) = splitHorizontally(by: self.split, box: box)
        return zip(views, [left] + splitVertically(n: views.count - 1, box: right))
            .map { (view, box) in
                (view, view == stack.focus ? [.focused] : [], box)
            }
    }

    public func expand() -> Tiled<View, OutputData> {
        Tiled(split: min(1, self.split + self.delta), delta: self.delta)
    }

    public func shrink() -> Tiled<View, OutputData> {
        Tiled(split: max(0, self.split - self.delta), delta: self.delta)
    }
}

func splitVertically(n: Int, box: wlr_box) -> [wlr_box] {
    var boxes: [wlr_box] = []
    var remainingHeight = box.height
    var currentY = box.y
    for i in (1...Int32(n)).reversed() {
        let nextHeight = remainingHeight / i
        boxes.append(wlr_box(x: box.x, y: currentY, width: box.width, height: nextHeight))
        currentY += nextHeight
        remainingHeight -= nextHeight
    }
    return boxes
}

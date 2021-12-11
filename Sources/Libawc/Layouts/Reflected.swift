import awc_config

import Wlroots

/// Reflects another layout either horizontally or vertically.
public final class Reflected<L: Layout>: Layout {
    public typealias View = L.View
    public typealias OutputData = L.OutputData

    public var description: String {
        get {
            "Reflected(\(layout.description))"
        }
    }

    private let layout: L
    private let direction: AwcDirection
    private let reflect: (wlr_box, wlr_box) -> wlr_box

    public init(layout: L, direction: AwcDirection) {
        self.layout = layout
        self.direction = direction
        self.reflect =
            direction == Horizontal
            ? { $1.reflectHorizontally(mirror: $0) }
            : { $1.reflectVertically(mirror: $0) }
    }

    public func emptyLayout<M: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<M>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)] where M.View == L.View, M.OutputData == L.OutputData {
        self.layout
            .emptyLayout(dataProvider: dataProvider, output: output, box: box)
            .map { (view, attributes, viewBox) in (view, attributes, self.reflect(box, viewBox)) }
    }

    public func doLayout<M: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<M>,
        stack: Stack<L.View>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)] where M.View == L.View, M.OutputData == L.OutputData {
        self.layout
            .doLayout(dataProvider: dataProvider, output: output, stack: stack, box: box)
            .map { (view, attributes, viewBox) in (view, attributes, self.reflect(box, viewBox)) }
    }

    public func expand() -> Reflected<L> {
        Reflected(layout: self.layout.expand(), direction: self.direction)
    }

    public func shrink() -> Reflected<L> {
        Reflected(layout: self.layout.shrink(), direction: self.direction)
    }
}


private extension wlr_box {
    func reflectHorizontally(mirror: wlr_box) -> wlr_box {
        wlr_box(
            x: 2 * mirror.x + mirror.width - self.x - self.width,
            y: self.y,
            width: self.width,
            height: self.height)
    }

    func reflectVertically(mirror: wlr_box) -> wlr_box {
        wlr_box(
            x: self.x,
            y: 2 * mirror.y + mirror.height - self.y - self.height,
            width: self.width,
            height: self.height)
    }
}

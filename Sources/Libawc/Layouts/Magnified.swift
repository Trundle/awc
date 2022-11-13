import DataStructures
import Wlroots

/// Magnifies the focused surfaces by a constant factor
public final class Magnified<MagnifiedLayout: Layout>: Layout {
    public typealias View = MagnifiedLayout.View
    public typealias OutputData = MagnifiedLayout.OutputData

    public var description: String {
        get {
            "Magnifier(\(layout.description))"
        }
    }

    private let layout: MagnifiedLayout
    /// Width and height of focused surface will be multiplied with this value
    private let magnification: Double

    public init(layout: MagnifiedLayout, magnification: Double) {
        self.layout = layout
        self.magnification = magnification
    }

    public func emptyLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)]
    where MagnifiedLayout.View == L.View, MagnifiedLayout.OutputData == L.OutputData {
        self.layout.emptyLayout(dataProvider: dataProvider, output: output, box: box)
    }

    public func doLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        stack: Stack<L.View>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)]
    where MagnifiedLayout.View == L.View, MagnifiedLayout.OutputData == L.OutputData {
        var arrangement = self.layout
            .doLayout(dataProvider: dataProvider, output: output, stack: stack, box: box)

        if !stack.up.isEmpty, let idx = arrangement.firstIndex(where: { $0.1.contains(.focused) }) {
            let (view, attributes, viewBox) = arrangement.remove(at: idx)
            arrangement.append((
                view, 
                attributes,
                fit(box: magnify(box: viewBox, magnification: self.magnification), boundary: box)
            ))
        }

        return arrangement
    }

    public func expand() -> Magnified<MagnifiedLayout> {
        Magnified(layout: self.layout.expand(), magnification: self.magnification)
    }

    public func shrink() -> Magnified<MagnifiedLayout> {
        Magnified(layout: self.layout.shrink(), magnification: self.magnification)
    }
}

fileprivate func magnify(box: wlr_box, magnification: Double) -> wlr_box {
    let scaledWidth = Int32(Double(box.width) * magnification)
    let scaledHeight = Int32(Double(box.height) * magnification)

    return wlr_box(
        x: box.x - (scaledWidth - box.width) / 2,
        y: box.y - (scaledHeight - box.height) / 2,
        width: scaledWidth,
        height: scaledHeight)
}

fileprivate func fit(box: wlr_box, boundary: wlr_box) -> wlr_box {
    wlr_box(
        x: max(boundary.x, box.x - max(0, box.x + box.width - boundary.x - boundary.width)),
        y: max(boundary.y, box.y - max(0, box.y + box.height - boundary.y - boundary.height)),
        width: min(boundary.width, box.width),
        height: min(boundary.height, box.height))
}

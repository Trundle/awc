//
// "Smart Border" support: only show borders if there is more than one view
//

import Libawc
import Wlroots

private let undecoratedAttributes: Set<ViewAttribute> = [.floating, .undecorated]

final class BorderShrinkLayout<Wrapped: Layout>: Layout {
    public typealias View = Wrapped.View
    public typealias OutputData = Wrapped.OutputData

    private let borderWidth: Int32
    private let layout: Wrapped

    init(borderWidth: Int32, layout: Wrapped) {
        self.borderWidth = borderWidth
        self.layout = layout
    }

    public func emptyLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)] where Wrapped.View == L.View, Wrapped.OutputData == L.OutputData {
        self.layout.emptyLayout(dataProvider: dataProvider, output: output, box: box)
    }

    public func doLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        stack: Libawc.Stack<L.View>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)] where Wrapped.View == L.View, Wrapped.OutputData == L.OutputData {
        let arrangement = self.layout.doLayout(dataProvider: dataProvider, output: output, stack: stack, box: box)
        if arrangement.filter({ $0.1.isDisjoint(with: undecoratedAttributes) }).count > 1 {
            return arrangement.map { ($0.0, $0.1, $0.2.shrink(by: self.borderWidth)) }
        } else {
            return arrangement.map {
                var attributes = $0.1
                attributes.insert(.undecorated)
                return ($0.0, attributes, $0.2)
            }
        }
    }

    func firstLayout() -> BorderShrinkLayout<Wrapped> {
        BorderShrinkLayout(borderWidth: self.borderWidth, layout: self.layout.firstLayout())
    }

    func nextLayout() -> BorderShrinkLayout<Wrapped>? {
        if let next = self.layout.nextLayout() {
            return BorderShrinkLayout(borderWidth: self.borderWidth, layout: next)
        } else {
            return nil
        }
    }
}

public func smartBorders<L: Layout>(
    borderWidth: Int32,
    activeBorderColor: float_rgba,
    inactiveBoarderColor: float_rgba,
    _ renderHook: @escaping RenderSurfaceHook<L>
) -> RenderSurfaceHook<L>
    where L.OutputData == OutputDetails
{
    { renderer, output, surface, attributes, box in
        if attributes.isDisjoint(with: undecoratedAttributes) {
            let color = attributes.contains(.focused) ? activeBorderColor : inactiveBorderColor
            drawBorder(
                renderer: renderer, output: output.data.output, box: box, width: borderWidth, color: color
            )
        }

        renderHook(renderer, output, surface, attributes, box)
    }
}

extension wlr_box {
    func shrink(by: Int32) -> wlr_box {
        wlr_box(x: self.x + by, y: self.y + by, width: self.width - 2 * by, height: self.height - 2 * by)
    }
}

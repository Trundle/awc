///
/// A helper to render images that show how a layout positions views.
///


import awc_config
import Cairo
import Libawc
import Wlroots


let width: Int32 = 160
let height: Int32 = 100
let font = "PragmataPro Mono Liga"


private extension Array {
    func toList() -> List<Element> {
        List(collection: self)
    }
}

public struct NoDataProvider: ExtensionDataProvider {
    public func getExtensionData<D>() -> D? {
        nil
    }
}

class View {
    let number: UInt
    let color: (Double, Double, Double)

    init(number: UInt, color: (Double, Double, Double)) {
        self.number = number
        self.color = color
    }
}


private func createStack() -> Stack<View> {
    let focus = View(number: 1, color: (1, 1, 1))
    let down = [
        View(number: 2, color: (0.7, 0.7, 0.7)),
        View(number: 3, color: (0.3, 0.3, 0.3)),
    ]
    return Stack(up: List.empty, focus: focus, down: down.toList())
}


private func render<L: Layout>(layout: L, cairo: OpaquePointer) where L.View == View, L.OutputData == () {
    let workspace = Workspace(tag: "visualizer", layout: layout)
    let output = Output(data: (), workspace: workspace)
    let box = wlr_box(x: 0, y: 0, width: width, height: height)
    let stack = createStack()
    let arrangement = layout.doLayout(dataProvider: NoDataProvider(), output: output, stack: stack, box: box)

    for (view, _, box) in arrangement {
        cairo_set_source_rgb(cairo, view.color.0, view.color.1, view.color.2)
        cairo_rectangle(cairo, Double(box.x), Double(box.y), Double(box.width), Double(box.height))
        cairo_fill(cairo)

        var textExtents = cairo_text_extents_t()
        cairo_select_font_face(cairo, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
        cairo_set_font_size(cairo, Double(box.height) / 2)
        cairo_text_extents(cairo, String(view.number), &textExtents)
        cairo_set_source_rgb(cairo, 0, 0, 0)
        cairo_move_to(
            cairo, 
            Double(box.x) + Double(box.width) / 2 - textExtents.width / 2 - textExtents.x_bearing,
            Double(box.y) + Double(box.height) / 2 - textExtents.height / 2 - textExtents.y_bearing)
        cairo_show_text(cairo, String(view.number))
    }
}

private func drawBorder(cairo: OpaquePointer) {
    cairo_set_source_rgb(cairo, 0, 0, 0)
    cairo_rectangle(cairo, 0, 0, Double(width), Double(height))
    cairo_set_line_width(cairo, 1)
    cairo_stroke(cairo)
}

private func render<L: Layout>(layout: L, to filename: String) where L.View == View, L.OutputData == () {
    guard let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height),
        let cairo = cairo_create(surface) else {
        print("[FATAL] Could not create cairo surface or context")
        return
    }
    defer {
        cairo_surface_destroy(surface)
        cairo_destroy(cairo)
    }
    render(layout: layout, cairo: cairo)
    drawBorder(cairo: cairo)
    cairo_surface_write_to_png(surface, filename)
}

func main() {
    let full = Full<View, ()>()
    let twoPane = TwoPane<View, ()>(split: 0.5, delta: 0.1)
    let rotatedTwoPane = Rotated(layout: twoPane)
    let reflectedTwoPane = Reflected(layout: twoPane, direction: Horizontal)
    let reflectedRotatedTwoPane = Reflected(layout: rotatedTwoPane, direction: Vertical)

    render(layout: full, to: "full.png")
    render(layout: twoPane, to: "two_pane.png")
    render(layout: rotatedTwoPane, to: "rotated_two_pane.png")
    render(layout: reflectedTwoPane, to: "reflected_two_pane.png")
    render(layout: reflectedRotatedTwoPane, to: "reflected_rotated_two_pane.png")
}


main()

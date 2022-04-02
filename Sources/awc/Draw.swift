import Wlroots

import Libawc

/// Draws a border with the given width around the given box. The border is drawn outside the box.
func drawBorder(
    renderer: UnsafeMutablePointer<wlr_renderer>,
    output: UnsafeMutablePointer<wlr_output>,
    box: wlr_box,
    width: Int32,
    color: float_rgba
) {
    var mutableColor = color
    mutableColor.withPtr { colorPtr in
        // Top
        withUnsafePointer(
            to: wlr_box(x: box.x - width, y: box.y - width, width: box.width + 2 * width, height: width)
        ) {
            drawBox(renderer: renderer, output: output, box: $0, color: colorPtr)
        }
        // Bottom
        withUnsafePointer(
            to: wlr_box(x: box.x - width, y: box.y + box.height, width: box.width + 2 * width, height: width)
        ) {
            drawBox(renderer: renderer, output: output, box: $0, color: colorPtr)
        }
        // Left
        withUnsafePointer(
            to: wlr_box(x: box.x - width, y: box.y - width, width: width, height: box.height + 2 * width)
        ) {
            drawBox(renderer: renderer, output: output, box: $0, color: colorPtr)
        }
        // Right
        withUnsafePointer(
            to: wlr_box(x: box.x + box.width, y: box.y - width, width: width, height: box.height + 2 * width)
        ) {
            drawBox(renderer: renderer, output: output, box: $0, color: colorPtr)
        }
    }
}

private func drawBox(
    renderer: UnsafeMutablePointer<wlr_renderer>,
    output: UnsafeMutablePointer<wlr_output>,
    box: UnsafePointer<wlr_box>,
    color: UnsafePointer<Float>
) {
    withUnsafePointer(to: box.pointee.scale(Double(output.pointee.scale))) { (scaledBox) in
        withUnsafePointer(to: &output.pointee.transform_matrix.0) { (outputTransformMatrixPtr) in
            wlr_render_rect(renderer, scaledBox, color, outputTransformMatrixPtr)
        }
    }
}

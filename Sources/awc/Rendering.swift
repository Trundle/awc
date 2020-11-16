import Wlroots

private func renderSurface(
    renderer: UnsafeMutablePointer<wlr_renderer>,
    output: UnsafeMutablePointer<wlr_output>,
    px: Int32,
    py: Int32,
    surface: UnsafeMutablePointer<wlr_surface>,
    sx: Int32,
    sy: Int32
) {
    // We first obtain a wlr_texture, which is a GPU resource. wlroots
    // automatically handles negotiating these with the client. The underlying
    // resource could be an opaque handle passed from the client, or the client
    // could have sent a pixel buffer which we copied to the GPU, or a few other
    // means. You don't have to worry about this, wlroots takes care of it.
    guard let texture = wlr_surface_get_texture(surface) else {
        return
    }

    // We also have to apply the scale factor for HiDPI outputs. This is only
    // part of the puzzle, AWC does not fully support HiDPI.
    let scale = Double(output.pointee.scale)
    var box = wlr_box(
        x: Int32(Double(px + sx) * scale),
        y: Int32(Double(py + sy) * scale),
        width: Int32(Double(surface.pointee.current.width) * scale),
        height: Int32(Double(surface.pointee.current.height) * scale)
    )

    // Those familiar with OpenGL are also familiar with the role of matrices
    // in graphics programming. We need to prepare a matrix to render the view
    // with. wlr_matrix_project_box is a helper which takes a box with a desired
    // x, y coordinates, width and height, and an output geometry, then
    // prepares an orthographic projection and multiplies the necessary
    // transforms to produce a model-view-projection matrix.
    //
    // Naturally you can do this any way you like, for example to make a 3D
    // compositor.
    var matrix: matrix9 = (0, 0, 0, 0, 0, 0, 0, 0, 0)
    let transform = wlr_output_transform_invert(surface.pointee.current.transform)
    withUnsafeMutablePointer(to: &matrix.0) { matrixPtr in
        withUnsafePointer(to: &output.pointee.transform_matrix.0) { (outputTransformMatrixPtr) in
            wlr_matrix_project_box(matrixPtr, &box, transform, 0, outputTransformMatrixPtr)
        }

        // This takes our matrix, the texture, and an alpha, and performs the actual rendering on the GPU.
        wlr_render_texture_with_matrix(renderer, texture, matrixPtr, 1)
    }
}

public func renderSurface<L: Layout>(
    _ renderer: UnsafeMutablePointer<wlr_renderer>,
    _ output: Output<L>,
    _ surface: Surface,
    _ attributes: Set<ViewAttribute>,
    _ box: wlr_box
) where L.View == Surface, L.OutputData == OutputDetails {
    let wlrOutput = output.data.output
    for (childSurface, sx, sy) in surface.surfaces() {
        renderSurface(
            renderer: renderer, output: wlrOutput, px: box.x, py: box.y, surface: childSurface, sx: sx, sy: sy
        )
    }
}

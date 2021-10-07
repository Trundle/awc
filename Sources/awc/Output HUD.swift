import awc_config
import Cairo
import Drm
import Libawc
import Wlroots


private extension AwcColor {
    func setSourceRgb(cairo: OpaquePointer) {
        cairo_set_source_rgba(
            cairo, 
            Double(self.r) / 255.0, 
            Double(self.g) / 255.0, 
            Double(self.b) / 255.0, 
            Double(self.a) / 255.0)
    }
}


/// An overlay that displays workspace and output information such as the name and the surfaces' titles.
public class OutputHud {
    private static let xMargin: Double = 48

    private var width: Int32 = 0
    private var height: Int32 = 0
    private var surface: OpaquePointer! = nil
    private var cairo: OpaquePointer! = nil
    private var texture: UnsafeMutablePointer<wlr_texture>? = nil

    init() {
    }

    deinit {
        cairo_surface_destroy(self.surface)
        cairo_destroy(self.cairo)
        destroyTexture() 
    }

    public func update<L: Layout>(
        output: Output<L>, 
        renderer: UnsafeMutablePointer<wlr_renderer>,
        font: String,
        config: AwcOutputHudConfig
    ) where L.OutputData == OutputDetails, L.View == Surface {
        let outputBox = output.data.box
        if width != outputBox.width || height != outputBox.height {
            self.width = outputBox.width
            self.height = outputBox.height
            if self.surface != nil {
                cairo_surface_destroy(self.surface)
                cairo_destroy(self.cairo)
            }
            self.surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height)
            self.cairo = cairo_create(self.surface)
        }
        destroyTexture()
        clearSurface()

        let name = toString(array: output.data.output.pointee.name)
        renderTagAndOutputName(tag: output.workspace.tag, outputName: name, font: font, config: config)

        if let stack = output.workspace.stack {
            renderViewTitleBoxes(stack: stack, at: 48, font: font, config: config)
        }

        let stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, self.width)
        let data = cairo_image_surface_get_data(surface)
        self.texture = wlr_texture_from_pixels(
            renderer, _DRM_FORMAT_ARGB8888, UInt32(stride), UInt32(self.width), UInt32(self.height), data)
    }

    public func render<L: Layout>(on output: Output<L>, with renderer: UnsafeMutablePointer<wlr_renderer>) 
    where L.OutputData == OutputDetails {
        if let texture = self.texture {
            var box = output.data.box.scale(Double(output.data.output.pointee.scale))
            box.x = 0
            box.y = 0
            var matrix: matrix9 = (0, 0, 0, 0, 0, 0, 0, 0, 0)
            withUnsafeMutablePointer(to: &matrix.0) { matrixPtr in
                withUnsafePointer(to: &output.data.output.pointee.transform_matrix.0) { (outputTransformMatrixPtr) in
                    wlr_matrix_project_box(matrixPtr, &box, WL_OUTPUT_TRANSFORM_NORMAL, 0, outputTransformMatrixPtr)
                }

                wlr_render_texture_with_matrix(renderer, texture, matrixPtr, 1)
            }
        }
    }

    private func destroyTexture() {
        if let texture = self.texture {
            wlr_texture_destroy(texture)
            self.texture = nil
        }
    }

    private func renderTagAndOutputName(tag: String, outputName: String, font: String, config: AwcOutputHudConfig) {
        let text = "\(tag) @ \(outputName)"
        cairo_select_font_face(self.cairo, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
        cairo_set_font_size(self.cairo, 18)
        var textExtents = cairo_text_extents_t()
        cairo_text_extents(self.cairo, text, &textExtents)

        config.active_background_color.setSourceRgb(cairo: self.cairo)
        let rectangleWidth = textExtents.width + 24
        let xPos = Double(width) - Self.xMargin - rectangleWidth
        cairo_rectangle(self.cairo, xPos, 48, rectangleWidth, textExtents.height + 24)
        cairo_fill(self.cairo)

        config.active_foreground_color.setSourceRgb(cairo: self.cairo)
        cairo_move_to(self.cairo, xPos + 12 - textExtents.x_bearing, 60 - textExtents.y_bearing)
        cairo_show_text(self.cairo, text)
    }

    private func renderViewTitleBoxes(stack: Stack<Surface>, at y: Double, font: String, config: AwcOutputHudConfig) {
        let boxWidth = Double(width) * 0.5
        let xPos = Double(width) / 2 - boxWidth / 2
        let surfaces = stack.toList()

        cairo_set_line_width(self.cairo, 1)

        cairo_select_font_face(self.cairo, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        var textExtents = cairo_text_extents_t()
        
        var currentY = y 
        for surface in surfaces {
            let title = surface.title

            cairo_save(self.cairo)
            defer {
                cairo_restore(self.cairo)
            }

            if surface == stack.focus {
                config.active_background_color.setSourceRgb(cairo: self.cairo)
                cairo_rectangle(self.cairo, xPos, currentY, boxWidth, 52)
                cairo_fill(self.cairo)

                cairo_rectangle(self.cairo, xPos, currentY, boxWidth, 52)
                cairo_clip(self.cairo)

                config.active_foreground_color.setSourceRgb(cairo: self.cairo)
                cairo_set_font_size(self.cairo, 36)
                cairo_text_extents(self.cairo, title, &textExtents)
                cairo_move_to(
                    self.cairo, xPos + 6 - textExtents.x_bearing, 
                    currentY + 24 - textExtents.y_bearing - textExtents.height / 2)
                cairo_show_text(self.cairo, title)
    
                currentY += 62
            } else {
                cairo_set_font_size(self.cairo, 24)
                cairo_text_extents(self.cairo, title, &textExtents)

                config.inactive_background_color.setSourceRgb(cairo: self.cairo)
                cairo_rectangle(self.cairo, xPos + 4, currentY, boxWidth - 8, 34)
                cairo_fill(self.cairo)

                cairo_rectangle(self.cairo, xPos + 4, currentY, boxWidth - 8, 34)
                cairo_clip(self.cairo)

                config.inactive_foreground_color.setSourceRgb(cairo: self.cairo)
                cairo_move_to(
                    self.cairo, xPos + 6 - textExtents.x_bearing, 
                    currentY + 17 - textExtents.y_bearing - textExtents.height / 2)
                cairo_show_text(self.cairo, title)

                cairo_move_to(self.cairo, xPos + 4, currentY + 33)
                cairo_line_to(self.cairo, xPos + 4 + boxWidth - 8, currentY + 33)
                cairo_stroke(self.cairo)

                currentY += 34
            }
        }
    }

    private func clearSurface() {
        cairo_save(self.cairo)
        defer {
            cairo_restore(self.cairo)
        }

        cairo_set_source_rgba(self.cairo, 0, 0, 0, 0)
        cairo_set_operator(self.cairo, CAIRO_OPERATOR_SOURCE)
        cairo_paint(self.cairo)
    }
}

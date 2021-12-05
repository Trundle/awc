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

    private let neonRenderer = NeonRenderer()
    private var width: Int32 = 0
    private var height: Int32 = 0
    private var surface: OpaquePointer! = nil
    private var cairo: OpaquePointer! = nil

    init() {
    }

    deinit {
        cairo_surface_destroy(self.surface)
        cairo_destroy(self.cairo)
   }

    public func update<L: Layout>(
        output: Output<L>,
        renderer: UnsafeMutablePointer<wlr_renderer>,
        font: String,
        colors: AwcOutputHudColors
    ) where L.OutputData == OutputDetails, L.View == Surface {
        let outputBox = output.data.box
        if self.width != outputBox.width || self.height != outputBox.height {
            self.width = outputBox.width
            self.height = outputBox.height
            self.neonRenderer.updateSize(
                width: self.width, height: self.height, scale: output.data.output.pointee.scale,
                renderer: renderer)
            if self.surface != nil {
                cairo_surface_destroy(self.surface)
                cairo_destroy(self.cairo)
            }
            self.surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, self.width, self.height)
            self.cairo = cairo_create(self.surface)
        }
        clearSurface()

        let name = toString(array: output.data.output.pointee.name)
        renderTagAndOutputName(tag: output.workspace.tag, outputName: name, font: font, colors: colors)

        if let stack = output.workspace.stack {
            renderViewTitleBoxes(stack: stack, at: 48, font: font, colors: colors)
        }

        self.neonRenderer.update(surface: self.surface, with: renderer)
    }

    public func render<L: Layout>(on output: Output<L>, with renderer: UnsafeMutablePointer<wlr_renderer>)
    where L.OutputData == OutputDetails, L.View == Surface {
        self.neonRenderer.render(on: output, with: renderer)
    }

    private func renderTagAndOutputName(tag: String, outputName: String, font: String, colors: AwcOutputHudColors) {
        // Determine text size (to know how large our box needs to be)
        let text = "\(tag) @ \(outputName)"
        cairo_select_font_face(self.cairo, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
        cairo_set_font_size(self.cairo, 18)
        var textExtents = cairo_text_extents_t()
        cairo_text_extents(self.cairo, text, &textExtents)

        // Background
        colors.active_background.setSourceRgb(cairo: self.cairo)
        let rectangleWidth = textExtents.width + 24
        let xPos = Double(width) - Self.xMargin - rectangleWidth
        cairo_rectangle(self.cairo, xPos, 48, rectangleWidth, textExtents.height + 24)
        cairo_fill(self.cairo)

        // Glow
        colors.active_glow.setSourceRgb(cairo: self.cairo)
        cairo_rectangle(self.cairo, xPos, 48, rectangleWidth, textExtents.height + 24)
        cairo_set_line_width(self.cairo, 2.0)
        cairo_stroke(self.cairo)

        // Text
        colors.active_foreground.setSourceRgb(cairo: self.cairo)
        cairo_move_to(self.cairo, xPos + 12 - textExtents.x_bearing, 60 - textExtents.y_bearing)
        cairo_show_text(self.cairo, text)
    }

    private func renderViewTitleBoxes(stack: Stack<Surface>, at y: Double, font: String, colors: AwcOutputHudColors) {
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
                // Background
                colors.active_background.setSourceRgb(cairo: self.cairo)
                cairo_rectangle(self.cairo, xPos, currentY, boxWidth, 52)
                cairo_fill(self.cairo)

                // Lightning outline
                colors.active_glow.setSourceRgb(cairo: self.cairo)
                cairo_rectangle(self.cairo, xPos, currentY, boxWidth, 52)
                cairo_set_line_width(self.cairo, 2.0)
                cairo_stroke(self.cairo)

                // Clip so long titles don't exceed the box
                cairo_rectangle(self.cairo, xPos, currentY, boxWidth, 52)
                cairo_clip(self.cairo)

                colors.active_foreground.setSourceRgb(cairo: self.cairo)
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

                colors.inactive_background.setSourceRgb(cairo: self.cairo)
                cairo_rectangle(self.cairo, xPos + 4, currentY, boxWidth - 8, 34)
                cairo_fill(self.cairo)

                cairo_rectangle(self.cairo, xPos + 4, currentY, boxWidth - 8, 34)
                cairo_clip(self.cairo)

                colors.inactive_foreground.setSourceRgb(cairo: self.cairo)
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

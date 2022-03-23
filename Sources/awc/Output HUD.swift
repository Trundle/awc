import awc_config
import Cairo
import CCairo
import Drm
import Libawc
import Wlroots


private extension AwcColor {
    func setSourceRgb(cairo: Cairo.Context) {
        cairo.setSource(
            r: Double(self.r) / 255.0,
            g: Double(self.g) / 255.0,
            b: Double(self.b) / 255.0,
            a: Double(self.a) / 255.0)
    }
}

private extension Stack {
    var count: Int {
        get {
            return self.up.reduce(0, { (sum, _) in sum + 1 })
                + self.down.reduce(0, { (sum, _) in sum + 1 })
                + 1
        }
    }
}


/// An overlay that displays workspace and output information such as the name and the surfaces' titles.
public class OutputHud {
    private static let xMargin: Double = 48

    private let neonRenderer = NeonRenderer()
    private var width: Int32 = 0
    private var height: Int32 = 0
    private var surface: Cairo.Surface! = nil
    // Initialize with a small, empty surface, because we need a valid Cairo context to
    // determine the real required size
    private var outputAndTagSurface: Cairo.Surface = Cairo.Surface(width: 1, height: 1)

    init() {
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
            self.surface = Cairo.Surface(
                width: Int32(self.viewBoxWidth()), 
                height: self.height / 3)
        }
        self.surface.context.clear()

        let name = toString(array: output.data.output.pointee.name)
        let outputAndTagPositionX = renderTagAndOutputName(
            tag: output.workspace.tag, outputName: name, font: font, colors: colors)

        if let stack = output.workspace.stack {
            let requiredHeight = min(self.viewBoxHeight(stack), self.height - 48)
            if self.surface.height < requiredHeight {
                self.surface = Cairo.Surface(
                    width: Int32(self.viewBoxWidth()),
                    height: requiredHeight)
            }
            renderViewTitleBoxes(stack: stack, font: font, colors: colors)
        }

        self.outputAndTagSurface.withRawPointer { outputSurface in
            self.surface.withRawPointer { viewSurface in
                self.neonRenderer.update(
                    surfaces: [
                        (outputAndTagPositionX, 48, outputSurface),
                        (Int32(Double(width) / 2 - self.viewBoxWidth() / 2), 48, viewSurface)
                    ],
                    with: renderer)
            }
        }
    }

    public func render<L: Layout>(on output: Output<L>, with renderer: UnsafeMutablePointer<wlr_renderer>)
    where L.OutputData == OutputDetails, L.View == Surface {
        self.neonRenderer.render(on: output, with: renderer)
    }

    private func viewBoxWidth() -> Double {
        return Double(self.width) * 0.5 + 2.0
    }

    private func renderTagAndOutputName(
        tag: String,
        outputName: String,
        font: String,
        colors: AwcOutputHudColors
    ) -> Int32 {
        var cairo = self.outputAndTagSurface.context

        // Determine text size (to know how large our box needs to be)
        let fontSize = 18.0
        let text = "\(tag) @ \(outputName)"
        cairo.selectFontFace(family: font)
        cairo.set(fontSize: fontSize)
        var textExtents = cairo_text_extents_t()
        cairo.extents(text: text, &textExtents)

        let padding = 24.0
        let stroke = 2.0
        let rectangleWidth = textExtents.width + padding
        let rectangleHeight = textExtents.height + padding

        if createOutputAndTagSurfaceIfRequired(
            width: Int32(rectangleWidth + 2 * stroke),
            height: Int32(rectangleHeight + 2 * stroke))
        {
            cairo = self.outputAndTagSurface.context
            cairo.selectFontFace(family: font)
            cairo.set(fontSize: fontSize)
        }

        cairo.clear()

        // Background
        colors.active_background.setSourceRgb(cairo: cairo)
        cairo.rectangle(x: stroke, y: stroke, width: rectangleWidth, height: rectangleHeight)
        cairo.fill()

        // Glow
        colors.active_glow.setSourceRgb(cairo: cairo)
        cairo.rectangle(x: stroke, y: stroke, width: rectangleWidth, height: rectangleHeight)
        cairo.set(lineWidth: stroke)
        cairo.stroke()

        // Text
        colors.active_foreground.setSourceRgb(cairo: cairo)
        cairo.moveTo(x: 12 - textExtents.x_bearing, y: 12 - textExtents.y_bearing)
        cairo.show(text: text)

        return Int32(Double(width) - Self.xMargin - rectangleWidth)
    }

    private func createOutputAndTagSurfaceIfRequired(width: Int32, height: Int32) -> Bool {
        guard self.outputAndTagSurface.width < width || self.outputAndTagSurface.height < height
        else {
            return false;
        }

        self.outputAndTagSurface = Cairo.Surface(width: width, height: height)
        return true
    }

    private func renderViewTitleBoxes(stack: Stack<Surface>, font: String, colors: AwcOutputHudColors) {
        let lineWidth = 1.0
        let boxWidth = self.viewBoxWidth() - 2 * lineWidth
        let xPos = lineWidth
        let cairo = self.surface.context
        let surfaces = stack.toList()

        cairo.set(lineWidth: lineWidth)

        cairo.selectFontFace(family: font)
        var textExtents = cairo_text_extents_t()

        var currentY = 0.0
        for surface in surfaces {
            let title = surface.title

            cairo.save()
            defer {
                cairo.restore()
            }

            if surface == stack.focus {
                // Background
                colors.active_background.setSourceRgb(cairo: cairo)
                cairo.rectangle(x: xPos, y: currentY, width: boxWidth, height: 52)
                cairo.fill()

                // Lightning outline
                colors.active_glow.setSourceRgb(cairo: cairo)
                cairo.rectangle(x: xPos, y: currentY, width: boxWidth, height: 52)
                cairo.set(lineWidth: 2.0)
                cairo.stroke()

                // Clip so long titles don't exceed the box
                cairo.rectangle(x: xPos, y: currentY, width: boxWidth, height: 52)
                cairo.clip()

                colors.active_foreground.setSourceRgb(cairo: cairo)
                cairo.set(fontSize: 36)
                cairo.extents(text: title, &textExtents)
                cairo.moveTo(
                    x: xPos + 6 - textExtents.x_bearing,
                    y: currentY + 24 - textExtents.y_bearing - textExtents.height / 2)
                cairo.show(text: title)

                currentY += 62
            } else {
                cairo.set(fontSize: 24)
                cairo.extents(text: title, &textExtents)

                colors.inactive_background.setSourceRgb(cairo: cairo)
                cairo.rectangle(x: xPos + 4, y: currentY, width: boxWidth - 8, height: 34)
                cairo.fill()

                cairo.rectangle(x: xPos + 4, y: currentY, width: boxWidth - 8, height: 34)
                cairo.clip()

                colors.inactive_foreground.setSourceRgb(cairo: cairo)
                cairo.moveTo(
                    x: xPos + 6 - textExtents.x_bearing,
                    y: currentY + 17 - textExtents.y_bearing - textExtents.height / 2)
                cairo.show(text: title)

                cairo.moveTo(x: xPos + 4, y: currentY + 33)
                cairo.lineTo(x: xPos + 4 + boxWidth - 8, y: currentY + 33)
                cairo.stroke()

                currentY += 34
            }
        }
    }

    private func viewBoxHeight(_ stack: Stack<Surface>) -> Int32 {
        return Int32(62 + (stack.count - 1) * 34 + 4)
    }
}

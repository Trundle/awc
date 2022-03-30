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

private extension List {
    var count: Int32 {
        get {
            return self.reduce(0, { (sum, _) in sum + 1 })
        }
    }
}

// Exists solely because tuples aren't hashable in Swift
private struct SurfaceCacheKey: Equatable, Hashable {
    let text: String
    let font: String
    let fontSize: Double
}


/// An overlay that displays workspace and output information such as the name and the surfaces' titles.
public class OutputHud {
    private static let xMargin: Double = 48

    private let neonRenderer = NeonRenderer()
    private var width: Int32 = 0
    private var height: Int32 = 0
    private var measureContext: Cairo.Context = Cairo.Surface(width: 1, height: 1).context
    private var textSurfaceCache: LRUCache<SurfaceCacheKey, Cairo.Surface> = LRUCache(maxSize: 64)

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
        }

        let name = output.data.output.name
        let (outputAndTagPositionX, outputAndTagSurface) = renderTagAndOutputName(
            tag: output.workspace.tag, outputName: name, font: font, colors: colors)

        let rects: [(wlr_box, float_rgba)]
        let titleSurfaces: [(Int32, Int32, Cairo.Surface)]
        if let stack = output.workspace.stack {
            rects = renderViewTitleBoxes(stack: stack, font: font, colors: colors)
            titleSurfaces = renderViewTitleTexts(stack: stack, font: font, colors: colors)
        } else {
            rects = []
            titleSurfaces = []
        }

        self.neonRenderer.update(
            rects: rects,
            surfaces: [
                (outputAndTagPositionX, Int32(48), outputAndTagSurface),
            ] + titleSurfaces)
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
    ) -> (Int32, Cairo.Surface) {
        let fontSize = 18.0
        let text = "\(tag) @ \(outputName)"
        if let surface = self.lookupCached(text: text, font: font, fontSize: fontSize) {
            return (Int32(Double(width) - Self.xMargin) - surface.width, surface)
        }

        var cairo = self.measureContext

        // Determine text size (to know how large our box needs to be)
        cairo.selectFontFace(family: font)
        cairo.set(fontSize: fontSize)
        var textExtents = cairo_text_extents_t()
        cairo.extents(text: text, &textExtents)

        let padding = 24.0
        let stroke = 2.0
        let rectangleWidth = textExtents.width + padding
        let rectangleHeight = textExtents.height + padding

        let surface = Cairo.Surface(
            width: Int32(rectangleWidth + 2 * stroke),
            height: Int32(rectangleHeight + 2 * stroke))
        cairo = surface.context
        cairo.selectFontFace(family: font)
        cairo.set(fontSize: fontSize)

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

        self.textSurfaceCache[SurfaceCacheKey(text: text, font: font, fontSize: fontSize)] = surface

        return (Int32(Double(width) - Self.xMargin - rectangleWidth), surface)
    }

    private func renderViewTitleBoxes(stack: Stack<Surface>, font: String, colors: AwcOutputHudColors
    ) -> [(wlr_box, float_rgba)] {
        let lineWidth: Int32 = 1
        let boxWidth = Int32(self.viewBoxWidth()) - 2 * lineWidth
        let xPos = Int32(Float(self.width) / 2 - Float(boxWidth) / 2)

        let upCount = stack.up.count
        let upHeight = upCount * 34
        let downCount = stack.down.count
        let downHeight = downCount * 34

        var boxes = [
            (
                wlr_box(x: xPos + 4, y: 48, width: boxWidth - 8, height: upHeight), 
                colors.inactive_background.toFloatRgba()
            ),
            (
                wlr_box(x: xPos, y: 48 + upHeight, width: boxWidth, height: 52),
                colors.active_background.toFloatRgba()
            ),
            (
                wlr_box(x: xPos + 4, y: 48 + upHeight + 60, width: boxWidth - 8, height: downHeight),
                colors.inactive_background.toFloatRgba()
            ),
            // Border around active box
            (
                wlr_box(x: xPos - 1, y: 48 + upHeight, width: 2, height: 52),
                colors.active_glow.toFloatRgba()
            ),
            (
                wlr_box(x: xPos + boxWidth - 1, y: 48 + upHeight, width: 2, height: 54),
                colors.active_glow.toFloatRgba()
            ),
            (
                wlr_box(x: xPos, y: 48 + upHeight, width: boxWidth, height: 2),
                colors.active_glow.toFloatRgba()
            ),
            (
                wlr_box(x: xPos - 1, y: 48 + upHeight + 52, width: boxWidth, height: 2),
                colors.active_glow.toFloatRgba()
            )
        ]

        // Add lines to up boxes
        for i in 0..<upCount {
            boxes.append((
                wlr_box(
                    x: xPos + 4,
                    y: 48 + (i + 1) * 34,
                    width: boxWidth - 8,
                    height: lineWidth),
                colors.inactive_foreground.toFloatRgba()
            ))
        }

        // Add lines to down boxes
        for i in 0..<downCount {
            boxes.append((
                wlr_box(
                    x: xPos + 4,
                    y: 48 + upHeight + 60 + (i + 1) * 34,
                    width: boxWidth - 8,
                    height: lineWidth),
                colors.inactive_foreground.toFloatRgba()
            ))
        }

        return boxes
    }

    private func renderViewTitleTexts(stack: Stack<Surface>, font: String, colors: AwcOutputHudColors) 
    -> [(Int32, Int32, Cairo.Surface)] {
        let boxWidth = self.viewBoxWidth() - 2
        let xPos = Int32(Double(self.width) / 2 - boxWidth / 2 + 6)

        var currentY: Int32 = 48

        var result: [(Int32, Int32, Cairo.Surface)] = []
        for surface in stack.up.reverse() {
            result.append((
                xPos, currentY + 6,
                renderText(
                    surface.title,
                    font: font,
                    fontSize: 24,
                    maxWidth: boxWidth - 12,
                    color: colors.inactive_foreground)
            ))
            currentY += 34
        }

        result.append((
                xPos, currentY + 6,
                renderText(
                    stack.focus.title,
                    font: font,
                    fontSize: 36,
                    maxWidth: boxWidth - 4,
                    color: colors.active_foreground)
            ))
        currentY += 60

        for surface in stack.down {
            result.append((
                xPos, currentY + 6,
                renderText(
                    surface.title,
                    font: font,
                    fontSize: 24,
                    maxWidth: boxWidth - 12,
                    color: colors.inactive_foreground)
            ))
            currentY += 34
        }
        return result
    }

    private func renderText(
        _ text: String,
        font: String,
        fontSize: Double,
        maxWidth: Double,
        color: AwcColor) -> Cairo.Surface {
        if let surface = self.lookupCached(text: text, font: font, fontSize: fontSize) {
            return surface
        }

        var textExtents = cairo_text_extents_t()
        self.measureContext.selectFontFace(family: font)
        self.measureContext.set(fontSize: fontSize)
        self.measureContext.extents(text: text, &textExtents)

        let surface = Cairo.Surface(
            width: Int32(min(maxWidth, textExtents.width)),
            height: Int32(fontSize))
        let cairo = surface.context
        cairo.selectFontFace(family: font)
        cairo.set(fontSize: fontSize)
        color.setSourceRgb(cairo: cairo)
        cairo.moveTo(x: 0, y: fontSize / 2 - (textExtents.height / 2 + textExtents.y_bearing))
        cairo.show(text: text)

        self.textSurfaceCache[SurfaceCacheKey(text: text, font: font, fontSize: fontSize)] = surface

        return surface
    }

    private func lookupCached(text: String, font: String, fontSize: Double) -> Cairo.Surface? {
        return self.textSurfaceCache.get(
            forKey: SurfaceCacheKey(text: text, font: font, fontSize: fontSize))
    }
}

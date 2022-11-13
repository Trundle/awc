import Cairo
import CCairo
import DataStructures
import NeonRenderer

public struct AwcOutputHudColors {
    let active_background: AwcColor
    let active_foreground: AwcColor
    let active_glow: AwcColor
    let inactive_background: AwcColor
    let inactive_foreground: AwcColor
}

struct AwcColor {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8

    func toFloatRgba() -> float_rgba {
        float_rgba(
            r: Float(self.r) / 255.0,
            g: Float(self.g) / 255.0,
            b: Float(self.b) / 255.0,
            a: Float(self.a) / 255.0)
    }
}

private extension AwcColor {
    func setSourceRgb(cairo: Cairo.Context) {
        cairo.setSource(
            r: Double(self.r) / 255.0,
            g: Double(self.g) / 255.0,
            b: Double(self.b) / 255.0,
            a: Double(self.a) / 255.0)
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

    public func update(state: State, font: String, colors: AwcOutputHudColors) {
        if self.width != state.width || self.height != state.height {
            self.width = state.width
            self.height = state.height
            self.neonRenderer.updateSize(
                display: state.eglDisplay,
                context: state.eglContext,
                surface: state.eglSurface,
                width: self.width,
                height: self.height,
                scale: state.scale)
        }

        let (outputAndTagPositionX, outputAndTagSurface) = renderTagAndOutputName(
            tag: state.workspace.tag, outputName: state.outputName, font: font, colors: colors)

        let rects: [(Box, float_rgba)]
        let titleSurfaces: [(Int32, Int32, Cairo.Surface)]
        if !state.workspace.views.isEmpty {
            rects = renderViewTitleBoxes(views: state.workspace.views, font: font, colors: colors)
            titleSurfaces = renderViewTitleTexts(views: state.workspace.views, font: font, colors: colors)
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

    public func render(state: State) {
        self.neonRenderer.render(
            display: state.eglDisplay,
            context: state.eglContext,
            surface: state.eglSurface)
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

    private func renderViewTitleBoxes(views: [AwcView], font: String, colors: AwcOutputHudColors
    ) -> [(Box, float_rgba)] {
        let lineWidth: Int32 = 1
        let boxWidth = Int32(self.viewBoxWidth()) - 2 * lineWidth
        let xPos = Int32(Float(self.width) / 2 - Float(boxWidth) / 2)

        let focusIndex = views.firstIndex(where: { $0.focus })!
        let upCount = Int32(focusIndex)
        let upHeight = upCount * 34
        let downCount = Int32(views.count) - upCount - 1
        let downHeight = downCount * 34

        var boxes = [
            (
                Box(x: xPos + 4, y: 48, width: boxWidth - 8, height: upHeight), 
                colors.inactive_background.toFloatRgba()
            ),
            (
                Box(x: xPos, y: 48 + upHeight, width: boxWidth, height: 52),
                colors.active_background.toFloatRgba()
            ),
            (
                Box(x: xPos + 4, y: 48 + upHeight + 60, width: boxWidth - 8, height: downHeight),
                colors.inactive_background.toFloatRgba()
            ),
            // Border around active box
            (
                Box(x: xPos - 1, y: 48 + upHeight, width: 2, height: 52),
                colors.active_glow.toFloatRgba()
            ),
            (
                Box(x: xPos + boxWidth - 1, y: 48 + upHeight, width: 2, height: 54),
                colors.active_glow.toFloatRgba()
            ),
            (
                Box(x: xPos, y: 48 + upHeight, width: boxWidth, height: 2),
                colors.active_glow.toFloatRgba()
            ),
            (
                Box(x: xPos - 1, y: 48 + upHeight + 52, width: boxWidth, height: 2),
                colors.active_glow.toFloatRgba()
            )
        ]

        // Add lines to up boxes
        for i in 0..<upCount {
            boxes.append((
                Box(
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
                Box(
                    x: xPos + 4,
                    y: 48 + upHeight + 60 + (i + 1) * 34,
                    width: boxWidth - 8,
                    height: lineWidth),
                colors.inactive_foreground.toFloatRgba()
            ))
        }

        return boxes
    }

    private func renderViewTitleTexts(views: [AwcView], font: String, colors: AwcOutputHudColors) 
    -> [(Int32, Int32, Cairo.Surface)] {
        let boxWidth = self.viewBoxWidth() - 2
        let xPos = Int32(Double(self.width) / 2 - boxWidth / 2 + 6)

        var currentY: Int32 = 48

        let focusIndex = views.firstIndex(where: { $0.focus })!
        var result: [(Int32, Int32, Cairo.Surface)] = []
        for view in views[..<focusIndex] {
            result.append((
                xPos, currentY + 6,
                renderText(
                    view.title,
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
                    views[focusIndex].title,
                    font: font,
                    fontSize: 36,
                    maxWidth: boxWidth - 4,
                    color: colors.active_foreground)
            ))
        currentY += 60

        for view in views[(focusIndex + 1)...] {
            result.append((
                xPos, currentY + 6,
                renderText(
                    view.title,
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
        color: AwcColor
    ) -> Cairo.Surface {
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

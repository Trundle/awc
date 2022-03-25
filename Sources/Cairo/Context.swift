import CCairo

/// The drawing context
public class Context {
    private let rawCairo: OpaquePointer

    public init(for surface: Surface) {
        self.rawCairo = cairo_create(surface.rawSurface)
    }

    deinit {
        cairo_destroy(self.rawCairo)
    }

    public func save() {
        cairo_save(self.rawCairo)
    }

    public func restore() {
        cairo_restore(self.rawCairo)
    }

    public func clip() {
        cairo_clip(self.rawCairo)
    }

    public func fill() {
        cairo_fill(self.rawCairo)
    }

    public func lineTo(x: Double, y: Double) {
        cairo_line_to(self.rawCairo, x, y)
    }

    public func moveTo(x: Double, y: Double) {
        cairo_move_to(self.rawCairo, x, y)
    }

    public func rectangle(x: Double, y: Double, width: Double, height: Double) {
        cairo_rectangle(self.rawCairo, x, y, width, height)
    }

    public func selectFontFace(
        family: String, 
        slant: cairo_font_slant_t = CAIRO_FONT_SLANT_NORMAL, 
        weight: cairo_font_weight_t = CAIRO_FONT_WEIGHT_NORMAL
    ) {
        cairo_select_font_face(self.rawCairo, family, slant, weight)
    }

    public func set(fontSize: Double) {
        cairo_set_font_size(self.rawCairo, fontSize)
    }

    public func set(lineWidth: Double) {
        cairo_set_line_width(self.rawCairo, lineWidth)
    }

    public func setSource(r: Double, g: Double, b: Double) {
        cairo_set_source_rgb(self.rawCairo, r, g, b)
    }

    public func setSource(r: Double, g: Double, b: Double, a: Double) {
        cairo_set_source_rgba(self.rawCairo, r, g, b, a)
    }

    public func show(text: String) {
        cairo_show_text(self.rawCairo, text)
    }

    public func stroke() {
        cairo_stroke(self.rawCairo)
    }

    public func extents(text: String, _ extents: inout cairo_text_extents_t) {
        cairo_text_extents(self.rawCairo, text, &extents)
    }

    public func clear() {
        save()
        defer {
            restore()
        }

        cairo_set_operator(self.rawCairo, CAIRO_OPERATOR_CLEAR)
        cairo_paint(self.rawCairo)
    }

    public func withRawPointer<Result>(body: (OpaquePointer) -> Result) -> Result {
        return body(self.rawCairo)
    }
}

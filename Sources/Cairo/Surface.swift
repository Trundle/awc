import CCairo

public class Surface {
    let rawSurface: OpaquePointer

    public lazy var context: Context = Context(for: self)
    public lazy var height: Int32 = cairo_image_surface_get_height(rawSurface)
    public lazy var width: Int32 = cairo_image_surface_get_width(rawSurface)

    public init(width: Int32, height: Int32, format: cairo_format_t = CAIRO_FORMAT_ARGB32) {
        self.rawSurface = cairo_image_surface_create(format, width, height)       
    }

    deinit {
        cairo_surface_destroy(self.rawSurface)
    }

    public func withRawPointer<Result>(body: (OpaquePointer) -> Result) -> Result {
        return body(self.rawSurface)
    }
}

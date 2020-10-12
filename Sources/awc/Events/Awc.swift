import Wlroots

enum Event {
    case frame(output: UnsafeMutablePointer<wlr_output>)

    /// Forwarded by the cursor when a pointer emits an axis event (e.g. scroll wheel).
    case cursorAxis(event: UnsafeMutablePointer<wlr_event_pointer_axis>)
    case cursorButton(event: UnsafeMutablePointer<wlr_event_pointer_button>)
    case cursorFrame(cursor: UnsafeMutablePointer<wlr_cursor>)
    case cursorMotion(event: UnsafeMutablePointer<wlr_event_pointer_motion>)
    case cursorMotionAbsolute(event: UnsafeMutablePointer<wlr_event_pointer_motion_absolute>)

    /// Raised by the seat when a client provides a cursor image.
    case cursorRequested(event: UnsafeMutablePointer<wlr_seat_pointer_request_set_cursor_event>)

    case key(device: UnsafeMutablePointer<wlr_input_device>, event: UnsafeMutablePointer<wlr_event_keyboard_key>)
    case modifiers(device: UnsafeMutablePointer<wlr_input_device>, keyboard: UnsafeMutablePointer<wlr_keyboard>)

    case newInput(device: UnsafeMutablePointer<wlr_input_device>)
    case newOutput(output: UnsafeMutablePointer<wlr_output>)

    case newSurface(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>)
    case surfaceDestroyed(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>)
    case map(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>)
    case unmap(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>)

    case newXWaylandSurface(surface: UnsafeMutablePointer<wlr_xwayland_surface>)
    case xwaylandSurfaceDestroyed(xwaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>)
    case mapX(xwaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>)
    case unmapX(xwaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>)
}

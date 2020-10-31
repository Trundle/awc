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

    /// This event is raised by the seat when a client wants to set the selection,
    /// usually when the user copies something.
    case setSelectionRequested(event: UnsafeMutablePointer<wlr_seat_request_set_selection_event>)

    case key(device: UnsafeMutablePointer<wlr_input_device>, event: UnsafeMutablePointer<wlr_event_keyboard_key>)
    case keyboardDestroyed(device: UnsafeMutablePointer<wlr_input_device>)
    case modifiers(device: UnsafeMutablePointer<wlr_input_device>)

    case newInput(device: UnsafeMutablePointer<wlr_input_device>)
    case newOutput(output: UnsafeMutablePointer<wlr_output>)
    case outputDestroyed(output: UnsafeMutablePointer<wlr_output>)

    // MARK: XWayland events
    case xwaylandReady
    case newXWaylandSurface(surface: UnsafeMutablePointer<wlr_xwayland_surface>)
    case xwaylandSurfaceDestroyed(xwaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>)
    case configureRequestX(event: UnsafeMutablePointer<wlr_xwayland_surface_configure_event>)
    case mapX(xwaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>)
    case unmapX(xwaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>)
}

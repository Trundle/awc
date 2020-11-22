import Wlroots

enum Event {
    /// Forwarded by the cursor when a pointer emits an axis event (e.g. scroll wheel).
    case cursorAxis(event: UnsafeMutablePointer<wlr_event_pointer_axis>)
    case cursorButton(event: UnsafeMutablePointer<wlr_event_pointer_button>)
    case cursorFrame(cursor: UnsafeMutablePointer<wlr_cursor>)
    case cursorMotion(event: UnsafeMutablePointer<wlr_event_pointer_motion>)
    case cursorMotionAbsolute(event: UnsafeMutablePointer<wlr_event_pointer_motion_absolute>)

    case key(device: UnsafeMutablePointer<wlr_input_device>, event: UnsafeMutablePointer<wlr_event_keyboard_key>)
    case keyboardDestroyed(device: UnsafeMutablePointer<wlr_input_device>)
    case modifiers(device: UnsafeMutablePointer<wlr_input_device>)

    case newInput(device: UnsafeMutablePointer<wlr_input_device>)
    case newOutput(output: UnsafeMutablePointer<wlr_output>)
    case outputDestroyed(output: UnsafeMutablePointer<wlr_output>)
}

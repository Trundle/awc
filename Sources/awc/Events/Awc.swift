import Wlroots

enum Event {
    /// Forwarded by the cursor when a pointer emits an axis event (e.g. scroll wheel).
    case cursorAxis(event: UnsafeMutablePointer<wlr_pointer_axis_event>)
    case cursorButton(event: UnsafeMutablePointer<wlr_pointer_button_event>)
    case cursorFrame(cursor: UnsafeMutablePointer<wlr_cursor>)
    case cursorMotion(event: UnsafeMutablePointer<wlr_pointer_motion_event>)
    case cursorMotionAbsolute(event: UnsafeMutablePointer<wlr_pointer_motion_absolute_event>)

    case key(device: UnsafeMutablePointer<wlr_keyboard>, event: UnsafeMutablePointer<wlr_keyboard_key_event>)
    case keyboardDestroyed(device: UnsafeMutablePointer<wlr_input_device>)
    case modifiers(device: UnsafeMutablePointer<wlr_keyboard>)

    case newInput(device: UnsafeMutablePointer<wlr_input_device>)
    case newOutput(output: UnsafeMutablePointer<wlr_output>)
    case outputDestroyed(output: UnsafeMutablePointer<wlr_output>)
    case outputFrame(output: UnsafeMutablePointer<wlr_output>)
}

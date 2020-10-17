//
// A Wayland Compositor
//

import Glibc

import Wlroots


// MARK: Wlroots compatibility structures

private struct float_rgba {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float

    mutating func withPtr<Result>(_ body: (UnsafePointer<Float>) -> Result) -> Result {
        withUnsafePointer(to: &self.r, body)
    }
}

private typealias matrix9 = (Float, Float, Float, Float, Float, Float, Float, Float, Float)

// MARK: Wlroots convenience extensions

extension wlr_box {
    func contains(x: Int, y: Int) -> Bool {
        self.x <= x && x < self.x + self.width && self.y <= y && y < self.y + self.height
    }
}

// MARK: Awc

struct KeyModifiers: OptionSet {
    let rawValue: UInt32

    static let shift = KeyModifiers(rawValue: WLR_MODIFIER_SHIFT.rawValue)
    static let caps = KeyModifiers(rawValue: WLR_MODIFIER_CAPS.rawValue)
    static let ctrl = KeyModifiers(rawValue: WLR_MODIFIER_CTRL.rawValue)
    static let alt = KeyModifiers(rawValue: WLR_MODIFIER_ALT.rawValue)
    static let mod2 = KeyModifiers(rawValue: WLR_MODIFIER_MOD2.rawValue)
    static let mod3 = KeyModifiers(rawValue: WLR_MODIFIER_MOD3.rawValue)
    static let logo = KeyModifiers(rawValue: WLR_MODIFIER_LOGO.rawValue)
    static let mod5 = KeyModifiers(rawValue: WLR_MODIFIER_MOD5.rawValue)
}

class Awc {
    var viewSet: ViewSet<Surface>
    private let wlEventHandler: WlEventHandler
    let outputLayout: UnsafeMutablePointer<wlr_output_layout>
    private let renderer: UnsafeMutablePointer<wlr_renderer>
    private let noOpOutput: UnsafeMutablePointer<wlr_output>
    let cursor: UnsafeMutablePointer<wlr_cursor>
    let cursorManager: UnsafeMutablePointer<wlr_xcursor_manager>
    let seat: UnsafeMutablePointer<wlr_seat>
    let xwayland: UnsafeMutablePointer<wlr_xwayland>
    private var hasKeyboard: Bool = false
    // The views that exist, should be managed, but are not mapped yet
    var unmapped: Set<Surface> = []
    // The "mod" key to be used for ked bindings, typically logo
    let mod: KeyModifiers = .alt

    init(
        wlEventHandler: WlEventHandler,
        noOpOutput: UnsafeMutablePointer<wlr_output>,
        outputLayout: UnsafeMutablePointer<wlr_output_layout>,
        renderer: UnsafeMutablePointer<wlr_renderer>,
        cursor: UnsafeMutablePointer<wlr_cursor>,
        cursorManager: UnsafeMutablePointer<wlr_xcursor_manager>,
        seat: UnsafeMutablePointer<wlr_seat>,
        xwayland: UnsafeMutablePointer<wlr_xwayland>
    ) {
        let layout = Choose(Full(), TwoPane())
        let workspace: Workspace<Surface> = Workspace(
            tag: "1",
            layout: layout
        )
        let output = Output(wlrOutput: noOpOutput, workspace: workspace)
        var otherWorkspaces: [Workspace<Surface>] = []
        for i in 2...9 {
            otherWorkspaces.append(Workspace(tag: "\(i)", layout: layout))
        }
        self.viewSet = ViewSet(current: output, hidden: otherWorkspaces)
        self.outputLayout = outputLayout
        self.renderer = renderer
        self.noOpOutput = noOpOutput
        self.cursor = cursor
        self.cursorManager = cursorManager
        self.seat = seat
        self.xwayland = xwayland
        self.wlEventHandler = wlEventHandler
        self.wlEventHandler.onEvent = self.onEvent
    }

    private func renderSurface(
        output: UnsafeMutablePointer<wlr_output>,
        px: Int32,
        py: Int32,
        surface: UnsafeMutablePointer<wlr_surface>,
        sx: Int32,
        sy: Int32,
        when: UnsafePointer<timespec>
    ) {
        // We first obtain a wlr_texture, which is a GPU resource. wlroots
        // automatically handles negotiating these with the client. The underlying
        // resource could be an opaque handle passed from the client, or the client
        // could have sent a pixel buffer which we copied to the GPU, or a few other
        // means. You don't have to worry about this, wlroots takes care of it.
        guard let texture = wlr_surface_get_texture(surface) else {
            return
        }

        // We also have to apply the scale factor for HiDPI outputs. This is only
        // part of the puzzle, AWC does not fully support HiDPI.
        let scale = Double(output.pointee.scale)
        var box = wlr_box(
            x: Int32(Double(px + sx) * scale),
            y: Int32(Double(py + sy) * scale),
            width: Int32(Double(surface.pointee.current.width) * scale),
            height: Int32(Double(surface.pointee.current.height) * scale)
        )

        // Those familiar with OpenGL are also familiar with the role of matrices
        // in graphics programming. We need to prepare a matrix to render the view
        // with. wlr_matrix_project_box is a helper which takes a box with a desired
        // x, y coordinates, width and height, and an output geometry, then
        // prepares an orthographic projection and multiplies the necessary
        // transforms to produce a model-view-projection matrix.
        //
        // Naturally you can do this any way you like, for example to make a 3D
        // compositor.
        var matrix: matrix9 = (0, 0, 0, 0, 0, 0, 0, 0, 0)
        let transform = wlr_output_transform_invert(surface.pointee.current.transform)
        withUnsafeMutablePointer(to: &matrix.0) { matrixPtr in
            withUnsafePointer(to: &output.pointee.transform_matrix.0) { (outputTransformMatrixPtr) in
                wlr_matrix_project_box(matrixPtr, &box, transform, 0, outputTransformMatrixPtr)
            }

            // This takes our matrix, the texture, and an alpha, and performs the actual rendering on the GPU.
            wlr_render_texture_with_matrix(self.renderer, texture, matrixPtr, 1)
        }

        // This lets the client know that we've displayed that frame and it can prepare another one now if it likes.
        wlr_surface_send_frame_done(surface, when)
    }

    private func viewAt(x: Double, y: Double)
                    -> (UnsafeMutablePointer<wlr_surface>, UnsafeMutablePointer<wlr_surface>, Double, Double)?
    {
        for output in self.viewSet.outputs() {
            for (view, box) in output.arrangement {
                if box.contains(x: Int(x), y: Int(y)) {
                    let surfaceX = x - Double(box.x)
                    let surfaceY = y - Double(box.y)
                    var sx: Double = 0
                    var sy: Double = 0
                    switch view {
                    case .xdg(let viewSurface):
                        if let surface = wlr_xdg_surface_surface_at(viewSurface, surfaceX, surfaceY, &sx, &sy) {
                            return (view.wlrSurface, surface, sx, sy)
                        }
                    case .xwayland:
                        if let surface = wlr_surface_surface_at(view.wlrSurface, surfaceX, surfaceY, &sx, &sy) {
                            return (view.wlrSurface, surface, sx, sy)
                        }
                    }
                }
            }
        }
        return nil
    }

    private func handleKeyPress(modifiers: KeyModifiers, sym: xkb_keysym_t) -> Bool {
        if sym == XKB_KEY_n && modifiers == [self.mod] {
            self.modifyAndUpdate {
                $0.modify {
                    $0.focusUp()
                }
            }
            return true
        } else if sym == XKB_KEY_N && modifiers == [.shift, self.mod] {
            self.modifyAndUpdate {
                $0.modify { $0.swapUp() }
            }
            return true
        } else if sym == XKB_KEY_r && modifiers == [self.mod] {
            self.modifyAndUpdate {
                $0.modify {
                    $0.focusDown()
                }
            }
            return true
        } else if sym == XKB_KEY_R && modifiers == [.shift, self.mod] {
            self.modifyAndUpdate {
                $0.modify { $0.swapDown() }
            }
            return true
        } else if sym == XKB_KEY_Return && modifiers == [self.mod] {
            self.modifyAndUpdate {
                $0.modify { $0.swapPrimary() }
            }
            return true
        } else if sym == XKB_KEY_C && modifiers == [.shift, self.mod] {
            self.kill()
            return true
        } else if sym == XKB_KEY_Return && modifiers == [.shift, self.mod] {
            executeCommand("kitty -o linux_display_server=wayland")
            return true
        } else if sym >= XKB_KEY_1 && sym <= XKB_KEY_9 && modifiers == [self.mod] {
            let n = sym - UInt32(XKB_KEY_0)
            self.modifyAndUpdate {
                $0.view(tag: "\(n)")
            }
            return true
        } else if [XKB_KEY_degree, XKB_KEY_section, 0x1002113, XKB_KEY_guillemotright,
                   XKB_KEY_guillemotleft, XKB_KEY_dollar, XKB_KEY_EuroSign, XKB_KEY_doublelowquotemark,
                   XKB_KEY_leftdoublequotemark].contains(Int32(sym)) && modifiers == [.shift, self.mod] {
            let n = 1 + [XKB_KEY_degree, XKB_KEY_section, 0x1002113, XKB_KEY_guillemotright,
                         XKB_KEY_guillemotleft, XKB_KEY_dollar, XKB_KEY_EuroSign, XKB_KEY_doublelowquotemark,
                         XKB_KEY_leftdoublequotemark].firstIndex(of: Int32(sym))!
            self.modifyAndUpdate {
                $0.shift(tag: "\(n)")
            }
            return true
        } else if (([XKB_KEY_x, XKB_KEY_v, XKB_KEY_l].contains(Int32(sym)) && modifiers == [.alt])
                || ([XKB_KEY_X, XKB_KEY_V, XKB_KEY_L].contains(Int32(sym)) && modifiers == [.shift, self.mod]))
        {
            let outputs = self.orderedOutputs()
            let n = [XKB_KEY_x, XKB_KEY_v, XKB_KEY_l, XKB_KEY_X, XKB_KEY_V, XKB_KEY_L].firstIndex(of: Int32(sym))! % 3
            if n < outputs.count {
                let targetTag = outputs[n].workspace.tag
                self.modifyAndUpdate {
                    if modifiers.contains(.shift) {
                        return $0.shift(tag: targetTag)
                    } else {
                        return $0.view(tag: targetTag)
                    }
                }
            }
            return true
        } else if sym == XKB_KEY_F1 {
            if let nextLayout = self.viewSet.current.workspace.layout.nextLayout() {
                self.modifyAndUpdate {
                    $0.replace(current: $0.current.replace(workspace: $0.current.workspace.replace(layout: nextLayout)))
                }
            }
            return true
        }
        return false
    }
}

// MARK: Event handling

extension Awc {
    private func onEvent(event: Event) {
        switch event {
        case .cursorAxis(let event): handleCursorAxis(event)
        case .cursorButton(let event): handleCursorButton(event)
        case .cursorFrame: handleCursorFrame()
        case .cursorMotion(let cursor): handleCursorMotion(cursor)
        case .cursorMotionAbsolute(let cursor): handleCursorMotionAbsolute(cursor)
        case .cursorRequested(let event): handleCursorRequested(event)
        case .frame(let output): handleFrame(output)
        case .key(let device, let keyEvent): handleKey(device, keyEvent)
        case .modifiers(let device, _): handleModifiers(device)
        case .newInput(let device): handleNewInput(device)
        case .newOutput(let output): handleNewOutput(output)
        case .newSurface(let surface): handleNewXdgSurface(surface)
        case .surfaceDestroyed(let surface): handleSurfaceDestroyed(surface)
        case .map(let surface): handleMap(surface)
        case .unmap(let surface): handleUnmap(surface)
        case .newXWaylandSurface(let surface): handleNewXWaylandSurface(surface)
        case .xwaylandSurfaceDestroyed(let surface): handleXWaylandSurfaceDestroyed(surface)
        case .mapX(let surface): handleMapX(surface)
        case .unmapX(let surface): handleUnmapX(surface)
        }
    }

    private func handleCursorAxis(_ event: UnsafeMutablePointer<wlr_event_pointer_axis>) {
        wlr_seat_pointer_notify_axis(
            self.seat,
            event.pointee.time_msec,
            event.pointee.orientation,
            event.pointee.delta,
            event.pointee.delta_discrete,
            event.pointee.source
        )
    }

    private func handleCursorButton(_ event: UnsafeMutablePointer<wlr_event_pointer_button>) {
        // XXX change focus here
        // Notify the client with pointer focus that a button press has occurred
        wlr_seat_pointer_notify_button(self.seat, event.pointee.time_msec, event.pointee.button, event.pointee.state)
    }

    /**
     * This event is forwarded by the cursor when a pointer emits an frame
	 * event. Frame events are sent after regular pointer events to group
	 * multiple events together. For instance, two axis events may happen at the
	 * same time, in which case a frame event won't be sent in between.
	 */
    private func handleCursorFrame() {
        wlr_seat_pointer_notify_frame(self.seat)
    }

    /// This event is forwarded by the cursor when a pointer emits a relative pointer motion event.
    private func handleCursorMotion(_ event: UnsafeMutablePointer<wlr_event_pointer_motion>) {
        // The cursor doesn't move unless we tell it to. The cursor automatically
        // handles constraining the motion to the output layout, as well as any
        // special configuration applied for the specific input device which
        // generated the event. You can pass NULL for the device if you want to move
        // the cursor around without any input.
        wlr_cursor_move(self.cursor, event.pointee.device, event.pointee.delta_x, event.pointee.delta_y)
        self.handleCursorMotion(time: event.pointee.time_msec)
    }

    /**
     * This event is forwarded by the cursor when a pointer emits an absolute
     * motion event, from 0..1 on each axis. This happens, for example, when
     * wlroots is running under a Wayland window rather than KMS+DRM, and you
     * move the mouse over the window. You could enter the window from any edge,
     * so we have to warp the mouse there. There is also some hardware which
     * emits these events.
     */
    private func handleCursorMotionAbsolute(_ event: UnsafeMutablePointer<wlr_event_pointer_motion_absolute>) {
        wlr_cursor_warp_absolute(self.cursor, event.pointee.device, event.pointee.x, event.pointee.y)
        self.handleCursorMotion(time: event.pointee.time_msec)
    }

    /// Handles the common path for a relative and absolute cursor motion
    private func handleCursorMotion(time: UInt32) {
        let cx = self.cursor.pointee.x
        let cy = self.cursor.pointee.y
        if let (_, surface, sx, sy) = self.viewAt(x: cx, y: cy) {
            let focusChanged = self.seat.pointee.pointer_state.focused_surface != surface
            wlr_seat_pointer_notify_enter(self.seat, surface, sx, sy)
            if !focusChanged {
                // The enter event contains coordinates, so we only need to notify on
                // motion if the focus did not change
                wlr_seat_pointer_notify_motion(self.seat, time, sx, sy)
            }
        } else {
            // If there's no surface under the cursor, set the cursor image to a
            // default. This is what makes the cursor image appear when you move it
            // around the screen, not over any surfaces.
            wlr_xcursor_manager_set_cursor_image(self.cursorManager, "left_ptr", self.cursor)
            wlr_seat_pointer_clear_focus(self.seat)
        }
    }

    private func handleCursorRequested(_ event: UnsafeMutablePointer<wlr_seat_pointer_request_set_cursor_event>) {
        let focusedClient = self.seat.pointee.pointer_state.focused_client
        // This can be sent by any client, so we check to make sure this one is actually has pointer focus first.
        if focusedClient == event.pointee.seat_client {
            wlr_cursor_set_surface(
                self.cursor, event.pointee.surface, event.pointee.hotspot_x, event.pointee.hotspot_y
            )
        }
    }

    private func handleNewInput(_ device: UnsafeMutablePointer<wlr_input_device>) {
        if device.pointee.type == WLR_INPUT_DEVICE_KEYBOARD {
            let context = xkb_context_new(XKB_CONTEXT_NO_FLAGS)
            let keymap: OpaquePointer = "de(neo)".withCString {
                var rules = xkb_rule_names()
                rules.layout = $0
                return xkb_keymap_new_from_names(context, &rules, XKB_KEYMAP_COMPILE_NO_FLAGS)
            }
            wlr_keyboard_set_keymap(device.pointee.keyboard, keymap)

            wlr_keyboard_set_repeat_info(device.pointee.keyboard, 25, 600)

            self.wlEventHandler.addKeyboardListeners(device: device)

            xkb_keymap_unref(keymap)
            xkb_context_unref(context)

            wlr_seat_set_keyboard(self.seat, device)
            self.hasKeyboard = true
        } else if device.pointee.type == WLR_INPUT_DEVICE_POINTER {
            // We don't do anything special with pointers. All of our pointer handling
            // is proxied through wlr_cursor. On another compositor, you might take this
            // opportunity to do libinput configuration on the device to set
            // acceleration, etc.
            wlr_cursor_attach_input_device(self.cursor, device)
        }

        // We need to let the wlr_seat know what our capabilities are, which is
        // communicated to the client. We always have a cursor, even if
        // there are no pointer devices, so we always include that capability.
        var caps = WL_SEAT_CAPABILITY_POINTER.rawValue
        if hasKeyboard {
            caps |= WL_SEAT_CAPABILITY_KEYBOARD.rawValue
        }
        wlr_seat_set_capabilities(self.seat, caps)
    }

    private func handleNewOutput(_ wlrOutput: UnsafeMutablePointer<wlr_output>) {
        // Some backends don't have modes. DRM+KMS does, and we need to set a mode
        // before we can use the output. The mode is a tuple of (width, height,
        // refresh rate), and each monitor supports only a specific set of modes. We
        // just pick the monitor's preferred mode, a more sophisticated compositor
        // would let the user configure it.
        if wl_list_empty(&wlrOutput.pointee.modes) == 0 {
            let mode = wlr_output_preferred_mode(wlrOutput)
            wlr_output_set_mode(wlrOutput, mode)
            wlr_output_enable(wlrOutput, true)
            guard wlr_output_commit(wlrOutput) else {
                return
            }
        }

        if self.viewSet.current.output == self.noOpOutput {
            self.viewSet = self.viewSet.replace(
                current: Output(wlrOutput: wlrOutput, workspace: self.viewSet.current.workspace))
        } else {
            var hidden = Array(self.viewSet.hidden)
            if let workspace = hidden.popLast() {
                self.viewSet = self.viewSet.replace(
                    current: Output(wlrOutput: wlrOutput, workspace: workspace),
                    visible: Array(self.viewSet.visible) + [self.viewSet.current],
                    hidden: hidden
                )
            }
        }

        self.wlEventHandler.addOutputListeners(output: wlrOutput)

        // Adds this to the output layout. The add_auto function arranges outputs
        // from left-to-right in the order they appear. A more sophisticated
        // compositor would let the user configure the arrangement of outputs in th
        // layout.
        // The output layout utility automatically adds a wl_output global to the
        // display, which Wayland clients can see to find out information about the
        // output (such as DPI, scale factor, manufacturer, etc).
        wlr_output_layout_add_auto(self.outputLayout, wlrOutput)

        // Show a cursor
        wlr_xcursor_manager_set_cursor_image(self.cursorManager, "left_ptr", self.cursor)
    }

    private func handleMap(_ xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>) {
        let surface = Surface.xdg(surface: xdgSurface)
        if self.unmapped.remove(surface) != nil {
            self.manage(surface: surface)
        }
    }

    private func handleUnmap(_ xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>) {
        handleUnmap(surface: Surface.xdg(surface: xdgSurface))
    }

    private func handleUnmap(surface: Surface) {
        self.modifyAndUpdate {
            self.unmapped.insert(surface)
            return $0.remove(view: surface)
        }
    }

    private func handleNewXdgSurface(_ surface: UnsafeMutablePointer<wlr_xdg_surface>) {
        // XXX does it require additional checks?
        guard surface.pointee.role == WLR_XDG_SURFACE_ROLE_TOPLEVEL else {
            return
        }
        self.unmapped.insert(Surface.xdg(surface: surface))
        self.wlEventHandler.addXdgSurfaceListeners(surface: surface)
        wlr_xdg_surface_ping(surface)
    }

    private func handleSurfaceDestroyed(_ surface: UnsafeMutablePointer<wlr_xdg_surface>) {
        self.unmapped.remove(Surface.xdg(surface: surface))
    }

    private func handleNewXWaylandSurface(_ surface: UnsafeMutablePointer<wlr_xwayland_surface>) {
        wlr_xwayland_surface_ping(surface)
        self.unmapped.insert(Surface.xwayland(surface: surface))
        self.wlEventHandler.addXWaylandSurfaceListeners(surface: surface)
    }

    private func handleXWaylandSurfaceDestroyed(_ surface: UnsafeMutablePointer<wlr_xwayland_surface>) {
        self.unmapped.remove(Surface.xwayland(surface: surface))
    }

    private func handleMapX(_ xwaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>) {
        let surface = Surface.xwayland(surface: xwaylandSurface)
        if self.unmapped.remove(surface) != nil {
            self.manage(surface: surface)
        }
    }

    private func handleUnmapX(_ xwaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>) {
        handleUnmap(surface: Surface.xwayland(surface: xwaylandSurface))
    }

    /**
     * Called every time an output is ready to display a frame, so generally at the output's
     * refresh rate.
     */
    private func handleFrame(_ wlrOutput: UnsafeMutablePointer<wlr_output>) {
        // wlr_output_attach_render makes the OpenGL context current
        guard wlr_output_attach_render(wlrOutput, nil) else {
            return
        }

        var now = timespec()
        clock_gettime(CLOCK_MONOTONIC, &now)

        // The "effective" resolution can change if one rotates the outputs
        var width: Int32 = 0
        var height: Int32 = 0
        wlr_output_effective_resolution(wlrOutput, &width, &height)
        // Begin the rendering (calls glViewport and some other GL sanity checks)
        wlr_renderer_begin(self.renderer, width, height)

        var color = float_rgba(r: 0.3, g: 0.3, b: 0.3, a: 1.0)
        color.withPtr { wlr_renderer_clear(self.renderer, $0) }

        // Find the workspace for this output
        if let output = self.viewSet.outputs().first(where: { $0.output == wlrOutput }) {
            for (parent, box) in output.arrangement {
                withUnsafePointer(to: now) {
                    for (surface, sx, sy) in parent.surfaces() {
                        self.renderSurface(
                            output: wlrOutput,
                            px: box.x,
                            py: box.y,
                            surface: surface,
                            sx: sx,
                            sy: sy,
                            when: $0
                        )
                    }
                }
            }
        }

        // Hardware cursors are rendered by the GPU on a separate plane, and can be
        // moved around without re-rendering what's beneath them - which is more
        // efficient. However, not all hardware supports hardware cursors. For this
        // reason, wlroots provides a software fallback, which we ask it to render
        // here. wlr_cursor handles configuring hardware vs software cursors for you,
        // and this function is a no-op when hardware cursors are in use.
        wlr_output_render_software_cursors(wlrOutput, nil)

        // Conclude rendering and swap the buffers, showing the final frame on-screen.
        wlr_renderer_end(self.renderer)
        wlr_output_commit(wlrOutput)
    }

    private func handleKey(
        _ device: UnsafeMutablePointer<wlr_input_device>,
        _ event: UnsafeMutablePointer<wlr_event_keyboard_key>
    ) {
        // Translate libinput keycode -> xkbcommon
        let keycode = event.pointee.keycode + 8
        // Get a list of keysyms based on the keymap for this keyboard
        let syms = UnsafeMutablePointer<Optional<UnsafePointer<xkb_keysym_t>>>.allocate(capacity: 1)
        defer {
            syms.deallocate()
        }
        let nsyms = xkb_state_key_get_syms(device.pointee.keyboard.pointee.xkb_state, keycode, syms)

        var handled = false
        let modifiers = KeyModifiers(rawValue: wlr_keyboard_get_modifiers(device.pointee.keyboard))
        if event.pointee.state == WLR_KEY_PRESSED {
            for i in 0..<Int(nsyms) {
                if let symPtr = syms[i] {
                    if handleKeyPress(modifiers: modifiers, sym: symPtr.pointee) {
                        handled = true
                        break
                    }
                }
            }
        }

        if !handled {
            // Pass the key event on to the client
            wlr_seat_set_keyboard(self.seat, device)
            wlr_seat_keyboard_notify_key(
                    self.seat, event.pointee.time_msec, event.pointee.keycode, event.pointee.state.rawValue)
        }
    }

    private func handleModifiers(_ device: UnsafeMutablePointer<wlr_input_device>) {
        // A seat can only have one keyboard, but this is a limitation of the
        // Wayland protocol - not wlroots. We assign all connected keyboards to the
        // same seat. You can swap out the underlying wlr_keyboard like this and
        // wlr_seat handles this transparently.
        wlr_seat_set_keyboard(self.seat, device)
        // Send modifiers to the client.
        wlr_seat_keyboard_notify_modifiers(self.seat, &device.pointee.keyboard.pointee.modifiers)
    }
}

private func setupXWayland(
    display: OpaquePointer,
    compositor: UnsafeMutablePointer<wlr_compositor>,
    wlEventHandler: WlEventHandler
) -> UnsafeMutablePointer<wlr_xwayland> {
    let xwayland = wlr_xwayland_create(display, compositor, true)
    wlEventHandler.addXWaylandListeners(xwayland: xwayland!)
    setenv("DISPLAY", xwayland!.pointee.display_name, 1)
    return xwayland!
}

func main() {
    wlr_log_init(WLR_DEBUG, nil)
    // The Wayland display is managed by libwayland. It handles accepting clients from the Unix
    // socket, managing Wayland globals, and so on.
    let wlDisplay = wl_display_create()
    // The backend is a wlroots feature which abstracts the underlying input and
    // output hardware. The autocreate option will choose the most suitable
    // backend based on the current environment, such as opening an X11 window
    // if an X11 server is running. The NULL argument here optionally allows you
    // to pass in a custom renderer if wlr_renderer doesn't meet your needs. The
    // backend uses the renderer, for example, to fall back to software cursors
    // if the backend does not support hardware cursors (some older GPUs
    // don't).
    let backend = wlr_backend_autocreate(wlDisplay, nil)

    // Create a no-op backend and output. Used when there is no other output.
    let noopBackend = wlr_noop_backend_create(wlDisplay)
    let noopOutput = wlr_noop_add_output(noopBackend)

    // If we don't provide a renderer, autocreate makes a GLES2 renderer for us.
    // The renderer is responsible for defining the various pixel formats it
    // supports for shared memory, this configures that for clients.
    let renderer = wlr_backend_get_renderer(backend)
    wlr_renderer_init_wl_display(renderer, wlDisplay)

    // This creates some hands-off wlroots interfaces. The compositor is
    // necessary for clients to allocate surfaces and the data device manager
    // handles the clipboard. Each of these wlroots interfaces has room for you
    // to dig your fingers in and play with their behavior if you want. Note that
    // the clients cannot set the selection directly without compositor approval,
    // see the handling of the request_set_selection event below.
    let compositor = wlr_compositor_create(wlDisplay, renderer)
    wlr_data_device_manager_create(wlDisplay)

    // Creates an output layout, which a wlroots utility for working with an arrangement
    // of screens in a physical layout.
    let outputLayout = wlr_output_layout_create()

    let wlEventHandler = WlEventHandler()

    // Set up our list of views and the xdg-shell. The xdg-shell is a Wayland
    // protocol which is used for application windows.
    let xdg_shell = wlr_xdg_shell_create(wlDisplay)
    wlEventHandler.addXdgShellListeners(xdgShell: xdg_shell!)

    // Configures a seat, which is a single "seat" at which a user sits and
    // operates the computer. This conceptually includes up to one keyboard,
    // pointer, touch, and drawing tablet device. We also rig up a listener to
    // let us know when new input devices are available on the backend.
    wlEventHandler.addBackendListeners(backend: backend!)
    let seat = wlr_seat_create(wlDisplay, "seat0")
    wlEventHandler.addSeatListeners(seat: seat!)

    // Creates a cursor, which is a wlroots utility for tracking the cursor image shown on screen.
    let cursor = wlr_cursor_create()
    wlr_cursor_attach_output_layout(cursor, outputLayout)

    // Creates an xcursor manager, another wlroots utility which loads up
    // Xcursor themes to source cursor images from and makes sure that cursor
    // images are available at all scale factors on the screen (necessary for
    // HiDPI support). We add a cursor theme at scale factor 1 to begin with.
    let cursorManager = wlr_xcursor_manager_create(nil, 24)
    wlr_xcursor_manager_load(cursorManager, 1)

    // wlr_cursor *only* displays an image on screen. It does not move around
    // when the pointer moves. However, we can attach input devices to it, and
    // it will generate aggregate events for all of them. In these events, we
    // can choose how we want to process them, forwarding them to clients and
    // moving the cursor around. More detail on this process is described at
    // https://drewdevault.com/2018/07/17/Input-handling-in-wlroots.html
    //
    // And more comments are sprinkled throughout the notify functions above.
    wlEventHandler.addCursorListeners(cursor: cursor!)

    /* Add a Unix socket to the Wayland display. */
    guard let socket = wl_display_add_socket_auto(wlDisplay) else {
        wlr_backend_destroy(backend)
        wlr_backend_destroy(noopBackend)
        return
    }

    // Start the backend. This will enumerate outputs and inputs, become the DRM master, etc
    guard wlr_backend_start(backend) else {
        wlr_backend_destroy(backend)
        wlr_backend_destroy(noopBackend)
        wl_display_destroy(wlDisplay)
        return
    }

    setenv("WAYLAND_DISPLAY", socket, 1)

    let xwayland = setupXWayland(display: wlDisplay!, compositor: compositor!, wlEventHandler: wlEventHandler)

    let awc = Awc(
        wlEventHandler: wlEventHandler, noOpOutput: noopOutput!, outputLayout: outputLayout!,
        renderer: renderer!,
        cursor: cursor!,
        cursorManager: cursorManager!,
        seat: seat!,
        xwayland: xwayland
    )

    // Run the Wayland event loop. This does not return until you exit the
    // compositor. Starting the backend rigged up all of the necessary event
    // loop configuration to listen to libinput events, DRM events, generate
    // frame events at the refresh rate, and so on.
    print("[INFO] Running Wayland compositor on WAYLAND_DISPLAY=\(String(cString: socket))")
    wl_display_run(wlDisplay)

    // Once wl_display_run returns, we shut down the server.
    wl_display_destroy_clients(wlDisplay)
    wl_display_destroy(wlDisplay)
}

main()

import Libawc
import Wlroots

extension Awc {
    /// Focuses the top window (if there is one)
    func focusTop() {
        withFocused { focus in
            if let prevSurface = self.seat.pointee.keyboard_state.focused_surface {
                guard prevSurface != focusedWlrSurface() else {
                    return
                }
                if wlr_surface_is_xdg_surface(prevSurface) {
                    let prevXdgSurface = wlr_xdg_surface_from_wlr_surface(prevSurface)
                    wlr_xdg_toplevel_set_activated(prevXdgSurface, false)
                } else if wlr_surface_is_xwayland_surface(prevSurface) {
                    let prevXWaylandSurface = wlr_xwayland_surface_from_wlr_surface(prevSurface)!
                    if !focus.popupOf(wlrXWaylandSurface: prevXWaylandSurface) {
                        wlr_xwayland_surface_activate(prevXWaylandSurface, false)
                    }
                }
            }

            // Activate the new surface
            switch focus {
            case .xdg(let surface): wlr_xdg_toplevel_set_activated(surface, true)
            case .xwayland(let surface):
                wlr_xwayland_surface_activate(surface, true)
                wlr_xwayland_set_seat(self.xwayland, self.seat);
            }
            // Tell the seat to have the keyboard enter this surface. wlroots will keep
            // track of this and automatically send key events to the appropriate
            // clients without additional work on your part.
            let keyboard = wlr_seat_get_keyboard(self.seat)!
            withUnsafeMutablePointer(to: &keyboard.pointee.keycodes.0) { keycodesPtr in
                wlr_seat_keyboard_notify_enter(
                        self.seat,
                        focus.wlrSurface,
                        keycodesPtr,
                        keyboard.pointee.num_keycodes,
                        &keyboard.pointee.modifiers)
            }
        }
    }

    /// Modifies the view set with given function and then updates.
    func modifyAndUpdate(_ f: (ViewSet<Surface>) -> ViewSet<Surface>) {
        self.viewSet = f(self.viewSet)
        self.updateLayout()
        self.focusTop()
    }

    /// Adds a new surface to be managed in the current workspace and brings it into focus.
    func manage(surface: Surface) {
        let floatingBox = surface.preferredFloatingBox(awc: self, output: self.viewSet.current)
        if floatingBox == nil {
            surface.setTiled()
        }
        self.modifyAndUpdate {
            var viewSet = $0.modifyOr(default: Stack.singleton(surface), { $0.insert(surface) })
            if floatingBox != nil {
                viewSet = viewSet.float(view: surface, box: floatingBox!)
            }
            return viewSet
        }
    }

    func updateLayout() {
        for output in self.viewSet.outputs() {
            let outputLayoutBox = wlr_output_layout_get_box(self.outputLayout, output.output).pointee
            let outputBox = wlr_box(x: 0, y: 0, width: outputLayoutBox.width, height: outputLayoutBox.height)

            if let stack = output.workspace.stack?.filter({ !self.viewSet.floating.contains(key: $0) }) {
                let arrangement = output.workspace.layout.doLayout(stack: stack, box: outputBox)
                for (surface, box) in arrangement {
                    surface.configure(output: outputLayoutBox, box: box)
                }
                output.arrangement = arrangement
            } else {
                output.arrangement = []
            }

            // Add floating windows
            if let stack = output.workspace.stack {
                for surface in stack.toList() {
                    if let box = self.viewSet.floating[surface] {
                        surface.configure(output: outputLayoutBox, box: box)
                        output.arrangement.append((surface, box))
                    }
                }
            }
        }
    }

    /// Kills the currently focused surface.
    func kill() {
        self.withFocused {
            switch $0 {
            case .xdg(let surface): wlr_xdg_toplevel_send_close(surface)
            case .xwayland(let surface): wlr_xwayland_surface_close(surface)
            }
        }
    }

    /// Applies operation `f` to the currently focused surface, if there is one.
    func withFocused(_ f: (Surface) -> ()) {
        if let stack = self.viewSet.current.workspace.stack {
            f(stack.focus)
        }
    }

    /// Returns an array of all outputs, where the first element is the left-most output.
    func orderedOutputs() -> [Output<Surface>] {
        self.viewSet.outputs()
            .map { ($0, wlr_output_layout_get_box(self.outputLayout, $0.output)!) }
            .sorted(by: { $0.1.pointee.x <= $1.1.pointee.x })
            .map { $0.0 }
    }

    /// Returns the current workspace's focused surface's wlr_surface.
    private func focusedWlrSurface() -> UnsafeMutablePointer<wlr_surface>? {
        if let surface = self.viewSet.current.workspace.stack?.focus {
            return surface.wlrSurface
        } else {
            return nil
        }
    }
}

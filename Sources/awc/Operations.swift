import Wlroots

extension Awc {
    /// Focuses the top window (if there is one)
    func focusTop() {
        let keyboard = wlr_seat_get_keyboard(self.seat)!

        if let prevSurface = self.seat.pointee.keyboard_state.focused_surface {
            guard prevSurface != focusedWlrSurface() else {
                return
            }
            if wlr_surface_is_xdg_surface(prevSurface) {
                let prevXdgSurface = wlr_xdg_surface_from_wlr_surface(prevSurface)
                wlr_xdg_toplevel_set_activated(prevXdgSurface, false)
            } else if wlr_surface_is_xwayland_surface(prevSurface) {
                let prevXWaylandSurface = wlr_xwayland_surface_from_wlr_surface(prevSurface)
                wlr_xwayland_surface_activate(prevXWaylandSurface, false)
            }
        }

        if let stack = self.viewSet.current.workspace.stack {
            // Activate the new surface
            switch stack.focus {
            case .xdg(let surface): wlr_xdg_toplevel_set_activated(surface, true)
            case .xwayland(let surface):
                wlr_xwayland_surface_activate(surface, true)
                wlr_xwayland_set_seat(self.xwayland, self.seat);
            }
            // Tell the seat to have the keyboard enter this surface. wlroots will keep
            // track of this and automatically send key events to the appropriate
            // clients without additional work on your part.
            withUnsafeMutablePointer(to: &keyboard.pointee.keycodes.0) { keycodesPtr in
                wlr_seat_keyboard_notify_enter(
                        self.seat,
                        stack.focus.wlrSurface,
                        keycodesPtr,
                        keyboard.pointee.num_keycodes,
                        &keyboard.pointee.modifiers)
            }
        }
    }

    /// Adds a new surface to be managed in the current workspace and brings it into focus.
    func manage(surface: Surface) {
        let workspace = self.viewSet.current.workspace
        if let stack = workspace.stack {
            workspace.stack = stack.insert(surface)
        } else {
            workspace.stack = Stack(up: .empty, focus: surface, down: .empty)
        }
        self.updateLayout()
        self.focusTop()
    }

    func updateLayout() {
        for output in self.viewSet.outputs() {
            if let stack = output.workspace.stack {
                var width: Int32 = 0
                var height: Int32 = 0
                wlr_output_effective_resolution(output.output, &width, &height)
                let outputBox = wlr_box(x: 0, y: 0, width: width, height: height)

                let arrangement = output.workspace.layout.doLayout(stack: stack, box: outputBox)
                for (surface, box) in arrangement {
                    switch surface {
                    case .xdg(let xdgSurface):
                        wlr_xdg_toplevel_set_size(xdgSurface, UInt32(box.width), UInt32(box.height))
                    case .xwayland(let xwaylandSurface):
                        wlr_xwayland_surface_configure(
                            xwaylandSurface,
                            Int16(outputBox.x + box.x),
                            Int16(outputBox.y + box.y),
                            UInt16(box.width),
                            UInt16(box.height)
                        )
                    }
                }
                output.arrangement = arrangement
            } else {
                output.arrangement = []
            }
        }
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

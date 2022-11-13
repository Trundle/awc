import DataStructures
import Libawc
import Wlroots

extension Awc {
    /// Focuses the top window (if there is one)
    func focusTop() {
        self.focus(focus: self.viewSet.current.workspace.stack?.focus)
    }

    func focus(focus: Surface?) {
        if let wlrSurface = focus?.wlrSurface, let exclusiveClient = self.exclusiveClient {
            guard wl_resource_get_client(wlrSurface.pointee.resource) == exclusiveClient else {
                return
            }
        }

        if let prevSurface = self.seat.pointee.keyboard_state.focused_surface {
            guard prevSurface != focus?.wlrSurface else {
                return
            }
            if wlr_surface_is_xdg_surface(prevSurface) {
                let prevXdgSurface = wlr_xdg_surface_from_wlr_surface(prevSurface)!
                wlr_xdg_toplevel_set_activated(prevXdgSurface.pointee.toplevel, false)
            } else if wlr_surface_is_xwayland_surface(prevSurface) {
                if case .xwayland = focus {} else {
                    let prevXWaylandSurface = wlr_xwayland_surface_from_wlr_surface(prevSurface)!
                    wlr_xwayland_surface_activate(prevXWaylandSurface, false)
                }
            }
        }

        // Activate the new surface
        if let focus = focus {
            switch focus {
            case .layer(_):
                // XXX what to do here?
                ()
            case .xdg(let surface): wlr_xdg_toplevel_set_activated(surface.pointee.toplevel, true)
            case .xwayland(let surface):
                wlr_xwayland_surface_activate(surface, true)
                wlr_xwayland_surface_restack(surface, nil, XCB_STACK_MODE_ABOVE)
                if let xwayland: UnsafeMutablePointer<wlr_xwayland> = self.getExtensionData() {
                    wlr_xwayland_set_seat(xwayland, self.seat)
                }
            }
            // Tell the seat to have the keyboard enter this surface. wlroots will keep
            // track of this and automatically send key events to the appropriate
            // clients without additional work on your part.
            if let keyboard = wlr_seat_get_keyboard(self.seat) {
                withUnsafeMutablePointer(to: &keyboard.pointee.keycodes.0) { keycodesPtr in
                    wlr_seat_keyboard_notify_enter(
                            self.seat,
                            focus.wlrSurface,
                            keycodesPtr,
                            keyboard.pointee.num_keycodes,
                            &keyboard.pointee.modifiers)
                }
            } else {
                wlr_seat_keyboard_notify_enter(self.seat, focus.wlrSurface, nil, 0, nil)
            }
        } else {
            // There is no new surface -take away keyboard focus from previous surface
            wlr_seat_keyboard_clear_focus(self.seat)
        }
    }

    /// Modifies the view set with given function and then updates.
    func modifyAndUpdate(_ f: (ViewSet<L, Surface>) -> ViewSet<L, Surface>) {
        self.viewSet = f(self.viewSet)
        self.updateLayout()
        self.focusTop()
    }

    /// Adds a new surface to be managed in the current workspace and brings it into focus.
    func manage(surface: Surface) {
        let wantsFloating = surface.wantsFloating(awc: self) || self.shouldFloat(surface: surface)
        if !wantsFloating {
            surface.setTiled()
        }
        self.modifyAndUpdate {
            var viewSet = $0.modifyOr(default: Stack.singleton(surface), { $0.insert(surface) })
            if wantsFloating {
                let floatingBox = surface.preferredFloatingBox(awc: self, output: self.viewSet.current)
                viewSet = viewSet.float(view: surface, box: floatingBox)
            }
            return viewSet
        }
    }

    func updateLayout() {
        for tree in self.sceneTrees.values {
            wlr_scene_node_set_enabled(&tree.pointee.node, false)
        }

        for output in self.viewSet.outputs() {
            let outputLayoutBox = output.data.box
            let outputBox =
                wlr_box(x: 0, y: 0, width: outputLayoutBox.width, height: outputLayoutBox.height)

            if let stack = output.workspace.stack?.filter({ !self.viewSet.floating.contains(key: $0) }) {
                let arrangement = output.workspace.layout
                    .doLayout(dataProvider: self, output: output, stack: stack, box: outputBox)
                    .filter { $0.2.width > 0 && $0.2.height > 0 }
                for (surface, _, box) in arrangement.reversed() {
                    surface.configure(output: outputLayoutBox, box: box)
                    if let tree = self.sceneTrees[surface] {
                        wlr_scene_node_reparent(&tree.pointee.node, self.sceneLayers.tiling)
                        wlr_scene_node_lower_to_bottom(&tree.pointee.node)
                        wlr_scene_node_set_enabled(&tree.pointee.node, true)
                        wlr_scene_node_set_position(&tree.pointee.node, outputLayoutBox.x + box.x, outputLayoutBox.y + box.y)
                    }
                }
                output.arrangement = arrangement
            } else {
                output.arrangement =
                    output.workspace.layout.emptyLayout(dataProvider: self, output: output, box: outputBox)
            }

            // Add floating windows
            if let stack = output.workspace.stack {
                for surface in stack.reverse().toList() {
                    if let box = self.viewSet.floating[surface] {
                        surface.configure(output: outputLayoutBox, box: box)

                        if let tree = self.sceneTrees[surface] {
                            wlr_scene_node_reparent(&tree.pointee.node, self.sceneLayers.floating)
                            wlr_scene_node_raise_to_top(&tree.pointee.node)
                            wlr_scene_node_set_enabled(&tree.pointee.node, true)
                            wlr_scene_node_set_position(&tree.pointee.node, outputLayoutBox.x + box.x, outputLayoutBox.y + box.y)
                        }
                    }
                }
            }
        }
    }

    /// Kills the currently focused surface.
    func kill() {
        self.withFocused {
            switch $0 {
            case .layer: /* layers cannot be closed */ ()
            case .xdg(let surface): wlr_xdg_toplevel_send_close(surface.pointee.toplevel)
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
    func orderedOutputs() -> [Output<L>] {
        self.viewSet.outputs().sorted(by: { $0.data.box.x <= $1.data.box.x })
    }
}

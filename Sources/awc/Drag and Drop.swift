import Wlroots

protocol DragIconHandler: class {
    func commit(icon: UnsafeMutablePointer<wlr_drag_icon>)
    func destroy(icon: UnsafeMutablePointer<wlr_drag_icon>)
    func map(icon: UnsafeMutablePointer<wlr_drag_icon>)
    func unmap(icon: UnsafeMutablePointer<wlr_drag_icon>)
}

struct DragIconListener: PListener {
    weak var handler: DragIconHandler?
    private var commit: wl_listener = wl_listener()
    private var destroy: wl_listener = wl_listener()
    private var map: wl_listener = wl_listener()
    private var unmap: wl_listener = wl_listener()

    internal mutating func listen(to icon: UnsafeMutablePointer<wlr_drag_icon>) {
        Self.add(signal: &icon.pointee.surface.pointee.events.commit, listener: &self.commit) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.commit,
                { (handler, surface: UnsafeMutablePointer<wlr_surface>) in
                    if let icon = surface.pointee.data {
                        handler.commit(icon: icon.bindMemory(to: wlr_drag_icon.self, capacity: 1))
                    }
                }
            )
        }

        Self.add(signal: &icon.pointee.events.destroy, listener: &self.destroy) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.destroy, { $0.destroy(icon: $1) })
        }

        Self.add(signal: &icon.pointee.events.map, listener: &self.map) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.map, { $0.map(icon: $1) })
        }

        Self.add(signal: &icon.pointee.events.unmap, listener: &self.unmap) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.unmap, { $0.unmap(icon: $1) })
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.commit.link)
        wl_list_remove(&self.destroy.link)
        wl_list_remove(&self.map.link)
        wl_list_remove(&self.unmap.link)
    }
}

extension Awc {
    func handleNewDrag(icon: UnsafeMutablePointer<wlr_drag_icon>) {
        icon.pointee.surface.pointee.data = UnsafeMutableRawPointer(icon)
        self.addListener(icon, DragIconListener.newFor(emitter: icon, handler: self))
    }
}

extension Awc: DragIconHandler {
    internal func commit(icon: UnsafeMutablePointer<wlr_drag_icon>) {
        updatePosition(icon: icon)
    }

    internal func destroy(icon: UnsafeMutablePointer<wlr_drag_icon>) {
        self.removeListener(icon, DragIconListener.self)
    }

    internal func map(icon: UnsafeMutablePointer<wlr_drag_icon>) {
        updatePosition(icon: icon)
    }

    internal func unmap(icon: UnsafeMutablePointer<wlr_drag_icon>) {
        self.surfaces.removeValue(forKey: icon.pointee.surface)
    }

    internal func updatePosition(icon: UnsafeMutablePointer<wlr_drag_icon>) {
        var x: Double = 0
        var y: Double = 0

        switch icon.pointee.drag.pointee.grab_type {
        case WLR_DRAG_GRAB_KEYBOARD_POINTER:
            x = self.cursor.pointee.x
            y = self.cursor.pointee.y
        case WLR_DRAG_GRAB_KEYBOARD_TOUCH:
            // XXX implement me
            return
        default: return
        }

        self.surfaces[icon.pointee.surface] = (x, y)

        damage(icon: icon, x: x, y: y)
    }

    private func damage(icon: UnsafeMutablePointer<wlr_drag_icon>, x: Double, y: Double) {
        if let wlrOutput = wlr_output_layout_output_at(self.outputLayout, x, y),
           let output = self.viewSet.outputs().first(where: { $0.data.output == wlrOutput })
        {
            var box = wlr_box(
                x: Int32(x),
                y: Int32(y),
                width: icon.pointee.surface.pointee.current.width,
                height: icon.pointee.surface.pointee.current.height
            )
            wlr_output_damage_add_box(output.data.damage, &box)
        }
    }
}

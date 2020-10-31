import Wlroots

protocol XdgShell: class {
    func newSurface(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>)
}

protocol XdgSurface: class {
    func surfaceDestroyed(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>)
    func map(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>)
    func unmap(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>)
}

protocol XdgMappedSurface: class {
    func newPopup(popup: UnsafeMutablePointer<wlr_xdg_popup>)
}

/// Signal listeners for XDG Shell.
struct XdgShellListener: PListener {
    weak var handler: XdgShell?
    private var newSurface: wl_listener = wl_listener()

    internal mutating func listen(to xdgShell: UnsafeMutablePointer<wlr_xdg_shell>) {
        Self.add(signal: &xdgShell.pointee.events.new_surface, listener: &self.newSurface) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.newSurface, { $0.newSurface(xdgSurface: $1) } )
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.newSurface.link)
    }
}

/// Signal listeners for an XDG surface.
struct XdgSurfaceListener: PListener {
    weak var handler: XdgSurface?
    private var destroy: wl_listener = wl_listener()
    private var map: wl_listener = wl_listener()
    private var unmap: wl_listener = wl_listener()

    internal mutating func listen(to surface: UnsafeMutablePointer<wlr_xdg_surface>) {
        Self.add(signal: &surface.pointee.events.destroy, listener: &self.destroy) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.destroy, { $0.surfaceDestroyed(xdgSurface: $1) })
        }

        Self.add(signal: &surface.pointee.events.map, listener: &self.map) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.map, { $0.map(xdgSurface: $1) })
        }

        Self.add(signal: &surface.pointee.events.unmap, listener: &self.unmap) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.unmap, { $0.unmap(xdgSurface: $1) })
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.destroy.link)
        wl_list_remove(&self.map.link)
        wl_list_remove(&self.unmap.link)
    }
}

/// Signal listeners for a mapped XDG surface.
struct XdgMappedSurfaceListener: PListener {
    weak var handler: XdgMappedSurface?
    private var newPopup: wl_listener = wl_listener()

    mutating func listen(to surface: UnsafeMutablePointer<wlr_xdg_surface>) {
        Self.add(signal: &surface.pointee.events.new_popup, listener: &self.newPopup) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.newPopup, { $0.newPopup(popup: $1) })
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.newPopup.link)
    }
}

extension Awc: XdgShell {
    func newSurface(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>) {
        // XXX does it require additional checks?
        guard xdgSurface.pointee.role == WLR_XDG_SURFACE_ROLE_TOPLEVEL else {
            return
        }
        self.unmapped.insert(Surface.xdg(surface: xdgSurface))

        self.addListener(xdgSurface, XdgSurfaceListener.newFor(emitter: xdgSurface, handler: self))

        // XXX add toplevel listeners
        wlr_xdg_surface_ping(xdgSurface)
    }
}

extension Awc: XdgSurface {
    internal func map(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>) {
        let surface = Surface.xdg(surface: xdgSurface)
        if self.unmapped.remove(surface) != nil {
            self.addListener(xdgSurface, XdgMappedSurfaceListener.newFor(emitter: xdgSurface, handler: self))
            self.manage(surface: surface)
        }
    }

    internal func unmap(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>) {
        self.removeListener(xdgSurface, XdgMappedSurfaceListener.self)
        self.handleUnmap(surface: Surface.xdg(surface: xdgSurface))
    }

    internal func surfaceDestroyed(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>) {
        self.removeListener(xdgSurface, XdgSurfaceListener.self)
        self.unmapped.remove(Surface.xdg(surface: xdgSurface))
    }
}

extension Awc: XdgMappedSurface {
    func newPopup(popup: UnsafeMutablePointer<wlr_xdg_popup>) {
        // XXX
        print("[DEBUG] New popup, but popups not implemented yet!")
    }
}

// Set up our list of views and the xdg-shell. The xdg-shell is a Wayland
// protocol which is used for application windows.
func setUpXdgShell<L: Layout>(display: OpaquePointer, awc: Awc<L>) {
    guard let xdg_shell = wlr_xdg_shell_create(display) else {
        print("[ERROR] Could not create XDG Shell")
        return
    }

    awc.addListener(xdg_shell, XdgShellListener.newFor(emitter: xdg_shell, handler: awc))
}

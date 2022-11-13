import Libawc
import Wlroots

protocol XdgShell: AnyObject {
    func newSurface(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>)
}

protocol XdgSurface: AnyObject {
    func surfaceDestroyed(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>)
    func map(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>)
    func unmap(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>)
}

protocol XdgMappedSurface: AnyObject {
    func commit(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>)
    func newPopup(popup: UnsafeMutablePointer<wlr_xdg_popup>)
    func requestFullscreen(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>)
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
    private var surface: UnsafeMutablePointer<wlr_xdg_surface>!
    private var destroy: wl_listener = wl_listener()
    private var map: wl_listener = wl_listener()
    private var unmap: wl_listener = wl_listener()

    internal mutating func listen(to surface: UnsafeMutablePointer<wlr_xdg_surface>) {
        self.surface = surface

        Self.add(signal: &surface.pointee.events.destroy, listener: &self.destroy) { (listener, data) in
            Self.handle(from: listener!, data: \Self.surface, \Self.destroy, { $0.surfaceDestroyed(xdgSurface: $1) })
        }

        Self.add(signal: &surface.pointee.events.map, listener: &self.map) { (listener, data) in
            Self.handle(from: listener!, data: \Self.surface, \Self.map, { $0.map(xdgSurface: $1) })
        }

        Self.add(signal: &surface.pointee.events.unmap, listener: &self.unmap) { (listener, data) in
            Self.handle(from: listener!, data: \Self.surface, \Self.unmap, { $0.unmap(xdgSurface: $1) })
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
    // XXX required?
    private var surface: UnsafeMutablePointer<wlr_xdg_surface>! = nil
    private var commit: wl_listener = wl_listener()
    private var newPopup: wl_listener = wl_listener()
    private var requestFullscreen: wl_listener = wl_listener()

    mutating func listen(to surface: UnsafeMutablePointer<wlr_xdg_surface>) {
        self.surface = surface

        Self.add(signal: &surface.pointee.surface.pointee.events.commit, listener: &self.commit) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.commit,
                { (handler, surface: UnsafeMutablePointer<wlr_surface>) in
                    if let xdgSurface = wlr_xdg_surface_from_wlr_surface(surface) {
                        handler.commit(xdgSurface: xdgSurface)
                    }
                }
            )
        }

        Self.add(signal: &surface.pointee.events.new_popup, listener: &self.newPopup) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.newPopup, { $0.newPopup(popup: $1) })
        }

        assert(surface.pointee.role == WLR_XDG_SURFACE_ROLE_TOPLEVEL)
        Self.add(signal: &surface.pointee.toplevel.pointee.events.request_fullscreen, listener: &self.requestFullscreen) {
            (wlListener, _) in
            let listenerPtr: UnsafeMutablePointer<Self> = wlContainer(of: wlListener!, \Self.requestFullscreen)
            if let handler = listenerPtr.pointee.handler {
                handler.requestFullscreen(xdgSurface: listenerPtr.pointee.surface)
            }
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.commit.link)
        wl_list_remove(&self.newPopup.link)
        wl_list_remove(&self.requestFullscreen.link)
    }
}

extension Awc: XdgShell {
    func newSurface(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>) {
        guard xdgSurface.pointee.role == WLR_XDG_SURFACE_ROLE_TOPLEVEL else {
            return
        }

        let surface = Surface.xdg(surface: xdgSurface)
        self.unmapped.insert(surface)
        self.addListener(xdgSurface, XdgSurfaceListener.newFor(emitter: xdgSurface, handler: self))

        guard let sceneTree = wlr_scene_xdg_surface_create(self.sceneLayers.tiling, xdgSurface) else {
            wl_resource_post_no_memory(xdgSurface.pointee.resource)
            return
        }
        surface.store(sceneTree: sceneTree)
        self.sceneTrees[surface] = sceneTree

        // XXX add toplevel listeners
        wlr_xdg_surface_ping(xdgSurface)
    }

    fileprivate func unconstrain(popup: UnsafeMutablePointer<wlr_xdg_popup>) {
        // XXX don't rely on arrangement
        if let parentWlrSurface = popup.pointee.parent,
           let parentXdgSurface = wlr_xdg_surface_from_wlr_surface(parentWlrSurface)
        {
            let parentSurface =  Surface.xdg(surface: parentXdgSurface)
            if let output = self.viewSet.findOutput(view: parentSurface),
               let (_, _, parentBox) = output.arrangement.first(where: { $0.0 == parentSurface })
            {
                var constraintBox = wlr_box(
                    x: -parentBox.x,
                    y: -parentBox.y,
                    width: parentBox.width + parentBox.x,
                    height: parentBox.height + parentBox.y)
                wlr_xdg_popup_unconstrain_from_box(popup, &constraintBox)
            }
        }
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
        let surface = Surface.xdg(surface: xdgSurface)
        self.unmapped.remove(surface)
        self.xdgGeometries.removeValue(forKey: surface)
        self.sceneTrees.removeValue(forKey: surface)
    }
}

extension Awc: XdgMappedSurface {
    internal func commit(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>) {
        let surface = Surface.xdg(surface: xdgSurface)
        var box = wlr_box()
        wlr_xdg_surface_get_geometry(xdgSurface, &box)
        self.xdgGeometries[surface] = box
    }

    internal func newPopup(popup: UnsafeMutablePointer<wlr_xdg_popup>) {
        let parent = wlr_xdg_surface_from_wlr_surface(popup.pointee.parent)
        if let parentTree = self.sceneTrees[Surface.xdg(surface: parent!)] {
            let xdgSurface = popup.pointee.base!
            if wlr_scene_xdg_surface_create(parentTree, xdgSurface) == nil {
                wl_resource_post_no_memory(xdgSurface.pointee.resource)
            }
        }
        self.unconstrain(popup: popup)
    }

    internal func requestFullscreen(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>) {
        let toplevel = xdgSurface.pointee.toplevel!
        wlr_xdg_toplevel_set_fullscreen(toplevel, toplevel.pointee.requested.fullscreen)
    }
}

// Set up our list of views and the xdg-shell. The xdg-shell is a Wayland
// protocol which is used for application windows.
func setUpXdgShell<L: Layout>(display: OpaquePointer, awc: Awc<L>) {
    guard let xdg_shell = wlr_xdg_shell_create(display, 3) else {
        fatalError("Could not create XDG Shell")
    }

    awc.addListener(xdg_shell, XdgShellListener.newFor(emitter: xdg_shell, handler: awc))
}

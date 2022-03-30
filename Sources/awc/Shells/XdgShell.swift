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
    func newSubsurface(subsurface: UnsafeMutablePointer<wlr_subsurface>)
}

protocol XdgPopup: AnyObject {
    func commit(popupSurface: UnsafeMutablePointer<wlr_xdg_surface>)
    func destroy(popupSurface: UnsafeMutablePointer<wlr_xdg_surface>)
    func map(popupSurface: UnsafeMutablePointer<wlr_xdg_surface>)
    func newSubsurface(subsurface: UnsafeMutablePointer<wlr_subsurface>)
    func unmap(popupSurface: UnsafeMutablePointer<wlr_xdg_surface>)
}

protocol Subsurface: AnyObject {
    func commit(subsurface: UnsafeMutablePointer<wlr_subsurface>)
    func destroy(subsurface: UnsafeMutablePointer<wlr_subsurface>)
    func newSubsurface(subsurface: UnsafeMutablePointer<wlr_subsurface>)
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
    private var commit: wl_listener = wl_listener()
    private var newPopup: wl_listener = wl_listener()
    private var newSubsurface: wl_listener = wl_listener()

    mutating func listen(to surface: UnsafeMutablePointer<wlr_xdg_surface>) {
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

        Self.add(signal: &surface.pointee.surface.pointee.events.new_subsurface, listener: &self.newSubsurface) {
            (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.newSubsurface, { $0.newSubsurface(subsurface: $1) })
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.commit.link)
        wl_list_remove(&self.newPopup.link)
        wl_list_remove(&self.newSubsurface.link)
    }
}

struct XdgPopupListener: PListener {
    weak var handler: XdgPopup?
    private var commit: wl_listener = wl_listener()
    private var destroy: wl_listener = wl_listener()
    private var map: wl_listener = wl_listener()
    private var newSubsurface: wl_listener = wl_listener()
    private var unmap: wl_listener = wl_listener()

    mutating func listen(to popup: UnsafeMutablePointer<wlr_xdg_popup>) {
        Self.add(signal: &popup.pointee.base.pointee.surface.pointee.events.commit, listener: &self.commit) {
            (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.commit,
                { (handler, surface: UnsafeMutablePointer<wlr_surface>) in
                    if let xdgSurface = wlr_xdg_surface_from_wlr_surface(surface) {
                        handler.commit(popupSurface: xdgSurface)
                    }
                }
            )
        }

        Self.add(signal: &popup.pointee.base.pointee.events.destroy, listener: &self.destroy) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.destroy, { $0.destroy(popupSurface: $1) })
        }

        Self.add(signal: &popup.pointee.base.pointee.events.map, listener: &self.map) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.map, { $0.map(popupSurface: $1) })
        }

        Self.add(signal: &popup.pointee.base.pointee.surface.pointee.events.new_subsurface, listener: &self.newSubsurface) {
            (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.newSubsurface, { $0.newSubsurface(subsurface: $1) })
        }

        Self.add(signal: &popup.pointee.base.pointee.events.unmap, listener: &self.unmap) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.unmap, { $0.unmap(popupSurface: $1) })
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.commit.link)
        wl_list_remove(&self.destroy.link)
        wl_list_remove(&self.map.link)
        wl_list_remove(&self.newSubsurface.link)
        wl_list_remove(&self.unmap.link)
    }
}

struct SubsurfaceListener: PListener {
    weak var handler: Subsurface?
    private var commit: wl_listener = wl_listener()
    private var destroy: wl_listener = wl_listener()
    private var newSubsurface: wl_listener = wl_listener()

    mutating func listen(to subsurface: UnsafeMutablePointer<wlr_subsurface>) {
        Self.add(signal: &subsurface.pointee.surface.pointee.events.commit, listener: &self.commit) {
            (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.commit,
                { (handler, surface: UnsafeMutablePointer<wlr_surface>) in
                    if let subsurface = wlr_subsurface_from_wlr_surface(surface) {
                        handler.commit(subsurface: subsurface)
                    }
                }
            )
        }

        Self.add(signal: &subsurface.pointee.events.destroy, listener: &self.destroy) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.destroy, { $0.destroy(subsurface: $1) })
        }

        Self.add(signal: &subsurface.pointee.surface.pointee.events.new_subsurface, listener: &self.newSubsurface) {
            (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.newSubsurface, { $0.newSubsurface(subsurface: $1) })
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.commit.link)
        wl_list_remove(&self.destroy.link)
        wl_list_remove(&self.newSubsurface.link)
    }
}

extension Awc {
    fileprivate func damageWlrSurface(parent: Surface, wlrSurface: UnsafeMutablePointer<wlr_surface>, sx: Int32, sy: Int32) {
        guard let output = self.viewSet.findOutput(view: parent) else {
            return
        }
        guard let box = output.arrangement.first(where: { $0.0 == parent})?.2 else {
            return
        }

        var damage = pixman_region32_t()
        pixman_region32_init(&damage)
        defer {
            pixman_region32_fini(&damage)
        }

        wlr_surface_get_effective_damage(wlrSurface, &damage)
        pixman_region32_translate(&damage, box.x + sx, box.y + sy)
        wlr_output_damage_add(output.data.damage, &damage)
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

            if let wlrSurface = xdgSurface.pointee.surface {
                for subsurface in wlrSurface.pointee.subsurfaces_above.sequence(\wlr_subsurface.parent_link) {
                    newSubsurface(subsurface: subsurface)
                }
                for subsurface in wlrSurface.pointee.subsurfaces_below.sequence(\wlr_subsurface.parent_link) {
                    newSubsurface(subsurface: subsurface)
                }
            }

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
    internal func commit(xdgSurface: UnsafeMutablePointer<wlr_xdg_surface>) {
        let surface = Surface.xdg(surface: xdgSurface)
        self.damageWlrSurface(parent: surface, wlrSurface: surface.wlrSurface, sx: 0, sy: 0)
    }

    func newPopup(popup: UnsafeMutablePointer<wlr_xdg_popup>) {
        self.addListener(popup.pointee.base, XdgPopupListener.newFor(emitter: popup, handler: self))

        if let parentWlrSurface = popup.pointee.parent,
           let parentXdgSurface = wlr_xdg_surface_from_wlr_surface(parentWlrSurface)
        {
            let parentSurface =  Surface.xdg(surface: parentXdgSurface)
            if let output = self.viewSet.findOutput(view: parentSurface),
               let (_, _, parentBox) = output.arrangement.first(where: { $0.0 == parentSurface })
            {
                let outputBox = output.data.box
                var constraintBox = wlr_box(
                    x: -parentBox.x, 
                    y: -parentBox.y,
                    width: outputBox.width,
                    height: outputBox.height)
                wlr_xdg_popup_unconstrain_from_box(popup, &constraintBox)
            }
        }
    }

    func newSubsurface(subsurface: UnsafeMutablePointer<wlr_subsurface>) {
        self.addListener(subsurface, SubsurfaceListener.newFor(emitter: subsurface, handler: self))

        if let wlrSurface = subsurface.pointee.surface {
            for childSubsurface in wlrSurface.pointee.subsurfaces_above.sequence(\wlr_subsurface.parent_link) {
                newSubsurface(subsurface: childSubsurface)
            }
            for childSubsurface in wlrSurface.pointee.subsurfaces_below.sequence(\wlr_subsurface.parent_link) {
                newSubsurface(subsurface: childSubsurface)
            }
        }
    }
}

extension Awc: XdgPopup {
    internal func commit(popupSurface: UnsafeMutablePointer<wlr_xdg_surface>) {
        if let popup = popupSurface.pointee.popup,
           let parentSurface = popup.pointee.parent,
           let parentXdgSurface = wlr_xdg_surface_from_wlr_surface(parentSurface)
        {
            let parentSurface = Surface.xdg(surface: parentXdgSurface)
            self.damageWlrSurface(
                parent: parentSurface,
                wlrSurface: popupSurface.pointee.surface,
                sx: popup.pointee.geometry.x,
                sy: popup.pointee.geometry.y
            )
        }
    }

    internal func destroy(popupSurface: UnsafeMutablePointer<wlr_xdg_surface>) {
        self.removeListener(popupSurface, XdgPopupListener.self)
    }

    internal func map(popupSurface: UnsafeMutablePointer<wlr_xdg_surface>) {
        self.damageWholePopup(popupSurface: popupSurface)
    }

    internal func unmap(popupSurface: UnsafeMutablePointer<wlr_xdg_surface>) {
        self.damageWholePopup(popupSurface: popupSurface)
    }

    private func damageWholePopup(popupSurface: UnsafeMutablePointer<wlr_xdg_surface>) {
        if let popup = popupSurface.pointee.popup,
           let parentSurface = popup.pointee.parent,
           let parentXdgSurface = wlr_xdg_surface_from_wlr_surface(parentSurface)
        {
            let surface = Surface.xdg(surface: parentXdgSurface)
            if let output = self.viewSet.findOutput(view: surface),
               let outputBox = output.arrangement.first(where: { $0.0 == surface})?.2
            {
                var box = popup.pointee.geometry
                box.x += outputBox.x
                box.y += outputBox.y
                wlr_output_damage_add_box(output.data.damage, &box)
            }
        }
    }
}


extension Awc: Subsurface {
    func commit(subsurface: UnsafeMutablePointer<wlr_subsurface>) {
        if let parentXdgSurface = subsurface.parentToplevel() {
            let parentSurface = Surface.xdg(surface: parentXdgSurface)
            if let (_, sx, sy) = parentSurface.surfaces().first(where: { $0.0 == subsurface.pointee.surface }) {
                self.damageWlrSurface(parent: parentSurface, wlrSurface: subsurface.pointee.surface, sx: sx, sy: sy)
            }
        }
    }

    func destroy(subsurface: UnsafeMutablePointer<wlr_subsurface>) {
        self.removeListener(subsurface, SubsurfaceListener.self)
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

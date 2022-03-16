import Glibc
import Libawc
import Wlroots

/// Atoms describing the functional type of a window, as set by the client.
///
/// See also https://specifications.freedesktop.org/wm-spec/1.4/ar01s05.html
enum AtomWindowType: String, CaseIterable {
    /// The window is popped up by a combo box (e.g. completions window in a text field)
    case combo = "_NET_WM_WINDOW_TYPE_COMBO"
    case dialog = "_NET_WM_WINDOW_TYPE_DIALOG"
    case dropdownMenu = "_NET_WM_WINDOW_TYPE_DROPDOWN_MENU"
    case menu = "_NET_WM_WINDOW_TYPE_MENU"
    case normal = "_NET_WM_WINDOW_TYPE_NORMAL"
    case notification = "_NET_WM_WINDOW_TYPE_NOTIFICATION"
    case popupMenu = "_NET_WM_WINDOW_TYPE_POPUP_MENU"
    /// The window is a "splash screen" (a window displayed on application startup)
    case splash = "_NET_WM_WINDOW_TYPE_SPLASH"
    case toolbar = "_NET_WM_WINDOW_TYPE_TOOLBAR"
    case tooltip = "_NET_WM_WINDOW_TYPE_TOOLTIP"

    /// A small persistent utility window, such as a palette or toolbox. It is distinct from type
    /// .toolbar because it does not correspond to a toolbar torn off from the main application.
    /// It's distinect from type DIALOG because it isn't a transient dialog, the user will
    /// probably keep it open while they're working.
    case utility = "_NET_WM_WINDOW_TYPE_UTILITY"
}

protocol XWayland: AnyObject {
    func xwaylandReady()
    func newSurface(xwaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>)
}

protocol XWaylandSurface: AnyObject{
    func configureRequest(event: UnsafeMutablePointer<wlr_xwayland_surface_configure_event>)
    func surfaceDestroyed(xwaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>)
    func map(xwaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>)
    func unmap(xwaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>)
}

protocol XWaylandMappedSurface: AnyObject {
    func commit(xwaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>)
}

private struct XWaylandListener: PListener {
    weak var handler: XWayland?
    private var newSurface: wl_listener = wl_listener()
    private var ready: wl_listener = wl_listener()

    internal mutating func listen(to xwayland: UnsafeMutablePointer<wlr_xwayland>) {
        Self.add(signal: &xwayland.pointee.events.ready, listener: &self.ready) { (listener, data) in
            let listenersPtr = wlContainer(of: listener!, \Self.ready)
            listenersPtr.pointee.handler?.xwaylandReady()
        }

        Self.add(signal: &xwayland.pointee.events.new_surface, listener: &self.newSurface) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.newSurface, { $0.newSurface(xwaylandSurface: $1) })
        }
    }

    internal mutating func deregister() {
        wl_list_remove(&self.newSurface.link)
        wl_list_remove(&self.ready.link)
    }
}

/// Signal listeners for an XWayland surface.
private struct XWaylandSurfaceListener: PListener {
    weak var handler: XWaylandSurface?
    private var configureRequest: wl_listener = wl_listener()
    private var destroy: wl_listener = wl_listener()
    private var map: wl_listener = wl_listener()
    private var unmap: wl_listener = wl_listener()

    internal mutating func listen(to surface: UnsafeMutablePointer<wlr_xwayland_surface>) {
        Self.add(
            signal: &surface.pointee.events.request_configure,
            listener: &self.configureRequest
        ) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.configureRequest, { $0.configureRequest(event: $1) })
        }

        Self.add(
            signal: &surface.pointee.events.destroy,
            listener: &self.destroy
        ) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.destroy, { $0.surfaceDestroyed(xwaylandSurface: $1) }
            )
        }

        Self.add(signal: &surface.pointee.events.map, listener: &self.map) { (listener, data) in
            Self.handle(from: listener!, data: data!, \XWaylandSurfaceListener.map, { $0.map(xwaylandSurface: $1) })
        }

        Self.add(signal: &surface.pointee.events.unmap, listener: &self.unmap) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.unmap, { $0.unmap(xwaylandSurface: $1) })
        }
    }

    mutating func deregister() {
        wl_list_remove(&configureRequest.link)
        wl_list_remove(&destroy.link)
        wl_list_remove(&map.link)
        wl_list_remove(&unmap.link)
    }
}

private struct XWaylandMappedSurfaceListener: PListener {
    weak var handler: XWaylandMappedSurface?
    private var commit: wl_listener = wl_listener()

    mutating func listen(to surface: UnsafeMutablePointer<wlr_xwayland_surface>) {
        Self.add(signal: &surface.pointee.surface.pointee.events.commit, listener: &self.commit) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.commit,
                { (handler, surface: UnsafeMutablePointer<wlr_surface>) in
                    if let xwaylandSurface = wlr_xwayland_surface_from_wlr_surface(surface) {
                        handler.commit(xwaylandSurface: xwaylandSurface)
                    }
                }
            )
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.commit.link)
    }
}

extension Awc: XWayland {
    // Called when XWayland is ready. Retrieves the X atoms (e.g. window types etc).
    internal func xwaylandReady() {
        let xcbConn = xcb_connect(nil, nil)
        let err = xcb_connection_has_error(xcbConn)
        guard err == 0 else {
            print("[ERROR] XBC connect failed: \(err)")
            return
        }
        defer {
            xcb_disconnect(xcbConn)
        }

        let cookies = UnsafeMutableBufferPointer<xcb_intern_atom_cookie_t>
            .allocate(capacity: AtomWindowType.allCases.count)
        for (i, type) in AtomWindowType.allCases.enumerated() {
            type.rawValue.withCString {
                cookies[i] = xcb_intern_atom(xcbConn, 0, UInt16(type.rawValue.count), $0)
            }
        }
        for (i, type) in AtomWindowType.allCases.enumerated() {
            let error = UnsafeMutablePointer<UnsafeMutablePointer<xcb_generic_error_t>?>.allocate(capacity: 1)
            defer {
                error.deallocate()
            }
            if let reply = xcb_intern_atom_reply(xcbConn, cookies[i], error) {
                defer {
                    free(reply)
                }
                if error.pointee == nil {
                    self.windowTypeAtoms[reply.pointee.atom] = type
                } else {
                    print("[ERROR] X11 error \(String(describing: error.pointee?.pointee.error_code)) when " +
                            "trying to resolve X11 atom \(type)")
                    free(error)
                }
            }
        }
    }

    internal func newSurface(xwaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>) {
        wlr_xwayland_surface_ping(xwaylandSurface)
        self.unmapped.insert(Surface.xwayland(surface: xwaylandSurface))
        self.addListener(xwaylandSurface, XWaylandSurfaceListener.newFor(emitter: xwaylandSurface, handler: self))
    }
}

extension Awc: XWaylandSurface {
    internal func surfaceDestroyed(xwaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>) {
        self.removeListener(xwaylandSurface, XWaylandSurfaceListener.self)
        self.unmapped.remove(Surface.xwayland(surface: xwaylandSurface))
    }

    internal func configureRequest(event: UnsafeMutablePointer<wlr_xwayland_surface_configure_event>) {
        // Allow configure request if it's a floating surface (so likely a menu or popup) or an unmapped surface
        let surface = Surface.xwayland(surface: event.pointee.surface)
        let floating = self.viewSet.floating.contains(key: surface)
        if floating || self.unmapped.contains(surface) {
            wlr_xwayland_surface_configure(
                event.pointee.surface, event.pointee.x, event.pointee.y, event.pointee.width, event.pointee.height
            )
            if floating {
                if let output = self.viewSet.findOutput(view: surface) {
                    let outputLayoutBox = output.data.box
                    let newBox = wlr_box(
                        x: Int32(event.pointee.x) - outputLayoutBox.x,
                        y: Int32(event.pointee.y) - outputLayoutBox.y,
                        width: Int32(event.pointee.width), height: Int32(event.pointee.height))
                    self.modifyAndUpdate {
                        $0.replace(floating: $0.floating.updateValue(newBox, forKey: surface))
                    }
                }
            }
        }
    }

    internal func map(xwaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>) {
        let surface = Surface.xwayland(surface: xwaylandSurface)
        if self.unmapped.remove(surface) != nil {
            self.addListener(
                xwaylandSurface,
                XWaylandMappedSurfaceListener.newFor(emitter: xwaylandSurface, handler: self)
            )
            self.manage(surface: surface)
        }
    }

    internal func unmap(xwaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>) {
        self.removeListener(xwaylandSurface, XWaylandMappedSurfaceListener.self)
        handleUnmap(surface: Surface.xwayland(surface: xwaylandSurface))
    }
}

extension Awc: XWaylandMappedSurface {
    internal func commit(xwaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>) {
        let surface = Surface.xwayland(surface: xwaylandSurface)
        guard let output = self.viewSet.findOutput(view: surface) else {
            return
        }
        guard let box = output.arrangement.first(where: { $0.0 == surface})?.2 else {
            return
        }

        if let waylandSurface = xwaylandSurface.pointee.surface {
            let newWidth = waylandSurface.pointee.current.width
            let newHeight = waylandSurface.pointee.current.height
            if (newWidth != box.width || newHeight != box.height)
                && self.viewSet.floating.contains(key: surface)
            {
                let newBox = wlr_box(x: box.x, y: box.y, width: newWidth, height: newHeight)
                self.modifyAndUpdate {
                    $0.replace(floating: $0.floating.updateValue(newBox, forKey: surface))
                }
            }
        }

        var damage = pixman_region32_t()
        pixman_region32_init(&damage)
        defer {
            pixman_region32_fini(&damage)
        }

        wlr_surface_get_effective_damage(xwaylandSurface.pointee.surface, &damage)
        pixman_region32_translate(&damage, box.x, box.y)
        wlr_output_damage_add(output.data.damage, &damage)
    }
}

func setupXWayland<L: Layout>(
    display: OpaquePointer,
    compositor: UnsafeMutablePointer<wlr_compositor>,
    awc: Awc<L>
) {
    guard let xwayland = wlr_xwayland_create(display, compositor, true) else {
        print("[ERROR] Could not create XWayland")
        return
    }
    awc.addExtensionData(xwayland)
    awc.addListener(xwayland, XWaylandListener.newFor(emitter: xwayland, handler: awc))
    setenv("DISPLAY", xwayland.pointee.display_name, 1)
}


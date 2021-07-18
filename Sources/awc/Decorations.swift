import Libawc
import Wlroots

// MARK: Wayland server decorations

protocol ServerDecorations: AnyObject {
    func newDecoration(serverDecoration: UnsafeMutablePointer<wlr_server_decoration>)
}

protocol ServerDecoration: AnyObject {
    func destroy(serverDecoration: UnsafeMutablePointer<wlr_server_decoration>)
    func requestMode(serverDecoration: UnsafeMutablePointer<wlr_server_decoration>)
}

private struct ServerDecorationsListener: PListener {
    weak var handler: ServerDecorations?
    private var newDecoration: wl_listener = wl_listener()

    internal mutating func listen(to decorationManager: UnsafeMutablePointer<wlr_server_decoration_manager>) {
        Self.add(
            signal: &decorationManager.pointee.events.new_decoration,
            listener: &self.newDecoration
        ) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.newDecoration, { $0.newDecoration(serverDecoration: $1) })
        }
    }

    internal mutating func deregister() {
        wl_list_remove(&self.newDecoration.link)
    }
}

private struct ServerDecorationListener: PListener {
    weak var handler: ServerDecoration?
    private var destroy: wl_listener = wl_listener()
    private var mode: wl_listener = wl_listener()

    internal mutating func listen(to deco: UnsafeMutablePointer<wlr_server_decoration>) {
        Self.add(signal: &deco.pointee.events.destroy, listener: &self.destroy) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.destroy, { $0.destroy(serverDecoration: $1) })
        }

        Self.add(signal: &deco.pointee.events.mode, listener: &self.mode) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.mode, { $0.requestMode(serverDecoration: $1) })
        }
    }

    internal mutating func deregister() {
        wl_list_remove(&self.destroy.link)
        wl_list_remove(&self.mode.link)
    }
}

extension Awc: ServerDecorations {
    func newDecoration(serverDecoration: UnsafeMutablePointer<wlr_server_decoration>) {
        self.addListener(serverDecoration, ServerDecorationListener.newFor(emitter: serverDecoration, handler: self))
    }
}

extension Awc: ServerDecoration {
    func destroy(serverDecoration: UnsafeMutablePointer<wlr_server_decoration>) {
        self.removeListener(serverDecoration, ServerDecorationListener.self)
    }

    func requestMode(serverDecoration: UnsafeMutablePointer<wlr_server_decoration>) {
        // XXX what to do if the client requests client-side decorations here?
    }
}

// MARK: XDG Toplevel Decorations

protocol XdgDecorations: AnyObject {
    func newToplevelDecoration(decoration: UnsafeMutablePointer<wlr_xdg_toplevel_decoration_v1>)
}

protocol XdgDecoration: AnyObject {
    func destroy(decoration: UnsafeMutablePointer<wlr_xdg_toplevel_decoration_v1>)
    func requestMode(decoration: UnsafeMutablePointer<wlr_xdg_toplevel_decoration_v1>)
}

struct XdgDecorationsListener: PListener {
    weak var handler: XdgDecorations?
    private var newToplevelDecoration: wl_listener = wl_listener()

    internal mutating func listen(to decorationManager: UnsafeMutablePointer<wlr_xdg_decoration_manager_v1>) {
        Self.add(
            signal: &decorationManager.pointee.events.new_toplevel_decoration,
            listener: &self.newToplevelDecoration
        ) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.newToplevelDecoration, {
                $0.newToplevelDecoration(decoration: $1)
            })
        }
    }

    internal mutating func deregister() {
        wl_list_remove(&self.newToplevelDecoration.link)
    }
}

struct XdgDecorationListener: PListener {
    weak var handler: XdgDecoration?
    private var destroy: wl_listener = wl_listener()
    private var requestMode: wl_listener = wl_listener()

    internal mutating func listen(to decoration: UnsafeMutablePointer<wlr_xdg_toplevel_decoration_v1>) {
        Self.add(signal: &decoration.pointee.events.destroy, listener: &self.destroy) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.destroy, { $0.destroy(decoration: $1) })
        }

        Self.add(signal: &decoration.pointee.events.request_mode, listener: &self.requestMode) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.requestMode, { $0.requestMode(decoration: $1) })
        }
    }

    internal mutating func deregister() {
        wl_list_remove(&self.destroy.link)
    }
}

extension Awc: XdgDecorations {
    func newToplevelDecoration(decoration: UnsafeMutablePointer<wlr_xdg_toplevel_decoration_v1>) {
        self.addListener(decoration, XdgDecorationListener.newFor(emitter: decoration, handler: self))
        self.requestMode(decoration: decoration)
    }
}

extension Awc: XdgDecoration {
    func destroy(decoration: UnsafeMutablePointer<wlr_xdg_toplevel_decoration_v1>) {
        self.removeListener(decoration, XdgDecorationListener.self)
    }

    func requestMode(decoration: UnsafeMutablePointer<wlr_xdg_toplevel_decoration_v1>) {
        wlr_xdg_toplevel_decoration_v1_set_mode(decoration, WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE)
    }
}

func setUpDecorations<L: Layout>(wlDisplay: OpaquePointer, awc: Awc<L>) {
    guard let decorationManager = wlr_server_decoration_manager_create(wlDisplay) else {
        print("[ERROR] Could not create decoration manager")
        return
    }
    guard let xdgDecorationManager = wlr_xdg_decoration_manager_v1_create(wlDisplay) else {
        print("[ERROR] Could not create XDG decorations manager")
        return
    }

    wlr_server_decoration_manager_set_default_mode(
        decorationManager,
        WLR_SERVER_DECORATION_MANAGER_MODE_SERVER.rawValue
    )
    awc.addListener(decorationManager, ServerDecorationsListener.newFor(emitter: decorationManager, handler: awc))
    awc.addListener(xdgDecorationManager, XdgDecorationsListener.newFor(emitter: xdgDecorationManager, handler: awc))
}

//
// Event handler for Wlroots (& other "low-level" events
//
// Does basic handling and then translates them into higher-level events.
//

import Wlroots

// Wlroot signal handlers don't have an extra parameter for arbitrary consumer-controlled
// data, but rather use a pattern that assumes that the signal handler is embedded in the
// data that should be passed. As the handler that triggered the signal is passed to the
// handler, `wl_container_of` can then be used to access all data required by the signal
// handler.
// `wl_container_of` is a macro and as such is very cumbersome to use in Swift. Its
// functionality can be built with `MemoryLayout`, but Swift only allows to get offsets
// into structs, not classes. Hence this struct is used as a container for all listeners
// that don't require any additional state because everything is passed as signal data.
// Given a signal callback, Swift's `MemoryLayout` can then be used to retrieve the
// `onEvent` callback property and the (type-safe) event is emitted via that.
private struct Listeners {
    var onEvent: (Event) -> ()
    let obtainPendingEvents: () -> [Event]

    // Backend
    var newInput: wl_listener = wl_listener()
    var newOutput: wl_listener = wl_listener()

    // Cursor
    var cursorAxis: wl_listener = wl_listener()
    var cursorButton: wl_listener = wl_listener()
    var cursorFrame: wl_listener = wl_listener()
    var cursorMotion: wl_listener = wl_listener()
    var cursorMotionAbsolute: wl_listener = wl_listener()

    // Seat
    var requestCursor: wl_listener = wl_listener()
    var requestSetSelection: wl_listener = wl_listener()

    // XDG Shell
    var newXdgSurface: wl_listener = wl_listener()

    // XWayland
    var xwaylandReady: wl_listener = wl_listener()
    var newXWaylandSurface: wl_listener = wl_listener()

    init() {
        var pendingEvents: [Event] = []
        self.onEvent = { pendingEvents.append($0) }
        self.obtainPendingEvents = {
            let events = Array(pendingEvents)
            pendingEvents.removeAll(keepingCapacity: false)
            return events
        }
    }
}

private protocol Listener {
    associatedtype Emitter

    var handler: WlEventHandler? { get set }
    init()
    mutating func listen(to: UnsafeMutablePointer<Emitter>)
    mutating func deregister()
}

extension Listener {
    static func newFor(
        emitter: UnsafeMutablePointer<Emitter>,
        handler: WlEventHandler
    ) -> UnsafeMutablePointer<Self> {
        let listener = UnsafeMutablePointer<Self>.allocate(capacity: 1)
        listener.initialize(to: Self())
        listener.pointee.handler = handler
        listener.pointee.listen(to: emitter)
        return listener
    }
}


/// Listeners for one wlr_output.
private struct OutputListener: Listener {
    typealias Emitter = wlr_output

    weak var handler: WlEventHandler?
    private var frame: wl_listener = wl_listener()
    private var outputDestroyed: wl_listener = wl_listener()

    fileprivate mutating func listen(to output: UnsafeMutablePointer<wlr_output>) {
        add(signal: &output.pointee.events.frame, listener: &self.frame) { (listener, data) in
            emitEvent(from: listener!, data: data!, \OutputListener.frame, { Event.frame(output: $0) })
        }
        add(signal: &output.pointee.events.destroy, listener: &self.outputDestroyed) { listener, data in
            emitEvent(from: listener!, data: data!,
                    \OutputListener.outputDestroyed, { Event.outputDestroyed(output: $0) }
            )
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.frame.link)
        wl_list_remove(&self.outputDestroyed.link)
    }
}

// Signal listeners for a keyboard wlr_input_device.
private struct KeyboardListener: Listener {
    weak var handler: WlEventHandler?
    var keyboard: UnsafeMutablePointer<wlr_input_device>?
    private var destroy: wl_listener = wl_listener()
    private var key: wl_listener = wl_listener()
    private var modifiers: wl_listener = wl_listener()

    fileprivate mutating func listen(to keyboard: UnsafeMutablePointer<wlr_input_device>) {
        self.keyboard = keyboard

        add(signal: &keyboard.pointee.keyboard.pointee.events.destroy, listener: &self.destroy) { (listener, data) in
            emitEventWithState(
                from: listener!,
                data: data!,
                \KeyboardListener.destroy,
                \KeyboardListener.keyboard,
                { (device, data: UnsafeMutablePointer<wlr_keyboard>) in Event.keyboardDestroyed(device: device) }
            )
        }

        add(signal: &keyboard.pointee.keyboard.pointee.events.modifiers, listener: &self.modifiers) { (listener, data) in
            emitEventWithState(
                from: listener!,
                data: data!,
                \KeyboardListener.modifiers,
                \KeyboardListener.keyboard,
                { (device, data: UnsafeMutablePointer<wlr_keyboard>) in Event.modifiers(device: device) }
            )
        }

        add(signal: &keyboard.pointee.keyboard.pointee.events.key, listener: &self.key) { (listener, data) in
            emitEventWithState(
                from: listener!,
                data: data!,
                \KeyboardListener.key,
                \KeyboardListener.keyboard,
                { Event.key(device: $0, event: $1) }
            )
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.destroy.link)
        wl_list_remove(&self.key.link)
        wl_list_remove(&self.modifiers.link)
    }
}

/// Signal listeners for an XDG surface.
private struct XdgSurfaceListener: Listener {
    weak var handler: WlEventHandler?
    private var destroy: wl_listener = wl_listener()
    private var map: wl_listener = wl_listener()
    private var unmap: wl_listener = wl_listener()

    fileprivate mutating func listen(to surface: UnsafeMutablePointer<wlr_xdg_surface>) {
        add(signal: &surface.pointee.events.destroy, listener: &self.destroy) { (listener, data) in
            emitEvent(
                from: listener!, data: data!, \XdgSurfaceListener.destroy, { Event.surfaceDestroyed(xdgSurface: $0) }
            )
        }

        add(signal: &surface.pointee.events.map, listener: &self.map) { (listener, data) in
            emitEvent(from: listener!, data: data!, \XdgSurfaceListener.map, { Event.map(xdgSurface: $0) })
        }

        add(signal: &surface.pointee.events.unmap, listener: &self.unmap) { (listener, data) in
            emitEvent(from: listener!, data: data!, \XdgSurfaceListener.unmap, { Event.unmap(xdgSurface: $0) })
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.destroy.link)
        wl_list_remove(&self.map.link)
        wl_list_remove(&self.unmap.link)
    }
}

/// Signal listeners for an XWayland surface.
private struct XWaylandSurfaceListener: Listener {
    weak var handler: WlEventHandler?
    private var configureRequest: wl_listener = wl_listener()
    private var destroy: wl_listener = wl_listener()
    private var map: wl_listener = wl_listener()
    private var unmap: wl_listener = wl_listener()

    fileprivate mutating func listen(to surface: UnsafeMutablePointer<wlr_xwayland_surface>) {
        add(signal: &surface.pointee.events.request_configure, listener: &self.configureRequest) { (listener, data) in
            emitEvent(
                from: listener!,
                data: data!,
                \XWaylandSurfaceListener.configureRequest,
                { Event.configureRequestX(event: $0) }
            )
        }

        add(signal: &surface.pointee.events.destroy, listener: &self.destroy) { (listener, data) in
            emitEvent(
                from: listener!,
                data: data!,
                \XWaylandSurfaceListener.destroy,
                { Event.xwaylandSurfaceDestroyed(xwaylandSurface: $0) }
            )
        }

        add(signal: &surface.pointee.events.map, listener: &self.map) { (listener, data) in
            emitEvent(
                from: listener!,
                data: data!,
                \XWaylandSurfaceListener.map,
                { Event.mapX(xwaylandSurface: $0) }
            )
        }

        add(signal: &surface.pointee.events.unmap, listener: &self.unmap) { (listener, data) in
            emitEvent(
                from: listener!,
                data: data!,
                \XWaylandSurfaceListener.unmap,
                { Event.unmapX(xwaylandSurface: $0) }
            )
        }
    }

    mutating func deregister() {
        wl_list_remove(&configureRequest.link)
        wl_list_remove(&destroy.link)
        wl_list_remove(&map.link)
        wl_list_remove(&unmap.link)
    }
}

class WlEventHandler {
    private var singletonListeners: Listeners
    private var listeners: [UnsafeMutableRawPointer: UnsafeMutableRawPointer] = [:]

    init() {
        self.singletonListeners = Listeners()
    }

    var onEvent: (Event) -> () {
        get {
            self.singletonListeners.onEvent
        }
        set {
            self.singletonListeners.onEvent = newValue
            for event in self.singletonListeners.obtainPendingEvents() {
                newValue(event)
            }
        }
    }

    func addBackendListeners(backend: UnsafeMutablePointer<wlr_backend>) {
        assert(self.singletonListeners.newInput.notify == nil, "already listening on a backend")

        self.singletonListeners.newInput.notify = { (listener, data) in
            WlEventHandler.emitEvent(
                from: listener!, data: data!, \Listeners.newInput, { Event.newInput(device: $0) }
            )
        }

        self.singletonListeners.newOutput.notify = { (listener, data) in
            WlEventHandler.emitEvent(
                from: listener!, data: data!, \Listeners.newOutput, { Event.newOutput(output: $0) }
            )
        }

        wl_signal_add(&backend.pointee.events.new_input, &self.singletonListeners.newInput)
        wl_signal_add(&backend.pointee.events.new_output, &self.singletonListeners.newOutput)
    }

    func addCursorListeners(cursor: UnsafeMutablePointer<wlr_cursor>) {
        assert(self.singletonListeners.cursorAxis.notify == nil, "already listening on a cursor")

        self.singletonListeners.cursorAxis.notify = { (listener, data) in
            WlEventHandler.emitEvent(
                from: listener!, data: data!, \Listeners.cursorAxis, { Event.cursorAxis(event: $0) }
            )
        }

        self.singletonListeners.cursorButton.notify = { (listener, data) in
            WlEventHandler.emitEvent(
                from: listener!, data: data!, \Listeners.cursorButton, { Event.cursorButton(event: $0) }
            )
        }

        self.singletonListeners.cursorFrame.notify = { (listener, data) in
            WlEventHandler.emitEvent(
                from: listener!, data: data!, \Listeners.cursorFrame, { Event.cursorFrame(cursor: $0) }
            )
        }

        self.singletonListeners.cursorMotion.notify = { (listener, data) in
            WlEventHandler.emitEvent(
                from: listener!, data: data!, \Listeners.cursorMotion, { Event.cursorMotion(event: $0) }
            )
        }

        self.singletonListeners.cursorMotionAbsolute.notify = { (listener, data) in
            WlEventHandler.emitEvent(
                from: listener!,
                data: data!,
                \Listeners.cursorMotionAbsolute,
                { Event.cursorMotionAbsolute(event: $0) }
            )
        }

        wl_signal_add(&cursor.pointee.events.axis, &self.singletonListeners.cursorAxis)
        wl_signal_add(&cursor.pointee.events.button, &self.singletonListeners.cursorButton)
        wl_signal_add(&cursor.pointee.events.frame, &self.singletonListeners.cursorFrame)
        wl_signal_add(&cursor.pointee.events.motion, &self.singletonListeners.cursorMotion)
        wl_signal_add(&cursor.pointee.events.motion_absolute, &self.singletonListeners.cursorMotionAbsolute)
    }

    func addKeyboardListeners(device: UnsafeMutablePointer<wlr_input_device>) {
        self.addListener(device, KeyboardListener.newFor(emitter: device, handler: self))
    }

    func removeKeyboardListeners(device: UnsafeMutablePointer<wlr_input_device>) {
        self.removeListener(device, KeyboardListener.self)
    }

    private func addListener<E, L: Listener>(_ emitter: UnsafeMutablePointer<E>, _ listener: UnsafeMutablePointer<L>) {
        self.listeners[UnsafeMutableRawPointer(emitter)] = UnsafeMutableRawPointer(listener)
    }

    private func removeListener<E, L: Listener>(_ emitter: UnsafeMutablePointer<E>, _ type: L.Type) {
        if let listener = self.listeners.removeValue(forKey: UnsafeMutableRawPointer(emitter)) {
            listener.bindMemory(to: type, capacity: 1).pointee.deregister()
        }
    }

    func addOutputListeners(output: UnsafeMutablePointer<wlr_output>) {
        self.addListener(output, OutputListener.newFor(emitter: output, handler: self))
    }

    func removeOutputListeners(output: UnsafeMutablePointer<wlr_output>) {
        self.removeListener(output, OutputListener.self)
    }

    func addSeatListeners(seat: UnsafeMutablePointer<wlr_seat>) {
        assert(self.singletonListeners.requestCursor.notify == nil, "already listening on a seat")

        self.singletonListeners.requestCursor.notify = { (listener, data) in
            WlEventHandler.emitEvent(
                from: listener!,
                data: data!,
                \Listeners.requestCursor,
                { Event.cursorRequested(event: $0) }
            )
        }

        self.singletonListeners.requestSetSelection.notify = { (listener, data) in
            WlEventHandler.emitEvent(
                from: listener!,
                data: data!,
                \Listeners.requestSetSelection,
                { Event.setSelectionRequested(event: $0) }
            )
        }
        wl_signal_add(&seat.pointee.events.request_set_cursor, &self.singletonListeners.requestCursor)
        wl_signal_add(&seat.pointee.events.request_set_selection, &self.singletonListeners.requestSetSelection)
    }

    func addXdgShellListeners(xdgShell: UnsafeMutablePointer<wlr_xdg_shell>) {
        assert(self.singletonListeners.newXWaylandSurface.notify == nil)

        self.singletonListeners.newXdgSurface.notify = { (listener, data) in
            WlEventHandler.emitEvent(from: listener!, data: data!, \Listeners.newXdgSurface,
                    { Event.newSurface(xdgSurface: $0) })
        }
        wl_signal_add(&xdgShell.pointee.events.new_surface, &self.singletonListeners.newXdgSurface)
    }

    func addXdgSurfaceListeners(surface: UnsafeMutablePointer<wlr_xdg_surface>) {
        self.addListener(surface, XdgSurfaceListener.newFor(emitter: surface, handler: self))

        // XXX add toplevel listeners
    }

    func removeXdgSurfaceListeners(surface: UnsafeMutablePointer<wlr_xdg_surface>) {
        self.removeListener(surface, XdgSurfaceListener.self)
    }

    func addXWaylandListeners(xwayland: UnsafeMutablePointer<wlr_xwayland>) {
        assert(singletonListeners.newXWaylandSurface.notify == nil)

        singletonListeners.newXWaylandSurface.notify = { (listener, data) in
            WlEventHandler.emitEvent(
                from: listener!,
                data: data!,
                \Listeners.newXWaylandSurface,
                { Event.newXWaylandSurface(surface: $0) }
            )
        }

        singletonListeners.xwaylandReady.notify = { (listener, data) in
            let listenersPtr = wlContainer(of: listener!, \Listeners.xwaylandReady)
            listenersPtr.pointee.onEvent(.xwaylandReady)
        }

        wl_signal_add(&xwayland.pointee.events.new_surface, &self.singletonListeners.newXWaylandSurface)
        wl_signal_add(&xwayland.pointee.events.ready, &self.singletonListeners.xwaylandReady)
    }

    func addXWaylandSurfaceListeners(surface: UnsafeMutablePointer<wlr_xwayland_surface>) {
        self.addListener(surface, XWaylandSurfaceListener.newFor(emitter: surface, handler: self))
    }

    func removeXWaylandSurfaceListeners(surface: UnsafeMutablePointer<wlr_xwayland_surface>) {
        self.removeListener(surface, XWaylandSurfaceListener.self)
    }

    private static func emitEvent<D>(
        from: UnsafeMutableRawPointer,
        data: UnsafeMutableRawPointer,
        _ path: PartialKeyPath<Listeners>,
        _ factory: (UnsafeMutablePointer<D>) -> Event
    ) {
        let listenersPtr = wlContainer(of: from, path)
        let typedData = data.bindMemory(to: D.self, capacity: 1)
        let event = factory(typedData)
        listenersPtr.pointee.onEvent(event)
    }
}

// Swift version of `wl_container_of`
private func wlContainer<R>(of: UnsafeMutableRawPointer, _ path: PartialKeyPath<R>) -> UnsafeMutablePointer<R> {
    (of - MemoryLayout<R>.offset(of: path)!).bindMemory(to: R.self, capacity: 1)
}

private func add(
    signal: UnsafeMutablePointer<wl_signal>,
    listener: inout wl_listener,
    _ notify: @escaping @convention(c) (UnsafeMutablePointer<wl_listener>?, UnsafeMutableRawPointer?) -> ()
) {
    assert(listener.notify == nil)

    listener.notify = notify
    wl_signal_add(signal, &listener)
}

private func emitEvent<D, L: Listener>(
    from: UnsafeMutableRawPointer,
    data: UnsafeMutableRawPointer,
    _ path: PartialKeyPath<L>,
    _ factory: (UnsafeMutablePointer<D>) -> Event
) {
    let listenersPtr = wlContainer(of: from, path)
    let typedData = data.bindMemory(to: D.self, capacity: 1)
    let event = factory(typedData)
    listenersPtr.pointee.handler?.onEvent(event)
}

private func emitEventWithState<D, L: Listener, S>(
    from: UnsafeMutableRawPointer,
    data: UnsafeMutableRawPointer,
    _ path: PartialKeyPath<L>,
    _ statePath: KeyPath<L, S?>,
    _ eventFactory: (S, UnsafeMutablePointer<D>) -> Event
) {
    let listenerPtr = wlContainer(of: from, path)
    if let state = listenerPtr.pointee[keyPath: statePath] {
        let typedData = data.bindMemory(to: D.self, capacity: 1)
        listenerPtr.pointee.handler?.onEvent(eventFactory(state, typedData))
    }
}

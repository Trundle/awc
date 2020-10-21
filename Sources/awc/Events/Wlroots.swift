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

    // Output
    var frame: wl_listener = wl_listener()

    // Seat
    var requestCursor: wl_listener = wl_listener()
    var requestSetSelection: wl_listener = wl_listener()

    // XDG Shell
    var newXdgSurface: wl_listener = wl_listener()
    var map: wl_listener = wl_listener()
    var unmap: wl_listener = wl_listener()
    var destroy: wl_listener = wl_listener()

    // XWayland
    var xwaylandReady: wl_listener = wl_listener()
    var newXWaylandSurface: wl_listener = wl_listener()
    var configureRequestX: wl_listener = wl_listener()
    var destroyX: wl_listener = wl_listener()
    var mapX: wl_listener = wl_listener()
    var unmapX: wl_listener = wl_listener()

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

// Unfortunately, sometimes additional state is required to usefully handle some events such
// as key presses, because it's not possible to get the input device from the event data alone.
// While it kind of looks like an oversight on Wlroot's side, this structure is used to keep
// additonal state for a signal listener. It gets allocated via unmanaged memory.
private struct StatefulListener {
    weak var handler: WlEventHandler?
    var state: UnsafeMutableRawPointer
    var listener: wl_listener = wl_listener()
}

class WlEventHandler {
    private var listeners: Listeners
    private var listenersWithState: [UnsafeMutablePointer<StatefulListener>] = []

    init() {
        self.listeners = Listeners()
    }

    var onEvent: (Event) -> () {
        get {
            self.listeners.onEvent
        }
        set {
            self.listeners.onEvent = newValue
            for event in self.listeners.obtainPendingEvents() {
                newValue(event)
            }
        }
    }

    func addBackendListeners(backend: UnsafeMutablePointer<wlr_backend>) {
        if self.listeners.newInput.notify == nil {
            self.listeners.newInput.notify = { (listener, data) in
                WlEventHandler.emitEvent(
                    from: listener!, data: data!, \Listeners.newInput, { Event.newInput(device: $0) }
                )
            }

            self.listeners.newOutput.notify = { (listener, data) in
                WlEventHandler.emitEvent(
                    from: listener!, data: data!, \Listeners.newOutput, { Event.newOutput(output: $0) }
                )
            }
        }
        wl_signal_add(&backend.pointee.events.new_input, &self.listeners.newInput)
        wl_signal_add(&backend.pointee.events.new_output, &self.listeners.newOutput)
    }

    func addCursorListeners(cursor: UnsafeMutablePointer<wlr_cursor>) {
        if self.listeners.cursorAxis.notify == nil {
            self.listeners.cursorAxis.notify = { (listener, data) in
                WlEventHandler.emitEvent(
                    from: listener!, data: data!, \Listeners.cursorAxis, { Event.cursorAxis(event: $0) }
                )
            }

            self.listeners.cursorButton.notify = { (listener, data) in
                WlEventHandler.emitEvent(
                    from: listener!, data: data!, \Listeners.cursorButton, { Event.cursorButton(event: $0) }
                )
            }

            self.listeners.cursorFrame.notify = { (listener, data) in
                WlEventHandler.emitEvent(
                    from: listener!, data: data!, \Listeners.cursorFrame, { Event.cursorFrame(cursor: $0) }
                )
            }

            self.listeners.cursorMotion.notify = { (listener, data) in
                WlEventHandler.emitEvent(
                    from: listener!, data: data!, \Listeners.cursorMotion, { Event.cursorMotion(event: $0) }
                )
            }

            self.listeners.cursorMotionAbsolute.notify = { (listener, data) in
                WlEventHandler.emitEvent(
                    from: listener!,
                    data: data!,
                    \Listeners.cursorMotionAbsolute,
                    { Event.cursorMotionAbsolute(event: $0) }
                )
            }
        }

        wl_signal_add(&cursor.pointee.events.axis, &self.listeners.cursorAxis)
        wl_signal_add(&cursor.pointee.events.button, &self.listeners.cursorButton)
        wl_signal_add(&cursor.pointee.events.frame, &self.listeners.cursorFrame)
        wl_signal_add(&cursor.pointee.events.motion, &self.listeners.cursorMotion)
        wl_signal_add(&cursor.pointee.events.motion_absolute, &self.listeners.cursorMotionAbsolute)
    }

    func addKeyboardListeners(device: UnsafeMutablePointer<wlr_input_device>) {
        let modifiers = UnsafeMutablePointer<StatefulListener>.allocate(capacity: 1)
        modifiers.initialize(to: StatefulListener(handler: self, state: UnsafeMutableRawPointer(device)))
        modifiers.pointee.listener.notify = { (listener, data) in
            WlEventHandler.emitEventWithState(
                from: listener!, data: data!, { Event.modifiers(device: $0, keyboard: $1) }
            )
        }
        wl_signal_add(&device.pointee.keyboard.pointee.events.modifiers, &modifiers.pointee.listener)
        self.listenersWithState.append(modifiers)

        let key = UnsafeMutablePointer<StatefulListener>.allocate(capacity: 1)
        key.initialize(to: StatefulListener(handler: self, state: UnsafeMutableRawPointer(device)))
        key.pointee.listener.notify = { (listener, data) in
            WlEventHandler.emitEventWithState(from: listener!, data: data!, { Event.key(device: $0, event: $1) })
        }
        wl_signal_add(&device.pointee.keyboard.pointee.events.key, &key.pointee.listener)
        self.listenersWithState.append(key)

        // XXX register to deregister
     }

    func addOutputListeners(output: UnsafeMutablePointer<wlr_output>) {
        if self.listeners.frame.notify == nil {
            self.listeners.frame.notify = { (listener, data) in
                WlEventHandler.emitEvent(from: listener!, data: data!, \Listeners.frame, { Event.frame(output: $0) })
            }
        }
        wl_signal_add(&output.pointee.events.frame, &self.listeners.frame)
    }

    func addSeatListeners(seat: UnsafeMutablePointer<wlr_seat>) {
        if self.listeners.requestCursor.notify == nil {
            self.listeners.requestCursor.notify = { (listener, data) in
                WlEventHandler.emitEvent(
                    from: listener!,
                    data: data!,
                    \Listeners.requestCursor,
                    { Event.cursorRequested(event: $0) }
                )
            }

            self.listeners.requestSetSelection.notify = { (listener, data) in
                // XXX
            }
        }
        wl_signal_add(&seat.pointee.events.request_set_cursor, &self.listeners.requestCursor)
        wl_signal_add(&seat.pointee.events.request_set_selection, &self.listeners.requestSetSelection)
    }

    func addXdgShellListeners(xdgShell: UnsafeMutablePointer<wlr_xdg_shell>) {
        self.listeners.newXdgSurface.notify = { (listener, data) in
            WlEventHandler.emitEvent(from: listener!, data: data!, \Listeners.newXdgSurface,
                    { Event.newSurface(xdgSurface: $0) })
        }
        wl_signal_add(&xdgShell.pointee.events.new_surface, &self.listeners.newXdgSurface)
    }

    func addXdgSurfaceListeners(surface: UnsafeMutablePointer<wlr_xdg_surface>) {
        if self.listeners.map.notify == nil {
            self.listeners.map.notify = { (listener, data) in
                WlEventHandler.emitEvent(from: listener!, data: data!, \Listeners.map, { Event.map(xdgSurface: $0) })
            }

            self.listeners.unmap.notify = { (listener, data) in
                WlEventHandler.emitEvent(
                    from: listener!, data: data!, \Listeners.unmap, { Event.unmap(xdgSurface: $0) }
                )
            }

            self.listeners.destroy.notify = { (listener, data) in
                WlEventHandler.emitEvent(
                    from: listener!, data: data!, \Listeners.destroy, { Event.surfaceDestroyed(xdgSurface: $0) }
                )
            }
        }

        wl_signal_add(&surface.pointee.events.map, &self.listeners.map)
        wl_signal_add(&surface.pointee.events.unmap, &self.listeners.unmap)
        wl_signal_add(&surface.pointee.events.destroy, &self.listeners.destroy)

        // XXX add toplevel listeners
    }

    func addXWaylandListeners(xwayland: UnsafeMutablePointer<wlr_xwayland>) {
        if listeners.newXWaylandSurface.notify == nil {
            listeners.newXWaylandSurface.notify = { (listener, data) in
                WlEventHandler.emitEvent(
                    from: listener!,
                    data: data!,
                    \Listeners.newXWaylandSurface,
                    { Event.newXWaylandSurface(surface: $0) }
                )
            }

            listeners.xwaylandReady.notify = { (listener, data) in
                let listenersPtr = wlContainer(of: listener!, \Listeners.xwaylandReady)
                listenersPtr.pointee.onEvent(.xwaylandReady)
            }
        }
        wl_signal_add(&xwayland.pointee.events.new_surface, &self.listeners.newXWaylandSurface)
        wl_signal_add(&xwayland.pointee.events.ready, &self.listeners.xwaylandReady)
    }

    func addXWaylandSurfaceListeners(surface: UnsafeMutablePointer<wlr_xwayland_surface>) {
        if self.listeners.mapX.notify == nil {
            self.listeners.mapX.notify = { (listener, data) in
                WlEventHandler.emitEvent(
                    from: listener!,
                    data: data!,
                    \Listeners.mapX,
                    { Event.mapX(xwaylandSurface: $0) }
                )
            }

            self.listeners.unmapX.notify = { (listener, data) in
                WlEventHandler.emitEvent(
                    from: listener!,
                    data: data!,
                    \Listeners.unmapX,
                    { Event.unmapX(xwaylandSurface: $0) }
                )
            }

            self.listeners.destroyX.notify = { (listener, data) in
                WlEventHandler.emitEvent(
                    from: listener!,
                    data: data!,
                    \Listeners.destroyX,
                    { Event.xwaylandSurfaceDestroyed(xwaylandSurface: $0) }
                )
            }

            self.listeners.configureRequestX.notify = { (listener, data) in
                WlEventHandler.emitEvent(
                        from: listener!,
                        data: data!,
                        \Listeners.configureRequestX,
                        { Event.configureRequestX(event: $0) }
                )
            }
        }

        wl_signal_add(&surface.pointee.events.request_configure, &self.listeners.configureRequestX)
        wl_signal_add(&surface.pointee.events.map, &self.listeners.mapX)
        wl_signal_add(&surface.pointee.events.unmap, &self.listeners.unmapX)
        wl_signal_add(&surface.pointee.events.destroy, &self.listeners.destroyX)
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

    private static func emitEventWithState<S, D>(
        from: UnsafeMutableRawPointer,
        data: UnsafeMutableRawPointer,
        _ eventFactory: (UnsafeMutablePointer<S>, UnsafeMutablePointer<D>) -> Event
    ) {
        let listenerPtr = wlContainer(of: from, \StatefulListener.listener)
        let state = listenerPtr.pointee.state.bindMemory(to: S.self, capacity: 1)
        let typedData = data.bindMemory(to: D.self, capacity: 1)
        listenerPtr.pointee.handler?.onEvent(eventFactory(state, typedData))
    }
}

// Swift version of `wl_container_of`
private func wlContainer<R>(of: UnsafeMutableRawPointer, _ path: PartialKeyPath<R>) -> UnsafeMutablePointer<R> {
    (of - MemoryLayout<R>.offset(of: path)!).bindMemory(to: R.self, capacity: 1)
}

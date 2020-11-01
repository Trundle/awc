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

/// XXX rename
protocol PListener {
    associatedtype Emitter
    associatedtype Handler

    var handler: Handler? { get set }
    init()
    mutating func listen(to: UnsafeMutablePointer<Emitter>)
    mutating func deregister()
}

extension PListener {
    // N.B. Caller is responsible for deallocating again
    static func newFor(
        emitter: UnsafeMutablePointer<Emitter>,
        handler: Handler
    ) -> UnsafeMutablePointer<Self> {
        let listener = UnsafeMutablePointer<Self>.allocate(capacity: 1)
        listener.initialize(to: Self())
        listener.pointee.handler = handler
        listener.pointee.listen(to: emitter)
        return listener
    }

    internal static func add(
        signal: UnsafeMutablePointer<wl_signal>,
        listener: inout wl_listener,
        _ notify: @escaping @convention(c) (UnsafeMutablePointer<wl_listener>?, UnsafeMutableRawPointer?) -> ()
    ) {
        assert(listener.notify == nil)

        listener.notify = notify
        wl_signal_add(signal, &listener)
    }

    internal static func handle<D, L: PListener>(
        from: UnsafeMutableRawPointer,
        data: UnsafeMutableRawPointer,
        _ path: PartialKeyPath<L>,
        _ handlerCallback: (L.Handler, UnsafeMutablePointer<D>) -> ()
    ) {
        let listenersPtr = wlContainer(of: from, path)
        let typedData = data.bindMemory(to: D.self, capacity: 1)
        if let handler = listenersPtr.pointee.handler {
            handlerCallback(handler, typedData)
        }
    }
}

/// A listener for Wayland signals.
protocol Listener {
    associatedtype Emitter

    var handler: WlEventHandler? { get set }
    init()
    mutating func listen(to: UnsafeMutablePointer<Emitter>)
    mutating func deregister()
}

extension Listener {
    // N.B. Caller is responsible for deallocating again
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

    internal static func add(
        signal: UnsafeMutablePointer<wl_signal>,
        listener: inout wl_listener,
        _ notify: @escaping @convention(c) (UnsafeMutablePointer<wl_listener>?, UnsafeMutableRawPointer?) -> ()
    ) {
        assert(listener.notify == nil)

        listener.notify = notify
        wl_signal_add(signal, &listener)
    }

    internal static func emitEvent<D, L: Listener>(
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

    internal static func emitEventWithState<D, L: Listener, S>(
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
}

protocol OutputDestroyedHandler: class {
    func destroyed(output: UnsafeMutablePointer<wlr_output>)
}

/// A specialized listener for an output: listens to destroy events.
struct OutputDestroyListener: PListener {
    weak var handler: OutputDestroyedHandler?
    private var destroyed: wl_listener = wl_listener()

    internal mutating func listen(to output: UnsafeMutablePointer<wlr_output>) {
        Self.add(signal: &output.pointee.events.destroy, listener: &self.destroyed) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.destroyed, { $0.destroyed(output: $1) })
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.destroyed.link)
    }
}


/// Listeners for one wlr_output.
private struct OutputListener: Listener {
    typealias Emitter = wlr_output

    weak var handler: WlEventHandler?
    private var frame: wl_listener = wl_listener()
    private var outputDestroyed: wl_listener = wl_listener()

    fileprivate mutating func listen(to output: UnsafeMutablePointer<wlr_output>) {
        OutputListener.add(signal: &output.pointee.events.frame, listener: &self.frame) { (listener, data) in
            OutputListener.emitEvent(from: listener!, data: data!, \OutputListener.frame, { Event.frame(output: $0) })
        }
        OutputListener.add(signal: &output.pointee.events.destroy, listener: &self.outputDestroyed) { listener, data in
            OutputListener.emitEvent(from: listener!, data: data!,
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

        KeyboardListener.add(
            signal: &keyboard.pointee.keyboard.pointee.events.destroy,
            listener: &self.destroy
        ) { (listener, data) in
            KeyboardListener.emitEventWithState(
                from: listener!,
                data: data!,
                \KeyboardListener.destroy,
                \KeyboardListener.keyboard,
                { (device, data: UnsafeMutablePointer<wlr_keyboard>) in Event.keyboardDestroyed(device: device) }
            )
        }

        KeyboardListener.add(
            signal: &keyboard.pointee.keyboard.pointee.events.modifiers,
            listener: &self.modifiers
        ) { (listener, data) in
            KeyboardListener.emitEventWithState(
                from: listener!,
                data: data!,
                \KeyboardListener.modifiers,
                \KeyboardListener.keyboard,
                { (device, data: UnsafeMutablePointer<wlr_keyboard>) in Event.modifiers(device: device) }
            )
        }

        KeyboardListener.add(
            signal: &keyboard.pointee.keyboard.pointee.events.key,
            listener: &self.key
        ) { (listener, data) in
            KeyboardListener.emitEventWithState(
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
        if let listenerPtr = self.listeners.removeValue(forKey: UnsafeMutableRawPointer(emitter)) {
            let typedListenerPtr = listenerPtr.bindMemory(to: type, capacity: 1)
            typedListenerPtr.pointee.deregister()
            typedListenerPtr.deallocate()
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

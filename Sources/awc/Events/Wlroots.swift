//
// Event handler for Wlroots (& other "low-level" events
//
// Does basic handling and then translates them into higher-level events.
//

import Wlroots

import Libawc


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

protocol SeatEventHandler: AnyObject {
    /// Raised by the seat when a client provides a cursor image.
    func cursorRequested(event: UnsafeMutablePointer<wlr_seat_pointer_request_set_cursor_event>)

    /// This event is raised by the seat when a client wants to set the selection,
    /// usually when the user copies something.
    func setSelectionRequested(event: UnsafeMutablePointer<wlr_seat_request_set_selection_event>)

    func dragRequested(event: UnsafeMutablePointer<wlr_seat_request_start_drag_event>)
    func start(drag: UnsafeMutablePointer<wlr_drag>)
}

struct SeatListener: PListener {
    weak var handler: SeatEventHandler?
    var requestCursor: wl_listener = wl_listener()
    var requestSetSelection: wl_listener = wl_listener()
    var requestStartDrag: wl_listener = wl_listener()
    var startDrag: wl_listener = wl_listener()

    mutating func listen(to seat: UnsafeMutablePointer<wlr_seat>) {
        Self.add(signal: &seat.pointee.events.request_set_cursor, listener: &self.requestCursor) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.requestCursor, { $0.cursorRequested(event: $1) })
        }

        Self.add(signal: &seat.pointee.events.request_set_selection, listener: &self.requestSetSelection) {
            (listener, data) in
            Self.handle(
                from: listener!,
                data: data!,
                \Self.requestSetSelection,
                { $0.setSelectionRequested(event: $1) }
            )
        }

        Self.add(signal: &seat.pointee.events.request_start_drag, listener: &self.requestStartDrag) {
            (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.requestStartDrag, { $0.dragRequested(event: $1) })
        }

        Self.add(signal: &seat.pointee.events.start_drag, listener: &self.startDrag) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.startDrag, { $0.start(drag: $1) })
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.requestCursor.link)
        wl_list_remove(&self.requestSetSelection.link)
        wl_list_remove(&self.requestStartDrag.link)
        wl_list_remove(&self.startDrag.link)
    }
}

protocol OutputDestroyedHandler: AnyObject {
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
    private var outputDestroyed: wl_listener = wl_listener()

    fileprivate mutating func listen(to output: UnsafeMutablePointer<wlr_output>) {
        OutputListener.add(signal: &output.pointee.events.destroy, listener: &self.outputDestroyed) { listener, data in
            OutputListener.emitEvent(from: listener!, data: data!,
                    \OutputListener.outputDestroyed, { Event.outputDestroyed(output: $0) }
            )
        }
    }

    mutating func deregister() {
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

private struct BackendListener: Listener {
    weak var handler: WlEventHandler?
    private var newInput: wl_listener = wl_listener()
    private var newOutput: wl_listener = wl_listener()

    mutating func listen(to backend: UnsafeMutablePointer<wlr_backend>) {
        Self.add(signal: &backend.pointee.events.new_input, listener: &self.newInput) { (listener, data) in
            Self.emitEvent(from: listener!, data: data!, \Self.newInput, { Event.newInput(device: $0) })
        }

        Self.add(signal: &backend.pointee.events.new_output, listener: &self.newOutput) { (listener, data) in
            Self.emitEvent(from: listener!, data: data!, \Self.newOutput, { Event.newOutput(output: $0) })
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.newInput.link)
        wl_list_remove(&self.newOutput.link)
    }
}

private struct CursorListener: Listener {
    weak var handler: WlEventHandler?
    private var axis: wl_listener = wl_listener()
    private var button: wl_listener = wl_listener()
    private var frame: wl_listener = wl_listener()
    private var motion: wl_listener = wl_listener()
    private var motionAbsolute: wl_listener = wl_listener()

    mutating func listen(to cursor: UnsafeMutablePointer<wlr_cursor>) {
        Self.add(signal: &cursor.pointee.events.axis, listener: &self.axis) { (listener, data) in
            Self.emitEvent(
                from: listener!, data: data!, \Self.axis, { Event.cursorAxis(event: $0) }
            )
        }

        Self.add(signal: &cursor.pointee.events.button, listener: &self.button) { (listener, data) in
            Self.emitEvent(
                from: listener!, data: data!, \Self.button, { Event.cursorButton(event: $0) }
            )
        }

        Self.add(signal: &cursor.pointee.events.frame, listener: &self.frame) { (listener, data) in
            Self.emitEvent(
                from: listener!, data: data!, \Self.frame, { Event.cursorFrame(cursor: $0) }
            )
        }

        Self.add(signal: &cursor.pointee.events.motion, listener: &self.motion) { (listener, data) in
            Self.emitEvent(
                from: listener!, data: data!, \Self.motion, { Event.cursorMotion(event: $0) }
            )
        }

        Self.add(signal: &cursor.pointee.events.motion_absolute, listener: &self.motionAbsolute) {
            (listener, data) in
            Self.emitEvent(
                from: listener!,
                data: data!,
                \Self.motionAbsolute,
                { Event.cursorMotionAbsolute(event: $0) }
            )
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.axis.link)
        wl_list_remove(&self.button.link)
        wl_list_remove(&self.frame.link)
        wl_list_remove(&self.motion.link)
        wl_list_remove(&self.motionAbsolute.link)
    }
}

class WlEventHandler {
    private let emitPending: ((Event) -> ()) -> ()
    private var onEventCallback: (Event) -> ()
    private var listeners: [UnsafeMutableRawPointer: UnsafeMutableRawPointer] = [:]

    init() {
        var pendingEvents: [Event] = []
        self.onEventCallback = { pendingEvents.append($0) }
        self.emitPending = { emitter in
            for event in pendingEvents {
                emitter(event)
            }
            pendingEvents.removeAll(keepingCapacity: false)
        }
    }

    var onEvent: (Event) -> () {
        get {
            self.onEventCallback
        }
        set {
            self.onEventCallback = newValue
            self.emitPending(newValue)
        }
    }

    func addBackendListeners(backend: UnsafeMutablePointer<wlr_backend>) {
        self.addListener(backend, BackendListener.newFor(emitter: backend, handler: self))
    }

    func addCursorListeners(cursor: UnsafeMutablePointer<wlr_cursor>) {
        self.addListener(cursor, CursorListener.newFor(emitter: cursor, handler: self))
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
}

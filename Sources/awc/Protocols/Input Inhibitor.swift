import Wlroots

public protocol InputInhibitorHandler: AnyObject {
    func activate(manager: UnsafeMutablePointer<wlr_input_inhibit_manager>)
    func deactivate(manager: UnsafeMutablePointer<wlr_input_inhibit_manager>)
}

struct InputInhibitorListener: PListener {
    weak var handler: InputInhibitorHandler?
    private var activate: wl_listener = wl_listener()
    private var deactivate: wl_listener = wl_listener()

    mutating func listen(to manager: UnsafeMutablePointer<wlr_input_inhibit_manager>) {
        Self.add(signal: &manager.pointee.events.activate, listener: &self.activate) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.activate, { $0.activate(manager: $1) })
        }

        Self.add(signal: &manager.pointee.events.deactivate, listener: &self.deactivate) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.deactivate, { $0.deactivate(manager: $1) })
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.activate.link)
        wl_list_remove(&self.deactivate.link)
    }
}

extension Awc: InputInhibitorHandler {
    public func activate(manager: UnsafeMutablePointer<wlr_input_inhibit_manager>) {
        setExclusive(client: manager.pointee.active_client)
    }

    public func deactivate(manager: UnsafeMutablePointer<wlr_input_inhibit_manager>) {
        self.exclusiveClient = nil
    }

    private func setExclusive(client: OpaquePointer) {
        if let seatClient = self.seat.pointee.pointer_state.focused_client {
            if seatClient.pointee.client != client {
                wlr_seat_pointer_clear_focus(self.seat)
            }
        }

        if let focusedSurface = self.seat.pointee.keyboard_state.focused_surface {
            if wl_resource_get_client(focusedSurface.pointee.resource) != client {
                wlr_seat_keyboard_clear_focus(self.seat)
            }
        }

        self.exclusiveClient = client
    }
}

public func setUpInputInhibitor<L: Layout>(awc: Awc<L>) {
    guard let manager = wlr_input_inhibit_manager_create(awc.wlDisplay) else {
        print("[ERROR] Could not create input inhibit manager :(")
        return
    }

    awc.addListener(manager, InputInhibitorListener.newFor(emitter: manager, handler: awc))
}

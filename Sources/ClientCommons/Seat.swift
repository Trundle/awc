import LayerShellClient

fileprivate class SeatListener {
    private static var listener = wl_seat_listener()
    private static var listenerInitialized = false
    
    fileprivate var capabilities: UInt32 = 0
    fileprivate var name: String? = nil

    init(_ seat: TypedOpaque<WlSeat>) {
        if !Self.listenerInitialized {
            Self.initializeListener()
        }

        wl_seat_add_listener(
            seat.get(as: WlSeat.self),
            &Self.listener,
            Unmanaged.passUnretained(self).toOpaque())
    }

    private static func initializeListener() {
        Self.listener.capabilities = { data, seat, capabilities in
            let this: SeatListener = Unmanaged.fromOpaque(data!).takeUnretainedValue()
            this.capabilities = capabilities
        }

        Self.listener.name = { data, _, name in
            let this: SeatListener = Unmanaged.fromOpaque(data!).takeUnretainedValue()
            this.name = String(cString: name!)
        }

        Self.listenerInitialized = true
    }
}

public class Seat {
    public let rawPtr: OpaquePointer
    private let listener: SeatListener

    public var name: String {
        get {
            listener.name!
        }
    }

    public var hasKeyboard: Bool {
        get {
            listener.capabilities & WL_SEAT_CAPABILITY_KEYBOARD.rawValue != 0
        }
    }

    public var hasPointer: Bool {
        get {
            listener.capabilities & WL_SEAT_CAPABILITY_POINTER.rawValue != 0
        }
    }

    init(_ seat: TypedOpaque<WlSeat>) {
        self.listener = SeatListener(seat)
        self.rawPtr = seat.get(as: WlSeat.self)
    }
}

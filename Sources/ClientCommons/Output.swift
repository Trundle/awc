import CWaylandEgl

public class Output {
    private static var listener = wl_output_listener()
    private static var listenerInitialized: Bool = false

    public let output: OpaquePointer
    private var _name: String!

    public var name: String {
        get {
            self._name
        }
    }

    // XXX make internal again
    init(output: OpaquePointer) {
        self.output = output

        if !Self.listenerInitialized {
            Self.initializeListener()
        }

        wl_output_add_listener(output, &Self.listener, Unmanaged.passUnretained(self).toOpaque())
    }

    private static func initializeListener() {
        Self.listener.geometry = { _, _, _, _, _, _, _, _, _, _ in }
        Self.listener.mode = { _, _, _, _, _, _ in }
        Self.listener.done = { _, _ in }
        Self.listener.scale = { _, _, _ in }
        Self.listener.description = { _, _, _ in }
        Self.listener.name = { data, wlOutput, name in
            assert(data != nil)
            assert(name != nil)

            let output: Output = Unmanaged.fromOpaque(data!).takeUnretainedValue()
            assert(output.output == wlOutput)
            output._name = String(cString: name!)
        }
        Self.listenerInitialized = true
    }
}

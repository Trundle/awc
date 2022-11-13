import LayerShellClient

struct XdgOutput {}

fileprivate class XdgOutputListener {
    private static var listener = zxdg_output_v1_listener()
    private static var listenerInitialized: Bool = false

    fileprivate var logicalX: Int32 = 0
    fileprivate var logicalY: Int32 = 0
    fileprivate var width: Int32 = 0
    fileprivate var height: Int32 = 0

    init(_ output: TypedOpaque<XdgOutput>) {
        if !Self.listenerInitialized {
            Self.initializeListener()
        }

        zxdg_output_v1_add_listener(
            output.get(as: XdgOutput.self),
            &Self.listener,
            Unmanaged.passUnretained(self).toOpaque())
    }

    private static func initializeListener() {
        Self.listener.logical_position = { data, _, x, y in
            let this: XdgOutputListener = Unmanaged.fromOpaque(data!).takeUnretainedValue()
            this.logicalX = x
            this.logicalY = y
        }
        Self.listener.logical_size = { data, _, width, height in
            let this: XdgOutputListener = Unmanaged.fromOpaque(data!).takeUnretainedValue()
            this.width = width
            this.height = height
        }
        Self.listener.done = { _, _ in }
        Self.listener.name = { _, _, _ in }
        Self.listener.description = { _, _, _ in }
        Self.listenerInitialized = true
    }
}

public func getPositionAndSize(
    output: Output,
    wlDisplay: OpaquePointer,
    _ registryListener: RegistryListener
) -> ((Int32, Int32), (Int32, Int32))? {
    let xdgOutput: TypedOpaque<XdgOutput> = TypedOpaque(zxdg_output_manager_v1_get_xdg_output(
        registryListener.get(XdgOutputManager.self),
        output.output)!)
    defer {
        zxdg_output_v1_destroy(xdgOutput.get(as: XdgOutput.self))
    }

    let listener = XdgOutputListener(xdgOutput)
    wl_display_roundtrip(wlDisplay)
    return ((listener.logicalX, listener.logicalY), (listener.width, listener.height))
}

public func getSize(
    output: Output,
    wlDisplay: OpaquePointer,
    _ registryListener: RegistryListener
) -> (Int32, Int32)? {
    getPositionAndSize(output: output, wlDisplay: wlDisplay, registryListener).map { $0.1 }
}

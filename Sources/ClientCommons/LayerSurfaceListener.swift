import LayerShellClient

public struct LayerSurface {}

public class LayerSurfaceListener {
    private static var listener = zwlr_layer_surface_v1_listener()
    private static var listenerInitialized = false

    public var width: UInt32 = 0
    public var height: UInt32 = 0
    private let layerSurface: OpaquePointer

    public init(_ layerSurface: TypedOpaque<LayerSurface>) {
        if !Self.listenerInitialized {
            Self.initializeListener()
        }
        self.layerSurface = layerSurface.get(as: LayerSurface.self)
        zwlr_layer_surface_v1_add_listener(
            layerSurface.get(as: LayerSurface.self),
            &Self.listener,
            Unmanaged.passUnretained(self).toOpaque())
    }

    private func handleConfigure(serial: UInt32, width: UInt32, height: UInt32) {
        self.width = width
        self.height = height
        zwlr_layer_surface_v1_ack_configure(self.layerSurface, serial)
    }

    private static func initializeListener() {
        Self.listener.configure = { data, _, serial, width, height in
          let this: LayerSurfaceListener = Unmanaged.fromOpaque(data!).takeUnretainedValue()
          this.handleConfigure(serial: serial, width: width, height: height)
        }
        Self.listener.closed = { _, _ in }
        Self.listenerInitialized = true
    }
}

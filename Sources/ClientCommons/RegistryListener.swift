import Glibc
import LayerShellClient

public struct LayerShell {}
public struct WlCompositor {}
public struct WlSeat {}
public struct XdgOutputManager {}

public class RegistryListener {
    private let display: OpaquePointer
    private var listener = wl_registry_listener()
    private var _outputs: [Output] = []
    private var _seats: [Seat] = []
    private var compositor: TypedOpaque<WlCompositor>? = nil
    private var layerShell: TypedOpaque<LayerShell>? = nil
    private var xdgOutputManager: TypedOpaque<XdgOutputManager>? = nil

    public init(_ display: OpaquePointer) {
        self.display = display
        self.listener.global = { data, registry, name, interface, version in
            let this: RegistryListener = Unmanaged.fromOpaque(data!).takeUnretainedValue()
            this.handleGlobal(registry: registry, name: name, interface: interface, version: version)
        }
        self.listener.global_remove = { _, _, _ in }

        let registry = wl_display_get_registry(display)
        wl_registry_add_listener(registry, &self.listener, Unmanaged.passRetained(self).toOpaque())
    }

    deinit {
        if let layerShell = self.layerShell {
            zwlr_layer_shell_v1_destroy(layerShell.get(as: LayerShell.self))
        }
        if let compositor = self.compositor {
            wl_compositor_destroy(compositor.get(as: WlCompositor.self))
        }
        if let xdgOutputManager = self.xdgOutputManager {
            zxdg_output_manager_v1_destroy(xdgOutputManager.get(as: XdgOutputManager.self))
        }

        wl_display_roundtrip(self.display)
    }

    public func get(_ t: LayerShell.Type) -> OpaquePointer {
        return self.layerShell!.get(as: t)
    }

    public func get(_ t: WlCompositor.Type) -> OpaquePointer {
        return self.compositor!.get(as: t)
    }

    public func get(_ t: XdgOutputManager.Type) -> OpaquePointer {
        return self.xdgOutputManager!.get(as: t)
    }

    public func getOutput(name: String) -> Output? {
        self._outputs.first(where: { $0.name == name })
    }

    public func outputs() -> [Output] {
        self._outputs
    }
    
    public func seats() -> [Seat] {
        self._seats
    }

    public func done() {
        Unmanaged.passUnretained(self).release()
    }

    public func hasAllGlobals() -> Bool {
        var missing: [String] = []
        if self.compositor == nil {
            missing.append("wl_compositor")
        }
        if self.layerShell == nil {
            missing.append("layer shell")
        }
        if self.xdgOutputManager == nil {
            missing.append("XDG output manager")
        }
        if !missing.isEmpty {
            logger.critical("The following globals are missing: \(missing.joined(separator: ", "))")
            return false
        } else {
            return true
        }
    }

    private func handleGlobal(
        registry: OpaquePointer?,
        name: UInt32,
        interface: UnsafePointer<CChar>?,
        version: UInt32)
    {
        assert(registry != nil)
        assert(interface != nil)

        if strcmp(interface!, wl_output_interface.name) == 0 {
            let output = OpaquePointer(bind_wl_output_interface(registry, name, 4)!)
            self._outputs.append(Output(output: output))
        } else if strcmp(interface!, wl_compositor_interface.name) == 0 {
            assert(version >= 4)
            self.compositor = TypedOpaque(bind_wl_compositor_interface(registry, name, 4))
        } else if strcmp(interface!, zwlr_layer_shell_v1_interface.name) == 0 {
            assert(version >= 4)
            self.layerShell = TypedOpaque(bind_zwlr_layer_shell_v1_interface(registry, name, version))
        } else if strcmp(interface!, wl_seat_interface.name) == 0 {
            self._seats.append(Seat(TypedOpaque(bind_wl_seat_interface(registry, name, 7))))
        } else if strcmp(interface!, zxdg_output_manager_v1_interface.name) == 0 {
            self.xdgOutputManager = TypedOpaque(bind_zxdg_output_manager_v1_interface(
                registry,
                name,
                2))
        }
    }
}

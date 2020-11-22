import Wlroots

// XXX Should this be a protocol instead?
public enum Surface: Hashable {
    case layer(surface: UnsafeMutablePointer<wlr_layer_surface_v1>)
    case xdg(surface: UnsafeMutablePointer<wlr_xdg_surface>)
    case xwayland(surface: UnsafeMutablePointer<wlr_xwayland_surface>)
}

extension Surface {
    func configure(output: wlr_box, box: wlr_box) {
        switch self {
        case .layer(let layerSurface):
            wlr_layer_surface_v1_configure(layerSurface, UInt32(box.width), UInt32(box.height))
        case .xdg(let xdgSurface):
            wlr_xdg_toplevel_set_size(xdgSurface, UInt32(box.width), UInt32(box.height))
        case .xwayland(let xwaylandSurface):
            wlr_xwayland_surface_configure(
                    xwaylandSurface,
                    Int16(output.x + box.x),
                    Int16(output.y + box.y),
                    UInt16(box.width),
                    UInt16(box.height)
            )
        }
    }

    func setTiled() {
        switch self {
        case .layer: ()
        case .xdg(let surface):
            let edges = WLR_EDGE_LEFT.rawValue | WLR_EDGE_RIGHT.rawValue |
                    WLR_EDGE_TOP.rawValue | WLR_EDGE_BOTTOM.rawValue
            wlr_xdg_toplevel_set_tiled(surface, edges)
        case .xwayland(let surface):
            wlr_xwayland_surface_set_maximized(surface, true)
        }
    }

    func preferredFloatingBox<L: Layout>(
        awc: Awc<L>,
        output: Output<L>
    ) -> wlr_box where L.View == Surface, L.OutputData == OutputDetails {
        switch self {
        case .layer: /* XXX */ return wlr_box()
        case .xdg(let surface):
            let box = UnsafeMutableBufferPointer<wlr_box>.allocate(capacity: 1)
            defer { box.deallocate() }
            wlr_xdg_surface_get_geometry(surface, box.baseAddress!)
            return box[0]
        case .xwayland(let surface):
            let outputBox = output.data.box
            return wlr_box(x: Int32(surface.pointee.x) - outputBox.x,
                    y: Int32(surface.pointee.y) - outputBox.y,
                    width: Int32(surface.pointee.width), height: Int32(surface.pointee.height))
        }
    }

    func wantsFloating<L: Layout>(awc: Awc<L>) -> Bool {
        switch self {
        case .layer: return true
        case .xdg(let surface): return surface.pointee.toplevel.pointee.parent != nil
        case .xwayland(let surface):
            if surface.pointee.override_redirect || surface.pointee.modal {
                return true
            } else {
                for i in 0..<surface.pointee.window_type_len {
                    if let type = awc.windowTypeAtoms[surface.pointee.window_type[i]] {
                        if [.dialog, .dropdownMenu, .menu, .notification, .popupMenu, .splash,
                            .toolbar, .tooltip, .utility
                           ].contains(type) {
                            return true
                        }
                    }
                }
                return false
            }
        }
    }

    func popupOf(wlrXWaylandSurface: UnsafeMutablePointer<wlr_xwayland_surface>) -> Bool {
        switch self {
        case .layer, .xdg: return false
        case .xwayland(let surface):
            var current = surface
            while current.pointee.parent != nil {
                current = current.pointee.parent
                if current == wlrXWaylandSurface {
                    return true
                }
            }
            return false
        }
    }
}

extension Surface {
    var wlrSurface: UnsafeMutablePointer<wlr_surface> {
        get {
            switch self {
            case .layer(let surface): return surface.pointee.surface
            case .xdg(let surface): return surface.pointee.surface
            case .xwayland(let surface): return surface.pointee.surface
            }
        }
    }

    func surfaces() -> [(UnsafeMutablePointer<wlr_surface>, Int32, Int32)] {
        switch self {
        case .layer(let surface): return collectLayerSurfaces(surface)
        case .xdg(let surface): return collectXdgSurfaces(surface)
        case .xwayland(let surface): return surface.pointee.surface.surfaces()
        }
    }

    private func collectLayerSurfaces(
        _ surface: UnsafeMutablePointer<wlr_layer_surface_v1>
    ) -> [(UnsafeMutablePointer<wlr_surface>, Int32, Int32)] {
        var surfaces: [(UnsafeMutablePointer<wlr_surface>, Int32, Int32)] = []
        withUnsafeMutablePointer(to: &surfaces) { (surfacesPtr) in
            wlr_layer_surface_v1_for_each_surface(
                    surface,
                    {
                        $3!.bindMemory(to: [(UnsafeMutablePointer<wlr_surface>, Int32, Int32)].self, capacity: 1)
                                .pointee
                                .append(($0!, $1, $2))
                    },
                    surfacesPtr
            )
        }
        return surfaces
    }

    private func collectXdgSurfaces(
        _ surface: UnsafeMutablePointer<wlr_xdg_surface>
    ) -> [(UnsafeMutablePointer<wlr_surface>, Int32, Int32)] {
        var surfaces: [(UnsafeMutablePointer<wlr_surface>, Int32, Int32)] = []
        withUnsafeMutablePointer(to: &surfaces) { (surfacesPtr) in
            wlr_xdg_surface_for_each_surface(
                    surface,
                    {
                        $3!.bindMemory(to: [(UnsafeMutablePointer<wlr_surface>, Int32, Int32)].self, capacity: 1)
                                .pointee
                                .append(($0!, $1, $2))
                    },
                    surfacesPtr
            )
        }
        return surfaces
    }
}

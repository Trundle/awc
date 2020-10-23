import Wlroots

enum Surface: Hashable {
    case xdg(surface: UnsafeMutablePointer<wlr_xdg_surface>)
    case xwayland(surface: UnsafeMutablePointer<wlr_xwayland_surface>)
}

extension Surface {
    func configure(output: wlr_box, box: wlr_box) {
        switch self {
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
        case .xdg(let surface):
            let edges = WLR_EDGE_LEFT.rawValue | WLR_EDGE_RIGHT.rawValue |
                    WLR_EDGE_TOP.rawValue | WLR_EDGE_BOTTOM.rawValue
            wlr_xdg_toplevel_set_tiled(surface, edges)
        case .xwayland(let surface):
            wlr_xwayland_surface_set_maximized(surface, true)
        }
    }

    func preferredFloatingBox(awc: Awc, output: Output<Surface>) -> wlr_box {
        switch self {
        case .xdg(let surface):
            let box = UnsafeMutableBufferPointer<wlr_box>.allocate(capacity: 1)
            wlr_xdg_surface_get_geometry(surface, box.baseAddress!)
            return box[0]
        case .xwayland(let surface):
            let outputBox = output.box
            return wlr_box(x: Int32(surface.pointee.x) - outputBox.x,
                    y: Int32(surface.pointee.y) - outputBox.y,
                    width: Int32(surface.pointee.width), height: Int32(surface.pointee.height))
        }
    }

    func wantsFloating(awc: Awc) -> Bool {
        switch self {
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
        case .xdg: return false
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
            case .xdg(let surface): return surface.pointee.surface
            case .xwayland(let surface): return surface.pointee.surface
            }
        }
    }

    func surfaces() -> [(UnsafeMutablePointer<wlr_surface>, Int32, Int32)] {
        switch self {
        case .xdg(let surface): return collectXdgSurfaces(surface)
        case .xwayland(let surface): return collectXWaylandSurfaces(surface)
        }
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

    private func collectXWaylandSurfaces(
        _ surface: UnsafeMutablePointer<wlr_xwayland_surface>
    ) -> [(UnsafeMutablePointer<wlr_surface>, Int32, Int32)] {
        var surfaces: [(UnsafeMutablePointer<wlr_surface>, Int32, Int32)] = []
        withUnsafeMutablePointer(to: &surfaces) { (surfacesPtr) in
            wlr_surface_for_each_surface(
                    surface.pointee.surface,
                    {
                        $3!.bindMemory(to: [(UnsafeMutablePointer < wlr_surface>, Int32, Int32)].self, capacity: 1)
                                .pointee
                                .append(($0!, $1, $2))
                    },
                    surfacesPtr
            )
        }
        return surfaces
    }
}

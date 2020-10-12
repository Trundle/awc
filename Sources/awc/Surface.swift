import Wlroots

enum Surface: Hashable {
    case xdg(surface: UnsafeMutablePointer<wlr_xdg_surface>)
    case xwayland(surface: UnsafeMutablePointer<wlr_xwayland_surface>)
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

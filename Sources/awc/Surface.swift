import Libawc
import Wlroots

// XXX Should this be a protocol instead?
public enum Surface: Hashable {
    case layer(surface: UnsafeMutablePointer<wlr_layer_surface_v1>)
    // XXX wlr…xdg_toplevel instead? It's always an error to create a Surface.xdg for anything else
    case xdg(surface: UnsafeMutablePointer<wlr_xdg_surface>)
    case xwayland(surface: UnsafeMutablePointer<wlr_xwayland_surface>)
}

extension Surface {
    func configure(output: wlr_box, box: wlr_box) {
        switch self {
        case .layer(let layerSurface):
            wlr_layer_surface_v1_configure(layerSurface, UInt32(box.width), UInt32(box.height))
        case .xdg(let xdgSurface):
            wlr_xdg_toplevel_set_size(xdgSurface.pointee.toplevel, box.width, box.height)
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
            wlr_xdg_toplevel_set_tiled(surface.pointee.toplevel, edges)
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
}

extension Surface {
    var title: String  {
        get {
            switch self {
            case .layer: return ""
            case .xdg(let surface): return surface.pointee.toplevel.pointee.title.toString()
            case .xwayland(let surface): return surface.pointee.title.toString()
            }
        }
    }

    var wlrSurface: UnsafeMutablePointer<wlr_surface> {
        get {
            switch self {
            case .layer(let surface): return surface.pointee.surface
            case .xdg(let surface): return surface.pointee.surface
            case .xwayland(let surface): return surface.pointee.surface
            }
        }
    }
}

// MARK: Store and retrieve Surfaces from a scene tree
extension Surface {
    static func from(sceneTree: UnsafeMutablePointer<wlr_scene_tree>) -> Self {
        var maybeTree = Optional.some(sceneTree)
        while let tree = maybeTree {
            if let rawSurfacePtr = tree.pointee.node.data {
                let wlrSurface = rawSurfacePtr.assumingMemoryBound(to: wlr_surface.self)
                if wlr_surface_is_xdg_surface(wlrSurface) {
                    return .xdg(surface: wlr_xdg_surface_from_wlr_surface(wlrSurface))
                } else if wlr_surface_is_xwayland_surface(wlrSurface) {
                    return .xwayland(surface: wlr_xwayland_surface_from_wlr_surface(wlrSurface))
                } else {
                    assert(wlr_surface_is_layer_surface(wlrSurface))
                    return .layer(surface: wlr_layer_surface_v1_from_wlr_surface(wlrSurface))
                }
            }
            maybeTree = tree.pointee.node.parent
        }
        fatalError("Could not find surface for given wlr_scene_tree")
    }

    func store(sceneTree: UnsafeMutablePointer<wlr_scene_tree>) {
        sceneTree.pointee.node.data = UnsafeMutableRawPointer(self.wlrSurface)
    }
}

fileprivate extension Optional where Wrapped == UnsafeMutablePointer<CChar> {
    func toString() -> String {
        if let ptr = self {
            return String(cString: ptr)
        } else {
            return ""
        }
    }
}

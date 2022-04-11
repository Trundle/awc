///
/// Layer Shell support
///
/// Layer Shell is a protocol that allows clients to create surface "layer"s on outputs,
/// for example for toolbars and so on.
///

import Wlroots
import Libawc

protocol LayerShell: AnyObject {
    func newSurface(layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>)
    func surfaceDestroyed(layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>)
    func commit(layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>)
    func map(layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>)
    func unmap(layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>)
}

protocol MappedLayerSurface: AnyObject {
    func newLayerPopup(popup: UnsafeMutablePointer<wlr_xdg_popup>)
}

protocol LayerShellPopup: AnyObject {
    func commit(layerPopupSurface: UnsafeMutablePointer<wlr_xdg_surface>)
    func destroy(layerPopup: UnsafeMutablePointer<wlr_xdg_popup>)
    func map(layerPopupSurface: UnsafeMutablePointer<wlr_xdg_surface>)
}

/// Signal listeners for a mapped layer
struct MappedLayerListener: PListener {
    weak var handler: MappedLayerSurface?
    private var newPopup: wl_listener = wl_listener()

    internal mutating func listen(to layer: UnsafeMutablePointer<wlr_layer_surface_v1>) {
        Self.add(signal: &layer.pointee.events.new_popup, listener: &self.newPopup) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.newPopup, { $0.newLayerPopup(popup: $1) } )
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.newPopup.link)
    }
}

struct LayerShellPopupListener: PListener {
    weak var handler: LayerShellPopup?
    private var commit: wl_listener = wl_listener()
    private var destroy: wl_listener = wl_listener()
    private var map: wl_listener = wl_listener()

    mutating func listen(to popup: UnsafeMutablePointer<wlr_xdg_popup>) {
        Self.add(signal: &popup.pointee.base.pointee.surface.pointee.events.commit, listener: &self.commit) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.commit, { (handler, surface: UnsafeMutablePointer<wlr_surface>) in
                if let xdgSurface = wlr_xdg_surface_from_wlr_surface(surface) {
                    handler.commit(layerPopupSurface: xdgSurface)
                }
            })
        }

        Self.add(signal: &popup.pointee.base.pointee.events.destroy, listener: &self.destroy) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.destroy, { $0.destroy(layerPopup: $1) })
        }

        Self.add(signal: &popup.pointee.base.pointee.events.map, listener: &self.map) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.map, { $0.map(layerPopupSurface: $1) })
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.commit.link)
        wl_list_remove(&self.destroy.link)
        wl_list_remove(&self.map.link)
    }
}

private let layerShellLayers =
    (ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND.rawValue...ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY.rawValue)
    .map { zwlr_layer_shell_v1_layer(rawValue: $0) }

private let layersAboveShell = [
    ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY.rawValue,
    ZWLR_LAYER_SHELL_V1_LAYER_TOP.rawValue
].map { zwlr_layer_shell_v1_layer(rawValue: $0) }

extension Awc: LayerShell {
    func newSurface(layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>) {
        guard let layerShellData: LayerShellData = self.getExtensionData() else {
            wlr_layer_surface_v1_destroy(layerSurface)
            return
        }

        guard layerShellLayers.contains(layerSurface.pointee.current.layer) else {
            wlr_layer_surface_v1_destroy(layerSurface)
            return
        }

        if layerSurface.pointee.output == nil {
            layerSurface.pointee.output = self.viewSet.current.data.output
        }

        if let output = self.viewSet.outputs().first(where: { $0.data.output == layerSurface.pointee.output } ) {
            let layers = layerShellData.layers[output.data.output, default: createLayers()]
            layerShellData.layers[output.data.output] = layers
            guard let layerData = layers[layerSurface.pointee.current.layer] else {
                return
            }
            layerShellData.outputDestroyListeners[layerSurface] =
                OutputDestroyListener.newFor(
                    emitter: output.data.output,
                    handler: LayerShellOutputDestroyedHandler(awc: self, surface: layerSurface)
                )
            self.addListener(layerSurface, LayerSurfaceListener.newFor(emitter: layerSurface, handler: self))

            layerData.unmapped.insert(layerSurface)
            let usableBox = self.arrangeLayers(wlrOutput: output.data.output, layers: layers)
            layerShellData.usableBoxes[output.data.output] = usableBox
        } else {
            wlr_layer_surface_v1_destroy(layerSurface)
        }
    }

    func surfaceDestroyed(layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>) {
        withShellAndLayerData(layerSurface, or: ()) { (layerShellData, layerData) in
            layerData.boxes.removeValue(forKey: layerSurface)
            layerData.mapped.remove(layerSurface)
            layerData.unmapped.remove(layerSurface)

            if let listenerPtr = layerShellData.outputDestroyListeners.removeValue(forKey: layerSurface) {
                if self.viewSet.outputs().contains(where: { $0.data.output == layerSurface.pointee.output }) {
                    listenerPtr.pointee.deregister()

                    guard let layers = layerShellData.layers[layerSurface.pointee.output] else {
                        return
                    }
                    let usableBox = self.arrangeLayers(wlrOutput: layerSurface.pointee.output, layers: layers)
                    layerShellData.usableBoxes[layerSurface.pointee.output] = usableBox

                    self.updateLayout()
                } else if layerData.mapped.isEmpty && layerData.unmapped.isEmpty {
                    // Output no longer exists and this was the last surface
                    layerShellData.usableBoxes.removeValue(forKey: layerSurface.pointee.output)
                    layerShellData.layers.removeValue(forKey: layerSurface.pointee.output)
                }
                listenerPtr.deallocate()
            }
        }
    }

    func commit(layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>) {
        guard let data: LayerShellData = self.getExtensionData() else {
            return
        }
        guard let layers = data.layers[layerSurface.pointee.output] else {
            return
        }

        // XXX layer could change here

        let usableBox = self.arrangeLayers(wlrOutput: layerSurface.pointee.output, layers: layers)
        data.usableBoxes[layerSurface.pointee.output] = usableBox

        withLayerData(layerSurface, or: ()) { layerData in
            if let box = layerData.boxes[layerSurface],
                let output = findOutput(for: layerSurface)
            {
                self.damage(output: output, layerSurface: layerSurface, box: box)
            }
        }
    }

    func map(layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>) {
        withLayerData(layerSurface, or: wlr_layer_surface_v1_destroy(layerSurface)) { layerData in
            layerData.unmapped.remove(layerSurface)
            layerData.mapped.insert(layerSurface)
            wlr_surface_send_enter(layerSurface.pointee.surface, layerSurface.pointee.output)
            self.updateLayout()

            if layersAboveShell.contains(layerSurface.pointee.current.layer) &&
               layerSurface.pointee.current.keyboard_interactive != ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE
            {
                // Theoretically, there could be another interactive layer above this one, but how likely is that?
                self.focus(focus: .layer(surface: layerSurface))
            }

            self.addListener(layerSurface, MappedLayerListener.newFor(emitter: layerSurface, handler: self))
        }
    }

    func unmap(layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>) {
        withLayerData(layerSurface, or: wlr_layer_surface_v1_destroy(layerSurface)) { layerData in
            self.removeListener(layerSurface, MappedLayerListener.self)

            layerData.mapped.remove(layerSurface)
            layerData.unmapped.insert(layerSurface)
            self.updateLayout()
            if layerSurface.pointee.current.keyboard_interactive != ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE  {
                self.focusTop()
            }
        }
    }

    private func damage(output: Output<L>, layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>, box: wlr_box) {
        var damage = pixman_region32_t()
        pixman_region32_init(&damage)
        defer {
            pixman_region32_fini(&damage)
        }

        wlr_surface_get_effective_damage(layerSurface.pointee.surface, &damage)
        pixman_region32_translate(&damage, box.x, box.y)
        wlr_output_damage_add(output.data.damage, &damage)
    }

    private func arrangeLayers(
        wlrOutput: UnsafeMutablePointer<wlr_output>,
        layers: [zwlr_layer_shell_v1_layer: LayerData]
    ) -> wlr_box {
        var usableArea = wlr_box()
        wlr_output_effective_resolution(wlrOutput, &usableArea.width, &usableArea.height)

        for layer in layerShellLayers.reversed() {
            if let layerData = layers[layer] {
                arrangeLayer(
                    wlrOutput: wlrOutput,
                    usableArea: &usableArea,
                    layer: layerData
                )
            }
        }

        return usableArea
    }

    private func arrangeLayer(
        wlrOutput: UnsafeMutablePointer<wlr_output>,
        usableArea: inout wlr_box,
        layer: LayerData
    ) {
        var fullArea = wlr_box()
        wlr_output_effective_resolution(wlrOutput, &fullArea.width, &fullArea.height)
        for layerSurface in layer.unmapped.union(layer.mapped) {
            let bounds: wlr_box
            if layerSurface.pointee.current.exclusive_zone == -1 {
                bounds = fullArea
            } else {
                bounds = wlr_box(x: 0, y: 0, width: usableArea.width, height: usableArea.height)
            }

            let state = layerSurface.pointee.current

            var box = wlr_box(
                x: 0, y: 0,
                width: Int32(state.desired_width),
                height: Int32(state.desired_height)
            )
            let anchor = Anchor.init(rawValue: state.anchor)

            // Horizontal axis
            if anchor.isSuperset(of: [.left, .right]) && box.width == 0 {
                box.x = bounds.x
                box.width = bounds.width
            } else if anchor.contains(.left) {
                box.x = bounds.x
            } else if anchor.contains(.right) {
                box.x = bounds.x + (bounds.width - box.width)
            } else {
                box.x = bounds.x + ((bounds.width / 2) - (box.width / 2))
            }

            // Vertical axis
            if anchor.isSuperset(of: [.top, .bottom]) && box.height == 0 {
                box.y = bounds.y
                box.height = bounds.height
            } else if anchor.contains(.top) {
                box.y = bounds.y
            } else if anchor.contains(.bottom) {
                box.y = bounds.y + (bounds.height - box.height)
            } else {
                box.y = bounds.y + ((bounds.height / 2) - (box.height / 2))
            }

            // Horizontal margin
            if anchor.isSuperset(of: [.left, .right]) {
                box.x += Int32(state.margin.left)
                box.width -= Int32(state.margin.left + state.margin.right)
            } else if anchor.contains(.left) {
                box.x += Int32(state.margin.left)
            } else if anchor.contains(.right) {
                box.x -= Int32(state.margin.right)
            }

            // Vertical margin
            if anchor.isSuperset(of: [.top, .bottom]) {
                box.y += Int32(state.margin.top)
                box.height -= Int32(state.margin.top + state.margin.bottom)
            } else if anchor.contains(.top) {
                box.y += Int32(state.margin.top)
            } else if anchor.contains(.bottom) {
                box.y -= Int32(state.margin.bottom)
            }

            guard box.width > 0 && box.height > 0 else {
                wlr_layer_surface_v1_destroy(layerSurface)
                continue
            }

            applyExclusive(
                usableArea: &usableArea,
                anchor: anchor,
                exclusive: state.exclusive_zone,
                margin: (top: Int32(state.margin.top), bottom: Int32(state.margin.bottom),
                         left: Int32(state.margin.left), right: Int32(state.margin.right))
            )

            wlr_layer_surface_v1_configure(layerSurface, UInt32(box.width), UInt32(box.height))
            layer.boxes[layerSurface] = box
        }
    }

    private func applyExclusive(
        usableArea: inout wlr_box,
        anchor: Anchor,
        exclusive: Int32,
        margin: (top: Int32, bottom: Int32, left: Int32, right: Int32)
    ) {
        guard exclusive > 0 else {
            return
        }

        let edges = [
            // Top
            ( singularAnchor: Anchor.top
            , anchorTriplet: Anchor([Anchor.left, Anchor.right, Anchor.top])
            , margin: margin.top
            , positiveAxis: \wlr_box.y
            , negativeAxis: \wlr_box.height
            ),
            // Bottom
            ( singularAnchor: Anchor.bottom
            , anchorTriplet: Anchor([Anchor.left, Anchor.right, Anchor.bottom])
            , margin: margin.bottom
            , positiveAxis: nil
            , negativeAxis: \wlr_box.height
            ),
            // Left
            ( singularAnchor: Anchor.left
            , anchorTriplet: Anchor([Anchor.left, Anchor.top, Anchor.bottom])
            , margin: margin.bottom
            , positiveAxis: \wlr_box.x
            , negativeAxis: \wlr_box.width
            ),
            // Left
            ( singularAnchor: Anchor.right
            , anchorTriplet: Anchor([Anchor.right, Anchor.top, Anchor.bottom])
            , margin: margin.right
            , positiveAxis: nil
            , negativeAxis: \wlr_box.width
            )
        ]
        for edge in edges {
            if (anchor == [edge.singularAnchor] || anchor == edge.anchorTriplet) && exclusive + edge.margin > 0 {
                if let positiveAxis = edge.positiveAxis {
                    usableArea[keyPath: positiveAxis] += exclusive + edge.margin
                }
                usableArea[keyPath: edge.negativeAxis] -= exclusive + edge.margin
                break
            }
        }
    }

    private func withLayerData(
        _ layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>,
        or: @autoclosure () -> (),
        block: (LayerData) -> ()
    ) {
        withShellAndLayerData(layerSurface, or: or(), block: { (_, layerData) in block(layerData) })
    }

    private func withShellAndLayerData(
        _ layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>,
        or: @autoclosure () -> (),
        block: (LayerShellData, LayerData) -> ()
    ) {
        guard let layerShellData: LayerShellData = self.getExtensionData() else {
            or()
            return
        }

        if let layerData = layerShellData.layers[layerSurface.pointee.output]?[layerSurface.pointee.current.layer] {
            block(layerShellData, layerData)
        } else {
            or()
        }
    }

    fileprivate func findOutput(for layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>) -> Output<L>? {
        self.viewSet.outputs().first(where: { $0.data.output == layerSurface.pointee.output })
    }
}

extension Awc: MappedLayerSurface {
    func newLayerPopup(popup: UnsafeMutablePointer<wlr_xdg_popup>) {
        let parentSurface = parentToplevel(of: popup)
        withLayerData(parentSurface, or: ()) { layerData in
            if let parentBox = layerData.boxes[parentSurface],
               let output = self.findOutput(for: parentSurface)
            {
                let outputBox = output.data.box

                var toplevelSxBox = wlr_box(
                  x: -parentBox.x,
                  y: -parentBox.y,
                  width: outputBox.width,
                  height: outputBox.height
                )
                wlr_xdg_popup_unconstrain_from_box(popup, &toplevelSxBox)
            }
        }
        self.addListener(popup, LayerShellPopupListener.newFor(emitter: popup, handler: self))
    }

    private func parentToplevel(
      of popup: UnsafeMutablePointer<wlr_xdg_popup>
    ) -> UnsafeMutablePointer<wlr_layer_surface_v1> {
        assert(wlr_surface_is_layer_surface(popup.pointee.parent))
        // If we support popups of popups at some point, this isn't good enough
        return wlr_layer_surface_v1_from_wlr_surface(popup.pointee.parent)!
    }
}

extension Awc: LayerShellPopup {
    func commit(layerPopupSurface: UnsafeMutablePointer<wlr_xdg_surface>) {
        damageWhole(popup: layerPopupSurface.pointee.popup)
    }

    func destroy(layerPopup: UnsafeMutablePointer<wlr_xdg_popup>) {
        self.removeListener(layerPopup, LayerShellPopupListener.self)
    }

    func map(layerPopupSurface: UnsafeMutablePointer<wlr_xdg_surface>) {
        let parentSurface = parentToplevel(of: layerPopupSurface.pointee.popup)
        wlr_surface_send_enter(layerPopupSurface.pointee.surface, parentSurface.pointee.output)
        damageWhole(popup: layerPopupSurface.pointee.popup)
    }


    private func damageWhole(popup: UnsafeMutablePointer<wlr_xdg_popup>) {
        let parentSurface = parentToplevel(of: popup)
        withLayerData(parentSurface, or: ()) { layerData in
            if let box = layerData.boxes[parentSurface],
               let output = findOutput(for: parentSurface)
            {
                let surface = popup.pointee.base.pointee.surface
#if WLROOTS_0_14
                let popupSx = popup.pointee.geometry.x - popup.pointee.base.pointee.geometry.x
                let popupSy = popup.pointee.geometry.y - popup.pointee.base.pointee.geometry.y
#else
                let popupSx = popup.pointee.geometry.x - popup.pointee.base.pointee.current.geometry.x
                let popupSy = popup.pointee.geometry.y - popup.pointee.base.pointee.current.geometry.y
#endif

                var damage = pixman_region32_t()
                defer {
                    pixman_region32_fini(&damage)
                }
                wlr_surface_get_effective_damage(surface, &damage)
                pixman_region32_translate(&damage, box.x + popupSx, box.y + popupSy)
                wlr_output_damage_add(output.data.damage, &damage)
            }
        }
    }
}

private func createLayers() -> [zwlr_layer_shell_v1_layer: LayerData] {
    Dictionary(uniqueKeysWithValues: layerShellLayers.map { ($0, LayerData(layer: $0)) })
}

/// Reacts to "output destroyed" events and updates layers (closes surfaces and so on)
private class LayerShellOutputDestroyedHandler<L: Layout>: OutputDestroyedHandler
    where L.View == Surface, L.OutputData == OutputDetails
{
    private unowned let awc: Awc<L>
    private let surface: UnsafeMutablePointer<wlr_layer_surface_v1>

    init(awc: Awc<L>, surface: UnsafeMutablePointer<wlr_layer_surface_v1>) {
        self.awc = awc
        self.surface = surface
    }

    func destroyed(output: UnsafeMutablePointer<wlr_output>) {
        if let data: LayerShellData = self.awc.getExtensionData() {
            if let listenerPtr = data.outputDestroyListeners[self.surface] {
                // Deregister the listener already, as the output goes away
                listenerPtr.pointee.deregister()
            }

            if let exclusiveClient = awc.exclusiveClient {
                // Check if the exclusive client is an interactive layer on the destroyed output
                for layer in layersAboveShell {
                    if let layerData = data.layers[output]?[layer] {
                        if layerData.mapped
                           .filter({ $0.pointee.current.keyboard_interactive != ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE  })
                           .contains(where: { wl_resource_get_client($0.pointee.resource) == exclusiveClient })
                        {
                            // It is - find another layer by this client that can be focused
                            if let newSurface =
                                self.findInteractiveMappedLayerSurfaceBy(client: exclusiveClient, data: data)
                            {
                                awc.focus(focus: .layer(surface: newSurface))
                            }
                        }
                    }
                }
            }

            data.layers.removeValue(forKey: output)
        }
        wlr_layer_surface_v1_destroy(self.surface)
    }

    private func findInteractiveMappedLayerSurfaceBy(
        client: OpaquePointer,
        data: LayerShellData
    ) -> UnsafeMutablePointer<wlr_layer_surface_v1>?
    {
        for output in self.awc.viewSet.outputs() {
            for layer in layersAboveShell {
                if let layerData = data.layers[output.data.output]?[layer] {
                    if let surface = layerData
                        .mapped
                        .filter({ $0.pointee.current.keyboard_interactive != ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE })
                        .first(where: { wl_resource_get_client($0.pointee.resource) == client })
                    {
                        return surface
                    }
                }
            }
        }
        return nil
    }
}

private struct Anchor: OptionSet {
    let rawValue: UInt32

    static let left = Anchor(rawValue: ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT.rawValue)
    static let right = Anchor(rawValue: ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT.rawValue)
    static let top = Anchor(rawValue: ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP.rawValue)
    static let bottom = Anchor(rawValue: ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM.rawValue)
}

/// Bookkeeping data for layer shell.
private class LayerShellData {
    var layers: [UnsafeMutablePointer<wlr_output>: [zwlr_layer_shell_v1_layer: LayerData]] = [:]
    var outputDestroyListeners: [
        UnsafeMutablePointer<wlr_layer_surface_v1>: UnsafeMutablePointer<OutputDestroyListener>
    ] = [:]
    var usableBoxes: [UnsafeMutablePointer<wlr_output>: wlr_box] = [:]
}

/// Data for one layer on one output
private class LayerData {
    let layer: zwlr_layer_shell_v1_layer
    var mapped: Set<UnsafeMutablePointer<wlr_layer_surface_v1>> = []
    var unmapped: Set<UnsafeMutablePointer<wlr_layer_surface_v1>> = []
    var boxes: [UnsafeMutablePointer<wlr_layer_surface_v1>: wlr_box] = [:]

    init(layer: zwlr_layer_shell_v1_layer) {
        self.layer = layer
    }
}

extension zwlr_layer_shell_v1_layer: Hashable {
}

/// Singleton listeners for layer shell.
private struct LayerShellListener: PListener {
    weak var handler: LayerShell?
    private var newSurface: wl_listener = wl_listener()

    internal mutating func listen(to layerShell: UnsafeMutablePointer<wlr_layer_shell_v1>) {
        Self.add(signal: &layerShell.pointee.events.new_surface, listener: &self.newSurface) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.newSurface, { $0.newSurface(layerSurface: $1) })
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.newSurface.link)
    }
}

/// Signal listeners for a layer surface.
private struct LayerSurfaceListener: PListener {
    weak var handler: LayerShell?
    private var commit: wl_listener = wl_listener()
    private var destroy: wl_listener = wl_listener()
    private var map: wl_listener = wl_listener()
    private var unmap: wl_listener = wl_listener()

    internal mutating func listen(to surface: UnsafeMutablePointer<wlr_layer_surface_v1>) {
        Self.add(signal: &surface.pointee.surface.pointee.events.commit, listener: &self.commit) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.commit, { (handler, surface: UnsafeMutablePointer<wlr_surface>) in
                if let layerSurface = wlr_layer_surface_v1_from_wlr_surface(surface) {
                    handler.commit(layerSurface: layerSurface)
                }
            })
        }

        Self.add(signal: &surface.pointee.events.destroy, listener: &self.destroy) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.destroy, { $0.surfaceDestroyed(layerSurface: $1) })
        }

        Self.add(signal: &surface.pointee.events.map, listener: &self.map) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.map, { $0.map(layerSurface: $1) })
        }

        Self.add(signal: &surface.pointee.events.unmap, listener: &self.unmap) { (listener, data) in
            Self.handle(from: listener!, data: data!, \Self.unmap, { $0.unmap(layerSurface: $1) })
        }
    }

    mutating func deregister() {
        wl_list_remove(&self.commit.link)
        wl_list_remove(&self.destroy.link)
        wl_list_remove(&self.map.link)
        wl_list_remove(&self.unmap.link)
    }
}

fileprivate extension wlr_box {
    func contains(box: wlr_box) -> Bool {
        let x2 = self.x + self.width
        let y2 = self.y + self.height
        return self.x <= box.x && self.y <= box.y
            && box.x + box.width <= x2 && box.y + box.height <= y2
    }
}

/// Layout that wraps around another layout and adds all layout shell surfaces.
/// This layout should be before any other layout that modifies boxes, otherwise
/// layer surfaces might be positioned at the wrong place.
final class LayerLayout<WrappedLayout: Layout>: Layout
    where WrappedLayout.View == Surface, WrappedLayout.OutputData == OutputDetails
{
    public typealias View = WrappedLayout.View
    public typealias OutputData = WrappedLayout.OutputData

    public var description: String {
        get {
            self.wrapped.description
        }
    }

    fileprivate let data: LayerShellData
    private let wrapped: WrappedLayout

    init(wrapped: WrappedLayout) {
        self.wrapped = wrapped
        self.data = LayerShellData()
    }

    private init(wrapped: WrappedLayout, data: LayerShellData) {
        self.data = data
        self.wrapped = wrapped
    }

    public func doLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        stack: Stack<Surface>,
        box: wlr_box
    ) -> [(Surface, Set<ViewAttribute>, wlr_box)] where L.View == Surface, L.OutputData == OutputDetails {
        guard let data: LayerShellData = dataProvider.getExtensionData() else {
            return wrapped.doLayout(dataProvider: dataProvider, output: output, stack: stack, box: box)
        }

        // XXX Sway applies exclusive surfaces first, then the non-exclusive ones
        var arrangement: [(Surface, Set<ViewAttribute>, wlr_box)] = []
        for layer in layerShellLayers[0..<(layerShellLayers.count / 2)] {
            addTo(
                arrangement: &arrangement,
                output: output,
                layoutBox: box,
                layer: layer,
                layerShellData: data)
        }

        let usableBox = determineUsableBox(on: output, data: data, box: box)
        arrangement += wrapped.doLayout(dataProvider: dataProvider, output: output, stack: stack, box: usableBox)

        for layer in layerShellLayers[(layerShellLayers.count / 2)...] {
            addTo(
                arrangement: &arrangement,
                output: output,
                layoutBox: box,
                layer: layer,
                layerShellData: data)
        }

        return arrangement
    }

    public func emptyLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        box: wlr_box
    ) -> [(Surface, Set<ViewAttribute>, wlr_box)] where L.View == Surface, L.OutputData == OutputDetails {
        var arrangement: [(Surface, Set<ViewAttribute>, wlr_box)] = []

        if let data: LayerShellData = dataProvider.getExtensionData() {
            for layer in layerShellLayers {
                addTo(
                    arrangement: &arrangement,
                    output: output,
                    layoutBox: box,
                    layer: layer,
                    layerShellData: data)
            }
        }

        return arrangement
    }

    func firstLayout() -> LayerLayout<WrappedLayout> {
        LayerLayout(wrapped: self.wrapped.firstLayout())
    }

    func nextLayout() -> LayerLayout<WrappedLayout>? {
        if let next = wrapped.nextLayout() {
            return LayerLayout(wrapped: next, data: self.data)
        } else {
            return nil
        }
    }

    func expand() -> LayerLayout<WrappedLayout> {
        LayerLayout(wrapped: self.wrapped.expand(), data: self.data)
    }

    func shrink() -> LayerLayout<WrappedLayout> {
        LayerLayout(wrapped: self.wrapped.shrink(), data: self.data)
    }

    private func addTo<L: Layout>(
        arrangement: inout [(Surface, Set<ViewAttribute>, wlr_box)],
        output: Output<L>,
        layoutBox: wlr_box,
        layer: zwlr_layer_shell_v1_layer,
        layerShellData: LayerShellData
    ) where L.OutputData == OutputDetails {
        if let layer = layerShellData.layers[output.data.output]?[layer] {
            for (layerSurface, box) in layer.boxes {
                if layoutBox.contains(box: box) && layer.mapped.contains(layerSurface) {
                    arrangement.append((Surface.layer(surface: layerSurface), [.undecorated], box))
                }
            }
        }
    }

    private func determineUsableBox<L: Layout>(
        on output: Output<L>,
        data: LayerShellData,
        box: wlr_box
    ) -> wlr_box where L.OutputData == OutputDetails {
        if let usableBox = data.usableBoxes[output.data.output], box.contains(box: usableBox) {
            return usableBox
        } else {
            return box
        }
    }
}


#if WLROOTS_0_14
private func wlr_layer_surface_v1_destroy(_ surface: UnsafeMutablePointer<wlr_layer_surface_v1>) {
    wlr_layer_surface_v1_close(surface)
}
#endif


func layerViewAt<L: Layout>(
  delegate: ViewAtHook<L>,
  awc: Awc<L>,
  x: Double,
  y: Double
) -> (Surface, UnsafeMutablePointer<wlr_surface>, Double, Double)?
{
    if let data: LayerShellData = awc.getExtensionData() {
        if let output = awc.viewSet.outputs().first(where: { $0.data.box.contains(x: Int(x), y: Int(y)) }),
           let layers = data.layers[output.data.output]?.values
        {
            let outputBox = output.data.box
            let outputX = x - Double(outputBox.x)
            let outputY = y - Double(outputBox.y)
            for layer in layers {
                for (layerSurface, box) in layer.boxes {
                    let sx = outputX - Double(box.x)
                    let sy = outputY - Double(box.y)
                    var subX: Double = 0
                    var subY: Double = 0
                    if let childSurface = wlr_layer_surface_v1_surface_at(layerSurface, sx, sy, &subX, &subY),
                       childSurface.isXdgPopup()
                    {
                        return (Surface.layer(surface: layerSurface), childSurface, subX, subY)
                    }
                }
            }
        }
    }

    return delegate(awc, x, y)
}

func setupLayerShell<L: Layout>(display: OpaquePointer, awc: Awc<L>) {
    guard let layerShell = wlr_layer_shell_v1_create(display) else {
        print("[DEBUG] Could not create Layer Shell")
        return
    }

    awc.addExtensionData(LayerShellData())
    awc.addListener(layerShell, LayerShellListener.newFor(emitter: layerShell, handler: awc))
}

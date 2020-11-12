///
/// Layer Shell support
///
/// Layer Shell is a protocol that allows clients to create surface "layer"s on outputs,
/// for example for toolbars and so on.
///

import Wlroots
import Libawc

protocol LayerShell: class {
    func newSurface(layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>)
    func surfaceDestroyed(layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>)
    func commit(layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>)
    func map(layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>)
    func unmap(layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>)
}

let layerShellLayers =
    (ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND.rawValue...ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY.rawValue)
    .map { zwlr_layer_shell_v1_layer(rawValue: $0) }

extension Awc: LayerShell {
    func newSurface(layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>) {
        // XXX handle popups as well
        guard let layerShellData: LayerShellData = self.getExtensionData() else {
            wlr_layer_surface_v1_close(layerSurface)
            return
        }

        guard layerShellLayers.contains(layerSurface.pointee.current.layer) else {
            wlr_layer_surface_v1_close(layerSurface)
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
            wlr_layer_surface_v1_close(layerSurface)
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
    }

    func map(layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>) {
        withLayerData(layerSurface, or: wlr_layer_surface_v1_close(layerSurface)) { layerData in
            layerData.unmapped.remove(layerSurface)
            layerData.mapped.insert(layerSurface)
            wlr_surface_send_enter(layerSurface.pointee.surface, layerSurface.pointee.output)
            self.updateLayout()
        }
    }

    func unmap(layerSurface: UnsafeMutablePointer<wlr_layer_surface_v1>) {
        withLayerData(layerSurface, or: wlr_layer_surface_v1_close(layerSurface)) { layerData in
            layerData.mapped.remove(layerSurface)
            layerData.unmapped.insert(layerSurface)
        }
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
                wlr_layer_surface_v1_close(layerSurface)
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
        }
        wlr_layer_surface_v1_close(self.surface)
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

/// Layout that wraps around another layout and adds all layout shell surfaces.
final class LayerLayout<WrappedLayout: Layout>: Layout
    where WrappedLayout.View == Surface, WrappedLayout.OutputData == OutputDetails
{
    public typealias View = WrappedLayout.View
    public typealias OutputData = WrappedLayout.OutputData

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
    ) -> [(Surface, wlr_box)] where L.View == Surface, L.OutputData == OutputDetails {
        guard let data: LayerShellData = dataProvider.getExtensionData() else {
            return wrapped.doLayout(dataProvider: dataProvider, output: output, stack: stack, box: box)
        }

        // XXX Sway applies exclusive surfaces first, then the non-exclusive ones
        var arrangement: [(Surface, wlr_box)] = []
        for layer in layerShellLayers[0..<(layerShellLayers.count / 2)] {
            addTo(arrangement: &arrangement, output: output, layer: layer, layerShellData: data)
        }

        let usableBox = data.usableBoxes[output.data.output] ?? box
        arrangement += wrapped.doLayout(dataProvider: dataProvider, output: output, stack: stack, box: usableBox)

        for layer in layerShellLayers[(layerShellLayers.count / 2)...] {
            addTo(arrangement: &arrangement, output: output, layer: layer, layerShellData: data)
        }

        return arrangement
    }

    public func emptyLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        box: wlr_box
    ) -> [(Surface, wlr_box)] where L.View == Surface, L.OutputData == OutputDetails {
        var arrangement: [(Surface, wlr_box)] = []

        if let data: LayerShellData = dataProvider.getExtensionData() {
            for layer in layerShellLayers {
                addTo(arrangement: &arrangement, output: output, layer: layer, layerShellData: data)
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

    private func addTo<L: Layout>(
        arrangement: inout [(Surface, wlr_box)],
        output: Output<L>,
        layer: zwlr_layer_shell_v1_layer,
        layerShellData: LayerShellData
    ) where L.OutputData == OutputDetails {
        if let layer = layerShellData.layers[output.data.output]?[layer] {
            for (layerSurface, box) in layer.boxes {
                if layer.mapped.contains(layerSurface) {
                    arrangement.append((Surface.layer(surface: layerSurface), box))
                }
            }
        }
    }
}

func setupLayerShell<L: Layout>(display: OpaquePointer, awc: Awc<L>) {
    guard let layerShell = wlr_layer_shell_v1_create(display) else {
        print("[DEBUG] Could not create Layer Shell")
        return
    }

    awc.addExtensionData(LayerShellData())
    awc.addListener(layerShell, LayerShellListener.newFor(emitter: layerShell, handler: awc))
}

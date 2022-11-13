///
/// Layer Shell support
///
/// Layer Shell is a protocol that allows clients to create surface "layer"s on outputs,
/// for example for toolbars and so on.
///

import DataStructures
import Wlroots
import Libawc
import Logging

fileprivate let logger = Logger(label: "LayerShell")

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

private let layerShellLayers =
    (ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND.rawValue...ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY.rawValue)
    .map { zwlr_layer_shell_v1_layer(rawValue: $0) }

private let layersAboveShell = [
    ZWLR_LAYER_SHELL_V1_LAYER_TOP.rawValue,
    ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY.rawValue,
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
            let layers = self.getOrCreateLayers(for: output, shellData: layerShellData)
            guard let layerData = layers[layerSurface.pointee.current.layer] else {
                return
            } 
            self.addListener(layerSurface, LayerSurfaceListener.newFor(emitter: layerSurface, handler: self))

            guard let sceneSurface = wlr_scene_layer_surface_v1_create(layerData.sceneTree, layerSurface) else {
                logger.warning("Could not create scene layer for layer surface: out of memory")
                return
            }
            Surface.layer(surface: layerSurface).store(sceneTree: sceneSurface.pointee.tree)
            withUnsafeMutablePointer(to: &sceneSurface.pointee.tree.pointee.node) {
                layerData.sceneSurfaces[$0] = sceneSurface
            }

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

            if self.viewSet.outputs().contains(where: { $0.data.output == layerSurface.pointee.output }) {
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

    private func getOrCreateLayers(
        for output: Output<L>,
        shellData: LayerShellData
    ) -> [zwlr_layer_shell_v1_layer: LayerData] {
        let layers = shellData.layers[output.data.output, default: {
            let outputDestroyedHandler: LayerShellOutputDestroyedHandler<L>? = self.getExtensionData()
            shellData.outputDestroyListeners[output.data.output] =
                OutputDestroyListener.newFor(
                    emitter: output.data.output,
                    handler: outputDestroyedHandler!
                )
            let layers = createLayers()
            let outputLayoutBox = output.data.box
            for layer in layers.values {
                wlr_scene_node_set_position(&layer.sceneTree.pointee.node, outputLayoutBox.x, outputLayoutBox.y)
            }
            return layers
        }()]
        shellData.layers[output.data.output] = layers
        return layers
    }

    private func arrangeLayers(
        wlrOutput: UnsafeMutablePointer<wlr_output>,
        layers: [zwlr_layer_shell_v1_layer: LayerData]
    ) -> wlr_box {
        var usableArea = wlr_box()
        wlr_output_effective_resolution(wlrOutput, &usableArea.width, &usableArea.height)

        var fullArea = usableArea

        for layer in layerShellLayers.reversed() {
            if let layerData = layers[layer] {
                arrangeLayer(
                    wlrOutput: wlrOutput,
                    fullArea: &fullArea,
                    usableArea: &usableArea,
                    layer: layerData
                )
            }
        }

        return usableArea
    }

    private func arrangeLayer(
        wlrOutput: UnsafeMutablePointer<wlr_output>,
        fullArea: inout wlr_box,
        usableArea: inout wlr_box,
        layer: LayerData
    ) {
        for node in layer.sceneTree.pointee.children.sequence(\wlr_scene_node.link) {
            if let surface = layer.sceneSurfaces[node] {
                wlr_scene_layer_surface_v1_configure(surface, &fullArea, &usableArea)
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

    fileprivate func createLayers() -> [zwlr_layer_shell_v1_layer: LayerData] {
        var result: [zwlr_layer_shell_v1_layer: LayerData] = [:]
        var parentTree = self.sceneLayers.background
        for layer in layerShellLayers {
            let layerData = LayerData(layer: layer, parentTree: parentTree)
            result[layer] = layerData
            parentTree = layerData.sceneTree
        }

        for (layer, tree) in zip(layersAboveShell, [self.sceneLayers.floating, self.sceneLayers.overlay]) {
            let layerData = result[layer]!
            wlr_scene_node_reparent(&layerData.sceneTree.pointee.node, tree)
        }

        return result
    }
}

extension Awc: MappedLayerSurface {
    func newLayerPopup(popup: UnsafeMutablePointer<wlr_xdg_popup>) {
        let parentSurface = parentToplevel(of: popup)
        withLayerData(parentSurface, or: ()) { layerData in
            for sceneSurface in layerData.sceneSurfaces.values {
                if sceneSurface.pointee.layer_surface == parentSurface {
                    wlr_scene_xdg_surface_create(sceneSurface.pointee.tree, popup.pointee.base)

                    if let output = self.findOutput(for: parentSurface) {
                        let outputBox = output.data.box

                        var lx: Int32 = 0
                        var ly: Int32 = 0
	                    wlr_scene_node_coords(&sceneSurface.pointee.tree.pointee.node, &lx, &ly)

                        var toplevelSxBox = wlr_box(
                          x: outputBox.x - lx,
                          y: outputBox.y - ly,
                          width: outputBox.width,
                          height: outputBox.height
                        )
                        wlr_xdg_popup_unconstrain_from_box(popup, &toplevelSxBox)
                    }
                    break
                }
            }
        }
    }

    private func parentToplevel(
      of popup: UnsafeMutablePointer<wlr_xdg_popup>
    ) -> UnsafeMutablePointer<wlr_layer_surface_v1> {
        assert(wlr_surface_is_layer_surface(popup.pointee.parent))
        // If we support popups of popups at some point, this isn't good enough
        return wlr_layer_surface_v1_from_wlr_surface(popup.pointee.parent)!
    }
}

/// Reacts to "output destroyed" events and updates layers (closes surfaces and so on)
private class LayerShellOutputDestroyedHandler<L: Layout>: OutputDestroyedHandler
    where L.View == Surface, L.OutputData == OutputDetails
{
    private unowned let awc: Awc<L>

    init(awc: Awc<L>) {
        self.awc = awc
    }

    func destroyed(output: UnsafeMutablePointer<wlr_output>) {
        if let data: LayerShellData = self.awc.getExtensionData() {
            if let listenerPtr = data.outputDestroyListeners.removeValue(forKey: output) {
                // Deregister the listener already, as the output goes away
                listenerPtr.pointee.deregister()
                listenerPtr.deallocate()
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

            // Destroy all layer surfaces on this output and remove layer trees from the scene graph
            // We go from top to bottom because scene tree nodes can be children of another layer
            for layer in layerShellLayers.reversed() {
                if let layerData = data.layers[output]?[layer] {
                    for surface in layerData.mapped.union(layerData.unmapped) {
                        wlr_layer_surface_v1_destroy(surface)
                    }
                    wlr_scene_node_destroy(&layerData.sceneTree.pointee.node)
                }
            }

            data.layers.removeValue(forKey: output)
        }
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

/// Bookkeeping data for layer shell.
private class LayerShellData {
    var layers: [UnsafeMutablePointer<wlr_output>: [zwlr_layer_shell_v1_layer: LayerData]] = [:]
    var outputDestroyListeners: [
        UnsafeMutablePointer<wlr_output>: UnsafeMutablePointer<OutputDestroyListener>
    ] = [:]
    var usableBoxes: [UnsafeMutablePointer<wlr_output>: wlr_box] = [:]
}

/// Data for one layer on one output
private class LayerData {
    let layer: zwlr_layer_shell_v1_layer
    let sceneTree: UnsafeMutablePointer<wlr_scene_tree>
    var sceneSurfaces: [UnsafeMutablePointer<wlr_scene_node>: UnsafeMutablePointer<wlr_scene_layer_surface_v1>] = [:]
    var mapped: Set<UnsafeMutablePointer<wlr_layer_surface_v1>> = []
    var unmapped: Set<UnsafeMutablePointer<wlr_layer_surface_v1>> = []
    var boxes: [UnsafeMutablePointer<wlr_layer_surface_v1>: wlr_box] = [:]

    init(layer: zwlr_layer_shell_v1_layer, parentTree: UnsafeMutablePointer<wlr_scene_tree>) {
        self.layer = layer
        self.sceneTree = wlr_scene_tree_create(parentTree)
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

    private let wrapped: WrappedLayout

    init(wrapped: WrappedLayout) {
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
            return LayerLayout(wrapped: next)
        } else {
            return nil
        }
    }

    func expand() -> LayerLayout<WrappedLayout> {
        LayerLayout(wrapped: self.wrapped.expand())
    }

    func shrink() -> LayerLayout<WrappedLayout> {
        LayerLayout(wrapped: self.wrapped.shrink())
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

func setupLayerShell<L: Layout>(display: OpaquePointer, awc: Awc<L>) {
    guard let layerShell = wlr_layer_shell_v1_create(display) else {
        fatalError("Could not create Layer Shell")
    }

    awc.addExtensionData(LayerShellOutputDestroyedHandler(awc: awc))
    awc.addExtensionData(LayerShellData())
    awc.addListener(layerShell, LayerShellListener.newFor(emitter: layerShell, handler: awc))
}

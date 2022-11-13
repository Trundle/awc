import Glibc

import ClientCommons
import Gles2ext
import EGlext
import LayerShellClient
import Logging
import LogHandlers
import NeonRenderer


fileprivate let namespace = "OutputHUD"
fileprivate var logger: Logger!

public class State {
    let eglDisplay: EGLDisplay
    let eglContext: EGLContext
    let eglSurface: EGLSurface
    let wlSurface: TypedOpaque<WlSurface>
    let outputName: String
    let width: Int32
    let height: Int32
    var workspace: AwcWorkspace
    var keepRunning: Bool = true
    var scale: Float = 1.0

    init(
        eglDisplay: EGLDisplay,
        eglContext: EGLContext,
        eglSurface: EGLSurface,
        wlSurface: TypedOpaque<WlSurface>,
        outputName: String,
        width: Int32,
        height: Int32,
        workspace: AwcWorkspace
    ) {
        self.eglDisplay = eglDisplay
        self.eglContext = eglContext
        self.eglSurface = eglSurface
        self.wlSurface = wlSurface
        self.outputName = outputName
        self.width = width
        self.height = height
        self.workspace = workspace

        // Keep one reference alive that will be freed with done()
        let _ = Unmanaged.passRetained(self)
    }

    func done() {
        Unmanaged.passUnretained(self).release()
    }
}

struct WlSurface {}

class FrameListener {
    private static var listener = wl_callback_listener()
    private static var listenerInitialized = false

    private let state: State
    private let outputHud: OutputHud

    init(state: State, outputHud: OutputHud) {
        if !Self.listenerInitialized {
            Self.initializeListener()
        }
        self.state = state
        self.outputHud = outputHud
    }

    func listen(_ callback: OpaquePointer) {
        wl_callback_add_listener(
            callback,
            &Self.listener,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private static func initializeListener() {
        Self.listener.done = { data, cb, _ in
            wl_callback_destroy(cb)
            let this: FrameListener = Unmanaged.fromOpaque(data!).takeUnretainedValue()
            render(state: this.state, frameListener: this, this.outputHud)
        }
        Self.listenerInitialized = true
    }
}

fileprivate func render(state: State, frameListener: FrameListener, _ outputHud: OutputHud) {
    guard state.keepRunning else { return }

    renderGl(display: state.eglDisplay, context: state.eglContext, surface: state.eglSurface) {
        glViewport(0, 0, state.width, state.height)

        glClearColor(0, 0, 0, 0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

        outputHud.render(state: state)
        eglSwapBuffers(state.eglDisplay, state.eglSurface)
    }

    let frameCallback = wl_surface_frame(state.wlSurface.get(as: WlSurface.self))
    frameListener.listen(frameCallback!)
}

func main() throws {
    LoggingSystem.bootstrap { _ in AnsiLogHandler(logLevel: .info) }
    logger = Logger(label: "OutputHUD")
    var state: State! = nil
    guard let display = wl_display_connect(nil) else {
        logger.critical("Could not connect to Wayland")
        return
    }
    defer {
        // Make sure everything is cleaned up
        wl_display_roundtrip(display)

        wl_display_disconnect(display)
        
        state.done()
    }

    let registryListener = RegistryListener(display)
    wl_display_roundtrip(display)
    // Another roundtrip to retrieve output names
    wl_display_roundtrip(display)
    guard registryListener.hasAllGlobals() else {
        return
    }

    guard let (eglDisplay, eglConfig, eglContext, eglCreatePlatformWindowSurfaceExt) = eglInit(display: display) else {
        return
    }

    let awcOutputs = try getAwcOutputs()
    // The first awc output is the active one
    guard let output = registryListener.getOutput(name: awcOutputs[0].name) else {
        logger.critical("Could not find output \(awcOutputs[0].name)")
        return
    }
    guard let (width, height) = getSize(output: output, wlDisplay: display, registryListener) else {
        logger.critical("Could not determine output size for output \(awcOutputs[0].name)")
        return
    }

    guard let wlSurface: TypedOpaque<WlSurface> = TypedOpaque(
        wl_compositor_create_surface(registryListener.get(WlCompositor.self))
    ) else {
        logger.critical("Could not create surface")
        return
    }

    let layerSurfaceUntyped = namespace.withCString {
        zwlr_layer_shell_v1_get_layer_surface(
            registryListener.get(LayerShell.self),
            wlSurface.get(as: WlSurface.self),
            output.output,
            ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY.rawValue,
            $0)
    }
    guard let layerSurface: TypedOpaque<LayerSurface> = TypedOpaque(layerSurfaceUntyped) else {
        logger.critical("Could not get layer shell surface")
        return
    }
    defer {
        zwlr_layer_surface_v1_destroy(layerSurface.get(as: LayerSurface.self))
    }
    zwlr_layer_surface_v1_set_size(layerSurface.get(as: LayerSurface.self), UInt32(width), UInt32(height))
    zwlr_layer_surface_v1_set_anchor(layerSurface.get(as: LayerSurface.self), 0)
    let layerSurfaceListener = LayerSurfaceListener(layerSurface)
    wl_surface_commit(wlSurface.get(as: WlSurface.self))
    wl_display_roundtrip(display)
    assert(layerSurfaceListener.width > 0)
    assert(layerSurfaceListener.height > 0)

    guard let eglWindow = eglWindowCreate(
        surface: wlSurface.get(as: WlSurface.self),
        width: Int32(layerSurfaceListener.width),
        height: Int32(layerSurfaceListener.height)
    ) else {
        logger.critical("Could not create EGL window")
        return
    }

    let eglSurface = eglCreatePlatformWindowSurfaceExt(
        eglDisplay, 
        eglConfig, 
        UnsafeMutableRawPointer(eglWindow.get(as: EGLWindow.self)),
        nil)
    guard eglSurface != EGL_NO_SURFACE else {
        logger.critical("Could not create EGL surface")
        return
    }
    wl_display_roundtrip(display)

    state = State(
        eglDisplay: eglDisplay,
        eglContext: eglContext,
        eglSurface: eglSurface!,
        wlSurface: wlSurface,
        outputName: output.name,
        width: Int32(layerSurfaceListener.width),
        height: Int32(layerSurfaceListener.height),
        workspace: awcOutputs[0].workspace)
    
    let outputHud = OutputHud()
    // XXX font & colors
    let colors = AwcOutputHudColors(
        active_background: AwcColor(r: 0x60, g: 0xa8, b: 0x6f, a: 0xb2),
        active_foreground: AwcColor(r: 0xff, g: 0xff, b: 0xff, a: 0xff),
        active_glow: AwcColor(r: 0x92, g: 0xff, b: 0xf1, a: 0xb2),
        inactive_background: AwcColor(r: 0x9e, g: 0x22, b: 0x91, a: 0xb2),
        inactive_foreground: AwcColor(r: 0xff, g: 0xff, b: 0xff, a: 0xff)
    )

    let frameListener = FrameListener(state: state, outputHud: outputHud)
    let update = {
        outputHud.update(state: state, font: "PragmataPro Mono Liga", colors: colors)
        render(state: state, frameListener: frameListener, outputHud)
    }
    update()

    run(wlDisplay: display, state: state, update: update)

    registryListener.done()
}

try main()

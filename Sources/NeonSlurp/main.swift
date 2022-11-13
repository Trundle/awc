import Glibc
// N.B. Foundation isn't used, but it results in libdispatch.so rpath being set
// in the resulting executable
import Foundation
import Logging

import Cairo
import ClientCommons
import CXkbCommon
import DataStructures
import EGlext
import Gles2ext
import LayerShellClient
import LogHandlers
import NeonRenderer

fileprivate let namespace = "NeonSlurp"
fileprivate var logger: Logger!

struct WlFrameCallback {}
struct WlKeyboard {}
struct WlPointer {}
struct WlSurface {}
struct XkbContext {}
struct XkbState {}

class KeyboardListener {
    private let context: TypedOpaque<XkbContext>
    private let keyPressedCallback: (xkb_keysym_t) -> ()
    private var listener = wl_keyboard_listener()
    private var state: TypedOpaque<XkbState>?

    init(
        _ pointer: TypedOpaque<WlKeyboard>,
        context: TypedOpaque<XkbContext>,
        keyPressed: @escaping (xkb_keysym_t) -> ()
    ) {
        self.context = context
        self.keyPressedCallback = keyPressed
        self.initializeListener()

        wl_keyboard_add_listener(
            pointer.get(as: WlKeyboard.self),
            &self.listener,
            Unmanaged.passUnretained(self).toOpaque())
    }

    private func initializeListener() {
        self.listener.keymap = { data, _, format, fd, size in
            if format == WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1.rawValue {
                guard let buffer = mmap(nil, Int(size) - 1, PROT_READ, MAP_PRIVATE, fd, 0) else {
                    logger.error("mmap() failed: \(errno)")
                    return
                }
                defer {
                    munmap(buffer, Int(size) - 1)
                    close(fd)
                }
                let this: KeyboardListener = Unmanaged.fromOpaque(data!).takeUnretainedValue()
                let keymap = xkb_keymap_new_from_buffer(
                    this.context.get(as: XkbContext.self),
                    buffer,
                    Int(size) - 1,
                    XKB_KEYMAP_FORMAT_TEXT_V1,
                    XKB_KEYMAP_COMPILE_NO_FLAGS)
                this.state = TypedOpaque(xkb_state_new(keymap))
            }
        }
        self.listener.enter = { _, _, _, _, _ in }
        self.listener.leave = { _, _, _, _ in }
        self.listener.key = { data, _, _, _, key, keyState in
            let this: KeyboardListener = Unmanaged.fromOpaque(data!).takeUnretainedValue()
            guard let state = this.state else {
                logger.warning("Got key event without keymap")
                return
            }
            // + 8 to translate libinput keycode to xkbcommon
            let keysym = xkb_state_key_get_one_sym(state.get(as: XkbState.self), key + 8)
            if keyState == WL_KEYBOARD_KEY_STATE_PRESSED.rawValue {
                this.keyPressedCallback(keysym)
            }
        }
        self.listener.modifiers = { _, _, _, _, _, _, _ in }
        self.listener.repeat_info = { _, _, _, _ in }
    }
}

class PointerListener {
    private var listener = wl_pointer_listener()
    private let enterCallback: (TypedOpaque<WlSurface>) -> ()
    private let pressedCallback: (UInt32) -> ()
    private let releasedCallback: (UInt32) -> ()
    private let motionCallback: (Int32, Int32) -> ()

    init(
        _ pointer: TypedOpaque<WlPointer>,
        enter: @escaping (TypedOpaque<WlSurface>) -> (),
        pressed: @escaping (UInt32) -> (),
        released: @escaping (UInt32) -> (),
        motion: @escaping (Int32, Int32) -> ()
    ) {
        self.enterCallback = enter
        self.pressedCallback = pressed
        self.releasedCallback = released
        self.motionCallback = motion
        self.initializeListener()

        wl_pointer_add_listener(
            pointer.get(as: WlPointer.self),
            &self.listener,
            Unmanaged.passUnretained(self).toOpaque())
    }

    private func initializeListener() {
        self.listener.enter = { data, _, _, surface, _ , _ in
            let this: PointerListener = Unmanaged.fromOpaque(data!).takeUnretainedValue()
            this.enterCallback(TypedOpaque(surface!))
        }
        self.listener.leave = { _, _, _, _ in }
        self.listener.motion = { data, _, _, surfaceX, surfaceY in
            let this: PointerListener = Unmanaged.fromOpaque(data!).takeUnretainedValue()
            this.motionCallback(surfaceX, surfaceY)
        }
        self.listener.button = { data, _, _, _, button, buttonState in
            let this: PointerListener = Unmanaged.fromOpaque(data!).takeUnretainedValue()
            if buttonState == WL_POINTER_BUTTON_STATE_PRESSED.rawValue {
                this.pressedCallback(button)
            } else if buttonState == WL_POINTER_BUTTON_STATE_RELEASED.rawValue {
                this.releasedCallback(button)
            }
        }
        self.listener.axis = { _, _, _, _, _ in }
        self.listener.frame = { _, _ in }
        self.listener.axis_source = { _, _, _ in }
        self.listener.axis_stop = { _, _, _, _ in }
        self.listener.axis_discrete = { _, _ , _, _ in }
    }
}

private func setWithinBounds(_ box: inout Box, x: Int32, y: Int32, maxX: Int32, maxY: Int32) {
    box.x = min(max(x, 0), maxX - box.width)
    box.y = min(max(y, 0), maxY - box.height)
}

private func drawResizeFrame(frame: Box, color: float_rgba) -> [(Box, float_rgba)] {
    let highlight = float_rgba(r: 1, g: 1, b: 1, a: 1)
    var rects: [(Box, float_rgba)] = [
        (frame, color),
        // Outer glow
        (Box(x: frame.x, y: frame.y, width: frame.width, height: 2), highlight),
        (Box(x: frame.x, y: frame.y + frame.height, width: frame.width, height: 2), highlight),
        (Box(x: frame.x, y: frame.y, width: 2, height: frame.height), highlight),
        (Box(x: frame.x + frame.width, y: frame.y, width: 2, height: frame.height), highlight),
    ]

    // Draw grid
    let gridSize: Int32 = 150
    for y in stride(from: frame.y + gridSize, to: frame.y + frame.height, by: Int(gridSize)) {
        rects.append((Box(x: frame.x, y: y, width: frame.width, height: 2), highlight))
    }
    for x in stride(from: frame.x + gridSize, to: frame.x + frame.width, by: Int(gridSize)) {
        rects.append((Box(x: x, y: frame.y, width: 2, height: frame.height), highlight))
    }

    return rects
}

func createOutputSurface(
    for output: Output,
    display: OpaquePointer,
    registryListener: RegistryListener,
    eglDisplay: EGLDisplay,
    eglConfig: EGLConfig,
    eglCreatePlatformWindowSurfaceExt: PFNEGLCREATEPLATFORMWINDOWSURFACEEXTPROC
) -> (LayerSurfaceListener, TypedOpaque<WlSurface>, EGLSurface, TypedOpaque<LayerSurface>, (Int32, Int32))? {
    guard let ((x, y), (width, height)) = getPositionAndSize(
        output: output,
        wlDisplay: display,
        registryListener
    ) else {
        logger.critical("Could not determine output size for output \(output.name)")
        return nil
    }

    guard let wlSurface: TypedOpaque<WlSurface> = TypedOpaque(
        wl_compositor_create_surface(registryListener.get(WlCompositor.self))
    ) else {
        logger.critical("Could not create surface")
        return nil
    }

    guard let layerSurface: TypedOpaque<LayerSurface> = TypedOpaque(namespace.withCString {
        zwlr_layer_shell_v1_get_layer_surface(
            registryListener.get(LayerShell.self),
            wlSurface.get(as: WlSurface.self),
            output.output,
            ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY.rawValue,
            $0)
    }) else {
        logger.critical("Could not get layer shell surface")
        return nil
    }
    zwlr_layer_surface_v1_set_size(layerSurface.get(as: LayerSurface.self), UInt32(width), UInt32(height))
    zwlr_layer_surface_v1_set_anchor(
        layerSurface.get(as: LayerSurface.self),
        ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP.rawValue |
        ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT.rawValue |
        ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT.rawValue |
        ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM.rawValue)
    zwlr_layer_surface_v1_set_keyboard_interactivity(layerSurface.get(as: LayerSurface.self), 1)
    zwlr_layer_surface_v1_set_exclusive_zone(layerSurface.get(as: LayerSurface.self), -1)
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
        return nil
    }

    let eglSurface = eglCreatePlatformWindowSurfaceExt(
        eglDisplay,
        eglConfig,
        UnsafeMutableRawPointer(eglWindow.get(as: EGLWindow.self)),
        nil)
    guard eglSurface != EGL_NO_SURFACE else {
        logger.critical("Could not create EGL surface")
        return nil
    }
    wl_display_roundtrip(display)

    return (layerSurfaceListener, wlSurface, eglSurface!, layerSurface, (x, y))
}

class FrameListener {
    private let calledCallback: () -> ()
    private var listener = wl_callback_listener()

    init(_ callback: TypedOpaque<WlFrameCallback>, called: @escaping () -> ()) {
        self.calledCallback = called
        self.listener.done = { data, cb, _ in
            wl_callback_destroy(cb)
            let this: FrameListener = Unmanaged.fromOpaque(data!).takeUnretainedValue()
            this.calledCallback()
        }
        wl_callback_add_listener(
            callback.get(as: WlFrameCallback.self),
            &self.listener,
            Unmanaged.passUnretained(self).toOpaque())
    }
}

class OutputState {
    fileprivate let eglSurface: EGLSurface
    fileprivate let wlSurface: TypedOpaque<WlSurface>
    fileprivate let x: Int32
    fileprivate let y: Int32
    fileprivate let width: Int32
    fileprivate let height: Int32

    public init(
        eglSurface: EGLSurface,
        wlSurface: TypedOpaque<WlSurface>,
        x: Int32,
        y: Int32,
        width: Int32,
        height: Int32
    ) {
        self.eglSurface = eglSurface
        self.wlSurface = wlSurface
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

class App {
    private let display: EGLDisplay
    private let context: EGLContext
    private let outputs: [TypedOpaque<WlSurface>: OutputState]
    private let neonRenderer = NeonRenderer()
    private var outputBySeat: [Seat: OutputState] = [:]
    private var pointer: [Seat: (Int32, Int32)] = [:]
    private var vertices: [Seat: (Int32, Int32)] = [:]
    private var buttonPressed: [Seat: Bool] = [:]
    private var frameCallbacks: [TypedOpaque<WlSurface>: FrameListener] = [:]
    var keepRunning: Bool = true
    var regionSelected: Bool = false

    public init(
        display: EGLDisplay,
        context: EGLContext,
        outputs: [OutputState]
    ) {
        self.display = display
        self.context = context
        self.outputs = Dictionary(uniqueKeysWithValues: outputs.map { ($0.wlSurface, $0) })
    }

    func render(on output: OutputState) {
        renderGl(display: self.display, context: self.context, surface: output.eglSurface) {
            glViewport(0, 0, GLsizei(output.width), GLsizei(output.height))

            glClearColor(0, 0, 0, 0)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

            self.neonRenderer.render(
                display: self.display,
                context: self.context,
                surface: output.eglSurface)

            eglSwapBuffers(display, output.eglSurface)
        }
    }

    func update(surface: EGLSurface, width: Int32, height: Int32, scale: Float) {
        self.neonRenderer.updateSize(
            display: self.display,
            context: self.context,
            surface: surface,
            width: width,
            height: height,
            scale: scale)
    }

    func handleKeyPress(keysym: xkb_keysym_t) {
        if keysym == XKB_KEY_Escape {
            self.keepRunning = false
        }
    }

    func handleButtonPress(seat: Seat, button: UInt32) {
        self.vertices[seat] = self.pointer[seat, default: (0, 0)]
        self.buttonPressed[seat] = true
    }

    func handleButtonRelease(seat: Seat, button: UInt32) {
        self.buttonPressed[seat] = false
        guard let box = self.currentBox(seat: seat) else { return }
        self.keepRunning = false
        self.regionSelected = true
        print("\(box.x),\(box.y) \(box.width)x\(box.height)")
    }

    func handlePointerEnter(seat: Seat, surface: TypedOpaque<WlSurface>) {
        guard let output = self.outputs[surface] else { return }
        self.outputBySeat[seat] = output
    }

    func handlePointerMotion(seat: Seat, surfaceX: Int32, surfaceY: Int32) {
        guard let output = self.outputBySeat[seat] else { return }
        self.pointer[seat] = (output.x + wl_fixed_to_int(surfaceX), output.y + wl_fixed_to_int(surfaceY))

        if self.buttonPressed[seat, default: false] {
            if var frame = self.currentBox(seat: seat) {
                frame.x -= output.x
                frame.y -= output.y
                // XXX hardcoded color
                let color = float_rgba(r: 0x9e / 255.0, g: 0x22 / 255.0, b: 0x91 / 255.0, a: 0xb2 / 255.0)
                let rects = drawResizeFrame(frame: frame, color: color)
                self.neonRenderer.update(rects: rects, surfaces: [])
            }
            self.requestRedraw(output: output)
        }
    }

    private func currentBox(seat: Seat) -> Box? {
        guard let (leftX, leftY) = self.vertices[seat],
            let (rightX, rightY) = self.pointer[seat]
        else {
            return nil
        }
        let deltaX = rightX - leftX
        let deltaY = rightY - leftY
        guard deltaX != 0 && deltaY != 0 else { return nil }

        let width = abs(rightX - leftX) + 1
        let height = abs(rightY - leftY) + 1
        let x = deltaX < 0 ? leftX - (width - 1) : leftX
        let y = deltaY < 0 ? leftY - (height - 1) : leftY
        return Box(x: x, y: y, width: width, height: height)
    }

    private func requestRedraw(output: OutputState) {
        guard self.frameCallbacks[output.wlSurface] == nil else { return }

        let frameCallback: TypedOpaque<WlFrameCallback> =
            TypedOpaque(wl_surface_frame(output.wlSurface.get(as: WlSurface.self)))
        self.frameCallbacks[output.wlSurface] = FrameListener(
            frameCallback,
            called: {
                self.frameCallbacks.removeValue(forKey: output.wlSurface)
                self.render(on: output)
            })
        wl_surface_commit(output.wlSurface.get(as: WlSurface.self))
    }
}

extension Seat: Hashable {
    public static func ==(_ left: Seat, _ right: Seat) -> Bool {
        left.rawPtr == right.rawPtr
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.rawPtr)
    }
}

extension TypedOpaque: Hashable {
    public static func ==(_ left: TypedOpaque<T>, _ right: TypedOpaque<T>) -> Bool {
        left.get(as: T.self) == right.get(as: T.self)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.get(as: T.self))
    }
}

func main() throws -> Int32 {
    LoggingSystem.bootstrap { _ in AnsiLogHandler(logLevel: .info) }
    logger = Logger(label: "OutputHUD")
    guard let display = wl_display_connect(nil) else {
        logger.critical("Could not connect to Wayland")
        return EXIT_FAILURE
    }
    defer {
        wl_display_disconnect(display)
    }

    guard let xkbContext: TypedOpaque<XkbContext> = TypedOpaque(xkb_context_new(XKB_CONTEXT_NO_FLAGS))
    else {
        logger.critical("Could not create xkb context")
        return EXIT_FAILURE
    }
    defer {
        xkb_context_unref(xkbContext.get(as: XkbContext.self))
    }

    let registryListener = RegistryListener(display)
    defer {
        registryListener.done()
    }
    wl_display_roundtrip(display)
    // Another roundtrip to retrieve output names & seat capabilities
    wl_display_roundtrip(display)
    guard registryListener.hasAllGlobals() else {
        return EXIT_FAILURE
    }

    guard let (eglDisplay, eglConfig, eglContext, eglCreatePlatformWindowSurfaceExt) = eglInit(display: display) else {
        return EXIT_FAILURE
    }

    let surfaces = registryListener.outputs().map {
        createOutputSurface(
            for: $0,
            display: display,
            registryListener: registryListener,
            eglDisplay: eglDisplay,
            eglConfig: eglConfig,
            eglCreatePlatformWindowSurfaceExt: eglCreatePlatformWindowSurfaceExt)
    }
    defer {
        for maybeSurface in surfaces {
            if let (_, _, _, layerSurface, _) = maybeSurface {
                zwlr_layer_surface_v1_destroy(layerSurface.get(as: LayerSurface.self))
            }
        }
    }
    guard surfaces.allSatisfy({ $0 != nil }) else {
        return EXIT_FAILURE
    }

    let outputs = surfaces.compactMap({ $0 }).map {
        let (listener, wlSurface, eglSurface, _, (x, y)) = $0
        return OutputState(
            eglSurface: eglSurface,
            wlSurface: wlSurface,
            x: x,
            y: y,
            width: Int32(listener.width),
            height: Int32(listener.height))
    }
    let app = App(display: eglDisplay, context: eglContext, outputs: outputs)

    let pointers: [(PointerListener, TypedOpaque<WlPointer>)] = registryListener
        .seats()
        .filter { $0.hasPointer }
        .map { seat in
            let ptr: TypedOpaque<WlPointer> = TypedOpaque(wl_seat_get_pointer(seat.rawPtr))
            return (
                PointerListener(
                    ptr,
                    enter: { app.handlePointerEnter(seat: seat, surface: $0) },
                    pressed: { app.handleButtonPress(seat: seat, button: $0) },
                    released: { app.handleButtonRelease(seat: seat, button: $0) },
                    motion: { app.handlePointerMotion(seat: seat, surfaceX: $0, surfaceY: $1) }),
                ptr
            )
        }
    defer {
        for (_, pointer) in pointers {
            wl_pointer_release(pointer.get(as: WlPointer.self))
        }
    }

    let keyboards = registryListener
        .seats()
        .filter { $0.hasKeyboard }
        .map { seat in
            let ptr:TypedOpaque<WlKeyboard> = TypedOpaque(wl_seat_get_keyboard(seat.rawPtr))
            return (KeyboardListener(ptr, context: xkbContext, keyPressed: app.handleKeyPress), ptr)
        }
    defer {
        for (_, keyboard) in keyboards {
            wl_keyboard_release(keyboard.get(as: WlKeyboard.self))
        }
    }

    for output in outputs {
        app.update(
            surface: output.eglSurface,
            width: output.width,
            height: output.height,
            // XXX
            scale: 1.0)
        app.render(on: output)
    }

    while app.keepRunning && wl_display_dispatch(display) != 0 {
    }

    return app.regionSelected ? EXIT_SUCCESS : EXIT_FAILURE
}

exit(try main())

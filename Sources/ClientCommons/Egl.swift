import Logging

import CWaylandEgl
import EGlext
import Gles2ext

public let EGL_NO_CONTEXT: EGLContext? = nil
public let EGL_NO_DISPLAY: EGLDisplay? = nil
public let EGL_NO_SURFACE: EGLSurface? = nil

let logger = Logger(label: "EGl")


public func eglInit(
    display: OpaquePointer
) -> (EGLDisplay, EGLConfig, EGLContext, PFNEGLCREATEPLATFORMWINDOWSURFACEEXTPROC)? {
    guard let eglGetPlatformDisplayExtRaw = eglGetProcAddress("eglGetPlatformDisplayEXT") else {
        logger.critical("EGL_EXT_platform_wayland not supported")
        return nil
    }
    let eglGetPlatformDisplayExt = unsafeBitCast(
        eglGetPlatformDisplayExtRaw,
        to: PFNEGLGETPLATFORMDISPLAYEXTPROC.self)

    guard let eglCreatePlatformWindowSurfaceExtRaw = eglGetProcAddress("eglCreatePlatformWindowSurfaceEXT") else {
        logger.critical("EGL_EXT_platform_base not supported")
        return nil
    }
    let eglCreatePlatformWindowSurfaceExt = unsafeBitCast(
        eglCreatePlatformWindowSurfaceExtRaw,
        to: PFNEGLCREATEPLATFORMWINDOWSURFACEEXTPROC.self)

    var success = false

    guard let eglDisplay = eglGetPlatformDisplayExt(
        GLenum(EGL_PLATFORM_WAYLAND_EXT),
        UnsafeMutableRawPointer(display),
        nil) 
    else {
        logger.critical("Could not create EGL display")
        return nil
    }

    defer {
        if !success {
            eglMakeCurrent(EGL_NO_DISPLAY, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT)
            eglTerminate(eglDisplay)
            eglReleaseThread()
        }
    }

    guard eglInitialize(eglDisplay, nil, nil) != EGL_FALSE else {
        // XXX clean up display
        logger.critical("Could not initialize EGL")
        return nil
    }

    let configAttribs: [EGLint] = [
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_NONE,
    ]
    var eglConfig: EGLConfig? = nil
    var matched: EGLint = 0
    guard eglChooseConfig(eglDisplay, configAttribs, &eglConfig, 1, &matched) != EGL_FALSE else {
        logger.critical("eglChooseConfig failed")
        return nil
    }
    guard matched != 0 else {
        logger.critical("EGL config didn't match")
        return nil
    }

    let contextAttribs: [EGLint] = [
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE,
    ]
    let eglContext = eglCreateContext(eglDisplay, eglConfig, EGL_NO_CONTEXT, contextAttribs)
    guard eglContext != EGL_NO_CONTEXT else {
        logger.critical("Could not create EGL context")
        return nil
    }

    success = true

    return (eglDisplay, eglConfig!, eglContext!, eglCreatePlatformWindowSurfaceExt)
}

public struct EGLWindow {}

// Trivial wrapper to avoid a dependency to CWaylandEgl in packages also having a depndency to
// ClientCommons, because having so results in a Swift crash: https://github.com/apple/swift/issues/52036
public func eglWindowCreate(
    surface: OpaquePointer,
    width: Int32,
    height: Int32
) -> TypedOpaque<EGLWindow>? {
    TypedOpaque(wl_egl_window_create(surface, width, height))
}

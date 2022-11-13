import Gles2ext
import EGlext
import Logging

fileprivate let logger = Logger(label: "OpenGL")

public struct float_rgba {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float

    public init(r: Float, g: Float, b: Float, a: Float) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public mutating func withPtr<Result>(_ body: (UnsafePointer<Float>) -> Result) -> Result {
        withUnsafePointer(to: &self) {
            $0.withMemoryRebound(to: Float.self, capacity: 4, body)
        }
    }
}

public typealias matrix9 = (Float, Float, Float, Float, Float, Float, Float, Float, Float)

class Program {
    private let id: GLuint
    private var locations: [String: GLint] = [:]
#if OPENGL_DEBUG
    private var isActive: Bool = false
#endif

    fileprivate init(id: GLuint) {
        self.id = id
    }

    deinit {
        gl { glDeleteProgram(self.id) }
    }

    public func getUniformLocation(name: String) -> GLint {
        if let location = self.locations[name] {
            return location
        } else {
            let location = name.withCString { namePtr in
                gl { glGetUniformLocation(self.id, namePtr) }
            }
            self.locations[name] = location
            return location
        }
    }

    public func set(name: String, int value: Int32) {
    #if OPENGL_DEBUG
        assert(self.isActive, "set() called, but program not active")
    #endif
        let location = self.getUniformLocation(name: name)
        gl { glUniform1i(location, GLint(value)) }
    }

    public func set(name: String, _ v1: Float, _ v2: Float, _ v3: Float, _ v4: Float) {
    #if OPENGL_DEBUG
        assert(self.isActive, "set() called, but program not active")
    #endif
        let location = self.getUniformLocation(name: name)
        gl { glUniform4f(location, GLfloat(v1), GLfloat(v2), GLfloat(v3), GLfloat(v4)) }
    }

    public func set(name: String, matrix: inout matrix9) {
    #if OPENGL_DEBUG
        assert(self.isActive, "set() called, but program not active")
    #endif
        let location = self.getUniformLocation(name: name)
        gl { glUniformMatrix3fv(location, 1, GLboolean(GL_FALSE), &matrix.0) }
    }

    public func use(_ block: () -> ()) {
        gl { glUseProgram(self.id) }
    #if OPENGL_DEBUG
        self.isActive = true
    #endif
        defer {
            gl { glUseProgram(0) }
        #if OPENGL_DEBUG
            self.isActive = false
        #endif
        }
        block()
    }
}

func gl<R>(_ block: () -> R, fileId: String = #fileID, line: Int = #line) -> R {
    let returnValue = block()

#if OPENGL_DEBUG
    let error = glGetError()
    if error != GL_NO_ERROR {
        logger.error("\(fileId):\(line): GL call returned \(error)")
    }
#endif

    return returnValue
}

func compileShader(source: String, type: GLenum) -> GLuint {
    let shader = gl { glCreateShader(type) }
    source.withCString { sourcePtr in
        var castedPtr: UnsafePointer<GLchar>? = UnsafePointer<GLchar>(sourcePtr)
        gl { glShaderSource(shader, 1, &castedPtr, nil) }
    }
    gl { glCompileShader(shader) }

    var success: GLint = 0
    gl { glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &success) }
    guard success != GL_FALSE else {
        fatalError("shader did not compile")
    }

    return shader
}

func compileProgram(vertexSource: String, fragmentSource: String) -> Program {
    let vertexShader = compileShader(source: vertexSource, type: GLenum(GL_VERTEX_SHADER))
    let fragmentShader = compileShader(source: fragmentSource, type: GLenum(GL_FRAGMENT_SHADER))

    let program = gl { glCreateProgram() }
    gl { glAttachShader(program, vertexShader) }
    gl { glAttachShader(program, fragmentShader) }
    gl { glLinkProgram(program) }

    gl { glDeleteShader(vertexShader) }
    gl { glDeleteShader(fragmentShader) }

    return Program(id: program)
}

public func renderGl(display: EGLDisplay, context: EGLContext, surface: EGLSurface, block: () -> ()) {
    renderBegin(display: display, context: context, surface: surface)
    defer {
        renderEnd()
    }

    block()
}

private func renderBegin(display: EGLDisplay, context: EGLContext, surface: EGLSurface) {
    if eglMakeCurrent(display, surface, surface, context) == 0 {
        logger.warning("Could not make EGL context current")
    }
}

private func renderEnd() {
    gl { glDisable(GLuint(GL_SCISSOR_TEST)) }
}

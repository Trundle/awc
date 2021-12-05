import Wlroots

class Program {
    private let id: GLuint
    private var locations: [String: GLint] = [:]
#if OPENGL_DEBUG
    private var active: Bool = false
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
        guard self.active else { fatalError("set() called, but program not active") }
    #endif
        let location = self.getUniformLocation(name: name)
        gl { glUniform1i(location, GLint(value)) }
    }

    public func set(name: String, matrix: inout matrix9) {
    #if OPENGL_DEBUG
        guard self.active else { fatalError("set() called, but program not active") }
    #endif
        let location = self.getUniformLocation(name: name)
        gl { glUniformMatrix3fv(location, 1, GLboolean(GL_FALSE), &matrix.0) }
    }

    public func use(_ block: () -> ()) {
        gl { glUseProgram(self.id) }
    #if OPENGL_DEBUG
        self.active = true
    #endif
        defer {
            gl { glUseProgram(0) }
        #if OPENGL_DEBUG
            self.active = false
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
        print("[ERROR] \(fileId):\(line): GL call returned \(error)")
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

func renderGl(with renderer: UnsafeMutablePointer<wlr_renderer>, block: () -> ()) {
    renderBegin(renderer)
    defer {
        renderEnd()
    }

    block()
}

private func renderBegin(_ renderer: UnsafeMutablePointer<wlr_renderer>) {
    let egl = wlr_gles2_renderer_get_egl(renderer)
    if (!wlr_egl_is_current(egl)) {
        wlr_egl_make_current(egl)
    }
}

private func renderEnd() {
    gl { glDisable(GLuint(GL_SCISSOR_TEST)) }
}

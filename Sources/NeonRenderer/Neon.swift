import CCairo
import Cairo
import DataStructures
import EGlext
import Gles2ext
import Gles32

private let backgroundQuadVertexSource = """
#version 320 es
layout (location = 0) in vec2 aPos;
uniform vec4 aColor;
uniform mat3 aProj;

out vec4 Color;

void main() {
    gl_Position = vec4(aProj * vec3(aPos, 1.0), 1.0);
    Color = aColor;
}
"""

private let backgroundQuadFragmentSource = """
#version 320 es
precision mediump float;

in vec4 Color;
layout (location = 0) out vec4 FragColor;

void main() {
    FragColor = Color;
}
"""


private let cairoSurfaceVertexSource = """
#version 320 es
layout (location = 0) in vec2 aPos;
layout (location = 1) in vec2 aTexCoord;
uniform mat3 aProj;

out vec2 TexCoord;

void main() {
    gl_Position = vec4(aProj * vec3(aPos, 1.0), 1.0);
    TexCoord = aTexCoord;
}
"""

private let cairoSurfaceFragmentSource = """
#version 320 es
precision mediump float;

in vec2 TexCoord;
out vec4 FragColor;
uniform sampler2D tex;

void main() {
    FragColor = texture(tex, TexCoord);
}
"""


private let overlayVertexSource = """
#version 320 es
layout (location = 0) in vec2 aPos;
layout (location = 1) in vec2 aTexCoord;
uniform mat3 aProj;

out vec2 TexCoord;

void main() {
    gl_Position = vec4(aProj * vec3(aPos, 1.0), 1.0);
    TexCoord = aTexCoord;
}
"""

private let overlayFragmentSource = """
#version 320 es
precision mediump float;

in vec2 TexCoord;
out vec4 FragColor;
uniform sampler2D tex;

void main() {
    FragColor = texture(tex, TexCoord);
    float brightness = dot(FragColor.rgb, vec3(0.2126, 0.7152, 0.0722)) * FragColor.a;
    if (brightness < 0.5) {
        FragColor = vec4(0.0, 0.0, 0.0, 0.0);
    }
}
"""

private let blurFragmentSource = """
#version 320 es
precision mediump float;

out vec4 FragColor;

in vec2 TexCoord;

uniform sampler2D tex;

uniform bool horizontal;
const float weight[5] = float[] (0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);

vec2 toVec(ivec2 v) {
    return vec2(float(v.x), float(v.y));
}

void main() {
    // Described in and original code from https://learnopengl.com/Advanced-Lighting/Bloom
    vec2 tex_offset = 1.0 / toVec(textureSize(tex, 0));
    vec3 result = texture(tex, TexCoord).rgb * weight[0];
    if (horizontal) {
        for (int i = 1; i < 5; ++i) {
            result += texture(tex, TexCoord + vec2(tex_offset.x * float(i), 0.0)).rgb * weight[i];
            result += texture(tex, TexCoord - vec2(tex_offset.x * float(i), 0.0)).rgb * weight[i];
        }
    } else {
        for (int i = 1; i < 5; ++i) {
            result += texture(tex, TexCoord + vec2(0.0, tex_offset.y * float(i))).rgb * weight[i];
            result += texture(tex, TexCoord - vec2(0.0, tex_offset.y * float(i))).rgb * weight[i];
        }
    }
    FragColor = vec4(result, 1.0);
}
"""

private let finalFragmentSource = """
#version 320 es
precision mediump float;

out vec4 FragColor;
in vec2 TexCoord;

uniform sampler2D overlay;
uniform sampler2D bloomBlur;

void main() {
    vec4 overlayColor = texture(overlay, TexCoord);
    vec3 bloomColor = texture(bloomBlur, TexCoord).rgb;
    overlayColor.rgb += bloomColor.rgb * vec3(1.25);
    if (overlayColor.a > 0.5) {
        float mixValue = distance(TexCoord, vec2(0, 0));
        overlayColor.rgb -= mix(vec3(0), vec3(0.25), mixValue);
    }

    FragColor = overlayColor;
}
"""

private var flip180: matrix9 = (
    1, 0, 0,
    0, -1, 0,
    0, 0, 1
)

enum wl_output_transform {
    case WL_OUTPUT_TRANSFORM_NORMAL
    case WL_OUTPUT_TRANSFORM_FLIPPED_180
}

/// Renders Cairo surfaces with a Neon-like effect.
public class NeonRenderer {
    private enum Framebuffers: Int, CaseIterable {
        case overlay
        case blurPingPong1
        case blurPingPong2
        case overlayHighlights
    }

    private enum Textures: Int, CaseIterable {
        case blurPingPong1
        case blurPingPong2
        case cairoSurface
        case overlay
        case overlayHighlights
    }

    private var width: Int32 = 0
    private var height: Int32 = 0
    private var scale: Float = 1.0
    private var framebuffers: [GLuint] = Array(repeating: 0, count: Framebuffers.allCases.count)
    private var textures: [GLuint] = Array(repeating: 0, count: Textures.allCases.count)
    private var backgroundQuads: Program!
    private var cairoSurface: Program!
    // Extracts the overlay's highlights (i.e. the glowy parts)
    private var overlay: Program!
    private var blur: Program!
    private var finalProgram: Program!
    private var quadVao: GLuint = 0
    private var quadVbo: GLuint = 0
    private var emptyCairoSurfaceTextureData: [GLubyte] = []
    private var overlayBoundingBox: (Int32, Int32, Int32, Int32) = (0, 0, 0, 0)
    private var nextRects: [(Box, float_rgba)] = []
    private var nextSurfaces: [(Int32, Int32, Cairo.Surface)] = []

    public init() {
    }

    deinit {
        self.freeBuffersAndTextures()
    }

    private func freeBuffersAndTextures() {
        if self.framebuffers[0] != 0 {
            gl { glDeleteFramebuffers(GLsizei(self.framebuffers.count), &self.framebuffers) }
        }
        if self.textures[0] != 0 {
            gl { glDeleteTextures(GLsizei(self.textures.count), &self.textures) }
        }
    }

    public func render(display: EGLDisplay, context: EGLContext, surface: EGLSurface) {
        var box = Box(x: 0, y: 0, width: self.width, height: self.height)
        var glMatrix: matrix9 = (0, 0, 0, 0, 0, 0, 0, 0, 0)
        self.glMatrix(for: &box, &glMatrix)

        var originalFbo: GLint = 0
        gl { glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &originalFbo) }
        defer {
            gl { glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLuint(originalFbo)) }
        }

        if !nextRects.isEmpty || !nextSurfaces.isEmpty {
            self.updateOverlayTexture()
        }

        gl { glClearColor(0, 0, 0, 0) }
        // The first fbo is for filling the overlay texture, doesn't need to be cleared
        for fbo in self.framebuffers[1...] {
            gl { glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo) }
            gl { glClear(GLbitfield(GL_COLOR_BUFFER_BIT)) }
        }

        self.scissorOverlayBoundingBox()
        defer {
            gl { glDisable(GLenum(GL_SCISSOR_TEST)) }
        }

        gl { glDisable(GLenum(GL_BLEND)) }

        self.overlay.use {
            self.bind(framebuffer: .overlayHighlights)
            gl { glActiveTexture(GLenum(GL_TEXTURE0)) }

            self.overlay.set(name: "aProj", matrix: &glMatrix)

            self.bind(texture: .overlay)
            self.renderQuad()
            self.unbindTexture()
        }

        // Blur bright fragments with two-pass Gaussian blur
        self.blur.use {
            self.blur.set(name: "aProj", matrix: &glMatrix)
            var horizontal = true
            var bufferIndex = Framebuffers.blurPingPong2
            var textureIndex = Textures.overlayHighlights
            for _ in 0..<10{
                self.blur.set(name: "horizontal", int: horizontal ? 1 : 0)
                self.bind(framebuffer: bufferIndex)
                self.bind(texture: textureIndex)
                self.renderQuad()
                bufferIndex = horizontal ? Framebuffers.blurPingPong1 : Framebuffers.blurPingPong2
                textureIndex = horizontal ? Textures.blurPingPong2 : Textures.blurPingPong1
                horizontal = !horizontal
            }
        }

        gl { glEnable(GLenum(GL_BLEND)) }
        gl { glBlendFunc(GLenum(GL_ONE), GLenum(GL_ONE_MINUS_SRC_ALPHA)) }

        // Finally, render the blurred fragments on top
        self.finalProgram.use {
            // XXX
            self.scissorOverlayYInvertedBoundingBox()
            self.glMatrix(for: &box, &glMatrix, transform: .WL_OUTPUT_TRANSFORM_FLIPPED_180)
            self.finalProgram.set(name: "aProj", matrix: &glMatrix)
            gl { glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLuint(originalFbo)) }
            gl { glActiveTexture(GLenum(GL_TEXTURE0)) }
            self.bind(texture: .overlay)
            gl { glActiveTexture(GLenum(GL_TEXTURE1)) }
            self.bind(texture: .blurPingPong1)
            self.renderQuad()
        }

        for fbo in self.framebuffers[1...] {
            gl { glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo) }
            let attachments = [GLenum(GL_COLOR_ATTACHMENT0)]
            gl { glInvalidateFramebuffer(GLenum(GL_FRAMEBUFFER), 1, attachments) }
        }

        gl { glActiveTexture(GLenum(GL_TEXTURE0)) }
    }

    public func update(rects: [(Box, float_rgba)], surfaces: [(Int32, Int32, Cairo.Surface)]) {
        self.nextRects = rects
        self.nextSurfaces = surfaces
    }

    public func updateSize(
        display: EGLDisplay,
        context: EGLContext,
        surface: EGLSurface,
        width: Int32,
        height: Int32,
        scale: Float
    ) {
        self.width = width
        self.height = height
        self.scale = scale
        if self.overlay == nil {
            self.initGl(display: display, context: context, surface: surface)
        } else {
            renderGl(display: display, context: context, surface: surface) {
                self.freeBuffersAndTextures()
                self.initBuffersAndTextures()
            }
        }
    }

    private func renderBackgroundQuads(quads: [(Box, float_rgba)]) {
        self.backgroundQuads.use {
            for (box, color) in quads {
                var box = box
                var glMatrix: matrix9 = (0, 0, 0, 0, 0, 0, 0, 0, 0)
                self.glMatrix(for: &box, &glMatrix)

                self.backgroundQuads.set(name: "aProj", matrix: &glMatrix)
                self.backgroundQuads.set(name: "aColor", color.r, color.g, color.b, color.a)
                self.renderQuad()
            }
        }
    }

    private func initQuadVaoAndVbo() {
        gl { glGenVertexArrays(1, &self.quadVao) }
        gl { glGenBuffers(1, &self.quadVbo) }
        gl { glBindVertexArray(self.quadVao) }
        defer {
            gl { glBindVertexArray(0) }
        }
        gl { glBindBuffer(GLenum(GL_ARRAY_BUFFER), self.quadVbo) }
        defer {
            gl { glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0) }
        }

        var vertices: [GLfloat] = [
            // pos & texture coords
            1, 0, // top right
            0, 0, // top left
            1, 1, // bottom right
            0, 1, // bottom left
        ]
        gl {
            glBufferData(
                GLenum(GL_ARRAY_BUFFER),
                MemoryLayout<GLfloat>.size * vertices.count,
                &vertices,
                GLenum(GL_STATIC_DRAW))
        }

        gl { glEnableVertexAttribArray(0) }
        gl {
            glVertexAttribPointer(
                0,
                2,
                GLenum(GL_FLOAT),
                GLboolean(GL_FALSE),
                2 * GLsizei(MemoryLayout<GLfloat>.size),
                nil)
        }
        gl {
            glVertexAttribPointer(
                1,
                2,
                GLenum(GL_FLOAT),
                GLboolean(GL_FALSE),
                2 * GLsizei(MemoryLayout<GLfloat>.size),
                nil)
        }
        gl { glEnableVertexAttribArray(1) }
    }

    private func renderQuad() {
        if self.quadVao == 0 {
            self.initQuadVaoAndVbo()
        }
        gl { glBindVertexArray(self.quadVao) }
        defer {
            gl { glBindVertexArray(0) }
        }
        gl { glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4) }
    }

    private func initGl(display: EGLDisplay, context: EGLContext, surface: EGLSurface) {
        renderGl(display: display, context: context, surface: surface) {
            self.backgroundQuads = compileProgram(
                vertexSource: backgroundQuadVertexSource,
                fragmentSource: backgroundQuadFragmentSource)
            self.cairoSurface = compileProgram(
                vertexSource: cairoSurfaceVertexSource,
                fragmentSource: cairoSurfaceFragmentSource)
            self.cairoSurface.use {
                self.cairoSurface.set(name: "tex", int: 0)
            }
            self.overlay = compileProgram(vertexSource: overlayVertexSource, fragmentSource: overlayFragmentSource)
            self.overlay.use {
                self.overlay.set(name: "tex", int: 0)
            }
            self.blur = compileProgram(vertexSource: overlayVertexSource, fragmentSource: blurFragmentSource)
            self.blur.use {
                self.blur.set(name: "tex", int: 0)
            }
            self.finalProgram = compileProgram(vertexSource: overlayVertexSource, fragmentSource: finalFragmentSource)
            self.finalProgram.use {
                self.finalProgram.set(name: "overlay", int: 0)
                self.finalProgram.set(name: "bloomBlur", int: 1)
            }

            self.initBuffersAndTextures()
        }
    }

    private func initBuffersAndTextures() {
        var originalFbo: GLint = 0
        gl { glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &originalFbo) }
        defer {
            gl { glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLuint(originalFbo)) }
        }

        gl { glGenFramebuffers(GLsizei(self.framebuffers.count), &self.framebuffers) }
        gl { glGenTextures(GLsizei(self.textures.count), &self.textures) }
        self.initOverlayTextures()
        self.initBlurPingPongTextures()

        self.bind(framebuffer: .overlay)
        gl {
            glFramebufferTexture2D(
                GLenum(GL_FRAMEBUFFER),
                GLenum(GL_COLOR_ATTACHMENT0),
                GLenum(GL_TEXTURE_2D),
                self.textures[Textures.overlay.rawValue],
                0)
        }
        self.checkFramebufferComplete()
    }

    private func initOverlayTextures() {
        self.initOverlayTexture(texture: .overlay)
        self.initOverlayTexture(texture: .overlayHighlights)

        self.bind(framebuffer: .overlayHighlights)
        gl {
            glFramebufferTexture2D(
                GLenum(GL_FRAMEBUFFER),
                GLenum(GL_COLOR_ATTACHMENT0),
                GLenum(GL_TEXTURE_2D),
                self.textures[Textures.overlayHighlights.rawValue],
                0)
        }
        self.checkFramebufferComplete()
    }

    private func initOverlayTexture(texture: Textures) {
        self.bind(texture: texture)
        gl { glTexImage2D(
            GLenum(GL_TEXTURE_2D),
            0,
            GL_RGBA,
            GLsizei((Float(self.width) * self.scale).rounded(.up)),
            GLsizei((Float(self.height) * self.scale).rounded(.up)),
            0,
            GLenum(GL_RGBA),
            GLenum(GL_UNSIGNED_BYTE),
            nil)
        }
        gl { glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR) }
        gl { glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR) }
        gl { glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE) }
        gl { glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE) }
    }

    private func initBlurPingPongTextures() {
        let indices = [
            (Framebuffers.blurPingPong1, Textures.blurPingPong1),
            (Framebuffers.blurPingPong2, Textures.blurPingPong2)
        ]
        for (bufferIndex, textureIndex) in indices {
            self.bind(framebuffer: bufferIndex)
            self.bind(texture: textureIndex)
            gl { glTexImage2D(
                GLenum(GL_TEXTURE_2D),
                0,
                GL_RGBA,
                GLsizei((Float(self.width) * self.scale).rounded(.up)),
                GLsizei((Float(self.height) * self.scale).rounded(.up)),
                0,
                GLenum(GL_RGBA),
                GLenum(GL_UNSIGNED_BYTE),
                nil)
            }
            gl { glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR) }
            gl { glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR) }
            gl { glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE) }
            gl { glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE) }
            gl {
                glFramebufferTexture2D(
                    GLenum(GL_FRAMEBUFFER),
                    GLenum(GL_COLOR_ATTACHMENT0),
                    GLenum(GL_TEXTURE_2D),
                    self.textures[textureIndex.rawValue],
                    0)
            }
            self.checkFramebufferComplete()
        }
        self.unbindTexture()
    }

    private func checkFramebufferComplete() {
        let status = gl { glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) }
        guard status == GL_FRAMEBUFFER_COMPLETE else {
            fatalError("Framebuffer status is \(status), this is unexpected")
        }
    }

    private func bind(framebuffer: Framebuffers) {
        gl { glBindFramebuffer(GLenum(GL_FRAMEBUFFER), self.framebuffers[framebuffer.rawValue]) }
    }

    private func bind(texture: Textures) {
        gl { glBindTexture(GLenum(GL_TEXTURE_2D), self.textures[texture.rawValue]) }
    }

    private func unbindTexture() {
        gl { glBindTexture(GLenum(GL_TEXTURE_2D), 0) }
    }

    private func updateOverlayTexture() {
        let rects = self.nextRects
        let surfaces = self.nextSurfaces
        self.nextRects = []
        self.nextSurfaces = []

        let boxes = 
            surfaces.map { Box(x: $0.0, y: $0.1, width: $0.2.width, height: $0.2.height) }
            + rects.map { $0.0 }
        // N.B. both cairo surfaces and rects
        let (minX, maxX, minY, maxY) =
            boxes
                .reduce((self.width, 0, self.height, 0), {
                    (
                        min($0.0, $1.x),
                        max($0.1, $1.x + $1.width),
                        min($0.2, $1.y),
                        max($0.3, $1.y + $1.height)
                    )
            })
        // The blur grows outside a bit, let's guess by no more than 4 pixels
        self.overlayBoundingBox = (
            max(0, minX - 4),
            max(0, minY - 4),
            min(maxX - minX + 8, self.width),
            min(maxY - minY + 8, self.height)
        )
        // Fill overlay texture: first, render background quads, then copy the cairo
        // surfaces to a texture and render the texture to the overlay texture
        var originalFbo: GLint = 0
        gl { glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &originalFbo) }
        defer {
            gl { glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLuint(originalFbo)) }
        }

        self.bind(framebuffer: .overlay)
        gl { glClearColor(0, 0, 0, 0) }
        gl { glClear(GLbitfield(GL_COLOR_BUFFER_BIT)) }

        self.renderBackgroundQuads(quads: rects)
        self.fillOverlayTexture(surfaces: surfaces)
    }

    private func fillOverlayTexture(surfaces: [(Int32, Int32, Cairo.Surface)]) {
        self.bind(texture: .cairoSurface)
        defer {
            self.unbindTexture()
        }

        gl { glEnable(GLenum(GL_BLEND)) }
        gl { glBlendFunc(GLenum(GL_ONE), GLenum(GL_ONE_MINUS_SRC_ALPHA)) }

        for (x, y, surface) in surfaces {
            surface.withRawPointer {
                //let name = String((0..<6).map{_ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()!})
                //cairo_surface_write_to_png($0, "/tmp/debugsurfaces/\(name)")

                let data = cairo_image_surface_get_data($0)
                gl { glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR) }
                gl { glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR) }
                gl { glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE) }
                gl { glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE) }
                gl { glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_SWIZZLE_R), GL_BLUE) }
                gl { glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_SWIZZLE_B), GL_RED) }
                gl {
                    glTexImage2D(
                        GLenum(GL_TEXTURE_2D),
                        0,
                        GL_RGBA,
                        surface.width,
                        surface.height,
                        0,
                        GLenum(GL_RGBA),
                        GLenum(GL_UNSIGNED_BYTE),
                        data)
                }
            }

            self.renderSurface(x: x, y: y, width: surface.width, height: surface.height)
        }
    }

    private func renderSurface(x: Int32, y: Int32, width: Int32, height: Int32) {
        var box = Box(x: x, y: y, width: width, height: height)
        var glMatrix: matrix9 = (0, 0, 0, 0, 0, 0, 0, 0, 0)
        self.glMatrix(for: &box, &glMatrix)

        self.cairoSurface.use {
            self.cairoSurface.set(name: "aProj", matrix: &glMatrix)
            self.renderQuad()
        }
    }
    
    private func glMatrix(
        for box: inout Box,
        _ result: inout matrix9,
        transform: wl_output_transform = .WL_OUTPUT_TRANSFORM_NORMAL
    ) {
        var transformMatrix: matrix9 = (
            1, 0, 0,
            0, 1, 0,
            0, 0, 1
        )
        var projMatrix: matrix9 = (0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutablePointer(to: &projMatrix.0) { projMatrixPtr in
            withUnsafePointer(to: &transformMatrix.0) { (outputTransformMatrixPtr) in
                wlr_matrix_project_box(projMatrixPtr, &box, .WL_OUTPUT_TRANSFORM_NORMAL, 0, outputTransformMatrixPtr)
            }

            withUnsafeMutablePointer(to: &result.0) { glMatrixPtr in
                wlr_matrix_projection(glMatrixPtr, self.width, self.height, transform)
                wlr_matrix_multiply(glMatrixPtr, glMatrixPtr, projMatrixPtr)
                wlr_matrix_multiply(glMatrixPtr, &flip180.0, glMatrixPtr)
                wlr_matrix_transpose(glMatrixPtr, glMatrixPtr)
            }
        }
    }

    private func scissorOverlayBoundingBox() {
        gl { glEnable(GLenum(GL_SCISSOR_TEST)) }
        gl { 
            glScissor(
                GLint(Float(self.overlayBoundingBox.0) * self.scale),
                GLint(Float(self.overlayBoundingBox.1) * self.scale),
                GLint(Float(self.overlayBoundingBox.2) * self.scale),
                GLint(Float(self.overlayBoundingBox.3) * self.scale)) 
        }
    }

    private func scissorOverlayYInvertedBoundingBox() {
        gl { glEnable(GLenum(GL_SCISSOR_TEST)) }
        gl { 
            glScissor(
                GLint(Float(self.overlayBoundingBox.0) * self.scale),
                GLint(Float(self.height - self.overlayBoundingBox.1 - self.overlayBoundingBox.3) * self.scale),
                GLint(Float(self.overlayBoundingBox.2) * self.scale),
                GLint(Float(self.overlayBoundingBox.3) * self.scale)) 
        }
    }
}

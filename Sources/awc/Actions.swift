import Glibc
import Foundation

import Cairo
import Libawc
import Wlroots


private let spawnHelperPath: String = {
    let arg0 = ProcessInfo.processInfo.arguments[0]
    if let i = arg0.lastIndex(of: "/") {
        return arg0[...i] + "SpawnHelper"
    } else {
        // Too bad, let's se if we are lucky
        return "SpawnHelper"
    }
}()

enum ExecuteError: Error {
    case noMemory
    case syscallError(Int32)
}

/// Executes the given command. The command will run in its own session (i.e. it will not be
/// a child process).
func executeCommand(_ cmd: String) throws {
    var attrs = posix_spawnattr_t()
    var result = posix_spawnattr_init(&attrs)
    guard result == 0 else {
        throw ExecuteError.syscallError(result)
    }
    defer {
        posix_spawnattr_destroy(&attrs)
    }

    let args = ["SpawnHelper", "/bin/sh", "-c", cmd].map { $0.withCString(strdup) } + [nil]
    defer {
        for value in args {
            free(value)
        }
    }
    if args.dropLast().contains(nil) {
        throw ExecuteError.noMemory
    }

    let env: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment.map {
        "\($0.0)=\($0.1)".withCString(strdup)
    } + [nil]
    defer {
        for value in env {
            free(value)
        }
    }
    if env.dropLast().contains(nil) {
        throw ExecuteError.noMemory
    }

    var pid = pid_t()
    let _ = try spawnHelperPath.withCString {
        result = posix_spawn(&pid, $0, nil, &attrs, args, env)
        guard result == 0 else {
            throw ExecuteError.syscallError(result)
        }
    }

    // Wait for child to complete
    var done = false
    var status = pid_t()
    while !done {
        done = withUnsafeMutablePointer(to: &status) {
            waitpid(pid, $0, 0) >= 0 || errno != EINTR
        }
    }
    if status != 0 {
        throw ExecuteError.syscallError(status)
    }
}

extension Awc {
    internal func execute(action: Action) {
        switch action {
        case .execute(let cmd):
            do {
                try executeCommand(cmd)
            } catch {
                print("[WARN] Could not execute '\(cmd)': \(error)")
            }
        case .expand: self.modifyAndUpdate { $0.replace(layout: $0.current.workspace.layout.expand()) }
        case .close: self.kill()
        case .configReload: self.reloadConfig()
        case .focusDown: self.modifyAndUpdate { $0.modify { $0.focusDown() } }
        case .focusUp: self.modifyAndUpdate { $0.modify { $0.focusUp() } }
        case .focusPrimary: self.modifyAndUpdate { $0.focusMain() }
        case .focusOutput(let n): self.withOutput(n) { self.execute(action: .view(tag: $0.workspace.tag)) }
        case .greedyView(let tag): self.modifyAndUpdate { $0.greedyView(tag: tag) }
        case .swapDown: self.modifyAndUpdate { $0.modify { $0.swapDown() } }
        case .swapUp: self.modifyAndUpdate { $0.modify { $0.swapUp() } }
        case .swapPrimary: self.modifyAndUpdate { $0.modify { $0.swapPrimary() } }
        case .nextLayout:
            let layout =  self.viewSet.current.workspace.layout
            let nextLayout = layout.nextLayout() ?? layout.firstLayout()
            self.modifyAndUpdate {
                $0.replace(layout: nextLayout)
            }
        case .resetLayouts: self.modifyAndUpdate { $0.replace(layout: self.defaultLayout) }
        case .moveTo(let tag): self.modifyAndUpdate { $0.shift(tag: tag) }
        case .moveToOutput(let n): self.withOutput(n) { self.execute(action: .moveTo(tag: $0.workspace.tag)) }
        case .shrink: self.modifyAndUpdate { $0.replace(layout: $0.current.workspace.layout.shrink()) }
        case .sink:
            self.withFocused { surface in
                self.modifyAndUpdate {
                    $0.sink(view: surface)
                }
            }
        case .swapWorkspaces:
            self.modifyAndUpdate {
                if let firstVisible = $0.visible.first {
                    return $0.replace(
                        current: $0.current.copy(workspace: firstVisible.workspace),
                        visible: [firstVisible.copy(workspace: $0.current.workspace)] + $0.visible[1...],
                        hidden: $0.hidden
                    )
                } else {
                    return $0
                }
            }
        case .swapWorkspaceTagWith(let tag):
            self.modifyAndUpdate {
                let currentTag = $0.current.workspace.tag
                return $0.mapWorkspaces {
                    switch $0.tag {
                    case currentTag: return $0.replace(tag: tag)
                    case tag: return $0.replace(tag: currentTag)
                    default: return $0
                    }
                 }
            }
        case .switchVt(let n):
            if let session = wlr_backend_get_session(self.backend) {
                wlr_session_change_vt(session, UInt32(n))
            }
        case .view(let tag): self.modifyAndUpdate { $0.view(tag: tag) }
        }
    }

    /// Note that `n` is one-indexed.
    private func withOutput(_ n: UInt8, _ action: (Output<L>) -> ()) {
        let outputs = self.orderedOutputs()
        if n > 0 && n <= outputs.count {
            action(outputs[Int(n - 1)])
        }
    }

    private func reloadConfig() {
        if let config = loadConfig(path: self.config.path) {
            // XXX This doesn't reload everything (e.g. border width)
            self.config = config
            let layout = self.layoutWrapper(config.layout)
            self.modifyAndUpdate { viewSet in
                viewSet.replace(
                    current: viewSet.current.copy(workspace: viewSet.current.workspace.replace(layout: layout)),
                    visible: viewSet.visible.map { $0.copy(workspace: $0.workspace.replace(layout: layout)) },
                    hidden: viewSet.hidden.map { $0.replace(layout: layout) }
                )
            }
            print("[INFO] Reloaded config!")
        } else {
            do {
                try executeCommand(self.config.generateErrorDisplayCmd(msg: "Reloading config failed :("))
            } catch {
                print("[WARN] Could not display error message: \(error)")
            }
        }
    }
}

// MARK: Mouse actions

extension Awc {
    internal func execute(action: ButtonAction, surface: Surface) {
        switch action {
        case .move: self.setToFloatingAndMove(surface)
        case .resize: self.setToFloatingAndResize(surface)
        case .resizeByFrame: self.setToFloatingAndResizeByFrame(surface)
        }
    }

    private func setToFloatingAndMove(_ surface: Surface) {
        self.modifyAndUpdate {
            if let output = $0.findOutput(view: surface) {
                let outputBox = output.data.box
                var box = $0.floating[surface] ?? surface.preferredFloatingBox(awc: self, output: output)
                let startBox = box

                let startX = self.cursor.pointee.x
                let startY = self.cursor.pointee.y
                self.dragging = { (time, x, y) in
                    setWithinBounds(
                        &box,
                        x: startBox.x + Int32(x - startX),
                        y: startBox.y + Int32(y - startY),
                        maxX: outputBox.width,
                        maxY: outputBox.height
                    )

                    self.modifyAndUpdate {
                        $0.float(view: surface, box: box)
                    }
                }

                return $0.float(view: surface, box: box)
            } else {
                return $0
            }
        }
    }

    private func setToFloatingAndResize(_ surface: Surface) {
        self.modifyAndUpdate {
            if let output = $0.findOutput(view: surface) {
                var box = $0.floating[surface] ?? surface.preferredFloatingBox(awc: self, output: output)
                let startBox = box

                let startX = Double(output.data.box.x + box.x + box.width)
                let startY = Double(output.data.box.y + box.y + box.height)

                self.dragging = { (time, x, y) in
                    box.width = max(startBox.width + Int32(x - startX), 24)
                    box.height = max(startBox.height + Int32(y - startY), 24)
                    self.modifyAndUpdate {
                        $0.float(view: surface, box: box)
                    }
                }

                wlr_cursor_warp(self.cursor, nil, startX, startY)

                return $0.float(view: surface, box: box)
            } else {
                return $0
            }
        }
    }

    private func setToFloatingAndResizeByFrame(_ surface: Surface) {
        if let output = self.viewSet.findOutput(view: surface) {
            let outputBox = output.data.box

            let startX = self.cursor.pointee.x
            let startY = self.cursor.pointee.y

            var currentX = startX
            var currentY = startY

            let toBox: (Int32) -> wlr_box = { margin in
                let x = Int32(min(currentX, startX)) - margin
                let y = Int32(min(currentY, startY)) - margin
                return wlr_box(
                    x: x - outputBox.x, y: y - outputBox.y,
                    width: Int32(max(currentX, startX)) - x + 2 * margin,
                    height: Int32(max(currentY, startY)) - y + 2 * margin)
            }

            let neonRenderer = NeonRenderer()
            let box = output.data.box
            neonRenderer.updateSize(
                width: box.width, height: box.height, scale: output.data.output.pointee.scale,
                renderer: self.renderer)
            let cairoSurface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, box.width, box.height)!
            let cairo = cairo_create(cairoSurface)!

            self.dragging = { (_, x, y) in
                currentX = x
                currentY = y

                drawResizeFrame(cairo: cairo, frame: toBox(0), color: self.config.colors.resize_frame.toFloatRgba())
                neonRenderer.update(surface: cairoSurface, with: self.renderer)

                // The blur of the neon effect makes the damage box a bit larger
                var box = toBox(Int32(self.config.borderWidth + 10))
                wlr_output_damage_add_box(output.data.damage, &box)
            }
            self.draggingEnd = { (_, _) in
                self.modifyAndUpdate {
                    $0.float(view: surface, box: toBox(0))
                }
                self.additionalRenderHook = nil
            }
            self.additionalRenderHook = { (renderer, renderingOutput) in
                if output.data.output == renderingOutput.data.output {
                    neonRenderer.render(on: renderingOutput, with: renderer)
                }
            }
        }
    }
}

private func setWithinBounds(_ box: inout wlr_box, x: Int32, y: Int32, maxX: Int32, maxY: Int32) {
    box.x = min(max(x, 0), maxX - box.width)
    box.y = min(max(y, 0), maxY - box.height)
}

private func drawResizeFrame(cairo: OpaquePointer, frame: wlr_box, color: float_rgba) {
    // Clear surface
    cairo_save(cairo)
    cairo_set_source_rgba(cairo, 0, 0, 0, 0)
    cairo_set_operator(cairo, CAIRO_OPERATOR_SOURCE)
    cairo_paint(cairo)
    cairo_restore(cairo)

    // Fill background
    cairo_set_source_rgba(cairo, Double(color.r), Double(color.g), Double(color.b), Double(color.a))
    cairo_rectangle(cairo, Double(frame.x), Double(frame.y), Double(frame.width), Double(frame.height))
    cairo_fill(cairo)

    cairo_set_line_width(cairo, 2.0)

    // Draw grid
    cairo_set_source_rgb(cairo, 1, 1, 1)
    let gridSize: Int32 = 150
    for y in stride(from: frame.y + gridSize, to: frame.y + frame.height, by: Int(gridSize)) {
        cairo_move_to(cairo, Double(frame.x), Double(y))
        cairo_line_to(cairo, Double(frame.x + frame.width), Double(y))
        cairo_stroke(cairo)
    }
    for x in stride(from: frame.x + gridSize, to: frame.x + frame.width, by: Int(gridSize)) {
        cairo_move_to(cairo, Double(x), Double(frame.y))
        cairo_line_to(cairo, Double(x), Double(frame.y + frame.height))
        cairo_stroke(cairo)
    }

    // Outer glow
    cairo_set_source_rgba(cairo, 1, 1, 1, 1)
    cairo_rectangle(cairo, Double(frame.x), Double(frame.y), Double(frame.width), Double(frame.height))
    cairo_stroke(cairo)
}

import Glibc
import Wlroots

/// Executes the given command. The command will run in its own session (i.e. it will not be
/// a child process).
func executeCommand(_ cmd: String) {
    var child = fork()
    if child == 0 {
        // Child
        child = fork()
        if child == 0 {
            // Grandchild
            setsid()
            execl("/bin/sh", "/bin/sh", "-c", cmd)
            // Should never be reached
            _exit(1)
        } else {
            // Terminate child
            _exit(child == -1 ? 1 : 0)
        }
    } else if child != -1 {
        // Wait for child to complete
        var done = false
        while !done {
            var status = pid_t()
            done = withUnsafeMutablePointer(to: &status) {
                waitpid(child, $0, 0) >= 0 || errno != EINTR
            }
        }
    }
}

private func execl(_ path: String, _ args: String...) {
    let cArgV = UnsafeMutableBufferPointer<UnsafeMutablePointer<Int8>?>.allocate(capacity: args.count + 1)
    for (i, value) in args.enumerated() {
        value.withCString { valuePtr in
            cArgV[i] = strdup(valuePtr)
        }
    }
    cArgV[args.count] = nil
    let _ = path.withCString {
        execv($0, cArgV.baseAddress!)
    }
}

extension Awc {
    internal func execute(action: Action) {
        switch action {
        case .execute(let cmd): executeCommand(cmd)
        case .close: self.kill()
        case .configReload: self.reloadConfig()
        case .focusDown: self.modifyAndUpdate { $0.modify { $0.focusDown() } }
        case .focusUp: self.modifyAndUpdate { $0.modify { $0.focusUp() } }
        case .focusPrimary: self.modifyAndUpdate { $0.focusMain() }
        case .focusOutput(let n): self.withOutput(n) { self.execute(action: .view(tag: $0.workspace.tag)) }
        case .swapDown: self.modifyAndUpdate { $0.modify { $0.swapDown() } }
        case .swapUp: self.modifyAndUpdate { $0.modify { $0.swapUp() } }
        case .swapPrimary: self.modifyAndUpdate { $0.modify { $0.swapPrimary() } }
        case .nextLayout:
            let layout =  self.viewSet.current.workspace.layout
            let nextLayout = layout.nextLayout() ?? layout.firstLayout()
            self.modifyAndUpdate {
                $0.replace(current: $0.current.copy(workspace: $0.current.workspace.replace(layout: nextLayout)))
            }
        case .moveTo(let tag): self.modifyAndUpdate { $0.shift(tag: tag) }
        case .moveToOutput(let n): self.withOutput(n) { self.execute(action: .moveTo(tag: $0.workspace.tag)) }
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
        if let config = loadConfig() {
            // XXX This doesn't reload everything (e.g. border width)
            self.config = config
            print("[INFO] Reloaded config!")
        } else {
            executeCommand(self.config.generateErrorDisplayCmd(msg: "Reloading config failed :("))
        }
    }
}

// MARK: Mouse actions

extension Awc {
    internal func execute(action: ButtonAction, surface: Surface) {
        switch action {
        case .move: self.setToFloatingAndMove(surface)
        case .resize: self.setToFloatingAndResize(surface)
        }
    }

    private func setToFloatingAndMove(_ surface: Surface) {
        self.modifyAndUpdate {
            if let output = $0.findOutput(view: surface) {
                var box = $0.floating[surface] ?? surface.preferredFloatingBox(awc: self, output: output)
                let startBox = box

                let startX = self.cursor.pointee.x
                let startY = self.cursor.pointee.y
                self.dragging = { (time, x, y) in
                    setWithinBounds(
                        &box,
                        x: startBox.x + Int32(x - startX),
                        y: startBox.y + Int32(y - startY),
                        bounds: output.data.box
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
}

private func setWithinBounds(_ box: inout wlr_box, x: Int32, y: Int32, bounds: wlr_box) {
    box.x = min(max(x, bounds.x), bounds.x + bounds.width - box.width)
    box.y = min(max(y, bounds.y), bounds.y + bounds.height - box.height)
}

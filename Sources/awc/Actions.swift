import Glibc
import Foundation
import Logging

import Libawc
import Wlroots

fileprivate let logger = Logger(label: "Actions")

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
                logger.warning("Could not execute '\(cmd)': \(error)")
            }
        case .expand: self.modifyAndUpdate { $0.replace(layout: $0.current.workspace.layout.expand()) }
        case .close: self.kill()
        case .configReload: self.reloadConfig()
        case .focus(let nth): self.modifyAndUpdate { $0.modify { 
            // N.B. nth is 1-indexed
            $0.focus(nth: nth - 1)
        } }
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
        case .assignScratchpad: self.assignFocusAsScratchpad()
        case .toggleScratchpad: self.toggleScratchpad()
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
            self.defaultLayout = layout
            self.modifyAndUpdate { viewSet in
                viewSet.replace(
                    current: viewSet.current.copy(workspace: viewSet.current.workspace.replace(layout: layout)),
                    visible: viewSet.visible.map { $0.copy(workspace: $0.workspace.replace(layout: layout)) },
                    hidden: viewSet.hidden.map { $0.replace(layout: layout) }
                )
            }
            logger.info("Reloaded config!")
        } else {
            do {
                try executeCommand(self.config.generateErrorDisplayCmd(msg: "Reloading config failed :("))
            } catch {
                logger.warning("Could not display error message: \(error)")
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
}

private func setWithinBounds(_ box: inout wlr_box, x: Int32, y: Int32, maxX: Int32, maxY: Int32) {
    box.x = min(max(x, 0), maxX - box.width)
    box.y = min(max(y, 0), maxY - box.height)
}

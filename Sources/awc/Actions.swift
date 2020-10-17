import Glibc

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

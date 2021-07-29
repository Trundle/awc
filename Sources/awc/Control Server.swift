import Foundation
import Glibc

import Libawc
import Wlroots


fileprivate struct EventMask: OptionSet, Hashable {
    let rawValue: UInt32

    static let error = EventMask(rawValue: UInt32(WL_EVENT_ERROR))
    static let hangup = EventMask(rawValue: UInt32(WL_EVENT_HANGUP))
}


fileprivate enum CtlError: Error {
    case syscallError(String)
    case missingEnvVar(String)
    case pathTooLong
}


class CtlClient {
    private static let BUFFER_SIZE = 1 * 1024 * 1024
    private static let ENCODER = JSONEncoder()

    private weak var server: CtlServer?
    private let fd: Int32
    private let buffer: UnsafeMutablePointer<Int8>
    private let decoder = CtlProtocolDecoder()
    private var dataToWrite: ArraySlice<UInt8> = ArraySlice()
    private var writableEventSource: OpaquePointer? = nil

    init(server: CtlServer, fd: Int32) {
        self.server = server
        self.fd = fd
        self.buffer = UnsafeMutablePointer<Int8>.allocate(capacity: CtlClient.BUFFER_SIZE)
    }

    func write<T: Encodable>(response: T) throws {
        let data = try CtlClient.ENCODER.encode(response)
        var size = UInt32(data.count)
        withUnsafeMutablePointer(to: &size) {
            $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<UInt32>.size) {
                write(buffer: UnsafeBufferPointer(start: $0, count: MemoryLayout<UInt32>.size))
            }
        }
        data.withUnsafeBytes {
            write(buffer: $0.bindMemory(to: UInt8.self))
        }
    }

    private func write(buffer: UnsafeBufferPointer<UInt8>) {
        self.dataToWrite.insert(contentsOf: buffer, at: self.dataToWrite.endIndex)
        if let server = self.server {
            if self.writableEventSource == nil {
                self.writableEventSource = wl_event_loop_add_fd(
                    server.eventLoop, 
                    self.fd, 
                    UInt32(WL_EVENT_WRITABLE), 
                    handleClientWriteable,
                    Unmanaged.passUnretained(self).toOpaque())
            }
        }
    }
}

extension CtlClient {
    fileprivate func handleRead(mask: UInt32) {
        let events = EventMask(rawValue: mask)
        guard !events.contains(.error) && !events.contains(.hangup) else {
            self.server?.disconnect(client: self)
            return
        }

        var bytesRead = 0
        repeat {
            bytesRead = recv(self.fd, self.buffer, CtlClient.BUFFER_SIZE, 0)
        } while bytesRead < 0 && errno == EINTR
        if bytesRead >= 0 {
            do {
                for request in try decoder.pushBytes(bytes: self.buffer, count: bytesRead) {
                    self.server?.handle(request: request, from: self)
                }
            } catch {
                self.server?.disconnect(client: self)
            }
        } else {
            self.server?.disconnect(client: self)
        }
    }

    fileprivate func handleWriteable(mask: UInt32) {        
        let events = EventMask(rawValue: mask)
        guard !events.contains(.error) && !events.contains(.hangup) else {
            self.server?.disconnect(client: self)
            return
        }

        var bytesWritten = 0
        repeat {
            bytesWritten = self.dataToWrite.withUnsafeBytes {
                Glibc.write(self.fd, $0.baseAddress, self.dataToWrite.count)
            }
        } while bytesWritten < 0 && errno == EINTR

        if bytesWritten > 0 {
            self.dataToWrite = self.dataToWrite.dropFirst(bytesWritten)
            if self.dataToWrite.isEmpty {
                wl_event_source_remove(self.writableEventSource)
                self.writableEventSource = nil
                self.dataToWrite = ArraySlice()
            }
        }
    }
}

extension CtlClient: Hashable {
    static func ==(lhs: CtlClient, rhs: CtlClient) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.fd)
    }
}


class CtlServer {
    fileprivate let eventLoop: OpaquePointer
    private let path: String
    private let fd: Int32
    private let sockaddr: UnsafeMutablePointer<sockaddr_un>
    private let requestHandler: (CtlClient, CtlRequest) throws -> ()
    private var clients: [CtlClient: OpaquePointer] = [:]
    var eventSource: OpaquePointer? = nil

    init(
        eventLoop: OpaquePointer, 
        path: String,
        fd: Int32, 
        sockaddr: UnsafeMutablePointer<sockaddr_un>,
        requestHandler: @escaping (CtlClient, CtlRequest) throws -> ()
    ) {
        self.eventLoop = eventLoop
        self.path = path
        self.fd = fd
        self.sockaddr = sockaddr
        self.requestHandler = requestHandler
    }

    deinit {
        self.sockaddr.deallocate()
    }

    func handle(request: CtlRequest, from client: CtlClient) {
        do {
            try self.requestHandler(client, request)
        } catch {
            disconnect(client: client)
        }
    }

    func stop() {
        if let eventSource = self.eventSource {
            wl_event_source_remove(eventSource)
        }
        close(self.fd)
        unlink(self.path)
    }

    fileprivate func handleConnect() throws {
        let clientFd = accept(self.fd, nil, nil)
        if clientFd < 0 {
            throw CtlError.syscallError("accept(): \(errno)")
        }
        try setNonblocking(fd: clientFd)
        let client = CtlClient(server: self, fd: clientFd)
        let eventSource = wl_event_loop_add_fd(
            self.eventLoop, clientFd, UInt32(WL_EVENT_READABLE), handleClientRead, 
            Unmanaged.passUnretained(client).toOpaque())
        self.clients[client] = eventSource!
    }

    fileprivate func disconnect(client: CtlClient) {
        if let eventSource = self.clients.removeValue(forKey: client) {
            wl_event_source_remove(eventSource)
        }
    }
}

fileprivate func setCloexec(fd: Int32) throws {
    let flags = fcntl(fd, F_GETFD)
    if flags < 0 {
        throw CtlError.syscallError("fcntl(): \(errno)")
    }
    if fcntl(fd, F_SETFD, flags | FD_CLOEXEC) < 0 {
        throw CtlError.syscallError("fcntl(): \(errno)")
    }
}

fileprivate func setNonblocking(fd: Int32) throws {
    let flags = fcntl(fd, F_GETFL)
    if flags < 0 {
        throw CtlError.syscallError("fcntl(): \(errno)")
    }
    if fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0 {
        throw CtlError.syscallError("fcntl(): \(errno)")
    }
}

fileprivate func handleConnect(fd: CInt, mask: UInt32, data: UnsafeMutableRawPointer?) -> CInt {
    let server: CtlServer = Unmanaged.fromOpaque(data!).takeUnretainedValue()
    try? server.handleConnect()
    return 0
}

fileprivate func handleClientRead(fd: CInt, mask: UInt32, data: UnsafeMutableRawPointer?) -> CInt {
    let client: CtlClient = Unmanaged.fromOpaque(data!).takeUnretainedValue()
    client.handleRead(mask: mask)
    return 0
}

fileprivate func handleClientWriteable(fd: CInt, mask: UInt32, data: UnsafeMutableRawPointer?) -> CInt {
    let client: CtlClient = Unmanaged.fromOpaque(data!).takeUnretainedValue()
    client.handleWriteable(mask: mask)
    return 0
}


func createRequestHandler<L: Layout>(awc: Awc<L>) -> (CtlClient, CtlRequest) throws -> () {
    { (client, request) in
        switch request {
        case .listLayouts:
            var layouts: [String] = []
            var currentLayout: L? = awc.defaultLayout
            while currentLayout != nil {
                layouts.append(currentLayout!.description)
                currentLayout = currentLayout!.nextLayout()
            }
            try client.write(response: layouts)
        case .setLayout(let layoutNumber):
            var currentLayout: L? = awc.defaultLayout
            for _ in 0..<layoutNumber {
                currentLayout = currentLayout?.nextLayout()
            }
            if let newLayout = currentLayout {
                awc.modifyAndUpdate {
                    $0.replace(layout: newLayout)
                }
            }
            try client.write(response: "ok")
        }
    }
}


func setUpCtlListeningSocket<L: Layout>(awc: Awc<L>) throws -> CtlServer {
    let sock = socket(AF_UNIX, CInt(SOCK_STREAM.rawValue), 0)
    if sock < 0 {
        throw CtlError.syscallError("socket(): \(errno)")
    }

    try setCloexec(fd: sock)
    try setNonblocking(fd: sock)

    guard let runtimeDir = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"] else {
        // XDG Base Directory Specification says to fall back, but oh well
        throw CtlError.missingEnvVar("Environment variable XDG_RUNTIME_DIR not set")
    }

    let addr = UnsafeMutablePointer<sockaddr_un>.allocate(capacity: 1)
    addr.pointee.sun_family = sa_family_t(AF_UNIX)
    let path = "\(runtimeDir)/awcctl.\(getuid()).\(getpid()).sock"
    let path_max_size = MemoryLayout.size(ofValue: addr.pointee.sun_path)
    if path.count >= path_max_size {
        throw CtlError.pathTooLong
    }
    withUnsafeMutablePointer(to: &addr.pointee.sun_path) {
        $0.withMemoryRebound(to: Int8.self, capacity: path_max_size) {
            _ = strncpy($0, path, path_max_size)
            $0[path_max_size - 1] = 0
        }
    }

    unlink(path)
    let bindResult = withUnsafeMutablePointer(to: &addr.pointee) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.stride))
        }
    }
    if bindResult < 0 {
        throw CtlError.syscallError("bind(): \(errno)")
    }

    if listen(sock, 8) < 0 {
        throw CtlError.syscallError("listen(): \(errno)")
    }

    let eventLoop = wl_display_get_event_loop(awc.wlDisplay)
    let server = CtlServer(
        eventLoop: eventLoop!, path: path, fd: sock, sockaddr: addr, requestHandler: createRequestHandler(awc: awc))
    let eventSource = wl_event_loop_add_fd(
        eventLoop, sock, UInt32(WL_EVENT_READABLE), handleConnect, 
        Unmanaged.passUnretained(server).toOpaque())
    server.eventSource = eventSource

    setenv("AWCSOCK", path, 1)

    return server
}

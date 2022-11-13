import Foundation
import Glibc

import ControlProtocol

fileprivate enum IpcError: Error {
    case syscallError(String)
    case missingEnvVar(String)
    case pathTooLong
}

fileprivate func connectToAwcSock(path: String) throws -> Int32 {
    let addr = UnsafeMutablePointer<sockaddr_un>.allocate(capacity: 1)
    defer {
        addr.deallocate()
    }

    addr.pointee.sun_family = sa_family_t(AF_UNIX)
    let pathMaxSize = MemoryLayout.size(ofValue: addr.pointee.sun_path)
    if path.count >= pathMaxSize {
        throw IpcError.pathTooLong
    }
    withUnsafeMutablePointer(to: &addr.pointee.sun_path) {
        $0.withMemoryRebound(to: Int8.self, capacity: pathMaxSize) {
            _ = strncpy($0, path, pathMaxSize)
            $0[pathMaxSize - 1] = 0
        }
    }

    let sock = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
    let result = addr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
    guard result >= 0 else {
        let err = errno
        close(sock)
        throw IpcError.syscallError("connect(): \(err)")
    }

    return sock
}

struct AwcView: Decodable, Equatable {
    let title: String
    let focus: Bool
}

struct AwcWorkspace: Decodable, Equatable {
    let tag: String
    let views: [AwcView]
}

struct AwcOutput: Decodable {
    let name: String
    let workspace: AwcWorkspace
}

func getAwcOutputs() throws -> [AwcOutput] {
    guard let sockPath = ProcessInfo.processInfo.environment["AWCSOCK"] else {
        throw IpcError.missingEnvVar("Environment variable AWCSOCK not set")
    }
    let sock = try connectToAwcSock(path: sockPath)
    defer {
        close(sock)
    }

    let encoder = JSONEncoder()
    let request = try encoder.encode(CtlRequest.listOutputs)
    sendSize(sock: sock, size: request.count)
    request.withUnsafeBytes {
        let bytesSent = send(sock, $0.baseAddress, request.count, 0)
        assert(bytesSent == request.count)
    }

    let protocolDecoder = ControlProtocol.CtlProtocolDecoder()
    let buffer = UnsafeMutableBufferPointer<CChar>.allocate(capacity: 1 * 1024 * 1024)
    defer {
        buffer.deallocate()
    }
    var bytesRead = 0
    var responses: [[AwcOutput]]
    repeat {
        bytesRead = recv(sock, buffer.baseAddress, buffer.count, 0)   
        responses = try protocolDecoder.pushBytes(bytes: buffer.baseAddress!, count: bytesRead)
    } while (bytesRead > 0 || errno == EINTR) && responses.isEmpty

    assert(responses.count == 1)
    return responses[0]
}

fileprivate func sendSize(sock: Int32, size: Int) {
    var data = UInt32(size)
    let bytesSent = send(sock, &data, MemoryLayout<UInt32>.size, 0)
    assert(bytesSent == MemoryLayout<UInt32>.size)
}

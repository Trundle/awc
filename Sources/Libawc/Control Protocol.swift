import Foundation
import Wlroots


public enum CtlRequest: Decodable, Equatable {
    case listLayouts
    case listWorkspaces
    case newWorkspace(String)
    case renameWorkspace(String, String)
    case setLayout(UInt8)

    private enum Keys: String, CodingKey {
        case cmd
        case layoutNumber = "layout_number"
        case newTag = "new_tag"
        case tag
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let cmd = try container.decode(String.self, forKey: .cmd)

        switch cmd {
        case "list_layouts": self = .listLayouts
        case "list_workspaces": self = .listWorkspaces
        case "new_workspace":
            let tag = try container.decode(String.self, forKey: .tag)
            self = .newWorkspace(tag)
        case "rename_workspace":
            let tag = try container.decode(String.self, forKey: .tag)
            let newTag = try container.decode(String.self, forKey: .newTag)
            self = .renameWorkspace(tag, newTag)
        case "set_layout":
            let layout = try container.decode(UInt8.self, forKey: .layoutNumber)
            self = .setLayout(layout)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid command \(cmd)"
                )
            )
        }
    }
}


fileprivate protocol DecoderState {
    func pushBytes(bytes: UnsafePointer<Int8>, count: UInt) throws -> (DecoderState, UInt, CtlRequest?)
}

/// Initial state: decodes the message if enough data and then switches to `ReadMsgDataState`.
fileprivate class InitialState: DecoderState {
    func pushBytes(bytes: UnsafePointer<Int8>, count: UInt) -> (DecoderState, UInt, CtlRequest?) {
        if count >= MemoryLayout<UInt32>.size {
            let size = bytes.withMemoryRebound(to: UInt32.self, capacity: 1) {
                $0.pointee
            }
            return (ReadMsgDataState(size: size), UInt(MemoryLayout<UInt32>.size), nil)
        } else {
            let copiedBytes = Array(UnsafeBufferPointer(start: bytes, count: Int(count)))
            return (PartialSizeReadState(bytes: copiedBytes), count, nil)
        }
    }
}

fileprivate class PartialSizeReadState: DecoderState {
    private let previousBytes: [Int8]

    init(bytes: [Int8]) {
        self.previousBytes = bytes
    }

    func pushBytes(bytes: UnsafePointer<Int8>, count: UInt) -> (DecoderState, UInt, CtlRequest?) {
        let stillWanted = MemoryLayout<UInt32>.size - previousBytes.count
        if Int(count) >= stillWanted {
            var data = self.previousBytes + Array(UnsafeBufferPointer(start: bytes, count: stillWanted))
            let size = withUnsafePointer(to: &data[0]) {
                $0.withMemoryRebound(to: UInt32.self, capacity: 1) {
                    $0.pointee
                }
            }
            return (ReadMsgDataState(size: size), UInt(stillWanted), nil)
        } else {
            let copiedBytes = Array(UnsafeBufferPointer(start: bytes, count: Int(count)))
            return (PartialSizeReadState(bytes: previousBytes + copiedBytes), count, nil)
        }
    }
}

fileprivate class ReadMsgDataState: DecoderState {
    private static let jsonDecoder = JSONDecoder()

    private let size: UInt
    private var data: [Int8] = []

    init(size: UInt32) {
        self.size = UInt(size)
        self.data.reserveCapacity(Int(size))
    }

    func pushBytes(bytes: UnsafePointer<Int8>, count: UInt) throws -> (DecoderState, UInt, CtlRequest?) {
        let stillWanted = min(self.size - UInt(data.count), count)
        data.insert(contentsOf: UnsafeBufferPointer(start: bytes, count: Int(stillWanted)), at: data.endIndex)
        if data.count >= Int(size) {
            let request = try data.withUnsafeBytes {
                try ReadMsgDataState.jsonDecoder.decode(CtlRequest.self, from: Data($0))
            }
            return (InitialState(), stillWanted, request)
        } else {
            return (self, stillWanted, nil)
        }
    }
}


public class CtlProtocolDecoder {
    private var state: DecoderState = InitialState()

    public init() {
    }

    public func pushBytes(bytes: UnsafePointer<Int8>, count: Int) throws -> [CtlRequest] {
        var requests: [CtlRequest] = []
        var countRemaining = count
        var currentBytes = bytes
        while countRemaining > 0 {
            let (nextState, bytesProcessed, maybeRequest) =
                try self.state.pushBytes(bytes: currentBytes, count: UInt(countRemaining))
            if let request = maybeRequest {
                requests.append(request)
            }
            currentBytes += Int(bytesProcessed)
            countRemaining -= Int(bytesProcessed)
            self.state = nextState
        }
        return requests
    }
}
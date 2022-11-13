import Foundation

import DataStructures


public enum CtlRequest: Decodable, Equatable {
    case listLayouts
    case listOutputs
    case listWorkspaces
    case newWorkspace(String)
    case renameWorkspace(String, String)
    case setFloating(Box)
    case setLayout(UInt8)

    private enum Keys: String, CodingKey {
        case cmd
        case layoutNumber = "layout_number"
        case newTag = "new_tag"
        case tag
        case x
        case y
        case width
        case height
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let cmd = try container.decode(String.self, forKey: .cmd)

        switch cmd {
        case "list_layouts": self = .listLayouts
        case "list_outputs": self = .listOutputs
        case "list_workspaces": self = .listWorkspaces
        case "new_workspace":
            let tag = try container.decode(String.self, forKey: .tag)
            self = .newWorkspace(tag)
        case "rename_workspace":
            let tag = try container.decode(String.self, forKey: .tag)
            let newTag = try container.decode(String.self, forKey: .newTag)
            self = .renameWorkspace(tag, newTag)
        case "set_floating":
            let x = try container.decode(Int32.self, forKey: .x)
            let y = try container.decode(Int32.self, forKey: .y)
            let width = try container.decode(Int32.self, forKey: .width)
            let height = try container.decode(Int32.self, forKey: .height)
            self = .setFloating(Box(x: x, y: y, width: width, height: height))
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


extension CtlRequest: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)

        switch self {
        case .listLayouts: try container.encode("list_layouts", forKey: .cmd)
        case .listOutputs: try container.encode("list_outputs", forKey: .cmd)
        case .listWorkspaces: try container.encode("list_workspaces", forKey: .cmd)
        case .newWorkspace(let tag):
            try container.encode("new_workspace", forKey: .cmd)
            try container.encode(tag, forKey: .tag)
        case .renameWorkspace(let tag, let newTag):
            try container.encode("rename_workspace", forKey: .cmd)
            try container.encode(tag, forKey: .tag)
            try container.encode(newTag, forKey: .newTag)
        case .setFloating(let box):
            try container.encode("set_floating", forKey: .cmd)
            try container.encode(box.x, forKey: .x)
            try container.encode(box.y, forKey: .y)
            try container.encode(box.width, forKey: .width)
            try container.encode(box.height, forKey: .height)
        case .setLayout(let number):
            try container.encode("set_layout", forKey: .cmd)
            try container.encode(number, forKey: .layoutNumber)
        }
    }
}


fileprivate protocol DecoderState {
    func pushBytes<Msg: Decodable>(bytes: UnsafePointer<Int8>, count: UInt) throws -> (DecoderState, UInt, Msg?)
}

/// Initial state: decodes the message if enough data and then switches to `ReadMsgDataState`.
fileprivate class InitialState: DecoderState {
    func pushBytes<Msg>(bytes: UnsafePointer<Int8>, count: UInt) -> (DecoderState, UInt, Msg?) {
        if count >= MemoryLayout<UInt32>.size {
            let size = UnsafeRawPointer(bytes).bindMemory(to: UInt32.self, capacity: 1).pointee
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

    func pushBytes<Msg>(bytes: UnsafePointer<Int8>, count: UInt) -> (DecoderState, UInt, Msg?) {
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

    func pushBytes<Msg: Decodable>(bytes: UnsafePointer<Int8>, count: UInt) throws -> (DecoderState, UInt, Msg?) {
        let stillWanted = min(self.size - UInt(data.count), count)
        data.insert(contentsOf: UnsafeBufferPointer(start: bytes, count: Int(stillWanted)), at: data.endIndex)
        if data.count >= Int(size) {
            let request = try data.withUnsafeBytes {
                try ReadMsgDataState.jsonDecoder.decode(Msg.self, from: Data($0))
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

    public func pushBytes<Msg: Decodable>(bytes: UnsafePointer<Int8>, count: Int) throws -> [Msg] {
        var requests: [Msg] = []
        var countRemaining = count
        var currentBytes = bytes
        while countRemaining > 0 {
            let (nextState, bytesProcessed, maybeRequest): (DecoderState, UInt, Msg?) =
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
/// This is a (highly) modified version of swift-log's StreamLogHandler (see
/// https://github.com/apple/swift-log/blob/74d7b91ceebc85daf387ebb206003f78813f71aa/Sources/Logging/Logging.swift#L567-L632
/// ), originally released under the Apache License 2.0

import Glibc
import Logging

fileprivate struct AnsiCodes {
    static let reset = "\u{1b}[0m"
    static let boldRed = "\u{1b}[1;31m"
    static let boldYellow = "\u{1b}[1;33m"

    private init() {}
}

class AnsiLogHandler: LogHandler {
    static var logLevelChangedListener: ((Logger.Level) -> ())? = nil

    private let file = stderr
    private let colorize: Bool

    private var prettyMetadata: String?
    public var metadata = Logger.Metadata() {
        didSet {
            self.prettyMetadata = self.prettify(self.metadata)
        }
    }

    public var logLevel: Logger.Level = .info {
        didSet {
            AnsiLogHandler.logLevelChangedListener?(self.logLevel)
        }
    }

    public init(logLevel: Logger.Level) {
        self.colorize = isatty(STDERR_FILENO) != 0
        self.logLevel = logLevel
        AnsiLogHandler.logLevelChangedListener?(logLevel)
    }

    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            return self.metadata[metadataKey]
        }
        set {
            self.metadata[metadataKey] = newValue
        }
    }

    public func log(level: Logger.Level,
                    message: Logger.Message,
                    metadata: Logger.Metadata?,
                    file: String, function: String, line: UInt) {
        let prettyMetadata = metadata?.isEmpty ?? true
            ? self.prettyMetadata
            : self.prettify(self.metadata.merging(metadata!, uniquingKeysWith: { _, new in new }))

        let color: String
        let colorEnd: String
        if self.colorize {
            switch level {
            case .critical, .error: color = AnsiCodes.boldRed
            case .warning: color = AnsiCodes.boldYellow
            default: color = ""
            }
            colorEnd = AnsiCodes.reset
        } else {
            color = ""
            colorEnd = ""
        }
        self.write(
            "\(self.timestamp()) "
            + "\(color)[\(level.rawValue.uppercased())]\(colorEnd) "
            + "\(prettyMetadata.map { " \($0)" } ?? "") "
            + "\(message)\n")
    }

    private func write(_ value: String) {
        flockfile(self.file)
        defer {
            funlockfile(self.file)
        }

        fputs(value, self.file)
    }

    private func timestamp() -> String {
        var buffer = [Int8](repeating: 0, count: 255)
        var timestamp = time(nil)
        let localTime = localtime(&timestamp)
        strftime(&buffer, buffer.count, "%Y-%m-%dT%H:%M:%S%z", localTime)
        return buffer.withUnsafeBufferPointer {
            $0.withMemoryRebound(to: CChar.self) {
                String(cString: $0.baseAddress!)
            }
        }
    }

    private func prettify(_ metadata: Logger.Metadata) -> String? {
        return !metadata.isEmpty ? metadata.map { "\($0)=\($1)" }.joined(separator: " ") : nil
    }
}

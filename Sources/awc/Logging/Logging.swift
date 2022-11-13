import Glibc
import Foundation
import Logging
import LogHandlers

import Wlroots

fileprivate var wlrLogLevel: wlr_log_importance = WLR_INFO
fileprivate let wlrLogger = Logger(label: "wlr")


extension wlr_log_importance: Comparable {
    public static func <(lhs: wlr_log_importance, rhs: wlr_log_importance) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}


fileprivate func wlrLogCallback(
    verbosity: wlr_log_importance,
    fmt: UnsafePointer<CChar>?,
    args: CVaListPointer?)
{
    guard let fmt = fmt, verbosity <= wlrLogLevel, args != nil else {
        return
    }

    let formatted = NSString(format: String(cString: fmt), arguments: args!)
    let msg = Logger.Message(stringLiteral: formatted as String)
    switch verbosity {
    case WLR_DEBUG: wlrLogger.debug(msg)
    case WLR_INFO: wlrLogger.info(msg)
    case WLR_ERROR: wlrLogger.error(msg)
    default: wlrLogger.info(msg)
    }
}


func initLogging(level: Logger.Level) {
    AnsiLogHandler.logLevelChangedListener = {
        switch $0 {
        case .trace, .debug: wlrLogLevel = WLR_DEBUG
        case .info: wlrLogLevel = WLR_INFO
        case .notice, .warning, .error, .critical: wlrLogLevel = WLR_ERROR
        }
    }

    LoggingSystem.bootstrap { _ in AnsiLogHandler(logLevel: level) }
    wlr_log_init(WLR_DEBUG, wlrLogCallback)
}

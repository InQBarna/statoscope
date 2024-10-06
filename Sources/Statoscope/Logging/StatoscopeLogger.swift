//
//  StatoscopeLogger.swift
//  
//
//  Created by Sergi Hernanz on 19/1/24.
//

import Foundation
import OSLog

public enum LogLevel: String, CaseIterable {
    case errors
    case when
    case effects
    case stateDiff
    case state
    case injection
}

extension LogLevel {
    var osLog: OSLogType {
        switch self {
        case .effects: return .debug
        case .errors: return .error
        case .stateDiff: return .debug
        case .state: return .info
        case .when: return .debug
        case .injection: return .debug
        }
    }
}

public extension LogLevel {
    static var basic: Set<LogLevel> = [.errors, .when]
    static var all: Set<LogLevel> = [.errors, .when, .effects, .stateDiff, .injection]
    static var verbose: Set<LogLevel> = [.errors, .when, .effects, .stateDiff, .injection, .state]
}

public struct StatoscopeLogger {

    /// Enable or disable statoscope log with this global variable
    public static var logLevel: Set<LogLevel> = [.errors]

    /// Overwrite statoscope logger method with this global variable
    public static var logReplacement: ((LogLevel, String) -> Void)?
    
    private static var loggers: [LogLevel: OSLog] = Dictionary(uniqueKeysWithValues: LogLevel
        .allCases
        .map {
            ($0, OSLog(subsystem: "com.inqbarna.statoscope", category: $0.rawValue))
        }
    )

    static func LOG(_ level: LogLevel, _ string: String) {
        if let logReplacement {
            logReplacement(level, "\(string)")
        } else if Self.logLevel.contains(level) {
            if #available(iOS 14.0, *), let logger = loggers[level] {
                os_log(level.osLog, log: logger, "\(string)")
            } else {
                print("\(string)")
            }
        }
    }

    static func logEnabled(_ level: LogLevel) -> Bool {
        return logReplacement != nil ||
            Self.logLevel.contains(level)
    }
    
    static func LOG(_ level: LogLevel, prefix: String, describing: Any) {
        let safePrefix = prefix.count == 0 ? "" : prefix + " "
        if let logReplacement {
            logReplacement(level, "\(safePrefix)\(describeObject(describing))")
        } else if Self.logLevel.contains(level) {
            if #available(iOS 14.0, *), let logger = loggers[level] {
                os_log(.debug, log: logger, "\(safePrefix)\(describeObject(describing))")
            } else {
                print("\(safePrefix)\(describeObject(describing))")
            }
        }
    }
    
    static func LOG(_ level: LogLevel, prefix: String, _ string: @autoclosure () -> String) {
        let safePrefix = prefix.count == 0 ? "" : prefix + " "
        if let logReplacement {
            logReplacement(level, "\(safePrefix)\(string())")
        } else if Self.logLevel.contains(level) {
            if #available(iOS 14.0, *), let logger = loggers[level] {
                let stringValue = string()
                os_log(.debug, log: logger, "\(safePrefix)\(stringValue)")
            } else {
                print("\(safePrefix)\(string())")
            }
        }
    }
}

public extension CollectionDifference.Change {
    var offset: Int {
        switch self {
        case .remove(let offset, _, _): return offset
        case .insert(let offset, _, _): return offset
        }
    }
}

extension ScopeImplementation {
    
    func logStateDiff(
        previousDescribingSelf: String,
        newDescribingSelf: String
    ) {
        let differences = newDescribingSelf
            .split(separator: "\n")
            .difference(from: previousDescribingSelf.split(separator: "\n"))
            .sorted { lhs, rhs in
                lhs.offset < rhs.offset
            }
        StatoscopeLogger.LOG(
            .stateDiff,
            "\(type(of: self)) (\(Unmanaged.passUnretained(self).toOpaque())):\n" +
            differences.map { difference in
                switch difference {
                case .remove(_, let element, _):
                    return "- " + element
                case .insert(_, let element, _):
                    return "+ " + element
                }
            }
                .joined(separator: "\n")
        )
    }
}

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
}

extension LogLevel {
    var osLog: OSLogType {
        switch self {
        case .effects: return .debug
        case .errors: return .error
        case .stateDiff: return .debug
        case .state: return .info
        case .when: return .debug
        }
    }
}

public extension LogLevel {
    static var basic: Set<LogLevel> = [.errors, .when]
    static var all: Set<LogLevel> = [.errors, .when, .effects, .stateDiff]
    static var verbose: Set<LogLevel> = [.errors, .when, .effects, .stateDiff, .state]
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

    static func LOG(_ level: LogLevel, prefix: String, describing: Any) {
        if let logReplacement {
            logReplacement(level, "\(prefix) \(describeObject(describing))")
        } else if Self.logLevel.contains(level) {
            if #available(iOS 14.0, *), let logger = loggers[level] {
                os_log(.debug, log: logger, "\(prefix) \(describeObject(describing))")
            } else {
                print("\(prefix) \(describeObject(describing))")
            }
        }
    }
    
    static func LOG(_ level: LogLevel, prefix: String, _ string: String) {
        if let logReplacement {
            logReplacement(level, "\(prefix) \(string)")
        } else if Self.logLevel.contains(level) {
            if #available(iOS 14.0, *), let logger = loggers[level] {
                os_log(.debug, log: logger, "\(prefix) \(string)")
            } else {
                print("\(prefix) \(string)")
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
    func logState(describingSelf: String) {
        LOG(.state, describingSelf)
    }
    
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

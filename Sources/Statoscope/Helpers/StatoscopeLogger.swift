//
//  StatoscopeLogger.swift
//  
//
//  Created by Sergi Hernanz on 19/1/24.
//

import Foundation

public enum LogLevel {
    case errors
    case when
    case effects
    case stateDiff
    case state
}

public extension LogLevel {
    static var basic: Set<LogLevel> = Set(arrayLiteral: .errors, .when)
    static var all: Set<LogLevel> = Set(arrayLiteral: .errors, .when, .effects, .stateDiff)
    static var verbose: Set<LogLevel> = Set(arrayLiteral: .errors, .when, .effects, .stateDiff, .state)
}

public struct StatoscopeLogger {

    /// Enable or disable statoscope log with this global variable
    public static var logLevel: Set<LogLevel> = Set(arrayLiteral: .errors)

    /// Overwrite statoscope logger method with this global variable
    public static var logReplacement: ((LogLevel, String) -> Void)?

    static func LOG(_ level: LogLevel, _ string: String) {
        if Self.logLevel.contains(level) {
            print("[SCOPE]: \(string)")
        }
    }

    static func LOG(_ level: LogLevel, prefix: String, _ string: String) {
        if let logReplacement {
            logReplacement(level, "[SCOPE]: \(prefix) \(string)")
        } else if Self.logLevel.contains(level) {
            print("[SCOPE]: \(prefix) \(string)")
        }
    }
}

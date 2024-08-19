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
    static var basic: Set<LogLevel> = [.errors, .when]
    static var all: Set<LogLevel> = [.errors, .when, .effects, .stateDiff]
    static var verbose: Set<LogLevel> = [.errors, .when, .effects, .stateDiff, .state]
}

public struct StatoscopeLogger {

    /// Enable or disable statoscope log with this global variable
    public static var logLevel: Set<LogLevel> = [.errors]

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
        for stateLine in describingSelf.split(separator: "\n") {
            LOG(.state, "[STATE] " + stateLine)
        }
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
        for difference in differences {
            switch difference {
            case .remove(_, let element, _):
                LOG(.stateDiff, "[STATE] [DIFF] - " + element)
            case .insert(_, let element, _):
                LOG(.stateDiff, "[STATE] [DIFF] + " + element)
            }
        }
    }
}

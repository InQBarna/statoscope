//
//  StatoscopeLogger.swift
//  
//
//  Created by Sergi Hernanz on 19/1/24.
//

import Foundation

public struct StatoscopeLogger {

    /// Enable or disable statoscope log with this global variable
    public static var logEnabled: Bool = false

    static func LOG(_ string: String) {
        if Self.logEnabled {
            print("[SCOPE]: \(string)")
        }
    }

    static func LOG(prefix: String, _ string: String) {
        if Self.logEnabled {
            print("[SCOPE]: \(prefix) \(string)")
        }
    }
}

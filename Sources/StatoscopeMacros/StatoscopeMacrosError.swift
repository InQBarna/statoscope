//
//  StatoscopeMacroError.swift
//  
//
//  Created by Sergi Hernanz on 16/3/24.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

public enum StatoscopeMacroError: Error {
    case message(String)
}

enum StatoscopeMacroDiagnostic: DiagnosticMessage {
    case notAStruct
    case notAnEnum
    case propertyTypeProblem(PatternBindingListSyntax.Element)

    var severity: DiagnosticSeverity {
        switch self {
        case .notAStruct: .error
        case .notAnEnum: .error
        case .propertyTypeProblem: .warning
        }
    }

    var message: String {
        switch self {
        case .notAStruct:
            "'Can only be applied to a 'struct'"
        case .notAnEnum:
            "'Can only be applied to an 'enum'"
        case .propertyTypeProblem(let binding):
            "Type error for property '\(binding.pattern)': \(binding)"
        }
    }

    var diagnosticID: MessageID {
        switch self {
        case .notAStruct:
            .init(domain: "StatoscopeMacros", id: "notAStruct")
        case .notAnEnum:
            .init(domain: "StatoscopeMacros", id: "notAnEnum")
        case .propertyTypeProblem(let binding):
            .init(domain: "StatoscopeMacros", id: "propertyTypeProblem(\(binding.pattern))")
        }
    }
}

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
    case subStateNotOptional
    case superStateNoTypeAnnotation
    case reducerMissingStateStruct
    case reducerMissingWhenEnum

    var severity: DiagnosticSeverity {
        switch self {
        case .notAStruct: .error
        case .notAnEnum: .error
        case .propertyTypeProblem: .warning
        case .subStateNotOptional: .error
        case .superStateNoTypeAnnotation: .error
        case .reducerMissingStateStruct: .error
        case .reducerMissingWhenEnum: .error
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
        case .subStateNotOptional:
            "@SubState properties must be optional. Use: @SubState var child: ChildState?"
        case .superStateNoTypeAnnotation:
            "@SuperState requires explicit type annotation. Use: @SuperState var parent: ParentState"
        case .reducerMissingStateStruct:
            "@Reducer requires a nested 'struct State' definition"
        case .reducerMissingWhenEnum:
            "@Reducer requires a nested 'enum When' definition"
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
        case .subStateNotOptional:
            .init(domain: "StatoscopeMacros", id: "subStateNotOptional")
        case .superStateNoTypeAnnotation:
            .init(domain: "StatoscopeMacros", id: "superStateNoTypeAnnotation")
        case .reducerMissingStateStruct:
            .init(domain: "StatoscopeMacros", id: "reducerMissingStateStruct")
        case .reducerMissingWhenEnum:
            .init(domain: "StatoscopeMacros", id: "reducerMissingWhenEnum")
        }
    }
}

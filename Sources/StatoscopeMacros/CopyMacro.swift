//
//  CopyMacro.swift
//  Views
//
//  Created by Sergi Hernanz on 27/12/24.
//

import SwiftCompilerPlugin
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

extension DeclModifierListSyntax {
    private static let visibilityModifiers: Set = ["private", "fileprivate", "internal", "package", "public", "open"]

    func visibilityText() -> String? {
        self.map(\.name.text)
            .first(where: { Self.visibilityModifiers.contains($0) })
    }
}

private func accessorIsAllowed(_ accessor: AccessorBlockSyntax.Accessors?) -> Bool {
    guard let accessor else { return true }
    return switch accessor {
    case .accessors(let accessorDeclListSyntax):
        !accessorDeclListSyntax.contains {
            $0.accessorSpecifier.text == "get" || $0.accessorSpecifier.text == "set"
        }
    case .getter:
        false
    }
}

private extension Array {
    var combinationsWithoutRepetition: [[Element]] {
        guard !isEmpty else { return [[]] }
        return Array(self[1...]).combinationsWithoutRepetition.flatMap { [$0, [self[0]] + $0] }
    }
}

public struct CopyMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {

        guard let structDeclSyntax = declaration as? StructDeclSyntax else {
            let diagnostic = Diagnostic(node: Syntax(node), message: StatoscopeMacroDiagnostic.notAStruct)
            context.diagnose(diagnostic)
            return []
        }
        let structVisibility = structDeclSyntax.modifiers.visibilityText() ?? "public"
        let variables = structDeclSyntax.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }
        let bindings = variables.flatMap(\.bindings).filter { accessorIsAllowed($0.accessorBlock?.accessors) }
        let parameterListString = bindings.map { binding in
            if binding.typeAnnotation?.type.as(OptionalTypeSyntax.self) != nil {
                "\(binding.pattern): \(binding.typeAnnotation?.type.trimmed ?? "")? = .some(nil)"
            } else {
                "\(binding.pattern): \(binding.typeAnnotation?.type.trimmed ?? "")? = nil"
            }
        }.joined(separator: ",\n")
        let constructorString = bindings.compactMap { binding in
            let pattern = binding.pattern
            if binding.typeAnnotation?.type.as(OptionalTypeSyntax.self) != nil {
                guard let annotation = binding.typeAnnotation?.type.as(OptionalTypeSyntax.self) else {
                    return ""
                }
                 return "\(pattern): (\(pattern) == .some(nil) ? self.\(pattern) : \(pattern) as? \(annotation.wrappedType.trimmed))"
            } else {
                return "\(pattern): \(pattern) ?? self.\(pattern)"
            }
        }.joined(separator: ",\n")
        return ["""
        \(raw: structVisibility) func copy(
            \(raw: parameterListString)
        ) -> Self {
            .init(
                \(raw: constructorString)
            )
        }
        """]
    }
}
